extends "res://tests/test_case.gd"
## Freeze tool, dev-mode editing of bundled maps, file format and previews.

const TEST_DATA := "user://map_pipeline_tests/data"
const TEST_LOCAL := "user://map_pipeline_tests/local"
const GEN_ID := "gen:twin_marches:7"

static var _frozen_cache := {}


func before_each() -> void:
	for directory in [TEST_DATA, TEST_LOCAL]:
		DirAccess.make_dir_recursive_absolute(directory)
		for file in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(directory.path_join(file))


func _roundtrip(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _copy_data_map(id: String) -> String:
	var text := FileAccess.get_file_as_string("res://data/maps/%s.json" % id)
	var file := FileAccess.open(TEST_DATA.path_join(id + ".json"), FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return text


func _dev_repository() -> MapRepository:
	var repository := MapRepository.new(data, TEST_LOCAL)
	repository.dev_mode = true
	repository.data_directory = TEST_DATA
	return repository


func _frozen(source: String, out_id: String) -> Dictionary:
	var key := source + "|" + out_id
	if not _frozen_cache.has(key):
		_frozen_cache[key] = MapFreezer.freeze(data, source, out_id)
	return _frozen_cache[key]


func test_format_writes_builder_files_byte_for_byte() -> void:
	# These maps are written by maplib.write; the editor must not reformat them.
	for id in ["burning_ford", "ashes_return", "into_the_embers", "red_sky_throne"]:
		var text := FileAccess.get_file_as_string("res://data/maps/%s.json" % id)
		assert_eq(MapFileFormat.encode(JSON.parse_string(text)), text, id)


func test_format_round_trips_every_bundled_map() -> void:
	var ids := MapRepository.new(data).data_map_ids()
	assert_gt(ids.size(), 20)
	for id in ids:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % id))
		assert_eq(JSON.parse_string(MapFileFormat.encode(parsed)), parsed, id)


func test_format_escapes_like_python_json() -> void:
	# Expected strings are what Python's json.dumps prints for the same values.
	assert_eq(MapFileFormat.value_text("The Last Watch \u2014 Survival"), "\"The Last Watch \\u2014 Survival\"")
	assert_eq(MapFileFormat.value_text("a\"b\\c\nd\te"), "\"a\\\"b\\\\c\\nd\\te\"")
	assert_eq(MapFileFormat.value_text(String.chr(0x1F525)), "\"\\ud83d\\udd25\"")
	assert_eq(MapFileFormat.value_text(String.chr(1)), "\"\\u0001\"")
	assert_eq(MapFileFormat.value_text({"pos": [3.0, 4], "ok": true, "x": null, "f": 0.75}),
		"{\"pos\": [3, 4], \"ok\": true, \"x\": null, \"f\": 0.75}")


func test_freeze_matches_the_generator_and_is_deterministic() -> void:
	var result := _frozen(GEN_ID, "frozen_twin")
	assert_eq(result["error"], "")
	if result["error"] != "":
		return
	var frozen: Dictionary = result["definition"]
	var again := MapFreezer.freeze(data, GEN_ID, "frozen_twin")
	assert_eq(MapFileFormat.encode(again["definition"]), MapFileFormat.encode(frozen))
	var generated := data.load_map(GEN_ID)
	assert_eq(frozen["id"], "frozen_twin")
	assert_eq(frozen["name"], generated["name"])
	assert_false(frozen.has("generator"), "Frozen maps are authored, without generator checks.")
	assert_eq(frozen["editor_source"]["map_id"], GEN_ID)
	assert_eq(frozen["editor_source"]["generator"], _roundtrip(generated["generator"]))
	for key in ["width", "height", "terrain", "roads", "decorations", "players", "heroes", "objects"]:
		assert_eq(frozen[key], _roundtrip(generated[key]), key)
	assert_eq(frozen.keys().slice(0, 6), ["_doc", "id", "name", "width", "height", "terrain"])
	assert_eq(frozen.keys()[-1], "editor_source")
	var problems := MapValidator.validate(frozen, data)
	assert_true(problems.is_empty(), str(problems))
	# Plays like the generated map: the same session start.
	var a := GameSession.new_game_from_definition(data, frozen, 5)
	assert_true(a != null)
	if a != null:
		assert_eq(a.state.heroes.size(), GameSession.new_game(data, GEN_ID, 5).state.heroes.size())


