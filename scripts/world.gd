extends Node2D
## The built floor: baked floor/prop texture, lighting, wall collision,
## kickable doors, breakable glass, pickups, pathfinding grid, raycasts and
## noise propagation.

const Layout = preload("res://scripts/layout.gd")
const Fx = preload("res://scripts/fx.gd")

const T := 16
const L_WALL := 1
const L_DOOR := 2
const L_GLASS := 4
const L_PLAYER := 8
const L_ENEMY := 16
const SOLID := L_WALL | L_DOOR | L_GLASS
const AMBIENT := Color("1e182e")
const DANCE_COLORS := [Color("ff2a6d"), Color("05d9e8"), Color("d300c5"), Color("f9f002")]
# zone index -> floor sprite in assets/sprites/floors/
const ZONE_FLOOR := ["concrete", "dancefloor", "vip_carpet", "kitchen_tile", "bar_planks",
	"restroom_tile", "concrete", "corridor_carpet", "elevator_steel"]

static var _bake_cache := {} # seed -> [floor texture, neon trim rects]

var main
var L: Dictionary
var fx
var astar: AStarGrid2D
var doors: Array = [] # {body, pivot, cells, vertical, locked, open, center}
var glass := {} # Vector2i -> StaticBody2D
var pickups: Array = [] # {kind, pos, node}
var enemy_list: Array = []
var exit_rect := Rect2()
var exit_open := false
var _glow: CanvasLayer
var _overlay: Node2D
var _neon: Node2D
var _trims: Array = []
var _font: Font
var _dance: Array = []
var _beat := -1


func build(layout: Dictionary) -> void:
	L = layout
	var cells: PackedByteArray = L.cells
	var w: int = L.w
	var h: int = L.h
	_font = ThemeDB.fallback_font

	var baked: Array = _bake()
	_trims = baked[1]
	# One sprite per room so no single item exceeds the 2D light limit.
	for s in Layout.COLS * Layout.ROWS:
		var spr := Sprite2D.new()
		spr.centered = false
		spr.texture = baked[0]
		spr.region_enabled = true
		spr.region_rect = _chunk_rect(s)
		spr.position = spr.region_rect.position
		add_child(spr)

	fx = Fx.new()
	fx.world = self
	for n in fx.decal_nodes:
		add_child(n)

	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(T, T)
	astar.offset = Vector2(T, T) / 2.0
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()

	var walls := StaticBody2D.new()
	walls.collision_layer = L_WALL
	walls.collision_mask = 0
	add_child(walls)
	for y in h:
		var run := -1
		for x in w + 1:
			var code := cells[y * w + x] if x < w else 0
			var cell := Vector2i(x, y)
			var solid := code == Layout.WALL or code == Layout.TABLE
			if x < w:
				if solid or code == Layout.GLASS or code == Layout.LOCK:
					astar.set_point_solid(cell, true)
				elif code == Layout.DOOR:
					astar.set_point_weight_scale(cell, 3.0)
				if code == Layout.GLASS:
					_add_glass(cell)
				elif code == Layout.FLOOR and L.zone[y * w + x] == 1:
					_dance.append(cell)
			if solid and run < 0:
				run = x
			elif not solid and run >= 0:
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2((x - run) * T, T)
				shape.shape = rect
				shape.position = Vector2((run + x) * T / 2.0, y * T + T / 2.0)
				walls.add_child(shape)
				run = -1

	for p in L.pickups:
		var spr := Sprite2D.new()
		spr.texture = Fx.tex("w_" + p.kind)
		spr.position = center(p.cell)
		spr.scale = Vector2(1.5, 1.5)
		add_child(spr)
		pickups.append({"kind": p.kind, "pos": spr.position, "node": spr})

	for d in L.doors:
		_add_door(d)

	if not L.exits.is_empty():
		exit_rect = Rect2(Vector2(L.exits[0]) * T, Vector2(T, T))
		for c in L.exits:
			exit_rect = exit_rect.merge(Rect2(Vector2(c) * T, Vector2(T, T)))

	# Mood: near-black ambient, coloured point lights per room.
	var dark := CanvasModulate.new()
	dark.color = AMBIENT
	add_child(dark)
	for s in Layout.COLS * Layout.ROWS:
		var origin := _chunk_origin(s)
		for l in Fx.LIGHTS[_chunk_zone(s)]:
			var light := PointLight2D.new()
			light.texture = Fx.tex("light")
			light.position = origin + Vector2(l[0] * Layout.CW, l[1] * Layout.CH) * T
			light.texture_scale = l[3] * 2.4 / 64.0
			light.color = Color(l[2])
			light.energy = l[4]
			add_child(light)

	# Neon, signs, dancefloor glow and FX sit on their own canvas so the
	# ambient darkness does not dim them.
	_glow = CanvasLayer.new()
	_glow.layer = 1
	_glow.follow_viewport_enabled = true
	add_child(_glow)
	_neon = Node2D.new()
	_neon.draw.connect(_draw_neon)
	_glow.add_child(_neon)
	_overlay = Node2D.new()
	_overlay.material = Fx.mat("add")
	_overlay.draw.connect(_draw_overlay)
	_glow.add_child(_overlay)
	_glow.add_child(fx)


