extends "res://tests/test_case.gd"
## Scene/input checks need frames, while the unit runner is synchronous. Run the
## same bounded headless smoke used for visual QA in a separate Godot instance.


func test_editor_scene_input_files_and_game_isolation() -> void:
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/editor_ui_check.gd"], output, true)
	var log := "\n".join(output)
	assert_eq(code, 0, log)
	assert_true(log.contains("Editor UI smoke checks: passed"), log)
	assert_false(log.contains("SCRIPT ERROR") or log.contains("ERROR:"), log)
