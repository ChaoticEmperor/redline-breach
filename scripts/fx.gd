extends Node2D
## Short-lived effects drawn in the world (tracers, muzzle flashes, glass shards, "!" pops) in
## hard colour steps on the art-pixel grid, plus the camera shake budget. Blood is persistent
## and lives in `Decals` under everything (the floor is the record of the fight).

const HOT := [Color("ffffff"), Color("fff1a8"), Color("ffb02e"), Color("ff5a1f")]
const TRACER_LIFE := 0.06
const FLASH_LIFE := 0.05
const SHAKE_FADE := 30.0 # art px of shake removed per second

var tracers: Array = [] # [from, to, life]
var flashes: Array = [] # [pos, life]
var shards: Array = [] # [pos, vel, life]
var pops: Array = [] # [pos, text, life]
var shake := 0.0
var _font: Font


func _ready() -> void:
	z_index = 10
	_font = ThemeDB.fallback_font


func tracer(from: Vector2, to: Vector2) -> void:
	tracers.append([from, to, TRACER_LIFE])


func flash(at: Vector2) -> void:
	flashes.append([at, FLASH_LIFE])


func add_shake(px: float) -> void:
	shake = maxf(shake, px)


func glass(at: Vector2, dir: Vector2, rng: RandomNumberGenerator) -> void:
	for i in 10:
		var v := (dir.rotated(rng.randf_range(-0.9, 0.9)) * rng.randf_range(40, 140))
		shards.append([at + Vector2(rng.randf_range(-12, 12), 0).rotated(dir.angle() + PI / 2), v, rng.randf_range(0.25, 0.5)])


func pop(at: Vector2, text: String) -> void:
	pops.append([at, text, 0.6])


func _process(delta: float) -> void:
	shake = maxf(0.0, shake - SHAKE_FADE * delta)
	for a in [tracers, flashes, shards, pops]:
		for i in range(a.size() - 1, -1, -1):
			var e: Array = a[i]
			e[e.size() - 1] -= delta
			if e[e.size() - 1] <= 0.0:
				a.remove_at(i)
	for s in shards:
		s[0] += s[1] * delta
		s[1] *= 0.9
	queue_redraw()


func _draw() -> void:
	for t in tracers:
		var step := int(clampf((1.0 - t[2] / TRACER_LIFE) * HOT.size(), 0, HOT.size() - 1))
		draw_line(t[0], t[1], HOT[step], 1.0)
	for f in flashes:
		var step := int(clampf((1.0 - f[1] / FLASH_LIFE) * HOT.size(), 0, HOT.size() - 1))
		draw_circle(f[0], 3.0 - step * 0.5, HOT[step])
	for s in shards:
		draw_rect(Rect2(s[0].floor(), Vector2(1, 1)), Color("dff4f6") if s[2] > 0.2 else Color("a8d4d8"))
	for p in pops:
		var y: float = (0.6 - p[2]) * 10.0
		draw_string(_font, p[0] + Vector2(-2, -y + 1), p[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
		draw_string(_font, p[0] + Vector2(-3, -y), p[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffc93c"))
