extends CanvasLayer
## Input abstraction. Mobile-first: floating dual virtual sticks (left half
## moves, right half aims and fires at full tilt) plus KICK/EXEC and DASH
## buttons. Falls back to WASD + mouse. Gameplay only reads `move`, `aim`,
## `fire` and `take()`; tests set `override` and drive those directly.

const STICK_R := 34.0
const BTN_R := 21.0
const BTN_KICK := Vector2(606, 128)
const BTN_DASH := Vector2(606, 182)
const SWAP_ZONE := Rect2(0, 0, 132, 36)

var move := Vector2.ZERO
var aim := Vector2.ZERO
var fire := false
var touch_mode := false
var override := false
var player
var q := {"kick": false, "dash": false, "swap": false, "any": false, "restart": false}
var _l_id := -1
var _l_origin := Vector2.ZERO
var _l_vec := Vector2.ZERO
var _r_id := -1
var _r_origin := Vector2.ZERO
var _r_vec := Vector2.ZERO
var _canvas: Node2D
var _font: Font


func _ready() -> void:
	layer = 10
	_font = ThemeDB.fallback_font
	touch_mode = DisplayServer.is_touchscreen_available()
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_ui)
	add_child(_canvas)


## Returns true once per queued press.
func take(n: String) -> bool:
	if q[n]:
		q[n] = false
		return true
	return false


func clear() -> void:
	for k in q:
		q[k] = false


func _input(event: InputEvent) -> void:
	if override:
		return
	if event is InputEventScreenTouch:
		touch_mode = true
		var p: Vector2 = event.position
		if event.pressed:
			q.any = true
			if p.distance_to(BTN_KICK) < BTN_R + 6.0:
				q.kick = true
			elif p.distance_to(BTN_DASH) < BTN_R + 6.0:
				q.dash = true
			elif SWAP_ZONE.has_point(p):
				q.swap = true
			elif p.x < 320.0 and _l_id == -1:
				_l_id = event.index
				_l_origin = p
				_l_vec = Vector2.ZERO
			elif p.x >= 320.0 and _r_id == -1:
				_r_id = event.index
				_r_origin = p
				_r_vec = Vector2.ZERO
		else:
			if event.index == _l_id:
				_l_id = -1
				_l_vec = Vector2.ZERO
			if event.index == _r_id:
				_r_id = -1
				_r_vec = Vector2.ZERO
	elif event is InputEventScreenDrag:
		if event.index == _l_id:
			_l_vec = ((event.position - _l_origin) / STICK_R).limit_length(1.0)
		elif event.index == _r_id:
			_r_vec = ((event.position - _r_origin) / STICK_R).limit_length(1.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		touch_mode = false
		q.any = true
		match event.physical_keycode:
			KEY_SPACE, KEY_SHIFT: q.dash = true
			KEY_E, KEY_F: q.kick = true
			KEY_Q: q.swap = true
			KEY_R: q.restart = true
	elif event is InputEventMouseButton and event.pressed:
		touch_mode = false
		match event.button_index:
			MOUSE_BUTTON_LEFT: q.any = true
			MOUSE_BUTTON_RIGHT: q.kick = true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN: q.swap = true


func _process(_delta: float) -> void:
	_canvas.queue_redraw()
	if override:
		return
	if touch_mode:
		move = _l_vec
		aim = _r_vec if _r_vec.length() > 0.25 else Vector2.ZERO
		fire = _r_vec.length() > 0.75
		return
	var m := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): m.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): m.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): m.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): m.y += 1.0
	move = m.normalized()
	fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if player != null and is_instance_valid(player):
		var origin: Vector2 = player.get_global_transform_with_canvas().origin
		var d := get_viewport().get_mouse_position() - origin
		aim = d.normalized() if d.length() > 3.0 else Vector2.ZERO


func _draw_ui() -> void:
	if not touch_mode:
		return
	_stick(_l_origin if _l_id != -1 else Vector2(74, 286), _l_vec, _l_id != -1, Color(0.02, 0.85, 0.91))
	_stick(_r_origin if _r_id != -1 else Vector2(500, 286), _r_vec, _r_id != -1, Color(1.0, 0.16, 0.43))
	var label := "KICK"
	if player != null and is_instance_valid(player):
		label = player.context()
	_button(BTN_KICK, label, Color(0.98, 0.94, 0.0) if label == "EXEC" else Color(1.0, 0.16, 0.43))
	_button(BTN_DASH, "DASH", Color(0.02, 0.85, 0.91))


func _stick(at: Vector2, vec: Vector2, active: bool, col: Color) -> void:
	var a := 0.55 if active else 0.22
	_canvas.draw_arc(at, STICK_R, 0, TAU, 32, Color(col, a), 2.0)
	_canvas.draw_circle(at + vec * STICK_R, 13.0, Color(col, a))
	if vec.length() > 0.75 and at.x > 320.0:
		_canvas.draw_arc(at, STICK_R + 4.0, 0, TAU, 32, Color(1, 1, 1, 0.6), 1.0)


func _button(at: Vector2, text: String, col: Color) -> void:
	_canvas.draw_circle(at, BTN_R, Color(col, 0.22))
	_canvas.draw_arc(at, BTN_R, 0, TAU, 32, Color(col, 0.8), 2.0)
	_canvas.draw_string(_font, at + Vector2(-BTN_R, 3), text, HORIZONTAL_ALIGNMENT_CENTER, BTN_R * 2.0, 8, Color(1, 1, 1, 0.9))
