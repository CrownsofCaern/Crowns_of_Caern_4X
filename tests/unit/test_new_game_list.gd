extends "res://tests/test_case.gd"
## The new-game map list (GameSetup.available_maps): random entries per mode,
## curated seeds (random_maps.curated in map_templates.json) and custom maps;
## no story maps, hand-written templates or legacy recipes.

## Long-running tests (whole AI games, balance sweeps, many generated maps):
## they run only with ./run_tests.sh --slow.
const SLOW := ["test_curated_conquest_maps_generate"]


func _curated() -> Array:
	return RandomMapTemplate.settings(data.map_templates).get("curated", [])


func test_list_has_no_story_maps_templates_or_legacy_recipes() -> void:
	var story := {}
	for f in DirAccess.get_files_at(GameData.DATA_DIR + "/maps"):
		story[String(f).get_basename()] = true
	var templates: Dictionary = data.map_templates.get("templates", {})
	var seen := {}
	for mode in GameSetup.MODES:
		var maps := GameSetup.available_maps(data, mode)
		assert_false(maps.is_empty(), "mode %s offers maps" % mode)
		assert_true(bool(maps[0].get("random", false)), "mode %s starts with its random entry" % mode)
		for m in maps:
			assert_eq(String(m["mode"]), mode)
			assert_false(story.has(String(m["id"])), "story map listed: %s" % m["id"])
			assert_false(templates.has(String(m.get("template", ""))), "hand-written template listed: %s" % m["id"])
			if m.has("recipe"):
				var r := ScenarioGenerator.recipe_of(data, String(m["recipe"]))
				assert_false(bool(r.get("legacy", false)), "legacy recipe listed: %s" % m["recipe"])
				assert_eq(String(r["mode"]), mode)
			assert_false(seen.has(String(m["id"])), "duplicate entry %s" % m["id"])
			seen[String(m["id"])] = true
			var id := GameSetup.map_id_for(m, 5)
			assert_false(story.has(id))
	assert_eq(GameSetup.available_maps(data, "all").size(), seen.size())
	# The old ids stay loadable.
	assert_false(data.load_map("mournfield").is_empty())
	assert_false(data.load_map("gen:crossing:3").is_empty())


func test_curated_entries_validate_and_conquest_ids_load() -> void:
	assert_eq(GameSetup.validate_curated(data, _curated()), [] as Array[String])
	var per_family := {}
	var per_mode := {}
	for c in _curated():
		var recipe := String(c.get("recipe", ""))
		var mode := "conquest" if recipe == "" else String(ScenarioGenerator.recipe_of(data, recipe)["mode"])
		per_mode[mode] = int(per_mode.get(mode, 0)) + 1
		if recipe == "":
			var family := String(RandomMapTemplate.parse(data.map_templates, String(c["template"]))["family"])
			per_family[family] = int(per_family.get(family, 0)) + 1
	for family in LayoutFamilies.ids(data.map_templates):
		assert_true(int(per_family.get(family, 0)) >= 3 and int(per_family.get(family, 0)) <= 6, "3-6 curated seeds for %s" % family)
	for mode in ScenarioGenerator.MODES:
		assert_eq(int(per_mode.get(mode, 0)), 2, "two curated %s missions" % mode)
	var curated := GameSetup.curated_entries(data, "conquest")
	assert_eq(curated.size(), int(per_mode["conquest"]))
	for entry in curated:
		var id := GameSetup.map_id_for(entry, 999)
		assert_eq(id, "gen:%s:%d" % [entry["template"], int(entry["map_seed"])], "a curated map ignores the seed box")


## Every curated seed really generates (a map each: slow).
func test_curated_conquest_maps_generate() -> void:
	for entry in GameSetup.curated_entries(data, "conquest"):
		var id := GameSetup.map_id_for(entry, 999)
		var def := data.load_map(id)
		assert_false(def.is_empty(), "%s generates" % id)
		if not def.is_empty():
			assert_eq(def["players"].size(), entry["slots"].size())


func test_curated_scenario_entries_build_template_ids() -> void:
	for mode in ScenarioGenerator.MODES:
		for entry in GameSetup.curated_entries(data, mode):
			var id := GameSetup.map_id_for(entry, 999)
			var parsed := ScenarioGenerator.parse_id(id)
			assert_eq(String(parsed["recipe"]), ScenarioGenerator.current_recipe(data, mode))
			assert_eq(int(parsed["seed"]), int(entry["map_seed"]))
			assert_eq(String(parsed["template"]), String(entry["template"]))
			assert_eq(entry["slots"].size(), ScenarioGenerator.players(data, String(entry["recipe"]), String(entry["template"])).size())
	var maze: Dictionary = GameSetup.curated_entries(data, "labyrinth")[0]
	assert_false(data.load_map(GameSetup.map_id_for(maze, 0)).is_empty(), "a curated expedition generates")


