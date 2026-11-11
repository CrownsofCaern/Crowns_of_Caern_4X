extends "res://tests/test_case.gd"


func test_playtest_return_saves_and_custom_launch_in_scene() -> void:
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/editor_playtest_check.gd"], output, true)
	var log := "\n".join(output)
	assert_eq(code, 0, log)
	assert_true(log.contains("Editor playtest checks: passed"), log)
	assert_false(log.contains("SCRIPT ERROR") or log.contains("ERROR:"), log)
