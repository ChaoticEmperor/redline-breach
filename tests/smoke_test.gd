extends SceneTree
## Headless smoke test:  godot --headless -s tests/smoke_test.gd
## Loads the real main scene and checks the game's rules: the view, movement, the object model
## (every object answers a Hit in its own way), weapons, physical bodies, breakables, enemies and
## the restart loop. Exits non-zero on any failed assertion.

const Controls = preload("res://scripts/controls.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Main = preload("res://scripts/main.gd")
const Level = preload("res://scripts/level.gd")
const Actor = preload("res://scripts/actors/actor.gd")
const Hit = preload("res://scripts/core/hit.gd")
const Table = preload("res://scripts/weapons/table.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const CharArt = preload("res://scripts/art/char_art.gd")

var fails := 0
var main
var cc


func _initialize() -> void:
	_run()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > 120000:
		print("== TIMED OUT ==")
		quit(1)
	return false


func ok(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


## Dead actors are freed: gone() is true for a freed or dead actor.
func gone(a) -> bool:
	return not is_instance_valid(a) or a.dead


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## Puts the player at `at`, still, aiming `aim`, holding `weapon`.
func place(at: Vector2, aim := Vector2.RIGHT, weapon := "unarmed", ammo := -1) -> void:
	var p = main.player
	p.global_position = at
	p.velocity = Vector2.ZERO
	p.reset_physics_interpolation()
	p.equip(Weapon.make(weapon, ammo))
	cc.move = Vector2.ZERO
	cc.aim = aim
	cc.fire = false


func attack(n := 20) -> void:
	main.player.weapon.cooldown = 0.0
	cc.fire = true
	await physics_frame
	cc.fire = false
	await frames(n)


func fresh(text := Level.TEST) -> void:
	main.build(text)
	await frames(3)


func _run() -> void:
	print("== project ==")
	ok(ProjectSettings.get_setting("physics/common/physics_interpolation"), "physics interpolation is on")
	ok(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")) == 60, "physics runs at 60 Hz")
	for n in Sfx.NAMES:
		if Sfx.snd(n) == null:
			ok(false, "sound '%s' is synthesised" % n)
	ok(true, "every sound is synthesised")

	print("== controls and view ==")
	for sz in [Vector2(640, 360), Vector2(800, 360), Vector2(360, 640), Vector2(360, 780)]:
		var at: Dictionary = Controls.layout(sz.x, sz.y)
		var good := true
		var r := {"stick": Controls.STICK_R, "fire": Controls.FIRE_R}
		var keys := at.keys()
		for i in keys.size():
			var p: Vector2 = at[keys[i]]
			good = good and p.x > 0 and p.y > 0 and p.x < sz.x and p.y < sz.y
			for j in range(i + 1, keys.size()):
				good = good and p.distance_to(at[keys[j]]) >= r.get(keys[i], Controls.BTN_R) + r.get(keys[j], Controls.BTN_R)
		ok(good, "touch controls fit and do not overlap at %dx%d units" % [sz.x, sz.y])
	var want := {Vector2i(1280, 720): 2, Vector2i(1920, 1080): 3, Vector2i(2560, 1440): 4, Vector2i(2556, 1179): 4, Vector2i(2400, 1080): 3}
	var scales_ok := true
	for sz in want:
		scales_ok = scales_ok and Main.scale_for(sz) == want[sz]
	ok(scales_ok, "the view scales by a whole number (720p x2, 1080p x3, 1440p x4, phones x3-4)")

	print("== art ==")
	for skin in ["player", "guard", "infected"]:
		var art := CharArt.load_skin(skin)
		var sf: SpriteFrames = art.frames
		ok(sf.get_frame_count("legs_walk") == 8 and sf.get_frame_count("pipe_walk") == 8 and sf.has_animation("dead_shot"),
				"skin '%s' has the 8-frame legs and walk, attacks and deaths" % skin)

	print("== level ==")
	var club := Level.parse(Level.club())
	var rows := Level.club().strip_edges().split("\n")
	var widths := {}
	for r in rows:
		widths[r.length()] = true
	ok(widths.size() == 1, "every row of the club floor is the same width")
	var built := Level.build(Level.club())
	var grid: AStarGrid2D = built.grid
	var start := Vector2i((club.start / Level.TILE).floor())
	var reach := true
	for t in club.things:
		if t.what in ["guard", "gunman", "infected", "pipe", "bat", "pistol", "shotgun"]:
			reach = reach and not grid.get_id_path(start, t.cell).is_empty()
	ok(reach, "every enemy and weapon on the club floor can be walked to")
	built.map.free()

	print("== main scene ==")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	cc = main.controls
	cc.override = true
	ok(main.enemies().size() == 6 and main.player != null, "the club floor builds with the player and 6 enemies")
	ok(main.restart_usec < 200000, "a floor builds in under 0.2 s (%d ms)" % (main.restart_usec / 1000))

	print("== movement ==")
	await fresh()
	var p = main.player
	place(Vector2(10.5, 6.5) * 32.0)
	cc.move = Vector2.RIGHT
	await frames(6)
	ok(p.velocity.length() >= p.speed * 0.95, "reaches walking speed in 0.1 s")
	cc.move = Vector2.ZERO
	await frames(6)
	ok(p.velocity.length() < 5.0, "stops from walking speed in 0.1 s")
	place(Vector2(254, 176))
	cc.move = Vector2.UP
	await frames(40)
	ok(p.global_position.y < 128.0, "walking into a doorway's edge slides round it")
	cc.move = Vector2.ZERO
	place(Vector2(10.5, 6.5) * 32.0, Vector2.DOWN)
	await frames(2)
	ok(is_equal_approx(p.look.torso.rotation, Vector2.DOWN.angle()), "the torso turns to the aim")
	cc.move = Vector2.LEFT
	var seen := {}
	for i in 30:
		await physics_frame
		seen[p.look.walk_frame] = true
	ok(absf(angle_difference(p.look.legs.rotation, Vector2.LEFT.angle())) < 0.01 and seen.size() >= 6,
			"the legs turn to the movement and step through their frames")
	cc.move = Vector2.ZERO

	print("== objects answer a Hit ==")
	await fresh()
	var g = main.spawn("glass_h", Vector2(12.5, 2.5) * 32.0)
	var tbl = main.spawn("table", Vector2(4.5, 2.5) * 32.0)
	var e = main.spawn("guard", Vector2(9.5, 7.5) * 32.0, Vector2.LEFT)
	await frames(2)
	g.take_hit(Hit.make("impact", Vector2.UP, 200.0))
	var t0: Vector2 = tbl.global_position
	tbl.take_hit(Hit.make("kick", Vector2.RIGHT, 340.0))
	await frames(20)
	ok(g.broken, "glass shatters when hit")
	ok(tbl.global_position.x > t0.x + 4.0, "a table slides when kicked (%.0f px)" % (tbl.global_position.x - t0.x))
	e.take_hit(Hit.make("shot", Vector2.RIGHT, 300.0, main.player, "player"))
	await frames(3)
	var bodies: Array = main.get_tree().get_nodes_in_group("bodies")
	ok(gone(e) and bodies.size() == 1, "an enemy dies from one shot and becomes a body")
	ok(bodies.size() == 1 and bodies[0].linear_velocity.x > 60.0, "the body is thrown the way the shot pushed it")
	var e2 = main.spawn("guard", Vector2(4.5, 7.5) * 32.0, Vector2.LEFT)
	await frames(2)
	e2.take_hit(Hit.make("blunt", Vector2.LEFT, 300.0, e2, "enemy"))
	await frames(2)
	ok(not gone(e2), "an actor ignores blows from its own side")

	print("== weapons ==")
	await fresh()
	var spot := Vector2(10.5, 2.5) * 32.0
	place(spot, Vector2.RIGHT, "unarmed")
	var d1 = main.spawn("guard", spot + Vector2(18, 0), Vector2.LEFT)
	await frames(1)
	await attack(25)
	ok(not gone(d1) and d1.is_down(), "a punch knocks down and does not kill")
	place(d1.global_position - Vector2(20, 0), Vector2.RIGHT, "pipe")
	await attack(25)
	ok(gone(d1), "a blow on a downed enemy finishes it")
	await fresh()
	place(spot, Vector2.RIGHT, "pipe")
	var front = main.spawn("guard", spot + Vector2(24, 0), Vector2.LEFT)
	var back = main.spawn("guard", spot + Vector2(-24, 0), Vector2.RIGHT)
	await frames(1)
	var heard: int = main.noises.size()
	cc.fire = true
	await frames(2)
	cc.fire = false
	ok(not gone(front), "the swing has not landed after 2 frames")
	await frames(30)
	ok(gone(front) and not gone(back), "a pipe kills in one hit in front and misses behind")
	ok(main.noises.size() == heard, "melee is silent")
	await fresh()
	place(spot, Vector2.RIGHT, "pistol")
	var far = main.spawn("guard", spot + Vector2(150, 0), Vector2.LEFT)
	await frames(1)
	heard = main.noises.size()
	await attack(3)
	ok(gone(far) and main.player.weapon.ammo == Table.full_ammo("pistol") - 1, "a pistol kills at 150 px and costs one round")
	ok(main.noises.size() == heard + 1, "a shot is loud")
	await fresh()
	place(spot, Vector2.RIGHT, "pistol", 3)
	var tgt = main.spawn("guard", spot + Vector2(110, 0), Vector2.LEFT)
	await frames(1)
	cc.press("throw")
	await frames(40)
	ok(not gone(tgt) and tgt.is_down() and main.player.weapon.name == "unarmed", "a thrown gun knocks down without killing")
	var landed = null
	for pk in main.get_tree().get_nodes_in_group("pickups"):
		if pk.weapon == "pistol":
			landed = pk
	ok(landed != null and landed.ammo == 3, "the thrown gun lands as a pickup with its ammo")

	print("== physical bodies and breakables ==")
	await fresh()
	var pane = main.spawn("glass_h", Vector2(12.5, 6.0) * 32.0)
	var victim = main.spawn("guard", Vector2(12.5, 8.3) * 32.0, Vector2.DOWN)
	await frames(2)
	victim.take_hit(Hit.make("shot", Vector2.UP, 420.0, main.player, "player"))
	await frames(40)
	ok(pane.broken, "a body thrown into glass breaks it")
	await fresh()
	var stool = main.spawn("stool", Vector2(12.5, 5.6) * 32.0)
	var v2 = main.spawn("guard", Vector2(12.5, 8.3) * 32.0, Vector2.DOWN)
	await frames(2)
	var s0: Vector2 = stool.global_position
	v2.take_hit(Hit.make("shot", Vector2.UP, 420.0, main.player, "player"))
	await frames(40)
	ok(stool.global_position.distance_to(s0) > 3.0, "a flying body knocks a stool away")
	await fresh()
	var door = main.spawn("door_h", Vector2(7.5, 4.5) * 32.0)
	await frames(2)
	door.take_hit(Hit.make("kick", Vector2.DOWN, 340.0))
	await frames(4)
	ok(absf(door.angular_velocity) > 1.0 or absf(door.rotation) > 0.1, "a kicked door swings on its hinge")

	print("== enemies ==")
	await fresh()
	place(Vector2(4.5, 6.5) * 32.0, Vector2.RIGHT)
	main.player.health.invulnerable = true
	var gm = main.spawn("guard", Vector2(12.5, 6.5) * 32.0, Vector2.LEFT)
	await frames(8)
	ok(gm.brain.state == gm.brain.NOTICE_BEAT, "an enemy that sees the player first waits a notice beat")
	var x0: float = gm.global_position.x
	await frames(30)
	ok(gm.brain.state == gm.brain.CHASE and gm.global_position.x < x0 - 10.0, "then it comes for the player")
	await fresh()
	for i in 6:
		main.spawn("guard", Vector2(2.5 + i * 2.5, 2.5) * 32.0, Vector2.UP)
	await frames(2)
	main.noise(Vector2(10.5, 2.5) * 32.0, 1000.0)
	var drawn: int = main.enemies().filter(func(x): return x.brain.state == x.brain.SEARCH).size()
	ok(drawn == Main.NOISE_DRAWS, "a noise draws only the nearest %d enemies (%d)" % [Main.NOISE_DRAWS, drawn])

	print("== the loop ==")
	await fresh()
	place(Vector2(4.5, 6.5) * 32.0, Vector2.RIGHT)
	main.spawn("infected", Vector2(5.4, 6.5) * 32.0, Vector2.LEFT)
	await frames(60)
	ok(main.state == "dead" and main.player.dead, "an infected that reaches the player kills it")
	await fresh(Level.club())
	cc.press("restart")
	await frames(2)
	ok(main.state == "play" and main.enemies().size() == 6 and main.restart_usec < 200000,
			"R restarts the same floor in under 0.2 s (%d ms)" % (main.restart_usec / 1000))
	for x in main.enemies():
		x.take_hit(Hit.make("shot", Vector2.RIGHT, 200.0, main.player, "player"))
	await frames(3)
	ok(main.state == "clear", "the floor is clear when every enemy is dead")

	print("== %s ==" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)
