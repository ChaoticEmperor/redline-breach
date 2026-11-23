extends Node2D
## The built floor: baked floor texture, wall collision, kickable doors,
## breakable glass, pickups, pathfinding grid, raycasts and noise propagation.

const Layout = preload("res://scripts/layout.gd")
const Fx = preload("res://scripts/fx.gd")

const T := 16
const L_WALL := 1
const L_DOOR := 2
const L_GLASS := 4
const L_PLAYER := 8
const L_ENEMY := 16
const SOLID := L_WALL | L_DOOR | L_GLASS
const DANCE_COLORS := [Color("ff2a6d"), Color("05d9e8"), Color("d300c5"), Color("f9f002")]

static var _floor_cache := {}

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
var _overlay: Node2D
var _dance: Array = []
var _beat := -1


func build(layout: Dictionary) -> void:
	L = layout
	var cells: PackedByteArray = L.cells
	var w: int = L.w
	var h: int = L.h

	var floor_spr := Sprite2D.new()
	floor_spr.centered = false
	floor_spr.texture = _floor_texture()
	add_child(floor_spr)

	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	fx = Fx.new()
	fx.world = self
	add_child(fx.decal_node)

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

	add_child(fx)


func _floor_texture() -> Texture2D:
	if _floor_cache.has(L.seed):
		return _floor_cache[L.seed]
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
			im.blit_rect(Fx.img("floor_%d_%d" % [L.zone[y * w + x], (x + y) % 2]), src, at)
			if code == Layout.TABLE:
				im.blit_rect(Fx.img("table"), src, at)
			elif code == Layout.EXIT:
				im.blit_rect(Fx.img("exit"), src, at)
	# Neon trim where walls meet open space.
	for y in h:
		for x in w:
			if cells[y * w + x] != Layout.WALL:
				continue
			var col: Color = Fx.PINK if ((x / 17) + (y / 11)) % 2 == 0 else Fx.CYAN
			if y + 1 < h and cells[(y + 1) * w + x] != Layout.WALL:
				im.fill_rect(Rect2i(x * T, y * T + T - 2, T, 2), col)
			if y > 0 and cells[(y - 1) * w + x] != Layout.WALL:
				im.fill_rect(Rect2i(x * T, y * T, T, 1), col)
			if x + 1 < w and cells[y * w + x + 1] != Layout.WALL:
				im.fill_rect(Rect2i(x * T + T - 1, y * T, 1, T), col)
			if x > 0 and cells[y * w + x - 1] != Layout.WALL:
				im.fill_rect(Rect2i(x * T, y * T, 1, T), col)
	var t := ImageTexture.create_from_image(im)
	if _floor_cache.size() > 4:
		_floor_cache.clear()
	_floor_cache[L.seed] = t
	return t


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
			p.node.modulate = Color(1.6, 1.6, 1.6) if beat % 2 == 0 else Color(1, 1, 1)


func _draw_overlay() -> void:
	for c in _dance:
		var k: int = hash(Vector3i(c.x / 2, c.y / 2, _beat / 2)) % 7
		if k < 4:
			var col: Color = DANCE_COLORS[k]
			_overlay.draw_rect(Rect2(c.x * T + 1, c.y * T + 1, T - 1, T - 1), Color(col, 0.3))
	if exit_open:
		_overlay.draw_rect(exit_rect, Color(0.2, 1.0, 0.45, 0.25 if _beat % 2 == 0 else 0.45))
