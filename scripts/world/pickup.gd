extends Node2D
## A weapon lying on the floor, with whatever ammo it has left.

const PropArt = preload("res://scripts/art/prop_art.gd")

var weapon := "pipe"
var ammo := 0


func setup(w: String, a: int, angle := 0.0) -> void:
	weapon = w
	ammo = a
	rotation = angle
	add_to_group("pickups")
	var spr := Sprite2D.new()
	spr.texture = PropArt.tex("w_" + weapon)
	add_child(spr)
