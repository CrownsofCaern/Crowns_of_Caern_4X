extends "res://tests/test_case.gd"
## Terrain painter: biome mix, rivers and lakes on generated maps, the
## decoration pass (clusters, no identical neighbours, clear of roads and
## objects), fairness of shared plans, and the painted-decoration map flag.

const TEMPLATES := ["twin_marches", "crossing", "adventure_marches_3_v1"]
const SEEDS := [1, 17]


func _gen(tpl: String, seed_number: int) -> Dictionary:
	return generated_map(tpl, seed_number)


func test_generated_maps_carry_painted_decorations() -> void:
	for tpl in TEMPLATES:
		var def := _gen(tpl, 1)
		assert_false(def.is_empty(), "%s generates" % tpl)
		assert_eq(String(def.get("decor", "")), TerrainPainter.DECOR_MODE, "%s is painted" % tpl)
		var with_variant := (def["decorations"] as Array).filter(func(d): return d.has("variant"))
		assert_gt(with_variant.size(), 50, "%s has painted decorations" % tpl)


func test_zones_mix_several_biomes() -> void:
	var biomes := 0.0
	var dominant := 0.0
	var mixed := 0.0
	var n := 0
	for tpl in TEMPLATES:
		for s in SEEDS:
			var st := TerrainPainter.terrain_stats(_gen(tpl, s), data)
			biomes += st["land_biomes"]
			dominant += st["dominant_share"]
			mixed += st["mixed_share"]
			n += 1
	assert_gt(biomes / n, 3.5, "maps mix several land biomes")
	assert_lt(dominant / n, 0.6, "no biome swallows the map")
	assert_gt(mixed / n, 0.2, "biomes meet often, not in a few big blocks")


func test_rivers_and_lakes_appear_without_breaking_maps() -> void:
	var rivers := 0
	var lakes := 0
	for tpl in TEMPLATES:
		for s in SEEDS:
			var def := _gen(tpl, s)
			var rows := "".join(def["terrain"])
			rivers += 1 if rows.contains("~") else 0
			lakes += 1 if rows.contains("#") else 0
			assert_eq(MapValidator.validate(def, data), [] as Array[String], "%s:%d stays valid" % [tpl, s])
	assert_gt(rivers, SEEDS.size(), "rivers run through many maps")
	assert_gt(lakes, SEEDS.size(), "lakes appear on many maps")


func test_no_decoration_shares_sprite_with_a_neighbour() -> void:
	for tpl in TEMPLATES:
		for s in SEEDS:
			var def := _gen(tpl, s)
			var painted := (def["decorations"] as Array).filter(func(d): return d.has("variant"))
			var st := TerrainPainter.terrain_stats(def, data, painted)
			assert_eq(float(st["identical_neighbors"]), 0.0, "%s:%d no identical neighbours" % [tpl, s])


func test_decoration_is_varied_and_clustered() -> void:
	var entropy := 0.0
	var kinds := 0.0
	var density := 0.0
	var n := 0
	for tpl in TEMPLATES:
		for s in SEEDS:
			var st := TerrainPainter.terrain_stats(_gen(tpl, s), data)
			entropy += st["kind_entropy"]
			kinds += st["deco_kinds"]
			density += st["deco_density"]
			n += 1
	assert_gt(kinds / n, 5.0, "many decoration kinds per map")
	assert_gt(entropy / n, 0.6, "no single kind dominates")
	assert_between(density / n, 0.08, 0.5, "decoration leaves open ground")


