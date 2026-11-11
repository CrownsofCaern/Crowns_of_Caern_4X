class_name BattlefieldArt
extends RefCounted
## Terrain scenery selection never reads or advances the game's random stream.

const MANIFEST := "res://assets/battlefields/manifest.json"
static var _manifest: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest


static func select(terrain: String, visual_seed: int = 0) -> Dictionary:
	var data := manifest()
	var variants: Array = data.get("terrains", {}).get(terrain, [])
	if variants.is_empty():
		variants = data.get("terrains", {}).get(data.get("default_terrain", "grass"), [])
	if variants.is_empty():
		return {}
	return data["assets"].get(variants[posmod(visual_seed, variants.size())], {})


static func source_rect(source: Vector2, destination: Vector2, source_horizon: float, target_horizon: float) -> Rect2:
	if source.x <= 0 or source.y <= 0 or destination.x <= 0 or destination.y <= 0:
		return Rect2()
	var src_h := clampf(source_horizon,0.01,0.99)
	var dst_h := clampf(target_horizon,0.01,0.99)
	var factor := maxf(destination.x/source.x, destination.y/source.y)
	factor = maxf(factor,destination.y*dst_h/(source.y*src_h))
	factor = maxf(factor,destination.y*(1.0-dst_h)/(source.y*(1.0-src_h)))
	var scaled := source*factor
	var offset := Vector2((destination.x-scaled.x)*0.5,
		clampf(destination.y*dst_h-source.y*src_h*factor, destination.y-scaled.y, 0.0))
	return Rect2(-offset/factor,destination/factor)
