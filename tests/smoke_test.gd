extends SceneTree
## Headless smoke test:  godot --headless -s tests/smoke_test.gd
## Loads the real main scene and checks the rules that hold from M0 on.
## Exits non-zero on any failed assertion.

const Controls = preload("res://scripts/controls.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Main = preload("res://scripts/main.gd")
const Player = preload("res://scripts/player.gd")

var fails := 0


func _initialize() -> void:
	_run()


## Watchdog: a script error inside the coroutine would otherwise hang forever.
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > 60000:
		print("== TIMED OUT ==")
		quit(1)
	return false


func ok(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	print("== project ==")
	ok(ProjectSettings.get_setting("physics/common/physics_interpolation"), "physics interpolation is on")
	ok(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")) == 60, "physics runs at 60 Hz")

	print("== sound ==")
	for n in Sfx.NAMES:
		var s: AudioStreamWAV = Sfx.snd(n)
		ok(s != null and s.data.size() > 0, "sound '%s' is synthesised" % n)
	ok(Sfx.music().loop_mode == AudioStreamWAV.LOOP_FORWARD, "music loops")

	print("== controls ==")
	for sz in [Vector2(640, 360), Vector2(800, 360), Vector2(360, 640), Vector2(360, 780)]:
		var at: Dictionary = Controls.layout(sz.x, sz.y)
		var inside := true
		for k in at:
			var p: Vector2 = at[k]
			inside = inside and p.x > 0 and p.y > 0 and p.x < sz.x and p.y < sz.y
		ok(inside, "touch controls are on screen at %dx%d units" % [sz.x, sz.y])
		var apart := true
		var r := {"stick": Controls.STICK_R, "fire": Controls.FIRE_R}
		var keys := at.keys()
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				var need: float = r.get(keys[i], Controls.BTN_R) + r.get(keys[j], Controls.BTN_R)
				apart = apart and at[keys[i]].distance_to(at[keys[j]]) >= need
		ok(apart, "touch controls do not overlap at %dx%d units" % [sz.x, sz.y])
	var c0 := Controls.new()
	ok(not c0.q.has("dash") and c0.q.has("throw") and c0.q.has("kick") and c0.q.has("pickup"), "no dash; throw, kick and pick-up presses exist")
	c0.free()

	print("== view scale ==")
	var want := {Vector2i(1280, 720): 2, Vector2i(1920, 1080): 3, Vector2i(2560, 1440): 4,
			Vector2i(2556, 1179): 4, Vector2i(2400, 1080): 3, Vector2i(1179, 2556): 4}
	for sz in want:
		var k := Main.scale_for(sz)
		var short := mini(sz.x, sz.y) / k
		ok(k == want[sz] and short >= 256 and short <= 400,
				"%dx%d draws art px x%d, short side %d art px (%.1f tiles)" % [sz.x, sz.y, k, short, short / 32.0])
	ok(Main.scale_for(Vector2i(300, 200)) == 1, "a tiny window still scales by 1")

	print("== main scene ==")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await physics_frame
	ok(main.controls != null and main.sfx != null, "main builds controls and sound")
	main.controls.override = true
	main.controls.press("kick")
	ok(main.controls.take("kick") and not main.controls.take("kick"), "a press is taken once")
	ok(main.view_scale >= 1 and main.container.stretch_shrink == main.view_scale, "the world view is scaled by a whole number")

	print("== movement ==")
	var p = main.player
	var cc = main.controls
	p.global_position = Vector2(10.5, 6.5) * 32.0
	p.reset_physics_interpolation()
	p.velocity = Vector2.ZERO
	cc.move = Vector2.RIGHT
	await _frames(6)
	ok(p.velocity.length() >= Player.SPEED * 0.95, "reaches walking speed in 0.1 s (%.0f of %.0f)" % [p.velocity.length(), Player.SPEED])
	cc.move = Vector2.ZERO
	await _frames(6)
	ok(p.velocity.length() < 5.0, "stops from walking speed in 0.1 s (%.1f left)" % p.velocity.length())

	# Walk straight up into the wall 14 px right of the doorway's centre (x 224-256).
	p.global_position = Vector2(254, 176)
	p.reset_physics_interpolation()
	cc.move = Vector2.UP
	await _frames(40)
	ok(p.global_position.y < 128.0, "walking into a doorway's edge slides round it (y %.0f)" % p.global_position.y)
	cc.move = Vector2.ZERO
	await _frames(10)

	print("== look and camera ==")
	p.global_position = Vector2(10.5, 6.5) * 32.0
	p.reset_physics_interpolation()
	cc.aim = Vector2.DOWN
	await _frames(2)
	ok(is_equal_approx(p.look.torso.rotation, Vector2.DOWN.angle()), "the torso turns to the aim")
	ok(p.look.walk_frame == 0, "standing shows leg frame 0 (legs hidden)")
	cc.move = Vector2.LEFT
	var seen := {}
	for i in 30:
		await physics_frame
		seen[p.look.walk_frame] = true
	ok(absf(angle_difference(p.look.legs.rotation, Vector2.LEFT.angle())) < 0.01, "the legs turn to the movement, apart from the aim")
	ok(seen.size() >= 6, "walking steps through the leg frames (%d seen)" % seen.size())
	cc.move = Vector2.ZERO
	cc.aim = Vector2.RIGHT
	await _frames(60)
	var lead: float = main.camera.position.x - p.global_position.x
	ok(lead > Main.LEAD * 0.8, "the camera leads toward the aim (%.0f px)" % lead)
	cc.look = true
	await _frames(60)
	lead = main.camera.position.x - p.global_position.x
	ok(lead > Main.LOOK_FAR * 0.8, "holding LOOK pushes the camera far ahead (%.0f px)" % lead)
	cc.look = false

	print("== %s ==" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)