func test_decorations_stay_on_open_land_away_from_objects() -> void:
	var cfg: Dictionary = data.terrain_painting["decoration"]
	for tpl in TEMPLATES:
		var def := _gen(tpl, 2)
		var map := AdventureMap.from_definition(def, data)
		var near := {}
		for o in def["objects"]:
			var r := int(cfg["town_clearing"]) if o["type"] == "town" else int(cfg["object_margin"])
			var c := AdventureMap.object_pos(o)
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					near[c + Vector2i(dx, dy)] = true
		for d in def["decorations"]:
			if not d.has("variant"):
				continue
			var p := Vector2i(int(d["pos"][0]), int(d["pos"][1]))
			assert_false(map.has_road(p), "%s: no decoration on the road at %s" % [tpl, p])
			assert_true(map.is_passable(p) and map.terrain_at(p) != "river", "%s: decoration on open land at %s" % [tpl, p])
			assert_false(near.has(p), "%s: decoration keeps clear of objects at %s" % [tpl, p])


func test_painting_changes_with_the_seed() -> void:
	# Same seed, same painting: test_mapgen compares whole maps; here the
	# painting must change with the seed.
	var a := _gen("crossing", 1)
	var c := _gen("crossing", 17)
	assert_ne(JSON.stringify(a["decorations"]), JSON.stringify(c["decorations"]))


## Player start zones share one plan: the same share of secondary biomes.
func test_start_zones_get_the_same_biome_share() -> void:
	for tpl in ["twin_marches", "adventure_marches_3_v1"]:
		for s in [1, 5]:
			var g := MapGenerator.new(data)
			var def := g.run(tpl, s)
			assert_false(def.is_empty())
			var shares: Array = []
			for z in g.template["zones"].size():
				if not g.template["zones"][z].has("player"):
					continue
				var base := g._base_terrain(z)
				var land := 0
				var other := 0
				for i in g.layout.open_tiles(z):
					var t := g.terrain[i]
					if t == "river" or not bool(data.terrain(t)["passable"]):
						continue
					land += 1
					other += 1 if t != base else 0
				shares.append(float(other) / maxf(1.0, land))
			for sh in shares:
				assert_lt(absf(float(sh) - float(shares[0])), 0.12, "%s:%d start zones %s" % [tpl, s, shares])


func test_decorate_keeps_authored_entries_first() -> void:
	var def := data.load_map("ember_ford")
	def["decorations"] = [{"pos": [1, 1], "kind": "gravestone"}]
	var out := TerrainPainter.decorate(def, data, 7)
	assert_eq(out[0], {"pos": [1, 1], "kind": "gravestone"})
	assert_gt(out.size(), 4, "hand-made maps can be decorated too")
	for d in out.slice(1):
		assert_ne(d["pos"], [1, 1], "authored tiles stay as they are")


func test_map_round_trips_decor_mode_and_variants() -> void:
	var def := _gen("crossing", 1)
	var map := AdventureMap.from_definition(def, data)
	assert_eq(map.decor_mode, TerrainPainter.DECOR_MODE)
	var back := map.static_definition()
	assert_eq(String(back["decor"]), TerrainPainter.DECOR_MODE)
	var count := (back["decorations"] as Array).filter(func(d): return d.has("variant")).size()
	assert_eq(count, (def["decorations"] as Array).filter(func(d): return d.has("variant")).size())
	# Older maps and saves have neither and keep the view's own scenery.
	var old := data.load_map("ember_ford")
	var m2 := AdventureMap.from_definition(old, data)
	assert_eq(m2.decor_mode, "")
	assert_false(m2.static_definition().has("decor"))


func test_saved_game_keeps_painted_decorations() -> void:
	var def := _gen("crossing", 1)
	var st := GameState.new()
	st.map = AdventureMap.from_definition(def, data)
	var saved := st.map.static_definition()
	var again := AdventureMap.from_definition(JSON.parse_string(JSON.stringify(saved)), data)
	assert_eq(again.decor_mode, TerrainPainter.DECOR_MODE)
	assert_eq(again.decoration_variants, st.map.decoration_variants)


