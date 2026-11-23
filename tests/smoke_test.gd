extends SceneTree
## Headless smoke test:  godot --headless -s tests/smoke_test.gd
## Checks layout generation, then plays the real main scene through
## `controls.override`. Exits non-zero on any failed assertion.

const Layout = preload("res://scripts/layout.gd")
const Enemy = preload("res://scripts/enemy.gd")

var fails := 0
var main
var c


func _initialize() -> void:
	_run()


## Watchdog: a script error inside the coroutine would otherwise hang forever.
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > 90000:
		print("== TIMED OUT ==")
		quit(1)
	return false


func ok(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _pick(kinds: Array):
	for e in main.world.enemy_list:
		if kinds.has(e.kind) and not e.dead and e.state != Enemy.DOWN:
			return e
	return null


## Zombies drawn by noise (sight puts them in CHASE instead).
func _awake() -> int:
	var n := 0
	for e in main.world.enemy_list:
		if e.state == Enemy.INVESTIGATE:
			n += 1
	return n


## Teleports a grabbing zombie onto the player and waits for the grab.
func _get_grabbed():
	var p = main.player
	var e = _pick(["shambler", "runner"])
	e.global_position = p.global_position + Vector2(9, 0)
	e.alert()
	for i in 40:
		await physics_frame
		if p.grab_t > 0.0:
			break
	return e


func _run() -> void:
	print("== layout ==")
	ok(Layout.validate(), "all chunks are %dx%d" % [Layout.CW, Layout.CH])
	for s in [1989, 1990, 1, 2, 3, 42, 777, 123456]:
		var L := Layout.generate(s)
		var reach := Layout.reachable(L)
		var good: bool = L.sig == Layout.generate(s).sig
		for z in L.zombies:
			good = good and reach.has(z.cell)
		for p in L.pickups:
			good = good and reach.has(p.cell)
		for e in L.exits:
			good = good and reach.has(e)
		var kinds := {}
		for z in L.zombies:
			kinds[z.kind] = true
		good = good and kinds.size() == 3 and L.exits.size() > 0 and L.pickups.size() >= 2
		ok(good, "seed %d: deterministic, connected, %d zombies, %d doors" % [s, L.zombies.size(), L.doors.size()])
	ok(Layout.generate(1).sig != Layout.generate(2).sig, "different seeds differ")

	print("== game ==")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	c = main.controls
	c.override = true
	c.touch_mode = false
	var p = main.player
	var w = main.world
	ok(p != null and p.alive, "player spawned")
	ok(w.enemy_list.size() >= 15, "zombies spawned (%d)" % w.enemy_list.size())
	ok(w.doors.size() >= 12 and w.glass.size() > 0, "doors (%d) and glass (%d) built" % [w.doors.size(), w.glass.size()])

	var p0: Vector2 = p.global_position
	c.move = Vector2.RIGHT
	await frames(20)
	c.move = Vector2.ZERO
	ok(p.global_position.x - p0.x > 20.0, "player moves")
	p0 = p.global_position
	c.q.dash = true
	await frames(10)
	ok(p.global_position.distance_to(p0) > 30.0, "dash covers ground")

	# Silent pipe vs loud pistol. (Immune to grabs so wandering zombies that
	# spot the player through a window cannot end this part early.)
	p.grab_immune = 99.0
	var awake := _awake()
	c.aim = Vector2.RIGHT
	c.fire = true
	await frames(6)
	c.fire = false
	ok(_awake() == awake, "pipe swing is silent")
	await frames(25)
	p.give("pistol")
	var rounds: int = p.ammo.pistol
	c.fire = true
	await frames(3)
	c.fire = false
	ok(p.ammo.pistol < rounds, "pistol consumes ammo")
	ok(_awake() > awake, "gunshot alerts zombies in other rooms (%d woke)" % (_awake() - awake))

	# Shoot one dead.
	var e = _pick(["shambler"])
	e.global_position = p.global_position + Vector2(40, 0)
	c.fire = true
	await frames(15)
	c.fire = false
	ok(main.kills >= 1 and main.combo >= 1, "pistol kills, combo starts")
	ok(w.fx.decal_count() > 5, "blood/casings persist (%d decals)" % w.fx.decal_count())

	# Grab with no response -> death after the escape window.
	p.grab_immune = 0.0
	await _get_grabbed()
	ok(p.grab_t > 0.0 and p.alive, "zombie grabs player")
	var t := 0
	while p.alive and t < 60:
		await physics_frame
		t += 1
	ok(not p.alive and main.state == "dead", "unanswered grab kills (~%.2fs)" % (t / 60.0))
	ok(t >= 18 and t <= 30, "escape window is about 0.4s")

	# Instant restart on the same seed.
	var sig: String = w.L.sig
	var seed_before: int = main.floor_seed
	c.q.any = true
	await frames(3)
	p = main.player
	w = main.world
	ok(main.state == "play" and p.alive, "restart on input")
	ok(main.floor_seed == seed_before and w.L.sig == sig, "restart keeps the same floor seed/layout")
	ok(main.restart_usec < 200000, "restart took %.1f ms (< 200 ms)" % (main.restart_usec / 1000.0))
	ok(w.fx.decal_count() == 0 and main.score == 0, "restart resets the floor")

	# Grab -> kick breaks free -> execute the downed zombie.
	e = await _get_grabbed()
	ok(p.grab_t > 0.0, "grabbed again")
	c.q.kick = true
	await frames(3)
	ok(p.alive and p.grab_t <= 0.0, "kick breaks the grab")
	ok(e.is_down(), "grabber is knocked down")
	await frames(22)
	e.global_position = p.global_position + Vector2(12, 0)
	ok(p.context() == "EXEC", "action button becomes EXEC near a downed zombie")
	var k: int = main.kills
	c.q.kick = true
	await frames(3)
	ok(main.kills == k + 1, "execution kills")
	ok(p.context() == "KICK", "action button returns to KICK")

	# Kick a door open.
	var di := -1
	for i in w.doors.size():
		if not w.doors[i].locked and not w.doors[i].open:
			di = i
			break
	var d: Dictionary = w.doors[di]
	var n := Vector2.RIGHT if d.vertical else Vector2.DOWN
	p.global_position = d.center - n * 13.0
	c.aim = n
	await frames(25)
	ok(not w.los(p.global_position, d.center + n * 13.0), "closed door blocks sight")
	c.q.kick = true
	await frames(3)
	ok(d.open and w.los(p.global_position, d.center + n * 13.0), "kick opens the door")

	# Shoot out a window.
	var gc := Vector2i(-1, -1)
	for cell in w.glass:
		if w.code_at(cell + Vector2i(-1, 0)) == Layout.FLOOR:
			gc = cell
			break
	p.global_position = w.center(gc + Vector2i(-1, 0))
	c.aim = Vector2.RIGHT
	p.give("pistol")
	await frames(2)
	c.fire = true
	await frames(4)
	c.fire = false
	ok(not w.glass.has(gc), "bullets break glass")

	# Bloater detonates and the floor can be cleared.
	p.global_position = w.center(w.L.start)
	p.grab_immune = 99.0
	var b = _pick(["bloater"])
	b.hit(99, Vector2.RIGHT)
	ok(b.state == Enemy.FUSE, "bloater swells instead of dropping")
	await frames(40)
	ok(not is_instance_valid(b) or b.dead, "bloater explodes")
	for i in 6:
		for z in w.enemy_list.duplicate():
			z.hit(99, Vector2.RIGHT)
		await frames(35)
		if w.enemy_list.is_empty():
			break
	ok(w.enemy_list.is_empty() and w.exit_open, "killing everything opens the elevator")
	ok(p.alive, "player survived the cleanup")
	p.global_position = w.exit_rect.get_center()
	await frames(3)
	ok(main.state == "clear", "reaching the elevator clears the floor")
	await frames(50)
	c.q.any = true
	await frames(3)
	ok(main.floor_seed == seed_before + 1 and main.state == "play", "next floor uses the next seed")

	print("== %s ==" % ("PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
