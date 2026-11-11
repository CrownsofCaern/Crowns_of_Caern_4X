extends "res://tests/test_case.gd"


func test_every_faction_keeps_the_mission_starting_development() -> void:
	var def := data.load_map("last_watch")
	var entry := {"slots": GameSetup._slots_from(def["players"])}
	for faction in GameSetup.playable_factions(data):
		var setup := GameSetup.default_setup(entry)
		setup["players"][0]["faction"] = faction
		setup["standard_start"] = true
		var s := GameSession.new_game(data, "last_watch", 7, setup)
		assert_eq(s.state.heroes_of(0).size(), 2, faction)
		assert_true(s.hero("hero_watch") != null)
		assert_true(s.hero("hero_scout") != null)
		var castle := s.town("town_last_watch")
		assert_eq(String(castle["town_type"]), faction)
		var tiers := []
		for creature in Town.dwellings(castle, data):
			tiers.append(int(data.creature(creature)["tier"]))
		tiers.sort()
		assert_eq(tiers, [1, 2, 3], faction + " must retain the authored tier-3 castle")
		assert_true(Town.defense_bonus(castle, data) >= 2)
		assert_false(s.state.game_over)


func test_scenario_role_and_difficulty_validation() -> void:
	var def := data.load_map("last_watch")
	var entry := {"slots": GameSetup._slots_from(def["players"])}
	var setup := GameSetup.default_setup(entry)
	setup["players"][1]["difficulty"] = "passive"
	assert_false(GameSetup.validate(def, setup, data).is_empty())
	setup["players"][1]["difficulty"] = "normal"
	setup["players"][2]["type"] = "closed"
	assert_false(GameSetup.validate(def, setup, data).is_empty())
