class_name VeteranVisual
extends RefCounted
## Level-five art stays keyed by the improved creature id, so it cannot be bought.
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _frames: Dictionary = {}

static func unit(id: String) -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/build/veteran_animations/manifest.json"))
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest.get("units", {}).get(id, {})

static func frames(id: String, action: String) -> Array:
	var key := id + ":" + action
	if _frames.has(key):
		return _frames[key]
	var definition := unit(id)
	if definition.is_empty() or not definition["actions"].has(action):
		return []
	var clip: Dictionary = definition["actions"][action]
	var path := "res://" + String(clip["path"])
	if not _textures.has(path):
		var texture := Art.texture_at(path)
		if texture == null:
			var image := Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
				return []
			texture = ImageTexture.create_from_image(image)
		_textures[path] = texture
	var result := []
	for i in int(clip["frame_count"]):
		var frame := AtlasTexture.new()
		frame.atlas = _textures[path]
		frame.region = Rect2(i * 320, 0, 320, 256)
		result.append(frame)
	_frames[key] = result
	return result

static func still(id: String) -> Texture2D:
	var poses := frames(id, "attack")
	if poses.is_empty():
		return null
	var frame := AtlasTexture.new()
	frame.atlas = poses[0].atlas
	# The fourth attack frame contains the approved 128px resting pose.
	frame.region = Rect2(1056, 80, 128, 128)
	return frame
