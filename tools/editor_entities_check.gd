extends SceneTree
## Entity/player authoring through the actual screen, canvas and property dialogs.
## godot --path . --script res://tools/editor_entities_check.gd -- /tmp/reignem-entities

var _failed := false
var _output := "/tmp/reignem-entities"


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error(message)


func _frames(count: int = 3) -> void:
	for i in count:
		await process_frame


func _shot(filename: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(_output.path_join(filename)) == OK, "Could not save " + filename)


func _pick(pick: OptionButton, value: Variant) -> void:
	for i in pick.item_count:
		if pick.get_item_metadata(i) == value:
			pick.select(i)
			pick.item_selected.emit(i)
			return
	_check(false, "Missing picker value: " + str(value))


func _choose(editor: MapEditorScreen, type: String, content: String, owner: int = -1) -> void:
	editor._select_tool("place_entity")
	editor._palette.search.text = ""
	editor._palette.select_type(type, MapPaletteCatalog.ALL)
	for i in editor._palette.items.item_count:
		if editor._palette.items.get_item_metadata(i) == content:
			editor._palette.items.select(i)
			break
	_pick(editor._palette.owner_pick, owner)


func _click(canvas: MapEditorViewport, pos: Vector2i) -> void:
	var press := InputEventMouseButton.new()
	press.position = canvas.map_view.position + (Vector2(pos) + Vector2.ONE * 0.5) * MapView.TILE * MapCamera.zoom_of(canvas.zoom_level)
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	canvas._gui_input(press)
	await _frames()