func test_freeze_keeps_scenario_data() -> void:
	var recipe := "survival_v1"
	var source := "%s%s:3" % [ScenarioGenerator.PREFIX, recipe]
	var result := MapFreezer.freeze(data, source, "frozen_survival", "Frozen survival")
	assert_eq(result["error"], "")
	if result["error"] != "":
		return
	var frozen: Dictionary = result["definition"]
	var generated := data.load_map(source)
	assert_eq(frozen["name"], "Frozen survival")
	assert_eq(frozen["scenario"], _roundtrip(generated["scenario"]))
	assert_eq(frozen["editor_source"], {"map_id": source})
	var problems := MapValidator.validate(frozen, data)
	assert_true(problems.is_empty(), str(problems))


func test_freeze_rejects_bad_output_ids() -> void:
	assert_ne(MapFreezer.freeze(data, GEN_ID, "Bad Id")["error"], "")
	assert_ne(MapFreezer.freeze(data, GEN_ID, "../escape")["error"], "")


func test_freeze_to_file_writes_the_builder_layout() -> void:
	assert_eq(MapFreezer.freeze_to_file(data, "burning_ford", "ford_copy", TEST_DATA), "")
	var text := FileAccess.get_file_as_string(TEST_DATA.path_join("ford_copy.json"))
	var parsed: Dictionary = JSON.parse_string(text)
	assert_eq(text, MapFileFormat.encode(parsed))
	assert_eq(parsed["id"], "ford_copy")
	assert_eq(parsed["objects"], _roundtrip(data.load_map("burning_ford")["objects"]))
	assert_false(FileAccess.file_exists(TEST_DATA.path_join("ford_copy.json.tmp")))


func test_dev_mode_is_off_unless_requested() -> void:
	assert_false(MapRepository.dev_mode_requested(), "Tests run without --maps-dev.")
	var repository := MapRepository.new(data, TEST_LOCAL)
	repository.data_directory = TEST_DATA
	_copy_data_map("burning_ford")
	assert_false(repository.dev_mode)
	assert_ne(repository.open_data_map("burning_ford")["error"], "")
	var document: MapDocument = repository.read_file(repository.data_path("burning_ford"))["document"]
	assert_false(document.is_data_map())
	assert_ne(repository.save_data_map(document), "")
	assert_ne(repository.freeze_to_document(GEN_ID, "x")["error"], "")


func test_untouched_save_keeps_bundled_file_byte_for_byte() -> void:
	var original := _copy_data_map("red_sky_throne")
	var repository := _dev_repository()
	var opened := repository.open_data_map("red_sky_throne")
	assert_eq(opened["error"], "")
	var document: MapDocument = opened["document"]
	assert_true(document.is_data_map())
	assert_false(document.read_only())
	assert_false(document.is_dirty())
	assert_eq(repository.save_data_map(document), "")
	assert_eq(FileAccess.get_file_as_string(repository.data_path("red_sky_throne")), original)


func test_scenario_objectives_quests_and_teams_survive_edits() -> void:
	var original: Dictionary = JSON.parse_string(_copy_data_map("last_watch"))
	var repository := _dev_repository()
	var document: MapDocument = repository.open_data_map("last_watch")["document"]
	assert_false(document.read_only(), "Dev mode edits scenario maps.")
	# Give a player a team too, then paint, rename and add an object.
	var players: Array = document.definition()["players"]
	players[-1]["team"] = 2
	assert_true(document.set_players(players))
	var cell := _passable_free_cell(document)
	assert_true(document.paint_terrain([cell], "snow"))
	assert_true(document.set_title("Last Watch, tuned"))
	var place := MapAuthoring.place(document, data, "resource", "gold", _passable_free_cell(document), -1)
	assert_eq(place["error"], "")
	assert_true(document.is_dirty())
	assert_eq(repository.save_data_map(document), "")
	var saved_text := FileAccess.get_file_as_string(repository.data_path("last_watch"))
	var saved: Dictionary = JSON.parse_string(saved_text)
	assert_eq(saved_text, MapFileFormat.encode(saved))
	assert_eq(saved["scenario"], original["scenario"])
	assert_eq(saved["scenario"]["objectives"], original["scenario"]["objectives"])
	assert_eq(saved["scenario"]["quests"], original["scenario"]["quests"])
	assert_eq(int(saved["players"][-1]["team"]), 2)
	assert_eq(saved["name"], "Last Watch, tuned")
	assert_eq(saved["objects"].size(), original["objects"].size() + 1)
	for object in original["objects"]:
		assert_true(object in saved["objects"], "kept " + str(object["id"]))
	assert_eq(saved.keys(), original.keys())
	# Reopening shows the same document; undoing everything restores the data.
	var reopened: MapDocument = repository.open_data_map("last_watch")["document"]
	assert_eq(reopened.definition(), saved)
	while document.can_undo():
		document.undo()
	assert_eq(_roundtrip(document.definition()), original)


