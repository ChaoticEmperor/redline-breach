extends CharacterBody2D
## The player: 3/4-view animated body that flips to face the aim. The weapon
## is held in the body's front fist and turns about its grip; the fist is drawn
## again on top of it so the hand closes over the grip (draw order: body,
## weapon, hand). Movement, dash, silent pipe / loud guns,
## contextual kick / execute, and the grab-break window.

const Fx = preload("res://scripts/fx.gd")
const World = preload("res://scripts/world.gd")

const SPEED := 112.0
const DASH_SPEED := 340.0
const DASH_TIME := 0.14
const DASH_CD := 0.7
const GRAB_WINDOW := 0.4
const ZOOM := 6.0 # on the 1920x1080 canvas
var art: Dictionary # sheet layout and scale, see Fx.art()
var shoulder := Vector2(0, -13) # chest height, relative to the feet: where shots land on a body
var hold := Vector2(0, -13) # where the weapon is held, relative to the feet: the fist, else the shoulder
var grips := false # the weapon sits in the fist (Fx.can_grip()); otherwise it floats at the shoulder
const HELD := {"pipe": 0.34, "pistol": 0.3, "shotgun": 0.36} # weapon sprite scale when it is not gripped
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
var kick_t := 0.0
var swing_t := 0.0
var recoil := 0.0
var ghost_t := 0.0
var body: AnimatedSprite2D
var arm: Node2D
var wep: Sprite2D
var hand: Sprite2D # the front fist, over the weapon
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
	add_child(shadow)
	body = AnimatedSprite2D.new()
	art = Fx.art("player")
	shoulder = Vector2(0, -art.shoulder * art.scale)
	body.sprite_frames = Fx.frames("player")
	body.scale = Vector2.ONE * art.scale
	body.offset = Vector2(0, art.cell / 2.0 - art.feet) # the feet row sits on the node
	body.modulate = world.actor_tint(1.0)
	body.light_mask = 2 # actors keep their own colours; see World.actor_tint()
	body.play("idle")
	add_child(body)
	arm = Node2D.new()
	arm.position = shoulder
	add_child(arm)
	wep = Sprite2D.new()
	wep.modulate = world.actor_tint(1.0)
	wep.light_mask = 2
	arm.add_child(wep)
	grips = Fx.can_grip()
	if grips:
		# Same sheet layout, scale, tint and light layer as the body, so the two cannot drift apart.
		hand = Sprite2D.new()
		hand.texture = Fx.tex("player_v3_hand")
		hand.hframes = hand.texture.get_width() / int(art.cell)
		hand.scale = body.scale
		hand.offset = body.offset
		hand.modulate = body.modulate
		hand.light_mask = 2
		add_child(hand)
		# The body advances its own frames after this node's _process; follow at once, not a frame late.
		body.frame_changed.connect(_hold)
	# Flashlight beam along the aim, a small pool of light around the body,
	# and a muzzle flash light that fires for a few frames per shot.
	var beam := PointLight2D.new()
	beam.texture = Fx.tex("cone")
	beam.texture_scale = 2.6
	beam.color = Color("fff2d0")
	beam.energy = 1.6
	arm.add_child(beam)
	var pool := PointLight2D.new()
	pool.texture = Fx.tex("light")
	pool.texture_scale = 1.8
	pool.color = Color("ffd6f2")
	pool.energy = 1.0
	pool.position = shoulder
	add_child(pool)
	muzzle_light = PointLight2D.new()
	muzzle_light.texture = Fx.tex("light")
	muzzle_light.texture_scale = 4.5
	muzzle_light.color = Color("ffc060")
	muzzle_light.energy = 0.0
	muzzle_light.range_item_cull_mask = 3 # a shot lights the actors as well as the room
	muzzle_light.position = shoulder
	add_child(muzzle_light)
	cam = Camera2D.new()
	add_child(cam)
	_set_weapon("pipe")
	_hold()


func _ready() -> void:
	cam.make_current()
	cam.reset_smoothing()


