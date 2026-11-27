extends "res://scripts/actors/brain.gd"
## The player's brain: the controls (touch, or keyboard and mouse). On touch with no aim
## dragged, it aims at the nearest enemy in range while attacking, else where it walks.

var controls


func _init(p_controls = null) -> void:
	controls = p_controls


func think(a, _delta: float) -> void:
	a.move = controls.move
	var av: Vector2 = controls.aim
	if av.length() > 0.2:
		a.aim = av.normalized()
	elif controls.touch_mode:
		var target = _nearest(a, 220.0 if a.weapon.is_gun() else 48.0) if controls.fire else null
		if target != null:
			a.aim = (target.global_position - a.global_position).normalized()
		elif a.move.length() > 0.3:
			a.aim = a.move.normalized()
	a.want_attack = controls.fire
	a.want_kick = controls.take("kick")
	a.want_throw = controls.take("throw")
	a.want_pickup = controls.take("pickup")


func _nearest(a, reach: float):
	var best = null
	for e in a.get_tree().get_nodes_in_group("actors"):
		if e == a or e.team == a.team or e.dead:
			continue
		var d: float = e.global_position.distance_to(a.global_position)
		if d < reach and (best == null or d < best.global_position.distance_to(a.global_position)):
			best = e
	return best
