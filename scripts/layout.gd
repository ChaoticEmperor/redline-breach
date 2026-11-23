extends RefCounted
## Floor layout: hand-crafted room chunks stitched into one tile grid from a seed.
## Pure data, no nodes. Same seed -> identical layout.

const CW := 16 # chunk interior width in tiles
const CH := 10 # chunk interior height in tiles
const COLS := 4
const ROWS := 3
const W := COLS * (CW + 1) + 1
const H := ROWS * (CH + 1) + 1

# Tile codes (ASCII).
const FLOOR := 46 # .
const WALL := 35 # #
const TABLE := 84 # T  solid furniture
const GLASS := 71 # G  breakable window
const DOOR := 68 # D  kickable door
const LOCK := 76 # L  elevator door, opens when the floor is clear
const EXIT := 69 # E  elevator floor

const ZONE_OF := {
	"entry": 0, "dance": 1, "vip": 2, "kitchen": 3, "bar": 4,
	"rest": 5, "storage": 6, "corr": 7, "corr2": 7, "elev": 8,
}
const REQUIRED := ["dance", "vip", "kitchen", "bar", "rest", "storage", "corr", "corr2"]
const FILLER := ["corr", "corr2", "bar", "storage"]

# Chunk legend: . floor  # wall  T furniture  G glass  L elevator door  E exit
#   P player start  z shambler  r runner  b bloater  1 pistol  2 shotgun
# Rows 4-5 on the left/right edge and columns 7-8 on the top/bottom edge are
# connection ports and must stay walkable.
const CHUNKS := {
	"entry": [
		"................",
		".TT..........TT.",
		".TT..........TT.",
		"................",
		"......P.........",
		"................",
		"................",
		".TT..........TT.",
		".TT....1.....TT.",
		"................",
	],
	"dance": [
		"................",
		"..z...TTTT...z..",
		"TT....TTTT....TT",
		"TT.z...z..z.z.TT",
		"....z....z......",
		"..z....z...r....",
		"TT...z....z...TT",
		"TT.z...b....z.TT",
		"....z.....z.....",
		"................",
	],
	"vip": [
		"TTT.G......G.TTT",
		"T.z.G......G...T",
		"....G.T....G.z..",
		"GG.GG......GG.GG",
		"................",
		"........r.......",
		"GG.GG......GG.GG",
		"....G....T.G....",
		"T.z.G..2...G.z.T",
		"TTT.G......G.TTT",
	],
	"kitchen": [
		"................",
		".TTTTTT..TTTTTT.",
		"................",
		".z............z.",
		"....TTTTTTTT....",
		"....TTTTTTTT....",
		"................",
		".b.....z......1.",
		".TTTTTT..TTTTTT.",
		"................",
	],
	"bar": [
		"................",
		".TTTTTTTTTTTT...",
		".............z..",
		"................",
		"..T..T..T..T....",
		"................",
		"......r.........",
		"..TT......TT....",
		"..TT..z...TT....",
		"................",
	],
	"rest": [
		"................",
		"..#..#..#..#..#.",
		".z#.T#b.#.T#.z#.",
		"###.###.###.###.",
		"................",
		"................",
		"................",
		"..TT..TT..TT....",
		"............r...",
		"................",
	],
	"storage": [
		"................",
		".TT.TT....TT.TT.",
		".TT.TT....TT.TT.",
		"......z.........",
		"................",
		"................",
		".........r......",
		".TT.TT....TT.TT.",
		".TT.TT.2..TT.TT.",
		"................",
	],
	"corr": [
		"#####......#####",
		"#####......#####",
		"#####..z...#####",
		"................",
		"................",
		"................",
		"................",
		"#####......#####",
		"#####...r..#####",
		"#####......#####",
	],
	"corr2": [
		"................",
		".#########......",
		".........#..z...",
		".........#......",
		"................",
		"................",
		"......#.........",
		"..r...#.........",
		"......#########.",
		"................",
	],
	"elev": [
		"................",
		"................",
		"..z..######..z..",
		".....#EEEE#.....",
		".....#EEEE#.....",
		".....#EEEE#.....",
		".....##LL##.....",
		"................",
		".......b........",
		"................",
	],
}


static func validate() -> bool:
	for k in CHUNKS:
		var rows: Array = CHUNKS[k]
		if rows.size() != CH:
			return false
		for r in rows:
			if (r as String).length() != CW:
				return false
	return true