# ---------------------------------------------------------------- baking

func _chunk_origin(s: int) -> Vector2:
	return Vector2((s % Layout.COLS) * (Layout.CW + 1) + 1, (s / Layout.COLS) * (Layout.CH + 1) + 1) * T


func _chunk_rect(s: int) -> Rect2:
	var cx := s % Layout.COLS
	var cy := s / Layout.COLS
	var size := Vector2(Layout.CW + 1 + (1 if cx == Layout.COLS - 1 else 0), Layout.CH + 1 + (1 if cy == Layout.ROWS - 1 else 0))
	return Rect2(Vector2(cx * (Layout.CW + 1), cy * (Layout.CH + 1)) * T, size * T)


func _chunk_zone(s: int) -> int:
	var c := cell_of(_chunk_origin(s))
	return L.zone[c.y * L.w + c.x]


## Bakes floor tiles, walls, furniture and the exit pad into one texture and
## collects the neon trim rectangles. Cached per seed so restarts are free.
func _bake() -> Array:
	if _bake_cache.has(L.seed):
		return _bake_cache[L.seed]
	var cells: PackedByteArray = L.cells
	var w: int = L.w
	var h: int = L.h
	var im := Image.create(w * T, h * T, false, Image.FORMAT_RGBA8)
	var src := Rect2i(0, 0, T, T)
	for y in h:
		for x in w:
			var code := cells[y * w + x]
			var at := Vector2i(x * T, y * T)
			if code == Layout.WALL:
				im.blit_rect(Fx.img("wall"), src, at)
				continue
			var z: int = L.zone[y * w + x]
			var sprite: String = "floors/" + ZONE_FLOOR[z]
			if Fx.has_sprite(sprite):
				# 32px floor sprites span 2x2 cells.
				im.blit_rect(Fx.img(sprite), Rect2i((x % 2) * T, (y % 2) * T, T, T), at)
			else:
				im.blit_rect(Fx.img("floor_%d_%d" % [z, (x + y) % 2]), src, at)
			if code == Layout.EXIT:
				im.blit_rect(Fx.img("exit"), src, at)

	_bake_furniture(im)
	if not L.exits.is_empty() and Fx.has_sprite("props/elevator_panel"):
		var r := Rect2i(L.exits[0] * T, Vector2i(T, T))
		for c in L.exits:
			r = r.merge(Rect2i(c * T, Vector2i(T, T)))
		_stamp(im, "props/elevator_panel", r, false, false)

	# Neon trim where walls meet open space (drawn unlit on the glow canvas).
	var trims: Array = []
	for y in h:
		for x in w:
			if cells[y * w + x] != Layout.WALL:
				continue
			var col: Color = Fx.PINK if ((x / 17) + (y / 11)) % 2 == 0 else Fx.CYAN
			if y + 1 < h and cells[(y + 1) * w + x] != Layout.WALL:
				trims.append([Rect2(x * T, y * T + T - 2, T, 2), col])
			if y > 0 and cells[(y - 1) * w + x] != Layout.WALL:
				trims.append([Rect2(x * T, y * T, T, 1), col])
			if x + 1 < w and cells[y * w + x + 1] != Layout.WALL:
				trims.append([Rect2(x * T + T - 1, y * T, 1, T), col])
			if x > 0 and cells[y * w + x - 1] != Layout.WALL:
				trims.append([Rect2(x * T, y * T, 1, T), col])
	if _bake_cache.size() > 4:
		_bake_cache.clear()
	_bake_cache[L.seed] = [ImageTexture.create_from_image(im), trims]
	return _bake_cache[L.seed]


