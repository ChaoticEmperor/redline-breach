extends CanvasLayer
## Input abstraction. Mobile-first: a MOVE stick on the left, and on the
## right a big HIT/FIRE button with KICK/EXEC and DASH beside it. Holding
## HIT/FIRE attacks; dragging it aims (otherwise the player auto-aims).
## Falls back to WASD + mouse. Gameplay only reads `move`, `aim`, `fire` and
## `take()`; tests set `override` and drive those directly.
##
## Like the HUD, layout is in units (short screen side = 360), anchored to
## the bottom corners, so it is the same in portrait and landscape.

const STICK_R := 40.0
const FIRE_R := 40.0
const BTN_R := 24.0
const SWAP_ZONE := Rect2(0, 0, 124, 42)
const PINK := Color("ff2a6d")
const CYAN := Color("05d9e8")
const YELLOW := Color("f9f002")
const MAGENTA := Color("d300c5")

var move := Vector2.ZERO
var aim := Vector2.ZERO
var fire := false
var touch_mode := false
var override := false
var player
const BUFFER_MS := 100 # a press stays usable this long, so fast taps are never dropped
var q := {"kick": 0, "dash": 0, "swap": 0, "any": 0, "restart": 0} # time of the last press, 0 = none
var u := 3.0
var W := 640.0
var H := 360.0
var _l_id := -1
var _l_origin := Vector2.ZERO
var _l_vec := Vector2.ZERO
var _f_id := -1
var _f_vec := Vector2.ZERO
var _canvas: Node2D
var _font: Font


## Button centres on a `w` x `h` unit screen.
static func layout(w: float, h: float) -> Dictionary:
	return {
		"stick": Vector2(70, h - 74),
		"fire": Vector2(w - 62, h - 66),
		"kick": Vector2(w - 142, h - 50),
		"dash": Vector2(w - 124, h - 112),
	}


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
	u = minf(size.x, size.y) / 360.0
	W = size.x / u
	H = size.y / u


func press(n: String) -> void:
	q[n] = Time.get_ticks_msec()


## Returns true once per press, if it happened within the buffer window.
func take(n: String) -> bool:
	var at: int = q[n]
	if at == 0:
		return false
	q[n] = 0
	return Time.get_ticks_msec() - at <= BUFFER_MS


func clear() -> void:
	for k in q:
		q[k] = 0


func _input(event: InputEvent) -> void:
	if override:
		return
	if event is InputEventScreenTouch:
		touch_mode = true
		var p: Vector2 = event.position / u
		var at := layout(W, H)
		if event.pressed:
			press("any")
			if p.distance_to(at.fire) < FIRE_R + 6.0 and _f_id == -1:
				_f_id = event.index
				_f_vec = Vector2.ZERO
			elif p.distance_to(at.kick) < BTN_R + 6.0:
				press("kick")
			elif p.distance_to(at.dash) < BTN_R + 6.0:
				press("dash")
			elif SWAP_ZONE.has_point(p):
				press("swap")
			elif p.x < W / 2.0 and _l_id == -1:
				_l_id = event.index
				_l_origin = p
				_l_vec = Vector2.ZERO
		else:
			if event.index == _l_id:
				_l_id = -1
				_l_vec = Vector2.ZERO
			if event.index == _f_id:
				_f_id = -1
				_f_vec = Vector2.ZERO
	elif event is InputEventScreenDrag:
		var p: Vector2 = event.position / u
		if event.index == _l_id:
			_l_vec = ((p - _l_origin) / STICK_R).limit_length(1.0)
		elif event.index == _f_id:
			_f_vec = ((p - layout(W, H).fire) / FIRE_R).limit_length(1.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		touch_mode = false
		press("any")
		match event.physical_keycode:
			KEY_SPACE, KEY_SHIFT: press("dash")
			KEY_E, KEY_F: press("kick")
			KEY_Q: press("swap")
			KEY_R: press("restart")
	elif event is InputEventMouseButton and event.pressed:
		touch_mode = false
		match event.button_index:
			MOUSE_BUTTON_LEFT: press("any")
			MOUSE_BUTTON_RIGHT: press("kick")
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN: press("swap")


func _process(_delta: float) -> void:
	_measure()
	_canvas.queue_redraw()
	if override:
		return
	if touch_mode:
		move = _l_vec
		fire = _f_id != -1
		# Dragging the fire button aims; a plain press leaves aim to auto-aim.
		aim = _f_vec.normalized() if _f_vec.length() > 0.35 else Vector2.ZERO
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


# ---------------------------------------------------------------- drawing

func _draw_ui() -> void:
	if not touch_mode:
		return
	var at := layout(W, H)
	var alive: bool = player != null and is_instance_valid(player)

	# MOVE stick: rests in the corner, jumps to where the thumb lands.
	var held := _l_id != -1
	var base: Vector2 = _l_origin if held else at.stick
	_canvas.draw_circle(base * u, STICK_R * u, Color(0.1, 0.35, 0.4, 0.3 if held else 0.22))
	_ring(base, STICK_R, 48, Color(CYAN, 0.55 if held else 0.3), 2.0)
	var knob := base + _l_vec * STICK_R
	_canvas.draw_circle(knob * u, 17.0 * u, Color(0.25, 0.75, 0.82, 0.75 if held else 0.45))
	_text(knob, 17.0, "MOVE", 7.5, Color(0.02, 0.1, 0.14, 0.9))

	# HIT / FIRE: octagon; shows the aim direction while dragged.
	var firing := _f_id != -1
	_canvas.draw_circle(at.fire * u, FIRE_R * 0.94 * u, Color(0.35, 0.02, 0.1, 0.55 if firing else 0.3))
	_ring(at.fire, FIRE_R, 8, Color(PINK, 1.0 if firing else 0.85), 2.5)
	_ring(at.fire, FIRE_R - 6.0, 8, Color(PINK, 0.5), 1.2)
	if _f_vec.length() > 0.35:
		_canvas.draw_circle((at.fire + _f_vec * FIRE_R) * u, 9.0 * u, Color(1, 1, 1, 0.7))
	_text(at.fire, FIRE_R, "FIRE" if alive and player.weapon != "pipe" else "HIT", 13, Color(1.0, 0.45, 0.55))

	var label := "KICK"
	if alive:
		label = player.context()
	_round_button(at.kick, label, YELLOW if label == "EXEC" else MAGENTA)
	_round_button(at.dash, "DASH", CYAN)


func _ring(c: Vector2, r: float, sides: int, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in sides + 1:
		pts.append((c + Vector2.RIGHT.rotated(TAU * (i + 0.5) / sides) * r) * u)
	_canvas.draw_polyline(pts, col, width * u, true)


func _round_button(c: Vector2, text: String, col: Color) -> void:
	_canvas.draw_circle(c * u, BTN_R * u, Color(col.r * 0.25, col.g * 0.25, col.b * 0.3, 0.45))
	_ring(c, BTN_R, 40, Color(col, 0.9), 2.0)
	_text(c, BTN_R, text, 9, col.lightened(0.25))


func _text(c: Vector2, half: float, text: String, size: float, col: Color) -> void:
	_canvas.draw_string(_font, Vector2(c.x - half, c.y + size * 0.36) * u, text, HORIZONTAL_ALIGNMENT_CENTER, half * 2.0 * u, int(size * u), col)
