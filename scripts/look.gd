extends Node2D
## How an actor is drawn. The one place that knows the view: an overhead body
## whose legs turn to the movement direction and whose torso turns to the aim
## (Paul, 2026-11-27). Gameplay only calls set_aim(), set_move() and play(), so a
## switch to 4-direction sprites would replace this node and nothing else.
##
## M1 draws a placeholder in code at the real sizes: a ~24x24 box in a 32 px
## cell, a big central head, shoulders as a crescent, black outline and inner
## contours. M6 swaps in the Tandem SpriteFrames (legs strip + torso per weapon).

const Weapons = preload("res://scripts/weapons.gd")

const STRIDE := 28.0 # art px walked per 8-frame leg cycle
const WALK_FRAMES := 8

@export var jacket := Color("e0a21e") # a warm colour marks the player
@export var jacket_dark := Color("a06a10")
@export var skin := Color("e8b48a")
@export var hair := Color("3a2418")
@export var trousers := Color("2c3a5a")

var weapon := "" # what the torso holds ("" = fists)
var swing := 0.0 # the melee weapon's angle off the aim, mid-swing
var aim_angle := 0.0
var move_angle := 0.0
var walk_frame := 0 # 0 = standing, legs hidden
var anim := "walk"
var _phase := 0.0
var legs: Node2D
var torso: Node2D


func _ready() -> void:
	legs = Node2D.new()
	legs.draw.connect(_draw_legs)
	add_child(legs)
	torso = Node2D.new()
	torso.draw.connect(_draw_torso)
	add_child(torso)


func set_aim(dir: Vector2) -> void:
	if dir.length() > 0.01:
		aim_angle = dir.angle()
		torso.rotation = aim_angle
	torso.queue_redraw()


## `vel` is the actor's velocity in art px per second.
func set_move(vel: Vector2, delta: float) -> void:
	var speed := vel.length()
	if speed > 4.0:
		move_angle = vel.angle()
		legs.rotation = move_angle
		_phase = fposmod(_phase + speed * delta / STRIDE, 1.0)
		walk_frame = 1 + int(_phase * (WALK_FRAMES - 1)) % (WALK_FRAMES - 1)
	else:
		_phase = 0.0
		walk_frame = 0
	legs.queue_redraw()


## Guns are held forward near the centre line; melee weapons in the leading hand.
func _grip() -> Vector2:
	return Vector2(8, 3) if Weapons.is_gun(weapon) else Vector2(8, 9)


func _tip() -> Vector2:
	var length: float = Weapons.info(weapon).length if weapon != "" else 0.0
	return _grip() + Vector2.RIGHT.rotated(swing) * length * (0.6 if Weapons.is_gun(weapon) else 0.9)


## The held weapon's tip (a gun's muzzle) in global coordinates: flashes and
## tracers start here, while shots are cast along the exact aim.
func tip_global() -> Vector2:
	torso.rotation = aim_angle
	return torso.to_global(_tip())


func play(name: String) -> void:
	anim = name
	torso.queue_redraw()


## Legs: two blobs in the trouser colour poking out past the body, one leading
## while the other trails; hidden on the standing frame.
func _draw_legs() -> void:
	if walk_frame == 0:
		return
	var s := sin(float(walk_frame) / (WALK_FRAMES - 1) * TAU) * 7.0
	for side in [-1.0, 1.0]:
		var p := Vector2(s * side, 4.0 * side)
		legs.draw_circle(p, 4.0, Color.BLACK)
		legs.draw_circle(p, 3.0, trousers)


## Torso facing +x: shoulders as a crescent round a big central head.
func _draw_torso() -> void:
	torso.draw_rect(Rect2(-6, -12, 12, 24), Color.BLACK)
	torso.draw_rect(Rect2(-5, -11, 10, 22), jacket_dark)
	torso.draw_rect(Rect2(-4, -10, 7, 20), jacket)
	# arms along the edges, hands at the front corners
	for side in [-1.0, 1.0]:
		torso.draw_rect(Rect2(-1, 9.0 * side - 1.0, 9, 3), Color.BLACK)
		torso.draw_circle(Vector2(8, 9.0 * side), 2.0, Color.BLACK)
		torso.draw_circle(Vector2(8, 9.0 * side), 1.0, skin)
	if weapon != "":
		var grip := _grip()
		var tip := _tip()
		torso.draw_line(grip, tip, Color("101014"), 3.0)
		torso.draw_line(grip, tip, Color("c8c8d0"), 1.0)
	torso.draw_circle(Vector2.ZERO, 5.5, Color.BLACK)
	torso.draw_circle(Vector2.ZERO, 4.5, hair)
	torso.draw_rect(Rect2(2, -2, 2, 4), skin) # the face edge shows which way it looks