func test_random_entry_with_family_and_teams() -> void:
	var entry := GameSetup.random_entry(data, {"size": "m", "players": 4, "monsters": "normal", "treasure": "normal", "family": "hub", "teams": 2})
	assert_eq(entry["template"], "random_m_4p_normal_normal_hub")
	assert_eq(GameSetup.map_id_for(entry, 8), "gen:random_m_4p_normal_normal_hub:8")
	assert_eq(entry["slots"].map(func(s): return int(s["team"])), [1, 1, 2, 2])
	var setup := GameSetup.default_setup(entry)
	assert_eq(setup["players"].map(func(p): return int(p["team"])), [1, 1, 2, 2], "the teams pre-fill the slot pickers")
	entry = GameSetup.random_entry(data, {"size": "l", "players": 6, "family": "ring", "teams": 3})
	assert_eq(entry["slots"].map(func(s): return int(s["team"])), [1, 1, 2, 2, 3, 3])
	# A family or team split the player count cannot use falls back.
	entry = GameSetup.random_entry(data, {"size": "m", "players": 3, "family": "diagonal", "teams": 2})
	assert_eq(entry["template"], "random_m_3p_normal_normal")
	assert_eq(int(entry["options"]["teams"]), 0)
	assert_true(entry["slots"].all(func(s): return int(s["team"]) == 0))
	assert_eq(GameSetup.team_choices(2), [0])
	assert_eq(GameSetup.team_choices(4), [0, 2])
	assert_eq(GameSetup.team_choices(5), [0])
	assert_eq(GameSetup.team_choices(6), [0, 2, 3])
	var s := GameSession.new_game(data, GameSetup.map_id_for(GameSetup.random_entry(data, {"size": "s", "players": 4, "family": "ring", "teams": 2}), 3), 3,
		GameSetup.default_setup(GameSetup.random_entry(data, {"size": "s", "players": 4, "family": "ring", "teams": 2})))
	assert_eq(s.state.team_of(0), s.state.team_of(1))
	assert_true(s.state.team_of(0) != s.state.team_of(2))


func test_scenario_random_entries_use_the_chosen_template() -> void:
	for mode in ["survival", "defence", "endless"]:
		var entry := GameSetup.random_entry(data, {"mode": mode, "size": "l", "players": 3, "monsters": "strong", "treasure": "rich", "family": "ring", "teams": 2})
		var recipe := ScenarioGenerator.current_recipe(data, mode)
		assert_eq(entry["recipe"], recipe)
		assert_eq(GameSetup.map_id_for(entry, 5), "scenario:%s:random_l_3p_strong_rich_ring:5" % recipe)
		assert_eq(int(entry["options"]["teams"]), 0, "missions have fixed sides")
		assert_eq(entry["slots"].size(), 3, "defender, invaders and potential ally")
		entry = GameSetup.random_entry(data, {"mode": mode, "size": "xl", "players": 6})
		assert_eq(int(entry["options"]["players"]), GameSetup.SCENARIO_MAX_PLAYERS)
	var maze := GameSetup.random_entry(data, {"mode": "labyrinth", "size": "l", "players": 3})
	assert_eq(maze["template"], "")
	assert_eq(GameSetup.map_id_for(maze, 7), "scenario:labyrinth_v2:7")
	assert_eq(maze["slots"].size(), 1)
	assert_false(data.load_map(GameSetup.map_id_for(maze, 7)).is_empty())


func test_townless_random_entry_generates_and_starts() -> void:
	var entry := GameSetup.random_entry(data, {"mode": "townless", "size": "m", "players": 2, "family": "diagonal"})
	var id := GameSetup.map_id_for(entry, 6)
	assert_eq(id, "scenario:%s:random_m_2p_normal_normal_diagonal:6" % ScenarioGenerator.current_recipe(data, "townless"))
	var def := data.load_map(id)
	assert_false(def.is_empty())
	if def.is_empty():
		return
	assert_eq(def["players"].size(), entry["slots"].size())
	var setup := GameSetup.default_setup(entry)
	setup["standard_start"] = true
	assert_eq(GameSetup.validate(def, setup, data), [] as Array[String])
	var s := GameSession.new_game(data, id, 6, setup)
	assert_true(s.towns_of(0).is_empty(), "the townless start has no town")
	assert_eq(s.state.heroes_of(0).size(), 1)


func test_validation_rejects_bad_curated_entries() -> void:
	var good: Dictionary = _curated()[0]
	var bad := [
		{"id": "a", "name": "A", "template": "random_m_2p_normal_normal_ring", "seed": 3},
		{"id": "a", "name": "Again", "template": "random_m_2p_normal_normal_ring", "seed": 4},
		{"id": "b", "name": "", "template": "random_m_2p_normal_normal_ring", "seed": 4},
		{"id": "c", "name": "C", "template": "random_m_2p_normal_normal", "seed": 4},
		{"id": "d", "name": "D", "template": "random_m_4p_normal_normal_lanes", "seed": 4},
		{"id": "e", "name": "E", "template": "random_m_2p_normal_normal_ring", "seed": 0},
		{"id": "f", "name": "F", "recipe": "survival_v1", "template": "random_m_2p_normal_normal_ring", "seed": 4},
		{"id": "g", "name": "G", "recipe": "labyrinth_v2", "template": "random_m_2p_normal_normal_ring", "seed": 4},
		{"id": "h", "name": "H", "recipe": "survival_v2", "template": "random_l_6p_normal_normal_ring", "seed": 4},
		{"id": "i", "name": "I", "recipe": "no_such_recipe", "seed": 4},
		{"id": "j", "name": "J", "template": "twin_marches", "seed": 4}]
	var errors := GameSetup.validate_curated(data, bad)
	for want in ["duplicate id", "b: missing name", "template random_m_2p_normal_normal must", "template random_m_4p_normal_normal_lanes must",
			"e: seed must be", "recipe survival_v1 is legacy", "recipe labyrinth_v2 takes no template", "at most 4 players",
			"unknown recipe no_such_recipe", "template twin_marches must"]:
		assert_true(errors.any(func(e): return String(e).contains(want)), "reports: " + want)
	assert_eq(GameSetup.validate_curated(data, [good]), [] as Array[String])
	assert_false(GameSetup.validate_curated(data, {"a": 1}).is_empty())
