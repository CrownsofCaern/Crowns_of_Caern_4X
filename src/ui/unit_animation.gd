class_name UnitAnimation
extends RefCounted
## Read-only clips. Battle code supplies action/time; this class never simulates combat.

static var _manifest: Dictionary = {}
static var _frames: Dictionary = {}
static var _raw_atlases: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists("res://assets/animations.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animations.json"))
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest


static func clip(sprite_id: String, action: String) -> Dictionary:
	return manifest().get("units", {}).get(sprite_id, {}).get("actions", {}).get(action, {})


static func frame_index(animation: Dictionary, elapsed: float) -> int:
	var durations: Array = animation.get("durations_ms", [])
	if durations.is_empty() or elapsed < 0.0:
		return -1
	var total := 0
	for duration in durations:
		total += int(duration)
	var time := int(elapsed * 1000.0)
	if bool(animation.get("loop", false)):
		time = time % maxi(total, 1)
	elif time >= total:
		return -1
	for i in durations.size():
		if time < int(durations[i]):
			return i
		time -= int(durations[i])
	return -1


static func sample(sprite_id: String, action: String, elapsed: float) -> Dictionary:
	var animation := clip(sprite_id, action)
	var index := frame_index(animation, elapsed)
	if index < 0:
		return {}
	var key := "%s:%s:%d" % [sprite_id, action, index]
	if not _frames.has(key):
		var unit: Dictionary = manifest()["units"][sprite_id]
		# A clip may live in its own atlas (idle passes), and a frame may name
		# its own (an attack ending on another sheet's rest pose).
		var atlas_name := String(animation.get("atlas", unit["atlas"]))
		var per_frame: Array = animation.get("frame_atlases", [])
		if index < per_frame.size():
			atlas_name = String(per_frame[index])
		var atlas: Dictionary = manifest()["atlases"][atlas_name]
		var texture := Art.texture_at(atlas["path"])
		if texture == null:
			var path := String(atlas["path"])
			if not _raw_atlases.has(path) and FileAccess.file_exists(path):
				var image := Image.new()
				if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
					_raw_atlases[path] = ImageTexture.create_from_image(image)
			texture = _raw_atlases.get(path)
			if texture == null:
				return {}
		var frame := AtlasTexture.new()
		frame.atlas = texture
		var r: Array = animation["frames"][index]
		frame.region = Rect2(r[0], r[1], r[2], r[3])
		_frames[key] = frame
	var anchor: Array = manifest()["anchor"]
	return {"texture": _frames[key], "anchor": Vector2(anchor[0], anchor[1]), "frame": index}


static func events_between(animation: Dictionary, previous: float, current: float) -> Array:
	var result := []
	for event in animation.get("events", []):
		var when := float(event["time_ms"]) / 1000.0
		if previous < when and current >= when:
			result.append(event["name"])
	return result


static func frames(sprite_id: String, action: String) -> Array:
	var animation := clip(sprite_id, action)
	var result := []
	var elapsed := 0.0
	for duration in animation.get("durations_ms", []):
		var pose := sample(sprite_id, action, elapsed + 0.001)
		if pose.is_empty():
			return []
		result.append(pose["texture"])
		elapsed += float(duration) / 1000.0
	return result
