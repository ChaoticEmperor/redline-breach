extends "res://scripts/actors/actor.gd"
## An enemy: an Actor with an AI brain. Kinds differ by behaviour and weapon, not by stats.

const EnemyBrain = preload("res://scripts/actors/enemy_brain.gd")

const KINDS := {
	"guard": {"skin": "guard", "weapon": "pipe", "speed": 150.0},
	"gunman": {"skin": "guard", "weapon": "pistol", "speed": 130.0},
	"infected": {"skin": "infected", "weapon": "claws", "speed": 165.0},
}

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


func hear(pos: Vector2) -> void:
	brain.hear(pos)
