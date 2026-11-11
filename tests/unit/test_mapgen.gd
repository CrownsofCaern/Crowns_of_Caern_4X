extends "res://tests/test_case.gd"
## Procedural map generation: determinism, validity, connectivity, start
## fairness, guarded chokepoints and integration with GameSession.

const TEMPLATES := ["twin_marches", "crossing", "broad_crossing", "great_marches"]
const SEEDS := [1, 2, 3, 17, 404, 90210]

static var _cache: Dictionary = {}


func _gen(tpl: String, seed_number: int) -> Dictionary:
	var key := "%s:%d" % [tpl, seed_number]
	if not _cache.has(key):
		_cache[key] = MapGenerator.generate(data, tpl, seed_number)
	return _cache[key]


func _grid_costs(def: Dictionary, neutrals_block: bool) -> Array:
	var d := def.duplicate()
	d["objects"] = []
	var m := AdventureMap.from_definition(d, data)
	var cost := PackedInt32Array()
	cost.resize(m.width * m.height)
	for y in m.height:
		for x in m.width:
			if m.is_passable(Vector2i(x, y)):
				cost[y * m.width + x] = m.move_cost(Vector2i(x, y))
	if neutrals_block:
		for o in def["objects"]:
			if o["type"] == "neutral_army":
				cost[int(o["pos"][1]) * m.width + int(o["pos"][0])] = 0
	return [m.width, m.height, cost]


func _idx(def: Dictionary, o: Dictionary) -> int:
	return int(o["pos"][1]) * int(def["width"]) + int(o["pos"][0])


func _zone(def: Dictionary, zone_id: String) -> Dictionary:
	for z in def["generator"]["zones"]:
		if z["id"] == zone_id:
			return z
	return {}


func test_templates_validate() -> void:
	var errors := MapGenerator.validate_templates(data)
	assert_true(errors.is_empty(), ", ".join(errors))
	assert_true(data.map_templates["templates"].size() >= 2)


func test_map_ids_round_trip() -> void:
	var id := MapGenerator.make_id("twin_marches", 77)
	assert_eq(id, "gen:twin_marches:77")
	assert_eq(MapGenerator.parse_id(id), {"template": "twin_marches", "seed": 77, "factions": []})
	assert_true(MapGenerator.parse_id("ember_ford").is_empty())
	assert_true(MapGenerator.parse_id("gen:twin_marches:x").is_empty())


func test_same_seed_same_map() -> void:
	for tpl in TEMPLATES:
		var a := JSON.stringify(MapGenerator.generate(data, tpl, 31337))
		var b := JSON.stringify(MapGenerator.generate(data, tpl, 31337))
		assert_eq(a, b, "%s is deterministic" % tpl)


func test_different_seeds_differ() -> void:
	var a := _gen("twin_marches", 1)
	var b := _gen("twin_marches", 2)
	assert_ne(JSON.stringify(a["terrain"]), JSON.stringify(b["terrain"]))
	assert_ne(JSON.stringify(a["objects"]), JSON.stringify(b["objects"]))


func test_generated_maps_are_valid() -> void:
	for tpl in TEMPLATES:
		for s in SEEDS:
			var def := _gen(tpl, s)
			assert_false(def.is_empty(), "%s/%d generated" % [tpl, s])
			if def.is_empty():
				continue
			var errors := MapValidator.validate(def, data)
			assert_true(errors.is_empty(), "%s/%d: %s" % [tpl, s, ", ".join(errors)])
			var t: Dictionary = data.map_templates["templates"][tpl]
			assert_eq(def["width"], t["width"])
			assert_eq(def["height"], t["height"])
			assert_eq(def["id"], MapGenerator.make_id(tpl, s))


func test_whole_map_is_connected() -> void:
	for tpl in TEMPLATES:
		for s in SEEDS:
			var def := _gen(tpl, s)
			var g := _grid_costs(def, false)
			var dist := GridSearch.distances(g[0], g[1], g[2], PackedInt32Array([_idx(def, def["heroes"][0])]))
			for o in def["objects"] + def["heroes"]:
				assert_true(dist[_idx(def, o)] >= 0, "%s/%d: %s reachable" % [tpl, s, o["id"]])
			# Every passable tile can be reached (no sealed-off land).
			var cost: PackedInt32Array = g[2]
			var stranded := 0
			for i in cost.size():
				if cost[i] > 0 and dist[i] < 0 and i != _idx(def, def["heroes"][0]):
					stranded += 1
			assert_eq(stranded, 0, "%s/%d stranded tiles" % [tpl, s])