static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cells := PackedByteArray()
	cells.resize(W * H)
	cells.fill(WALL)
	var zone := PackedByteArray()
	zone.resize(W * H)
	zone.fill(255)

	var n := COLS * ROWS
	var entry := rng.randi_range(0, ROWS - 1) * COLS
	var exit_slot := rng.randi_range(0, ROWS - 1) * COLS + COLS - 1
	var pool: Array = REQUIRED.duplicate()
	while pool.size() < n - 2:
		pool.append(FILLER[rng.randi_range(0, FILLER.size() - 1)])
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	var zombies: Array = []
	var pickups: Array = []
	var exits: Array = []
	var locks: Array = []
	var doors: Array = []
	var start := Vector2i(2, 2)

	for s in n:
		var chunk_name: String
		if s == entry:
			chunk_name = "entry"
		elif s == exit_slot:
			chunk_name = "elev"
		else:
			chunk_name = pool.pop_back()
		var ox := (s % COLS) * (CW + 1) + 1
		var oy := (s / COLS) * (CH + 1) + 1
		var rows: Array = CHUNKS[chunk_name]
		var fh := rng.randf() < 0.5
		var fv := rng.randf() < 0.5
		for y in CH:
			for x in CW:
				var row: String = rows[CH - 1 - y if fv else y]
				var ch := row[CW - 1 - x if fh else x]
				var cell := Vector2i(ox + x, oy + y)
				var idx := cell.y * W + cell.x
				zone[idx] = ZONE_OF[chunk_name]
				var code := FLOOR
				match ch:
					"#": code = WALL
					"T": code = TABLE
					"G": code = GLASS
					"L":
						code = LOCK
						locks.append(cell)
					"E":
						code = EXIT
						exits.append(cell)
					"P": start = cell
					"z": zombies.append({"kind": "shambler", "cell": cell})
					"r": zombies.append({"kind": "runner", "cell": cell})
					"b": zombies.append({"kind": "bloater", "cell": cell})
					"1": pickups.append({"kind": "pistol", "cell": cell})
					"2": pickups.append({"kind": "shotgun", "cell": cell})
				cells[idx] = code

	# Connections: random spanning tree of doors (guarantees every room is
	# reachable), then extra doors / glass windows on the remaining shared walls.
	var edges: Array = []
	for s in n:
		if s % COLS < COLS - 1:
			edges.append([s, s + 1, true])
		if s / COLS < ROWS - 1:
			edges.append([s, s + COLS, false])
	var seen := {entry: true}
	while seen.size() < n:
		var frontier: Array = []
		for e in edges:
			if seen.has(e[0]) != seen.has(e[1]):
				frontier.append(e)
		var pick: Array = frontier[rng.randi_range(0, frontier.size() - 1)]
		seen[pick[0]] = true
		seen[pick[1]] = true
		edges.erase(pick)
		_port(cells, zone, doors, pick[0], pick[2], DOOR)
	for e in edges:
		var roll := rng.randf()
		if roll < 0.25:
			_port(cells, zone, doors, e[0], e[2], DOOR)
		elif roll < 0.7:
			_port(cells, zone, doors, e[0], e[2], GLASS)

	if locks.size() >= 2:
		locks.sort()
		doors.append({"cells": locks, "vertical": locks[0].x == locks[1].x, "locked": true})

	return {
		"seed": seed_value, "w": W, "h": H, "cells": cells, "zone": zone,
		"doors": doors, "zombies": zombies, "pickups": pickups, "exits": exits,
		"start": start,
		"sig": cells.hex_encode() + str(zombies) + str(pickups) + str(start),
	}


## Punches a two-tile opening in the wall shared by slot `a` and its right
## (horizontal) or lower neighbour.
static func _port(cells: PackedByteArray, zone: PackedByteArray, doors: Array, a: int, horizontal: bool, code: int) -> void:
	var cx := a % COLS
	var cy := a / COLS
	var pair: Array = []
	for k in 2:
		var c: Vector2i
		var side: Vector2i
		if horizontal:
			c = Vector2i((cx + 1) * (CW + 1), cy * (CH + 1) + 1 + 4 + k)
			side = Vector2i(1, 0)
		else:
			c = Vector2i(cx * (CW + 1) + 1 + 7 + k, (cy + 1) * (CH + 1))
			side = Vector2i(0, 1)
		cells[c.y * W + c.x] = code
		zone[c.y * W + c.x] = zone[(c.y - side.y) * W + c.x - side.x]
		for nb in [c - side, c + side]:
			var ni: int = nb.y * W + nb.x
			if cells[ni] == WALL or cells[ni] == TABLE or cells[ni] == GLASS:
				cells[ni] = FLOOR
		pair.append(c)
	if code == DOOR:
		doors.append({"cells": pair, "vertical": horizontal, "locked": false})


## Flood fill from the player start. Returns the set of reachable cells.
static func reachable(L: Dictionary, through_glass := false) -> Dictionary:
	var cells: PackedByteArray = L.cells
	var out := {L.start: true}
	var queue: Array = [L.start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if nb.x < 0 or nb.y < 0 or nb.x >= W or nb.y >= H or out.has(nb):
				continue
			var code := cells[nb.y * W + nb.x]
			if code == WALL or code == TABLE or (code == GLASS and not through_glass):
				continue
			out[nb] = true
			queue.append(nb)
	return out
