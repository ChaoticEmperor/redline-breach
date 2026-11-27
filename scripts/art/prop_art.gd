extends RefCounted
## Props and floor weapons from assets/sprites/world/props.{png,json}: name -> texture.

const DIR := "res://assets/sprites/world/"

static var _cache := {}
static var _meta: Dictionary
static var _sheet: Texture2D


static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	if _meta.is_empty():
		_sheet = load(DIR + "props.png")
		_meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "props.json"))
	var r: Array = _meta.get(name, [0, 0, 1, 1])
	var at := AtlasTexture.new()
	at.atlas = _sheet
	at.region = Rect2(r[0], r[1], r[2], r[3])
	_cache[name] = at
	return at