func test_each_player_gets_town_hero_and_basic_mines() -> void:
	for s in SEEDS:
		var def := _gen("twin_marches", s)
		for hd in def["heroes"]:
			var pl := int(hd["owner"])
			var towns: Array = def["objects"].filter(func(o): return o["type"] == "town" and int(o["owner"]) == pl)
			assert_eq(towns.size(), 1, "seed %d player %d owns one town" % [s, pl])
			var t: Dictionary = towns[0]
			assert_eq(t["town_type"], def["players"][pl]["faction"])
			assert_false(t.has("garrison"), "own town starts ungarrisoned")
			var d := Vector2i(int(hd["pos"][0]) - int(t["pos"][0]), int(hd["pos"][1]) - int(t["pos"][1]))
			assert_true(absi(d.x) <= 1 and absi(d.y) <= 1, "hero starts next to the town")
			for res in ["wood", "ore"]:
				var mines: Array = def["objects"].filter(func(o): return o["type"] == "mine" and o["resource"] == res and o["zone"] == t["zone"] and not o.has("guard"))
				assert_true(mines.size() >= 1, "seed %d player %d has a free %s mine" % [s, pl, res])


func test_starts_are_fair() -> void:
	for tpl in TEMPLATES:
		for s in SEEDS:
			var m := MapValidator.fairness(_gen(tpl, s), data)
			assert_eq(m.size(), 2)
			var a: Dictionary = m[0]
			var b: Dictionary = m[1]
			assert_eq(a["signature"], b["signature"], "%s/%d same start content" % [tpl, s])
			assert_eq(a["guard_value"], b["guard_value"], "%s/%d same start guard strength" % [tpl, s])
			assert_eq(a["pile_value"], b["pile_value"], "%s/%d same start pickups" % [tpl, s])
			for kind in ["wood", "ore"]:
				assert_lt(absi(int(a["mine_cost"][kind]) - int(b["mine_cost"][kind])), 500, "%s/%d %s mine distance" % [tpl, s, kind])
				assert_lt(int(a["mine_cost"][kind]), 1500, "%s mine within a day" % kind)
			var lo := mini(int(a["enemy_town_cost"]), int(b["enemy_town_cost"]))
			var hi := maxi(int(a["enemy_town_cost"]), int(b["enemy_town_cost"]))
			assert_lt(float(hi) / float(lo), 1.36, "%s/%d enemy distance %d vs %d" % [tpl, s, lo, hi])


func test_factions_get_their_own_rare_mine() -> void:
	var gen := MapGenerator.new(data)
	assert_eq(gen.faction_rare("concord"), "gems")
	assert_eq(gen.faction_rare("ashen"), "sulfur")
	var def := _gen("twin_marches", 3)
	for hd in def["heroes"]:
		var faction: String = def["players"][int(hd["owner"])]["faction"]
		var zone := String(_zone_for_player(def, int(hd["owner"]))["id"])
		var rare: Array = def["objects"].filter(func(o): return o["type"] == "mine" and o["zone"] == zone and o["resource"] == gen.faction_rare(faction))
		assert_eq(rare.size(), 1, "%s start has its %s mine" % [faction, gen.faction_rare(faction)])


func _zone_for_player(def: Dictionary, pl: int) -> Dictionary:
	for z in def["generator"]["zones"]:
		if int(z.get("player", -1)) == pl:
			return z
	return {}


func test_players_are_separated_by_guarded_chokepoints() -> void:
	for tpl in TEMPLATES:
		for s in SEEDS:
			var def := _gen(tpl, s)
			var safe := _grid_costs(def, true)
			var free := _grid_costs(def, false)
			var h0: Dictionary = def["heroes"][0]
			var h1: Dictionary = def["heroes"][1]
			var d_safe := GridSearch.distances(safe[0], safe[1], safe[2], PackedInt32Array([_idx(def, h0)]))
			var d_free := GridSearch.distances(free[0], free[1], free[2], PackedInt32Array([_idx(def, h0)]))
			assert_true(d_free[_idx(def, h1)] > 0, "%s/%d heroes can meet" % [tpl, s])
			assert_eq(d_safe[_idx(def, h1)], -1, "%s/%d only by fighting through a guard" % [tpl, s])
			# Every guarded connection is a one-tile pass with its guard on it.
			var conns: Array = data.map_templates["templates"][tpl]["connections"]
			for ci in conns.size():
				var gc: Dictionary = def["generator"]["connections"][ci]
				assert_false(gc["gate"].is_empty(), "%s/%d connection %d has a pass" % [tpl, s, ci])
				if conns[ci]["guard"] != "none":
					assert_ne(gc["guard"], "", "%s/%d connection %d is guarded" % [tpl, s, ci])
					if int(conns[ci].get("width", 1)) == 1:
						assert_eq(gc["gate"].size(), 1)


