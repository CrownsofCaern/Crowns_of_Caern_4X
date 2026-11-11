extends SceneTree
## Renderer spike and smoke check, not the released editor UI.
## godot --path . --script res://tools/editor_document_preview.gd -- /tmp/editor.png
## Add --headless before --path to run assertions without a screenshot.

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)


func _label(title: String, at: Vector2, font_size: int = 24) -> void:
	var label := Label.new()
	label.text = title
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiStyle.TEXT)
	root.add_child(label)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	RenderingServer.set_default_clear_color(UiStyle.PANEL_BG)
	var data := GameData.get_default()
	var document := MapDocument.blank(data, "custom:preview", "Draft", 12, 12)
	var blank := document.definition()
	var left := MapView.new()
	root.add_child(left)
	left.position = Vector2(80, 180)
	left.bind_terrain_preview(AdventureMap.from_definition(blank, data))
	_check(left.session == null, "Blank draft must render without a session.")
	_check(left._ground.get_used_cells().size() == 144, "Blank draft should draw every ground tile.")
	_check(left._fog.get_used_cells().is_empty(), "Draft must not be covered by fog.")
	_check(not left._preview_map.objects.size(), "Blank draft has no objects.")
	var forest: Array[Vector2i] = []
	var river: Array[Vector2i] = []
	var road: Array[Vector2i] = []
	var mountain: Array[Vector2i] = []
	for y in 12:
		river.append(Vector2i(6, y))
	for y in range(2, 9):
		for x in range(1, 4):
			forest.append(Vector2i(x, y))
	for x in 12:
		road.append(Vector2i(x, 6))
	for x in range(8, 12):
		mountain.append(Vector2i(x, 2))
	document.begin_action("Landscape")
	document.paint_terrain(forest, "forest")
	document.paint_terrain(river, "water")
	document.paint_terrain(mountain, "mountain")
	document.paint_roads(road, true)
	document.end_action()
	var painted := document.definition()
	var right := MapView.new()
	root.add_child(right)
	right.position = Vector2(720, 180)
	right.bind_terrain_preview(AdventureMap.from_definition(painted, data))
	_check(right._ground.get_used_cells().size() == 144, "Edited draft should draw every ground tile.")
	_check(right._preview_map.is_passable(Vector2i(6, 6)), "Painted road must bridge the water.")
	_check(not right._preview_map.is_passable(Vector2i(6, 5)), "Unbridged water must stay blocked.")
	document.undo()
	_check(document.definition() == blank, "Whole landscape action should undo exactly.")
	document.redo()
	_check(document.definition() == painted, "Whole landscape action should redo exactly.")
	_label("Map editor · document and renderer foundation", Vector2(80, 45), 30)
	_label("Blank draft", Vector2(80, 130))
	_label("Painted draft", Vector2(720, 130))
	_label("12 × 12 · no players or heroes\nShared terrain, transitions, barriers and bridge art\nGrouped undo/redo verified", Vector2(80, 700), 18)
	_label("Internal rendering spike\nEditor controls are the next milestone", Vector2(720, 700), 18)
	for i in 4:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var args := OS.get_cmdline_user_args()
		var path := args[0] if not args.is_empty() else "/tmp/reignem-editor-foundation.png"
		_check(root.get_texture().get_image().save_png(path) == OK, "Cannot save renderer preview.")
		print("Editor foundation preview: " + path)
	# Rebinding the same view must restore normal session/fog behaviour, then cleanly detach.
	var session := GameSession.new_game(data, "ember_ford", 17)
	left.bind(session)
	_check(session.state_changed.is_connected(left.refresh), "Game binding must reconnect refresh.")
	_check(left._preview_map == null, "Game binding must clear the preview source.")
	left.bind_terrain_preview(AdventureMap.from_definition(blank, data))
	_check(not session.state_changed.is_connected(left.refresh), "Preview must detach the old game.")
	for i in 2:
		await process_frame
	print("Editor renderer smoke checks: " + ("FAILED" if _failed else "passed"))
	GameData._default = null
	quit(1 if _failed else 0)
