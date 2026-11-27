extends RigidBody2D
## A door on a hinge. Pushed open by whoever walks through; a kick or a flying body swings it
## hard, and a door swinging fast knocks down whoever it hits.

const Layers = preload("res://scripts/core/layers.gd")
const Hit = preload("res://scripts/core/hit.gd")
const PropArt = preload("res://scripts/art/prop_art.gd")

const LENGTH := 28.0
const KNOCK_SPIN := 6.0 # radians per second: faster than this, the door knocks people down

var main
var _hinge: StaticBody2D


## `hinge` is the hinge point; the door lies along +x from it (rotated by `angle`).
func setup(p_main, angle: float) -> void:
	main = p_main
	collision_layer = Layers.PROPS
	collision_mask = Layers.ACTORS | Layers.BODIES | Layers.PROPS
	gravity_scale = 0.0
	mass = 2.0
	angular_damp = 3.0
	linear_damp = 20.0
	contact_monitor = true
	max_contacts_reported = 4
	rotation = angle
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(LENGTH, 4)
	shape.shape = r
	shape.position = Vector2(LENGTH / 2.0, 0)
	add_child(shape)
	var spr := Sprite2D.new()
	spr.texture = PropArt.tex("door")
	spr.position = Vector2(LENGTH / 2.0, 0)
	add_child(spr)
	body_entered.connect(_on_body_entered)
	add_to_group("props")


## Pins the door to a fixed hinge point; call once it is in the tree.
func attach_hinge() -> void:
	_hinge = StaticBody2D.new()
	_hinge.collision_layer = 0
	_hinge.position = position
	get_parent().add_child(_hinge)
	var j := PinJoint2D.new()
	j.position = position
	j.softness = 0.0
	get_parent().add_child(j)
	j.node_a = j.get_path_to(_hinge)
	j.node_b = j.get_path_to(self)


func take_hit(hit) -> void:
	# push at the free end, so a kick swings it on its hinge
	var tip := global_position + Vector2.RIGHT.rotated(rotation) * LENGTH
	apply_impulse(hit.dir * hit.force * 0.6, tip - global_position)


func _on_body_entered(other) -> void:
	if absf(angular_velocity) > KNOCK_SPIN and other.has_method("take_hit") and other.get("team") != null:
		var push: Vector2 = (other.global_position - global_position).normalized()
		other.take_hit(Hit.make("impact", push, 260.0, self, ""))