func test_guarded_treasure_needs_a_fight() -> void:
	var checked := 0
	for s in SEEDS:
		var def := _gen("twin_marches", s)
		var by_id := {}
		for o in def["objects"]:
			by_id[o["id"]] = o
		for o in def["objects"]:
			if not o.has("guarded_by"):
				continue
			var guard: Dictionary = by_id[o["guarded_by"]]
			assert_eq(guard["type"], "neutral_army")
			assert_eq(guard["guards"], o["id"])
			var gp := Vector2i(int(guard["pos"][0]), int(guard["pos"][1]))
			var op := Vector2i(int(o["pos"][0]), int(o["pos"][1]))
			assert_eq(absi(gp.x - op.x) + absi(gp.y - op.y), 1, "guard stands next to %s" % o["id"])
			if o["type"] == "resource" and o.get("treasure", false):
				# Named templates use open guard pockets: the prize sits in the
				# open and its adjacent guard keeps it out of reach (the guard rule).
				checked += 1
	assert_gt(checked, 10, "treasure comes with an adjacent guard")


func test_neutral_strength_follows_guard_levels() -> void:
	var levels: Dictionary = data.map_templates["guard_levels"]
	for s in SEEDS:
		var def := _gen("twin_marches", s)
		for o in def["objects"]:
			if o["type"] != "neutral_army":
				continue
			var v := 0
			for st in o["stacks"]:
				v += MapGenerator.creature_value(data.creature(st[0])) * int(st[1])
			var known := false
			var spread := float(data.map_templates["hoard_rules"]["guard_spread"]) if o.get("hoard", false) else 0.0
			for lv in levels.values():
				known = known or absf(float(o["value"]) - float(lv)) <= float(lv) * spread + 25.0
			assert_true(known, "value is a guard level (within the hoard spread)")
			assert_between(float(v) / float(o["value"]), 0.75, 1.35, "%s army worth %d for level %d" % [o["id"], v, o["value"]])
			assert_true(String(o["name"]).length() > 0)


func test_placement_follows_distance_bands() -> void:
	# Not random: free wood/ore mines are close to the town, the gold mine far.
	var bands: Dictionary = data.map_templates["distance_bands"]
	for s in SEEDS:
		var def := _gen("twin_marches", s)
		for hd in def["heroes"]:
			var m: Dictionary = MapValidator.fairness(def, data)[int(hd["owner"])]
			assert_lt(int(m["mine_cost"]["wood"]), int(bands["mid"][1]), "wood mine near")
			assert_gt(int(m["mine_cost"]["gold"]), int(m["mine_cost"]["wood"]), "gold mine farther than wood")


func test_session_plays_generated_map() -> void:
	var id := MapGenerator.make_id("crossing", 5)
	var s := GameSession.new_game(data, id, 9)
	assert_eq(s.state.map.map_id, id)
	assert_eq(s.state.players.size(), 2)
	assert_eq(s.state.heroes.size(), 2)
	var h := s.hero("hero_p0")
	assert_true(h != null)
	assert_true(s.state.map.is_passable(h.pos))
	# March towards the nearest free resource pile and collect it.
	var target := Vector2i(-1, -1)
	var best := 1 << 30
	for oid in s.state.map.objects:
		var o: Dictionary = s.state.map.objects[oid]
		if o["type"] == "resource" and not o.has("guarded_by"):
			var plan := s.plan_path("hero_p0", AdventureMap.object_pos(o))
			var cost := 0
			for c in plan["costs"]:
				cost += int(c)
			if not plan["path"].is_empty() and cost < best:
				best = cost
				target = AdventureMap.object_pos(o)
	assert_ne(target, Vector2i(-1, -1), "a free pile is reachable")
	var before: Dictionary = s.state.player(0)["resources"].to_dict()
	for _day in 3:
		s.move_hero("hero_p0", target)
		if h.pos == target:
			break
		s.end_turn()
		s.end_turn()
	assert_eq(h.pos, target)
	assert_ne(JSON.stringify(s.state.player(0)["resources"].to_dict()), JSON.stringify(before), "pile collected")


