extends RefCounted
## Abstract weapon: what an actor holds. Subclasses (melee.gd, gun.gd) decide what `use`
## does; the actor only calls use() and reads ready(). `make(name, ammo)` builds the right one.

const Table = preload("res://scripts/weapons/table.gd")

var name := "unarmed"
var ammo := 0
var info: Dictionary
var cooldown := 0.0


static func make(p_name: String, p_ammo := -1) -> RefCounted:
	var data: Dictionary = Table.info(p_name)
	var w = load("res://scripts/weapons/gun.gd" if data.kind == "gun" else "res://scripts/weapons/melee.gd").new()
	w.name = p_name
	w.info = data
	w.ammo = Table.full_ammo(p_name) if p_ammo < 0 else p_ammo
	return w


func is_gun() -> bool:
	return false


## The sheet animation set this weapon is drawn with (claws use the unarmed frames).
func art() -> String:
	return info.get("art", name)


func ready() -> bool:
	return cooldown <= 0.0


func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	_tick(delta)


## Starts an attack by `actor`. Returns false if nothing happened (empty, cooling down).
func use(_actor) -> bool:
	return false


func _tick(_delta: float) -> void:
	pass
