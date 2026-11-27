extends RigidBody2D
## A body: what an actor becomes when it dies. A physics body carrying the blow's push: it is
## thrown, spins a little, slides, and knocks into props and other actors (they get an impact
## Hit), then settles and leaves its blood. Ragdoll-like without a skeleton: impulse, collision
## and the death sprite for its cause.

const Layers = preload("res://scripts/core/layers.gd")
const Hit = preload("res://scripts/core/hit.gd")

const IMPACT_SPEED := 110.0 # slower than this it just bumps

var main
var spr: Sprite2D
var _frames: Array = [] # optional animation: textures played once over _anim_len seconds (a bloater swelling)
var _anim_len := 0.0
var _anim_t := 0.0
var _settled := false
var _vel := Vector2.ZERO # the velocity before this tick's contacts slowed it


func setup(p_main, tex: Texture2D, push: Vector2, dir: Vector2) -> void:
	main = p_main
	collision_layer = Layers.BODIES
	collision_mask = Layers.WORLD | Layers.PROPS | Layers.BODIES | Layers.ACTORS
	gravity_scale = 0.0
	mass = 1.2
	linear_damp = 3.2
	angular_damp = 6.0
	contact_monitor = true
	max_contacts_reported = 4
	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 7.0
	cap.height = 30.0
	shape.shape = cap
	shape.rotation = PI / 2.0
	add_child(shape)
	spr = Sprite2D.new()
	spr.texture = tex
	add_child(spr)
	rotation = (-dir).angle() + PI # head away from the blow
	linear_velocity = push
	_vel = push
	angular_velocity = randf_range(-2.0, 2.0)
	body_entered.connect(_on_body_entered)
	add_to_group("bodies")
	z_index = 1


func _on_body_entered(other) -> void:
	var v := _vel.length()
	if v > IMPACT_SPEED and other.has_method("take_hit"):
		other.take_hit(Hit.make("impact", _vel.normalized(), v * 0.7, self, ""))


func take_hit(hit) -> void: # kicked or shot again: pushed again
	apply_central_impulse(hit.dir * hit.force * 0.5)


## Plays `frames` once over `seconds`, holding the last (a bloater's body inflating before it bursts).
func animate(frames: Array, seconds: float) -> void:
	_frames = frames
	_anim_len = seconds
	_anim_t = 0.0
	spr.texture = frames[0]


func _physics_process(delta: float) -> void:
	if not _frames.is_empty():
		_anim_t += delta
		spr.texture = _frames[mini(int(_anim_t / _anim_len * _frames.size()), _frames.size() - 1)]
	_vel = linear_velocity
	if not _settled and linear_velocity.length() < 6.0:
		_settled = true
		main.blood(global_position, Vector2.RIGHT.rotated(rotation), 1.4)