func _process(delta: float) -> void:
	var look := aim * 26.0 if alive else Vector2.ZERO
	var jitter: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * fx.shake
	cam.offset = cam.offset.lerp(look, minf(1.0, delta * 6.0)) + jitter + fx.kick
	# Zoom follows the short screen side so portrait and landscape show the
	# same amount of room; if the view is larger than the floor, centre it.
	var screen := get_viewport().get_visible_rect().size
	var zoom := ZOOM * minf(screen.x, screen.y) / 1080.0
	cam.zoom = Vector2.ONE * zoom * (1.0 + fx.punch)
	var floor_size := Vector2(world.L.w, world.L.h) * World.T
	var spare := ((screen / zoom - floor_size) / 2.0).max(Vector2.ZERO)
	cam.limit_left = -int(spare.x)
	cam.limit_top = -int(spare.y)
	cam.limit_right = int(floor_size.x + spare.x)
	cam.limit_bottom = int(floor_size.y + spare.y)

	muzzle_light.energy = maxf(0.0, muzzle_light.energy - delta * 40.0)
	recoil = maxf(0.0, recoil - delta * 40.0)
	kick_t = maxf(0.0, kick_t - delta)
	if not alive:
		return
	body.flip_h = aim.x < 0.0
	arm.rotation = aim.angle()
	wep.flip_v = aim.x < 0.0
	if swing_t > 0.0:
		swing_t -= delta
		wep.rotation = lerpf(1.4, -1.4, clampf(swing_t / 0.16, 0.0, 1.0)) * (-1.0 if wep.flip_v else 1.0)
	else:
		wep.rotation = 0.0
	var anim := "idle"
	if kick_t > 0.0:
		anim = "kick"
	elif velocity.length() > 12.0:
		anim = "run"
	if body.animation != anim:
		body.play(anim)
	_hold()


## Puts the weapon in the fist of the frame being shown and the fist over it.
func _hold() -> void:
	if not grips:
		hold = shoulder
		arm.position = shoulder - aim * recoil
		return
	var cell: int = Fx.PLAYER_V3[body.animation][0] + body.frame
	var at: Vector2 = Fx.hand_anchors()[cell]
	hand.frame = cell
	hand.flip_h = body.flip_h
	hand.position = body.position
	hand.visible = at != Vector2.INF
	arm.visible = hand.visible
	if not hand.visible:
		return
	# Whole sheet pixels, so the weapon stays on the body's pixel grid.
	var px := Vector2(floorf(at.x) + 0.5 - art.cell / 2.0, floorf(at.y) + 0.5 - art.feet)
	if body.flip_h:
		px.x = -px.x
	hold = px * art.scale + body.position
	# The fist stays put, so the weapon only slides a pixel or two in it on recoil.
	arm.position = hold - aim * recoil * 0.25
	var grip: Vector2 = Fx.HELD_GRIP[weapon] + Vector2(0.5, 0.5)
	if wep.flip_v:
		grip.y = wep.texture.get_height() - grip.y
	wep.offset = -grip


