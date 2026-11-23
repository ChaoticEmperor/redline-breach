extends CharacterBody2D
## The player: twin-stick movement, dash, silent pipe / loud guns,
## contextual kick / execute, and the grab-break window.

const Fx = preload("res://scripts/fx.gd")
const World = preload("res://scripts/world.gd")

const SPEED := 112.0
const DASH_SPEED := 340.0
const DASH_TIME := 0.14
const DASH_CD := 0.7
const GRAB_WINDOW := 0.4
const ZOOM := 3.6 # on the 1920x1080 canvas
const WEAPONS := {
	"pipe": {"cd": 0.34, "loud": 0.0},
	"pistol": {"cd": 0.2, "pellets": 1, "spread": 0.025, "dmg": 2, "range": 420.0, "loud": 400.0, "pickup": 10},
	"shotgun": {"cd": 0.75, "pellets": 7, "spread": 0.2, "dmg": 1, "range": 200.0, "loud": 520.0, "pickup": 6},
}

var main
var world
var controls
var fx
var alive := true
var aim := Vector2.RIGHT
var weapon := "pipe"
var owned: Array = ["pipe"]
var ammo := {"pistol": 0, "shotgun": 0}
var cd := 0.0
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var grab_t := 0.0
var grab_immune := 0.0
var grabbers: Array = []
var kick_cd := 0.0
var swing_t := 0.0
var vis: Node2D
var wep: Sprite2D
var body: Sprite2D
var muzzle_light: PointLight2D
var cam: Camera2D


func setup(p_main, p_world, p_controls) -> void:
	main = p_main
	world = p_world
	controls = p_controls
	fx = world.fx
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = World.L_PLAYER
	collision_mask = World.SOLID
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	add_child(shape)
	var shadow := Sprite2D.new()
	shadow.texture = Fx.tex("shadow")
	shadow.position = Vector2(1, 2)
	add_child(shadow)
	vis = Node2D.new()
	add_child(vis)
	wep = Sprite2D.new()
	wep.centered = false
	vis.add_child(wep)
	body = Sprite2D.new()
	vis.add_child(body)
	# Flashlight beam along the aim, a small pool of light around the feet,
	# and a muzzle flash light that fires for a few frames per shot.
	var beam := PointLight2D.new()
	beam.texture = Fx.tex("cone")
	beam.texture_scale = 2.4
	beam.color = Color("fff2d0")
	beam.energy = 1.5
	vis.add_child(beam)
	var pool := PointLight2D.new()
	pool.texture = Fx.tex("light")
	pool.texture_scale = 1.6
	pool.energy = 0.9
	add_child(pool)
	muzzle_light = PointLight2D.new()
	muzzle_light.texture = Fx.tex("light")
	muzzle_light.texture_scale = 4.0
	muzzle_light.color = Color("ffc060")
	muzzle_light.energy = 0.0
	add_child(muzzle_light)
	cam = Camera2D.new()
	cam.zoom = Vector2(ZOOM, ZOOM)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = world.L.w * World.T
	cam.limit_bottom = world.L.h * World.T
	add_child(cam)
	_set_weapon("pipe")


func _ready() -> void:
	cam.make_current()
	cam.reset_smoothing()


func _process(delta: float) -> void:
	var look := aim * 26.0 if alive else Vector2.ZERO
	var jitter: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * fx.shake
	cam.offset = cam.offset.lerp(look, minf(1.0, delta * 6.0)) + jitter
	cam.zoom = Vector2.ONE * ZOOM * (1.0 + fx.punch)
	muzzle_light.energy = maxf(0.0, muzzle_light.energy - delta * 40.0)
	var swing := 0.0
	if swing_t > 0.0:
		swing_t -= delta
		swing = lerpf(1.3, -1.3, clampf(swing_t / 0.16, 0.0, 1.0))
	# With a full-body weapon sprite the whole figure swings; otherwise only
	# the separate procedural weapon does.
	wep.rotation = swing
	body.rotation = swing * 0.6 if not wep.visible else 0.0


