extends CanvasLayer
## Heads-up display: weapon/ammo, score and combo, remaining zombies,
## grab-break prompt, death and floor-clear screens.

const Fx = preload("res://scripts/fx.gd")

const PINK := Color("ff2a6d")
const CYAN := Color("05d9e8")
const YELLOW := Color("f9f002")

var main
var _canvas: Node2D
var _font: Font


func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
	var vignette := Sprite2D.new()
	vignette.texture = Fx.tex("vignette")
	vignette.centered = false
	vignette.scale = Vector2(10, 10)
	vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(vignette)
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _text(pos: Vector2, text: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_canvas.draw_string(_font, pos + Vector2(1, 1), text, align, width, size, Color(0, 0, 0, 0.8))
	_canvas.draw_string(_font, pos, text, align, width, size, col)


func _draw_hud() -> void:
	var p = main.player
	if p == null or not is_instance_valid(p):
		return
	var c := _canvas

	# Weapon panel (tap to swap on touch).
	c.draw_rect(Rect2(4, 4, 124, 26), Color(0.04, 0.02, 0.08, 0.7))
	c.draw_rect(Rect2(4, 4, 124, 26), CYAN, false, 1.0)
	c.draw_rect(Rect2(4, 4, 2, 26), PINK)
	var w: String = p.weapon
	_text(Vector2(12, 16), w.to_upper(), 10, Color.WHITE)
	_text(Vector2(12, 26), "SILENT" if w == "pipe" else "LOUD  x%02d" % p.ammo[w], 8, CYAN if w == "pipe" else YELLOW)
	if p.owned.size() > 1:
		_text(Vector2(86, 16), "[Q] SWAP" if not main.controls.touch_mode else "TAP SWAP", 6, Color(1, 1, 1, 0.5))

	# Score and combo.
	_text(Vector2(436, 16), "%07d" % main.score, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	if main.combo > 1 and main.combo_t > 0.0:
		_text(Vector2(436, 30), "x%d COMBO" % main.combo, 10, YELLOW, HORIZONTAL_ALIGNMENT_RIGHT, 200)
		c.draw_rect(Rect2(636 - 60 * main.combo_t / main.COMBO_TIME, 34, 60 * main.combo_t / main.COMBO_TIME, 2), YELLOW)

	var left: int = main.world.enemy_list.size()
	if left > 0:
		_text(Vector2(220, 14), "INFECTED  %02d" % left, 8, PINK, HORIZONTAL_ALIGNMENT_CENTER, 200)
	elif main.state == "play":
		_text(Vector2(170, 16), "FLOOR CLEAR - GET TO THE ELEVATOR", 10, Color("30ff70"), HORIZONTAL_ALIGNMENT_CENTER, 300)

	if main.state == "play" and main.floor_time < 5.0 and main.deaths == 0:
		var hint := "L-STICK MOVE   R-STICK AIM, PUSH TO FIRE" if main.controls.touch_mode \
			else "WASD MOVE   MOUSE AIM/FIRE   SPACE DASH   E / RMB KICK   Q SWAP"
		_text(Vector2(70, 340), hint, 8, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 500)

	if p.grab_t > 0.0:
		c.draw_rect(Rect2(0, 0, 640, 360), Color(0.8, 0.0, 0.1, 0.22))
		_text(Vector2(120, 120), "GRABBED!  KICK!", 24, YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 400)
		c.draw_rect(Rect2(220, 132, 200.0 * p.grab_t / p.GRAB_WINDOW, 5), PINK)

	if main.state == "dead":
		c.draw_rect(Rect2(0, 0, 640, 360), Color(0.25, 0.0, 0.04, 0.5))
		_text(Vector2(120, 160), "YOU DIED", 32, PINK, HORIZONTAL_ALIGNMENT_CENTER, 400)
		_text(Vector2(120, 182), main.cause, 10, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 400)
		_text(Vector2(120, 206), "TAP TO RESTART" if main.controls.touch_mode else "PRESS R / CLICK TO RESTART", 10, CYAN, HORIZONTAL_ALIGNMENT_CENTER, 400)
	elif main.state == "clear":
		c.draw_rect(Rect2(0, 0, 640, 360), Color(0.0, 0.05, 0.1, 0.6))
		_text(Vector2(120, 140), "FLOOR CLEARED", 32, CYAN, HORIZONTAL_ALIGNMENT_CENTER, 400)
		_text(Vector2(120, 168), "SCORE %d    KILLS %d    TIME %.1fs    DEATHS %d" % [main.score, main.kills, main.floor_time, main.deaths], 10, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 400)
		_text(Vector2(120, 196), "TAP FOR NEXT FLOOR" if main.controls.touch_mode else "PRESS ANY KEY FOR NEXT FLOOR", 10, YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 400)
