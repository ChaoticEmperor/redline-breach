extends Node
## Component: decides what a hit does to its owner. One hit kills (the genre's rule);
## punches, kicks and impacts knock down instead. Emits a signal; the owner reacts.

signal died(hit)
signal knocked(hit)

@export var invulnerable := false
var dead := false


func take(hit) -> String:
	if dead or invulnerable:
		return "none"
	if hit.lethal():
		dead = true
		died.emit(hit)
		return "dead"
	knocked.emit(hit)
	return "down"
