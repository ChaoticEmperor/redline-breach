extends Node
## REDLINE // 1989, top-down prototype. Builds the pixel-true view and a floor, places every
## object the level names, and runs the loop: one hit kills, restart is instant (R), the floor
## is clear when every enemy is dead.
##
## Pixel-true view: the world is drawn into a SubViewport at a low resolution and shown
## `view_scale` times larger, so rotated sprites land on the same pixel grid as everything else.

const Controls = preload("res://scripts/controls.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Level = preload("res://scripts/level.gd")
const Player = preload("res://scripts/actors/player.gd")
const Enemy = preload("res://scripts/actors/enemy.gd")
const Pickup = preload("res://scripts/world/pickup.gd")
const Glass = preload("res://scripts/world/glass.gd")
const Door = preload("res://scripts/world/door.gd")
const Furniture = preload("res://scripts/world/furniture.gd")
const Decals = preload("res://scripts/world/decals.gd")
const Outlines = preload("res://scripts/world/outlines.gd")
const Table = preload("res://scripts/weapons/table.gd")
const CharArt = preload("res://scripts/art/char_art.gd")
const Fx = preload("res://scripts/fx.gd")

const SHORT_TARGET := 330 # the view's short side aims for this many art px; 16:9 desktops get 640x360
const BORDER := Color("0d0709")
const LEAD := 40.0
const LOOK_FAR := 150.0
const CAM_RATE := 10.0
const NOISE_DRAWS := 4 # a shot alerts only the nearest few in earshot
const NOISE_SCATTER := 40.0 # each to a spot this far round the sound, not the exact pixel

var controls
var sfx
var container: SubViewportContainer
var view: SubViewport
var world: Node2D
var map: TileMapLayer
var grid: AStarGrid2D
var player
var camera: Camera2D
var fx
var decals
var hud: Label
var view_scale := 1
var floor_seed := 1989
var level_text := Level.club()
var rng := RandomNumberGenerator.new()
var noises: Array = []
var kills := 0
var state := "play" # play | dead | clear
var _state_t := 0.0
var restart_usec := 0


static func scale_for(size: Vector2i) -> int:
	return maxi(1, roundi(float(mini(size.x, size.y)) / SHORT_TARGET))


func _ready() -> void:
	RenderingServer.set_default_clear_color(BORDER)
	Sfx.warm()
	sfx = Sfx.new()
	add_child(sfx)
	var layer := CanvasLayer.new()
	add_child(layer)
	container = SubViewportContainer.new()
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(container)
	view = SubViewport.new()
	view.snap_2d_transforms_to_pixel = true
	view.snap_2d_vertices_to_pixel = true
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	view.handle_input_locally = false
	container.add_child(view)
	world = Node2D.new()
	world.y_sort_enabled = false
	view.add_child(world)
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_color", Color("f6ede4"))
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	ui.add_child(hud)
	controls = Controls.new()
	add_child(controls)
	controls.aim_origin = func() -> Vector2: return to_window(player.global_position) if is_instance_valid(player) else Vector2.ZERO
	var music := AudioStreamPlayer.new()
	music.stream = Sfx.music()
	music.volume_db = -16.0
	add_child(music)
	music.play()
	get_viewport().size_changed.connect(_fit)
	_fit()
	build(level_text)


## Builds (or rebuilds, on restart) the floor from scratch: same text, same seed, same floor.
func build(text: String) -> void:
	var t0 := Time.get_ticks_usec()
	level_text = text
	for c in world.get_children():
		world.remove_child(c)
		c.queue_free()
	rng.seed = floor_seed
	seed(floor_seed)
	noises.clear()
	kills = 0
	state = "play"
	var info := Level.build(text)
	map = info.map
	grid = info.grid
	world.add_child(map)
	var outlines := Outlines.new()
	outlines.setup(info.cells)
	world.add_child(outlines)
	decals = Decals.new()
	world.add_child(decals)
	for t in info.things:
		spawn(t.what, t.pos, (info.start - t.pos).normalized())
	player = Player.new()
	player.setup_player(self, controls)
	player.position = info.start
	world.add_child(player)
	controls.player = player
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = player.position
	world.add_child(camera)
	camera.make_current()
	fx = Fx.new()
	world.add_child(fx)
	restart_usec = Time.get_ticks_usec() - t0
	_update_hud()


## Places one object the level (or a test) names at `pos`; returns it.
func spawn(what: String, pos: Vector2, facing := Vector2.RIGHT) -> Node:
	var n: Node
	match what:
		"guard", "gunman", "infected", "runner", "bloater", "riot":
			n = Enemy.new()
			n.setup_enemy(self, what, facing)
			n.position = pos
			world.add_child(n)
		"pipe", "bat", "pistol", "shotgun":
			n = drop(what, Table.full_ammo(what), pos)
		"glass_h", "glass_v":
			n = Glass.new()
			n.setup(self, what == "glass_v")
			n.position = pos
			world.add_child(n)
		"door_h", "door_v":
			n = Door.new()
			var vertical := what == "door_v"
			n.setup(self, PI / 2.0 if vertical else 0.0)
			n.position = pos + (Vector2(0, -Level.TILE / 2.0) if vertical else Vector2(-Level.TILE / 2.0, 0))
			world.add_child(n)
			n.attach_hinge()
		"table", "stool":
			n = Furniture.new()
			n.setup(what)
			n.position = pos
			world.add_child(n)
	return n


func enemies() -> Array:
	return get_tree().get_nodes_in_group("actors").filter(func(a): return a.team == "enemy" and not a.dead and not a.is_queued_for_deletion())


# ---------------------------------------------------------------- services for the objects

func drop(weapon: String, ammo: int, pos: Vector2, angle := 0.0) -> Node:
	var pk := Pickup.new()
	pk.setup(weapon, ammo, angle)
	pk.position = pos
	world.add_child(pk)
	return pk


## A loud sound: the nearest NOISE_DRAWS enemies within `radius` come to a spot near it.
func noise(pos: Vector2, radius: float, source = null) -> void:
	noises.append([pos, radius])
	var near := enemies().filter(func(e): return e != source and e.global_position.distance_to(pos) <= radius)
	near.sort_custom(func(a, b): return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	for e in near.slice(0, NOISE_DRAWS):
		e.hear(pos + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * NOISE_SCATTER)


func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := Vector2i((from / Level.TILE).floor())
	var b := Vector2i((to / Level.TILE).floor())
	if not grid.is_in_boundsv(a) or not grid.is_in_boundsv(b) or grid.is_point_solid(b):
		return PackedVector2Array()
	return grid.get_point_path(a, b, true)


func corpse_texture(skin: String, cause: String, i: int) -> Texture2D:
	var art := CharArt.load_skin(skin)
	return art.frames.get_frame_texture("dead_" + cause, clampi(i, 0, 2))


func blood(at: Vector2, dir: Vector2, size: float) -> void:
	decals.splat(at, dir, size, rng)


func shards(at: Vector2, dir: Vector2) -> void:
	fx.glass(at, dir, rng)


func popup(at: Vector2, text: String) -> void:
	fx.pop(at, text)


func on_actor_died(a, _hit) -> void:
	if a == player:
		state = "dead"
		_state_t = 0.0
	else:
		kills += 1
		if enemies().filter(func(e): return e != a).is_empty():
			state = "clear"
			sfx.play("clear")
	_update_hud()


func _update_hud() -> void:
	var line := "KILLS %d   ENEMIES %d" % [kills, enemies().size()]
	if state == "dead":
		line += "\nYOU DIED   press R to restart"
	elif state == "clear":
		line += "\nFLOOR CLEAR   press R to play again"
	hud.text = line


# ---------------------------------------------------------------- view

func _fit() -> void:
	var win := Vector2i(get_viewport().get_visible_rect().size)
	view_scale = scale_for(win)
	container.stretch_shrink = view_scale
	container.size = Vector2(win / view_scale * view_scale)


func to_window(p: Vector2) -> Vector2:
	return container.position + (view.get_canvas_transform() * p) * view_scale


func _physics_process(delta: float) -> void:
	_state_t += delta
	if controls.take("restart"):
		build(level_text)
		return
	if is_instance_valid(player) and not player.dead:
		var target: Vector2 = player.global_position + player.aim * (LOOK_FAR if controls.look else LEAD)
		camera.position = camera.position.lerp(target, 1.0 - exp(-CAM_RATE * delta))
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * fx.shake if fx.shake > 0.0 else Vector2.ZERO
	_update_hud()
