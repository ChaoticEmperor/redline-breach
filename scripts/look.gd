extends Node2D
## Component: how an actor is drawn. The one place that knows the view: an overhead body whose
## legs turn to the movement and whose torso turns to the aim (Paul, 2026-11-27). Gameplay only
## calls set_skin(), set_weapon(), set_aim(), set_move() and attack(); swapping the art (another
## skin, or 4-direction sprites later) replaces what is in here and nothing else.

const CharArt = preload("res://scripts/art/char_art.gd")

const STRIDE := 30.0 # art px walked per 8-frame leg cycle, so feet do not skate

var skin := ""
var weapon := "unarmed"
var aim_angle := 0.0
var move_angle := 0.0
var walk_frame := 0 # 0 = standing, legs hidden
var legs: AnimatedSprite2D
var torso: AnimatedSprite2D
var _art: Dictionary
var _phase := 0.0
var _attacking := false


func _ready() -> void:
	legs = AnimatedSprite2D.new()
	torso = AnimatedSprite2D.new()
	for s in [legs, torso]:
		s.centered = false
		add_child(s)
	torso.animation_finished.connect(func(): _attacking = false; _show_walk())
	if skin != "":
		set_skin(skin)


func set_skin(p_skin: String) -> void:
	skin = p_skin
	if legs == null:
		return
	_art = CharArt.load_skin(skin)
	for s in [legs, torso]:
		s.sprite_frames = _art.frames
		s.offset = -_art.anchor
	legs.animation = "legs_walk"
	_show_walk()


func set_weapon(w: String) -> void:
	weapon = w if w != "" else "unarmed"
	_attacking = false
	_show_walk()


func set_aim(dir: Vector2) -> void:
	if dir.length() > 0.01:
		aim_angle = dir.angle()
		torso.rotation = aim_angle


## `vel` is the actor's velocity in art px per second.
func set_move(vel: Vector2, delta: float) -> void:
	var speed := vel.length()
	if speed > 4.0:
		move_angle = vel.angle()
		legs.rotation = move_angle
		_phase = fposmod(_phase + speed * delta / STRIDE, 1.0)
		walk_frame = 1 + int(_phase * 7) % 7
	else:
		_phase = 0.0
		walk_frame = 0
	legs.frame = walk_frame
	if not _attacking:
		torso.frame = walk_frame


## Plays the weapon's attack once; returns how long it lasts in seconds.
func attack() -> float:
	var name := weapon + "_attack"
	if not torso.sprite_frames.has_animation(name):
		return 0.2
	_attacking = true
	torso.play(name)
	return torso.sprite_frames.get_frame_count(name) / torso.sprite_frames.get_animation_speed(name)


func is_attacking() -> bool:
	return _attacking


## The tip of the held weapon in global coordinates (muzzle flashes and tracers start here).
func tip_global() -> Vector2:
	var reach := {"pistol": 14.0, "shotgun": 20.0}
	return global_position + Vector2.RIGHT.rotated(aim_angle) * float(reach.get(weapon, 10.0)) + Vector2(0, 1).rotated(aim_angle)


func _show_walk() -> void:
	if torso == null or torso.sprite_frames == null:
		return
	torso.stop()
	torso.animation = weapon + "_walk"
	torso.frame = walk_frame
