extends "res://tests/test_case.gd"
## Random maps (RandomMapTemplate, random_maps in map_templates.json), the
## generator's density fill and scales, the bigger templates and campaign
## maps, and the new-game options.


func _cfg() -> Dictionary:
	return data.map_templates


func _neutral_value(def: Dictionary) -> int:
	var v := 0
	for o in def["objects"]:
		if o["type"] == "neutral_army":
			v += int(o.get("value", 0))
	return v


func _count(def: Dictionary, pred: Callable) -> int:
	return (def["objects"] as Array).filter(pred).size()


func test_names_round_trip_and_bad_names_are_rejected() -> void:
	var tname := RandomMapTemplate.make_name("l", 4, "strong", "rich")
	assert_eq(tname, "random_l_4p_strong_rich")
	assert_eq(RandomMapTemplate.parse(_cfg(), tname), {"size": "l", "players": 4, "monsters": "strong", "treasure": "rich"})
	assert_true(MapGenerator.has_template(_cfg(), tname))
	var fam := RandomMapTemplate.make_name("m", 2, "normal", "normal", "diagonal")
	assert_eq(fam, "random_m_2p_normal_normal_diagonal")
	assert_eq(RandomMapTemplate.parse(_cfg(), fam)["family"], "diagonal")
	assert_eq(RandomMapTemplate.make_name("m", 2, "normal", "normal", "mixed"), "random_m_2p_normal_normal", "mixed keeps the short name")
	for bad in ["random_q_4p_normal_normal", "random_m_4_normal_normal", "random_m_1p_normal_normal",
			"random_s_6p_normal_normal", "random_m_4p_furious_normal", "random_m_4p_normal_heaps", "random_m_4p_normal",
			"random_m_4p_normal_normal_diagonal", "random_m_2p_normal_normal_moat", "random_m_2p_normal_normal_ring_x"]:
		assert_eq(RandomMapTemplate.parse(_cfg(), bad), {}, bad)
		assert_false(MapGenerator.has_template(_cfg(), bad), bad)
	assert_eq(RandomMapTemplate.build(_cfg(), "random_s_6p_normal_normal", 1), {}, "a small map holds at most four players")


func test_templates_scale_with_size_and_players() -> void:
	var last := 0
	for size in RandomMapTemplate.option_keys(_cfg(), "sizes"):
		var t := RandomMapTemplate.build(_cfg(), RandomMapTemplate.make_name(size, 2, "normal", "normal", "ring"), 1)
		assert_gt(int(t["width"]), last, "%s is larger than the size before" % size)
		last = int(t["width"])
		assert_eq((t["zones"] as Array).size(), RandomMapTemplate.zone_count(_cfg(), size, 2))
	var two := RandomMapTemplate.build(_cfg(), "random_m_2p_normal_normal", 1)
	var six := RandomMapTemplate.build(_cfg(), "random_m_6p_normal_normal", 1)
	assert_gt(int(six["width"]), int(two["width"]), "more players, more room")
	assert_eq((six["players"] as Array).size(), 6)
	assert_eq(String(two["symmetry"]), "rotate180", "even player counts mirror each other")
	assert_eq(String(RandomMapTemplate.build(_cfg(), "random_m_3p_normal_normal", 1)["symmetry"]), "none")
	# Every player has exactly one start zone, and the template passes the template checks.
	var starts := (six["zones"] as Array).filter(func(z): return z.has("player"))
	assert_eq(starts.size(), 6)
	# Same options and seed, same template.
	assert_eq(RandomMapTemplate.build(_cfg(), "random_m_6p_normal_normal", 1), six)


