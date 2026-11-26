extends Node2D
## Everything audiovisual is generated here in code: pixel textures, WAV
## sound effects, persistent decals (blood, casings, corpses) and short-lived
## particles. Generated assets are cached statically so restarts are free.

const RATE := 22050
const MAX_DECALS := 320 # per room
const SPRITE_DIR := "res://assets/sprites/"
const SPRITE_PX := 4.0
const PropAtlas = preload("res://scripts/prop_atlas.gd")
const InfectedAtlas = preload("res://scripts/infected_atlas.gd")
const CELL := 64          # one pose in the character sheet
const ART_SCALE := 0.5    # character sheet pixels -> world pixels (same pixel size as the props)
# who -> [sheet row, {animation: [first frame, frames, fps, loops]}]
const ANIMS := {
	"player": [0, {"idle": [0, 4, 5.0, true], "run": [4, 6, 13.0, true], "kick": [10, 2, 16.0, false], "death": [12, 3, 7.0, false]}],
	"shambler": [1, {"walk": [0, 4, 5.0, true], "lunge": [4, 1, 1.0, false], "down": [5, 1, 1.0, false]}],
	"horde": [2, {"walk": [0, 4, 5.0, true], "lunge": [4, 1, 1.0, false], "down": [5, 1, 1.0, false]}],
	"runner": [3, {"walk": [0, 4, 12.0, true], "lunge": [4, 1, 1.0, false], "down": [5, 1, 1.0, false]}],
	"bloater": [4, {"walk": [0, 4, 4.0, true], "lunge": [4, 1, 1.0, false], "down": [5, 1, 1.0, false]}],
	"riot": [5, {"walk": [0, 4, 5.0, true], "lunge": [4, 1, 1.0, false], "down": [5, 1, 1.0, false]}],
}
# Logical texture name -> sliced sprite (tools/slice_sheets.py). Anything
# without a sprite file falls back to the procedural generator below.
const SPRITES := {
	"player_pipe": "chars/player_pipe", "player_pistol": "chars/player_pistol",
	"player_shotgun": "chars/player_shotgun", "shambler": "chars/zombie_shambler",
	"runner": "chars/zombie_runner", "bloater": "chars/zombie_bloater",
	"corpse_shambler": "chars/corpse_zombie", "corpse_runner": "chars/corpse_zombie",
	"corpse_bloater": "chars/corpse_zombie", "corpse_player": "chars/corpse_player",
	# Weapons drawn with Atelier (tools/draw_weapons.py): top-down and HUD side views.
	"w_pipe": "weapons/top_pipe", "w_pistol": "weapons/top_pistol", "w_shotgun": "weapons/top_shotgun",
	"hud_pipe": "weapons/hud_pipe", "hud_pistol": "weapons/hud_pistol", "hud_shotgun": "weapons/hud_shotgun",
	# 3/4-view sheets drawn with Atelier (tools/draw_characters.py, tools/draw_props.py).
	"chars_v2": "chars/sheet_characters_v2", "props_v2": "props/sheet_props_v2",
	# Its normal map, same layout, from the forms' true normals (tools/draw_props.py).
	"props_v2_n": "props/sheet_props_v2_n",
	# The infected, packed from hand-made animation sheets (tools/import_infected.py).
	"infected_shambler": "chars/infected_shambler", "infected_horde": "chars/infected_horde",
	"infected_runner": "chars/infected_runner", "infected_bloater": "chars/infected_bloater",
	# The player, converted from a reference image (tools/convert_reference.py).
	"player_v3": "chars/sheet_player_v3",
	# Its front fist alone (same layout), drawn over the held weapon so the hand grips it.
	"player_v3_hand": "chars/sheet_player_v3_hand",
	# Held weapons at the player sheet's pixel size and palette (tools/draw_weapons.py).
	"held_pipe": "weapons/held_pipe", "held_pistol": "weapons/held_pistol", "held_shotgun": "weapons/held_shotgun",
}
## Held weapon sheets: HELD_DIRS cells of HELD_CELL pixels, one per aim direction (cell i points
## i x 22.5 degrees clockwise from right), the grip pixel at the centre pixel of each cell.
## HELD_REACH is how far the muzzle or tip is from the grip, in sheet pixels.
## Keep in step with HELD_* in tools/draw_weapons.py.
const HELD_DIRS := 16
const HELD_CELL := 64
const HELD_REACH := {"pipe": 27.0, "pistol": 12.0, "shotgun": 28.0}
## How far the barrel's centre line is above the grip pixel, in sheet pixels (on the
## weapon's upper side, which the tool keeps up-screen by mirroring left-aiming cells).
const HELD_BORE := {"pipe": 0.0, "pistol": 4.0, "shotgun": 3.5}
const BLOOD := [Color("8e0b1c"), Color("b3122a"), Color("6a0714")]
const ROOMS_X := 4
const ROOMS_Y := 3
const ROOM_W := 17 * 16
const ROOM_H := 11 * 16
const PINK := Color("ff2a6d")
const CYAN := Color("05d9e8")

