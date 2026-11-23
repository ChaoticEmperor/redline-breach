extends CanvasLayer
## Heads-up display: weapon/ammo, score and combo, remaining zombies,
## grab-break prompt, death and floor-clear screens.
##
## Layout is written in "units": the screen is always 360 units tall and
## `W` units wide (640 at 16:9, wider on 20:9 / 21:9 phones). Panels anchor
## to the corners/centre from `W`, and everything is multiplied by `u`
## (pixels per unit) when drawn, so text is rasterised at native size.

const Fx = preload("res://scripts/fx.gd")

const PINK := Color("ff2a6d")
const CYAN := Color("05d9e8")
const YELLOW := Color("f9f002")

var main
var u := 3.0
var W := 640.0
var _canvas: Node2D
var _vignette: Sprite2D
var _font: Font


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
	u = size.y / 360.0
	W = size.x / u
	_vignette.scale = size / _vignette.texture.get_size()
	_canvas.queue_redraw()


func _rect(x: float, y: float, w: float, h: float, col: Color, filled := true) -> void:
	_canvas.draw_rect(Rect2(x * u, y * u, w * u, h * u), col, filled, -1.0 if filled else u)


func _text(x: float, y: float, text: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var w := width * u if width > 0.0 else -1.0
	var px := int(size * u)
	_canvas.draw_string(_font, Vector2(x + 0.6, y + 0.6) * u, text, align, w, px, Color(0, 0, 0, 0.8))
	_canvas.draw_string(_font, Vector2(x, y) * u, text, align, w, px, col)


func _draw_hud() -> void:
	var p = main.player
	if p == null or not is_instance_valid(p):
		return
	var mid := W / 2.0
	var touch: bool = main.controls.touch_mode
	const CENTER := HORIZONTAL_ALIGNMENT_CENTER
	const RIGHT := HORIZONTAL_ALIGNMENT_RIGHT

	# Top-left: weapon panel (tap to swap on touch).
	_rect(4, 4, 124, 26, Color(0.04, 0.02, 0.08, 0.7))
	_rect(4, 4, 124, 26, CYAN, false)
	_rect(4, 4, 2, 26, PINK)
	var w: String = p.weapon
	_text(12, 16, w.to_upper(), 10, Color.WHITE)
	_text(12, 26, "SILENT" if w == "pipe" else "LOUD  x%02d" % p.ammo[w], 8, CYAN if w == "pipe" else YELLOW)
	if p.owned.size() > 1:
		_text(86, 16, "TAP SWAP" if touch else "[Q] SWAP", 6, Color(1, 1, 1, 0.5))

	# Top-right: score and combo, below the web page's fullscreen button.
	_text(W - 204, 40, "%07d" % main.score, 12, Color.WHITE, RIGHT, 200)
	if main.combo > 1 and main.combo_t > 0.0:
		var k: float = main.combo_t / main.COMBO_TIME
		_text(W - 204, 54, "x%d COMBO" % main.combo, 10, YELLOW, RIGHT, 200)
		_rect(W - 4 - 60 * k, 58, 60 * k, 2, YELLOW)

	# Top-centre: infected count.
	var left: int = main.world.enemy_list.size()
	if left > 0:
		_text(mid - 100, 14, "INFECTED  %02d" % left, 8, PINK, CENTER, 200)
	elif main.state == "play":
		_text(mid - 150, 16, "FLOOR CLEAR - GET TO THE ELEVATOR", 10, Color("30ff70"), CENTER, 300)

	if main.state == "play" and main.floor_time < 5.0 and main.deaths == 0:
		var hint := "L-STICK MOVE   R-STICK AIM, PUSH TO FIRE" if touch \
			else "WASD MOVE   MOUSE AIM/FIRE   SPACE DASH   E / RMB KICK   Q SWAP"
		_text(mid - 250, 340, hint, 8, Color(1, 1, 1, 0.75), CENTER, 500)

	if p.grab_t > 0.0:
		_rect(0, 0, W, 360, Color(0.8, 0.0, 0.1, 0.22))
		_text(mid - 200, 120, "GRABBED!  KICK!", 24, YELLOW, CENTER, 400)
		_rect(mid - 100, 132, 200.0 * p.grab_t / p.GRAB_WINDOW, 5, PINK)

	if main.state == "dead":
		_rect(0, 0, W, 360, Color(0.25, 0.0, 0.04, 0.5))
		_text(mid - 200, 160, "YOU DIED", 32, PINK, CENTER, 400)
		_text(mid - 200, 182, main.cause, 10, Color.WHITE, CENTER, 400)
		_text(mid - 200, 206, "TAP TO RESTART" if touch else "PRESS R / CLICK TO RESTART", 10, CYAN, CENTER, 400)
	elif main.state == "clear":
		_rect(0, 0, W, 360, Color(0.0, 0.05, 0.1, 0.6))
		_text(mid - 200, 140, "FLOOR CLEARED", 32, CYAN, CENTER, 400)
		_text(mid - 200, 168, "SCORE %d    KILLS %d    TIME %.1fs    DEATHS %d" % [main.score, main.kills, main.floor_time, main.deaths], 10, Color.WHITE, CENTER, 400)
		_text(mid - 200, 196, "TAP FOR NEXT FLOOR" if touch else "PRESS ANY KEY FOR NEXT FLOOR", 10, YELLOW, CENTER, 400)
