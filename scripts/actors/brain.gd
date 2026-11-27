extends Node
## Abstract brain: decides for an actor. Subclasses fill think(); the actor then acts on
## move, aim and the want_* flags. The same actor class runs the player or an enemy.

func think(_actor, _delta: float) -> void:
	pass
