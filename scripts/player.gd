extends CharacterBody2D
## The player: moves, aims, and draws through a Look node. Weapons arrive in M2.

const Look = preload("res://scripts/look.gd")

const SPEED := 192.0 # art px per second: 6 tiles a second
const ACCEL := SPEED / 0.1 # reaches SPEED, and stops from it, in 0.1 s (6 physics frames)
const RADIUS := 9.0 # collision: about 0.56 of a tile, so a one-tile door has room either side
const NUDGE := 12.0 # how far a blocked player is slid sideways to round a corner

var controls
var aim := Vector2.RIGHT
var look


func setup(p_controls) -> void:
	controls = p_controls
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	look = Look.new()
	add_child(look)


func _physics_process(delta: float) -> void:
	var mv: Vector2 = controls.move
	var av: Vector2 = controls.aim
	if av.length() > 0.2:
		aim = av.normalized()
	elif controls.touch_mode and mv.length() > 0.3:
		aim = mv.normalized() # no aim on touch: face where we walk (M3 adds auto-aim)
	velocity = velocity.move_toward(mv.limit_length(1.0) * SPEED, ACCEL * delta)
	move_and_slide()
	_round_corner(mv, delta)
	look.set_aim(aim)
	look.set_move(velocity, delta)


## Walking straight into the edge of a wall or doorway slides the player
## sideways round it instead of stopping them dead (matters most on a touch stick).
func _round_corner(mv: Vector2, delta: float) -> void:
	if mv.length() < 0.3 or get_slide_collision_count() == 0:
		return
	var dir := Vector2(signf(mv.x), 0) if absf(mv.x) > absf(mv.y) else Vector2(0, signf(mv.y))
	if absf(mv.dot(dir.orthogonal())) > 0.35 * mv.length():
		return # steering diagonally already: the slide along the wall does the job
	var blocked := false
	for i in get_slide_collision_count():
		blocked = blocked or get_slide_collision(i).get_normal().dot(dir) < -0.7
	if not blocked:
		return
	for side in [dir.orthogonal(), -dir.orthogonal()]:
		for d in [3.0, 6.0, NUDGE]:
			var from := global_transform.translated(side * d)
			if not test_move(global_transform, side * d) and not test_move(from, dir * 4.0):
				move_and_collide(side * SPEED * 0.7 * delta)
				return
