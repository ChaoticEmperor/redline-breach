extends CharacterBody2D
## The player: moves, aims, attacks, throws and picks up weapons, and draws
## through a Look node.

const Look = preload("res://scripts/look.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Thrown = preload("res://scripts/thrown.gd")

const WALLS := 1 # physics layer bits
const BODIES := 2
const PLAYER := 4
const MUZZLE := 10.0 # art px ahead of the body where a thrown weapon leaves the hand

const SPEED := 192.0 # art px per second: 6 tiles a second
const ACCEL := SPEED / 0.1 # reaches SPEED, and stops from it, in 0.1 s (6 physics frames)
const RADIUS := 9.0 # collision: about 0.56 of a tile, so a one-tile door has room either side
const NUDGE := 12.0 # how far a blocked player is slid sideways to round a corner

var main
var controls
var aim := Vector2.RIGHT
var look
var weapon := Weapons.FISTS
var ammo := 0
var cd := 0.0 # time until the weapon can be used again
var swing_t := -1.0 # 0..1 through a melee swing, -1 when not swinging
var _struck := false


func setup(p_main, p_controls) -> void:
	main = p_main
	controls = p_controls
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = PLAYER
	collision_mask = WALLS
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

	cd = maxf(0.0, cd - delta)
	if swing_t >= 0.0:
		_swing(delta)
	# Presses are buffered by `controls`, so only take one when it can act.
	if controls.take("pickup"):
		take_pickup()
	if controls.take("throw"):
		if weapon != Weapons.FISTS:
			throw_weapon()
		else:
			take_pickup()
	if controls.fire and cd <= 0.0:
		attack()

	look.set_aim(aim)
	look.set_move(velocity, delta)
	look.weapon = weapon
	look.swing = Weapons.swing_angle(weapon, swing_t) if swing_t >= 0.0 else 0.0


func is_armed() -> bool:
	return Weapons.is_gun(weapon) and ammo > 0


## What the KICK button does here (M3 adds EXEC over a downed enemy).
func context() -> String:
	return "KICK"


func attack() -> void:
	var w := Weapons.info(weapon)
	if w.kind == "melee":
		swing_t = 0.0
		_struck = false
		cd = w.swing
		main.sfx.play("swing")
	elif ammo > 0:
		ammo -= 1
		cd = w.rate
		_shoot(w)
	else:
		cd = 0.3
		main.sfx.play("empty")


func _swing(delta: float) -> void:
	var w := Weapons.info(weapon)
	swing_t += delta / w.swing
	if not _struck and swing_t >= Weapons.STRIKE:
		_struck = true
		for body in targets_in_arc(w.reach, w.arc):
			if w.how == "punch":
				body.knockdown(aim)
			else:
				body.hit(aim, w.how)
			main.sfx.play("hit")
			main.fx.add_shake(2.0)
	if swing_t >= 1.0:
		swing_t = -1.0


## Bodies that can be hit within `reach` and `arc` radians either side of the
## aim, with no wall between.
func targets_in_arc(reach: float, arc: float) -> Array:
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = reach
	q.shape = c
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = BODIES
	var found := []
	for r in space.intersect_shape(q, 32):
		var body = r.collider
		if not body.has_method("hit"):
			continue
		var to: Vector2 = body.global_position - global_position
		if to.length() > 0.5 and absf(aim.angle_to(to)) > arc:
			continue
		var los := PhysicsRayQueryParameters2D.create(global_position, body.global_position, WALLS)
		if space.intersect_ray(los).is_empty():
			found.append(body)
	return found


func _shoot(w: Dictionary) -> void:
	var space := get_world_2d().direct_space_state
	# Cast from the body's centre (never inside a wall); draw from the muzzle.
	look.set_aim(aim)
	var muzzle: Vector2 = look.tip_global()
	var from := global_position
	for i in w.pellets:
		var dir := aim.rotated(main.rng.randf_range(-w.spread, w.spread))
		var q := PhysicsRayQueryParameters2D.create(from, from + dir * w.range, WALLS | BODIES)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		var to: Vector2 = from + dir * w.range
		if not hit.is_empty():
			to = hit.position
			if hit.collider.has_method("hit"):
				hit.collider.hit(dir, w.how)
		if to.distance_to(from) > muzzle.distance_to(from):
			main.fx.tracer(muzzle, to)
	main.fx.flash(muzzle)
	main.fx.add_shake(w.shake)
	main.sfx.play(w.sound)
	main.noise(global_position, w.noise)


func throw_weapon() -> void:
	var t := Thrown.new()
	t.setup(main, weapon, ammo, aim, self)
	t.position = global_position + aim * MUZZLE
	main.world.add_child(t)
	weapon = Weapons.FISTS
	ammo = 0
	swing_t = -1.0
	main.sfx.play("swing", 0.7)


## Takes the nearest weapon on the floor, dropping the one in hand there.
func take_pickup() -> bool:
	var best = null
	for pk in get_tree().get_nodes_in_group("pickups"):
		var d: float = pk.global_position.distance_to(global_position)
		if d <= Weapons.PICK_REACH + RADIUS and (best == null or d < best.global_position.distance_to(global_position)):
			best = pk
	if best == null:
		return false
	var old := weapon
	var old_ammo := ammo
	weapon = best.weapon
	ammo = best.ammo
	best.remove_from_group("pickups")
	best.queue_free()
	if old != Weapons.FISTS:
		main.drop(old, old_ammo, global_position, aim.angle() + PI / 2.0)
	swing_t = -1.0
	main.sfx.play("pickup")
	return true


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
