extends Node2D
## Everything audiovisual is generated here in code: pixel textures, WAV
## sound effects, persistent decals (blood, casings, corpses) and short-lived
## particles. Generated assets are cached statically so restarts are free.

const RATE := 22050
const MAX_DECALS := 1600
const BLOOD := [Color("8e0b1c"), Color("b3122a"), Color("6a0714")]
const PINK := Color("ff2a6d")
const CYAN := Color("05d9e8")

# zone index -> [colour A, line colour, pattern, colour A for odd cells]
const FLOORS := [
	["2a2833", "33313d", 0, "2a2833"], # entry
	["120c1c", "2a1a40", 1, "120c1c"], # dance
	["3a1446", "52206a", 4, "3a1446"], # vip
	["b8bcc2", "5a6068", 1, "747a84"], # kitchen
	["4a2c1c", "341e12", 2, "4a2c1c"], # bar
	["1f5a5a", "174444", 3, "1f5a5a"], # restroom
	["34343a", "2a2a30", 0, "303036"], # storage
	["4a1420", "5e1c2c", 4, "4a1420"], # corridor
	["50545c", "3c4048", 1, "50545c"], # elevator lobby
]

static var _tex := {}
static var _img := {}
static var _snd := {}
static var _music: AudioStreamWAV

var world
var decal_node: Node2D
var decals: Array = []
var parts: Array = [] # [pos, vel, life, color]
var tracers: Array = [] # [a, b, life, color]
var rings: Array = [] # [pos, radius, max_radius]
var popups: Array = [] # [pos, text, life, color]
var shake := 0.0
var _pool: Array = []
var _next := 0
var _last := {}
var _font: Font
var _was_busy := false


func _init() -> void:
	z_index = 50
	decal_node = Node2D.new()
	decal_node.draw.connect(_draw_decals)


func _ready() -> void:
	_font = ThemeDB.fallback_font
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


# ---------------------------------------------------------------- sound

func play(n: String, pitch := 1.0, vol := -7.0) -> void:
	var now := Time.get_ticks_msec()
	if int(_last.get(n, -1000)) > now - 40:
		return
	_last[n] = now
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = snd(n)
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.volume_db = vol
	p.play()


static func snd(n: String) -> AudioStreamWAV:
	if not _snd.has(n):
		var s: AudioStreamWAV
		match n:
			"pistol": s = _synth(0.18, 900, 120, 0.75, 9, 0.9)
			"shotgun": s = _synth(0.4, 300, 50, 0.85, 6, 0.6, false, 1.0)
			"swing": s = _synth(0.14, 500, 180, 0.9, 5, 0.25)
			"hit": s = _synth(0.12, 160, 60, 0.5, 8, 0.5)
			"kick": s = _synth(0.12, 220, 70, 0.4, 9, 0.5)
			"glass": s = _synth(0.35, 4200, 2600, 0.7, 7, 1.0)
			"door": s = _synth(0.22, 110, 45, 0.5, 7, 0.4)
			"groan": s = _synth(0.5, 95, 60, 0.25, 2.5, 0.2, true, 0.45)
			"boom": s = _synth(0.7, 90, 25, 0.8, 4, 0.3, false, 1.0)
			"die": s = _synth(0.25, 240, 50, 0.6, 6, 0.4)
			"pickup": s = _synth(0.12, 660, 1320, 0.0, 4, 1.0, true, 0.35)
			"dash": s = _synth(0.15, 300, 900, 0.85, 5, 0.3)
			"exec": s = _synth(0.3, 130, 35, 0.6, 5, 0.5)
			"grab": s = _synth(0.25, 180, 420, 0.2, 3, 1.0, true, 0.5)
			"clear": s = _synth(0.5, 440, 1760, 0.0, 2.5, 1.0, true, 0.35)
			"fuse": s = _synth(0.45, 200, 900, 0.2, 0.5, 1.0, true, 0.4)
			_: s = _synth(0.05, 1500, 1200, 0.3, 10, 1.0, true, 0.3) # "empty"
		_snd[n] = s
	return _snd[n]


## One-shot synth: pitch sweep f0->f1 mixed with low-passed noise, exp decay.
static func _synth(dur: float, f0: float, f1: float, noise: float, decay: float, lp := 1.0, square := false, vol := 0.8) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([dur, f0, f1])
	var ph := 0.0
	var z := 0.0
	for i in n:
		var t := float(i) / n
		ph += f0 * pow(f1 / f0, t) / RATE
		var o := sin(ph * TAU)
		if square:
			o = signf(o)
		z += lp * (rng.randf_range(-1.0, 1.0) - z)
		var s := (o * (1.0 - noise) + z * noise * (2.0 - lp)) * exp(-t * decay) * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data, RATE)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Four-second looping synth bassline with kick and hats.
