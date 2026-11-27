extends RefCounted
## One blow, from anything to anything. Every object that can be hit implements
## `take_hit(hit)` and answers in its own way (polymorphism): glass shatters, a door
## swings, a table slides, an actor is knocked down or dies by the right death.
##   kind   what it is: punch, blunt, cut, shot, kick, impact (a flying body or object), blast
##   dir    which way it pushes (unit vector)
##   force  how hard, in art px per second of push given to the target
##   source who or what dealt it (an actor, a body, a thrown weapon), or null
##   team   the dealer's side; an actor ignores hits from its own side, except impacts

const LETHAL := ["blunt", "cut", "shot", "blast"]
const KNOCK := ["punch", "kick", "impact"]

var kind := "blunt"
var dir := Vector2.RIGHT
var force := 0.0
var source: Object
var team := ""


static func make(p_kind: String, p_dir: Vector2, p_force: float, p_source: Object = null, p_team := "") -> RefCounted:
	var h = load("res://scripts/core/hit.gd").new()
	h.kind = p_kind
	h.dir = p_dir.normalized() if p_dir.length() > 0.001 else Vector2.RIGHT
	h.force = p_force
	h.source = p_source
	h.team = p_team
	return h


func lethal() -> bool:
	return kind in LETHAL
