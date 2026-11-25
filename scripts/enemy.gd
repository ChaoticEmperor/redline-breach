extends CharacterBody2D
## The infected, drawn in 3/4 view with walk / lunge / downed frames.
## Shambler: slow, grabs. Runner: fast, fragile, grabs. Bloater: slow, tanky,
## swells and bursts into acid on contact or death. Riot guard: armoured;
## pistol rounds bounce off its front, so flank it, kick it over, or use the
## pipe or shotgun.

const Fx = preload("res://scripts/fx.gd")
const World = preload("res://scripts/world.gd")

enum { IDLE, INVESTIGATE, CHASE, DOWN, FUSE }

const SIGHT := 150.0
const BLAST := 44.0
const REACTION := 0.25 # time a player needs to notice a warning before moving
## Time from the fuse lighting to the burst: reacting, then walking out of BLAST from contact.
const FUSE_TIME := 0.65
const ACID := Color("b8ff40")
const NOTICE := 0.25 # the beat between spotting the player and going for them
const ACTOR_LIGHT := 2 # light layer for actors; room lights only reach layer 1
const STATS := {
	"shambler": {"hp": 2, "speed": 40.0, "r": 5.0, "score": 100, "size": 1.0},
	"runner": {"hp": 1, "speed": 98.0, "r": 4.5, "score": 150, "size": 1.0},
	"bloater": {"hp": 5, "speed": 26.0, "r": 7.0, "score": 250, "size": 1.0},
	"riot": {"hp": 6, "speed": 34.0, "r": 5.5, "score": 400, "size": 1.0},
}

var main
var world
var player
var fx
var kind := "shambler"
var hp := 1
var speed := 40.0
var radius := 5.0
var state := IDLE
var dead := false
var target := Vector2.ZERO
var last_seen := Vector2.ZERO
var facing := Vector2.RIGHT
var sees := false
var lost_t := 0.0
var think_t := 0.0
var route := PackedVector2Array()
var route_i := 0
var repath_t := 0.0
var down_t := 0.0
var fuse_t := 0.0
var bash_t := 0.0
var stagger_t := 0.0
var knock := Vector2.ZERO
var wander := Vector2.ZERO
var wander_t := 0.0
var body: AnimatedSprite2D
var base_scale := 0.5
var lit := Color.WHITE # the body's normal modulate: its own colours, unaffected by room lights
var skin := "shambler"
var notice_t := 0.0


func setup(p_main, p_world, p_player, p_kind: String) -> void:
	main = p_main
	world = p_world
	player = p_player
	fx = world.fx
	kind = p_kind
	var st: Dictionary = STATS[kind]
	hp = st.hp
	speed = st.speed * randf_range(0.9, 1.1)
	radius = st.r
	facing = Vector2.RIGHT if randf() < 0.5 else Vector2.LEFT
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = World.L_ENEMY
	collision_mask = World.SOLID
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	var shadow := Sprite2D.new()
	shadow.texture = Fx.tex("shadow")
	shadow.scale = Vector2.ONE * (radius / 5.0)
	add_child(shadow)
	base_scale = Fx.ART_SCALE * st.size
	body = AnimatedSprite2D.new()
	# Shamblers come in two looks; the club's dancefloor crowd is the second.
	skin = "horde" if kind == "shambler" and randf() < 0.5 else kind
	body.sprite_frames = Fx.frames(skin)
	body.scale = Vector2.ONE * base_scale
	body.offset = Vector2(0, -28) # feet (row 60 of the 64px cell) sit on the node
	lit = world.actor_tint()
	body.modulate = lit
	body.light_mask = ACTOR_LIGHT
	body.play("walk")
	body.frame = randi() % 4
	add_child(body)
	think_t = randf() * 0.2
	world.enemy_list.append(self)


func is_down() -> bool:
	return state == DOWN and not dead


func _pose(anim: String, moving := true) -> void:
	if body.animation != anim:
		body.play(anim)
	if anim == "walk":
		body.speed_scale = 1.0 if moving else 0.0
	body.flip_h = facing.x < 0.0


