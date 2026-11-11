extends SceneTree
## Launch/return isolation, temporary save slots and the real custom-map menu.
## godot --path . --script res://tools/editor_playtest_check.gd -- /tmp/reignem-playtest

var _failed := false
var _output := "/tmp/reignem-playtest"


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error(message)


func _frames(count: int = 4) -> void:
	for i in count:
		await process_frame


func _shot(filename: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(_output.path_join(filename)) == OK, "Cannot save " + filename)


func _snapshot(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


func _files(directory: String) -> Dictionary:
	var hashes := {}
	if DirAccess.dir_exists_absolute(directory):
		for file in DirAccess.get_files_at(directory):
			hashes[file] = FileAccess.get_file_as_string(directory.path_join(file)).sha256_text()
	return hashes


func _choose_custom(menu: MainMenu, id: String) -> void:
	menu._show_setup()
	for i in menu._maps.size():
		if menu._maps[i]["id"] == id:
			menu._map_pick.select(i)
			menu._fill_slots()
			return
	_check(false, "Custom map is missing from New Game.")


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Playtest scene check timed out."); quit(1))
	if not OS.get_cmdline_user_args().is_empty():
		_output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_output)
	var test_root := "user://editor_launch_smoke_%d" % OS.get_process_id()
	var maps_directory := test_root.path_join("maps")
	var saves_directory := test_root.path_join("ordinary_saves")
	var normal_saves := _files(SaveSlots.DEFAULT_DIR)
	var normal_campaigns := _files(Campaign.SAVE_DIR)
	var data := GameData.get_default()
	var old_maps_directory := data.custom_maps_directory
	data.custom_maps_directory = maps_directory
	root.size = Vector2i(1280, 800)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_directory = saves_directory
	root.add_child(main)
	await _frames()
	main.start_new_game("ember_ford", 1, {})
	var parent_session: GameSession = main.session
	var parent_before := _snapshot(parent_session.state.to_dict())
	main._open_menu()
	main._open_editor()
	await _frames()
	var editor: MapEditorScreen = main.map_editor
	# Blank drafts get actionable validation instead of a half-initialized game.
	editor.start_playtest()
	_check(editor._playtest_controller == null and editor._message.visible, "Invalid drafts must not start a playtest.")
	editor._message.hide()
	var document := MapDocument.blank(data, "custom:playtest-demo", "The authored crossing", 16, 12)
	document.set_players([{"id": 0, "name": "Cinderwatch", "faction": "forge",
		"is_human": true, "color": "#13579a", "difficulty": "normal", "team": 0}])
	MapAuthoring.place(document, data, "town", "concord", Vector2i(2, 2), 0)
	var placed := MapAuthoring.place(document, data, "hero", "knight", Vector2i(2, 2), 0)
	var hero_id: String = placed["id"]
	MapAuthoring.place(document, data, "town", "ashen", Vector2i(12, 9), -1)
	var hero := document.entity(hero_id, true)
	hero["army"] = [["pike_militia", 12]]
	_check(MapAuthoring.store(document, data, hero, true, hero_id) == "", "Fixture hero should be valid.")
	_check(MapPlayability.errors(document.definition(), data).is_empty(), "Fixture must be playable.")
	editor.bind_document(document)
	editor.canvas.zoom_level = 2
	editor.canvas.focus = Vector2(400, 300)
	editor.canvas.selected = Vector2i(2, 2)
	editor.canvas._position_map()
	editor._playtest_seed.value = 137
	var draft_before := document.definition()
	var undo_cursor := document._cursor
	var focus_before := editor.canvas.focus
	editor._playtest_button.pressed.emit()
	await _frames()
	var controller: Node = editor._playtest_controller
	_check(controller != null and not editor.visible, "Playtest should open a separate game controller.")
	if controller == null:
		quit(1)
		return
	var initial := _snapshot(controller.session.state.to_dict())
	var temporary: String = controller.save_directory
	_check(temporary != SaveSlots.DEFAULT_DIR and FileAccess.file_exists(SaveSlots.path_for("auto", temporary)), "Playtest autosave must use its own folder.")
	_check(controller.session.state.heroes.size() == 1 and controller.session.hero(hero_id).class_id == "knight", "Playtest should keep the authored foreign hero class and count.")
	_check(controller.session.hero(hero_id).army.total_creatures() == 12, "Playtest should keep authored armies.")
	await controller._execute_move(Vector2i(3, 2))
	await _frames()
	_check(controller.session.hero(hero_id).pos == Vector2i(3, 2), "Playtest should run normal movement commands.")
	_check(document.definition() == draft_before, "Gameplay must not mutate the source document.")
	controller._on_slot_chosen("save", "1")
	_check(FileAccess.file_exists(SaveSlots.path_for("1", temporary)), "Manual playtest saves must also be isolated.")
	controller._on_slot_chosen("load", "1")
	await _frames()
	_check(controller.session.hero(hero_id).pos == Vector2i(3, 2), "Playtest must load its isolated slot.")
	await _shot("01-playtest.png")
	controller._open_menu()
	var visible_buttons: Array[String] = []
	for button in controller.menu._home.get_children():
		if button is Button and button.visible:
			visible_buttons.append(button.text)
	_check(visible_buttons.has("Return to Editor") and not visible_buttons.has("Campaign") and not visible_buttons.has("New Game") and not visible_buttons.has("Quit"), "Playtest menu must offer return without campaign/new-game escape paths.")
	controller.menu._return_editor_btn.pressed.emit()
	await _frames()
	_check(editor.visible and editor._playtest_controller == null, "Return should restore the editor.")
	_check(not DirAccess.dir_exists_absolute(temporary), "Returning should clean up temporary playtest slots.")
	_check(document.definition() == draft_before and document._cursor == undo_cursor and document.is_dirty(), "Return must preserve the draft and undo history.")
	_check(editor.canvas.focus == focus_before and editor.canvas.zoom_level == 2 and editor.canvas.selected == Vector2i(2, 2), "Return must preserve camera and selection.")
	_check(main.session == parent_session and _snapshot(parent_session.state.to_dict()) == parent_before, "A prior running game must remain unchanged.")
	_check(_files(SaveSlots.DEFAULT_DIR) == normal_saves and _files(Campaign.SAVE_DIR) == normal_campaigns, "Playtest must not write ordinary saves or campaign progress.")
	# Repeated playtests restart from the clean authored snapshot under the same seed.
	editor.start_playtest()
	await _frames()
	controller = editor._playtest_controller
	_check(_snapshot(controller.session.state.to_dict()) == initial, "Restarting with the same seed must recreate the original starting game.")
	root.close_requested.emit()
	await _frames()
	_check(editor.visible and editor._playtest_controller == null and editor._discard.visible, "Window close from playtest should first return, then guard the unsaved draft.")
	editor._discard.canceled.emit()
	editor._discard.hide()
	# Save the draft and verify the real New Game browser and actual Begin action.
	editor.save_current()
	_check(not document.is_dirty(), "Valid custom map should save normally.")
	var invalid := MapDocument.blank(data, "custom:unfinished", "Unfinished", 10, 10)
	editor.repository.save(invalid)
	editor._request_replacement(editor._close)
	await _frames()
	_choose_custom(main.menu, "custom:playtest-demo")
	_check(not main.menu._maps.any(func(entry): return entry["id"] == "custom:unfinished"), "Unfinished drafts must not appear in New Game.")
	var setup: Dictionary = main.menu.current_setup()
	_check(not setup["standard_start"] and setup["preserve_authored"], "Custom setup should preserve authored starts.")
	_check(setup["players"][0]["color"] == "#13579a" and setup["players"][0]["name"] == "Cinderwatch", "Custom names and arbitrary authored colours should survive setup.")
	await _shot("02-custom-map-setup.png")
	var path := maps_directory.path_join("playtest-demo.json")
	DirAccess.remove_absolute(path)
	main.menu._start()
	_check(main.session == parent_session and main.menu._error.text != "", "A missing custom file must fail without replacing the running game.")
	editor.repository.save(document)
	_choose_custom(main.menu, "custom:playtest-demo")
	main.menu._start()
	await _frames()
	_check(main.session.state.map.map_id == "custom:playtest-demo" and main.session.state.heroes.size() == 1, "Begin must launch the saved custom map through the normal game flow.")
	_check(main.session.hero(hero_id).class_id == "knight" and main.session.hero(hero_id).army.total_creatures() == 12, "New Game must preserve authored foreign hero class/army.")
	main._on_slot_chosen("save", "1")
	DirAccess.remove_absolute(path)
	main._on_slot_chosen("load", "1")
	await _frames()
	_check(main.session.state.map.map_id == "custom:playtest-demo", "Custom game saves must load after the source map is removed.")
	_check(_files(SaveSlots.DEFAULT_DIR) == normal_saves, "Scene checks must not overwrite the player's ordinary saves.")
	main.queue_free()
	await _frames()
	for directory in [maps_directory, saves_directory]:
		for file in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(directory.path_join(file))
		DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(test_root)
	data.custom_maps_directory = old_maps_directory
	AudioManager.stop_all()
	Art.reload()
	GameData._default = null
	print("Editor playtest checks: " + ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)
