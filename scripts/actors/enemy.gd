extends "res://scripts/actors/actor.gd"
## An enemy: an Actor with an AI brain. Kinds differ by behaviour and weapon, not by stats.

const EnemyBrain = preload("res://scripts/actors/enemy_brain.gd")

const Burst = preload("res://scripts/world/burst.gd")

## Kinds differ by what they do, not by bigger numbers:
##   lunge   closes in, then charges in a straight line it cannot steer, and needs a moment to recover
##   burst   bursts after a short, visible fuse when it dies; the blast kills whatever is inside it
##   armour  blocks shots and blows from the front; get it from the side or behind, or knock it down
const KINDS := {
	"guard": {"skin": "guard", "weapon": "pipe", "speed": 150.0},
	"gunman": {"skin": "guard", "weapon": "pistol", "speed": 130.0},
	"infected": {"skin": "infected", "weapon": "claws", "speed": 165.0},
	"runner": {"skin": "runner", "weapon": "claws", "speed": 200.0, "lunge": true},
	"bloater": {"skin": "bloater", "weapon": "claws", "speed": 80.0, "burst": true},
	"riot": {"skin": "riot", "weapon": "shield", "speed": 115.0, "armour": true},
}
const FRONT := 1.2 # radians either side of where an armoured enemy faces that its shield covers

var kind := "guard"


func setup_enemy(p_main, p_kind: String, facing: Vector2) -> void:
	kind = p_kind
	team = "enemy"
	var k: Dictionary = KINDS[kind]
	var b = EnemyBrain.new()
	b.facing = facing
	setup(p_main, b, k.skin, k.weapon)
	speed = k.speed
	aim = facing
	b.lunges = k.get("lunge", false)


func hear(pos: Vector2) -> void:
	brain.hear(pos)


## Armour: a shot, cut or blow that comes from in front is stopped by the shield (it only shoves);
## a kick, an impact, or anything from the side or behind gets through.
func take_hit(hit) -> void:
	if KINDS[kind].get("armour", false) and not is_down() and hit.kind in ["shot", "cut", "blunt", "punch"]:
		if absf(aim.angle_to(-hit.dir)) < FRONT:
			velocity = hit.dir * hit.force * 0.3
			main.sfx.play("hit", 1.8)
			main.fx.flash(global_position + aim * 10.0)
			return
	super.take_hit(hit)


func _on_died(hit) -> void:
	if KINDS[kind].get("burst", false):
		var b := Burst.new()
		b.setup(main)
		b.position = global_position
		main.world.add_child(b)
	super._on_died(hit)
