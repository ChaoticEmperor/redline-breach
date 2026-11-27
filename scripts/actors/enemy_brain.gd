extends "res://scripts/actors/brain.gd"
## An enemy's brain. Idle until it sees the player (a plain line of sight inside a cone and a
## range, checked on staggered frames) or hears a noise; a 0.25 s notice beat (a "!") before it
## comes; then it chases along a tile path and attacks: melee when in reach, a gun after a short
## first-shot delay. It searches the last place it saw the player before giving up.

const Layers = preload("res://scripts/core/layers.gd")

const SIGHT := 300.0
const CONE := 1.2 # radians either side of where it faces
const NEAR := 56.0 # sensed in any direction this close
const NOTICE := 0.25
const FIRST_SHOT := 0.45
const THINK := 0.1 # seconds between sight checks
const SLOW := 0.55 # walking speed while idle or searching, as a share of full speed
const LUNGE_RANGE := 110.0 # a lunging enemy charges from this close
const LUNGE_SPEED := 1.9 # its charge, as a share of its speed (it cannot steer)
const LUNGE_TIME := 0.38
const LUNGE_RECOVER := 0.5 # after a charge it stands, catching itself: the player's opening

enum { IDLE, NOTICE_BEAT, CHASE, SEARCH }

var state := IDLE
var facing := Vector2.RIGHT
var target_pos := Vector2.ZERO
var sees := false
var _think_t := 0.0
var _notice_t := 0.0
var _shot_t := 0.0
var _path := PackedVector2Array()
var _path_i := 0
var _repath_t := 0.0
var _lost_t := 0.0
var lunges := false
var lunge_t := 0.0 # > 0 while charging
var recover_t := 0.0
var lunge_dir := Vector2.ZERO


func _ready() -> void:
	_think_t = randf() * THINK # spread the sight checks over frames


func hear(pos: Vector2) -> void:
	if state in [IDLE, SEARCH]:
		state = SEARCH
		target_pos = pos
		_repath_t = 0.0


func think(a, delta: float) -> void:
	var p = a.main.player
	var alive: bool = p != null and is_instance_valid(p) and not p.dead
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = THINK
		sees = alive and _can_see(a, p)
	a.want_attack = false
	a.move = Vector2.ZERO
	match state:
		IDLE:
			a.aim = facing
			if sees:
				_notice(a)
		NOTICE_BEAT:
			_notice_t -= delta
			a.aim = (p.global_position - a.global_position).normalized() if alive else a.aim
			if _notice_t <= 0.0:
				state = CHASE
				_shot_t = FIRST_SHOT
		CHASE:
			if not alive:
				state = IDLE
				return
			if lunges and _lunge(a, p, delta):
				return
			if sees:
				target_pos = p.global_position
				_lost_t = 0.0
			else:
				_lost_t += delta
				if _lost_t > 2.5:
					state = SEARCH
			var to: Vector2 = p.global_position - a.global_position
			a.aim = to.normalized() if sees else a.aim
			if a.weapon.is_gun() and a.weapon.ammo > 0:
				_shot_t -= delta
				if sees and to.length() < a.weapon.info.range * 0.8:
					a.want_attack = _shot_t <= 0.0
					if to.length() > 90.0:
						return # hold position and shoot
				_follow(a, target_pos, delta, 1.0)
			else:
				if sees and to.length() < a.weapon.info.reach + 6.0:
					a.want_attack = true
				else:
					_follow(a, target_pos, delta, 1.0)
		SEARCH:
			if sees:
				_notice(a)
				return
			if _follow(a, target_pos, delta, SLOW):
				state = IDLE
				facing = a.aim


## The charge: once in range and in sight, it runs straight at where the player was, faster than it
## walks and without turning, then stops to recover. Returns true while it owns the move.
func _lunge(a, p, delta: float) -> bool:
	if recover_t > 0.0:
		recover_t -= delta
		a.move = Vector2.ZERO
		return true
	if lunge_t > 0.0:
		lunge_t -= delta
		a.move = lunge_dir * LUNGE_SPEED
		a.aim = lunge_dir
		a.want_attack = a.global_position.distance_to(p.global_position) < a.weapon.info.reach + 8.0
		if lunge_t <= 0.0:
			recover_t = LUNGE_RECOVER
		return true
	var to: Vector2 = p.global_position - a.global_position
	if sees and to.length() < LUNGE_RANGE and to.length() > 30.0:
		lunge_t = LUNGE_TIME
		lunge_dir = to.normalized()
		a.main.popup(a.global_position + Vector2(0, -16), "!")
		return true
	return false


func _notice(a) -> void:
	state = NOTICE_BEAT
	_notice_t = NOTICE
	a.main.popup(a.global_position + Vector2(0, -16), "!")


## Walks toward `dest` along the tile path; returns true when there.
func _follow(a, dest: Vector2, delta: float, pace: float) -> bool:
	_repath_t -= delta
	if _repath_t <= 0.0 or _path_i >= _path.size():
		_repath_t = 0.4
		_path = a.main.path(a.global_position, dest)
		_path_i = 1 if _path.size() > 1 else 0
	if _path.is_empty():
		return a.global_position.distance_to(dest) < 12.0
	while _path_i < _path.size() - 1 and a.global_position.distance_to(_path[_path_i]) < 10.0:
		_path_i += 1
	var to: Vector2 = _path[_path_i] - a.global_position
	if _path_i == _path.size() - 1 and to.length() < 10.0:
		return true
	a.move = to.normalized() * pace
	if not sees:
		a.aim = to.normalized()
	return false


func _can_see(a, p) -> bool:
	var to: Vector2 = p.global_position - a.global_position
	var d := to.length()
	if d > SIGHT:
		return false
	if d > NEAR and state == IDLE and absf(facing.angle_to(to)) > CONE:
		return false
	var space: PhysicsDirectSpaceState2D = a.get_world_2d().direct_space_state
	var exclude := [a.get_rid()]
	for hop in 4: # glass is see-through
		var q := PhysicsRayQueryParameters2D.create(a.global_position, p.global_position, Layers.WORLD | Layers.PROPS)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var c = hit.collider
		if c.has_method("lets_shots_through") and c.lets_shots_through():
			exclude.append(c.get_rid())
			continue
		if c is RigidBody2D: # furniture and doors do not block sight
			exclude.append(c.get_rid())
			continue
		return false
	return true
