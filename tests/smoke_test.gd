extends SceneTree
## Headless smoke test:  godot --headless -s tests/smoke_test.gd
## Checks layout generation, then plays the real main scene through
## `controls.override`. Exits non-zero on any failed assertion.

const Layout = preload("res://scripts/layout.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Fx = preload("res://scripts/fx.gd")

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
		good = good and kinds.size() == 4 and L.exits.size() > 0 and L.pickups.size() >= 2
		ok(good, "seed %d: deterministic, connected, %d zombies, %d doors" % [s, L.zombies.size(), L.doors.size()])
	ok(Layout.generate(1).sig != Layout.generate(2).sig, "different seeds differ")

	print("== ui layout ==")
	var Hud = load("res://scripts/hud.gd")
	var Controls = load("res://scripts/controls.gd")
	for sz in [Vector2(640, 360), Vector2(800, 360), Vector2(520, 360), Vector2(360, 480), Vector2(360, 640), Vector2(360, 800)]:
		var screen := Rect2(Vector2.ZERO, sz)
		var hud: Dictionary = Hud.layout(sz.x, sz.y)
		var fine := true
		var keys: Array = hud.keys()
		for i in keys.size():
			fine = fine and screen.encloses(hud[keys[i]])
			for j in range(i + 1, keys.size()):
				fine = fine and not (hud[keys[i]] as Rect2).intersects(hud[keys[j]])
		var pad: Dictionary = Controls.layout(sz.x, sz.y)
		var radius := {"stick": Controls.STICK_R, "fire": Controls.FIRE_R, "kick": Controls.BTN_R, "dash": Controls.BTN_R}
		keys = pad.keys()
		for i in keys.size():
			var c: Vector2 = pad[keys[i]]
			var r: float = radius[keys[i]]
			fine = fine and screen.encloses(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
			fine = fine and c.y - r > 80.0 # clear of the top HUD rows
			for j in range(i + 1, keys.size()):
				fine = fine and c.distance_to(pad[keys[j]]) > r + radius[keys[j]]
		ok(fine, "%dx%d: HUD panels and touch buttons fit without overlapping" % [sz.x, sz.y])

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
	# Look: the figure is about 12% of the screen height and self-lit art cancels the ambient.
	var figure: float = p.art.height * p.art.scale * p.ZOOM / 1080.0
	ok(figure > 0.10 and figure < 0.15, "player figure is %.1f%% of the screen height (10-15%%)" % (figure * 100.0))
	var px: float = p.art.scale * p.ZOOM
	ok(is_equal_approx(px, roundf(px)), "player art pixels are a whole number of screen pixels at 1080p (%.2f)" % px)
	# Held weapon (pixel-art-engineer section 9): same pixel size as the body, gripped by the fist.
	if p.grips:
		ok(is_equal_approx(p.wep.scale.x, p.body.scale.x) and p.wep.modulate == p.body.modulate and p.wep.light_mask == p.body.light_mask,
			"held weapon shares the body's pixel size, tint and light layer")
		ok(p.hand.get_index() > p.wep.get_index() and p.wep.get_index() > p.body.get_index(), "draw order is body, weapon, hand")
		ok(p.wep.rotation == 0.0 and p.wep.hframes == Fx.HELD_DIRS and p.wep.get_parent() == p,
			"the held weapon shows a pre-drawn direction and is never rotated")
		var fist: Vector2 = Fx.hand_anchors()[p.hand.frame]
		var want: Vector2 = Vector2(floorf(fist.x) + 0.5 - p.art.cell / 2.0, floorf(fist.y) + 0.5 - p.art.feet) * p.art.scale
		if p.body.flip_h:
			want.x = -want.x
		ok(p.hand.visible and p.hand.frame == Fx.PLAYER_V3[p.body.animation][0] + p.body.frame and p.wep.position.distance_to(want) < 0.01,
			"the weapon sits in the fist of the frame being shown")
	ok(not p.grips or is_equal_approx(Fx.PX, p.art.scale), "effects are drawn at the player's art pixel size")
	var lit: Color = w._unlit * w.AMBIENT
	ok(absf(lit.r - 1.0) < 0.01 and absf(lit.g - 1.0) < 0.01 and absf(lit.b - 1.0) < 0.01 and w.AMBIENT.get_luminance() < 0.35,
		"ambient stays dim and the unlit modulate cancels it")
	ok(w.doors.size() >= 12 and w.glass.size() > 0, "doors (%d) and glass (%d) built" % [w.doors.size(), w.glass.size()])

	var p0: Vector2 = p.global_position
	c.move = Vector2.RIGHT
	await frames(20)
	ok(p.body.animation == "run", "run animation plays while moving")
	if p.grips:
		ok(p.hand.frame == Fx.PLAYER_V3["run"][0] + p.body.frame and p.hand.flip_h == p.body.flip_h, "the fist follows the run cycle")
	c.move = Vector2.ZERO
	ok(p.global_position.x - p0.x > 20.0, "player moves")
	await frames(4)
	ok(p.body.animation == "idle", "idle animation plays when standing")
	var sorted_ok: bool = w.y_sort_enabled and w.props.size() > 10 and p.get_parent() == w
	for prop in w.props:
		sorted_ok = sorted_ok and prop.get_parent() == w and prop.z_index == 0
	for e2 in w.enemy_list:
		sorted_ok = sorted_ok and e2.get_parent() == w and e2.z_index == 0
	ok(sorted_ok, "actors and %d props share one Y-sorted layer" % w.props.size())
	p0 = p.global_position
	c.press("dash")
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
	if p.grips:
		var off: Vector2 = (p.wep.position - p.hold) / p.art.scale
		ok(p.wep.rotation == 0.0 and off.distance_to(off.round()) < 0.01, "the weapon stays unrotated and on whole art pixels through a swing")
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
	ok(p.body.animation == "death", "death animation plays")
	ok(not p.wep.visible and (p.hand == null or not p.hand.visible), "weapon and fist are hidden on the floor")
	ok(t >= 18 and t <= 30, "escape window is about 0.4s")

	# Instant restart on the same seed.
	var sig: String = w.L.sig
	var seed_before: int = main.floor_seed
	c.press("any")
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
	c.press("kick")
	await frames(3)
	ok(p.alive and p.grab_t <= 0.0, "kick breaks the grab")
	ok(e.is_down(), "grabber is knocked down")
	await frames(22)
	e.global_position = p.global_position + Vector2(12, 0)
	ok(p.context() == "EXEC", "action button becomes EXEC near a downed zombie")
	var k: int = main.kills
	c.press("kick")
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
	c.press("kick")
	await frames(3)
	ok(d.open and w.los(p.global_position, d.center + n * 13.0), "kick opens the door")
	ok(w.flying.size() == 1, "kicked door flies off its hinges")
	var before: int = w.fx.decal_count()
	await frames(30)
	ok(w.flying.is_empty() and w.fx.decal_count() > before, "the door lands and stays as debris")

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

	# Riot guard: light rounds bounce off the front only.
	var guard = _pick(["riot"])
	var hp0: int = guard.hp
	guard.facing = Vector2.LEFT
	guard.hit(2, Vector2.RIGHT, 0.0, false)
	ok(guard.hp == hp0, "riot armour stops a pistol round from the front")
	guard.hit(1, Vector2.RIGHT, 0.0, true)
	ok(guard.hp == hp0 - 1, "pipe and shotgun get through the armour")
	guard.facing = Vector2.RIGHT
	guard.hit(2, Vector2.RIGHT, 0.0, false)
	ok(guard.hp == hp0 - 3, "a pistol round in the back gets through")

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
	c.press("any")
	await frames(3)
	ok(main.floor_seed == seed_before + 1 and main.state == "play", "next floor uses the next seed")

	print("== %s ==" % ("PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