func test_save_load_generated_map() -> void:
	var s := GameSession.new_game(data, MapGenerator.make_id("twin_marches", 12), 4)
	s.end_turn()
	var path := "user://test_mapgen_save.json"
	assert_eq(s.save_to_file(path), OK)
	var loaded := GameSession.load_from_file(data, path)
	assert_true(loaded != null)
	assert_eq(JSON.stringify(loaded.state.to_dict()), JSON.stringify(s.state.to_dict()))
	assert_eq(loaded.state.map.width, s.state.map.width)
	for i in s.state.map.terrain.size():
		if loaded.state.map.terrain[i] != s.state.map.terrain[i]:
			assert_true(false, "terrain differs after load at %d" % i)
			break


func test_hand_made_map_passes_structural_checks() -> void:
	var errors := MapValidator.validate(data.load_map("ember_ford"), data)
	assert_true(errors.is_empty(), ", ".join(errors))


func test_encounters_follow_risk_tiers() -> void:
	var risk: Dictionary = data.map_templates["encounter_risk"]
	for s in SEEDS:
		var def := _gen("twin_marches", s)
		var m := AdventureMap.from_definition(def.merged({"objects": []}, true), data)
		var gate_tiles := {}
		for c in def["generator"]["connections"]:
			for t in c["gate"]:
				gate_tiles[Vector2i(int(t[0]), int(t[1]))] = true
		var by_zone := {}
		for o in def["objects"]:
			if o["type"] != "encounter":
				continue
			assert_true(data.encounters.has(o["encounter"]), "known encounter")
			var p := AdventureMap.object_pos(o)
			assert_false(m.has_road(p), "seed %d: %s not on a road" % [s, o["id"]])
			assert_false(gate_tiles.has(p), "seed %d: %s not in a pass" % [s, o["id"]])
			var profile := String(_zone(def, o["zone"])["profile"])
			var tier := "low" if profile in ["start", "wild"] else "high"
			assert_true((risk[tier] as Array).has(o["encounter"]), "seed %d: %s in a %s zone is %s risk" % [s, o["encounter"], profile, tier])
			by_zone[o["zone"]] = by_zone.get(o["zone"], []) + [o["encounter"]]
		assert_eq(by_zone.get("start_0", []), by_zone.get("start_1", []), "mirrored starts share encounters")
		assert_true(by_zone.has("heart"), "the heartland has encounters")


func test_neutral_towns_have_garrisons() -> void:
	for s in SEEDS:
		var def := _gen("twin_marches", s)
		var neutral: Array = def["objects"].filter(func(o): return o["type"] == "town" and int(o["owner"]) < 0)
		assert_eq(neutral.size(), 3, "flanks and heartland hold neutral towns")
		for t in neutral:
			assert_true(data.town_types.has(t["town_type"]))
			assert_false((t.get("garrison", []) as Array).is_empty(), "%s is garrisoned" % t["id"])


func test_zone_terrain_varies() -> void:
	var distinct := 0
	for s in SEEDS:
		var def := _gen("twin_marches", s)
		var seen := {}
		for z in def["generator"]["zones"]:
			if not z.has("player"):
				seen[z["terrain"]] = true
		distinct += seen.size()
	# wild, flank and heartland groups pick different base terrains.
	assert_eq(distinct, SEEDS.size() * 3)


func test_session_runs_town_rules_on_generated_map() -> void:
	var s := GameSession.new_game(data, MapGenerator.make_id("twin_marches", 8), 2)
	var own := 0
	for id in s.state.map.objects:
		var o: Dictionary = s.state.map.objects[id]
		if o["type"] == "town":
			assert_true((o["built"] as Array).size() > 0, "Town.normalize filled buildings")
			if int(o["owner"]) == 0:
				own += 1
		if o["type"] == "mine" and not (o.get("guard", []) as Array).is_empty():
			assert_true(s.is_guarded(o, 0), "guarded mine counts as guarded")
	assert_eq(own, 1)


