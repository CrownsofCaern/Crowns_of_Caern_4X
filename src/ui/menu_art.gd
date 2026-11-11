class_name MenuArt
extends RefCounted
## Full-resolution menu artwork and game-facing branding. The user data folder
## uses the new title; LegacyUserData copies saves from previous titles over.

const TITLE := "Crowns of Caern"
const MANIFEST := "res://assets/menus/manifest.json"
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest


static func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var entry: Dictionary = manifest().get("assets", {}).get(id, {})
	var path := String(entry.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var result: Texture2D = load(path)
	if result != null and bool(entry.get("crop_alpha", false)):
		var image := result.get_image()
		if image != null:
			var bounds := image.get_used_rect()
			if bounds.has_area():
				var cropped := AtlasTexture.new()
				cropped.atlas = result
				cropped.region = Rect2(bounds)
				result = cropped
	_textures[id] = result
	return result


static func backdrop(id: String) -> TextureRect:
	var image := TextureRect.new()
	image.name = "MenuArtwork"
	image.texture = texture(id)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return image
