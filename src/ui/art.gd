class_name Art
extends RefCounted
## Read-only access to the built art in assets/manifest.json (written by
## tools/assets/pipeline.py). UI-only: rules code never touches art.
## Every lookup degrades gracefully (null / empty) so the game still runs
## with placeholder drawing if an asset is missing.

const MANIFEST_PATH := "res://assets/manifest.json"

static var _manifest: Dictionary = {}
static var _loaded := false
static var _atlas_cache: Dictionary = {}    # path -> Texture2D
static var _emblem_icons: Dictionary = {}
static var _sprite_cache: Dictionary = {}   # id -> AtlasTexture


static func manifest() -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_manifest = parsed
	return _manifest


## Drops caches (tests, or after rebuilding assets while the game runs).
static func reload() -> void:
	_loaded = false
	_manifest = {}
	_atlas_cache.clear()
	_sprite_cache.clear()
	_emblem_icons.clear()


static func texture_at(path: String) -> Texture2D:
	if not _atlas_cache.has(path):
		_atlas_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _atlas_cache[path]


static func has_sprite(id: String) -> bool:
	return manifest().get("sprites", {}).has(id)


static func sprite_info(id: String) -> Dictionary:
	return manifest().get("sprites", {}).get(id, {})


static func sprite(id: String) -> Texture2D:
	if _sprite_cache.has(id):
		return _sprite_cache[id]
	var info := sprite_info(id)
	var tex: AtlasTexture = null
	if not info.is_empty():
		var atlas_info: Dictionary = manifest()["atlases"].get(info["atlas"], {})
		var sheet := texture_at(atlas_info.get("path", ""))
		if sheet != null:
			tex = AtlasTexture.new()
			tex.atlas = sheet
			var r: Array = info["rect"]
			tex.region = Rect2(r[0], r[1], r[2], r[3])
	_sprite_cache[id] = tex
	return tex


## Anchor in the sprite's own pixels (feet for figures, centre for UI).
static func anchor(id: String) -> Vector2:
	var a: Array = sprite_info(id).get("anchor", [0, 0])
	return Vector2(a[0], a[1])


## Faction identity is independent of the owning player's banner colour.
static func faction_emblem(faction: String) -> Texture2D:
	if not faction in ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch", "darkelf", "fishmen"]:
		return null
	return texture_at("res://assets/emblems/%s.tres" % faction)


## OptionButton uses the texture's native size, so cache a compact copy.
static func faction_emblem_icon(faction: String) -> Texture2D:
	if not _emblem_icons.has(faction):
		var tex := faction_emblem(faction)
		if tex == null:
			return null
		var image := tex.get_image()
		image.resize(28, 28, Image.INTERPOLATE_LANCZOS)
		_emblem_icons[faction] = ImageTexture.create_from_image(image)
	return _emblem_icons[faction]


static func creature(creature_id: String, veteran_level: int = 1) -> Texture2D:
	if veteran_level >= 5:
		var veteran := VeteranVisual.still(creature_id)
		if veteran != null:
			return veteran
	return sprite("creature_" + creature_id)


## Unique campaign portraits only apply to their original class. A hero whose
## class was changed during setup uses the matching generic class portrait.
const CAMPAIGN_PORTRAIT_CLASSES := {
	"hero_watch": "knight", "hero_scout": "ranger",
	"hero_wren": "knight", "hero_maelis": "ranger", "hero_edda": "oracle",
	"hero_ysmay": "necromancer", "hero_orrin": "gravewarden", "hero_corvin": "blightcaller",
	"hero_skarn": "warlord", "hero_ithra": "warlock", "hero_morvath": "tormentor",
	"hero_cerrid": "grovewarden", "hero_neve": "huntmaster", "hero_brakka": "thornspeaker",
	"hero_gunnra": "runesmith", "hero_dask": "ironmarshal", "hero_tobbin": "artificer",
	"hero_ulvra": "thane", "hero_bjarr": "reaver", "hero_iska": "frostcaller",
	"hero_serane": "de_dreadmarshal", "hero_ulmarra": "de_veilseer", "hero_rhuvel": "de_nightstalker",
	"hero_ilo": "fm_deep_oracle", "hero_thunn": "fm_tidemarshal", "hero_sael": "fm_reef_hunter",
}


static func hero_profile(hero_id: String, class_id: String) -> Texture2D:
	if CAMPAIGN_PORTRAIT_CLASSES.get(hero_id, "") == class_id and class_id != "":
		var portrait_id: String = {"hero_watch": "hero_wren", "hero_scout": "hero_maelis"}.get(hero_id, hero_id)
		var unique := texture_at("res://assets/hero_portraits/campaign/%s.png" % portrait_id)
		if unique != null:
			return unique
	if not GameData.get_default().hero_classes.has(class_id):
		return null
	return texture_at("res://assets/hero_portraits/classes/%s.png" % class_id)


## Sprite id of a hero class's mounted figure (hero_<class>); the knight when
## a class has no art of its own.
static func hero_sprite_id(class_id: String) -> String:
	var id := "hero_" + class_id
	return id if has_sprite(id) else "hero_knight"


## Tint for a hero's greyscale banner overlay: the owning player's colour,
## lifted a little so dark player colours still read on the map.
static func banner_tint(player_color: Color) -> Color:
	return player_color.lightened(0.15)


static func hero(class_id: String) -> Texture2D:
	return sprite(hero_sprite_id(class_id))


static func resource_icon(resource_id: String) -> Texture2D:
	var icon := sprite("ui_resource_" + resource_id)
	if icon != null:
		return icon
	return sprite("resource_" + resource_id)


## Nine-slice StyleBox from a UI frame sprite, or null when not built.
static func stylebox(id: String, content_margin: float = -1.0) -> StyleBoxTexture:
	var tex := sprite(id)
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var ns: Array = sprite_info(id).get("nine_slice", [0, 0, 0, 0])
	sb.texture_margin_left = ns[0]
	sb.texture_margin_top = ns[1]
	sb.texture_margin_right = ns[2]
	sb.texture_margin_bottom = ns[3]
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	if content_margin >= 0.0:
		sb.set_content_margin_all(content_margin)
	return sb


static func terrain_info() -> Dictionary:
	return manifest().get("terrain", {})
