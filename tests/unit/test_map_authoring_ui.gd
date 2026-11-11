extends "res://tests/test_case.gd"


func test_entity_palette_properties_players_and_undo_in_scene() -> void:
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/editor_entities_check.gd"], output, true)
	var log := "\n".join(output)
	assert_eq(code, 0, log)
	assert_true(log.contains("Entity editor smoke checks: passed"), log)
	assert_false(log.contains("SCRIPT ERROR") or log.contains("ERROR:"), log)