# zone index -> [colour A, line colour, pattern, colour A for odd cells]
const FLOORS := [
	["4a4a60", "3c3c50", 1, "44445a"], # entry
	["241a3a", "3a2a5c", 1, "241a3a"], # dance
	["6a2a80", "8a3aa6", 4, "6a2a80"], # vip
	["d0d6dc", "7a848e", 1, "8e98a4"], # kitchen
	["7a4a2c", "55321c", 2, "7a4a2c"], # bar
	["2f8a8a", "236a6a", 3, "2f8a8a"], # restroom
	["5a5a62", "484850", 0, "52525a"], # storage
	["7a2434", "962e44", 4, "7a2434"], # corridor
	["7a808c", "5c626c", 1, "7a808c"], # elevator lobby
]

# zone index -> [fill, edge, highlight, motif] for solid furniture
const FURN := [
	["3c5a8a", "1c2a44", "6a8ac0", 0], # entry: benches
	["2a2a34", "101016", "4a4a5a", 1], # dance: speakers
	["c22a7a", "6a1040", "ff6ab0", 2], # vip: velvet sofas
	["aab4be", "5a646e", "e6f0f8", 1], # kitchen: steel counters
	["8a5a30", "4a2c14", "c08a50", 3], # bar: counter with bottles
	["d8e0e4", "7a868c", "ffffff", 1], # restroom: sinks
	["8a6a3a", "4a3618", "b08a50", 4], # storage: crates
	["5a3030", "2a1414", "8a5050", 0], # corridor
	["606874", "30343c", "9098a4", 0], # elevator lobby
]
const ROOM_NAMES := ["MOTEL", "REDLINE", "VIP LOUNGE", "KITCHEN", "BAR", "RESTROOM", "STORAGE", "STAFF ONLY", "ELEVATOR"]

# zone index -> lights as [x 0..1, y 0..1, colour, radius px, intensity]
const LIGHTS := [
	[[0.5, 0.5, "f67edc", 150, 1.6]],
	[[0.5, 0.15, "ff2a80", 140, 2.3], [0.2, 0.6, "8a5cff", 130, 1.8], [0.8, 0.6, "ff2a6d", 130, 1.9]],
	[[0.5, 0.5, "e06bff", 140, 1.4], [0.1, 0.15, "ff2a6d", 80, 1.5], [0.9, 0.85, "ff2a6d", 80, 1.5]],
	[[0.3, 0.5, "f0e6ff", 130, 1.2], [0.7, 0.5, "f0e6ff", 130, 1.2]],
	[[0.4, 0.15, "ffb24a", 130, 1.7], [0.7, 0.8, "ff6a3a", 100, 1.2]],
	[[0.5, 0.6, "d09cff", 140, 1.3]],
	[[0.5, 0.5, "ffd070", 110, 1.0]],
	[[0.5, 0.5, "ff4050", 130, 1.1]],
	[[0.5, 0.45, "8affb0", 120, 1.4]],
]

static var _tex := {}
static var _img := {}
static var _snd := {}
static var _music: AudioStreamWAV
static var _mats := {}
# The converted player sheet: 96px cells, 3 sheet pixels per world pixel (2 screen pixels per
# art pixel at 1080p), feet on row 90, figure 78px tall, weapon held 37px above the feet (chest height).
# animation: [first frame, frames, fps, loops]
## Transient effects are drawn on the art's pixel grid (PX world pixels, the player
## sheet's pixel size), in hard colour steps, and fade through an ordered dither
## instead of alpha, so they read as pixel art beside the sprites.
const PX := 1.0 / 3.0
const BAYER := [0.03125, 0.53125, 0.15625, 0.65625, 0.78125, 0.28125, 0.90625, 0.40625,
		0.21875, 0.71875, 0.09375, 0.59375, 0.96875, 0.46875, 0.84375, 0.34375]
const WARN := [Color("d4ff3a"), Color("7fd11c"), Color("14200a")] # blast-zone ring: acid green bright, mid, and its dark edge
const HOT := [Color("fff3a6"), Color("ffe26b"), Color("ff8a2a"), Color("f2561d")] # hottest first
const SLASH_RAMP := [Color("c8f6ff"), Color("05d9e8"), Color("1c7fa6")]
const MUZZLE_LOBES := [[0.0, 11.0, 0.8], [0.0, 4.5, 1.7], [0.6, 5.5, 0.55], [-0.6, 5.5, 0.55]]
const FLASH_TIME := 0.066 # two 30 fps frames: white-hot, then cooler and shorter
const SPARK_TIME := 0.16
const PLAYER_V3 := {"idle": [0, 2, 2.2, true], "run": [2, 4, 8.5, true], "kick": [6, 1, 1.0, false], "death": [7, 1, 1.0, false]}

static var _paths := {}
static var _frames := {}
static var _props := {}
static var _hands: Array = []

var world
var decal_nodes: Array = [] # one canvas per room (keeps each under the light limit)
var decals: Array = []
var parts: Array = [] # [pos, vel, life, color]
var tracers: Array = [] # [a, b, life, color]
var rings: Array = [] # [pos, radius, max_radius]
var popups: Array = [] # [pos, text, life, color]
var warns: Array = [] # [enemy, pos, radius]: the blast zone of a lit fuse, drawn until it bursts
var flashes: Array = [] # [pos, life]
var slashes: Array = [] # [pos, angle, life]
var ghosts: Array = [] # [texture, pos, flipped, life]
var shells: Array = [] # [pos, velocity, height, vertical speed]
var pools: Array = [] # [pos, age, next drop]
var kick := Vector2.ZERO # directional camera shove
var shake := 0.0
var punch := 0.0 # camera zoom kick, as a fraction of the base zoom
var _pool: Array = []
var _next := 0
var _last := {}
var _font: Font
var _was_busy := false


