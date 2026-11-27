extends Node
## Procedural sound: every effect and the music loop are synthesised in code as
## AudioStreamWAV, cached statically so restarts are free. Carried over from the
## 3/4 game's fx.gd unchanged; the names are gameplay events, not files.

const RATE := 22050
const NAMES := ["pistol", "shotgun", "swing", "hit", "kick", "glass", "door", "groan", "boom", "die",
		"pickup", "exec", "grab", "clear", "fuse", "empty"]

static var _snd := {}
static var _music: AudioStreamWAV

var _pool: Array = []
var _next := 0
var _last := {}


func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


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



## Builds every sound once, so the first shot of a floor does not stall.
static func warm() -> void:
	for n in NAMES:
		snd(n)
	music()
