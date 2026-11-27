extends CharacterBody2D
## Base class of every character (abstract: use player.gd or enemy.gd). An actor is a body
## that moves, aims, holds one Weapon and is built from components:
##   Health  decides what a Hit does (dies, or is knocked down)
##   Look    how it is drawn (the art; swap the skin to swap the art)
##   Brain   what it decides: sets move / aim / the want_* flags each physics tick
## It reacts to every Hit through take_hit(), like every other object in the world.

const Layers = preload("res://scripts/core/layers.gd")
const Hit = preload("res://scripts/core/hit.gd")
const Health = preload("res://scripts/core/health.gd")
const Look = preload("res://scripts/look.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Table = preload("res://scripts/weapons/table.gd")
const Body = preload("res://scripts/world/body.gd")
const Thrown = preload("res://scripts/world/thrown.gd")

const ACCEL_TIME := 0.1 # reaches full speed, and stops from it, in 0.1 s
const RADIUS := 9.0 # about 0.56 of a tile: a one-tile door has room either side
const NUDGE := 12.0 # how far a blocked actor is slid sideways to round a corner
const DOWN_TIME := 1.6 # a knocked-down actor gets up after this long
const DOWN_FRICTION := 900.0 # how fast a knocked-down body slides to a stop, px/s^2
const KICK_REACH := 22.0
const KICK_FORCE := 340.0
const MUZZLE := 10.0

var main
var team := "enemy"
var skin := "guard"
var speed := 192.0
var health
var look
var brain
var weapon
var aim := Vector2.RIGHT
# intent, written by the brain each tick
var move := Vector2.ZERO
var want_attack := false
var want_throw := false
var want_pickup := false
var want_kick := false
# state
var down_t := 0.0
var dead := false
var _down_sprite: Sprite2D


func setup(p_main, p_brain, p_skin: String, p_weapon := "unarmed", ammo := -1) -> void:
	main = p_main
	skin = p_skin
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = Layers.ACTORS
	collision_mask = Layers.WORLD | Layers.PROPS | Layers.ACTORS
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	health = Health.new()
	health.died.connect(_on_died)
	health.knocked.connect(_on_knocked)
	add_child(health)
	look = Look.new()
	look.skin = skin
	add_child(look)
	brain = p_brain
	add_child(brain)
	add_to_group("actors")
	z_index = 2 # the living draw over bodies, blood and props
	equip(Weapon.make(p_weapon, ammo))


func equip(w) -> void:
	weapon = w
	if look:
		look.set_weapon(w.art())


func is_down() -> bool:
	return down_t > 0.0


func is_armed() -> bool:
	return weapon.is_gun() and weapon.ammo > 0


func _physics_process(delta: float) -> void:
	if dead:
		return
	weapon.tick(delta)
	if is_down():
		_down_tick(delta)
		return
	brain.think(self, delta)
	velocity = velocity.move_toward(move.limit_length(2.0) * speed, speed * maxf(move.length(), 1.0) / ACCEL_TIME * delta)
	move_and_slide()
	_push_props()
	_round_corner(move, delta)
	if want_kick:
		kick()
	if want_pickup:
		take_pickup()
	if want_throw:
		if weapon.name in ["unarmed", "claws"]:
			take_pickup()
		else:
			throw_weapon()
	if want_attack:
		weapon.use(self)
	want_kick = false
	want_pickup = false
	want_throw = false
	look.set_aim(aim)
	look.set_move(velocity, delta)


# ---------------------------------------------------------------- being hit

## Every object in the world answers a Hit; an actor dies, or is knocked down and slides.
func take_hit(hit) -> void:
	if dead:
		return
	if hit.team == team and hit.kind != "impact":
		return
	if is_down() and hit.kind in ["kick", "punch", "blunt"] and hit.source != null and hit.source != self:
		hit.kind = "blunt" # a blow on a downed actor finishes it
	velocity = hit.dir * hit.force
	health.take(hit)


func _on_knocked(hit) -> void:
	down_t = DOWN_TIME
	look.visible = false
	if _down_sprite == null:
		_down_sprite = Sprite2D.new()
		add_child(_down_sprite)
	_down_sprite.texture = main.corpse_texture(skin, "blunt", 0)
	_down_sprite.rotation = (-hit.dir).angle() # head away from the blow
	_down_sprite.visible = true
	_drop_weapon()
	main.sfx.play("kick")


func _down_tick(delta: float) -> void:
	var v := velocity
	velocity = velocity.move_toward(Vector2.ZERO, DOWN_FRICTION * delta)
	var col := move_and_collide(velocity * delta)
	if col:
		var other = col.get_collider()
		if other != null and other.has_method("take_hit") and v.length() > 120.0:
			other.take_hit(Hit.make("impact", v.normalized(), v.length() * 0.8, self, ""))
		velocity = velocity.bounce(col.get_normal()) * 0.3
	down_t -= delta
	if down_t <= 0.0:
		down_t = 0.0
		_down_sprite.visible = false
		look.visible = true


func _on_died(hit) -> void:
	dead = true
	_drop_weapon()
	var body := Body.new()
	var cause: String = hit.kind if hit.kind in ["shot", "cut"] else "blunt"
	body.setup(main, main.corpse_texture(skin, cause, main.rng.randi_range(0, 2)), hit.dir * hit.force * 1.1, hit.dir)
	body.position = global_position
	main.world.add_child(body)
	main.blood(global_position, hit.dir, 1.0 if hit.kind != "punch" else 0.4)
	main.sfx.play("die")
	main.on_actor_died(self, hit)
	if team == "player":
		# the player stays in the scene (the camera and the restart need it), out of play
		look.visible = false
		collision_layer = 0
		collision_mask = 0
	else:
		queue_free()


# ---------------------------------------------------------------- acting

func kick() -> void:
	var hit_any := false
	for t in targets_in_arc(KICK_REACH, 1.1):
		t.take_hit(Hit.make("kick", (t.global_position - global_position).normalized(), KICK_FORCE, self, team))
		hit_any = true
	main.sfx.play("kick" if hit_any else "swing", 1.0 if hit_any else 1.6)


## Things that can be hit within `reach` and `arc` radians either side of the aim, with no wall between.
func targets_in_arc(reach: float, arc: float) -> Array:
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = reach + RADIUS
	q.shape = c
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = Layers.ACTORS | Layers.PROPS | Layers.WORLD
	q.exclude = [get_rid()]
	var found := []
	for r in space.intersect_shape(q, 32):
		var t = r.collider
		if not t.has_method("take_hit") or t in found:
			continue
		var to: Vector2 = t.global_position - global_position
		if to.length() > 1.0 and absf(aim.angle_to(to)) > arc:
			continue
		var los := PhysicsRayQueryParameters2D.create(global_position, t.global_position, Layers.WORLD)
		los.exclude = [t.get_rid()]
		if space.intersect_ray(los).is_empty():
			found.append(t)
	return found


func throw_weapon() -> void:
	var t := Thrown.new()
	t.setup(main, weapon.name, weapon.ammo, aim, self)
	t.position = global_position + aim * MUZZLE
	main.world.add_child(t)
	equip(Weapon.make("unarmed"))
	main.sfx.play("swing", 0.7)


func take_pickup() -> bool:
	var best = null
	for pk in get_tree().get_nodes_in_group("pickups"):
		var d: float = pk.global_position.distance_to(global_position)
		if d <= Table.PICK_REACH + RADIUS and (best == null or d < best.global_position.distance_to(global_position)):
			best = pk
	if best == null:
		return false
	var old = weapon
	equip(Weapon.make(best.weapon, best.ammo))
	best.remove_from_group("pickups")
	best.queue_free()
	if old.info.get("drops", true) and old.name != "unarmed":
		main.drop(old.name, old.ammo, global_position, aim.angle() + PI / 2.0)
	main.sfx.play("pickup")
	return true


func _drop_weapon() -> void:
	if weapon.name != "unarmed" and weapon.info.get("drops", true):
		main.drop(weapon.name, weapon.ammo, global_position + Vector2(main.rng.randf_range(-6, 6), main.rng.randf_range(-6, 6)), main.rng.randf() * TAU)
	equip(Weapon.make("claws" if weapon.name == "claws" else "unarmed"))


## Walking into a table or a stool pushes it.
func _push_props() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var o = col.get_collider()
		if o is RigidBody2D:
			o.apply_central_impulse(-col.get_normal() * speed * 0.06)


## Walking straight into the edge of a wall or doorway slides the actor round it.
func _round_corner(mv: Vector2, delta: float) -> void:
	if mv.length() < 0.3 or get_slide_collision_count() == 0:
		return
	var dir := Vector2(signf(mv.x), 0) if absf(mv.x) > absf(mv.y) else Vector2(0, signf(mv.y))
	if absf(mv.dot(dir.orthogonal())) > 0.35 * mv.length():
		return
	var blocked := false
	for i in get_slide_collision_count():
		blocked = blocked or get_slide_collision(i).get_normal().dot(dir) < -0.7
	if not blocked:
		return
	for side in [dir.orthogonal(), -dir.orthogonal()]:
		for d in [3.0, 6.0, NUDGE]:
			var from := global_transform.translated(side * d)
			if not test_move(global_transform, side * d) and not test_move(from, dir * 4.0):
				move_and_collide(side * speed * 0.7 * delta)
				return


# ---------------------------------------------------------------- services the weapons use

func sfx(n: String) -> void:
	main.sfx.play(n)


func shake(px: float) -> void:
	if team == "player":
		main.fx.add_shake(px)


func rng() -> RandomNumberGenerator:
	return main.rng


func fx_tracer(a: Vector2, b: Vector2) -> void:
	main.fx.tracer(a, b)


func fx_flash(p: Vector2) -> void:
	main.fx.flash(p)


func make_noise(radius: float) -> void:
	main.noise(global_position, radius, self)