func _init() -> void:
	for i in ROOMS_X * ROOMS_Y:
		var n := Node2D.new()
		n.draw.connect(_draw_decals.bind(i))
		decal_nodes.append(n)
		decals.append([])


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
	for n in ["chars_v2", "props_v2", "pixel", "light", "cone", "door", "door_locked",
			"w_pipe", "w_pistol", "w_shotgun", "hud_pipe", "hud_pistol", "hud_shotgun", "glow", "shadow", "vignette"]:
		tex(n)


## Shared blend materials: "add" for glows, "mul" for the baked light map.
static func mat(kind: String) -> CanvasItemMaterial:
	if not _mats.has(kind):
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if kind == "add" else CanvasItemMaterial.BLEND_MODE_MUL
		_mats[kind] = m
	return _mats[kind]


# ---------------------------------------------------------------- textures

## Animation frames for a character, cut from the character sheet.
static func frames(who: String) -> SpriteFrames:
	if not _frames.has(who):
		var sf := SpriteFrames.new()
		sf.remove_animation("default")
		var a := art(who)
		var row: int = ANIMS[who][0] if a.sheet == "chars_v2" else 0
		var anims: Dictionary = ANIMS[who][1]
		if a.sheet == "player_v3":
			anims = PLAYER_V3
		elif a.sheet != "chars_v2":
			anims = InfectedAtlas.ANIMS[who]
		for anim in anims:
			var d: Array = anims[anim]
			sf.add_animation(anim)
			sf.set_animation_speed(anim, d[2])
			sf.set_animation_loop(anim, d[3])
			for i in d[1]:
				var at := AtlasTexture.new()
				at.atlas = tex(a.sheet)
				at.region = Rect2((d[0] + i) * a.cell, row * a.cell, a.cell, a.cell)
				sf.add_frame(anim, at)
		_frames[who] = sf
	return _frames[who]


## How a character's sheet is laid out and shown: sheet name, cell size, scale to
## world pixels, the row its feet stand on, its height and shoulder height in
## sheet pixels. The player uses the converted sheet when that file exists, and an
## infected skin its packed sheet (same pixel size as the player); anything
## without one falls back to the code-drawn character sheet.
static func art(who: String) -> Dictionary:
	if who == "player" and has_sprite("player_v3"):
		return {"sheet": "player_v3", "cell": 96, "scale": 1.0 / 3.0, "feet": 90, "height": 78, "shoulder": 37}
	if InfectedAtlas.ANIMS.has(who) and has_sprite("infected_" + who):
		var h: int = InfectedAtlas.HEIGHT[who]
		return {"sheet": "infected_" + who, "cell": InfectedAtlas.CELL, "scale": 1.0 / 3.0, "feet": InfectedAtlas.FEET,
				"height": h, "shoulder": h / 2}
	return {"sheet": "chars_v2", "cell": CELL, "scale": ART_SCALE, "feet": 60, "height": 42, "shoulder": 26}


## True when the player has the art to hold a weapon in its fist: the hand sheet
## and the three weapons drawn at the same pixel size. Otherwise the weapon is
## drawn the old way, floating at the shoulder.
static func can_grip() -> bool:
	return art("player").sheet == "player_v3" and has_sprite("player_v3_hand") \
			and has_sprite("held_pipe") and has_sprite("held_pistol") and has_sprite("held_shotgun")


## Centre of the fist in each cell of the hand sheet, in sheet pixels from the
## cell's top-left; Vector2.INF for a cell with no hand (lying down).
static func hand_anchors() -> Array:
	if _hands.is_empty():
		var im: Image = img("player_v3_hand")
		var cell: int = art("player").cell
		for f in im.get_width() / cell:
			var sum := Vector2.ZERO
			var n := 0
			for y in cell:
				for x in cell:
					if im.get_pixel(f * cell + x, y).a > 0.5:
						sum += Vector2(x + 0.5, y + 0.5)
						n += 1
			_hands.append(sum / n if n > 0 else Vector2.INF)
	return _hands


static func frame_tex(who: String, anim: String, i: int) -> Texture2D:
	return frames(who).get_frame_texture(anim, i)


## Rectangle of a prop inside the props sheet image.
static func prop_rect(n: String) -> Rect2i:
	var p: Array = PropAtlas.PROPS[n]
	return Rect2i(p[0], p[1], p[2], p[3])


static func prop_tex(n: String) -> Texture2D:
	if not _props.has(n):
		var r := prop_rect(n)
		if prop_normals():
			_props[n] = lit(ImageTexture.create_from_image(img("props_v2").get_region(r)),
				ImageTexture.create_from_image(img("props_v2_n").get_region(r)))
		else:
			var at := AtlasTexture.new()
			at.atlas = tex("props_v2")
			at.region = r
			_props[n] = at
	return _props[n]


## True when the props sheet has a normal map beside it (both files exist), so props shade
## with the direction of the room lights. Without it props are lit flat, as before.
static func prop_normals() -> bool:
	return has_sprite("props_v2") and has_sprite("props_v2_n")


