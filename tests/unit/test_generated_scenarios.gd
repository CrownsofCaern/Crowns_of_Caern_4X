extends "res://tests/test_case.gd"


func test_generated_scenario_recipes_validate() -> void:
	assert_eq(ScenarioGenerator.validate(data), [] as Array[String])
	assert_eq(Campaign.validate(data), [] as Array[String])


func test_generated_sieges_are_valid_and_vary_geography_and_armies() -> void:
	var shapes := {}
	var armies := {}
	for recipe in ["survival_v1", "defence_v1", "endless_v1"]:
		for seed_value in [1, 7, 19, 37]:
			var def := ScenarioGenerator.generate(data, recipe, seed_value)
			assert_false(def.is_empty())
			var errors := MapValidator.validate(def, data)
			assert_true(errors.is_empty(), "%s seed %d: %s" % [recipe, seed_value, ", ".join(errors)])
			shapes[JSON.stringify(def["terrain"])] = true
			armies[JSON.stringify(def["scenario"]["waves"])] = true
	assert_gt(shapes.size(), 2)
	assert_gt(armies.size(), 2)


func test_labyrinth_has_feasible_deadline_and_risky_shortcut() -> void:
	for seed_value in [1, 7, 19, 37, 404, 90210]:
		var def := ScenarioGenerator.generate(data, "labyrinth_v1", seed_value)
		var errors := MapValidator.validate(def, data)
		assert_true(errors.is_empty(), "seed %d: %s" % [seed_value, ", ".join(errors)])
		var s := GameSession.new_game(data, String(def["id"]), 9)
		var hero := s.hero("hero_watch")
		var goal: Array = def["scenario"]["objectives"][0]["pos"]
		var target := Vector2i(int(goal[0]), int(goal[1]))
		var keeper: Dictionary = s.state.map.objects.get("labyrinth_shortcut_guard", {})
		assert_false(keeper.is_empty(), "there must be a guarded shorter route")
		var travel_def := def.duplicate(true)
		travel_def["objects"] = travel_def["objects"].filter(func(o): return o["type"] != "neutral_army" or o["id"] == "labyrinth_shortcut_guard")
		var travel_map := AdventureMap.from_definition(travel_def, data)
		var finder := Pathfinder.new(travel_map)
		var safe_route := finder.find_path(hero.pos, target)
		var safe_cost := 0
		for cost in finder.step_costs(hero.pos, safe_route):
			safe_cost += cost
		var safe := {"total_cost": safe_cost}
		assert_between(safe["total_cost"], 11000, 21000)
		assert_gt(21 - ceili(float(safe["total_cost"]) / hero.max_movement(data)), 5, "reserve time for battles and detours")
		var unsafe := Pathfinder.new(s.state.map).find_path(hero.pos, target)
		var short_cost := 0
		for cost in s.pathfinder.step_costs(hero.pos, unsafe):
			short_cost += cost
		# Remove the shortcut guard to compare the route the player can unlock.
		travel_map.remove_object("labyrinth_shortcut_guard")
		var opened := finder.find_path(hero.pos, target)
		var opened_cost := 0
		for cost in finder.step_costs(hero.pos, opened):
			opened_cost += cost
		assert_lt(opened_cost, safe["total_cost"] - 1500)
		assert_false(s.state.game_over)


func test_generated_scenario_save_is_a_snapshot() -> void:
	var s := GameSession.new_game(data, "scenario:survival_v1:7", 11)
	s.state.day = 7
	WaveDirector.on_day(s)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	var original := data.scenario_recipes.duplicate(true)
	data.scenario_recipes = {}
	var back := GameSession.from_state(data, GameState.from_dict(saved, data))
	data.scenario_recipes = original
	assert_eq(JSON.parse_string(JSON.stringify(back.state.map.static_definition())), saved["map"])
	assert_eq(back.state.rules, saved["rules"])
	assert_eq(back.state.scenario_runtime, saved["scenario_runtime"])
	var actual_ids := back.state.heroes.keys()
	var expected_ids := s.state.heroes.keys()
	actual_ids.sort()
	expected_ids.sort()
	assert_eq(actual_ids, expected_ids)
	assert_eq(back.state.scenario_runtime["spawned"], s.state.scenario_runtime["spawned"])


func test_endless_continues_and_has_no_automatic_victory() -> void:
	var s := GameSession.new_game(data, "scenario:endless_v1:7", 11)
	s.state.day = 70
	WaveDirector.on_day(s)
	assert_gt(WaveDirector.waves(s.state).size(), 8)
	for h in s.state.heroes_of(1):
		h.alive = false
	VictoryRules.update(s)
	assert_false(s.state.game_over)
	assert_false(WaveDirector.cleared(s.state))


func test_setup_keeps_scenario_roles_and_converts_player_faction() -> void:
	var entry := GameSetup.map_entry(data, "scenario:labyrinth_v1:7")
	var setup := GameSetup.default_setup(entry)
	setup["players"][0]["faction"] = "frostmarch"
	setup["standard_start"] = true
	var s := GameSession.new_game(data, GameSetup.map_id_for(entry, 7), 11, setup)
	assert_true(s.hero("hero_watch") != null)
	assert_eq(s.hero("hero_watch").faction, "frostmarch")
	assert_eq(s.state.heroes_of(0).size(), 1)
	assert_false(s.state.game_over)


func test_new_campaign_uses_three_distinct_mission_types() -> void:
	var c := Campaign.start(data, "long_watch", 7)
	var expected := ["survival", "defence", "labyrinth"]
	for i in 3:
		c.chapter = i
		var s := c.begin_chapter(data)
		assert_true(s != null)
		assert_eq(ScenarioRules.definition(s.state)["mode"], expected[i])
		assert_true(s.hero("hero_watch") != null)
