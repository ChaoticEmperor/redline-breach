extends SceneTree
## Frame capture for the visual polisher. Needs a display (xvfb is enough):
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       -s tools/capture_views.gd -- <out dir> [view ...] [WIDTHxHEIGHT]
##
## Views: `entry` (the player at spawn) or the name of a zone (`dancefloor`,
## `vip`, `kitchen`, `bar`, ...), which puts the player on a walkable cell in
## the middle of the first room of that zone. For each view it writes
## `actual_<view>.png` and a sidecar `actual_<view>.json` holding the player
## figure's on-screen height as a fraction of the viewport height.

const Fx = preload("res://scripts/fx.gd")
const Layout = preload("res://scripts/layout.gd")

const ZONES := ["entry", "dancefloor", "vip", "kitchen", "bar", "restroom", "storage", "staff", "elevator"]
const FIGURE_PX := 42.0 # height of the drawn player figure in sheet pixels
const SETTLE_FRAMES := 40
const FIRST_BEAT := 40 # world beats (250 ms each) before the first shot
const BEAT_STEP := 32 # ... and between shots

var main


func _initialize() -> void:
	_run()


## Watchdog: a script error inside the coroutine would otherwise hang forever.
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > 120000:
		print("capture_views: timed out")
		quit(1)
	return false


func _run() -> void:
	var out := "tools/out"
	var views: Array = []
	var size := Vector2i(1920, 1080)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		if i == 0:
			out = a
		elif a.contains("x") and a.replace("x", "").is_valid_int():
			size = Vector2i(int(a.get_slice("x", 0)), int(a.get_slice("x", 1)))
		else:
			views.append_array(a.split(",", false))
	if views.is_empty():
		views = ["entry", "dancefloor"]
	if DisplayServer.get_name() == "headless":
		print("capture_views: the headless display cannot render; run under xvfb-run. Nothing captured.")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join(".gdignore"), FileAccess.WRITE).close() # keep Godot from importing captures

	seed(1989)
	get_root().size = size
	main = load("res://main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	main.controls.override = true # nothing reads real input
	main.controls.touch_mode = false
	main.controls.visible = false
	var world = main.world
	var player = main.player
	for e in world.enemy_list: # zombies hold their spawn positions, so runs are comparable
		e.set_physics_process(false)

	var shot := -1
	for view in views:
		var cell: Vector2i = world.L.start
		if view != "entry":
			var found = _zone_cell(world, ZONES.find(view))
			if found == null:
				print("capture_views: no room for view '%s', skipped" % view)
				continue
			cell = found
		player.grab_immune = 99.0 # zombies cannot kill the player mid-capture
		player.global_position = world.center(cell)
		player.velocity = Vector2.ZERO
		player.aim = Vector2.RIGHT
		player.cam.offset = Vector2.ZERO
		player.cam.reset_smoothing()
		for i in SETTLE_FRAMES: # lights, camera and animations settle
			await process_frame
		# The dancefloor pulse and the alarm strobes follow the clock: shoot each
		# view on a fixed beat so two runs show the same tiles lit.
		shot += 1
		while world._beat < FIRST_BEAT + shot * BEAT_STEP:
			await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = out.path_join("actual_%s.png" % view)
		var err := get_root().get_texture().get_image().save_png(path)
		var visible: Vector2 = get_root().get_visible_rect().size
		var zoom: float = player.cam.zoom.y
		var info := {
			"view": view,
			"size": [size.x, size.y],
			"seed": main.floor_seed,
			"beat": world._beat,
			"cell": [cell.x, cell.y],
			"camera_zoom": zoom,
			"art_scale": Fx.ART_SCALE,
			"figure_sheet_px": FIGURE_PX,
			"char_height_ratio": FIGURE_PX * Fx.ART_SCALE * zoom / visible.y,
		}
		var f := FileAccess.open(out.path_join("actual_%s.json" % view), FileAccess.WRITE)
		f.store_string(JSON.stringify(info, "  ") + "\n")
		f.close()
		print("capture_views: %s -> %s (%s)" % [view, path, "ok" if err == OK else "error %d" % err])
	quit(0)


## A walkable cell of `zone`, as close as possible to the middle of the first
## room of that zone. Null when the floor has no such room.
func _zone_cell(world, zone: int):
	if zone < 0:
		return null
	var L: Dictionary = world.L
	for s in Layout.COLS * Layout.ROWS:
		if world._chunk_zone(s) != zone:
			continue
		var mid: Vector2i = world.cell_of(world._chunk_origin(s)) + Vector2i(Layout.CW, Layout.CH) / 2
		var best = null
		var best_d := 1e9
		for y in range(mid.y - Layout.CH / 2, mid.y + Layout.CH / 2 + 1):
			for x in range(mid.x - Layout.CW / 2, mid.x + Layout.CW / 2 + 1):
				var c := Vector2i(x, y)
				if world.code_at(c) != Layout.FLOOR or L.zone[y * L.w + x] != zone:
					continue
				var d := Vector2(c - mid).length()
				if d < best_d:
					best_d = d
					best = c
		if best != null:
			return best
	return null