func _physics_process(delta: float) -> void:
	if dead:
		return
	knock = knock.move_toward(Vector2.ZERO, 500.0 * delta)
	if state == DOWN:
		down_t -= delta
		velocity = knock
		move_and_slide()
		_pose("down")
		if down_t <= 0.0:
			state = CHASE
			body.modulate = lit
		return
	if state == FUSE:
		fuse_t -= delta
		var k := fuse_progress()
		body.scale = Vector2.ONE * base_scale * (1.0 + k * 0.5)
		body.modulate = lit.lerp(lit * Color(2.2, 1.4, 0.6), k)
		if fuse_t <= 0.0:
			_explode()
		return

	var pp: Vector2 = player.global_position
	var to_p := pp - global_position
	var dist := to_p.length()
	stagger_t = maxf(0.0, stagger_t - delta)

	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.2
		sees = player.alive and dist < SIGHT and world.los(global_position, pp)
		if sees:
			last_seen = pp
			lost_t = 0.0
			if state != CHASE:
				alert()
				if state == CHASE:
					# Spotted, not yet lunging: a readable beat so a grab never comes from nowhere.
					notice_t = NOTICE
					fx.popup(global_position + Vector2(0, -30), "!", Color("f9f002"))
		elif state == CHASE:
			lost_t += 0.2
			if lost_t > 4.0 or not player.alive:
				state = INVESTIGATE
				target = last_seen

	var want := Vector2.ZERO
	var grabbing := false
	match state:
		IDLE:
			wander_t -= delta
			if wander_t <= 0.0:
				wander_t = randf_range(1.0, 3.0)
				wander = Vector2.RIGHT.rotated(randf() * TAU) * 0.3 if randf() < 0.5 else Vector2.ZERO
			want = wander
		INVESTIGATE:
			want = _follow(target, delta)
			if global_position.distance_to(target) < 14.0:
				state = IDLE
		CHASE:
			grabbing = player.grab_t > 0.0 and player.grabbers.has(self)
			if notice_t > 0.0:
				notice_t -= delta
				facing = to_p / maxf(dist, 0.01)
				velocity = knock
				_pose("walk", false)
				move_and_slide()
				return
			if grabbing:
				want = Vector2.ZERO
			elif sees and dist < 90.0:
				want = to_p / maxf(dist, 0.01)
			else:
				want = _follow(pp, delta)
			if player.alive and dist < radius + 8.0:
				if kind == "bloater":
					_start_fuse()
					return
				player.grab(self)

	if state != IDLE:
		for o in world.enemy_list:
			if o != self:
				var d: Vector2 = global_position - o.global_position
				var l := d.length_squared()
				if l < 144.0 and l > 0.01:
					want += d.normalized() * 0.5
	velocity = want * speed * (0.3 if stagger_t > 0.0 else 1.0) + knock
	if want.length() > 0.1:
		facing = want.normalized()
	elif state == CHASE and dist > 0.1:
		facing = to_p / dist
	_pose("lunge" if grabbing or (state == CHASE and dist < 26.0) else "walk", want.length() > 0.05)
	move_and_slide()

	# Alerted zombies batter down doors and smash through glass in their way.
	var blocked := false
	if state != IDLE:
		for i in get_slide_collision_count():
			var col = get_slide_collision(i).get_collider()
			if col == null:
				continue
			if col.has_meta("door"):
				blocked = true
				bash_t += delta
				if bash_t > 0.6:
					bash_t = 0.0
					world.kick_door(col.get_meta("door"), want, false)
			elif col.has_meta("glass") and state == CHASE:
				blocked = true
				bash_t += delta
				if bash_t > 0.3:
					bash_t = 0.0
					world.break_glass(col.get_meta("glass"))
	if not blocked:
		bash_t = maxf(0.0, bash_t - delta)


func _follow(dest: Vector2, delta: float) -> Vector2:
	repath_t -= delta
	if repath_t <= 0.0:
		repath_t = randf_range(0.4, 0.6)
		route = world.path(global_position, dest)
		route_i = 1
	while route_i < route.size() and global_position.distance_to(route[route_i]) < 5.0:
		route_i += 1
	var goal := route[route_i] if route_i < route.size() else dest
	var d := goal - global_position
	return d.normalized() if d.length() > 2.0 else Vector2.ZERO


# ---------------------------------------------------------------- reactions

