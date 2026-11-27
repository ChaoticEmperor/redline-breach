extends Node2D
## A bloater's burst. Readable danger: a ring at the exact reach of the blast and a second ring
## closing on the centre show where and when it goes off, and the fuse leaves time to step out
## (FUSE >= REACTION + RADIUS / the player's speed, asserted by the smoke test). The blast is a
## lethal Hit for everything inside it with no wall between: the player, other enemies, glass,
## furniture and bodies alike.

const Layers = preload("res://scripts/core/layers.gd")
const Hit = preload("res://scripts/core/hit.gd")

const RADIUS := 52.0
const FUSE := 0.75
const REACTION := 0.25 # the time a player needs to notice a warning before moving
const FORCE := 480.0
const ACID := [Color("9cff3a"), Color("5fae1c"), Color("2c5a0c")]

var main
var t := 0.0
var done := false


func setup(p_main) -> void:
	main = p_main
	z_index = 9
	add_to_group("bursts")


func _physics_process(delta: float) -> void:
	if done:
		return
	t += delta
	if t >= FUSE:
		done = true
		_blast()
		queue_free()
	queue_redraw()


func _draw() -> void:
	var step := int(t * 12.0) % 2
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 48, ACID[step], 1.0)
	draw_arc(Vector2.ZERO, RADIUS * (1.0 - t / FUSE), 0, TAU, 32, ACID[1], 1.0)


func _blast() -> void:
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS
	q.shape = c
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = Layers.ACTORS | Layers.PROPS | Layers.BODIES | Layers.WORLD
	var hit_any := {}
	for r in space.intersect_shape(q, 64):
		var o = r.collider
		if not o.has_method("take_hit") or hit_any.has(o):
			continue
		var los := PhysicsRayQueryParameters2D.create(global_position, o.global_position, Layers.WORLD)
		los.exclude = [o.get_rid()]
		var wall := space.intersect_ray(los)
		if not wall.is_empty() and not (wall.collider.has_method("lets_shots_through") and wall.collider.lets_shots_through()):
			continue
		hit_any[o] = true
		var dir: Vector2 = (o.global_position - global_position).normalized()
		o.take_hit(Hit.make("blast", dir, FORCE, self, ""))
	main.sfx.play("boom")
	main.fx.add_shake(8.0)
	main.fx.flash(global_position)
	main.blood(global_position, Vector2.RIGHT, 1.6)