## A texture that carries a normal map for 2D lights; just `diffuse` when there is none.
static func lit(diffuse: Texture2D, normal: Texture2D) -> Texture2D:
	if normal == null:
		return diffuse
	var ct := CanvasTexture.new()
	ct.diffuse_texture = diffuse
	ct.normal_texture = normal
	return ct


## Path of the sprite file for a texture name, or "" if there is none.
## No file means procedural art.
static func sprite_path(n: String) -> String:
	if not _paths.has(n):
		var path: String = SPRITE_DIR + SPRITES.get(n, n) + ".png"
		_paths[n] = path if ResourceLoader.exists(path) else ""
	return _paths[n]


static func has_sprite(n: String) -> bool:
	return sprite_path(n) != ""


## Sprite files hold 4 pixels per world pixel; procedural art is 1:1.
static func sprite_scale(n: String) -> float:
	return 1.0 / SPRITE_PX if has_sprite(n) else 1.0


## Square copy of an image at `size` pixels, for baking the floor texture.
static func scaled(n: String, size: int) -> Image:
	var key := "%s@%d" % [n, size]
	if not _img.has(key):
		var im: Image = img(n).duplicate()
		im.resize(size, size, Image.INTERPOLATE_NEAREST)
		_img[key] = im
	return _img[key]


static func tex(n: String) -> Texture2D:
	if not _tex.has(n):
		if has_sprite(n):
			_tex[n] = load(sprite_path(n))
		else:
			_tex[n] = ImageTexture.create_from_image(img(n))
	return _tex[n]


static func img(n: String) -> Image:
	if not _img.has(n):
		if has_sprite(n):
			var im: Image = (load(sprite_path(n)) as Texture2D).get_image()
			if im.is_compressed():
				im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			_img[n] = im
		else:
			_img[n] = _make(n)
	return _img[n]


static func _make(n: String) -> Image:
	if n.begins_with("floor_"):
		var p := n.split("_")
		var f: Array = FLOORS[int(p[1])]
		return _tile(Color(f[3] if p[2] == "1" else f[0]), Color(f[1]), f[2], int(p[1]) * 7 + int(p[2]))
	if n == "chars_v2":
		return _fallback_chars()
	if n == "props_v2":
		return _fallback_props()
	if n == "pixel":
		return _solid(1, 1, Color.WHITE, Color.WHITE)
	if n.begins_with("hud_"):
		return _make("w_" + n.substr(4)) # no side-view art: reuse the top-down weapon
	if n.begins_with("table_"):
		return _furniture(FURN[int(n.split("_")[1])])
	match n:
		"player_pipe", "player_pistol", "player_shotgun":
			return _outline(_actor(14, Color("f2c230"), Color("3a2616"), Color("e8b890"), 4))
		"light": return _light(64, 0.0)
		"cone": return _light(128, 0.55)
		"shambler": return _outline(_actor(14, Color("5c7a48"), Color("a3b57c"), Color("a3b57c"), 6))
		"runner": return _outline(_actor(12, Color("b83a3a"), Color("e0a890"), Color("e0a890"), 5))
		"bloater": return _outline(_actor(20, Color("b0a53a"), Color("dcd67c"), Color("8a8030"), 4))
		"corpse_player": return _outline(_corpse(14, Color("f2c230"), Color("3a2616")))
		"corpse_shambler": return _outline(_corpse(14, Color("4a6238"), Color("8a9a68")))
		"corpse_runner": return _outline(_corpse(12, Color("8a2c2c"), Color("b88a78")))
		"corpse_bloater": return _outline(_corpse(20, Color("8a8230"), Color("b0aa60")))
		"glow": return _radial(64, 64, Color(1, 1, 1), 0.0, 1.0, true)
		"shadow": return _radial(16, 12, Color(0, 0, 0), 0.0, 0.45, true)
		"vignette": return _radial(64, 36, Color(0.02, 0.0, 0.06), 0.55, 0.75, false)
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


## Stand-in character sheet (same layout as the real one): plain figures.
static func _fallback_chars() -> Image:
	var im := Image.create(CELL * 15, CELL * 6, false, Image.FORMAT_RGBA8)
	var cols := [Color("f0b820"), Color("8a4a44"), Color("c9cfd6"), Color("7a2a36"), Color("a8b83a"), Color("586044")]
	for row in 6:
		for i in (15 if row == 0 else 6):
			var lying := i == (14 if row == 0 else 5)
			var o := Vector2i(i * CELL, row * CELL)
			if lying:
				im.fill_rect(Rect2i(o + Vector2i(8, 44), Vector2i(48, 12)), Color("8e0b1c"))
				im.fill_rect(Rect2i(o + Vector2i(14, 44), Vector2i(36, 9)), cols[row])
			else:
				im.fill_rect(Rect2i(o + Vector2i(24, 44), Vector2i(16, 16)), cols[row].darkened(0.5))
				im.fill_rect(Rect2i(o + Vector2i(22, 22), Vector2i(20, 24)), cols[row])
				im.fill_rect(Rect2i(o + Vector2i(25, 8), Vector2i(15, 15)), cols[row].lightened(0.4))
	return im


