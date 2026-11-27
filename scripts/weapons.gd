extends RefCounted
## The weapon table. Melee is silent and kills in one hit inside an arc in
## front; guns carry only the ammo they came with (no reloads, no ammo
## pickups) and are loud. Anything can be thrown: a thrown weapon knocks down
## whoever it hits and lands as a pickup. Bare fists knock down, never kill.
##
## Sizes are in art px (a tile is 32). Times are in seconds.

const FISTS := ""

const TABLE := {
	"": {"kind": "melee", "reach": 18.0, "arc": 0.9, "swing": 0.26, "how": "punch", "length": 0.0},
	"pipe": {"kind": "melee", "reach": 28.0, "arc": 1.3, "swing": 0.32, "how": "blunt", "length": 28.0},
	"bat": {"kind": "melee", "reach": 30.0, "arc": 1.4, "swing": 0.36, "how": "blunt", "length": 30.0},
	"pistol": {"kind": "gun", "ammo": 8, "rate": 0.2, "pellets": 1, "spread": 0.03, "range": 360.0,
			"noise": 360.0, "shake": 3.0, "sound": "pistol", "how": "shot", "length": 14.0},
	"shotgun": {"kind": "gun", "ammo": 4, "rate": 0.75, "pellets": 6, "spread": 0.22, "range": 240.0,
			"noise": 420.0, "shake": 7.0, "sound": "shotgun", "how": "shot", "length": 30.0},
}

## The share of a swing at which the blow lands: the strike is fast (the first
## third), then it holds at full extension so the hit reads, then recovers.
const STRIKE := 0.3
const THROW_SPEED := 420.0 # art px per second
const THROW_TIME := 0.55 # how long a throw flies before it drops
const THROW_SPIN := 18.0 # radians per second
const PICK_REACH := 18.0 # how close a pickup must be to take it


static func info(w: String) -> Dictionary:
	return TABLE[w]


static func is_gun(w: String) -> bool:
	return TABLE[w].kind == "gun"


static func full_ammo(w: String) -> int:
	return int(TABLE[w].get("ammo", 0))


## Where a melee weapon is in a swing, as an angle off the aim, for `t` from 0 to 1.
static func swing_angle(w: String, t: float) -> float:
	var arc: float = TABLE[w].arc
	if t < STRIKE:
		return lerpf(-arc, arc, 1.0 - pow(1.0 - t / STRIKE, 2.0))
	if t < 0.5:
		return arc
	return lerpf(arc, 0.0, smoothstep(0.5, 1.0, t))
