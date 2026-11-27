extends StaticBody2D
## Breakable: a glass pane. Any blow, shot, thrown weapon or flying body breaks it; shots and
## thrown things pass through. Once broken, everyone walks through the frame.

const Layers = preload("res://scripts/core/layers.gd")
const PropArt = preload("res://scripts/art/prop_art.gd")

const STRENGTH := 40.0 # the smallest force that breaks it

var broken := false
var _spr: Sprite2D
var _shape: CollisionShape2D
var main


func setup(p_main, vertical: bool) -> void:
	main = p_main
	collision_layer = Layers.WORLD
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(32, 4)
	_shape.shape = r
	add_child(_shape)
	_spr = Sprite2D.new()
	_spr.texture = PropArt.tex("glass")
	add_child(_spr)
	rotation = PI / 2.0 if vertical else 0.0
	add_to_group("breakables")


func lets_shots_through() -> bool:
	return true


func take_hit(hit) -> void:
	if broken or hit.force < STRENGTH:
		return
	broken = true
	_spr.texture = PropArt.tex("glass_broken")
	_shape.set_deferred("disabled", true)
	main.sfx.play("glass")
	main.shards(global_position, hit.dir)
