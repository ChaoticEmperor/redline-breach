extends Node2D
## Short-lived effects drawn in the world: tracers and muzzle flashes, in hard
## colour steps on the art-pixel grid (no alpha fades), plus the camera shake
## budget. Lives inside the pixel-true view, so everything lands on art pixels.

const HOT := [Color("ffffff"), Color("fff1a8"), Color("ffb02e"), Color("ff5a1f")]
const TRACER_LIFE := 0.06
const FLASH_LIFE := 0.05
const SHAKE_FADE := 30.0 # art px of shake removed per second: big hits settle at a known time

var tracers: Array = [] # [from, to, life]
var flashes: Array = [] # [pos, life]
var shake := 0.0


func tracer(from: Vector2, to: Vector2) -> void:
	tracers.append([from, to, TRACER_LIFE])


func flash(at: Vector2) -> void:
	flashes.append([at, FLASH_LIFE])


func add_shake(px: float) -> void:
	shake = maxf(shake, px)


func _process(delta: float) -> void:
	shake = maxf(0.0, shake - SHAKE_FADE * delta)
	for a in [tracers, flashes]:
		for i in range(a.size() - 1, -1, -1):
			a[i][a[i].size() - 1] -= delta
			if a[i][a[i].size() - 1] <= 0.0:
				a.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for t in tracers:
		var step := int(clampf((1.0 - t[2] / TRACER_LIFE) * HOT.size(), 0, HOT.size() - 1))
		draw_line(t[0], t[1], HOT[step], 1.0)
	for f in flashes:
		var step := int(clampf((1.0 - f[1] / FLASH_LIFE) * HOT.size(), 0, HOT.size() - 1))
		draw_circle(f[0], 3.0 - step * 0.5, HOT[step])