static func music() -> AudioStreamWAV:
	if _music == null:
		var rate := 11025
		var step := rate / 4 # one 8th note at 120 BPM
		var notes := [55.0, 55.0, 110.0, 55.0, 43.65, 43.65, 87.3, 43.65, 49.0, 49.0, 98.0, 49.0, 41.2, 41.2, 82.4, 61.74]
		var n := step * 16
		var data := PackedByteArray()
		data.resize(n * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1989
		var ph := 0.0
		for i in n:
			var k := i / step
			var t := float(i % step) / step
			ph += notes[k] / rate
			var s := (fposmod(ph, 1.0) * 2.0 - 1.0) * 0.32 * (1.0 - t * 0.7)
			if k % 2 == 0:
				s += sin(TAU * 48.0 * t * (1.6 - t)) * exp(-t * 7.0) * 0.6
			else:
				s += rng.randf_range(-1.0, 1.0) * exp(-t * 28.0) * 0.14
			data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
		_music = _wav(data, rate)
		_music.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_music.loop_begin = 0
		_music.loop_end = n
	return _music


static func warm() -> void:
	for n in ["pistol", "shotgun", "swing", "hit", "kick", "glass", "door", "groan", "boom", "die",
			"pickup", "dash", "exec", "grab", "clear", "fuse", "empty"]:
		snd(n)
	for n in ["player", "shambler", "runner", "bloater", "glass", "door", "door_locked",
			"w_pipe", "w_pistol", "w_shotgun"]:
		tex(n)


# ---------------------------------------------------------------- textures

static func tex(n: String) -> Texture2D:
	if not _tex.has(n):
		_tex[n] = ImageTexture.create_from_image(img(n))
	return _tex[n]


static func img(n: String) -> Image:
	if not _img.has(n):
		_img[n] = _make(n)
	return _img[n]


static func _make(n: String) -> Image:
	if n.begins_with("floor_"):
		var p := n.split("_")
		var f: Array = FLOORS[int(p[1])]
		return _tile(Color(f[3] if p[2] == "1" else f[0]), Color(f[1]), f[2], int(p[1]) * 7 + int(p[2]))
	match n:
		"player": return _actor(14, Color("e6dfcc"), Color("5a3a22"), Color("e6dfcc"), 0)
		"shambler": return _actor(14, Color("5c7a48"), Color("a3b57c"), Color("a3b57c"), 6)
		"runner": return _actor(12, Color("9c3a3a"), Color("d6a48e"), Color("d6a48e"), 5)
		"bloater": return _actor(20, Color("a59a3a"), Color("d2cc78"), Color("8a8030"), 4)
		"wall": return _tile(Color("1a1026"), Color("261838"), 2, 99)
		"table":
			var t := _solid(16, 16, Color("7a5230"), Color("3a2614"))
			t.fill_rect(Rect2i(2, 2, 12, 1), Color("9a6c42"))
			return t
		"exit":
			var e := _solid(16, 16, Color("12301c"), Color("1c5a30"))
			e.fill_rect(Rect2i(6, 4, 4, 8), Color("30ff70"))
			return e
		"glass":
			var g := _solid(16, 16, Color(0.4, 0.9, 1.0, 0.28), Color(0.7, 1.0, 1.0, 0.8))
			for i in 5:
				g.set_pixel(4 + i, 9 - i, Color(1, 1, 1, 0.8))
				g.set_pixel(8 + i, 12 - i, Color(1, 1, 1, 0.5))
			return g
		"door":
			var d := _solid(32, 6, Color("b06a30"), Color("5a3214"))
			d.fill_rect(Rect2i(26, 2, 3, 2), Color("ffd866"))
			return d
		"door_locked": return _solid(32, 6, Color("8890a0"), Color("ff2a6d"))
		"w_pipe": return _solid(11, 2, Color("9aa0aa"), Color("9aa0aa"))
		"w_pistol":
			var w := _solid(7, 3, Color("30303a"), Color("30303a"))
			w.fill_rect(Rect2i(0, 0, 2, 3), Color("6a4a2a"))
			return w
		_: # "w_shotgun"
			var w2 := _solid(13, 3, Color("3a3a44"), Color("3a3a44"))
			w2.fill_rect(Rect2i(0, 0, 4, 3), Color("7a4a24"))
			return w2


static func _solid(w: int, h: int, fill: Color, border: Color) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(border)
	if w > 2 and h > 2:
		im.fill_rect(Rect2i(1, 1, w - 2, h - 2), fill)
	return im


static func _tile(a: Color, b: Color, mode: int, sd: int) -> Image:
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for y in 16:
		for x in 16:
			var c := a
			match mode:
				0:
					if rng.randf() < 0.12: c = b
				1:
					if x == 0 or y == 0: c = b
				2:
					if y % 4 == 0 or x == (y / 4 * 5 + 3) % 16: c = b
				3:
					if x % 4 == 0 or y % 4 == 0: c = b
				4:
					if (x + y) % 8 == 0 or (x - y + 16) % 8 == 0: c = b
			im.set_pixel(x, y, c)
	return im


## Top-down figure facing +X: shoulders, head, optional outstretched arms.
static func _actor(size: int, body: Color, head: Color, arm: Color, arms: int) -> Image:
	var im := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2.0
	var rx := size * 0.2
	var ry := size * 0.4
	var hr := size * 0.19
	for y in size:
		for x in size:
			var dx := x + 0.5 - c
			var dy := y + 0.5 - c
			var col := Color(0, 0, 0, 0)
			var e := (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry)
			if arms > 0 and dx > 0 and dx < arms and absf(absf(dy) - ry * 0.72) < 1.1:
				col = arm
			if e <= 1.0:
				col = body.darkened(0.35) if e > 0.72 else body
			if (dx - 0.5) * (dx - 0.5) + dy * dy <= hr * hr:
				col = head
			im.set_pixel(x, y, col)
	return im


# ---------------------------------------------------------------- decals

func _add(d: Array) -> void:
	decals.append(d)
	if decals.size() > MAX_DECALS:
		decals = decals.slice(200)
	decal_node.queue_redraw()


func blood(pos: Vector2, dir: Vector2, n: int, spread := 12.0) -> void:
	for i in n:
		var p := pos + dir * randf_range(0.0, 28.0) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * spread * randf()
		if world.solid_at(p):
			continue
		var s := float(randi_range(1, 3))
		_add([0, p.floor(), Vector2(s, s), BLOOD[randi() % 3]])
	for i in mini(n, 10):
		var v := (dir * randf_range(40, 160)) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 60.0
		parts.append([pos, v, randf_range(0.15, 0.35), BLOOD[1]])


func casing(pos: Vector2) -> void:
	var p := pos + Vector2(randf_range(-7, 7), randf_range(-7, 7))
	if not world.solid_at(p):
		_add([0, p.floor(), Vector2(2, 1) if randf() < 0.5 else Vector2(1, 2), Color("e8c040")])


func shards(pos: Vector2) -> void:
	for i in 14:
		var p := pos + Vector2(randf_range(-14, 14), randf_range(-14, 14))
		if not world.solid_at(p):
			_add([0, p.floor(), Vector2(1, 1), Color(0.75, 1.0, 1.0, 0.9)])
		parts.append([pos, Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 120.0, 0.25, Color(0.8, 1, 1)])


func corpse(kind: String, pos: Vector2, rot: float, tint := Color(0.5, 0.42, 0.42)) -> void:
	_add([1, pos, tex(kind), rot, tint])


func _draw_decals() -> void:
	for d in decals:
		if d[0] == 0:
			decal_node.draw_rect(Rect2(d[1], d[2]), d[3])
		else:
			var t: Texture2D = d[2]
			decal_node.draw_set_transform(d[1], d[3])
			decal_node.draw_texture(t, -t.get_size() / 2.0, d[4])
			decal_node.draw_set_transform(Vector2.ZERO, 0.0)


# ---------------------------------------------------------------- transient

func tracer(a: Vector2, b: Vector2, col := Color(1, 0.95, 0.6)) -> void:
	tracers.append([a, b, 0.06, col])


func spark(pos: Vector2) -> void:
	for i in 4:
		parts.append([pos, Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 90.0, 0.12, Color(1, 0.9, 0.5)])


func ring(pos: Vector2, max_r: float) -> void:
	rings.append([pos, 4.0, max_r])


func popup(pos: Vector2, text: String, col := Color(1, 1, 1)) -> void:
	popups.append([pos, text, 0.8, col])


func add_shake(a: float) -> void:
	shake = maxf(shake, a)


func _process(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 28.0)
	for p in parts:
		p[0] += p[1] * delta
		p[1] *= 0.88
		p[2] -= delta
	for t in tracers:
		t[2] -= delta
	for r in rings:
		r[1] += delta * 260.0
	for p in popups:
		p[0].y -= delta * 22.0
		p[2] -= delta
	parts = parts.filter(func(p): return p[2] > 0.0)
	tracers = tracers.filter(func(t): return t[2] > 0.0)
	rings = rings.filter(func(r): return r[1] < r[2])
	popups = popups.filter(func(p): return p[2] > 0.0)
	var busy := not (parts.is_empty() and tracers.is_empty() and rings.is_empty() and popups.is_empty())
	if busy or _was_busy:
		queue_redraw()
	_was_busy = busy


func _draw() -> void:
	for t in tracers:
		draw_line(t[0], t[1], t[3], 1.0)
	for p in parts:
		draw_rect(Rect2(p[0], Vector2(2, 2)), p[3])
	for r in rings:
		var a: float = 1.0 - r[1] / r[2]
		draw_arc(r[0], r[1], 0, TAU, 24, Color(1, 0.8, 0.3, a), 3.0)
	for p in popups:
		draw_string(_font, p[0] + Vector2(-40, 0), p[1], HORIZONTAL_ALIGNMENT_CENTER, 80, 8, Color(p[3], minf(1.0, p[2] * 3.0)))
