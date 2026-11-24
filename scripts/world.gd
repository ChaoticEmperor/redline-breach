extends Node2D
## The built floor in 3/4 view: baked floor and wall facades, Y-sorted props
## and wall caps (so actors pass behind and in front of them), lighting,
## collision, kickable doors, breakable glass, pickups, pathfinding, raycasts
## and noise propagation.

const Layout = preload("res://scripts/layout.gd")
const Fx = preload("res://scripts/fx.gd")
const PropAtlas = preload("res://scripts/prop_atlas.gd")

const T := 16
const L_WALL := 1
const L_DOOR := 2
const L_GLASS := 4
const L_PLAYER := 8
const L_ENEMY := 16
const SOLID := L_WALL | L_DOOR | L_GLASS
const AMBIENT := Color("3e2654")
const B := 3 # baked floor texture pixels per world pixel
const PROP_SCALE := 0.5 # props sheet pixels -> world pixels (32 per cell)
const CAP := 8.0 # how far a wall's top edge rises over the floor behind it
const DANCE_COLORS := [Color("ff2a6d"), Color("05d9e8"), Color("ff2a80"), Color("ff2a9d")]
const DANCE_ALPHA := 0.42 # strength of the additive tile pulse
const LIGHT_SPREAD := 3.2 # room light radius (Fx.LIGHTS, px) -> light texture scale, over 64
# zone index -> floor sprite in assets/sprites/floors/
const ZONE_FLOOR := ["concrete", "dancefloor", "vip_carpet", "kitchen_tile", "bar_planks",
	"restroom_tile", "concrete", "corridor_carpet", "elevator_steel"]
# zone index -> plaster colour of the wall face seen from that room
const ZONE_WALL := ["4e4a6c", "3c2466", "5c2468", "7c8694", "5e3a2c", "2c6068", "55503f", "5a2030", "4e5868"]
const ZONE_SIGN := {0: "sign_motel", 1: "sign_redline", 2: "sign_lounge", 4: "sign_lounge"}
const HAZARD_ZONES := [6, 7, 8] # service areas: hazard stripes and alarm lights

static var _bake_cache := {} # seed -> {floor, trims, props, alarms}

var main
var L: Dictionary
var fx
var astar: AStarGrid2D
var doors: Array = [] # {body, pivot, cells, vertical, locked, open, center}
var glass := {} # Vector2i -> StaticBody2D
var pickups: Array = [] # {kind, pos, node}
var enemy_list: Array = []
var props: Array = [] # Sprite2D nodes of the furniture, Y-sorted
var flying: Array = [] # doors in flight: {node, vel, life, hit}
var exit_rect := Rect2()
var exit_open := false
var _glow: CanvasLayer
var _overlay: Node2D
var _neon: Node2D
var _trims: Array = []
var _alarms: Array = [] # flickering PointLight2Ds
var _font: Font
var _unlit := Color.WHITE # cancels the ambient tint for self-lit things
var _dance: Array = []
var _beat := -1


