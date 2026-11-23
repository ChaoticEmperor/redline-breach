extends CanvasLayer
## Input abstraction. Mobile-first: floating dual virtual sticks (left half
## moves, right half aims and fires at full tilt) plus KICK/EXEC and DASH
## buttons. Falls back to WASD + mouse. Gameplay only reads `move`, `aim`,
## `fire` and `take()`; tests set `override` and drive those directly.
##
## Like the HUD, layout is in units: the screen is 360 units tall and `W`
## wide, so the buttons stay in the right-hand corner on any aspect ratio.

const STICK_R := 34.0
const BTN_R := 21.0
const SWAP_ZONE := Rect2(0, 0, 132, 36)

var move := Vector2.ZERO
var aim := Vector2.ZERO
var fire := false
var touch_mode := false
var override := false
var player
var q := {"kick": false, "dash": false, "swap": false, "any": false, "restart": false}
var u := 3.0
var W := 640.0
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
	_measure()


func _measure() -> void:
	var size := get_viewport().get_visible_rect().size
	u = size.y / 360.0
	W = size.x / u


func kick_pos() -> Vector2:
	return Vector2(W - 34.0, 128.0)


func dash_pos() -> Vector2:
	return Vector2(W - 34.0, 182.0)


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
		var p: Vector2 = event.position / u
		if event.pressed:
			q.any = true
			if p.distance_to(kick_pos()) < BTN_R + 6.0:
				q.kick = true
			elif p.distance_to(dash_pos()) < BTN_R + 6.0:
				q.dash = true
			elif SWAP_ZONE.has_point(p):
				q.swap = true
			elif p.x < W / 2.0 and _l_id == -1:
				_l_id = event.index
				_l_origin = p
				_l_vec = Vector2.ZERO
			elif p.x >= W / 2.0 and _r_id == -1:
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
		var p: Vector2 = event.position / u
		if event.index == _l_id:
			_l_vec = ((p - _l_origin) / STICK_R).limit_length(1.0)
		elif event.index == _r_id:
			_r_vec = ((p - _r_origin) / STICK_R).limit_length(1.0)
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
	_measure()
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
	_stick(_l_origin if _l_id != -1 else Vector2(74, 286), _l_vec, _l_id != -1, Color(0.02, 0.85, 0.91), false)
	_stick(_r_origin if _r_id != -1 else Vector2(W - 140, 286), _r_vec, _r_id != -1, Color(1.0, 0.16, 0.43), true)
	var label := "KICK"
	if player != null and is_instance_valid(player):
		label = player.context()
	_button(kick_pos(), label, Color(0.98, 0.94, 0.0) if label == "EXEC" else Color(1.0, 0.16, 0.43))
	_button(dash_pos(), "DASH", Color(0.02, 0.85, 0.91))


func _stick(at: Vector2, vec: Vector2, active: bool, col: Color, fires: bool) -> void:
	var a := 0.55 if active else 0.22
	_canvas.draw_arc(at * u, STICK_R * u, 0, TAU, 48, Color(col, a), 2.0 * u, true)
	_canvas.draw_circle((at + vec * STICK_R) * u, 13.0 * u, Color(col, a))
	if fires and vec.length() > 0.75:
		_canvas.draw_arc(at * u, (STICK_R + 4.0) * u, 0, TAU, 48, Color(1, 1, 1, 0.6), u, true)


func _button(at: Vector2, text: String, col: Color) -> void:
	_canvas.draw_circle(at * u, BTN_R * u, Color(col, 0.22))
	_canvas.draw_arc(at * u, BTN_R * u, 0, TAU, 48, Color(col, 0.8), 2.0 * u, true)
	_canvas.draw_string(_font, (at + Vector2(-BTN_R, 3)) * u, text, HORIZONTAL_ALIGNMENT_CENTER, BTN_R * 2.0 * u, int(8 * u), Color(1, 1, 1, 0.9))
