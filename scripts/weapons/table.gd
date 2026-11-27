extends RefCounted
## The weapon table: data only. Melee is silent and kills in one hit inside an arc in front;
## guns carry only the ammo they came with and are loud. Bare fists knock down, never kill.
## Sizes in art px (a tile is 32); times in seconds; force is the push a Hit gives.

const TABLE := {
	"unarmed": {"kind": "melee", "reach": 20.0, "arc": 0.9, "how": "punch", "force": 260.0, "length": 0.0},
	"claws": {"kind": "melee", "reach": 22.0, "arc": 1.0, "how": "cut", "force": 220.0, "length": 0.0, "art": "unarmed", "drops": false},
	"shield": {"kind": "melee", "reach": 22.0, "arc": 1.0, "how": "kick", "force": 380.0, "length": 0.0, "drops": false},
	"pipe": {"kind": "melee", "reach": 30.0, "arc": 1.3, "how": "blunt", "force": 320.0, "length": 18.0},
	"bat": {"kind": "melee", "reach": 32.0, "arc": 1.4, "how": "blunt", "force": 380.0, "length": 20.0},
	"pistol": {"kind": "gun", "ammo": 8, "rate": 0.22, "pellets": 1, "spread": 0.03, "range": 380.0,
			"noise": 360.0, "shake": 3.0, "sound": "pistol", "how": "shot", "force": 260.0, "length": 12.0},
	"shotgun": {"kind": "gun", "ammo": 4, "rate": 0.75, "pellets": 6, "spread": 0.22, "range": 260.0,
			"noise": 420.0, "shake": 7.0, "sound": "shotgun", "how": "shot", "force": 420.0, "length": 22.0},
}
## The share of a swing at which the blow lands (the strike frame), see the attack sheet.
const STRIKE := 0.42
const THROW_SPEED := 440.0
const THROW_TIME := 0.55
const THROW_SPIN := 18.0
const PICK_REACH := 18.0


static func info(w: String) -> Dictionary:
	return TABLE[w]


static func is_gun(w: String) -> bool:
	return TABLE[w].kind == "gun"


static func full_ammo(w: String) -> int:
	return int(TABLE[w].get("ammo", 0))