## Stand-in props sheet: flat blocks with a darker front face.
static func _fallback_props() -> Image:
	var im := Image.create(PropAtlas.SIZE.x, PropAtlas.SIZE.y, false, Image.FORMAT_RGBA8)
	for n in PropAtlas.PROPS:
		var p: Array = PropAtlas.PROPS[n]
		var col := Color.from_hsv(float(hash(n) % 100) / 100.0, 0.45, 0.7)
		var depth: int = p[5] * 32
		im.fill_rect(Rect2i(p[0], p[1], p[2], p[3]), col.darkened(0.45))
		if depth > 0:
			im.fill_rect(Rect2i(p[0], p[1], p[2], depth), col)
	return im


## Radial alpha gradient. `glow` fades out from the centre; otherwise it
## fades in from `inner` (0..1 of the radius) towards the corners.
static func _radial(w: int, h: int, col: Color, inner: float, strength: float, glow: bool) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (x + 0.5) / w * 2.0 - 1.0
			var dy := (y + 0.5) / h * 2.0 - 1.0
			var d := sqrt(dx * dx + dy * dy)
			var a: float
			if glow:
				a = pow(clampf(1.0 - d, 0.0, 1.0), 2.0) * strength
			else:
				a = clampf((d - inner) / (1.42 - inner), 0.0, 1.0) * strength
			im.set_pixel(x, y, Color(col, a))
	return im


## Light2D texture. `cone` > 0 narrows it to a beam along +X (half-angle in
## radians) for the flashlight; 0 gives a round falloff.
static func _light(size: int, cone: float) -> Image:
	var im := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c)
			var f := pow(clampf(1.0 - d.length() / c, 0.0, 1.0), 1.5)
			if cone > 0.0:
				f *= clampf((cone - absf(d.angle())) / 0.25, 0.0, 1.0)
			im.set_pixel(x, y, Color(f, f, f, 1.0))
	return im


## One furniture tile; world.gd adds edges where the piece ends.
static func _furniture(f: Array) -> Image:
	var fill := Color(f[0])
	var edge := Color(f[1])
	var hi := Color(f[2])
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	im.fill(fill)
	match int(f[3]):
		1: # ring: speaker cone / burner / basin
			for y in 16:
				for x in 16:
					var d := Vector2(x - 7.5, y - 7.5).length()
					if d < 5.5 and d > 3.5:
						im.set_pixel(x, y, edge)
					elif d <= 1.5:
						im.set_pixel(x, y, hi)
		2: # cushion button
			im.fill_rect(Rect2i(2, 3, 12, 9), fill.lightened(0.12))
			im.fill_rect(Rect2i(7, 7, 2, 2), edge)
		3: # bottles and glasses
			im.fill_rect(Rect2i(3, 4, 2, 4), Color("30ff70"))
			im.fill_rect(Rect2i(8, 6, 2, 3), Color("05d9e8"))
			im.fill_rect(Rect2i(12, 4, 2, 4), Color("ff2a6d"))
		4: # crate planks
			for i in 12:
				im.set_pixel(2 + i, 2 + i, edge)
				im.set_pixel(13 - i, 2 + i, edge)
	return im


## Adds a one pixel outline (grows the image by 2) so actors read on any floor.
static func _outline(src: Image, col := Color("120a1a")) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	out.blit_rect(src, Rect2i(0, 0, w, h), Vector2i(1, 1))
	for y in h + 2:
		for x in w + 2:
			if out.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var sx: int = x - 1 + d.x
				var sy: int = y - 1 + d.y
				if sx >= 0 and sy >= 0 and sx < w and sy < h and src.get_pixel(sx, sy).a > 0.0:
					out.set_pixel(x, y, col)
					break
	return out