func test_config_validation_catches_bad_pools() -> void:
	assert_eq(TerrainPainter.validate_config(data, ["pines"], 10).filter(func(e): return e.contains("lacks")).size() > 0, true,
		"unknown atlas kinds are reported")
	var saved := data.terrain_painting
	var bad: Dictionary = saved.duplicate(true)
	bad["affinity"]["grass"]["mountain"] = 2
	bad["decoration"]["biomes"]["forest"]["density"] = 3.0
	data.terrain_painting = bad
	var errors := TerrainPainter.validate_config(data)
	data.terrain_painting = saved
	assert_true(errors.any(func(e): return e.contains("non-land terrain mountain")), str(errors))
	assert_true(errors.any(func(e): return e.contains("density")), str(errors))
	assert_eq(TerrainPainter.validate_config(data), [] as Array[String])


func test_landmarks_are_impassable_set_pieces() -> void:
	var found := 0
	for tpl in TEMPLATES:
		for s in SEEDS:
			var def := _gen(tpl, s)
			var map := AdventureMap.from_definition(def, data)
			for e in def.get("scenery", []):
				var lib: Dictionary = TerrainPainter.scenery_library()[e["kind"]]
				if lib["category"] != "landmark":
					continue
				found += 1
				assert_eq(e["footprint"], lib["footprint"])
				for dy in int(e["footprint"][1]):
					for dx in int(e["footprint"][0]):
						var p := Vector2i(int(e["pos"][0]) + dx, int(e["pos"][1]) + dy)
						assert_false(map.is_passable(p), "%s:%d landmark tile %s blocks" % [tpl, s, p])
						assert_true(map.object_at(p).is_empty(), "nothing stands on a landmark")
	assert_gt(found, 3, "landmarks appear on generated maps")


func test_scenery_pieces_are_spaced_and_on_their_biome() -> void:
	var cfg: Dictionary = data.terrain_painting["scenery"]
	var total := 0
	for tpl in TEMPLATES:
		var def := _gen(tpl, 3)
		var map := AdventureMap.from_definition(def, data)
		var pieces: Array = def.get("scenery", []).filter(func(e): return int(e["footprint"][0]) == 1 and int(e["footprint"][1]) == 1)
		total += pieces.size()
		for e in pieces:
			var p := Vector2i(int(e["pos"][0]), int(e["pos"][1]))
			assert_true(cfg["biomes"].has(map.terrain_at(p)), "%s scenery on a listed biome" % e["kind"])
			assert_true(cfg["biomes"][map.terrain_at(p)].has(e["kind"]), "%s fits %s" % [e["kind"], map.terrain_at(p)])
			assert_false(map.has_road(p))
			for o in pieces:
				if o != e:
					var q := Vector2i(int(o["pos"][0]), int(o["pos"][1]))
					assert_true(maxi(absi(p.x - q.x), absi(p.y - q.y)) >= int(cfg["spacing"]), "scenery is spaced out")
			for d in def["decorations"]:
				assert_ne(d["pos"], e["pos"], "no decoration under scenery")
	assert_gt(total, 3, "scenery pieces appear")


func test_surface_patches_cover_their_terrain_share() -> void:
	var def := _gen("twin_marches", 2)
	assert_true(def.has("surface"), "ground variants are painted")
	var map := AdventureMap.from_definition(def, data)
	var per: Dictionary = data.terrain_painting["surfaces"]["kinds"]
	var counts := {}
	var on := {}
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var t := map.terrain_at(p)
			counts[t] = int(counts.get(t, 0)) + 1
			if map.surface.has(p):
				assert_true(per.has(t) and per[t]["kind"] == map.surface[p], "surface %s matches %s" % [map.surface[p], t])
				on[t] = int(on.get(t, 0)) + 1
	for t in on:
		assert_between(float(on[t]) / counts[t], float(per[t]["coverage"]) - 0.05, float(per[t]["coverage"]) + 0.05, t)
	var back := AdventureMap.from_definition(map.static_definition(), data)
	assert_eq(back.surface, map.surface, "ground variants survive a save")
	assert_eq(back.scenery, map.scenery, "scenery survives a save")
