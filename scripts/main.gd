extends Node
## REDLINE // 1989, top-down rewrite. Builds the pixel-true view, the floor and
## the player. Score, death and restart arrive in M5.
##
## Pixel-true view: the world is drawn into a SubViewport at a low resolution
## and shown `view_scale` times larger by a SubViewportContainer, so rotated
## sprites land on the same pixel grid as everything else. The UI (touch
## controls, HUD) is drawn at the window's own resolution on top.

const Controls = preload("res://scripts/controls.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Level = preload("res://scripts/level.gd")
const Player = preload("res://scripts/player.gd")

## The view's short side aims for this many art px (about 10 tiles). The scale is the
## whole number that comes closest; the long side expands with the window, so
## wide phones see more of the floor instead of black bars. Measured in M1:
## 1280x720 x2, 1920x1080 x3, 2560x1440 x4, 3840x2160 x7 (548x308), iPhone
## 2556x1179 x4 (639x294), Android 2400x1080 x3 (800x360).
const SHORT_TARGET := 330 # 16:9 desktops (720p, 1080p, 1440p) all get 640x360
const BORDER := Color("0a0612") # fills the few window pixels left over (fewer than the scale)
const LEAD := 40.0 # art px the camera leads toward the aim
const LOOK_FAR := 150.0 # art px it looks ahead while LOOK is held
const CAM_RATE := 10.0 # how fast the camera closes on its target, per second

var controls
var sfx
var container: SubViewportContainer
var view: SubViewport
var world: Node2D
var map: TileMapLayer
var player
var camera: Camera2D
var view_scale := 1


## The whole-number scale for a window of `size` pixels (always at least 1).
static func scale_for(size: Vector2i) -> int:
	return maxi(1, roundi(float(mini(size.x, size.y)) / SHORT_TARGET))


func _ready() -> void:
	RenderingServer.set_default_clear_color(BORDER)
	Sfx.warm()
	sfx = Sfx.new()
	add_child(sfx)

	var layer := CanvasLayer.new()
	layer.layer = 0
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
	view.add_child(world)

	controls = Controls.new()
	add_child(controls)
	controls.aim_origin = func() -> Vector2: return to_window(player.global_position)

	var music := AudioStreamPlayer.new()
	music.stream = Sfx.music()
	music.volume_db = -16.0
	add_child(music)
	music.play()

	get_viewport().size_changed.connect(_fit)
	_fit()
	build(Level.TEST)


func build(text: String) -> void:
	for c in world.get_children():
		c.queue_free()
	var info := Level.build(text)
	map = info.map
	world.add_child(map)
	player = Player.new()
	player.setup(controls)
	player.position = info.start
	world.add_child(player)
	controls.player = player
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS # physics interpolation draws it between ticks
	camera.position = player.position
	world.add_child(camera)
	camera.make_current()


## Sizes the view to the window: the largest part of it that is a whole
## multiple of the scale; the remainder (fewer pixels than the scale) shows BORDER.
func _fit() -> void:
	var win := Vector2i(get_viewport().get_visible_rect().size)
	view_scale = scale_for(win)
	container.stretch_shrink = view_scale
	container.position = Vector2.ZERO
	container.size = Vector2(win / view_scale * view_scale)


## Where a world point is in window pixels.
func to_window(p: Vector2) -> Vector2:
	return container.position + (view.get_canvas_transform() * p) * view_scale


func _physics_process(delta: float) -> void:
	if player == null:
		return
	var target: Vector2 = player.global_position + player.aim * (LOOK_FAR if controls.look else LEAD)
	camera.position = camera.position.lerp(target, 1.0 - exp(-CAM_RATE * delta))