func _physics_process(delta: float) -> void:
	if not alive:
		return
	cd = maxf(0.0, cd - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	kick_cd = maxf(0.0, kick_cd - delta)
	grab_immune = maxf(0.0, grab_immune - delta)

	if grab_t > 0.0:
		grab_t -= delta
		velocity = Vector2.ZERO
		body.position = Vector2(randf_range(-1, 1), randf_range(-1, 1))
		var kicked: bool = controls.take("kick")
		var dashed: bool = controls.take("dash")
		if kicked or dashed:
			_break_grab()
		elif grab_t <= 0.0:
			die("GRABBED")
		return
	body.position = Vector2.ZERO

	var mv: Vector2 = controls.move
	var av: Vector2 = controls.aim
	if av.length() > 0.2:
		aim = av.normalized()
	elif controls.touch_mode:
		# No aim stick on touch: face the nearest threat while attacking,
		# otherwise face where we are walking.
		var target = _nearest(190.0 if weapon != "pipe" else 44.0) if controls.fire else null
		if target != null:
			aim = (target.global_position - global_position).normalized()
		elif mv.length() > 0.3:
			aim = mv.normalized()

	# Presses are buffered by `controls`, so only take one when it can act.
	if dash_cd <= 0.0 and controls.take("dash"):
		dash_dir = mv.normalized() if mv.length() > 0.2 else aim
		dash_t = DASH_TIME
		dash_cd = DASH_CD
		ghost_t = 0.0
		fx.play("dash")
	if dash_t > 0.0:
		dash_t -= delta
		velocity = dash_dir * DASH_SPEED
		ghost_t -= delta
		if ghost_t <= 0.0:
			ghost_t = 0.03
			fx.ghost(body.sprite_frames.get_frame_texture(body.animation, body.frame), global_position, body.flip_h,
					art.cell * art.scale / 2.0, (art.feet - art.cell / 2.0) * art.scale)
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
	if kick_cd <= 0.0 and controls.take("kick"):
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
	fx.popup(global_position + Vector2(0, -26), kind.to_upper(), Fx.CYAN)


func _set_weapon(kind: String) -> void:
	weapon = kind
	if grips:
		# Drawn at the body's pixel size; _hold() sets the offset so the grip sits in the fist.
		wep.texture = Fx.tex("held_" + kind)
		wep.centered = false
		wep.scale = Vector2.ONE * art.scale
		return
	# No fist art: the side-view weapon floats at the shoulder, its grip on the pivot.
	wep.texture = Fx.tex("hud_" + kind)
	wep.scale = Vector2.ONE * HELD[kind] * (1.0 if Fx.has_sprite("hud_" + kind) else 3.0)
	wep.offset = Vector2(wep.texture.get_width() * 0.32, 0)


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
	var heavy := weapon == "shotgun"
	var reach: float = (wep.texture.get_width() - Fx.HELD_GRIP[weapon].x) * art.scale if grips else 13.0
	var muzzle := global_position + hold + aim * reach
	for i in w.pellets:
		_bullet(muzzle, aim.rotated(randf_range(-w.spread, w.spread)), w.range, w.dmg)
	fx.casing(global_position + hold, aim)
	fx.flash(muzzle)
	muzzle_light.energy = 2.5
	recoil = 5.0 if heavy else 3.0
	fx.play(weapon)
	fx.add_shake(5.0 if heavy else 2.5)
	fx.add_punch(0.05 if heavy else 0.025)
	fx.add_kick(-aim * (5.0 if heavy else 2.5))
	main.shots += 1
	world.noise(global_position, w.loud)
	if ammo[weapon] <= 0:
		_set_weapon("pipe")


func _bullet(muzzle: Vector2, dir: Vector2, reach: float, dmg: int) -> void:
	# Cast along the floor from the feet so a muzzle poking into a wall
	# cannot tunnel; the tracer is drawn at chest height.
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
			col.hit(dmg, dir, 70.0, weapon != "pistol")
		else:
			fx.spark(end + shoulder)
		break
	fx.tracer(muzzle, end + shoulder)


func _swing() -> void:
	swing_t = 0.16
	fx.play("swing")
	fx.slash(global_position + hold, aim.angle())
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
		fx.add_kick(aim * 3.0)
		main.hitstop()


# ---------------------------------------------------------------- kick / exec

## Closest standing zombie in sight within `reach`, or null.
func _nearest(reach: float):
	var best = null
	var best_d := reach
	for e in world.enemy_list:
		var d: float = e.global_position.distance_to(global_position)
		if d < best_d and not e.is_down() and world.los(global_position, e.global_position):
			best = e
			best_d = d
	return best


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
	kick_cd = 0.3
	kick_t = 0.18
	var target = _exec_target()
	if target != null:
		fx.play("exec")
		fx.add_shake(4.0)
		main.hitstop()
		target.execute((target.global_position - global_position).normalized())
		return
	fx.play("kick")
	if controls.touch_mode and controls.aim == Vector2.ZERO:
		var close = _nearest(26.0)
		if close != null:
			aim = (close.global_position - global_position).normalized()
	for e in world.enemy_list.duplicate():
		var d: Vector2 = e.global_position - global_position
		if d.length() < 26.0 and absf(aim.angle_to(d)) < 1.0:
			e.knockdown(d.normalized())
			fx.add_shake(2.0)
			fx.add_kick(aim * 3.0)
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
	kick_t = 0.18
	grabbers.clear()
	fx.play("kick")
	fx.add_shake(4.0)
	for e in world.enemy_list.duplicate():
		var d: Vector2 = e.global_position - global_position
		if d.length() < 24.0:
			e.knockdown(d.normalized() if d.length() > 0.1 else aim)


func die(cause: String) -> void:
	if not alive or dash_t > 0.0: # a dash is briefly invulnerable
		return
	alive = false
	grab_t = 0.0
	grabbers.clear()
	velocity = Vector2.ZERO
	body.position = Vector2.ZERO
	body.play("death")
	arm.visible = false
	if hand != null:
		hand.visible = false
	fx.blood(global_position, Vector2.ZERO, 40, 22.0)
	fx.pool(global_position)
	fx.play("die", 0.7)
	fx.add_shake(6.0)
	main.player_died(cause)