## A body lying flat: long torso, head at one end, splayed limbs, wounds.
static func _corpse(size: int, body: Color, head: Color) -> Image:
	var w := size + 6
	var im := Image.create(w, size, false, Image.FORMAT_RGBA8)
	var cx := w / 2.0
	var cy := size / 2.0
	var rx := size * 0.42
	var ry := size * 0.24
	var hr := size * 0.17
	var rng := RandomNumberGenerator.new()
	rng.seed = size * 31 + int(body.r8)
	for y in size:
		for x in w:
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			var col := Color(0, 0, 0, 0)
			# limbs: two diagonals crossing the torso
			if absf(absf(dx) - absf(dy) * 1.1 - rx * 0.35) < 0.9 and absf(dy) < size * 0.46 and absf(dx) < rx + 2.0:
				col = body.darkened(0.25)
			if (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0:
				col = Color("8e0b1c") if rng.randf() < 0.18 else body
			if (dx - rx - hr * 0.5) * (dx - rx - hr * 0.5) + dy * dy <= hr * hr:
				col = head
			im.set_pixel(x, y, col)
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
	var p: Vector2 = d[1]
	var i := clampi(int(p.x) / ROOM_W, 0, ROOMS_X - 1) + clampi(int(p.y) / ROOM_H, 0, ROOMS_Y - 1) * ROOMS_X
	decals[i].append(d)
	if decals[i].size() > MAX_DECALS:
		decals[i] = decals[i].slice(60)
	decal_nodes[i].queue_redraw()


func decal_count() -> int:
	var n := 0
	for list in decals:
		n += list.size()
	return n


func blood(pos: Vector2, dir: Vector2, n: int, spread := 12.0) -> void:
	for i in n:
		var p := pos + dir * randf_range(0.0, 28.0) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * spread * randf()
		if world.solid_at(p):
			continue
		var s := float(randi_range(1, 3))
		_add([0, p.floor(), Vector2(s, s), BLOOD[randi() % 3]])
	# Bigger hits also leave layered splats thrown along the blow.
	for i in n / 7:
		_splat(pos + dir * randf_range(4.0, 20.0) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * spread * 0.6, randi_range(2, 4), dir)
	for i in mini(n, 10):
		var v := (dir * randf_range(40, 160)) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 60.0
		parts.append([pos, v, randf_range(0.15, 0.35), BLOOD[1]])


## A pool: dark base, brighter wet core, and a streak of drops along `dir`.
func _splat(pos: Vector2, r: int, dir := Vector2.ZERO) -> void:
	for layer in 2:
		var col: Color = BLOOD[2] if layer == 0 else BLOOD[randi() % 2]
		var k := r if layer == 0 else maxi(1, r - 1)
		for i in 3:
			var p := pos + Vector2(randi_range(-k, k), randi_range(-k, k))
			var s := Vector2(randi_range(k, k * 2), randi_range(k, k * 2))
			if not world.solid_at(p) and not world.solid_at(p + s):
				_add([0, p.floor(), s, col])
	if dir != Vector2.ZERO:
		for i in 4:
			var p := pos + dir * (r * 2.0 + i * randf_range(3.0, 6.0)) + Vector2(randf_range(-2, 2), randf_range(-2, 2))
			var s := float(maxi(1, r - i))
			if not world.solid_at(p):
				_add([0, p.floor(), Vector2(s, s), BLOOD[1]])


## A brass shell: ejected sideways, arcs, bounces, then stays on the floor.
func casing(pos: Vector2, aim: Vector2) -> void:
	var side := aim.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
	shells.append([pos, side * randf_range(30, 60) - aim * randf_range(10, 30), 10.0, randf_range(50, 90)])


func splinters(pos: Vector2, dir: Vector2) -> void:
	for i in 14:
		var v := dir.rotated(randf_range(-0.9, 0.9)) * randf_range(60, 220)
		parts.append([pos, v, randf_range(0.2, 0.45), Color("b47c4a") if i % 2 == 0 else Color("5e3618")])
	for i in 7:
		var p := pos + dir.rotated(randf_range(-0.8, 0.8)) * randf_range(8, 38)
		if not world.solid_at(p):
			_add([0, p.floor(), Vector2(randi_range(1, 3), 1), Color("8a5630")])


## Acid and gibs left by a burst bloater.
func acid(pos: Vector2, radius: float) -> void:
	for i in 22:
		var p := pos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(4.0, radius)
		if not world.solid_at(p):
			var s := float(randi_range(1, 4))
			_add([0, p.floor(), Vector2(s, s * 0.6).ceil(), Color("8ad022") if i % 3 else Color("4a7a12")])
	for i in 16:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60, 240)
		parts.append([pos, v, randf_range(0.25, 0.5), Color("d0ff5a") if i % 2 == 0 else Color("b3122a")])


## A pool that keeps spreading under a fresh corpse.
func pool(pos: Vector2) -> void:
	pools.append([pos, 0.0, 0.0])


func slash(pos: Vector2, angle: float) -> void:
	slashes.append([pos, angle, 0.14])


## `half` is half the frame's width in world pixels; `lift` how far its centre is above the feet.
func ghost(texture: Texture2D, pos: Vector2, flipped: bool, half: float, lift: float) -> void:
	ghosts.append([texture, pos, flipped, 0.22, half, lift])


func add_kick(v: Vector2) -> void:
	kick += v
	kick = kick.limit_length(8.0)


func shards(pos: Vector2) -> void:
	for i in 14:
		var p := pos + Vector2(randf_range(-14, 14), randf_range(-14, 14))
		if not world.solid_at(p):
			_add([0, p.floor(), Vector2(1, 1), Color(0.75, 1.0, 1.0, 0.9)])
		parts.append([pos, Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 120.0, 0.25, Color(0.8, 1, 1)])


## Leaves a sprawled body (a frame from the character sheet) on the floor.
## `pos` is where the feet were; `flipped` mirrors it away from the blow.
## The downed pose of `who` left on the floor where it fell: the last frame of "down" (a sheet
## may give "down" a fall before the body on the floor).
func corpse(who: String, pos: Vector2, flipped: bool, size := 1.0) -> void:
	var a := art(who)
	var s: float = a.scale * size
	var last: int = frames(who).get_frame_count("down") - 1
	_add([1, pos + Vector2(0, (a.cell / 2.0 - a.feet) * s), frame_tex(who, "down", last), randf_range(-0.12, 0.12),
			Color.WHITE, Vector2(-s if flipped else s, s)])


## Any texture as a floor decal (a broken door, debris).
func debris(texture: Texture2D, pos: Vector2, rot: float, size: float) -> void:
	_add([1, pos, texture, rot, Color(0.8, 0.8, 0.8), Vector2(size, size)])


func flash(pos: Vector2, dir := Vector2.RIGHT) -> void:
	flashes.append([pos, FLASH_TIME, dir.normalized()])