## Groups touching furniture cells into pieces and draws each as props that
## suit the room (or as procedural blocks when the sprites are missing).
func _bake_furniture(im: Image) -> void:
	var seen := {}
	var index := 0
	for y in L.h:
		for x in L.w:
			var start := Vector2i(x, y)
			if seen.has(start) or code_at(start) != Layout.TABLE:
				continue
			var piece: Array = []
			var queue: Array = [start]
			seen[start] = true
			var box := Rect2i(start, Vector2i.ONE)
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				piece.append(c)
				box = box.merge(Rect2i(c, Vector2i.ONE))
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb: Vector2i = c + d
					if not seen.has(nb) and code_at(nb) == Layout.TABLE:
						seen[nb] = true
						queue.append(nb)
			var zone: int = L.zone[y * L.w + x]
			var prop := _prop_for(zone, box.size.x, box.size.y, piece.size(), index)
			index += 1
			var sprite: String = "props/" + prop[0]
			if not Fx.has_sprite(sprite):
				_bake_blocks(im, piece, zone)
			elif piece.size() < box.size.x * box.size.y:
				# L-shaped piece: one sprite over the whole box, elbow matched.
				var right := not piece.has(box.position) or not piece.has(box.position + Vector2i(0, box.size.y - 1))
				var bottom := not piece.has(box.position) or not piece.has(box.position + Vector2i(box.size.x - 1, 0))
				_stamp(im, sprite, Rect2i(box.position * T, box.size * T), right, bottom)
			else:
				var fw: int = mini(prop[1], box.size.x)
				var fh: int = mini(prop[2], box.size.y)
				for py in range(box.position.y, box.end.y, fh):
					for px in range(box.position.x, box.end.x, fw):
						var size := Vector2i(mini(fw, box.end.x - px), mini(fh, box.end.y - py))
						_stamp(im, sprite, Rect2i(Vector2i(px, py) * T, size * T), false, false)


## Picks [sprite, width, height] (in cells) for a furniture piece.
func _prop_for(zone: int, w: int, h: int, count: int, index: int) -> Array:
	match zone:
		0: return ["potted_palm", 2, 2]
		1: return ["dj_booth", 4, 2] if w >= 4 else ["speaker", 2, 2]
		2:
			if count == 1: return ["table_cocktail", 1, 1]
			return ["booth_seat", w, h] if count < w * h else ["sofa_pink", 2, 1]
		3: return ["stove", 2, 2] if h >= 2 else ["kitchen_counter", 2, 1]
		4:
			if count == 1: return ["bar_stool", 1, 1]
			return ["bar_counter", 2, 1] if h == 1 else ["sofa_pink", 2, 1]
		5: return ["toilet_stall", 1, 1] if count == 1 else ["sink", 1, 1]
		6: return ["crate", 1, 1] if index % 2 == 0 else ["metal_shelf", 2, 2]
	return ["crate", 1, 1]


