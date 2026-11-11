extends "res://tests/test_case.gd"
## Mission recipes v2 (map overhaul phase 2): sieges on the map generator, the
## wide-corridor expedition maze, template-aware scenario ids, and the
## week-one rule for every offered recipe and the Long Watch chapters.


func _week_one(map_id: String) -> Array[String]:
	var s := GameSession.new_game(data, map_id, 5, {}, {"random_events": false})
	return ScenarioGating.week_one_problems(s)


func test_scenario_ids_carry_an_optional_template() -> void:
	assert_eq(ScenarioGenerator.parse_id("scenario:survival_v2:4"), {"recipe": "survival_v2", "seed": 4, "template": ""})
	assert_eq(ScenarioGenerator.parse_id("scenario:survival_v2:random_m_2p_normal_normal_hub:4"),
		{"recipe": "survival_v2", "seed": 4, "template": "random_m_2p_normal_normal_hub"})
	assert_eq(ScenarioGenerator.make_id("defence_v2", "random_s_2p_weak_poor", 9), "scenario:defence_v2:random_s_2p_weak_poor:9")
	assert_eq(ScenarioGenerator.make_id("labyrinth_v2", "", 9), "scenario:labyrinth_v2:9")
	assert_eq(ScenarioGenerator.parse_id("scenario:survival_v2::4"), {})
	assert_eq(ScenarioGenerator.parse_id("scenario:survival_v2:x"), {})
	assert_true(ScenarioGenerator.generate(data, "survival_v2", 1, "not_a_template").is_empty())
	assert_true(ScenarioGenerator.generate(data, "labyrinth_v2", 1, "random_m_2p_normal_normal").is_empty(), "the maze takes no template")


func test_menus_offer_current_recipes_only() -> void:
	assert_eq(ScenarioGenerator.current_recipe(data, "survival"), "survival_v2")
	assert_eq(ScenarioGenerator.current_recipe(data, "defence"), "defence_v2")
	assert_eq(ScenarioGenerator.current_recipe(data, "endless"), "endless_v2")
	assert_eq(ScenarioGenerator.current_recipe(data, "labyrinth"), "labyrinth_v2")
	assert_eq(ScenarioGenerator.current_recipe(data, "townless"), "townless_v1")
	assert_true(ScenarioGenerator.uses_template(data, "survival_v2"))
	assert_true(ScenarioGenerator.uses_template(data, "townless_v1"))
	assert_false(ScenarioGenerator.uses_template(data, "labyrinth_v2"))
	assert_eq(ScenarioGenerator.players(data, "defence_v2").size(), 3)
	assert_eq(ScenarioGenerator.players(data, "labyrinth_v2").size(), 1)
	assert_eq(ScenarioGenerator.players(data, "townless_v1", "random_m_3p_normal_normal").size(), 3)


func test_legacy_recipes_still_load() -> void:
	for recipe in ["survival_v1", "defence_v1", "endless_v1", "labyrinth_v1"]:
		assert_true(bool(ScenarioGenerator.recipe_of(data, recipe).get("legacy", false)))
		assert_false(data.load_map("scenario:%s:7" % recipe).is_empty(), recipe)


func test_recipe_validation_rejects_bad_siege_waves() -> void:
	var original := data.scenario_recipes.duplicate(true)
	data.scenario_recipes["recipes"]["survival_v2"]["waves"] = [[0, 1.0], [7, -1]]
	data.scenario_recipes["recipes"]["defence_v2"]["template"] = "nowhere"
	data.scenario_recipes["recipes"]["endless_v2"]["legacy"] = "yes"
	var errors := ScenarioGenerator.validate(data)
	data.scenario_recipes = original
	assert_eq(errors.size(), 4, "\n".join(errors))