func _draw_decals(i: int) -> void:
	var node: Node2D = decal_nodes[i]
	for d in decals[i]:
		if d[0] == 0:
			node.draw_rect(Rect2(d[1], d[2]), d[3])
		else:
			var t: Texture2D = d[2]
			node.draw_set_transform(d[1], d[3], d[5])
			node.draw_texture(t, -t.get_size() / 2.0, d[4])
			node.draw_set_transform(Vector2.ZERO, 0.0)


# ---------------------------------------------------------------- transient

func tracer(a: Vector2, b: Vector2, col := Color(1, 0.95, 0.6)) -> void:
	tracers.append([a, b, 0.06, col])


func spark(pos: Vector2) -> void:
	for i in 5:
		parts.append([pos, Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 110.0, SPARK_TIME, Color(1, 0.9, 0.5)])


func ring(pos: Vector2, max_r: float) -> void:
	rings.append([pos, 4.0, max_r])


## Marks the blast zone round a lit fuse: a ring at its exact reach plus a second
## ring that closes in on the centre as the fuse burns, so the timer can be read.
## The zone stays where it was marked: a warning that follows its source is not one.
func warn(enemy, pos: Vector2, radius: float) -> void:
	warns.append([enemy, pos, radius])


func popup(pos: Vector2, text: String, col := Color(1, 1, 1)) -> void:
	popups.append([pos, text, 0.8, col])


func add_shake(a: float) -> void:
	shake = maxf(shake, a)


func add_punch(a: float) -> void:
	punch = maxf(punch, a)


func _process(delta: float) -> void:
	kick = kick.move_toward(Vector2.ZERO, delta * 60.0)
	for s in slashes:
		s[2] -= delta
	slashes = slashes.filter(func(s): return s[2] > 0.0)
	for g in ghosts:
		g[3] -= delta
	ghosts = ghosts.filter(func(g): return g[3] > 0.0)
	for s in shells:
		s[0] += s[1] * delta
		s[2] += s[3] * delta
		s[3] -= 520.0 * delta
		if s[2] <= 0.0:
			s[2] = 0.0
			s[3] *= -0.45
			s[1] *= 0.5
			if absf(s[3]) < 22.0:
				s[3] = 0.0
				if not world.solid_at(s[0]):
					_add([0, s[0].floor(), Vector2(2, 1) if randf() < 0.5 else Vector2(1, 2), Color("e8c040")])
	shells = shells.filter(func(s): return s[2] > 0.0 or s[3] != 0.0)
	for p in pools:
		p[1] += delta
		if p[1] >= p[2]:
			p[2] += 0.22
			var reach: float = 3.0 + p[1] * 3.2
			_splat(p[0] + Vector2(randf_range(-reach, reach), randf_range(-reach * 0.5, reach * 0.5)), 2 + int(p[1] * 0.5))
	pools = pools.filter(func(p): return p[1] < 3.5)
	shake = maxf(0.0, shake - delta * 28.0)
	punch = maxf(0.0, punch - delta * 0.35)
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
	for f in flashes:
		f[1] -= delta
	flashes = flashes.filter(func(f): return f[1] > 0.0)
	parts = parts.filter(func(p): return p[2] > 0.0)
	tracers = tracers.filter(func(t): return t[2] > 0.0)
	rings = rings.filter(func(r): return r[1] < r[2])
	popups = popups.filter(func(p): return p[2] > 0.0)
	warns = warns.filter(func(w): return is_instance_valid(w[0]) and not w[0].dead)
	var busy := not warns.is_empty() or not (parts.is_empty() and tracers.is_empty() and rings.is_empty() and popups.is_empty()
			and flashes.is_empty() and slashes.is_empty() and ghosts.is_empty() and shells.is_empty())
	if busy or _was_busy:
		queue_redraw()
	_was_busy = busy


## One art pixel at `p`, snapped to the art grid. `a` below 1 is not blended: an
## ordered dither decides whether the pixel is drawn, so fades stay hard-edged.
func _dot(p: Vector2, col: Color, a := 1.0, size := 1) -> void:
	var cx := int(floor(p.x / PX))
	var cy := int(floor(p.y / PX))
	if a < 1.0 and a <= BAYER[(cy & 3) * 4 + (cx & 3)]:
		return
	draw_rect(Rect2(cx * PX, cy * PX, PX * size, PX * size), col)


## Muzzle flash along `dir`: a long spike, a fat body and two side rays, in three
## hard colour steps. The first half is white-hot; the second is shorter and cooler.
func _muzzle(pos: Vector2, dir: Vector2, hot: bool) -> void:
	var grow: float = 1.0 if hot else 0.6
	var fat: float = 1.0 if hot else 0.72
	var cols: Array = [Color.WHITE, HOT[1], HOT[2]] if hot else [HOT[1], HOT[2], HOT[3]]
	var side := dir.orthogonal()
	var reach: float = 11.0 * grow
	var u := -1.0
	while u < reach:
		var v := -4.0
		while v < 4.0:
			var m := -1.0
			for lobe in MUZZLE_LOBES: # [angle, length, width]
				var ld := Vector2.from_angle(lobe[0])
				var along: float = u * ld.x + v * ld.y
				var across: float = absf(-u * ld.y + v * ld.x)
				var length: float = lobe[1] * grow
				if along < 0.0 or along > length:
					continue
				var w: float = lobe[2] * fat * pow(1.0 - along / length, 0.8) * minf(1.0, 0.45 + 3.0 * along / length)
				m = maxf(m, (w - across) / maxf(lobe[2] * fat, 0.01))
			if m > 0.0:
				_dot(pos + dir * u + side * v, cols[0] if m > 0.45 else (cols[1] if m > 0.15 else cols[2]))
			v += PX
		u += PX