func _stamp(im: Image, sprite: String, rect: Rect2i, flip_x: bool, flip_y: bool) -> void:
	var p: Image = Fx.img(sprite).duplicate()
	if flip_x:
		p.flip_x()
	if flip_y:
		p.flip_y()
	p.resize(rect.size.x, rect.size.y, Image.INTERPOLATE_NEAREST)
	im.blend_rect(p, Rect2i(Vector2i.ZERO, rect.size), rect.position)


func _bake_blocks(im: Image, piece: Array, zone: int) -> void:
	var f: Array = Fx.FURN[zone]
	for c in piece:
		var at: Vector2i = c * T
		im.blit_rect(Fx.img("table_%d" % zone), Rect2i(0, 0, T, T), at)
		if not piece.has(c + Vector2i(-1, 0)):
			im.fill_rect(Rect2i(at.x, at.y, 1, T), Color(f[1]))
		if not piece.has(c + Vector2i(1, 0)):
			im.fill_rect(Rect2i(at.x + T - 1, at.y, 1, T), Color(f[1]))
		if not piece.has(c + Vector2i(0, -1)):
			im.fill_rect(Rect2i(at.x, at.y, T, 2), Color(f[2]))
		if not piece.has(c + Vector2i(0, 1)):
			im.fill_rect(Rect2i(at.x, at.y + T - 3, T, 3), Color(f[1]))


func _add_glass(cell: Vector2i) -> void:
	var b := StaticBody2D.new()
	b.collision_layer = L_GLASS
	b.collision_mask = 0
	b.position = center(cell)
	b.set_meta("glass", cell)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(T, T)
	shape.shape = rect
	b.add_child(shape)
	var spr := Sprite2D.new()
	spr.texture = Fx.tex("glass")
	b.add_child(spr)
	add_child(b)
	glass[cell] = b


func _add_door(d: Dictionary) -> void:
	var a: Vector2i = d.cells[0]
	var vertical: bool = d.vertical
	var hinge := Vector2(a.x * T + T / 2.0, a.y * T) if vertical else Vector2(a.x * T, a.y * T + T / 2.0)
	var mid := hinge + (Vector2(0, T) if vertical else Vector2(T, 0))
	var body := StaticBody2D.new()
	body.collision_layer = L_DOOR
	body.collision_mask = 0
	body.position = mid
	body.set_meta("door", doors.size())
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6, T * 2) if vertical else Vector2(T * 2, 6)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	var pivot := Node2D.new()
	pivot.position = hinge
	pivot.rotation = PI / 2.0 if vertical else 0.0
	var spr := Sprite2D.new()
	spr.texture = Fx.tex("door_locked" if d.locked else "door")
	spr.centered = false
	spr.position = Vector2(0, -3)
	pivot.add_child(spr)
	add_child(pivot)
	doors.append({"body": body, "pivot": pivot, "cells": d.cells, "vertical": vertical,
		"locked": d.locked, "open": false, "center": mid})


# ---------------------------------------------------------------- queries

func center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * T + Vector2(T, T) / 2.0


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i((pos / T).floor())


func code_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= L.w or cell.y >= L.h:
		return Layout.WALL
	return L.cells[cell.y * L.w + cell.x]


func solid_at(pos: Vector2) -> bool:
	var code := code_at(cell_of(pos))
	return code == Layout.WALL or code == Layout.TABLE


