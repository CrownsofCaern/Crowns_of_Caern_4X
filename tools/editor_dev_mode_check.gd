extends SceneTree
## Headless smoke test of the editor's dev mode: open a bundled map in place,
## edit, save it back, Save As a new bundled map, and freeze a generated map.
## Works on a temporary copy of data/maps, never on the real files.
##   godot --headless --path . --script res://tools/editor_dev_mode_check.gd

const TEST_DATA := "user://editor_dev_mode_check/data"
const TEST_LOCAL := "user://editor_dev_mode_check/local"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, text: String) -> void:
	if not value:
		_failed = true
		push_error(text)


func _run() -> void:
	for directory in [TEST_DATA, TEST_LOCAL]:
		DirAccess.make_dir_recursive_absolute(directory)
		for file in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(directory.path_join(file))
	for id in ["last_watch", "burning_ford"]:
		var file := FileAccess.open(TEST_DATA.path_join(id + ".json"), FileAccess.WRITE)
		file.store_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % id))
		file.close()
	var data := GameData.get_default()
	var repository := MapRepository.new(data, TEST_LOCAL)
	repository.dev_mode = true
	repository.data_directory = TEST_DATA
	root.size = Vector2i(1280, 800)
	var editor := MapEditorScreen.new()
	root.add_child(editor)
	editor.build(data, repository)
	editor.open()
	await process_frame
	# Open the scenario map in place.
	editor._show_open()
	var picked := false
	for i in editor._open_pick.item_count:
		if editor._open_pick.get_item_metadata(i).get("data_id", "") == "last_watch":
			editor._open_pick.select(i)
			picked = true
	_check(picked, "Dev mode lists bundled maps.")
	editor._open_selected()
	await process_frame
	var document := editor.document
	_check(document.is_data_map() and not document.read_only(), "Scenario map opens editable in place.")
	_check(str(document.definition()["id"]) == "last_watch", "Opened in place, not as a copy.")
	_check(not editor._save.disabled and not editor._players_button.disabled, "Save and Players are enabled.")
	_check(editor._read_only.text.contains("data/maps/last_watch.json"), "Dev mode banner names the file.")
	var scenario: Dictionary = document.definition()["scenario"]
	editor._rename_map("Last Watch (dev)")
	editor.save_current()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_DATA.path_join("last_watch.json")))
	_check(saved["name"] == "Last Watch (dev)", "Save writes the bundled file.")
	_check(saved["scenario"] == scenario, "Save keeps the scenario.")
	_check(not document.is_dirty(), "Saved document is clean.")
	editor._check_placement()
	_check(editor._message.dialog_text == "Valid bundled map.", "Validate uses the full map validator: " + editor._message.dialog_text)
	editor._message.hide()
	# Save As a second bundled map.
	editor._show_save_as()
	_check(editor._save_id.text == "last_watch_copy", "Save As suggests a bundled id.")
	editor._save_copy()
	_check(FileAccess.file_exists(TEST_DATA.path_join("last_watch_copy.json")), "Save As writes a bundled copy.")
	_check(str(editor.document.definition()["id"]) == "last_watch_copy", "Editor switches to the copy.")
	# Freeze a generated map from the Open dialog.
	editor._show_open()
	editor._freeze_source.text = "gen:twin_marches:7"
	editor._freeze_id.text = "frozen_twin"
	editor._open_selected()
	_check(editor.document.is_data_map() and editor.document.is_dirty(), "Freeze opens an unsaved bundled map.")
	editor.save_current()
	_check(FileAccess.file_exists(TEST_DATA.path_join("frozen_twin.json")), "Saving a freeze writes the file.")
	_check(DirAccess.get_files_at(TEST_LOCAL).is_empty(), "Dev mode does not write local maps.")
	editor.queue_free()
	await process_frame
	print("Editor dev mode checks: " + ("FAILED" if _failed else "passed"))
	GameData._default = null
	quit(1 if _failed else 0)