func build(layout: Dictionary) -> void:
	L = layout
	var cells: PackedByteArray = L.cells
	var w: int = L.w
	var h: int = L.h
	_font = ThemeDB.fallback_font
	_unlit = Color(1.0 / AMBIENT.r, 1.0 / AMBIENT.g, 1.0 / AMBIENT.b)
	y_sort_enabled = true # children draw in order of their y: lower on screen is nearer

	var baked: Dictionary = _bake()
	_trims = baked.trims
	# One sprite per room so no single item exceeds the 2D light limit.
	for s in Layout.COLS * Layout.ROWS:
		var spr := Sprite2D.new()
		spr.centered = false
		spr.texture = baked.floor
		var r := _chunk_rect(s)
		spr.region_enabled = true
		spr.region_rect = Rect2(r.position * B, r.size * B)
		spr.position = r.position
		spr.scale = Vector2.ONE / B
		spr.z_index = -10 # the floor is never sorted against actors
		add_child(spr)

	fx = Fx.new()
	fx.world = self
	for n in fx.decal_nodes:
		n.z_index = -5
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
		var cap := -1
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
			# A wall with open floor behind (north of) it gets a cap that
			# hides the feet of anyone standing there.
			var capped := code == Layout.WALL and y > 0 and cells[(y - 1) * w + x] != Layout.WALL
			if capped and cap < 0:
				cap = x
			elif not capped and cap >= 0:
				_add_cap(cap, x, y)
				cap = -1

	for p in L.pickups:
		var spr := Sprite2D.new()
		spr.texture = Fx.tex("w_" + p.kind)
		spr.position = center(p.cell)
		spr.scale = Vector2.ONE * 1.5 * Fx.sprite_scale("w_" + p.kind)
		spr.z_index = -1
		add_child(spr)
		pickups.append({"kind": p.kind, "pos": spr.position, "node": spr})

	for d in L.doors:
		_add_door(d)

	for p in baked.props:
		var spr := Sprite2D.new()
		spr.texture = p.tex
		spr.centered = false
		spr.scale = Vector2.ONE * PROP_SCALE
		spr.offset = Vector2(0, -p.tex.get_height()) # stands on its bottom edge
		spr.position = p.pos
		add_child(spr)
		props.append(spr)
		if p.glow != "":
			_add_light(p.pos + Vector2(p.tex.get_width() * PROP_SCALE / 2.0, -6), Color(p.glow), 1.1, 1.3)

	if not L.exits.is_empty():
		exit_rect = Rect2(Vector2(L.exits[0]) * T, Vector2(T, T))
		for c in L.exits:
			exit_rect = exit_rect.merge(Rect2(Vector2(c) * T, Vector2(T, T)))

	# Mood: dim violet ambient, coloured point lights per room.
	var dark := CanvasModulate.new()
	dark.color = AMBIENT
	add_child(dark)
	for s in Layout.COLS * Layout.ROWS:
		var origin := _chunk_origin(s)
		for l in Fx.LIGHTS[_chunk_zone(s)]:
			_add_light(origin + Vector2(l[0] * Layout.CW, l[1] * Layout.CH) * T, Color(l[2]), l[4], l[3] * LIGHT_SPREAD / 64.0)

	# Neon, signs, dancefloor glow and FX sit on their own canvas so the
	# ambient darkness does not dim them.
	_glow = CanvasLayer.new()
	_glow.layer = 1
	_glow.follow_viewport_enabled = true
	add_child(_glow)
	# Neon trim, signs and alarm lamps are self-lit but stay in the world, under
	# the actors, so nobody is ever drawn behind a wall decoration.
	_neon = Node2D.new()
	_neon.draw.connect(_draw_neon)
	_self_lit(_neon)
	add_child(_neon)
	for s in Layout.COLS * Layout.ROWS:
		var zone := _chunk_zone(s)
		var at := _chunk_origin(s) + Vector2(6, -15)
		var halo := Sprite2D.new()
		halo.texture = Fx.tex("glow")
		halo.material = Fx.mat("add")
		halo.position = at + Vector2(24, 7)
		halo.scale = Vector2(2.0, 0.7)
		halo.modulate = Color(Fx.PINK if s % 2 == 0 else Fx.CYAN, 0.5)
		_glow.add_child(halo)
		if ZONE_SIGN.has(zone):
			var sign := Sprite2D.new()
			sign.texture = Fx.prop_tex(ZONE_SIGN[zone])
			sign.centered = false
			sign.scale = Vector2.ONE * PROP_SCALE
			sign.position = at
			_self_lit(sign)
			add_child(sign)
	for a in baked.alarms: # wall-mounted hazard lights in service areas
		var lamp := Sprite2D.new()
		lamp.texture = Fx.prop_tex("hazard_light")
		lamp.scale = Vector2.ONE * PROP_SCALE
		lamp.position = a
		_self_lit(lamp)
		add_child(lamp)
		_alarms.append(_add_light(a + Vector2(0, 10), Color("ff3a1c"), 1.6, 1.5))
	_overlay = Node2D.new()
	_overlay.material = Fx.mat("add")
	_overlay.draw.connect(_draw_overlay)
	_glow.add_child(_overlay)
	_glow.add_child(fx)


func _self_lit(node: CanvasItem) -> void:
	node.modulate = _unlit
	node.light_mask = 0
	node.z_index = -3 # above floor and gore, below everything Y-sorted