func _select(editor: MapEditorScreen, pos: Vector2i) -> void:
	editor._select_tool("inspect")
	await _click(editor.canvas, pos)


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Entity editor smoke timed out."); quit(1))
	if not OS.get_cmdline_user_args().is_empty():
		_output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_output)
	root.size = Vector2i(1280, 800)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(6)
	main._open_editor()
	var editor: MapEditorScreen = main.map_editor
	editor.new_document("Cinderwatch", 12, 12)
	await _frames()
	var document := editor.document
	_choose(editor, "hero", "knight")
	await _click(editor.canvas, Vector2i(3, 4))
	_check(document.definition()["heroes"].is_empty(), "A new hero needs an existing owner.")
	editor._players_button.pressed.emit()
	var players := editor._players_dialog
	_check(not editor.canvas.editing_enabled, "Player dialog must block canvas editing.")
	players._add.pressed.emit()
	players._add.pressed.emit()
	players._rows[0]["name"].text = "Cinderwatch"
	players._rows[1]["name"].text = "The Ashen Host"
	_pick(players._rows[0]["faction"], "concord")
	_pick(players._rows[1]["faction"], "ashen")
	await _shot("01-players.png")
	players.confirmed.emit()
	await _frames()
	_check(not players.visible and document.definition()["players"].size() == 2, "Player dialog should apply two complete player slots.")
	_choose(editor, "town", "concord", 0)
	await _click(editor.canvas, Vector2i(3, 4))
	var town_id := editor._selected_id
	_check(not document.entity(town_id).is_empty(), "Town palette should place a registered town.")
	_choose(editor, "hero", "knight", 0)
	await _click(editor.canvas, Vector2i(3, 4))
	var hero_id := editor._selected_id
	_check(document.entities_at(Vector2i(3, 4)).size() == 2 and editor._selected_hero, "Hero may share its own town, with both available for selection.")
	editor._properties.pressed.emit()
	var properties := editor._entity_dialog
	_check(properties.visible and not editor.canvas.editing_enabled, "Properties should open as a modal.")
	properties._fields["Name"].text = "Warden Vale"
	properties._army._rows[0]["count"].value = -5
	var before := document.definition()
	properties.confirmed.emit()
	_check(properties.visible and properties._error.text != "" and document.definition() == before, "Bad army counts must not partially apply property edits.")
	properties._army._rows[0]["count"].value = 24
	properties._error.text = ""
	await _shot("02-hero-properties.png")
	properties.confirmed.emit()
	await _frames()
	_check(document.entity(hero_id, true)["name"] == "Warden Vale" and document.entity(hero_id, true)["army"][0][1] == 24, "Hero name and army should apply together.")
	document.undo()
	_check(document.entity(hero_id, true)["name"] != "Warden Vale", "One undo should reverse the complete property edit.")
	document.redo()
	editor._select_tool("move_entity")
	await _click(editor.canvas, Vector2i(5, 4))
	_check(document.entity(hero_id, true)["pos"] == [5, 4] and editor._selected_id == hero_id, "Move should preserve identity and selected hero.")
	editor._duplicate_button.pressed.emit()
	await _click(editor.canvas, Vector2i(6, 4))
	var clone_id := editor._selected_id
	_check(clone_id != hero_id and document.entity(clone_id, true)["army"] == document.entity(hero_id, true)["army"], "Duplicate should preserve properties with a new identity.")
	editor._delete_button.pressed.emit()
	_check(document.entity(clone_id, true).is_empty(), "Delete should remove the selected hero.")
	document.undo()
	await _frames()
	_check(not document.entity(clone_id, true).is_empty(), "Undo should restore a deleted hero.")
	_choose(editor, "town", "ashen", 1)
	await _click(editor.canvas, Vector2i(8, 4))
	await _select(editor, Vector2i(5, 4))
	before = document.definition()
	editor._move_button.pressed.emit()
	await _click(editor.canvas, Vector2i(8, 4))
	_check(document.definition() == before and editor._selected_id == hero_id, "Invalid move to an enemy town must preserve the source and selection.")
	await _select(editor, Vector2i(3, 4))
	editor._properties.pressed.emit()
	properties._fields["Name"].text = "Cinderwatch Keep"
	properties._building_checks["c_market"].button_pressed = true
	_pick(properties._army._rows[0]["pick"], "pike_militia")
	properties._army._rows[0]["count"].value = 12
	properties.confirmed.emit()
	await _frames()
	_check(document.entity(town_id)["built"].has("c_market") and document.entity(town_id)["garrison"] == [["pike_militia", 12]], "Town buildings and garrison should be editable.")
	_choose(editor, "resource", "gold")
	await _click(editor.canvas, Vector2i(2, 7))
	var resource_id := editor._selected_id
	editor._properties.pressed.emit()
	properties._fields["Amount"].value = 750
	properties.confirmed.emit()
	_check(document.entity(resource_id)["amount"] == 750, "Resource quantity should apply.")
	_choose(editor, "neutral_army", "pike_militia")
	await _click(editor.canvas, Vector2i(7, 7))
	var guard_id := editor._selected_id
	_choose(editor, "mine", "wood")
	await _click(editor.canvas, Vector2i(8, 7))
	var mine_id := editor._selected_id
	editor._properties.pressed.emit()
	_pick(properties._fields["Guarded by"], guard_id)
	_check(properties._army.tabs.current == "wilds", "Guard stacks should open on the Wild creatures tab.")
	properties._army.show_category("concord")
	_pick(properties._army._rows[0]["pick"], "longbowman")
	properties._army._rows[0]["count"].value = 9
	properties.confirmed.emit()
	await _frames()
	_check(document.entity(mine_id)["guard"] == [["longbowman", 9]], "Mine guards should use the stack editor.")
	await _select(editor, Vector2i(7, 7))
	editor._delete_button.pressed.emit()
	_check(not document.entity(guard_id).is_empty() and editor._status.text.contains("links"), "Deleting a referenced guard must be blocked.")
	await _select(editor, Vector2i(8, 7))
	editor._properties.pressed.emit()
	_pick(properties._fields["Guarded by"], "")
	properties.confirmed.emit()
	await _frames()
	_choose(editor, "site", "outcast_camp")
	await _click(editor.canvas, Vector2i(9, 7))
	var site_id := editor._selected_id
	editor._properties.pressed.emit()
	properties._fields["Starting recruits"].value = 17
	properties.confirmed.emit()
	await _frames()
	_check(document.entity(site_id)["available"] == 17, "Dwelling initial recruits should be editable.")
	editor._properties.pressed.emit()
	_pick(properties._content, "oathstone")
	_check(not properties._fields.has("Creature") and not properties._fields["Owner"].get_parent().visible, "Changing to a non-dwelling must hide irrelevant ownership/recruit controls.")
	properties.confirmed.emit()
	await _frames()
	_check(not document.entity(site_id).has("available") and not document.entity(site_id).has("owner"), "Changing site kind should remove obsolete dwelling fields.")
	editor._properties.pressed.emit()
	_pick(properties._content, "outcast_camp")
	_check(properties._fields.has("Creature") and properties._fields["Owner"].get_parent().visible, "Changing to a dwelling must expose recruit and owner controls.")
	properties._fields["Starting recruits"].value = 17
	properties.confirmed.emit()
	await _frames()
	_check(document.entity(site_id)["available"] == 17, "Converted dwelling should accept authored recruits.")
	# Referenced player removal fails without touching document or ownership.
	editor._players_button.pressed.emit()
	before = document.definition()
	var remove: Button = players._rows[1]["box"].get_child(0).get_child(4)
	remove.pressed.emit()
	players.confirmed.emit()
	_check(players.visible and players._error.text != "" and document.definition() == before, "Removing an owned player must report references without deleting entities.")
	players.hide()
	await _frames()
	_check(MapValidator.validate(document.definition(), main.data).is_empty(), "Authored setup should satisfy the shared map validator.")
	# Palette discovery includes additions without palette source changes.
	var addition: Dictionary = main.data.artifacts.values()[0].duplicate(true)
	addition["name"] = "Smoke test addition"
	main.data.artifacts["editor_smoke_addition"] = addition
	editor.refresh_palettes()
	_choose(editor, "artifact", "editor_smoke_addition")
	_check(editor._palette.content() == "editor_smoke_addition", "Registered content should be discovered automatically.")
	main.data.artifacts.erase("editor_smoke_addition")
	editor.refresh_palettes()
	_choose(editor, "town", "concord", 0)
	await _shot("03-entity-editor.png")
	root.size = Vector2i(1024, 720)
	await _shot("04-compact-editor.png")
	await _select(editor, Vector2i(5, 4))
	editor._properties.pressed.emit()
	await _shot("05-compact-properties.png")
	properties.hide()
	root.size = Vector2i(1280, 800)
	await _frames()
	var directory := "user://editor_entities_smoke_" + str(OS.get_process_id())
	var repository := MapRepository.new(main.data, directory)
	_check(repository.save(document) == "", "Authored entities and players should save as a local map.")
	var loaded := repository.load_local(str(document.definition()["id"]).trim_prefix("custom:"))
	_check(loaded.has("document") and loaded["document"].definition() == JSON.parse_string(JSON.stringify(document.definition())), "Entity properties and players should survive file round trips.")
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	editor._request_replacement(editor._close)
	await _frames()
	print("Entity editor smoke checks: " + ("FAILED" if _failed else "passed"))
	AudioManager.stop_all()
	main.queue_free()
	await _frames()
	Art.reload()
	GameData._default = null
	quit(1 if _failed else 0)
