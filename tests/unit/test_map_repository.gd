extends "res://tests/test_case.gd"

const TEST_DIRECTORY := "user://editor_repository_tests"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIRECTORY)
	for file in DirAccess.get_files_at(TEST_DIRECTORY):
		DirAccess.remove_absolute(TEST_DIRECTORY.path_join(file))


func _blank() -> MapDocument:
	return MapDocument.blank(data, "custom:test", "Test", 4, 4)


func test_local_draft_round_trip_and_replace_existing_file() -> void:
	var repository := MapRepository.new(data, TEST_DIRECTORY)
	var document := _blank()
	assert_eq(repository.save(document), "")
	assert_false(document.is_dirty())
	document.paint_terrain([Vector2i.ZERO], "snow")
	assert_eq(repository.save(document), "")
	var result := repository.load_local("test")
	assert_eq(result["error"], "")
	if result.has("document"):
		# JSON has one number type; Godot decodes even integer literals as floats.
		assert_eq(result["document"].definition(), JSON.parse_string(JSON.stringify(document.definition())))
		assert_false(result["document"].is_dirty())
	assert_false(FileAccess.file_exists(TEST_DIRECTORY.path_join("test.json.tmp")))
	assert_eq(repository.list_local().size(), 1)


func test_invalid_file_does_not_hide_good_maps() -> void:
	var repository := MapRepository.new(data, TEST_DIRECTORY)
	repository.save(_blank())
	var file := FileAccess.open(TEST_DIRECTORY.path_join("broken.json"), FileAccess.WRITE)
	file.store_string("{invalid JSON")
	file.close()
	var results := repository.list_local()
	assert_eq(results.size(), 2)
	assert_true(results[0]["error"].contains("Invalid JSON"))
	assert_eq(results[1]["error"], "")


func test_failed_save_preserves_dirty_state_and_previous_file() -> void:
	var repository := MapRepository.new(data, TEST_DIRECTORY)
	var document := _blank()
	repository.save(document)
	var before: Dictionary = repository.load_local("test")["document"].definition()
	document.set_title("Unsaved")
	# A directory occupying the temporary filename makes the write fail reliably.
	DirAccess.make_dir_absolute(TEST_DIRECTORY.path_join("test.json.tmp"))
	assert_ne(repository.save(document), "")
	assert_true(document.is_dirty())
	assert_eq(repository.load_local("test")["document"].definition(), before)
	DirAccess.remove_absolute(TEST_DIRECTORY.path_join("test.json.tmp"))


func test_path_traversal_and_bundled_ids_cannot_be_saved() -> void:
	var repository := MapRepository.new(data, TEST_DIRECTORY)
	for id in ["../outside", "/absolute", "", "test.json", "gen:template:4", "Uppercase", "a/b"]:
		assert_false(MapRepository.valid_local_id(id))
		assert_ne(repository.load_local(id)["error"], "")
	var document := MapDocument.from_definition(data.load_map("ember_ford"), data)
	assert_ne(repository.save(document), "")
	assert_eq(repository.list_local().size(), 0)


func test_cannot_save_unfinished_action() -> void:
	var document := _blank()
	document.begin_action("Painting")
	document.paint_terrain([Vector2i.ZERO], "forest")
	var repository := MapRepository.new(data, TEST_DIRECTORY)
	assert_ne(repository.save(document), "")
	assert_true(document.is_dirty())
	assert_eq(repository.list_local().size(), 0)


func test_imported_scenario_round_trip_is_read_only() -> void:
	var repository := MapRepository.new(data, TEST_DIRECTORY)
	var result := repository.read_file("res://data/maps/last_watch.json")
	assert_eq(result["error"], "")
	if result.has("document"):
		assert_true(result["document"].read_only())
		assert_ne(repository.save(result["document"]), "")
		assert_eq(result["document"].definition(), data.load_map("last_watch"))


func test_mismatched_file_identity_is_not_discovered_as_another_map() -> void:
	var repository := MapRepository.new(data, TEST_DIRECTORY)
	repository.save(_blank())
	DirAccess.rename_absolute(TEST_DIRECTORY.path_join("test.json"), TEST_DIRECTORY.path_join("other.json"))
	assert_ne(repository.load_local("other")["error"], "")
