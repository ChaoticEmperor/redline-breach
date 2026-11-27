extends RefCounted
## Turns an ASCII floor map into a TileMapLayer, one letter per tile.
## M1 knows walls, floor and the player start; M4 adds doors, glass, props,
## pickups and spawns, and loads hand-made floors from files.
##   #  wall      .  floor      P  player start (on floor)

const TILE := 32 # art pixels per tile; a door is one tile
const WALL := Vector2i(1, 0) # atlas coords in the tileset
const FLOOR := Vector2i(0, 0)

## A test room for M1: a wall with a one-tile doorway, and a pillar.
const TEST := """
####################
#..................#
#..................#
#..................#
#######.############
#..................#
#.....P............#
#...........##.....#
#...........##.....#
#..................#
####################
"""

static var _tileset: TileSet


## Parses `text` into {cells: {Vector2i: char}, size: Vector2i, start: Vector2}.
static func parse(text: String) -> Dictionary:
	var rows := text.strip_edges().split("\n")
	var cells := {}
	var start := Vector2.ZERO
	var w := 0
	for y in rows.size():
		var row: String = rows[y].strip_edges(false, true)
		w = maxi(w, row.length())
		for x in row.length():
			var c := row[x]
			if c == "P":
				start = (Vector2(x, y) + Vector2(0.5, 0.5)) * TILE
				c = "."
			if c != " ":
				cells[Vector2i(x, y)] = c
	return {"cells": cells, "size": Vector2i(w, rows.size()), "start": start}


static func build(text: String) -> Dictionary:
	var info := parse(text)
	var map := TileMapLayer.new()
	map.tile_set = tileset()
	for cell in info.cells:
		map.set_cell(cell, 0, WALL if info.cells[cell] == "#" else FLOOR)
	info["map"] = map
	return info


## Placeholder tiles drawn in code: a quiet unoutlined floor with a darker seam,
## and a grey wall with a black outline (bodies, props and walls are outlined).
static func tileset() -> TileSet:
	if _tileset != null:
		return _tileset
	var img := Image.create(TILE * 2, TILE, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, TILE, TILE), Color("2a2036"))
	img.fill_rect(Rect2i(0, TILE - 1, TILE, 1), Color("1d1626"))
	img.fill_rect(Rect2i(TILE - 1, 0, 1, TILE), Color("1d1626"))
	img.fill_rect(Rect2i(TILE, 0, TILE, TILE), Color("000000"))
	img.fill_rect(Rect2i(TILE + 2, 2, TILE - 4, TILE - 4), Color("5a5a64"))
	img.fill_rect(Rect2i(TILE + 2, 2, TILE - 4, 3), Color("7a7a86"))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	src.create_tile(FLOOR)
	src.create_tile(WALL)
	var h := TILE / 2.0
	var td := src.get_tile_data(WALL, 0)
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]))
	_tileset = ts
	return ts
