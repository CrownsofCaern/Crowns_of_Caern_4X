extends "res://tests/test_case.gd"

var custom_data: GameData
var directory := ""


func before_each() -> void:
	custom_data = GameData.new()
	custom_data.load_all(GameData.DATA_DIR)
	directory = "user://custom_map_tests_%d" % OS.get_process_id()
	custom_data.custom_maps_directory = directory
	DirAccess.make_dir_recursive_absolute(directory)
	_clean()


func _clean() -> void:
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))


func _definition() -> Dictionary:
	var document := MapDocument.blank(custom_data, "custom:launch", "Launch map", 10, 10)
	document.set_players([{"id": 0, "name": "My realm", "faction": "forge", "is_human": true,
		"color": "#ab1234", "difficulty": "normal", "team": 0}])
	MapAuthoring.place(document, custom_data, "town", "concord", Vector2i(2, 2), 0)
	MapAuthoring.place(document, custom_data, "hero", "knight", Vector2i(2, 2), 0)
	var definition := document.definition()
	definition["heroes"][0]["army"] = [["pike_militia", 7]]
	return definition


func test_complete_authored_map_passes_without_mutating_definition() -> void:
	var definition := _definition()
	var before := definition.duplicate(true)
	assert_eq(MapPlayability.errors(definition, custom_data), [] as Array[String])
	assert_eq(definition, before)


func test_incomplete_drafts_save_but_are_not_discovered_as_playable() -> void:
	var document := MapDocument.blank(custom_data, "custom:draft", "Draft", 10, 10)
	var repository := MapRepository.new(custom_data)
	assert_eq(repository.save(document), "")
	assert_gt(MapPlayability.errors(document.definition(), custom_data).size(), 0)
	assert_eq(repository.playable_maps().size(), 0)
	assert_true(repository.load_local("draft").has("document"))
	_clean()


func test_safe_validation_handles_bad_shapes_and_nested_runtime_fields() -> void:
	for patch in [{"width": 0}, {"players": []}, {"roads": [{"from": [0, 0], "to": [3, 2]}]},
		{"heroes": [false]}, {"generator": {}}, {"scenario": {}}]:
		var definition := _definition()
		definition.merge(patch, true)
		assert_gt(MapPlayability.errors(definition, custom_data).size(), 0, str(patch))
	for patch in [{"army": false}, {"army": [["pike_militia", 0]]}, {"owner": 4}, {"army": []}]:
		var definition := _definition()
		definition["heroes"][0].merge(patch, true)
		assert_gt(MapPlayability.errors(definition, custom_data).size(), 0, str(patch))
	for patch in [{"garrison": false}, {"available": []}, {"available": {"pike_militia": []}}, {"last_build_day": []}, {"stock": [false]}, {"stock": [{"kind": "map", "remaining": []}]}, {"visitors": [false]}]:
		var definition := _definition()
		definition["objects"][0].merge(patch, true)
		assert_gt(MapPlayability.errors(definition, custom_data).size(), 0, str(patch))


func test_players_need_human_starts_distinct_colours_and_opposing_sides() -> void:
	var definition := _definition()
	definition["players"][0]["is_human"] = false
	assert_gt(MapPlayability.errors(definition, custom_data).size(), 0)
	definition = _definition()
	definition["players"].append(definition["players"][0].duplicate(true))
	definition["players"][1]["id"] = 1
	assert_gt(MapPlayability.errors(definition, custom_data).size(), 0, "duplicate colours and missing starts")
	definition = _definition()
	definition["objects"] = []
	assert_gt(MapPlayability.errors(definition, custom_data).size(), 0, "no starting town")


func test_shared_validator_rejects_unreachable_content() -> void:
	var definition := _definition()
	definition["objects"].append({"id": "treasure", "type": "resource", "resource": "gold", "amount": 100, "pos": [8, 8]})
	for y in 10:
		definition["terrain"][y] = ".....^...."
	var errors := MapPlayability.errors(definition, custom_data)
	assert_gt(errors.size(), 0)
	assert_true("\n".join(errors).contains("unreachable"))


