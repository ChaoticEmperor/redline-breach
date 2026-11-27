extends "res://scripts/actors/actor.gd"
## The player: an Actor with the controls for a brain and the player's skin.

const PlayerBrain = preload("res://scripts/actors/player_brain.gd")


func setup_player(p_main, controls, p_skin := "player") -> void:
	team = "player"
	setup(p_main, PlayerBrain.new(controls), p_skin, "unarmed")