func hear(pos: Vector2) -> void:
	if dead or state == CHASE or state == DOWN or state == FUSE:
		return
	state = INVESTIGATE
	target = pos
	repath_t = 0.0


func alert() -> void:
	if dead or state == CHASE or state == DOWN or state == FUSE:
		return
	state = CHASE
	repath_t = 0.0
	if randf() < 0.5:
		fx.play("groan", randf_range(0.8, 1.3), -12.0)
	for o in world.enemy_list:
		if o != self and o.state == IDLE and o.global_position.distance_to(global_position) < 70.0:
			o.alert()


## `pierce` is false for light rounds, which riot armour stops from the front.
func hit(dmg: int, dir: Vector2, kb := 0.0, pierce := true) -> void:
	if dead:
		return
	if kind == "riot" and not pierce and state != DOWN and dir.dot(facing) < -0.2:
		fx.spark(global_position + Vector2(0, -11))
		fx.play("empty", 0.5, -4.0)
		fx.popup(global_position + Vector2(0, -28), "ARMOR", Fx.CYAN)
		alert()
		return
	hp -= dmg
	knock = dir * kb
	fx.blood(global_position, dir, 5 + dmg * 3)
	if hp <= 0:
		_die(dir)
	else:
		stagger_t = 0.25
		alert()


func knockdown(dir: Vector2) -> void:
	if dead or state == FUSE:
		return
	player.grabbers.erase(self)
	if kind == "bloater":
		# Too heavy to floor: shove it back instead.
		knock = dir * 130.0
		stagger_t = 0.5
		alert()
		return
	state = DOWN
	notice_t = 0.0
	main.on_knockdown()
	down_t = 1.8
	knock = dir * 170.0
	if absf(dir.x) > 0.1:
		facing = Vector2(-signf(dir.x), 0) # falls away from the blow
	body.modulate = lit * Color(0.75, 0.75, 1.0)
	fx.play("hit")


func execute(dir: Vector2) -> void:
	if dead:
		return
	fx.blood(global_position, dir, 30, 16.0)
	_die(dir, true)


func _die(dir: Vector2, executed := false) -> void:
	if kind == "bloater":
		_start_fuse()
		return
	dead = true
	world.enemy_list.erase(self)
	player.grabbers.erase(self)
	# The body drops away from the killing blow and its pool keeps spreading.
	fx.corpse(Fx.frame_tex(skin, "down", 0), global_position, dir.x > 0.0 if absf(dir.x) > 0.1 else body.flip_h, STATS[kind].size)
	fx.blood(global_position, dir, 14)
	fx.pool(global_position)
	fx.play("die")
	main.on_kill(self, executed)
	queue_free()


## 0 when the fuse lights, 1 at the burst.
func fuse_progress() -> float:
	return clampf(1.0 - fuse_t / FUSE_TIME, 0.0, 1.0)


func _start_fuse() -> void:
	if state == FUSE or dead:
		return
	state = FUSE
	fuse_t = FUSE_TIME
	velocity = Vector2.ZERO
	_pose("lunge")
	fx.play("fuse")
	# Readable danger: the blast's exact reach is marked on the floor for the whole fuse.
	fx.warn(self, global_position, BLAST)
	fx.popup(global_position + Vector2(0, -30), "!!", ACID)


func _explode() -> void:
	dead = true
	world.enemy_list.erase(self)
	var pos := global_position
	fx.corpse(Fx.frame_tex(kind, "down", 0), pos, false, STATS[kind].size)
	fx.acid(pos, BLAST)
	fx.blood(pos, Vector2.ZERO, 40, 40.0)
	fx.ring(pos, BLAST)
	fx.play("boom", 1.0, -3.0)
	fx.add_shake(8.0)
	fx.add_punch(0.08)
	world.flash(pos, ACID, 6.0)
	main.on_kill(self, false)
	for e in world.enemy_list.duplicate():
		var d: Vector2 = e.global_position - pos
		if d.length() < BLAST + 2.0:
			e.hit(4, d.normalized(), 200.0)
	if player.alive and player.global_position.distance_to(pos) < BLAST and world.ray(pos, player.global_position, World.L_WALL).is_empty():
		player.die("BLOWN APART")
	world.blast(pos, BLAST)
	world.noise(pos, 500.0)
	queue_free()