func test_sieges_build_on_the_generator_with_gated_goals() -> void:
	var shapes := {}
	for case in [["survival_v2", "", 1], ["defence_v2", "", 2], ["endless_v2", "random_m_2p_normal_normal_diagonal", 3], ["survival_v2", "random_s_4p_normal_normal", 4]]:
		var id := ScenarioGenerator.make_id(case[0], case[1], case[2])
		var def := data.load_map(id)
		assert_false(def.is_empty(), id)
		if def.is_empty():
			continue
		assert_true(MapValidator.validate(def, data).is_empty(), id)
		shapes[JSON.stringify(def["terrain"])] = true
		var sc: Dictionary = def["scenario"]
		assert_eq(def["players"].size(), 3)
		assert_eq(sc["invasion_players"], [1])
		assert_eq(def["heroes"].map(func(h): return h["id"]), ["hero_watch", "hero_scout"])
		assert_eq(sc["protected_towns"].size(), 3 if case[0] == "defence_v2" else 1, id)
		for tid in sc["protected_towns"]:
			var town: Array = def["objects"].filter(func(o): return o["id"] == tid)
			assert_eq(int(town[0]["owner"]), 0, "%s protects its own towns" % id)
		assert_eq(sc["waves"].size(), 7)
		var entries := {}
		for w in sc["waves"]:
			entries[String(w["entry_name"])] = true
		assert_eq(entries.size(), 2, "%s invades by two roads" % id)
		assert_gt(int(def["width"]), 60, "%s is a wide map" % id)
		var names := {}
		for o in def["objects"]:
			if o["type"] == "town":
				assert_false(names.has(o["name"]), "%s town names are unique" % id)
				names[o["name"]] = true
		for guard in sc["siege"]["guards"].values():
			assert_lt(float(guard["start_win"]), ScenarioSiege.GUARD_WIN)
			assert_gt(float(guard["later_win"]), 0.5, "three weeks of growth can take each held site")
		assert_eq(_week_one(id), [] as Array[String], id)
		if case[0] == "endless_v2":
			assert_false(sc["endless"].is_empty())
	assert_eq(shapes.size(), 4)


func test_siege_is_deterministic() -> void:
	var a := data.load_map("scenario:survival_v2:11")
	var b := data.load_map("scenario:survival_v2:11")
	assert_eq(JSON.stringify(a), JSON.stringify(b))


func test_maze_has_wide_corridors_and_guarded_chokepoints() -> void:
	for seed_value in [1, 37, 404]:
		var def := ScenarioGenerator.generate(data, "labyrinth_v2", seed_value)
		assert_false(def.is_empty())
		if def.is_empty():
			continue
		assert_true(MapValidator.validate(def, data).is_empty())
		var map := AdventureMap.from_definition(def, data)
		var guarded := {}
		for o in def["objects"]:
			if o["type"] == "neutral_army":
				guarded[AdventureMap.object_pos(o)] = true
		var pass_ := func(p: Vector2i) -> bool: return map.in_bounds(p) and map.is_passable(p)
		for y in map.height:
			for x in map.width:
				var p := Vector2i(x, y)
				if not pass_.call(p):
					continue
				var narrow_h: bool = not pass_.call(p + Vector2i.UP) and not pass_.call(p + Vector2i.DOWN) and pass_.call(p + Vector2i.LEFT) and pass_.call(p + Vector2i.RIGHT)
				var narrow_v: bool = not pass_.call(p + Vector2i.LEFT) and not pass_.call(p + Vector2i.RIGHT) and pass_.call(p + Vector2i.UP) and pass_.call(p + Vector2i.DOWN)
				if narrow_h or narrow_v:
					assert_true(guarded.has(p), "seed %d: one-tile passage at %s must be guarded" % [seed_value, p])
		var budget: Dictionary = def["scenario"]["travel_budget"]
		assert_gt(int(budget["buffer_days"]), 4)
		var kinds: Array = def["objects"].filter(func(o): return o["type"] == "scenario_site").map(func(o): return o["kind"])
		assert_true(kinds.has("observatory"))
		assert_true(kinds.has("supplies"))
		assert_eq(_week_one(String(def["id"])), [] as Array[String])


func test_townless_runs_on_a_random_template() -> void:
	var def := data.load_map("scenario:townless_v1:random_m_2p_normal_normal_hub:3")
	assert_false(def.is_empty())
	assert_eq(def["scenario"]["recipe"]["template"], "random_m_2p_normal_normal_hub")


func test_long_watch_chapters_gate_their_goals() -> void:
	var maps: Array = data.campaigns["long_watch"]["chapters"].map(func(ch): return String(ch["map"]))
	assert_eq(maps, ["last_watch", "scenario:defence_v2:19", "scenario:labyrinth_v2:37"])
	for id in maps:
		assert_eq(_week_one(id), [] as Array[String], id)
