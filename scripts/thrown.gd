extends Node2D
## A thrown weapon in flight: it spins, knocks down the first body it hits,
## stops at a wall, and lands as a pickup when it stops.

const Weapons = preload("res://scripts/weapons.gd")

const BODIES := 2 # physics layer of enemies (and anything else that can be hit)
const WALLS := 1

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


func _physics_process(delta: float) -> void:
	_t += delta
	rotation += Weapons.THROW_SPIN * delta
	var step := dir * Weapons.THROW_SPEED * delta
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + step, WALLS | (1 << (BODIES - 1)))
	if thrower is CollisionObject2D:
		q.exclude = [thrower.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var body = hit.collider
		if body.has_method("knockdown"):
			body.knockdown(dir)
			main.sfx.play("hit")
		else:
			main.sfx.play("kick", 1.4)
		global_position = hit.position - dir * 6.0
		_land()
		return
	global_position += step
	if _t >= Weapons.THROW_TIME:
		_land()


func _land() -> void:
	main.drop(weapon, ammo, global_position, rotation)
	queue_free()


func _draw() -> void:
	var half: float = Weapons.info(weapon).length / 2.0
	draw_rect(Rect2(-half - 1, -2, half * 2 + 2, 4), Color("101014"))
	draw_rect(Rect2(-half, -1, half * 2, 2), Color("c8c8d0"))
