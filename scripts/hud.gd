extends CanvasLayer
## Heads-up display: weapon box, infected pill + floor progress bar, combo
## badge, score, grab prompt, death and floor-clear screens.
##
## Layout is in "units": the SHORT side of the screen is always 360 units,
## so `W` x `H` is 640x360 on a 16:9 landscape screen and 360x800 on a 9:20
## portrait phone. `layout()` places the same components for both shapes
## (one row in landscape, stacked rows in portrait); everything is
## multiplied by `u` (pixels per unit) when drawn, so text stays sharp.

const Fx = preload("res://scripts/fx.gd")

const PINK := Color("ff2a6d")
const CYAN := Color("05d9e8")
const YELLOW := Color("f9f002")
const MAGENTA := Color("d300c5")
const PANEL := Color(0.05, 0.03, 0.1, 0.78)
const CENTER := HORIZONTAL_ALIGNMENT_CENTER
const RIGHT := HORIZONTAL_ALIGNMENT_RIGHT

var main
var u := 3.0
var W := 640.0
var H := 360.0
var _canvas: Node2D
var _vignette: Sprite2D
var _font: Font


## Where each HUD component goes on a `w` x `h` unit screen. "fullscreen" is
## the slot kept free for the web page's fullscreen toggle.
static func layout(w: float, _h: float) -> Dictionary:
	var slot := Rect2(w - 34, 8, 26, 26)
	if w >= 520.0:
		return {
			"weapon": Rect2(8, 8, 112, 26),
			"infected": Rect2(w / 2 - 86, 8, 112, 21),
			"bar": Rect2(w / 2 - 86, 31, 112, 3),
			"combo": Rect2(w / 2 + 32, 8, 58, 26),
			"score": Rect2(w - 34 - 6 - 110, 8, 110, 26),
			"fullscreen": slot,
		}
	return {
		"weapon": Rect2(8, 8, 104, 26),
		"infected": Rect2(118, 8, w - 118 - 42, 26),
		"bar": Rect2(8, 40, w - 16, 5),
		"combo": Rect2(8, 51, 76, 20),
		"score": Rect2(w - 8 - 120, 51, 120, 20),
		"fullscreen": slot,
	}


func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
	_vignette = Sprite2D.new()
	_vignette.texture = Fx.tex("vignette")
	_vignette.centered = false
	_vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_vignette)
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)


func _process(_delta: float) -> void:
	var size := get_viewport().get_visible_rect().size
	u = minf(size.x, size.y) / 360.0
	W = size.x / u
	H = size.y / u
	_vignette.scale = size / _vignette.texture.get_size()
	_canvas.queue_redraw()


func _box(r: Rect2, col: Color, filled := true, width := 1.0) -> void:
	_canvas.draw_rect(Rect2(r.position * u, r.size * u), col, filled, -1.0 if filled else width * u)


## Text centred vertically in `r`, aligned horizontally inside it.
func _label(r: Rect2, text: String, size: float, col: Color, align := CENTER, shadow := true) -> void:
	var px := int(size * u)
	var at := Vector2(r.position.x, r.position.y + r.size.y / 2.0 + size * 0.36) * u
	if shadow:
		_canvas.draw_string(_font, at + Vector2(0.6, 0.6) * u, text, align, r.size.x * u, px, Color(0, 0, 0, 0.8))
	_canvas.draw_string(_font, at, text, align, r.size.x * u, px, col)


func _line(y: float, text: String, size: float, col: Color) -> void:
	_label(Rect2(0, y, W, size), text, size, col)


