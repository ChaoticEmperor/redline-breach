extends Node2D
## A weapon lying on the floor, with whatever ammo it has left.
## Placeholder art: a short outlined bar at the weapon's real length
## (0.4 to 1 tile), lighter outlined than a body so it reads as an object.

const Weapons = preload("res://scripts/weapons.gd")

var weapon := "pipe"
var ammo := 0


func setup(w: String, a: int, angle := 0.0) -> void:
	weapon = w
	ammo = a
	rotation = angle
	add_to_group("pickups")


func _draw() -> void:
	var half: float = Weapons.info(weapon).length / 2.0
	var col := Color("9aa0aa") if not Weapons.is_gun(weapon) else Color("c8c8d0")
	draw_rect(Rect2(-half - 1, -2, half * 2 + 2, 4), Color("101014"))
	draw_rect(Rect2(-half, -1, half * 2, 2), col)
	if Weapons.is_gun(weapon) and ammo == 0:
		draw_rect(Rect2(-1, -1, 2, 2), Color("ff2a6d")) # an empty gun shows a red mark