func test_save_as_copies_a_bundled_map_as_bundled() -> void:
	_copy_data_map("burning_ford")
	var repository := _dev_repository()
	var document: MapDocument = repository.open_data_map("burning_ford")["document"]
	var copy := document.copy_as("burning_ford_b", "Burning Ford B")
	assert_true(copy.is_data_map())
	assert_eq(repository.save_data_map(copy), "")
	assert_eq(repository.data_map_ids(), ["burning_ford", "burning_ford_b"])
	assert_eq(repository.open_data_map("burning_ford_b")["document"].definition()["name"], "Burning Ford B")
	assert_eq(DirAccess.get_files_at(TEST_LOCAL).size(), 0, "Nothing goes to the local maps folder.")


func test_freeze_to_document_then_save() -> void:
	var repository := _dev_repository()
	var result := repository.freeze_to_document(GEN_ID, "frozen_twin")
	assert_eq(result["error"], "")
	if result["error"] != "":
		return
	var document: MapDocument = result["document"]
	assert_true(document.is_data_map())
	assert_true(document.is_dirty(), "A fresh freeze is unsaved.")
	assert_eq(repository.save_data_map(document), "")
	assert_eq(FileAccess.get_file_as_string(repository.data_path("frozen_twin")),
		MapFileFormat.encode(_frozen(GEN_ID, "frozen_twin")["definition"]))


func test_identity_mismatch_is_refused() -> void:
	var text := _copy_data_map("burning_ford")
	var file := FileAccess.open(TEST_DATA.path_join("other.json"), FileAccess.WRITE)
	file.store_string(text)
	file.close()
	assert_ne(_dev_repository().open_data_map("other")["error"], "")


func test_preview_draws_terrain_towns_and_heroes() -> void:
	var definition := data.load_map("burning_ford")
	var image := MapPreview.render(definition, data, 4)
	assert_eq(image.get_size(), Vector2i(int(definition["width"]) * 4, int(definition["height"]) * 4))
	var town: Dictionary = definition["objects"].filter(func(o): return o["type"] == "town")[0]
	var pos := Vector2i(int(town["pos"][0]), int(town["pos"][1])) * 4 + Vector2i(2, 2)
	var expected := Color(MapPreview.NEUTRAL)
	for player in definition["players"]:
		if int(player["id"]) == int(town.get("owner", -1)):
			expected = Color(player["color"])
	assert_eq(image.get_pixelv(pos).to_html(false), expected.to_html(false), "town marker colour")
	var corner := Color(data.terrain(data.terrain_by_char[String(definition["terrain"][0][0])])["color"])
	assert_eq(image.get_pixel(0, 0).to_html(false), corner.to_html(false), "terrain colour")
	var path := "user://map_pipeline_tests/preview.png"
	assert_eq(MapPreview.save_png(definition, data, path), "")
	assert_true(FileAccess.file_exists(path))
	assert_gt(MapPreview.render(_frozen(GEN_ID, "frozen_twin")["definition"], data).get_width(), 0)


func _passable_free_cell(document: MapDocument) -> Vector2i:
	var definition := document.definition()
	var map := AdventureMap.from_definition(definition, data)
	var used := {}
	for entity in definition["objects"] + definition["heroes"]:
		used[AdventureMap.object_pos(entity)] = true
	for y in range(2, map.height - 2):
		for x in range(2, map.width - 2):
			var cell := Vector2i(x, y)
			if map.is_passable(cell) and not used.has(cell) and not map.has_road(cell) \
					and String(definition["terrain"][y][x]) == ".":
				return cell
	return Vector2i(-1, -1)


func test_editor_dev_mode_screen() -> void:
	# The screen needs a SceneTree; run the bounded smoke check in its own instance.
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/editor_dev_mode_check.gd"], output, true)
	var log := "\n".join(output)
	assert_eq(code, 0, log)
	assert_true(log.contains("Editor dev mode checks: passed"), log)
	assert_false(log.contains("SCRIPT ERROR"), log)
