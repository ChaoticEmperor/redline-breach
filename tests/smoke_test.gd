extends SceneTree
## Headless smoke test:  godot --headless -s tests/smoke_test.gd
## Loads the real main scene and checks the rules that hold from M0 on.
## Exits non-zero on any failed assertion.

const Controls = preload("res://scripts/controls.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Main = preload("res://scripts/main.gd")
const Player = preload("res://scripts/player.gd")

var fails := 0


## A stand-in enemy for the weapon checks (real enemies arrive in M3).
class Dummy extends CharacterBody2D:
	var dead := false
	var down := false
	var how := ""

	func _init() -> void:
		collision_layer = 2
		collision_mask = 1
		var shape := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 9.0
		shape.shape = c
		add_child(shape)

	func hit(_dir: Vector2, p_how: String) -> void:
		dead = true
		how = p_how

	func knockdown(_dir: Vector2) -> void:
		down = true


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


func _dummy(main, at: Vector2):
	var d := Dummy.new()
	d.position = at
	main.world.add_child(d)
	await physics_frame
	return d


## Holds fire for one frame, then waits `n` frames.
func _attack(p, cc, n: int) -> void:
	p.cd = 0.0
	cc.fire = true
	await physics_frame
	cc.fire = false
	await _frames(n)


## Where a shotgun blast's pellets end, fired right from the open floor on a fresh floor seed.
func _spread(main, p, cc) -> Array:
	main.rng.seed = main.floor_seed
	p.weapon = "shotgun"
	p.ammo = 4
	p.global_position = Vector2(4.5, 2.5) * 32.0
	p.reset_physics_interpolation()
	cc.aim = Vector2.RIGHT
	await physics_frame
	main.fx.tracers.clear()
	await _attack(p, cc, 1)
	var out := []
	for t in main.fx.tracers:
		out.append(Vector2i(t[1]))
	return out


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

	print("== weapons ==")
	var W = preload("res://scripts/weapons.gd")
	ok(main.get_tree().get_nodes_in_group("pickups").size() == 2, "the test room has a pipe and a pistol on the floor")
	var spot := Vector2(10.5, 2.5) * 32.0 # open floor above the wall
	cc.aim = Vector2.RIGHT
	# Fists knock down, never kill.
	var d = await _dummy(main, spot + Vector2(16, 0))
	p.global_position = spot
	p.reset_physics_interpolation()
	await _attack(p, cc, 20)
	ok(d.down and not d.dead, "a punch knocks down and does not kill")
	d.queue_free()
	# Melee kills in one hit in front, misses behind, and is silent.
	p.weapon = "pipe"
	var front = await _dummy(main, spot + Vector2(22, 0))
	var back = await _dummy(main, spot + Vector2(-22, 0))
	var heard: int = main.noises.size()
	await _attack(p, cc, 30)
	ok(front.dead and front.how == "blunt", "a pipe kills in one hit in front")
	ok(not back.dead, "a swing does not hit behind the player")
	ok(main.noises.size() == heard, "melee is silent")
	front.queue_free()
	back.queue_free()
	# The blow lands after the strike, not on the first frame.
	var late = await _dummy(main, spot + Vector2(22, 0))
	cc.fire = true
	await _frames(2)
	cc.fire = false
	ok(not late.dead, "the swing has not landed after 2 frames")
	await _frames(30)
	ok(late.dead, "the swing lands during its strike")
	late.queue_free()
	# Guns: one hit kills, each shot costs a round, shots are loud, an empty gun clicks.
	p.weapon = "pistol"
	p.ammo = W.full_ammo("pistol")
	var far = await _dummy(main, spot + Vector2(150, 0))
	heard = main.noises.size()
	await _attack(p, cc, 3)
	ok(far.dead and far.how == "shot", "a pistol shot kills at 150 px")
	ok(p.ammo == W.full_ammo("pistol") - 1, "a shot costs one round (%d left)" % p.ammo)
	ok(main.noises.size() == heard + 1 and main.noises[-1][1] >= 300.0, "a shot is loud")
	far.queue_free()
	p.ammo = 0
	var safe = await _dummy(main, spot + Vector2(150, 0))
	await _attack(p, cc, 3)
	ok(not safe.dead and p.weapon == "pistol", "an empty gun does nothing and stays in hand")
	safe.queue_free()
	var walled = await _dummy(main, spot + Vector2(0, 96)) # beyond the wall row
	p.ammo = 3
	cc.aim = Vector2.DOWN
	await _attack(p, cc, 3)
	ok(not walled.dead, "shots stop at walls")
	walled.queue_free()
	cc.aim = Vector2.RIGHT
	# Throw: knocks down, does not kill, lands as a pickup with its ammo.
	p.weapon = "pistol"
	p.ammo = 3
	var tgt = await _dummy(main, spot + Vector2(120, 0))
	cc.press("throw")
	await _frames(40)
	ok(tgt.down and not tgt.dead, "a thrown gun knocks down without killing")
	ok(p.weapon == W.FISTS, "throwing empties the hands")
	var landed = null
	for pk in main.get_tree().get_nodes_in_group("pickups"):
		if pk.global_position.distance_to(tgt.global_position) < 40.0:
			landed = pk
	ok(landed != null and landed.weapon == "pistol" and landed.ammo == 3, "the thrown gun lands near the target with its ammo")
	tgt.queue_free()
	# Pick up: standing on it and pressing takes it; THROW with empty hands also takes.
	p.global_position = landed.global_position
	p.reset_physics_interpolation()
	await _frames(2)
	cc.press("throw")
	await _frames(2)
	ok(p.weapon == "pistol" and p.ammo == 3, "THROW with empty hands picks up the weapon underfoot")
	main.drop("shotgun", 4, p.global_position)
	cc.press("pickup")
	await _frames(2)
	var swapped := false
	for pk in main.get_tree().get_nodes_in_group("pickups"):
		swapped = swapped or (pk.weapon == "pistol" and pk.global_position.distance_to(p.global_position) < 4.0)
	ok(p.weapon == "shotgun" and swapped, "picking up swaps, dropping the old weapon at the feet")
	# Shotgun spread replays the same after a rebuild with the same seed.
	ok(await _spread(main, p, cc) == await _spread(main, p, cc), "shotgun spread replays the same from the same floor seed")

	print("== %s ==" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)
