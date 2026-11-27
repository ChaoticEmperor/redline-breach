extends Node2D
## REDLINE // 1989, top-down rewrite: milestone M0 skeleton.
## The 3/4-view game was removed (it lives in git history before this branch).
## For now this shows one empty placeholder room drawn in code; movement, aim
## and the pixel-true viewport arrive in M1 (see tasks/future-tasks.md).

const Controls = preload("res://scripts/controls.gd")
const Sfx = preload("res://scripts/sfx.gd")

const TILE := 32 # art pixels per tile; a door is one tile
const ROOM := Vector2i(15, 8) # the placeholder room, in tiles
const FLOOR := Color("1c1426")
const SEAM := Color("140e1c")
const WALL := Color("3a3a40")
const OUTLINE := Color("000000")

var controls
var sfx


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("0a0612"))
	Sfx.warm()
	sfx = Sfx.new()
	add_child(sfx)
	controls = Controls.new()
	add_child(controls)
	var music := AudioStreamPlayer.new()
	music.stream = Sfx.music()
	music.volume_db = -16.0
	add_child(music)
	music.play()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Centre the room on the canvas at a whole-number scale.
	var view := get_viewport_rect().size
	var px := maxf(1.0, floorf(minf(view.x / ((ROOM.x + 2) * TILE), view.y / ((ROOM.y + 2) * TILE))))
	var size := Vector2((ROOM.x + 2) * TILE, (ROOM.y + 2) * TILE) * px
	var o := ((view - size) / 2.0).floor()
	draw_rect(Rect2(o, size), OUTLINE)
	draw_rect(Rect2(o + Vector2.ONE * px * 2, size - Vector2.ONE * px * 4), WALL)
	var inner := Rect2(o + Vector2.ONE * TILE * px, Vector2(ROOM) * TILE * px)
	draw_rect(inner.grow(px * 2), OUTLINE)
	draw_rect(inner, FLOOR)
	for x in range(1, ROOM.x):
		draw_rect(Rect2(inner.position + Vector2(x * TILE * px, 0), Vector2(px, inner.size.y)), SEAM)
	for y in range(1, ROOM.y):
		draw_rect(Rect2(inner.position + Vector2(0, y * TILE * px), Vector2(inner.size.x, px)), SEAM)
