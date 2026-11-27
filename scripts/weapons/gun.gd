extends "res://scripts/weapons/weapon.gd"
## Gun: casts its pellets from the body's centre along the aim (seeded spread), so a muzzle
## against a wall never shoots through it. Glass is broken and passed through; anything else
## that can be hit stops the pellet. Loud: every shot is a noise enemies hear.

const Hit = preload("res://scripts/core/hit.gd")
const Layers = preload("res://scripts/core/layers.gd")


func is_gun() -> bool:
	return true


func use(actor) -> bool:
	if not ready():
		return false
	if ammo <= 0:
		cooldown = 0.3
		actor.sfx("empty")
		return false
	ammo -= 1
	cooldown = info.rate
	actor.look.attack()
	var space: PhysicsDirectSpaceState2D = actor.get_world_2d().direct_space_state
	var from: Vector2 = actor.global_position
	var muzzle: Vector2 = actor.look.tip_global()
	for i in info.pellets:
		var dir: Vector2 = actor.aim.rotated(actor.rng().randf_range(-info.spread, info.spread))
		var exclude := [actor.get_rid()]
		var to: Vector2 = from + dir * info.range
		for hop in 4: # pass through broken glass
			var q := PhysicsRayQueryParameters2D.create(from, from + dir * info.range, Layers.SHOTS)
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			to = hit.position
			var c = hit.collider
			if c.has_method("take_hit"):
				c.take_hit(Hit.make(info.how, dir, info.force, actor, actor.team))
			if c.has_method("lets_shots_through") and c.lets_shots_through():
				exclude.append(c.get_rid())
				to = from + dir * info.range
				continue
			break
		actor.fx_tracer(muzzle, to)
	actor.fx_flash(muzzle)
	actor.shake(info.shake)
	actor.sfx(info.sound)
	actor.make_noise(info.noise)
	return true
