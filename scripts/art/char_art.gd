extends RefCounted
## Loads a character skin (tools/draw_topdown_chars.py, later Tandem's Godot export) into
## SpriteFrames. The sheet + JSON is the only contract: swap the art by swapping the files.

const DIR := "res://assets/sprites/chars/"

static var _cache := {}


static func has_skin(skin: String) -> bool:
	return ResourceLoader.exists(DIR + skin + ".png") and FileAccess.file_exists(DIR + skin + ".json")


## {frames: SpriteFrames, anchor: Vector2, dead_anchor: Vector2, anims: Dictionary}
static func load_skin(skin: String) -> Dictionary:
	if _cache.has(skin):
		return _cache[skin]
	var tex: Texture2D = load(DIR + skin + ".png")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + skin + ".json"))
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for name in meta.anims:
		var a: Dictionary = meta.anims[name]
		sf.add_animation(name)
		sf.set_animation_speed(name, a.fps)
		sf.set_animation_loop(name, a.loop)
		for i in int(a.frames):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * a.cell, a.y, a.cell, a.cell)
			sf.add_frame(name, at)
	var out := {"frames": sf, "anchor": Vector2(meta.anchor[0], meta.anchor[1]),
			"dead_anchor": Vector2(meta.dead_anchor[0], meta.dead_anchor[1]), "anims": meta.anims}
	_cache[skin] = out
	return out
