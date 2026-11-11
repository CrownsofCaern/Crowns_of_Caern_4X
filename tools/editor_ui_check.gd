extends SceneTree
## Real scene/input/render smoke tests. Saves screenshots with a headed renderer.
## godot --path . --script res://tools/editor_ui_check.gd -- /tmp/reignem-editor-ui
## Also works headless (no screenshots).

var _failed := false
var _directory := "/tmp/reignem-editor-ui"
const TEST_MAPS := "user://editor_ui_smoke"


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, text: String) -> void:
	if not value:
		_failed = true
		push_error(text)


func _frames(count: int = 3) -> void:
	for i in count:
		await process_frame


func _shot(filename: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(_directory.path_join(filename)) == OK, "Cannot save " + filename)


func _button_at(position: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT, alt: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	event.alt_pressed = alt
	Input.parse_input_event(event)
	await _frames(1)


func _tile_position(canvas: MapEditorViewport, tile: Vector2i) -> Vector2:
	return canvas.get_global_transform_with_canvas() * (canvas.map_view.position + (Vector2(tile) + Vector2.ONE * 0.5) * MapView.TILE * MapCamera.zoom_of(canvas.zoom_level))


func _drag(canvas: MapEditorViewport, from: Vector2i, to: Vector2i) -> void:
	# Feed local GUI events directly so unrelated native window focus/mouse events
	# cannot interrupt a synthetic stroke on the developer's active desktop.
	var start := canvas.get_global_transform_with_canvas().affine_inverse() * _tile_position(canvas, from)
	var end := canvas.get_global_transform_with_canvas().affine_inverse() * _tile_position(canvas, to)
	var press := InputEventMouseButton.new()
	press.position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	canvas._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.relative = end - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(motion)
	canvas.finish_stroke()
	await _frames()


func _layer_state(view: MapView) -> Dictionary:
	var state := {}
	var layers := {"ground": view._ground, "roads": view._roads, "high_roads": view._highres_roads,
		"barriers": view._barriers, "decorations": view._deco}
	for terrain in view._blends:
		layers["blend:" + terrain] = view._blends[terrain]
	for key in layers:
		var layer: TileMapLayer = layers[key]
		var cells := {}
		for pos in layer.get_used_cells():
			cells[pos] = [layer.get_cell_source_id(pos), layer.get_cell_atlas_coords(pos)]
		state[key] = cells
	return state


func _run() -> void:
	create_timer(60).timeout.connect(func():
		push_error("Editor UI smoke timed out.")
		quit(1))
	var test_maps := TEST_MAPS + "_" + str(OS.get_process_id())
	if not OS.get_cmdline_user_args().is_empty():
		_directory = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_directory)
	DirAccess.make_dir_recursive_absolute(test_maps)
	root.size = Vector2i(1280, 800)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_directory = test_maps
	root.add_child(main)
	await _frames(8)
	var editor_button: Button
	for button in main.menu._home.get_children():
		if button is Button and button.text == "Map Editor":
			editor_button = button
	_check(editor_button != null, "Title screen must offer Map Editor.")
	await _shot("01-title.png")
	if editor_button == null:
		quit(1)
		return
	editor_button.pressed.emit()
	await _frames()
	var editor: MapEditorScreen = main.map_editor
	var canvas := editor.canvas
	editor.repository = MapRepository.new(main.data, test_maps)
	editor.new_document("Brush test", 12, 12)
	await _frames()
	_check(editor.visible and not main.menu.visible, "Editor should replace the title screen.")
	_check(not main.can_process() and editor.can_process(), "Game presentation must suspend while the separate editor remains interactive.")
	_check(not auto_accept_quit, "Window close must not silently discard an editor draft.")
	root.close_requested.emit()
	_check(editor._discard.visible, "Window close should offer the same unsaved-change guard.")
	editor._discard.canceled.emit()
	editor._discard.hide()
	_check(main.session == null and canvas.map_view.session == null, "Opening a draft must not start a game.")
	canvas.terrain_id = "forest"
	await _drag(canvas, Vector2i(2, 2), Vector2i(9, 2))
	_check(editor.document.definition()["terrain"][2] == "..ffffffff..", "Fast pointer drag must fill intermediate tiles.")
	editor.document.undo()
	await _frames()
	_check(editor.document.definition()["terrain"][2] == "............", "One undo should revert the complete stroke.")
	editor.document.redo()
	await _frames()
	canvas.tool = "rectangle"
	canvas.terrain_id = "water"
	await _drag(canvas, Vector2i(5, 4), Vector2i(7, 7))
	_check(editor.document.definition()["terrain"][6] == ".....###....", "Rectangle tool should fill its whole area.")
	canvas.tool = "road"
	await _drag(canvas, Vector2i(1, 6), Vector2i(10, 6))
	_check(canvas.map_view._preview_map.is_passable(Vector2i(6, 6)), "Painted road should bridge water.")
	canvas.tool = "erase_road"
	await _drag(canvas, Vector2i(6, 6), Vector2i(6, 6))
	_check(not canvas.map_view._preview_map.is_passable(Vector2i(6, 6)), "Erasing a bridge should restore impassability.")
	editor.document.undo()
	await _frames()
	canvas.tool = "decoration"
	canvas.decoration_kind = "boulders"
	await _drag(canvas, Vector2i(3, 9), Vector2i(3, 9))
	_check(canvas.map_view._preview_map.decorations.get(Vector2i(3, 9)) == "boulders", "Decoration tool should place authored scenery.")
	canvas.tool = "erase_decoration"
	await _drag(canvas, Vector2i(3, 9), Vector2i(3, 9))
	_check(canvas.map_view._deco.get_cell_source_id(Vector2i(3, 9)) == -1, "Erasing must also suppress automatic scenery.")
	# Sampling is inspect-only, even when a paint tool is selected.
	var before := editor.document.definition()
	var sample := _tile_position(canvas, Vector2i(2, 2))
	await _button_at(sample, true, MOUSE_BUTTON_LEFT, true)
	await _button_at(sample, false, MOUSE_BUTTON_LEFT, true)
	_check(canvas.terrain_id == "forest" and editor.document.definition() == before, "Alt-click must sample without editing.")
	var zoom_point := canvas.size * 0.5
	canvas.zoom_by(1, zoom_point)
	_check(canvas.zoom_level == 2, "Zoom controls should use existing camera levels.")
	var origin := canvas.map_view.position
	var pan_press := InputEventMouseButton.new()
	pan_press.button_index = MOUSE_BUTTON_RIGHT
	pan_press.pressed = true
	pan_press.position = canvas.size * 0.5
	canvas._gui_input(pan_press)
	var pan := InputEventMouseMotion.new()
	pan.position = pan_press.position + Vector2(30, 0)
	pan.relative = Vector2(30, 0)
	canvas._gui_input(pan)
	pan_press.pressed = false
	canvas._input(pan_press)
	_check(canvas.map_view.position.x > origin.x and editor.document.definition() == before, "Panning should move the camera without editing.")
	var outside := InputEventMouseButton.new()
	outside.position = Vector2(-4, canvas.size.y * 0.5)
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	canvas._gui_input(outside)
	_check(not canvas._stroke and editor.document.definition() == before, "A press outside the clipped canvas must never paint.")
	canvas.zoom_by(-1, zoom_point)
	canvas.show_grid = true
	canvas._overlay.queue_redraw()
	# Painting must be gated while a modal is open.
	editor._new_dialog.popup_centered()
	await _frames()
	_check(not canvas.editing_enabled, "Modal dialogs must disable painting.")
	editor._new_dialog.hide()
	await _frames()
	_check(canvas.editing_enabled, "Closing a modal must restore canvas input.")
	editor._request_replacement(editor._close)
	_check(editor._discard.visible and editor.visible, "Dirty drafts need a discard prompt.")
	editor._discard.canceled.emit()
	editor._discard.hide()
	_check(editor.visible and editor.document.definition() == before, "Keeping edits should preserve the document.")
	editor.save_current()
	_check(not editor.document.is_dirty(), "Save should clear dirty state.")
	var saved_id: String = editor.document.definition()["id"].trim_prefix("custom:")
	var loaded := editor.repository.load_local(saved_id)
	_check(loaded.has("document"), "Saved drafts should reopen from local storage.")
	editor._show_save_as()
	editor._save_title.text = "Saved copy"
	editor._save_id.text = "smoke-copy"
	editor._save_dialog.confirmed.emit()
	editor._save_dialog.hide()
	await _frames()
	_check(editor.document.definition()["id"] == "custom:smoke-copy" and not editor.document.is_dirty(), "Save As should open the independent saved copy.")
	editor._show_open()
	for i in editor._open_pick.item_count:
		if editor._open_pick.get_item_metadata(i).get("local_id", "") == saved_id:
			editor._open_pick.select(i)
			break
	editor._open_dialog.confirmed.emit()
	editor._open_dialog.hide()
	await _frames()
	_check(editor.document.definition()["id"] == "custom:" + saved_id, "Open dialog should load the selected local map.")
	var reopened := editor.document
	editor._show_save_as()
	editor._save_id.text = saved_id
	editor._save_dialog.confirmed.emit()
	editor._save_dialog.hide()
	_check(editor._overwrite.visible and editor.document == reopened, "Save As must confirm before replacing an existing map.")
	editor._overwrite.canceled.emit()
	editor._overwrite.hide()
	await _frames()
	# Escape rolls back an unfinished stroke instead of leaving an open transaction.
	canvas.tool = "terrain"
	canvas.terrain_id = "desert"
	var escape_before := editor.document.definition()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = canvas.map_view.position + Vector2(2.5, 3.5) * MapView.TILE
	canvas._gui_input(press)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	editor._unhandled_key_input(escape)
	await _frames()
	_check(not editor.document.has_open_action() and editor.document.definition() == escape_before, "Escape should cancel the whole current stroke.")
	# Incremental atlas cells must exactly match a fresh full terrain build.
	var full := MapView.new()
	root.add_child(full)
	full.hide()
	full.bind_terrain_preview(AdventureMap.from_definition(editor.document.definition(), main.data))
	_check(_layer_state(full) == _layer_state(canvas.map_view), "Incremental terrain layers differ from a fresh full build.")
	full.queue_free()
	await _shot("02-terrain-editor.png")
	# A copied ordinary map displays objects/heroes without normalizing its armies.
	var source: Dictionary = main.data.load_map("ember_ford")
	var copy := MapDocument.from_definition(source, main.data).copy_as("custom:copied", "Ember Ford · local copy")
	editor.bind_document(copy)
	await _frames()
	_check(canvas.map_view._objects.get_child_count() >= source["objects"].size() + source["heroes"].size(), "Copied map should show its objects and heroes.")
	_check(editor.document.definition()["heroes"] == source["heroes"], "Preview must preserve authored armies and heroes.")
	await _shot("03-copied-map.png")
	root.size = Vector2i(1024, 720)
	await _shot("04-compact-editor.png")
	root.size = Vector2i(1280, 800)
	await _frames()
	# Exercise barrier biome influence, glow changes and occupied hero tiles too.
	var ground_id := canvas.map_view._ground.get_instance_id()
	editor.document.begin_action("Change terrain near barriers")
	editor.document.paint_terrain([Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4)], "grass")
	editor.document.paint_terrain([Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5)], "snow")
	editor.document.paint_terrain([Vector2i(18, 10), Vector2i(19, 10), Vector2i(20, 10)], "infernal")
	editor.document.paint_roads([Vector2i(7, 1), Vector2i(7, 2)], true)
	editor.document.end_action()
	await _frames()
	var starts: Array[Vector2i] = []
	for hero in source["heroes"]:
		starts.append(AdventureMap.object_pos(hero))
	var comparison := MapView.new()
	root.add_child(comparison)
	comparison.hide()
	comparison.bind_terrain_preview(AdventureMap.from_definition(editor.document.definition(), main.data), starts)
	_check(canvas.map_view._ground.get_instance_id() == ground_id, "Terrain edits must reuse the existing layers.")
	_check(_layer_state(comparison) == _layer_state(canvas.map_view), "Incremental barrier/biome layers differ from a full build.")
	_check(comparison._glow_cells.size() == canvas.map_view._glow_cells.size(), "Incremental glow cells should match a full build.")
	comparison.queue_free()
	var scenario := MapDocument.from_definition(main.data.load_map("last_watch"), main.data)
	editor.bind_document(scenario)
	await _frames()
	_check(editor._save.disabled and not editor._read_only.text.is_empty(), "Scenario editing must remain read-only.")
	before = scenario.definition()
	canvas.paint_cells([Vector2i(1, 1)])
	_check(scenario.definition() == before, "Scenario definitions must survive attempted edits unchanged.")
	scenario.mark_saved()
	editor._request_replacement(editor._close)
	await _frames()
	_check(main.menu.visible and not editor.visible and main.session == null, "Exit should return to the title without starting a game.")
	_check(main.can_process(), "Leaving the editor must restore the game controller's process mode.")
	_check(auto_accept_quit, "Leaving the editor should restore the normal window-close policy.")
	# Existing games survive opening and closing the separate editor.
	main.start_new_game("ember_ford", 17, {})
	var game: GameSession = main.session
	var game_before := game.state.to_dict()
	main._open_menu()
	main._open_editor()
	await _frames()
	editor.new_document("Discard test", 12, 12)
	editor._request_replacement(editor._close)
	_check(editor._discard.visible, "Dirty exit should require a discard decision.")
	editor._discard.confirmed.emit()
	editor._discard.hide()
	await _frames()
	_check(editor.document == null, "Confirmed discard must not reopen the abandoned dirty document.")
	_check(main.session == game and game.state.to_dict() == game_before, "Editor must not mutate an existing game.")
	main.menu.resume_requested.emit()
	_check(main.map_view.input_enabled and main.map_view.visible and main.hud.visible, "Resume should restore the game view and input.")
	for file in DirAccess.get_files_at(test_maps):
		DirAccess.remove_absolute(test_maps.path_join(file))
	DirAccess.remove_absolute(test_maps)
	print("Editor UI smoke checks: " + ("FAILED" if _failed else "passed"))
	AudioManager.stop_all()
	GameData._default = null
	quit(1 if _failed else 0)
