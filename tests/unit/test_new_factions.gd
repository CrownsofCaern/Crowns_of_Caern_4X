extends "res://tests/test_case.gd"


func test_factions_have_full_rosters_and_art() -> void:
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/dlc_factions.json"))
	for fid in ["darkelf", "fishmen"]:
		assert_true(fid in GameSetup.playable_factions(data), fid)
		var roster: Array = pack["factions"][fid]["creature_ids"]
		assert_eq(roster.size(), 16)
		for i in 8:
			var base: Dictionary = data.creature(roster[i * 2])
			var upgraded: Dictionary = data.creature(roster[i * 2 + 1])
			assert_eq(int(base["tier"]), i + 1)
			assert_eq(base["upgrade"], roster[i * 2 + 1])
			assert_eq(upgraded["upgrade_of"], roster[i * 2])
			assert_true(Art.has_sprite("creature_" + String(roster[i * 2])))
		assert_eq(GameSetup.classes_for_faction(data, fid).size(), 3)


func test_new_factions_start_recruit_and_survive_save() -> void:
	var setup := {"players": [{"type": "human", "faction": "darkelf", "hero_class": "de_veilseer"},
		{"type": "computer", "faction": "fishmen", "hero_class": "fm_deep_oracle"}], "standard_start": true}
	var session := GameSession.new_game(data, "twin_marches", 5, setup)
	for i in 2:
		var faction: String = ["darkelf", "fishmen"][i]
		var hero: Hero = session.state.heroes_of(i)[0]
		assert_eq(hero.class_id, ["de_veilseer", "fm_deep_oracle"][i])
		var town: Dictionary = session.towns_of(i)[0]
		assert_eq(town["town_type"], faction)
		assert_eq(data.creature(Town.recruitable(town, data)[0])["faction"], faction)
	var town_id: String = session.towns_of(0)[0]["id"]
	assert_true(session.recruit(town_id, "de_gloam_spear", 1, true)["ok"])
	var restored := GameState.from_dict(session.state.to_dict(), data)
	assert_eq(restored.player(0)["faction"], "darkelf")
	assert_eq(restored.player(1)["faction"], "fishmen")
	assert_eq(restored.heroes_of(0)[0].class_id, "de_veilseer")


func test_new_factions_on_generated_map() -> void:
	var maps := GameSetup.available_maps(data).filter(func(m): return m["generated"] and m["slots"].size() >= 2)
	assert_false(maps.is_empty())
	if maps.is_empty():
		return
	var entry: Dictionary = maps[0]
	var setup := GameSetup.default_setup(entry)
	setup["players"][0]["faction"] = "darkelf"
	setup["players"][1]["faction"] = "fishmen"
	var session := GameSession.new_game(data, GameSetup.map_id_for(entry, 5), 5, setup)
	assert_eq(session.towns_of(0)[0]["town_type"], "darkelf")
	assert_eq(session.towns_of(1)[0]["town_type"], "fishmen")
	assert_eq(data.hero_classes[session.state.heroes_of(0)[0].class_id]["faction"], "darkelf")
	assert_eq(data.hero_classes[session.state.heroes_of(1)[0].class_id]["faction"], "fishmen")
