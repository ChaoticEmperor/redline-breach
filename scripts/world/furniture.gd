extends RigidBody2D
## Furniture: a table or a stool. Pushed by whoever walks into it, slid by blows and by flying
## bodies; heavy things move less.

const Layers = preload("res://scripts/core/layers.gd")
const PropArt = preload("res://scripts/art/prop_art.gd")

const KINDS := {"table": {"r": 12.0, "mass": 4.0}, "stool": {"r": 5.0, "mass": 1.0}}

var kind := "table"


func setup(p_kind: String) -> void:
	kind = p_kind
	collision_layer = Layers.PROPS
	collision_mask = Layers.WORLD | Layers.PROPS | Layers.ACTORS | Layers.BODIES
	gravity_scale = 0.0
	mass = KINDS[kind].mass
	linear_damp = 7.0
	angular_damp = 8.0
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = KINDS[kind].r
	shape.shape = c
	add_child(shape)
	var spr := Sprite2D.new()
	spr.texture = PropArt.tex(kind)
	add_child(spr)
	add_to_group("props")


func take_hit(hit) -> void:
	apply_central_impulse(hit.dir * hit.force * mass * 0.35)
	apply_torque_impulse(randf_range(-30.0, 30.0))