func test_save_stores_generated_terrain() -> void:
	var s := GameSession.new_game(data, MapGenerator.make_id("crossing", 21), 4)
	var d := s.state.to_dict()
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	assert_true(d.has("map"), "generated maps save their terrain")
	assert_true(GameSession.new_game(data, "ember_ford", 1).state.to_dict().has("map"), "hand-made maps also save their terrain")
	# The loaded terrain comes from the save, not from regenerating the id.
	var rows: Array = d["map"]["terrain"]
	var p := Vector2i(-1, -1)
	for y in rows.size():
		var x := String(rows[y]).find(".")
		if x >= 0:
			p = Vector2i(x, y)
			break
	if p.x < 0:
		p = Vector2i(0, 0)
	var row := String(rows[p.y])
	row[p.x] = "d"
	rows[p.y] = row
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)), data)
	assert_eq(loaded.map.terrain_at(p), "desert")
	assert_eq(loaded.map.width, s.state.map.width)


func test_v3_save_of_generated_map_migrates() -> void:
	var s := GameSession.new_game(data, MapGenerator.make_id("crossing", 22), 4)
	s.end_turn()
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	d.erase("map")
	d["version"] = 3
	assert_true(GameState.validate_save(d).is_empty())
	var loaded := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_eq(JSON.stringify(loaded.state.to_dict()), JSON.stringify(s.state.to_dict()), "v3 save regenerates the same map")


func test_validator_rejects_unknown_object_types() -> void:
	var def := _gen("crossing", 1).duplicate(true)
	def["objects"].append({"id": "oddity", "type": "artifact_pile", "pos": def["objects"][0]["pos"]})
	var errors := MapValidator.validate(def, data)
	assert_true(errors.size() >= 2, "unknown type and shared tile: %s" % ", ".join(errors))


func test_validator_lets_a_hero_start_in_its_own_town() -> void:
	var def := data.load_map("twin_marches").duplicate(true)
	assert_eq(MapValidator.validate(def, data).size(), 0, "heroes start in their own towns")
	# Swap the heroes: each now stands in the rival's town.
	var a: Array = def["heroes"][0]["pos"]
	def["heroes"][0]["pos"] = def["heroes"][1]["pos"]
	def["heroes"][1]["pos"] = a
	var errors := MapValidator.validate(def, data)
	assert_eq(errors.size(), 2, "a hero in a rival's town still shares a tile: %s" % ", ".join(errors))


func _hoards(def: Dictionary) -> Array:
	return def["objects"].filter(func(o): return o.get("hoard", false) and o["type"] != "neutral_army")


func test_hoards_fill_every_zone_by_its_size() -> void:
	var expected_total := 0
	var placed_total := 0
	for tpl in TEMPLATES:
		for s in SEEDS:
			var def := _gen(tpl, s)
			var tpl_zones: Array = data.map_templates["templates"][tpl]["zones"]
			for zi in tpl_zones.size():
				var zone: Dictionary = def["generator"]["zones"][zi]
				var fill: Dictionary = data.map_templates["profiles"][zone["profile"]].get("hoards", {})
				# Mirrored zones copy the first zone of their group, so count by that one.
				var first := zi
				for zj in zi:
					if tpl_zones[zj].get("group", "") == tpl_zones[zi].get("group", "") and tpl_zones[zi].has("group"):
						first = zj
						break
				var want := MapGenerator.hoard_count(int(def["generator"]["zones"][first]["tiles"]), fill)
				var got := _hoards(def).filter(func(o): return o["zone"] == zone["id"]).size()
				expected_total += want
				placed_total += got
				assert_true(got <= want, "%s %d %s: at most %d hoards, got %d" % [tpl, s, zone["id"], want, got])
				if zone.has("player"):
					assert_eq(got, want, "%s %d: every start hoard placed" % [tpl, s])
	assert_gt(float(placed_total) / expected_total, 0.95, "nearly every planned hoard finds a spot")


func test_hoards_are_guarded_pockets() -> void:
	for s in SEEDS:
		var def := _gen("great_marches", s)
		var by_id := {}
		for o in def["objects"]:
			by_id[o["id"]] = o
		for o in _hoards(def):
			assert_true(o.has("guarded_by"), "%s has a guard" % o["id"])
			var g: Dictionary = by_id[o["guarded_by"]]
			assert_true(g.get("hoard", false), "the guard is marked as a hoard guard")
			assert_true(o["type"] == "artifact" or (o["type"] == "resource" and o["treasure"]), "a hoard is treasure or armour")