func _physics_process(delta: float) -> void:
	if not alive:
		return
	cd = maxf(0.0, cd - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	kick_cd = maxf(0.0, kick_cd - delta)
	grab_immune = maxf(0.0, grab_immune - delta)

	if grab_t > 0.0:
		grab_t -= delta
		vis.position = Vector2(randf_range(-1, 1), randf_range(-1, 1))
		var kicked: bool = controls.take("kick")
		var dashed: bool = controls.take("dash")
		if kicked or dashed:
			_break_grab()
		elif grab_t <= 0.0:
			die("GRABBED")
		return
	vis.position = Vector2.ZERO

	var mv: Vector2 = controls.move
	var av: Vector2 = controls.aim
	if av.length() > 0.2:
		aim = av.normalized()
	elif controls.touch_mode and mv.length() > 0.3:
		aim = mv.normalized()
	vis.rotation = aim.angle()

	if controls.take("dash") and dash_cd <= 0.0:
		dash_dir = mv.normalized() if mv.length() > 0.2 else aim
		dash_t = DASH_TIME
		dash_cd = DASH_CD
		fx.play("dash")
	if dash_t > 0.0:
		dash_t -= delta
		velocity = dash_dir * DASH_SPEED
	else:
		velocity = mv.limit_length(1.0) * SPEED
	move_and_slide()
	if dash_t > 0.0:
		# Dashing bursts through doors and windows.
		for i in get_slide_collision_count():
			var col = get_slide_collision(i).get_collider()
			if col == null:
				continue
			if col.has_meta("door"):
				world.kick_door(col.get_meta("door"), dash_dir)
			elif col.has_meta("glass"):
				world.break_glass(col.get_meta("glass"))

	if controls.take("swap"):
		_swap()
	if controls.take("kick"):
		_action()
	if controls.fire:
		_fire()

	var got: String = world.take_pickup(global_position)
	if got != "":
		give(got)
	if world.exit_open and world.exit_rect.has_point(global_position):
		main.floor_cleared()


# ---------------------------------------------------------------- weapons

func give(kind: String) -> void:
	if not owned.has(kind):
		owned.append(kind)
	ammo[kind] += WEAPONS[kind].pickup
	_set_weapon(kind)
	fx.play("pickup")
	fx.popup(global_position + Vector2(0, -12), kind.to_upper(), Fx.CYAN)


func _set_weapon(kind: String) -> void:
	weapon = kind
	body.texture = Fx.tex("player_" + kind)
	body.scale = Vector2.ONE * Fx.sprite_scale("player_" + kind)
	wep.visible = not Fx.has_sprite("player_" + kind)
	wep.texture = Fx.tex("w_" + kind)
	wep.position = Vector2(3, 3)


func _swap() -> void:
	var i := owned.find(weapon)
	for k in owned.size():
		i = (i + 1) % owned.size()
		if owned[i] == "pipe" or ammo[owned[i]] > 0:
			_set_weapon(owned[i])
			return


func _fire() -> void:
	if cd > 0.0:
		return
	var w: Dictionary = WEAPONS[weapon]
	cd = w.cd
	if weapon == "pipe":
		_swing()
		return
	if ammo[weapon] <= 0:
		fx.play("empty")
		_set_weapon("pipe")
		return
	ammo[weapon] -= 1
	var muzzle := global_position + aim * 9.0
	for i in w.pellets:
		_bullet(muzzle, aim.rotated(randf_range(-w.spread, w.spread)), w.range, w.dmg)
	fx.casing(global_position)
	fx.flash(muzzle + aim * 3.0)
	muzzle_light.energy = 2.5
	fx.play(weapon)
	fx.add_shake(5.0 if weapon == "shotgun" else 2.5)
	fx.add_punch(0.05 if weapon == "shotgun" else 0.025)
	main.shots += 1
	world.noise(global_position, w.loud)
	if ammo[weapon] <= 0:
		_set_weapon("pipe")


func _bullet(muzzle: Vector2, dir: Vector2, reach: float, dmg: int) -> void:
	# Cast from the body centre so a muzzle poking into a wall cannot tunnel.
	var from := global_position
	var to := from + dir * reach
	var end := to
	var exclude: Array[RID] = []
	for n in 8:
		var hit: Dictionary = world.ray(from, to, World.SOLID | World.L_ENEMY, exclude)
		if hit.is_empty():
			break
		var col = hit.collider
		if col.has_meta("glass"):
			world.break_glass(col.get_meta("glass"))
			exclude.append(hit.rid)
			continue
		end = hit.position
		if col.has_method("hit"):
			col.hit(dmg, dir, 70.0)
		else:
			fx.spark(end)
		break
	fx.tracer(muzzle, end)


func _swing() -> void:
	swing_t = 0.16
	fx.play("swing")
	var landed := false
	for e in world.enemy_list.duplicate():
		var d: Vector2 = e.global_position - global_position
		if d.length() < 28.0 and absf(aim.angle_to(d)) < 1.1 and world.los(global_position, e.global_position):
			e.hit(2, d.normalized(), 150.0)
			landed = true
	var hit: Dictionary = world.ray(global_position, global_position + aim * 24.0, World.SOLID)
	if not hit.is_empty() and hit.collider.has_meta("glass"):
		world.break_glass(hit.collider.get_meta("glass"))
	if landed:
		fx.play("hit")
		fx.add_shake(3.0)


# ---------------------------------------------------------------- kick / exec

func _exec_target():
	var best = null
	var best_d := 24.0
	for e in world.enemy_list:
		var d: float = e.global_position.distance_to(global_position)
		if e.is_down() and d < best_d:
			best = e
			best_d = d
	return best


## Label for the contextual action button.
func context() -> String:
	return "EXEC" if alive and _exec_target() != null else "KICK"


func _action() -> void:
	if kick_cd > 0.0:
		return
	kick_cd = 0.3
	var target = _exec_target()
	if target != null:
		fx.play("exec")
		fx.add_shake(4.0)
		target.execute((target.global_position - global_position).normalized())
		return
	fx.play("kick")
	for e in world.enemy_list.duplicate():
		var d: Vector2 = e.global_position - global_position
		if d.length() < 26.0 and absf(aim.angle_to(d)) < 1.0:
			e.knockdown(d.normalized())
			fx.add_shake(2.0)
	var hit: Dictionary = world.ray(global_position, global_position + aim * 24.0, World.SOLID)
	if not hit.is_empty():
		if hit.collider.has_meta("door"):
			world.kick_door(hit.collider.get_meta("door"), aim)
		elif hit.collider.has_meta("glass"):
			world.break_glass(hit.collider.get_meta("glass"))


# ---------------------------------------------------------------- grab / death

func grab(e) -> bool:
	if not alive or dash_t > 0.0 or grab_immune > 0.0:
		return false
	if grab_t <= 0.0:
		grab_t = GRAB_WINDOW
		fx.play("grab")
	if not grabbers.has(e):
		grabbers.append(e)
	return true


func _break_grab() -> void:
	grab_t = 0.0
	grab_immune = 0.7
	grabbers.clear()
	fx.play("kick")
	fx.add_shake(4.0)
	for e in world.enemy_list.duplicate():
		var d: Vector2 = e.global_position - global_position
		if d.length() < 24.0:
			e.knockdown(d.normalized() if d.length() > 0.1 else aim)


func die(cause: String) -> void:
	if not alive:
		return
	alive = false
	grab_t = 0.0
	grabbers.clear()
	velocity = Vector2.ZERO
	vis.visible = false
	fx.corpse("player", global_position, vis.rotation)
	fx.blood(global_position, Vector2.ZERO, 40, 22.0)
	fx.play("die", 0.7)
	fx.add_shake(6.0)
	main.player_died(cause)