func _add_light(pos: Vector2, col: Color, energy: float, size: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = Fx.tex("light")
	light.position = pos
	light.texture_scale = size
	light.color = col
	light.energy = energy
	add_child(light)
	return light


## Short burst of light in the world (explosions).
func flash(pos: Vector2, col: Color, size: float) -> void:
	var light := _add_light(pos, col, 3.0, size)
	var tween := create_tween()
	tween.tween_property(light, "energy", 0.0, 0.3)
	tween.tween_callback(light.queue_free)


func _add_cap(x0: int, x1: int, y: int) -> void:
	var cap := Sprite2D.new()
	cap.texture = Fx.tex("pixel")
	cap.centered = false
	cap.scale = Vector2((x1 - x0) * T, CAP)
	cap.offset = Vector2(0, -1) # rises above its sorting line (the wall's far edge)
	cap.position = Vector2(x0 * T, y * T)
	cap.modulate = Color("1a1026")
	add_child(cap)
	var edge := Sprite2D.new() # neon along the top of the cap, sorted with it
	edge.texture = Fx.tex("pixel")
	edge.centered = false
	edge.scale = Vector2((x1 - x0) * T, 1)
	edge.offset = Vector2(0, -CAP)
	edge.position = cap.position
	edge.modulate = (Fx.PINK if ((x0 / 17) + (y / 11)) % 2 == 0 else Fx.CYAN) * _unlit
	edge.light_mask = 0
	add_child(edge)


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


## Bakes floor tiles, wall tops and wall faces into one texture, builds the
## furniture sprites and collects neon trim and alarm positions. Cached per
## seed so restarts are free.
func _bake() -> Dictionary:
	if _bake_cache.has(L.seed):
		return _bake_cache[L.seed]
	var cells: PackedByteArray = L.cells
	var w: int = L.w
	var h: int = L.h
	var tp := T * B # one cell in baked pixels
	var im := Image.create(w * tp, h * tp, false, Image.FORMAT_RGBA8)
	var src := Rect2i(0, 0, tp, tp)
	var rng := RandomNumberGenerator.new()
	rng.seed = L.seed
	var alarms: Array = []
	for y in h:
		for x in w:
			var code := cells[y * w + x]
			var at := Vector2i(x, y) * tp
			if code == Layout.WALL:
				im.blit_rect(Fx.scaled("wall", tp), src, at)
				if y + 1 < h and cells[(y + 1) * w + x] != Layout.WALL:
					var zone: int = L.zone[(y + 1) * w + x]
					_bake_facade(im, at, zone, rng)
					if HAZARD_ZONES.has(zone) and (x * 7 + y * 3) % 6 == 0:
						alarms.append(Vector2(x * T + T / 2.0, y * T + 9))
				continue
			var z: int = L.zone[y * w + x]
			var sprite: String = "floors/" + ZONE_FLOOR[z]
			if Fx.has_sprite(sprite):
				# Floor sprites span 2x2 cells.
				im.blit_rect(Fx.scaled(sprite, tp * 2), Rect2i((x % 2) * tp, (y % 2) * tp, tp, tp), at)
			else:
				im.blit_rect(Fx.scaled("floor_%d_%d" % [z, (x + y) % 2], tp), src, at)
			if code == Layout.EXIT:
				im.blit_rect(Fx.scaled("exit", tp), src, at)

	# Neon trim where walls meet open space (drawn unlit on the glow canvas).
	var trims: Array = []
	for y in h:
		for x in w:
			if cells[y * w + x] != Layout.WALL:
				continue
			var col: Color = Fx.PINK if ((x / 17) + (y / 11)) % 2 == 0 else Fx.CYAN
			if y + 1 < h and cells[(y + 1) * w + x] != Layout.WALL:
				trims.append([Rect2(x * T, y * T + T - 1, T, 1), col])
			if x + 1 < w and cells[y * w + x + 1] != Layout.WALL:
				trims.append([Rect2(x * T + T - 1, y * T, 1, T), col])
			if x > 0 and cells[y * w + x - 1] != Layout.WALL:
				trims.append([Rect2(x * T, y * T, 1, T), col])
	if _bake_cache.size() > 4:
		_bake_cache.clear()
	_bake_cache[L.seed] = {"floor": ImageTexture.create_from_image(im), "trims": trims,
		"props": _build_props(), "alarms": alarms}
	return _bake_cache[L.seed]


## The face of a wall seen from the room in front of it: plaster with a
## cornice and skirting, cracks, and hazard stripes in service areas.
func _bake_facade(im: Image, at: Vector2i, zone: int, rng: RandomNumberGenerator) -> void:
	var tp := T * B
	var base := Color(ZONE_WALL[zone])
	var top := at.y + 5 * B
	im.fill_rect(Rect2i(at.x, top, tp, tp - 5 * B), base)
	im.fill_rect(Rect2i(at.x, top, tp, B), base.lightened(0.35)) # cornice
	im.fill_rect(Rect2i(at.x, top + B, tp, B), base.lightened(0.12))
	im.fill_rect(Rect2i(at.x, at.y + tp - 2 * B, tp, 2 * B), base.darkened(0.55)) # skirting
	for i in 5: # stains and chipped plaster
		var p := Vector2i(at.x + rng.randi_range(0, tp - 2 * B), top + rng.randi_range(2 * B, 7 * B))
		im.fill_rect(Rect2i(p, Vector2i(rng.randi_range(1, 3) * B, B)), base.darkened(0.3) if i % 2 == 0 else base.lightened(0.15))
	if rng.randf() < 0.35: # a crack running down the wall
		var cx := at.x + rng.randi_range(3 * B, tp - 4 * B)
		for i in 7:
			im.fill_rect(Rect2i(cx, top + (2 + i) * B, B, B), base.darkened(0.6))
			cx += rng.randi_range(-1, 1) * B
	if HAZARD_ZONES.has(zone):
		for i in 4:
			im.fill_rect(Rect2i(at.x + i * 4 * B, at.y + tp - 5 * B, 2 * B, 3 * B), Color("f9f002"))
			im.fill_rect(Rect2i(at.x + i * 4 * B + 2 * B, at.y + tp - 5 * B, 2 * B, 3 * B), Color("1a1026"))


## Groups touching furniture cells into pieces and builds one 3/4 sprite per
## piece from the props sheet. Returns [{tex, pos, glow}], pos being the
## bottom-left corner of the piece's footprint.
func _build_props() -> Array:
	var sheet: Image = Fx.img("props_v2")
	var out: Array = []
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
			var names := _prop_for(L.zone[y * L.w + x], box.size.x, box.size.y, piece.size(), index)
			index += 1
			var first: Array = PropAtlas.PROPS[names[0]]
			var pos := Vector2(box.position.x, box.end.y) * T
			var glow: String = {"vat": "5aff7a", "arcade": "05d9e8", "vending": "ff5a8a", "dj": "d300c5"}.get(names[0], "")
			if Vector2i(first[4], first[5]) == box.size:
				out.append({"tex": Fx.prop_tex(names[0]), "pos": pos, "glow": glow}) # one object fills the piece
				continue
			# Otherwise the piece is assembled cell by cell, back row first so
			# nearer objects overlap the ones behind.
			var cell_px := 32
			var rise := 0
			for n in names:
				rise = maxi(rise, int(PropAtlas.PROPS[n][3]) - cell_px)
			var im := Image.create(box.size.x * cell_px, box.size.y * cell_px + rise, false, Image.FORMAT_RGBA8)
			piece.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
			for c in piece:
				var local: Vector2i = c - box.position
				var n: String = names[(local.x + local.y) % names.size()]
				var r := Fx.prop_rect(n)
				im.blend_rect(sheet, r, Vector2i(local.x * cell_px, rise + (local.y + 1) * cell_px - r.size.y))
			out.append({"tex": ImageTexture.create_from_image(im), "pos": pos, "glow": glow})
	return out


## Props for a furniture piece: one name if a whole object fits its
## footprint, otherwise single-cell props to repeat (alternating).
func _prop_for(zone: int, w: int, h: int, count: int, index: int) -> Array:
	var names: Array = ["crate"]
	match zone:
		0: names = ["arcade"] if index % 2 == 0 else ["vending"]
		1: names = ["dj"] if w >= 4 else ["speaker"]
		2: names = ["table"] if count == 1 else ["booth"]
		3: names = ["stove", "counter"] if h >= 2 else ["counter"]
		4:
			if count == 1: names = ["stool"]
			else: names = ["bar", "bar_bottles"] if h == 1 else ["booth"]
		5: names = ["toilet"] if count == 1 else ["sink"]
		6: names = [["vat"], ["barrels"], ["crate"], ["rack"]][index % 4]
		7: names = ["tape"] if count == 1 else ["chairs"]
	var first: Array = PropAtlas.PROPS[names[0]]
	if first[4] * first[5] > 1 and Vector2i(first[4], first[5]) != Vector2i(w, h):
		return ["crate"] # a large object that does not fit this piece
	return names


func _add_glass(cell: Vector2i) -> void:
	var b := StaticBody2D.new()
	b.collision_layer = L_GLASS
	b.collision_mask = 0
	b.position = Vector2(cell.x * T + T / 2.0, (cell.y + 1) * T) # sorted by its base
	b.set_meta("glass", cell)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(T, T)
	shape.shape = rect
	shape.position = Vector2(0, -T / 2.0)
	b.add_child(shape)
	var spr := Sprite2D.new()
	spr.texture = Fx.prop_tex("glass")
	spr.scale = Vector2.ONE * PROP_SCALE
	spr.offset = Vector2(0, -spr.texture.get_height() / 2.0)
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


## Opens a door. A kick (`knock`) blasts it off its hinges: it flies across
## the room, flooring every zombie in its path. Zombies only push it open.
func kick_door(i: int, dir: Vector2, knock := true) -> bool:
	var d: Dictionary = doors[i]
	if d.open or d.locked:
		return false
	d.open = true
	d.body.collision_layer = 0
	fx.play("door")
	if not knock:
		var s: float
		if d.vertical:
			s = -1.0 if dir.x > 0.0 else 1.0
		else:
			s = 1.0 if dir.y > 0.0 else -1.0
		create_tween().tween_property(d.pivot, "rotation", d.pivot.rotation + s * PI * 0.47, 0.12)
		return true
	# Through the doorway, along the wall's normal.
	var n := Vector2(signf(dir.x) if dir.x != 0.0 else 1.0, 0) if d.vertical else Vector2(0, signf(dir.y) if dir.y != 0.0 else 1.0)
	d.pivot.visible = false
	var slab := Sprite2D.new()
	slab.texture = Fx.tex("door")
	slab.position = d.center
	slab.rotation = d.pivot.rotation
	add_child(slab)
	flying.append({"node": slab, "vel": n * 330.0, "life": 0.32, "hit": []})
	fx.splinters(d.center, n)
	fx.add_shake(4.0)
	fx.add_kick(n * 4.0)
	for e in enemy_list.duplicate():
		var off: Vector2 = e.global_position - d.center
		if off.length() < 30.0 and off.dot(n) > -4.0:
			e.knockdown(n)
	noise(d.center, 90.0)
	return true


func _physics_process(delta: float) -> void:
	for f in flying.duplicate():
		var node: Sprite2D = f.node
		var step: Vector2 = f.vel * delta
		f.life -= delta
		var blocked := solid_at(node.position + step + f.vel.normalized() * 6.0)
		if not blocked:
			node.position += step
			node.rotation += delta * 22.0
		for e in enemy_list.duplicate():
			if not f.hit.has(e) and e.global_position.distance_to(node.position) < 18.0:
				f.hit.append(e)
				e.knockdown(f.vel.normalized())
				fx.add_shake(2.0)
		if blocked or f.life <= 0.0:
			# It comes to rest as debris on the floor.
			fx.debris(node.texture, node.position, node.rotation, 1.0)
			fx.splinters(node.position, -f.vel.normalized())
			node.queue_free()
			flying.erase(f)


func break_glass(cell: Vector2i) -> void:
	if not glass.has(cell):
		return
	var b: StaticBody2D = glass[cell]
	glass.erase(cell)
	b.collision_layer = 0
	# The frame stays, with shards left in it and scattered on the floor.
	(b.get_child(1) as Sprite2D).texture = Fx.prop_tex("glass_broken")
	b.z_index = -2
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
	var now := Time.get_ticks_msec()
	for i in _alarms.size(): # emergency lights strobe, out of step with each other
		_alarms[i].energy = 1.7 if ((now + i * 370) / 420) % 2 == 0 else 0.25
	var beat := now / 250
	if beat != _beat:
		_beat = beat
		_overlay.queue_redraw()
		for p in pickups:
			p.node.modulate = Color(4, 4, 4) if beat % 2 == 0 else Color(2.5, 2.5, 2.5)


func _draw_neon() -> void:
	for t in _trims:
		_neon.draw_rect(t[0], t[1])
	for s in Layout.COLS * Layout.ROWS:
		var zone := _chunk_zone(s)
		if ZONE_SIGN.has(zone):
			continue # this room has a neon sign sprite instead
		var at := _chunk_origin(s) + Vector2(6, -5)
		var text: String = Fx.ROOM_NAMES[zone]
		var col: Color = Fx.PINK if s % 2 == 0 else Fx.CYAN
		# Text is drawn at 4x size and scaled down so it stays sharp when zoomed.
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x / 4.0
		_neon.draw_rect(Rect2(at + Vector2(-3, -9), Vector2(width + 6, 12)), Color("0a0612"))
		_neon.draw_rect(Rect2(at + Vector2(-3, -9), Vector2(width + 6, 12)), col, false, 1.0)
		_neon.draw_set_transform(at, 0.0, Vector2(0.25, 0.25))
		_neon.draw_string(_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, col.lightened(0.4))
		_neon.draw_set_transform(Vector2.ZERO, 0.0)


func _draw_overlay() -> void:
	for c in _dance:
		var k: int = hash(Vector3i(c.x / 2, c.y / 2, _beat / 2)) % 7
		if k < 4:
			var col: Color = DANCE_COLORS[k]
			_overlay.draw_rect(Rect2(c.x * T + 1, c.y * T + 1, T - 1, T - 1), Color(col, DANCE_ALPHA))
	if exit_open:
		_overlay.draw_rect(exit_rect, Color(0.2, 1.0, 0.45, 0.3 if _beat % 2 == 0 else 0.55))