func test_hoard_guards_grow_toward_the_heart() -> void:
	var by_profile := {}
	var counts := {}
	for tpl in ["twin_marches", "great_marches"]:
		for s in SEEDS:
			var def := _gen(tpl, s)
			var profile_of := {}
			for z in def["generator"]["zones"]:
				profile_of[z["id"]] = z["profile"]
			for o in def["objects"]:
				if o["type"] == "neutral_army" and o.get("hoard", false):
					var p: String = profile_of[o["zone"]]
					by_profile[p] = float(by_profile.get(p, 0.0)) + float(o["value"])
					counts[p] = int(counts.get(p, 0)) + 1
	var avg := {}
	for p in by_profile:
		avg[p] = by_profile[p] / counts[p]
	assert_lt(avg["start"], avg["wild"], "start hoards are the weakest")
	assert_lt(avg["wild"], avg["center"], "the heart holds the strongest guards")
	assert_lt(avg["flank"], avg["center"])
	assert_lt(avg["start"], 2000.0, "start hoards are light or weak on average")
	assert_gt(avg["center"], 6000.0, "heart hoards are strong on average")


func test_hoard_prizes_scale_with_their_guard() -> void:
	var rules: Dictionary = data.map_templates["hoard_rules"]
	var checked := 0
	for s in SEEDS:
		var def := _gen("broad_crossing", s)
		var by_id := {}
		for o in def["objects"]:
			by_id[o["id"]] = o
		for o in _hoards(def):
			if o["type"] != "resource":
				continue
			var unit := float(MapValidator.RESOURCE_VALUE.get(o["resource"], MapValidator.RARE_VALUE))
			var worth := float(o["amount"]) * unit
			var gv := float(by_id[o["guarded_by"]]["value"])
			var lo := maxf(float(rules["min_value"]), gv * float(rules["value_ratio"][0]))
			var hi := maxf(float(rules["min_value"]), gv * float(rules["value_ratio"][1]))
			var slack := 50.0 if o["resource"] == "gold" else unit   # gold is rounded to hundreds
			assert_between(worth, lo - slack, hi + slack, "%s worth %d for a %d guard" % [o["id"], worth, gv])
			checked += 1
	assert_gt(checked, 20)


func test_generated_maps_are_denser_than_before() -> void:
	# Before hoards (generator v1) twin marches had about 28 neutral armies.
	for s in SEEDS:
		var def := _gen("twin_marches", s)
		var neutrals: Array = def["objects"].filter(func(o): return o["type"] == "neutral_army")
		assert_gt(neutrals.size(), 40, "seed %d has a dense field of neutrals" % s)


func test_validator_rejects_bad_hoard_settings() -> void:
	var saved: Dictionary = data.map_templates.duplicate(true)
	data.map_templates["profiles"]["start"]["hoards"]["picks"][0]["guard"] = "colossal"
	data.map_templates["hoard_rules"]["value_ratio"] = [0.8, 0.2]
	var errors := MapGenerator.validate_templates(data)
	data.map_templates = saved
	assert_true(errors.any(func(e): return e.contains("hoards: guard")), "unknown guard level reported")
	assert_true(errors.any(func(e): return e.contains("value_ratio")), "bad ratio reported")


func test_ai_counts_the_cache_behind_a_hoard_guard() -> void:
	var s := GameSession.new_game(data, MapGenerator.make_id("crossing", 5), 9)
	s.end_turn()   # the computer player
	var h: Hero = s.state.heroes_of(1)[0]
	var cache := {}
	for id in s.state.map.objects:
		var o: Dictionary = s.state.map.objects[id]
		if o["type"] == "resource" and o.get("hoard", false):
			cache = o
			break
	assert_false(cache.is_empty(), "the map has a guarded cache")
	var guard: Dictionary = s.state.map.objects[cache["guarded_by"]]
	var gp := AdventureMap.object_pos(guard)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = gp + d
		if s.state.map.is_passable(q) and q != AdventureMap.object_pos(cache) and s.state.map.object_at(q).is_empty():
			h.pos = q
			break
	s.state.player(1)["fog"].reveal(h.pos, 4)
	var ai := StrategicAI.new(s, 1)
	var field := AiDistanceField.build(s.state.map, h.pos, ai._blocked_for(h))
	var cands: Array = ai.candidate_targets(h, field).filter(func(c): return c["id"] == guard["id"])
	assert_eq(cands.size(), 1, "the guard is a target")
	var floor_value := ai.defender_value(guard) * float(ai.settings["neutral_value_rate"]) \
		+ float(cache["amount"]) * ai.resource_value(cache["resource"])
	assert_gt(float(cands[0]["value"]), floor_value - 1.0, "the cache behind it counts")