func test_random_maps_generate_valid_fair_maps() -> void:
	for tname in ["random_s_3p_normal_normal", "random_m_4p_normal_normal", "random_l_2p_weak_sparse", "random_xl_5p_strong_rich"]:
		var g := MapGenerator.new(data)
		var def := g.run(tname, 11)
		assert_false(def.is_empty(), "%s generates (%s)" % [tname, g.rejected])
		if def.is_empty():
			continue
		assert_eq(MapValidator.validate(def, data), [] as Array[String], tname)
		var n := int(RandomMapTemplate.parse(_cfg(), tname)["players"])
		assert_eq((def["players"] as Array).size(), n)
		assert_eq((def["heroes"] as Array).size(), n)
		for p in n:
			assert_eq(_count(def, func(o): return o["type"] == "town" and int(o.get("owner", -1)) == p), 1, "%s player %d owns a town" % [tname, p])
		assert_eq(String(def["id"]), "gen:%s:11" % tname)


func test_monster_and_treasure_options_change_the_map() -> void:
	# Summed over three seeds: one map alone can land near the bound (seed 5
	# alone gave a ratio of 1.96 after the open guard pockets in #135), while
	# the three together sit around 2.4.
	var weak_value := 0
	var deadly_value := 0
	for seed in [5, 6, 7]:
		weak_value += _neutral_value(generated_map("random_m_2p_weak_normal", seed))
		deadly_value += _neutral_value(generated_map("random_m_2p_deadly_normal", seed))
	assert_gt(deadly_value, weak_value * 2.0, "deadly guards are far stronger than weak ones")
	var sparse := generated_map("random_m_2p_normal_sparse", 5)
	var rich := generated_map("random_m_2p_normal_rich", 5)
	var loot := func(o): return o["type"] == "resource" and (bool(o.get("hoard", false)) or bool(o.get("scatter", false)))
	assert_gt(_count(rich, loot), _count(sparse, loot) * 1.6, "rich maps hold many more hoards and piles")


func test_scatter_fills_zones_with_matching_piles() -> void:
	var def := generated_map("twin_marches", 1)
	var per_zone := {}
	for o in def["objects"]:
		if bool(o.get("scatter", false)):
			assert_false(o.has("guarded_by"), "scattered piles are free")
			per_zone[o["zone"]] = int(per_zone.get(o["zone"], 0)) + 1
	assert_gt(per_zone.size(), 3, "most zones get scattered piles")
	assert_eq(per_zone.get("start_0", 0), per_zone.get("start_1", 0), "both starts get the same piles")
	assert_gt(int(per_zone.get("start_0", 0)), 0)
	assert_eq(MapGenerator.hoard_count(260, {"per_tiles": 100, "max": 4}, 1.5), 4, "treasure scale raises the rate")
	assert_eq(MapGenerator.hoard_count(1000, {"per_tiles": 100, "max": 4}, 1.5), 6)
	assert_eq(MapGenerator.hoard_count(1000, {"per_tiles": 100, "max": 4}, 0.5), 2)


func test_skirmish_and_campaign_maps_are_large() -> void:
	# Playtests (Nov 7): the maps were still too small, so every template is about
	# twice the area of its first version and the hand-made campaign maps too.
	var old_area := {"twin_marches": 36 * 36, "crossing": 34 * 24, "broad_crossing": 50 * 34, "great_marches": 48 * 48}
	for tid in old_area:
		var t: Dictionary = _cfg()["templates"][tid]
		assert_gt(int(t["width"]) * int(t["height"]), old_area[tid] * 1.85, "%s is about twice as large" % tid)
	for cid in data.campaigns:
		for ch in data.campaigns[cid]["chapters"]:
			var mid := String(ch["map"])
			if MapGenerator.is_generated_id(mid) or ScenarioGenerator.is_generated_id(mid):
				continue
			var def: Dictionary = GameData.read_json("%s/maps/%s.json" % [GameData.DATA_DIR, mid])
			assert_gt(int(def["width"]) * int(def["height"]), 1200, "%s %s is a large map" % [cid, mid])