func _draw() -> void:
	for g in ghosts:
		# Dash after-image: the body frame, tinted and fading.
		var half: float = g[4]
		var at: Vector2 = g[1] + Vector2(half if g[2] else -half, -half - g[5])
		draw_texture_rect(g[0], Rect2(at, Vector2(-half * 2.0 if g[2] else half * 2.0, half * 2.0)), false,
				Color(0.3, 0.9, 1.0, g[3] * 2.4))
	for s in slashes:
		# The tail chases the head; the arc is widest mid-sweep and dissolves through the dither.
		var k: float = s[2] / 0.14
		var sweep := 1.25
		var from: float = s[1] - sweep + (1.0 - k) * 1.2
		var to: float = s[1] + sweep
		var a := from
		while a < to:
			var v: float = (a - from) / maxf(to - from, 0.01) # 0 at the tail, 1 at the head
			var w: float = 2.6 * pow(sin(PI * clampf(v, 0.02, 0.98)), 0.6)
			var dir := Vector2.from_angle(a)
			var r: float = 21.0 - w * 0.5
			while r < 21.0 + w * 0.5:
				_dot(s[0] + dir * r, Color.WHITE if k > 0.5 else SLASH_RAMP[0], 0.35 + v * 0.65 * (0.5 + k))
				r += PX
			r = 17.2
			while r < 17.2 + w * 0.5:
				_dot(s[0] + dir * r, SLASH_RAMP[1] if k > 0.4 else SLASH_RAMP[2], v * (0.3 + k * 0.7))
				r += PX
			a += PX / 21.0
	for s in shells:
		draw_rect(Rect2(s[0] + Vector2(0, -s[2]), Vector2(2, 1)), Color("ffe27a"))
	for t in tracers:
		# A hot core that breaks up as it fades, stepped along the art grid.
		var span: Vector2 = t[1] - t[0]
		var n := int(span.length() / PX)
		var k: float = t[2] / 0.06
		var step: Vector2 = span / maxf(n, 1)
		for i in n:
			_dot(t[0] + step * i, t[3] if k > 0.5 else HOT[2], 0.25 + k, 2)
	for f in flashes:
		_muzzle(f[0], f[2], f[1] > FLASH_TIME * 0.5)
	for p in parts:
		# Sparks cool down the ramp and trail one pixel behind.
		var k: float = p[2] / SPARK_TIME
		_dot(p[0], HOT[0] if k > 0.6 else (HOT[1] if k > 0.3 else HOT[2]), 1.0, 2)
		_dot(p[0] - p[1].normalized() * PX * 2.0, HOT[3], k * 1.4)
	for r in rings:
		# Blast ring: thins and cools as it grows, then dissolves.
		var k: float = 1.0 - r[1] / r[2]
		var col: Color = HOT[0] if k > 0.7 else (HOT[1] if k > 0.45 else (HOT[2] if k > 0.2 else HOT[3]))
		var thick: float = maxf(PX, 3.0 * k + 0.4)
		var a := 0.0
		while a < TAU:
			var dir := Vector2.from_angle(a)
			var d := 0.0
			while d < thick:
				_dot(r[0] + dir * (r[1] + d), col, 0.3 + k * 1.2)
				d += PX
			a += PX / maxf(r[1], 1.0)
	var now := Time.get_ticks_msec()
	for w in warns:
		var at: Vector2 = w[1]
		var r: float = w[2]
		var k: float = w[0].fuse_progress()
		# The outer ring flashes faster as the burst nears; its dashes march round.
		var on: bool = (now / int(lerpf(140.0, 45.0, k))) % 2 == 0
		var col: Color = WARN[0] if on else WARN[1]
		var n := int(TAU * r / PX)
		var shift := int(now / 40) % 6
		for i in n:
			if (i + shift) % 6 < 4:
				var d := Vector2.from_angle(TAU * i / n)
				_dot(at + d * (r + PX * 2.0), WARN[2], 1.0, 2) # dark edge: reads on bright floors too
				_dot(at + d * (r - PX), col, 1.0, 3)
		# The inner ring closes in from the edge: the burst comes when it reaches the centre.
		var ri := r * (1.0 - k)
		if ri > 2.0:
			var m := int(TAU * ri / PX)
			for i in m:
				if i % 3 != 2:
					_dot(at + Vector2.from_angle(TAU * i / m) * ri, WARN[0], 1.0, 2)
	for p in popups:
		# Drawn at 4x size and scaled down so text stays sharp under the camera zoom.
		draw_set_transform(p[0] + Vector2(-40, 0), 0.0, Vector2(0.25, 0.25))
		draw_string(_font, Vector2.ZERO, p[1], HORIZONTAL_ALIGNMENT_CENTER, 320, 32, Color(p[3], minf(1.0, p[2] * 3.0)))
		draw_set_transform(Vector2.ZERO, 0.0)
