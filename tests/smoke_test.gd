extends SceneTree
## Headless smoke test:  godot --headless -s tests/smoke_test.gd
## Loads the real main scene and checks the rules that hold from M0 on.
## Exits non-zero on any failed assertion.

const Controls = preload("res://scripts/controls.gd")
const Sfx = preload("res://scripts/sfx.gd")

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

	print("== main scene ==")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await physics_frame
	ok(main.controls != null and main.sfx != null, "main builds controls and sound")
	main.controls.override = true
	main.controls.press("kick")
	ok(main.controls.take("kick") and not main.controls.take("kick"), "a press is taken once")

	print("== %s ==" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)