func _draw_hud() -> void:
	var p = main.player
	if p == null or not is_instance_valid(p):
		return
	var L := layout(W, H)
	var touch: bool = main.controls.touch_mode

	# Weapon box (tap to swap on touch).
	var wr: Rect2 = L.weapon
	var w: String = p.weapon
	_box(wr, Color(0.3, 0.08, 0.42, 0.85))
	_box(wr, CYAN, false, 1.5)
	var icon: Texture2D = Fx.tex("w_" + w)
	var isz := icon.get_size() * 2.2
	_canvas.draw_texture_rect(icon, Rect2((wr.position + Vector2(20, wr.size.y / 2.0) - isz / 2.0) * u, isz * u), false, Color(1.25, 1.25, 1.4))
	_label(Rect2(wr.position.x + 40, wr.position.y + 2, wr.size.x - 42, 12), w.to_upper(), 9, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	var sub := "SILENT" if w == "pipe" else "LOUD  %d LEFT" % p.ammo[w]
	_label(Rect2(wr.position.x + 40, wr.position.y + 13, wr.size.x - 42, 10), sub, 6.5, CYAN if w == "pipe" else YELLOW, HORIZONTAL_ALIGNMENT_LEFT)

	# Infected pill and floor progress bar.
	var left: int = main.world.enemy_list.size()
	var ir: Rect2 = L.infected
	var icol := PINK if left > 0 else Color("30ff70")
	_box(ir, PANEL)
	_box(ir, icol, false, 1.5)
	_label(ir, "INFECTED: %02d" % left if left > 0 else "EXIT OPEN", 10, icol)
	var br: Rect2 = L.bar
	_box(br, Color(0.2, 0.1, 0.3, 0.9))
	var total: int = left + main.kills
	if total > 0:
		_box(Rect2(br.position, Vector2(br.size.x * main.kills / total, br.size.y)), MAGENTA)

	# Combo badge.
	if main.combo > 1 and main.combo_t > 0.0:
		var cr: Rect2 = L.combo
		_box(cr, YELLOW)
		_label(Rect2(cr.position, cr.size - Vector2(0, 3)), "COMBO x%d" % main.combo, 9, Color("1a1026"), CENTER, false)
		_box(Rect2(cr.position.x + 3, cr.end.y - 4, (cr.size.x - 6) * main.combo_t / main.COMBO_TIME, 2), Color("1a1026"))

	_label(L.score, "%07d" % main.score, 14, Color.WHITE, RIGHT)

	var cy := H / 2.0
	if main.state == "play" and main.floor_time < 5.0 and main.deaths == 0:
		if touch:
			_line(cy + 40, "LEFT STICK MOVES   HOLD FIRE, DRAG IT TO AIM", 8, Color(1, 1, 1, 0.75))
		elif W >= 520.0:
			_line(H - 26, "WASD MOVE   MOUSE AIM/FIRE   SPACE DASH   E / RMB KICK   Q SWAP", 8, Color(1, 1, 1, 0.75))

	if p.grab_t > 0.0:
		_box(Rect2(0, 0, W, H), Color(0.8, 0.0, 0.1, 0.22))
		_line(cy - 70, "GRABBED!  KICK!", 24, YELLOW)
		_box(Rect2(W / 2 - 100, cy - 42, 200.0 * p.grab_t / p.GRAB_WINDOW, 5), PINK)

	if main.state == "dead":
		_box(Rect2(0, 0, W, H), Color(0.25, 0.0, 0.04, 0.5))
		_line(cy - 44, "YOU DIED", 32, PINK)
		_line(cy - 4, main.cause, 10, Color.WHITE)
		_line(cy + 20, "TAP TO RESTART" if touch else "PRESS R / CLICK TO RESTART", 10, CYAN)
	elif main.state == "clear":
		_box(Rect2(0, 0, W, H), Color(0.0, 0.05, 0.1, 0.6))
		_line(cy - 54, "FLOOR CLEARED", 28, CYAN)
		_line(cy - 14, "SCORE %d    KILLS %d" % [main.score, main.kills], 10, Color.WHITE)
		_line(cy + 2, "TIME %.1fs    DEATHS %d" % [main.floor_time, main.deaths], 10, Color.WHITE)
		_line(cy + 26, "TAP FOR NEXT FLOOR" if touch else "PRESS ANY KEY FOR NEXT FLOOR", 10, YELLOW)
