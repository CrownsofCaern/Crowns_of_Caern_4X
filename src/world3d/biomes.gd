class_name Biomes
extends RefCounted
## Ground looks per biome (data/biomes.json): colours, water or lava, pools, how
## many dead trees. View-only data; the rules never read it.

const PATH := "res://data/biomes.json"
const COLOR_KEYS := ["grass", "lush", "dry", "dirt", "rock", "moss", "ash", "water_deep", "water_sky", "tuft"]
const NUMBER_KEYS := ["puddles", "dead_trees", "trees", "bushes", "tufts", "snow"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data


static func get_biome(biome_name: String) -> Dictionary:
	var b: Dictionary = data()["biomes"]
	return b.get(biome_name, b[data()["base"]])


static func for_faction(faction: String) -> String:
	return data()["factions"].get(faction, data()["base"])


static func color(b: Dictionary, key: String) -> Color:
	var a: Array = b[key]
	return Color(float(a[0]), float(a[1]), float(a[2]))


static func validate() -> Array[String]:
	var errors: Array[String] = []
	var d := data()
	if not d.get("biomes", {}).has(d.get("base", "")):
		errors.append("biomes: base biome missing")
	for f in d.get("factions", {}):
		if not d["biomes"].has(d["factions"][f]):
			errors.append("biomes: faction %s uses unknown biome %s" % [f, d["factions"][f]])
	for n in d.get("biomes", {}):
		var b: Dictionary = d["biomes"][n]
		for k in COLOR_KEYS:
			if not b.has(k) or (b[k] as Array).size() != 3:
				errors.append("biomes: %s needs colour %s" % [n, k])
		for k in NUMBER_KEYS:
			if not b.has(k) or float(b[k]) < 0.0:
				errors.append("biomes: %s needs a non-negative %s" % [n, k])
		if not b.has("lava"):
			errors.append("biomes: %s needs lava true/false" % n)
	return errors
