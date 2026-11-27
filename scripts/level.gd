extends RefCounted
## Turns an ASCII floor map into a TileMapLayer plus a list of things to place, one letter per
## tile. The tiles (and which are solid) come from assets/sprites/world/tiles.json, so the art
## and the legend can change without touching this file. Floors are drawn in Tandem's tile maps
## and exported back as this format (the level files stay the source of truth).
##   tiles:   .  rose tile   ,  dancefloor   ~  carpet   =  wood   w  restroom
##            #  wall        C  bar counter  K  booth                      (solid: # C K)
##   things:  P player   E guard (pipe)   F gunman (pistol)   Z infected
##            l pipe  b bat  i pistol  g shotgun          (weapons on the floor)
##            G glass (horizontal)  | glass (vertical)  D door (horizontal)  d door (vertical)
##            T table   s stool
## A thing's tile takes the floor most common round it.

const TILE := 32
const DIR := "res://assets/sprites/world/"
const THINGS := {"P": "player", "E": "guard", "F": "gunman", "Z": "infected", "l": "pipe", "b": "bat", "i": "pistol",
		"g": "shotgun", "G": "glass_h", "|": "glass_v", "D": "door_h", "d": "door_v", "T": "table", "s": "stool"}

## The first floor: a bar, a lounge, a lobby, the dancefloor and a restroom. Drawn and edited in
## Tandem's tile map ("Club floor 1") and exported back to this file.
static func club() -> String:
	return FileAccess.get_file_as_string("res://levels/club.txt")

## An empty test room: a wall with a one-tile doorway (x 7) between two open areas.
const TEST := """
####################
#..................#
#..................#
#..................#
#######.############
#..................#
#.....P............#
#..................#
#..................#
####################
"""

static var _tileset: TileSet
static var _tiles: Dictionary # char -> {x, solid, name}


static func legend() -> Dictionary:
	if _tiles.is_empty():
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "tiles.json"))
		for t in meta.tiles:
			_tiles[t.char] = t
	return _tiles


## Parses `text` into {cells: {Vector2i: char}, size, start, things: [{what, cell, pos}]}.
static func parse(text: String) -> Dictionary:
	var tiles := legend()
	var rows := text.strip_edges().split("\n")
	var raw := {}
	var w := 0
	for y in rows.size():
		var row: String = rows[y].strip_edges(false, true)
		w = maxi(w, row.length())
		for x in row.length():
			raw[Vector2i(x, y)] = row[x]
	var cells := {}
	var things := []
	var start := Vector2.ZERO
	for cell in raw:
		var c: String = raw[cell]
		if tiles.has(c):
			cells[cell] = c
			continue
		if c == " ":
			continue
		cells[cell] = _floor_near(raw, cell, tiles)
		var pos := (Vector2(cell) + Vector2(0.5, 0.5)) * TILE
		if c == "P":
			start = pos
		elif THINGS.has(c):
			things.append({"what": THINGS[c], "cell": cell, "pos": pos})
	return {"cells": cells, "size": Vector2i(w, rows.size()), "start": start, "things": things}


static func _floor_near(raw: Dictionary, cell: Vector2i, tiles: Dictionary) -> String:
	var count := {}
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var n: String = raw.get(cell + d, "")
		if tiles.has(n) and not tiles[n].solid:
			count[n] = count.get(n, 0) + 1
	var best := "."
	for k in count:
		if count[k] > count.get(best, 0):
			best = k
	return best


static func is_solid(c: String) -> bool:
	return legend().has(c) and legend()[c].solid


static func build(text: String) -> Dictionary:
	var info := parse(text)
	var map := TileMapLayer.new()
	map.tile_set = tileset()
	for cell in info.cells:
		map.set_cell(cell, 0, Vector2i(int(legend()[info.cells[cell]].x), 0))
	info["map"] = map
	# the walking grid: solid tiles and unbroken glass block; doors and furniture do not
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, info.size)
	grid.cell_size = Vector2(TILE, TILE)
	grid.offset = Vector2(TILE, TILE) / 2.0
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for cell in info.cells:
		if is_solid(info.cells[cell]):
			grid.set_point_solid(cell)
	for t in info.things:
		if t.what.begins_with("glass"):
			grid.set_point_solid(t.cell)
	info["grid"] = grid
	return info


static func tileset() -> TileSet:
	if _tileset != null:
		return _tileset
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	var src := TileSetAtlasSource.new()
	src.texture = load(DIR + "tiles.png")
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	var h := TILE / 2.0
	for c in legend():
		var t: Dictionary = legend()[c]
		var at := Vector2i(int(t.x), 0)
		src.create_tile(at)
		if t.solid:
			var td := src.get_tile_data(at, 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]))
	_tileset = ts
	return ts
