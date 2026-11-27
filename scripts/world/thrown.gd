extends Node2D
## A thrown weapon in flight: it spins, knocks down the first thing it hits (an impact Hit),
## and lands as a pickup when it stops.

const Table = preload("res://scripts/weapons/table.gd")
const Layers = preload("res://scripts/core/layers.gd")
const Hit = preload("res://scripts/core/hit.gd")
const PropArt = preload("res://scripts/art/prop_art.gd")

var main
var weapon := "pipe"
var ammo := 0
var dir := Vector2.RIGHT
var thrower: Node
var _t := 0.0


func setup(p_main, w: String, a: int, d: Vector2, by: Node) -> void:
	main = p_main
	weapon = w
	ammo = a
	dir = d.normalized()
	thrower = by
	var spr := Sprite2D.new()
	spr.texture = PropArt.tex("w_" + weapon)
	add_child(spr)


func _physics_process(delta: float) -> void:
	_t += delta
	rotation += Table.THROW_SPIN * delta
	var step := dir * Table.THROW_SPEED * delta
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + step, Layers.WORLD | Layers.ACTORS | Layers.PROPS | Layers.BODIES)
	if is_instance_valid(thrower):
		q.exclude = [thrower.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c = hit.collider
		if c.has_method("take_hit"):
			c.take_hit(Hit.make("impact", dir, 300.0, self, ""))
			main.sfx.play("hit")
		if c.has_method("lets_shots_through") and c.lets_shots_through():
			global_position += step # through the broken glass
			return
		global_position = hit.position - dir * 6.0
		_land()
		return
	global_position += step
	if _t >= Table.THROW_TIME:
		_land()


func _land() -> void:
	main.drop(weapon, ammo, global_position, rotation)
	queue_free()