func ray(a: Vector2, b: Vector2, mask: int, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters2D.create(a, b, mask, exclude)
	return get_world_2d().direct_space_state.intersect_ray(q)


## Line of sight. Glass is see-through, walls and closed doors are not.
func los(a: Vector2, b: Vector2) -> bool:
	return ray(a, b, L_WALL | L_DOOR).is_empty()


func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := cell_of(from)
	var b := cell_of(to)
	if not astar.is_in_boundsv(a) or not astar.is_in_boundsv(b):
		return PackedVector2Array()
	return astar.get_point_path(a, b, true)


# ---------------------------------------------------------------- events

## Loud events wake every zombie in range, regardless of walls.
func noise(pos: Vector2, radius: float) -> void:
	for e in enemy_list:
		if e.global_position.distance_to(pos) < radius:
			e.hear(pos)


func kick_door(i: int, dir: Vector2, knock := true) -> bool:
	var d: Dictionary = doors[i]
	if d.open or d.locked:
		return false
	d.open = true
	d.body.collision_layer = 0
	var s: float
	if d.vertical:
		s = -1.0 if dir.x > 0.0 else 1.0
	else:
		s = 1.0 if dir.y > 0.0 else -1.0
	create_tween().tween_property(d.pivot, "rotation", d.pivot.rotation + s * PI * 0.47, 0.12)
	fx.play("door")
	fx.add_shake(2.0)
	if knock:
		var n := dir.normalized()
		for e in enemy_list.duplicate():
			var off: Vector2 = e.global_position - d.center
			if off.length() < 30.0 and off.dot(n) > -4.0:
				e.knockdown(n)
		noise(d.center, 90.0)
	return true


func break_glass(cell: Vector2i) -> void:
	if not glass.has(cell):
		return
	var b: StaticBody2D = glass[cell]
	glass.erase(cell)
	b.collision_layer = 0
	b.queue_free()
	astar.set_point_solid(cell, false)
	fx.shards(center(cell))
	fx.play("glass")
	noise(center(cell), 140.0)


## Explosion side effects on the level itself.
func blast(pos: Vector2, radius: float) -> void:
	for cell in glass.keys():
		if center(cell).distance_to(pos) < radius + 8.0:
			break_glass(cell)
	for i in doors.size():
		if doors[i].center.distance_to(pos) < radius + 8.0:
			kick_door(i, doors[i].center - pos, false)


func open_exit() -> void:
	if exit_open:
		return
	exit_open = true
	for d in doors:
		if d.locked:
			d.locked = false
			d.open = true
			d.body.collision_layer = 0
			d.pivot.visible = false
			for c in d.cells:
				astar.set_point_solid(c, false)
	fx.play("clear")
	_overlay.queue_redraw()


func take_pickup(pos: Vector2) -> String:
	for p in pickups:
		if p.pos.distance_to(pos) < 12.0:
			pickups.erase(p)
			p.node.queue_free()
			return p.kind
	return ""


func _process(_delta: float) -> void:
	var beat := Time.get_ticks_msec() / 250
	if beat != _beat:
		_beat = beat
		_overlay.queue_redraw()
		for p in pickups:
			p.node.modulate = Color(9, 9, 9) if beat % 2 == 0 else Color(5, 5, 5)


func _draw_neon() -> void:
	for t in _trims:
		_neon.draw_rect(t[0], t[1])
	for s in Layout.COLS * Layout.ROWS:
		var at := _chunk_origin(s) + Vector2(6, -4)
		var text: String = Fx.ROOM_NAMES[_chunk_zone(s)]
		var col: Color = Fx.PINK if s % 2 == 0 else Fx.CYAN
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		_neon.draw_rect(Rect2(at + Vector2(-3, -9), Vector2(width + 6, 12)), Color("0a0612"))
		_neon.draw_rect(Rect2(at + Vector2(-3, -9), Vector2(width + 6, 12)), col, false, 1.0)
		_neon.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col.lightened(0.4))


func _draw_overlay() -> void:
	for c in _dance:
		var k: int = hash(Vector3i(c.x / 2, c.y / 2, _beat / 2)) % 7
		if k < 4:
			var col: Color = DANCE_COLORS[k]
			_overlay.draw_rect(Rect2(c.x * T + 1, c.y * T + 1, T - 1, T - 1), Color(col, 0.28))
	if exit_open:
		_overlay.draw_rect(exit_rect, Color(0.2, 1.0, 0.45, 0.3 if _beat % 2 == 0 else 0.55))