func test_large_free_for_all_maps() -> void:
	for players in [4, 5, 6]:
		var tpl := "crown_of_%d" % players
		for seed_number in [1, 17, 404]:
			var def := _gen(tpl, seed_number)
			assert_false(def.is_empty(), "%s generated" % tpl)
			if def.is_empty():
				continue
			assert_eq(def["players"].size(), players)
			assert_eq(def["heroes"].size(), players)
			assert_true(MapValidator.validate(def, data).is_empty(), "%s validates" % tpl)
			for z in def["generator"]["zones"]:
				if z.get("profile", "") == "center":
					for o in def["objects"]:
						if o.get("zone", "") == z["id"] and o.get("role", "") == "wander":
							assert_true(int(o["value"]) >= 8500, "heartland wanderers are strong")


func test_authored_landmarks_survive_map_snapshot() -> void:
	for id in ["greyhold_harvest", "knight_who_came_back", "gen:crown_of_4:1"]:
		var def := data.load_map(id)
		assert_false(def.get("decorations", []).is_empty(), "%s has authored decoration" % id)
		var map := AdventureMap.from_definition(def, data)
		var restored := AdventureMap.from_definition(map.static_definition(), data)
		assert_eq(restored.decorations, map.decorations, "%s retains landmarks" % id)
		for p in map.decorations:
			assert_true(map.in_bounds(p) and map.is_passable(p), "%s landmark is on land" % id)
			assert_false(map.has_road(p), "%s landmark is off the road" % id)
			assert_true(map.object_at(p).is_empty(), "%s landmark is clear of objects" % id)


func test_story_map_snapshots_and_legacy_saves() -> void:
	var session := GameSession.new_game(data, "greyhold_harvest", 1)
	var saved := session.state.to_dict()
	assert_true(saved.has("map"), "story saves snapshot their map")
	var restored := GameState.from_dict(saved, data)
	assert_eq(restored.map.width, 51)
	assert_eq(restored.map.decorations, session.state.map.decorations)
	saved.erase("map")
	var old := GameState.from_dict(saved, data)
	assert_eq(old.map.width, 44, "older story saves retain their original terrain")


## The hand-made campaign maps (second_lockstone and bring_the_winter are frozen
## generator maps since the map overhaul and carry the generator's sites).
func test_campaign_landmarks_and_previous_layouts() -> void:
	var ids := ["burning_ford", "ashes_return", "into_the_embers", "warm_earth", "twice_dead", "pale_crown",
		"deep_shift", "fallen_hold", "axe_line", "roots_remember", "briar_seal",
		"sun_goes_out", "granary_of_highmere", "pit_below", "breaking_the_lockstone", "red_sky_throne"]
	for id in ids:
		var def := data.load_map(id)
		var old: Dictionary = GameData.read_json(GameData.DATA_DIR + "/legacy_maps/" + id + ".json")
		# Area, not width: some kept layouts were turned a quarter (map overhaul).
		assert_true(int(def["width"]) * int(def["height"]) > int(old["width"]) * int(old["height"]), "%s was enlarged" % id)
		var sites: Array = def["objects"].filter(func(o): return o.get("type", "") == "site")
		assert_eq(sites.size(), 2, "%s has two story buildings" % id)
		assert_true((def.get("decorations", []) as Array).size() + sites.size() >= 6, "%s has its landmarks" % id)
		assert_true(MapValidator.validate(def, data).is_empty(), "%s remains reachable" % id)
		var map := AdventureMap.from_definition(def, data)
		for p in map.decorations:
			assert_true(map.is_passable(p) and not map.has_road(p) and map.object_at(p).is_empty(), "%s landmark is clear" % id)


func test_free_for_all_rim_waystations() -> void:
	var def := _gen("crown_of_4", 1)
	for z in def["generator"]["zones"]:
		if not z.has("player"):
			continue
		var anchor := Vector2i(int(z["anchor"][0]), int(z["anchor"][1]))
		var pieces := 0
		for d in def.get("decorations", []):
			var p := Vector2i(int(d["pos"][0]), int(d["pos"][1]))
			if anchor.distance_to(p) < 14:
				pieces += 1
		assert_gt(pieces, 0, "player %s has a rim landmark" % z["player"])


