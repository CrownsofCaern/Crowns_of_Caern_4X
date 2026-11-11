extends SceneTree
## Terrain and decoration variety over many generated maps (TerrainPainter.terrain_stats).
##   godot --headless --path . --script res://tools/terrain_report.gd -- [seeds] [out.md] [template,template...]
## For each template it averages the biome mix of the painted terrain and the
## variety of the decorations. "view fallback" measures what the map view's
## per-terrain hash scenery would show on the same terrain (the only decoration
## maps had before the painter), so the two decoration columns compare directly.

const DEFAULT_TEMPLATES := ["twin_marches", "crossing", "broad_crossing", "great_marches", "adventure_marches_4_v1",
	"crown_of_4", "random_m_4p_normal_normal", "random_l_2p_normal_normal"]
const KEYS := ["land_biomes", "dominant_share", "mixed_share", "mean_patch", "deco_density", "deco_kinds", "kind_entropy",
	"same_kind_neighbors", "identical_neighbors"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 20
	var out_path: String = args[1] if args.size() > 1 else ""
	var templates: Array = Array(args[2].split(",")) if args.size() > 2 else DEFAULT_TEMPLATES
	var data := GameData.get_default()
	var manifest: Dictionary = GameData.read_json("res://assets/manifest.json")
	var lines: Array[String] = ["# Terrain and decoration variety", "",
		"%d seeds per template. Shares are fractions of passable land tiles (rivers excluded)." % seeds, "",
		"| template | biomes | dominant | mixed | mean patch | deco density | kinds | kind entropy | same-kind nbr | identical nbr | fallback kinds | fallback entropy | fallback identical nbr |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
	for tpl in templates:
		var sum := {}
		var fb := {}
		var n := 0
		for s in range(1, seeds + 1):
			var def := MapGenerator.generate(data, String(tpl), s)
			if def.is_empty():
				continue
			n += 1
			_add(sum, TerrainPainter.terrain_stats(def, data))
			_add(fb, TerrainPainter.terrain_stats(def, data, fallback_decorations(def, data, manifest)))
		if n == 0:
			lines.append("| %s | failed |" % tpl)
			continue
		lines.append("| %s | %.1f | %.2f | %.2f | %.0f | %.2f | %.1f | %.2f | %.2f | %.3f | %.1f | %.2f | %.3f |" % [tpl,
			sum["land_biomes"] / n, sum["dominant_share"] / n, sum["mixed_share"] / n, sum["mean_patch"] / n, sum["deco_density"] / n,
			sum["deco_kinds"] / n, sum["kind_entropy"] / n, sum["same_kind_neighbors"] / n, sum["identical_neighbors"] / n,
			fb["deco_kinds"] / n, fb["kind_entropy"] / n, fb["identical_neighbors"] / n])
	var text := "\n".join(lines) + "\n"
	print(text)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(text)
	quit(0)


static func _add(acc: Dictionary, st: Dictionary) -> void:
	for k in KEYS:
		acc[k] = float(acc.get(k, 0.0)) + float(st[k])


## The decorations the map view draws on land when a map places none itself
## (TerrainTiles.deco_coords), as {pos, kind, variant}.
static func fallback_decorations(def: Dictionary, data: GameData, manifest: Dictionary) -> Array:
	var t: Dictionary = manifest.get("terrain", {})
	var variants := int(t.get("deco", {}).get("variants", 1))
	var map := AdventureMap.from_definition(def, data)
	var taken := {}
	for o in def["objects"]:
		taken[AdventureMap.object_pos(o)] = true
	var out: Array = []
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var tid := map.terrain_at(p)
			if map.has_road(p) or taken.has(p) or tid == "river" or not map.is_passable(p):
				continue
			var d: Dictionary = t.get("terrains", {}).get(tid, {}).get("deco", {})
			var kinds: Array = d.get("kinds", [])
			if kinds.is_empty() or TerrainTiles.cell_hash(p, 1000, 3) >= int(float(d.get("chance", 0.0)) * 1000.0):
				continue
			out.append({"pos": [x, y], "kind": kinds[TerrainTiles.cell_hash(p, kinds.size(), 5)],
				"variant": TerrainTiles.cell_hash(p, variants, 11)})
	return out