func test_discovery_and_loading_skip_bad_files_and_unsafe_ids() -> void:
	var repository := MapRepository.new(custom_data)
	assert_eq(repository.save(MapDocument.from_definition(_definition(), custom_data)), "")
	var file := FileAccess.open(directory.path_join("broken.json"), FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var maps := GameSetup.available_maps(custom_data).filter(func(entry): return entry.get("custom", false))
	assert_eq(maps.size(), 1)
	assert_eq(maps[0]["id"], "custom:launch")
	assert_eq(maps[0]["mode"], "conquest")
	assert_false(custom_data.load_map("custom:launch").is_empty())
	assert_true(custom_data.load_map("custom:../outside").is_empty())
	assert_true(custom_data.load_map("custom:missing").is_empty())
	assert_true(GameSession.new_game(custom_data, "custom:missing", 1) == null)
	_clean()


func test_factory_preserves_authored_heroes_classes_armies_and_input() -> void:
	var definition := _definition()
	var before := definition.duplicate(true)
	var session := GameSession.new_game_from_definition(custom_data, definition, 42)
	assert_true(session != null)
	assert_eq(session.state.heroes.size(), 1)
	var hero: Hero = session.state.heroes.values()[0]
	assert_eq(hero.class_id, "knight", "foreign authored class survives")
	assert_eq(hero.army.total_creatures(), 7)
	assert_eq(hero.army.slots[0]["creature"], "pike_militia")
	assert_eq(definition, before)
	session.state.map.terrain[0] = "water"
	assert_eq(definition, before)


func test_custom_default_setup_keeps_authored_starts_and_names() -> void:
	var repository := MapRepository.new(custom_data)
	repository.save(MapDocument.from_definition(_definition(), custom_data))
	var entry: Dictionary = GameSetup.available_maps(custom_data).filter(func(map): return map.get("custom", false))[0]
	var setup := GameSetup.default_setup(entry)
	assert_false(setup["standard_start"])
	var session := GameSession.new_game(custom_data, entry["id"], 1, setup)
	assert_eq(session.state.heroes.size(), 1, "Forge's normal hero count must not replace authored heroes")
	assert_eq(session.state.heroes.values()[0].class_id, "knight")
	assert_eq(session.state.heroes.values()[0].army.total_creatures(), 7)
	assert_eq(session.state.players[0]["name"], "My realm")
	_clean()


func test_explicit_empty_custom_garrison_is_preserved_but_omitted_uses_defaults() -> void:
	var definition := _definition()
	var session := GameSession.new_game_from_definition(custom_data, definition, 1)
	assert_true(Town.garrison(session.state.map.objects["town_1"]).is_empty())
	definition["objects"][0].erase("garrison")
	session = GameSession.new_game_from_definition(custom_data, definition, 1)
	assert_false(Town.garrison(session.state.map.objects["town_1"]).is_empty())


func test_saved_custom_game_loads_after_original_map_is_deleted() -> void:
	var repository := MapRepository.new(custom_data)
	repository.save(MapDocument.from_definition(_definition(), custom_data))
	var session := GameSession.new_game(custom_data, "custom:launch", 42)
	var before := session.state.to_dict()
	assert_eq(SaveSlots.save(session, "1", directory), OK)
	DirAccess.remove_absolute(directory.path_join("launch.json"))
	var loaded := SaveSlots.load_slot(custom_data, "1", directory)
	assert_true(loaded != null)
	if loaded != null:
		assert_eq(JSON.parse_string(JSON.stringify(loaded.state.to_dict())), JSON.parse_string(JSON.stringify(before)))
	_clean()


func test_scenario_factory_keeps_existing_scenario_rules() -> void:
	var definition := custom_data.load_map("last_watch")
	var before := definition.duplicate(true)
	var session := GameSession.new_game_from_definition(custom_data, definition, 7)
	assert_true(ScenarioRules.active(session.state))
	assert_eq(ScenarioRules.definition(session.state), definition["scenario"])
	assert_eq(definition, before)