func test_story_buildings_use_all_existing_landmark_art() -> void:
	var used := {}
	var used_art := {}
	for id in ["greyhold_harvest", "knight_who_came_back", "burning_ford", "ashes_return", "into_the_embers", "warm_earth", "twice_dead", "pale_crown", "deep_shift", "fallen_hold", "second_lockstone", "axe_line", "roots_remember", "briar_seal", "sun_goes_out", "granary_of_highmere", "bring_the_winter", "pit_below", "breaking_the_lockstone", "red_sky_throne"]:
		var def := data.load_map(id)
		for o in def["objects"]:
			if o.get("type", "") != "site":
				continue
			var sid := String(o["site"])
			used[sid] = true
			used_art[String(data.sites[sid]["sprite"])] = true
			assert_true(Art.sprite(String(data.sites[sid]["sprite"])) != null, "%s has art" % sid)
			if data.sites[sid]["kind"] == "dwelling":
				assert_true(MapSites.creature_pool(data.sites[sid], data).has(o["creature"]), "%s offers a suitable creature" % sid)
			if String(data.sites[sid].get("guard", "none")) != "none":
				assert_false(o.get("guard", []).is_empty(), "%s is guarded" % sid)
	# Spell crypts and traders are random finds with separately rolled content,
	# so the handcrafted stories need not permanently include either. Cobolt
	# trading posts are traders too: every map gets one at new game.
	var landmarks := data.sites.keys().filter(func(k): return String(data.sites[k]["kind"]) not in ["spell", "trader", "village", "cobolt"])
	# (Frozen generator maps among them may also hold random finds.)
	# The Living maps sites reuse landmark art and are random finds; what must
	# appear in the stories is every piece of landmark art.
	for k in landmarks:
		assert_true(used.has(k) or used_art.has(String(data.sites[k]["sprite"])), "landmark art of %s is used" % k)


func test_crown_has_fair_rim_sites_and_guarded_landmarks() -> void:
	for players in [4, 5, 6]:
		var def := _gen("crown_of_%d" % players, 1)
		var rim := 0
		var heart := {}
		for o in def["objects"]:
			if o.get("type", "") != "site":
				continue
			if o.get("zone", "") == "heart":
				heart[o["site"]] = o
			elif o.get("site", "") == "wardens_causeway":
				rim += 1
		assert_eq(rim, players, "every player has the same waystation")
		for sid in ["pyre_citadel", "sellsword_gate", "bleeding_rift", "elder_rings", "outcast_camp", "pilgrims_rest"]:
			assert_true(heart.has(sid), "%s in the heart" % sid)
			if heart.has(sid) and String(data.sites[sid].get("guard", "none")) != "none":
				var guards: Array = heart[sid].get("guard", [])
				var value := 0.0
				for stack in guards:
					value += MapGenerator.creature_value(data.creature(stack[0])) * int(stack[1])
				assert_gt(value, 6500.0, "%s has a strong heartland guard" % sid)


func test_town_names_are_unique_per_map() -> void:
	for template in ["random_s_4p_normal_normal", "random_xl_6p_normal_normal", "twin_marches"]:
		for s in range(1, 9):
			var def := MapGenerator.generate(data, template, s)
			var names := {}
			for o in def["objects"]:
				if o["type"] == "town":
					assert_false(names.has(o["name"]), "%s seed %d repeats %s" % [template, s, o["name"]])
					names[o["name"]] = true
	assert_eq(JSON.stringify(MapGenerator.generate(data, "random_s_4p_normal_normal", 3)), JSON.stringify(MapGenerator.generate(data, "random_s_4p_normal_normal", 3)))


func test_town_names_fall_back_to_a_numbered_suffix() -> void:
	var g := MapGenerator.new(data)
	g.rng = GameRng.new(5)
	for n in data.map_templates["town_names"]:
		g.objects.append({"type": "town", "name": n})
	var first := g._town_name()
	assert_true(first.ends_with(" II"), first)
	g.objects.append({"type": "town", "name": first})
	g.rng = GameRng.new(5)
	assert_eq(g._town_name(), first.trim_suffix(" II") + " III")
