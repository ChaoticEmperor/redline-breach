extends "res://scripts/weapons/weapon.gd"
## Melee: a swing. The blow lands at the strike frame (not on the press), on every body in the
## arc with no wall between; silent.

const Hit = preload("res://scripts/core/hit.gd")
const Layers = preload("res://scripts/core/layers.gd")

var _actor
var _t := -1.0
var _length := 0.3
var _struck := false


func use(actor) -> bool:
	if not ready():
		return false
	_actor = actor
	_length = maxf(actor.look.attack(), 0.15)
	_t = 0.0
	_struck = false
	cooldown = _length
	actor.sfx("swing")
	return true


func swinging() -> bool:
	return _t >= 0.0


func _tick(delta: float) -> void:
	if _t < 0.0 or not is_instance_valid(_actor):
		return
	_t += delta / _length
	if not _struck and _t >= Table.STRIKE:
		_struck = true
		for target in _actor.targets_in_arc(info.reach, info.arc):
			var dir: Vector2 = (target.global_position - _actor.global_position).normalized()
			target.take_hit(Hit.make(info.how, dir, info.force, _actor, _actor.team))
			_actor.sfx("hit")
			_actor.shake(2.0)
	if _t >= 1.0:
		_t = -1.0