func test_bad_random_settings_are_reported() -> void:
	var cfg := _cfg().duplicate(true)
	cfg["random_maps"]["sizes"]["m"]["rings"] = ["moat"]
	cfg["random_maps"]["sizes"]["x_y"] = {"max_players": 1, "player_tiles": 10, "rings": ["outer"]}
	cfg["random_maps"]["monsters"]["weak"]["scale"] = 0
	var errors := RandomMapTemplate.validate(cfg)
	for want in ["unknown ring moat", "must not contain _", "max_players below", "player_tiles", "outer ring needs", "scale must be > 0"]:
		assert_true(errors.any(func(e): return String(e).contains(want)), "reports: " + want)
	assert_eq(RandomMapTemplate.validate(_cfg()), [] as Array[String])
	assert_eq(MapGenerator.validate_templates(data), [] as Array[String])


func test_new_game_entry_and_setup_for_a_random_map() -> void:
	var maps := GameSetup.available_maps(data)
	assert_true(bool(maps[0].get("random", false)), "the random map comes first")
	var entry := GameSetup.random_entry(data, {"size": "s", "players": 6, "monsters": "normal", "treasure": "rich"})
	assert_eq(entry["slots"].size(), 4, "players are clamped to what the size holds")
	assert_eq(int(entry["options"]["players"]), 4)
	entry = GameSetup.random_entry(data, {"size": "m", "players": 4, "monsters": "weak", "treasure": "normal"})
	assert_eq(entry["slots"].size(), 4)
	var setup := GameSetup.default_setup(entry)
	setup["players"][1]["faction"] = "forge"
	setup["players"][2]["faction"] = "hollow"
	setup["players"][3]["type"] = "closed"
	setup["players"][0]["team"] = 1
	setup["players"][1]["team"] = 1
	setup["players"][2]["difficulty"] = "hard"
	setup["standard_start"] = true
	var map_id := GameSetup.map_id_for(entry, 21)
	assert_eq(map_id, "gen:random_m_4p_weak_normal:21")
	var s := GameSession.new_game(data, map_id, 21, setup)
	assert_eq(s.state.players.size(), 3, "the closed slot is removed")
	assert_eq(String(s.state.player(1)["faction"]), "forge")
	assert_eq(String(s.state.player(2)["difficulty"]), "hard")
	assert_eq(int(s.state.player(0)["team"]), int(s.state.player(1)["team"]))
	assert_gt(s.state.map.width, 60)


func test_menu_random_options_rebuild_the_slots() -> void:
	var menu := MainMenu.new()
	menu.build(data)
	menu.open(false)
	menu._show_setup()
	assert_true(bool(menu._selected_map().get("random", false)), "New Game opens on the random map")
	assert_true(menu._random_row.visible)
	menu.set_random_options({"size": "l", "players": 5, "monsters": "strong", "treasure": "sparse"})
	assert_eq(menu._slot_rows.size(), 5)
	assert_eq(menu._selected_map()["template"], "random_l_5p_strong_sparse")
	menu.set_random_options({"size": "s"})
	assert_eq(menu._slot_rows.size(), 4, "a small map lowers the player count")
	assert_eq(menu.random_options()["players"], 4)
	var got := []
	menu.start_requested.connect(func(map_id, seed_value, setup): got.append([map_id, seed_value, setup]))
	menu._seed_edit.text = "77"
	menu._start()
	assert_eq(got.size(), 1)
	assert_eq(got[0][0], "gen:random_s_4p_strong_sparse:77")
	assert_eq((got[0][2]["players"] as Array).size(), 4)
	# Picking a curated seed hides the random options and plays its own seed.
	for i in menu._maps.size():
		if bool(menu._maps[i].get("curated", false)):
			menu._map_pick.select(i)
			menu._fill_slots()
			break
	assert_true(bool(menu._selected_map().get("curated", false)))
	assert_false(menu._random_row.visible)
	menu._start()
	assert_eq(got.size(), 2)
	assert_eq(got[1][0], GameSetup.map_id_for(menu._selected_map(), 0))
	assert_eq(got[1][1], 77, "the seed box still seeds the game")
	menu.free()
