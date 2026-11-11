class_name MapEditorScreen
extends Control
## Authored terrain, entities, properties, player setup and local document files.

signal closed
signal quit_requested

const TOOLS := [["Terrain brush", "terrain"], ["Rectangle fill", "rectangle"],
	["Road brush", "road"], ["Erase roads", "erase_road"],
	["Decoration", "decoration"], ["Erase decoration", "erase_decoration"],
	["Place object / hero", "place_entity"], ["Move selected", "move_entity"],
	["Duplicate selected", "duplicate_entity"], ["Inspect", "inspect"]]

var document: MapDocument
var canvas: MapEditorViewport
var repository: MapRepository
var _data: GameData
var _title: Label
var _status: Label
var _selection: Label
var _read_only: Label
var _terrain: OptionButton
var _terrain_label: Label
var _decoration: OptionButton
var _decoration_label: Label
var _tool: OptionButton
var _brush: SpinBox
var _brush_label: Label
var _objects_button: Button
var _hint: Label
var _undo: Button
var _redo: Button
var _save: Button
var _save_as: Button
var _zoom: Label
var _rename: LineEdit
var _rename_button: Button
var _new_dialog: ConfirmationDialog
var _new_title: LineEdit
var _new_width: SpinBox
var _new_height: SpinBox
var _new_terrain: OptionButton
var _open_dialog: ConfirmationDialog
var _open_pick: OptionButton
var _freeze_source: LineEdit
var _freeze_id: LineEdit
var _save_dialog: ConfirmationDialog
var _save_title: LineEdit
var _save_id: LineEdit
var _discard: ConfirmationDialog
var _overwrite: ConfirmationDialog
var _message: AcceptDialog
var _pending_action: Callable
var _pending_copy: MapDocument
var _owns_window_close := false
var _previous_auto_quit := true
var _playtest_button: Button
var _playtest_seed: SpinBox
var _playtest_controller: Node
var _playtest_directory := ""
var _playtest_faction := ""
var _palette: MapEntityPalette
var _entity_pick: OptionButton
var _properties: Button
var _move_button: Button
var _duplicate_button: Button
var _delete_button: Button
var _players_button: Button
var _entity_dialog: MapEntityDialog
var _players_dialog: MapPlayersDialog
var _selected_id := ""
var _selected_hero := false


func build(data: GameData, maps: MapRepository = null) -> void:
	_data = data
	repository = maps if maps != null else MapRepository.new(data)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.make_theme()
	var background := ColorRect.new()
	background.color = UiStyle.PANEL_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var bar := HBoxContainer.new()
	layout.add_child(bar)
	_button(bar, "Back", func(): _request_replacement(_close))
	_title = UiStyle.label("Map Editor", 23, UiStyle.BRASS)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(_title)
	_button(bar, "New", func(): _request_replacement(func(): _new_dialog.popup_centered()))
	_button(bar, "Open", func(): _request_replacement(_show_open))
	_save = _button(bar, "Save", save_current)
	_save_as = _button(bar, "Save As", _show_save_as)
	_undo = _button(bar, "Undo", func(): canvas.finish_stroke(); document.undo())
	_redo = _button(bar, "Redo", func(): canvas.finish_stroke(); document.redo())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	layout.add_child(body)
	var palette := _side_panel(body, 210)
	palette.add_child(UiStyle.label("TOOLS", 17, UiStyle.BRASS))
	_tool = OptionButton.new()
	for item in TOOLS:
		_tool.add_item(item[0])
		_tool.set_item_metadata(_tool.item_count - 1, item[1])
	_tool.item_selected.connect(func(_index):
		canvas.finish_stroke()
		canvas.tool = _tool.get_selected_metadata()
		_update_tools())
	palette.add_child(_tool)
	_objects_button = _button(palette, "Objects & heroes", func(): _select_tool("place_entity"))
	_terrain_label = UiStyle.label("Terrain", 15, UiStyle.TEXT_DIM)
	palette.add_child(_terrain_label)
	_terrain = OptionButton.new()
	_terrain.item_selected.connect(func(_index):
		canvas.finish_stroke()
		canvas.terrain_id = str(_terrain.get_selected_metadata()))
	palette.add_child(_terrain)
	_decoration_label = UiStyle.label("Decoration", 15, UiStyle.TEXT_DIM)
	palette.add_child(_decoration_label)
	_decoration = OptionButton.new()
	_decoration.item_selected.connect(func(_index):
		canvas.finish_stroke()
		canvas.decoration_kind = str(_decoration.get_selected_metadata()))
	palette.add_child(_decoration)
	_brush_label = UiStyle.label("Brush width (tiles)", 15, UiStyle.TEXT_DIM)
	palette.add_child(_brush_label)
	_brush = _spin(palette, 1, 15, 1)
	_brush.value_changed.connect(func(value):
		canvas.finish_stroke()
		canvas.brush_side = int(value))
	var grid := CheckBox.new()
	grid.text = "Show grid"
	grid.toggled.connect(func(value): canvas.show_grid = value; canvas._overlay.queue_redraw())
	palette.add_child(grid)
	var zoom_bar := HBoxContainer.new()
	palette.add_child(zoom_bar)
	_button(zoom_bar, "−", func(): canvas.zoom_by(-1, canvas.size * 0.5))
	_zoom = UiStyle.label("100%", 16)
	_zoom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zoom_bar.add_child(_zoom)
	_button(zoom_bar, "+", func(): canvas.zoom_by(1, canvas.size * 0.5))
	_palette = MapEntityPalette.new()
	palette.add_child(_palette)
	_palette.build(data)
	_palette.place_requested.connect(func(): _select_tool("place_entity"))
	_hint = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	palette.add_child(_hint)
	_read_only = _wrapped("", 14, UiStyle.WARN)
	palette.add_child(_read_only)
	canvas = MapEditorViewport.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(240, 200)
	body.add_child(canvas)
	canvas.tile_selected.connect(func(_cell): _show_selection())
	canvas.terrain_sampled.connect(_sample_terrain)
	canvas.zoom_changed.connect(func(value): _zoom.text = "%d%%" % roundi(value * 100))
	canvas.entity_requested.connect(_entity_action)
	var inspector := _side_panel(body, 210)
	inspector.add_child(UiStyle.label("MAP", 17, UiStyle.BRASS))
	_rename = LineEdit.new()
	_rename.placeholder_text = "Map name"
	_rename.text_submitted.connect(func(value): _rename_map(value))
	inspector.add_child(_rename)
	_rename_button = _button(inspector, "Rename", func(): _rename_map(_rename.text))
	_players_button = _button(inspector, "Players…", func(): canvas.finish_stroke(); _players_dialog.open_players(document))
	inspector.add_child(UiStyle.label("Playtest seed", 14, UiStyle.TEXT_DIM))
	_playtest_seed = _spin(inspector, 0, 2147483647, 1)
	_playtest_button = _button(inspector, "Playtest", start_playtest)
	inspector.add_child(HSeparator.new())
	inspector.add_child(UiStyle.label("SELECTED TILE", 17, UiStyle.BRASS))
	_selection = _wrapped("Click a tile to inspect it.", 15)
	inspector.add_child(_selection)
	_entity_pick = OptionButton.new()
	_entity_pick.clip_text = true
	_entity_pick.item_selected.connect(func(index):
		var entry: Dictionary = _entity_pick.get_item_metadata(index)
		_selected_id = entry["id"]
		_selected_hero = entry["hero"])
	inspector.add_child(_entity_pick)
	_properties = _button(inspector, "Properties…", func(): _entity_dialog.open_entity(document, _selected_id, _selected_hero))
	_move_button = _button(inspector, "Move", func(): _select_tool("move_entity"))
	_duplicate_button = _button(inspector, "Duplicate", func(): _select_tool("duplicate_entity"))
	_delete_button = _button(inspector, "Delete", _delete_entity)
	inspector.add_child(HSeparator.new())
	_button(inspector, "Validate map", _check_placement)
	inspector.add_child(_wrapped("Maps can be saved as drafts before their player starts are ready.", 14, UiStyle.TEXT_DIM))
	_status = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(_status)
	_build_dialogs()
	refresh_palettes()
	hide()


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _wrapped(text: String, font_size: int, color: Color = UiStyle.TEXT) -> Label:
	var label := UiStyle.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _side_panel(parent: Node, width: int) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size.x = width
	parent.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column


func _spin(parent: Node, minimum: int, maximum: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	spin.step = 1
	parent.add_child(spin)
	return spin


func _dialog(title_text: String) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title_text
	dialog.min_size = Vector2i(420, 180)
	add_child(dialog)
	dialog.visibility_changed.connect(func():
		if canvas != null:
			canvas.editing_enabled = not _modal_open())
	return dialog


func _dialog_body(dialog: ConfirmationDialog) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	dialog.add_child(body)
	return body


func _field(parent: Node, label_text: String, initial: String) -> LineEdit:
	parent.add_child(UiStyle.label(label_text, 15))
	var edit := LineEdit.new()
	edit.text = initial
	parent.add_child(edit)
	return edit


func _build_dialogs() -> void:
	_new_dialog = _dialog("New map")
	var body := _dialog_body(_new_dialog)
	_new_title = _field(body, "Name", "Untitled map")
	body.add_child(UiStyle.label("Width / height (tiles)", 15))
	var dimensions := HBoxContainer.new()
	body.add_child(dimensions)
	_new_width = _spin(dimensions, 4, MapDocument.MAX_SIDE, 40)
	_new_height = _spin(dimensions, 4, MapDocument.MAX_SIDE, 30)
	body.add_child(UiStyle.label("Starting terrain", 15))
	_new_terrain = OptionButton.new()
	body.add_child(_new_terrain)
	_new_dialog.get_ok_button().text = "Create"
	_new_dialog.confirmed.connect(func():
		_new_dialog.hide()
		new_document(_new_title.text, int(_new_width.value), int(_new_height.value), str(_new_terrain.get_selected_metadata())))
	_open_dialog = _dialog("Open map")
	body = _dialog_body(_open_dialog)
	var dev := repository.dev_mode
	body.add_child(_wrapped("Dev mode: bundled maps open in place and Save writes res://data/maps." if dev else "Bundled maps open as local copies. Scenario maps can be inspected read-only.", 15))
	_open_pick = OptionButton.new()
	_open_pick.custom_minimum_size.x = 480
	_open_pick.clip_text = true
	body.add_child(_open_pick)
	# Dev mode can also freeze a generated map into a new bundled map.
	var freeze_box := VBoxContainer.new()
	freeze_box.visible = dev
	body.add_child(freeze_box)
	_freeze_source = _field(freeze_box, "Or freeze a map id (gen:<template>:<seed>, scenario:<recipe>:<seed>)", "")
	_freeze_source.placeholder_text = "gen:broad_crossing:311"
	_freeze_id = _field(freeze_box, "New bundled map id", "")
	_open_dialog.get_ok_button().text = "Open"
	_open_dialog.confirmed.connect(_open_selected)
	_save_dialog = _dialog("Save map as")
	body = _dialog_body(_save_dialog)
	_save_title = _field(body, "Map name", "")
	_save_id = _field(body, "File ID (lowercase letters, numbers, - and _)", "")
	_save_dialog.confirmed.connect(_save_copy)
	_discard = _dialog("Unsaved changes")
	_discard.dialog_text = "Discard changes to this map? Save it first if you want to keep them."
	_discard.get_ok_button().text = "Discard changes"
	_discard.get_cancel_button().text = "Keep editing"
	_discard.confirmed.connect(func():
		_discard.hide()
		if _pending_action.is_valid():
			_pending_action.call()
		_pending_action = Callable())
	_discard.canceled.connect(func(): _pending_action = Callable())
	_overwrite = _dialog("Replace saved map?")
	_overwrite.get_ok_button().text = "Replace"
	_overwrite.confirmed.connect(_write_copy)
	_overwrite.canceled.connect(func(): _pending_copy = null)
	_message = AcceptDialog.new()
	_message.title = "Map Editor"
	_message.min_size = Vector2i(440, 160)
	add_child(_message)
	_message.visibility_changed.connect(func(): canvas.editing_enabled = not _modal_open())
	_entity_dialog = MapEntityDialog.new()
	add_child(_entity_dialog)
	_entity_dialog.build(_data)
	_entity_dialog.applied.connect(func(id, hero, pos):
		_selected_id = id
		_selected_hero = hero
		canvas.selected = pos
		_select_tool("inspect")
		_show_selection())
	_entity_dialog.visibility_changed.connect(func(): canvas.editing_enabled = not _modal_open())
	_players_dialog = MapPlayersDialog.new()
	add_child(_players_dialog)
	_players_dialog.build(_data)
	_players_dialog.visibility_changed.connect(func(): canvas.editing_enabled = not _modal_open())


func open() -> void:
	if not _owns_window_close:
		_previous_auto_quit = get_tree().auto_accept_quit
		get_tree().auto_accept_quit = false
		get_window().close_requested.connect(_on_window_close)
		_owns_window_close = true
	refresh_palettes()
	show()
	if document == null:
		new_document("Untitled map", 40, 30)
	else:
		_update_document()


func refresh_palettes() -> void:
	var selected_terrain := canvas.terrain_id
	_terrain.clear()
	_new_terrain.clear()
	var ids := _data.terrains.keys()
	ids.sort()
	# Walkable ground first, then blocking terrain under its own heading.
	var blocking := ids.filter(func(id): return not bool(_data.terrains[id].get("passable", true)))
	ids = ids.filter(func(id): return not blocking.has(id)) + blocking
	for id in ids:
		if not blocking.is_empty() and id == blocking[0] and _terrain.item_count > 0:
			_terrain.add_separator("Impassable")
		var image := Image.create(18, 18, false, Image.FORMAT_RGBA8)
		image.fill(Color(_data.terrains[id].get("color", "#777777")))
		_terrain.add_icon_item(ImageTexture.create_from_image(image), str(_data.terrains[id].get("name", id)))
		_terrain.set_item_metadata(_terrain.item_count - 1, id)
		_new_terrain.add_item(str(_data.terrains[id].get("name", id)))
		_new_terrain.set_item_metadata(_new_terrain.item_count - 1, id)
		if id == selected_terrain:
			_terrain.select(_terrain.item_count - 1)
			_new_terrain.select(_new_terrain.item_count - 1)
	if _terrain.item_count > 0:
		canvas.terrain_id = str(_terrain.get_selected_metadata())
	_decoration.clear()
	ids = Art.terrain_info().get("deco", {}).get("kinds", {}).keys()
	ids.sort()
	for id in ids:
		_decoration.add_item(str(id).capitalize())
		_decoration.set_item_metadata(_decoration.item_count - 1, id)
	if _decoration.item_count > 0:
		canvas.decoration_kind = str(_decoration.get_selected_metadata())
	_palette.refresh(document, true)
	_update_tools()


func new_document(title_text: String, width: int, height: int, terrain: String = "grass") -> void:
	var value := MapDocument.blank(_data, "custom:" + _suggest_id(title_text), title_text, width, height, terrain)
	if value == null:
		_notice("The map dimensions or starting terrain are invalid.")
		return
	bind_document(value)
	_status.text = "New draft · %d × %d tiles" % [width, height]


func bind_document(value: MapDocument) -> void:
	if document != null and document.changed.is_connected(_update_document):
		document.changed.disconnect(_update_document)
	document = value
	_selected_id = ""
	canvas.bind(document, _data)
	document.changed.connect(_update_document)
	_rename.text = str(document.definition().get("name", "Untitled map"))
	_update_document()


func _update_document() -> void:
	var definition := document.definition()
	_title.text = "Map Editor · " + str(definition.get("name", definition["id"])) + (" *" if document.is_dirty() else "")
	_undo.disabled = not document.can_undo()
	_redo.disabled = not document.can_redo()
	_save.disabled = document.read_only()
	_save_as.disabled = document.read_only()
	_rename.editable = not document.read_only()
	_read_only.text = "Read-only: this map uses scenario features or object types whose editing tools are not available yet." if document.read_only() else ""
	if document.is_data_map():
		_read_only.text = "Dev mode: Save writes data/maps/%s.json. Scenario, objectives, quests and teams are kept as they are." % str(definition["id"])
	if not _rename.has_focus():
		_rename.text = str(definition.get("name", "Untitled map"))
	_rename_button.disabled = document.read_only()
	_players_button.disabled = document.read_only()
	_playtest_button.disabled = document.read_only()
	_palette.refresh(document)
	_update_tools()
	_show_selection()


func _update_tools() -> void:
	var locked := document != null and document.read_only()
	_objects_button.disabled = locked
	_tool.disabled = locked
	if locked:
		canvas.tool = "inspect"
		_tool.select(TOOLS.size() - 1)
	_terrain.disabled = locked or canvas.tool not in ["terrain", "rectangle"]
	_decoration.disabled = locked or canvas.tool != "decoration" or _decoration.item_count == 0
	_brush.editable = not locked and canvas.tool not in ["rectangle", "inspect", "place_entity", "move_entity", "duplicate_entity"]
	var entities := canvas.tool.ends_with("entity")
	for control in [_terrain_label, _terrain, _decoration_label, _decoration, _brush_label, _brush]:
		control.visible = not entities
	_palette.visible = canvas.tool == "place_entity"
	_hint.text = ("Click a tile to place\nMove/Duplicate: pick a tile\nEsc returns to Inspect" if entities else "Left-drag to paint\nAlt-click to sample terrain\nEsc cancels a stroke") + "\nRight/middle-drag to pan\nWheel to zoom\nCtrl/Cmd+Z to undo\nCtrl/Cmd+S to save"


func _rename_map(value: String) -> void:
	canvas.finish_stroke()
	if not value.strip_edges().is_empty():
		document.set_title(value.strip_edges())


func _sample_terrain(id: String) -> void:
	canvas.terrain_id = id
	for i in _terrain.item_count:
		if _terrain.get_item_metadata(i) == id:
			_terrain.select(i)
	_status.text = "Sampled " + str(_data.terrains[id].get("name", id))


func _show_selection() -> void:
	if _entity_pick == null:
		return
	_entity_pick.clear()
	if document == null or canvas.selected == MapEditorViewport.INVALID:
		_selection.text = "Click a tile to inspect it."
		_selected_id = ""
		_update_entity_buttons()
		return
	var definition := document.definition()
	var pos := canvas.selected
	var id: String = _data.terrain_by_char[definition["terrain"][pos.y][pos.x]]
	var lines: Array[String] = ["Tile %d, %d" % [pos.x, pos.y], str(_data.terrains[id].get("name", id))]
	var map := AdventureMap.from_definition(definition, _data)
	if map.has_road(pos):
		lines.append("Road / bridge")
	for entity in definition["objects"] + definition["heroes"]:
		if AdventureMap.object_pos(entity) == pos:
			lines.append("\n" + str(entity.get("name", entity["id"])))
			lines.append(str(entity.get("type", "hero")).capitalize())
	_selection.text = "\n".join(lines)
	for entry in document.entities_at(pos):
		var entity: Dictionary = entry["entity"]
		_entity_pick.add_item(str(entity.get("name", entity["id"])) + " · " + str(entity["id"]))
		_entity_pick.set_item_metadata(_entity_pick.item_count - 1, {"id": entity["id"], "hero": entry["hero"]})
		if entity["id"] == _selected_id:
			_entity_pick.select(_entity_pick.item_count - 1)
	if _entity_pick.item_count > 0:
		var chosen: Dictionary = _entity_pick.get_selected_metadata()
		_selected_id = chosen["id"]
		_selected_hero = chosen["hero"]
	else:
		_selected_id = ""
	_update_entity_buttons()


func _update_entity_buttons() -> void:
	var disabled := document == null or document.read_only() or _selected_id == ""
	for button in [_properties, _move_button, _duplicate_button, _delete_button]:
		button.disabled = disabled
	_entity_pick.disabled = _entity_pick.item_count == 0


func _select_tool(value: String) -> void:
	canvas.finish_stroke()
	canvas.tool = value
	for i in TOOLS.size():
		if TOOLS[i][1] == value:
			_tool.select(i)
	_update_tools()
	if value in ["move_entity", "duplicate_entity"]:
		_status.text = "Click a destination tile, or choose a source entity first. Esc returns to Inspect."


func _entity_action(action: String, pos: Vector2i) -> void:
	var result: Dictionary
	if action == "place_entity":
		result = MapAuthoring.place(document, _data, _palette.type(), _palette.content(), pos, _palette.selected_owner())
	else:
		if _selected_id == "":
			canvas.selected = pos
			_show_selection()
			_status.text = "Now click a destination tile." if _selected_id != "" else "Select an existing object or hero first."
			return
		result = MapAuthoring.move(document, _data, _selected_id, _selected_hero, pos, action == "duplicate_entity")
	if result["error"] != "":
		_status.text = result["error"]
		return
	_selected_id = result["id"]
	_selected_hero = result["hero"]
	canvas.selected = pos
	if action != "place_entity":
		_select_tool("inspect")
	_show_selection()
	_status.text = "Entity placed." if action == "place_entity" else "Entity duplicated." if action == "duplicate_entity" else "Entity moved."


func _delete_entity() -> void:
	canvas.finish_stroke()
	var error := MapAuthoring.delete(document, _selected_id, _selected_hero)
	_status.text = "Entity deleted. Undo restores it." if error == "" else error


func save_current() -> void:
	canvas.finish_stroke()
	if document.read_only():
		_notice("This map is read-only.")
		return
	var id := str(document.definition()["id"])
	if document.is_data_map():
		var data_error := repository.save_data_map(document)
		if data_error != "":
			_notice(data_error)
		else:
			_status.text = "Saved bundled map · data/maps/" + id + ".json"
		return
	if not id.begins_with("custom:"):
		_show_save_as()
		return
	var error := repository.save(document)
	if error != "":
		_notice(error)
	else:
		_status.text = "Saved locally · " + id.trim_prefix("custom:") + ".json"


func _show_save_as() -> void:
	canvas.finish_stroke()
	if document.read_only():
		return
	_save_title.text = str(document.definition().get("name", "Untitled map"))
	_save_id.text = str(document.definition()["id"]) + "_copy" if document.is_data_map() else _suggest_id(_save_title.text)
	_save_dialog.popup_centered()


func _save_copy() -> void:
	_save_dialog.hide()
	var id := _save_id.text.strip_edges()
	if not MapRepository.valid_local_id(id):
		_notice("Use 1–80 lowercase letters, numbers, hyphens or underscores for the file ID.")
		return
	var bundled := document.is_data_map()
	_pending_copy = document.copy_as(id if bundled else "custom:" + id, _save_title.text.strip_edges())
	if _pending_copy == null:
		return
	if FileAccess.file_exists(repository.data_path(id) if bundled else repository.directory.path_join(id + ".json")):
		_overwrite.dialog_text = "Replace %s.json with this map?" % id
		_overwrite.popup_centered()
	else:
		_write_copy()


func _write_copy() -> void:
	_overwrite.hide()
	if _pending_copy == null:
		return
	var error := repository.save_data_map(_pending_copy) if _pending_copy.is_data_map() else repository.save(_pending_copy)
	if error != "":
		_notice(error)
	else:
		var old_focus := canvas.focus
		var old_selected := canvas.selected
		bind_document(_pending_copy)
		canvas.focus = old_focus
		canvas.selected = old_selected
		canvas._position_map()
		_show_selection()
		_status.text = ("Saved bundled map · data/maps/%s.json" if document.is_data_map() else "Saved local copy · %s.json") % str(document.definition()["id"]).trim_prefix("custom:")
	_pending_copy = null


func _show_open() -> void:
	_open_pick.clear()
	for entry in repository.list_local():
		var label := "Local · " + str(entry["local_id"])
		if entry.has("document"):
			label = "Local · " + str(entry["document"].definition().get("name", entry["local_id"]))
		else:
			label += " (unreadable)"
		_open_pick.add_item(label)
		_open_pick.set_item_metadata(_open_pick.item_count - 1, {"local_id": entry["local_id"]})
		_open_pick.set_item_disabled(_open_pick.item_count - 1, not entry.has("document"))
	for id in repository.data_map_ids():
		_open_pick.add_item(("Bundled (in place) · " if repository.dev_mode else "Bundled · ") + id.capitalize())
		_open_pick.set_item_metadata(_open_pick.item_count - 1, {"path": repository.data_path(id), "data_id": id})
	_freeze_source.text = ""
	_freeze_id.text = ""
	for i in _open_pick.item_count:
		if not _open_pick.is_item_disabled(i):
			_open_pick.select(i)
			break
	_open_dialog.get_ok_button().disabled = _open_pick.item_count == 0
	_open_dialog.popup_centered()


func _open_selected() -> void:
	_open_dialog.hide()
	if _open_pick.selected < 0:
		return
	var source := _freeze_source.text.strip_edges()
	if repository.dev_mode and source != "":
		var frozen := repository.freeze_to_document(source, _freeze_id.text.strip_edges())
		if not frozen.has("document"):
			_notice(frozen["error"])
			return
		bind_document(frozen["document"])
		_status.text = "Frozen %s · unsaved; Save writes data/maps/%s.json" % [source, _freeze_id.text.strip_edges()]
		return
	var selection: Dictionary = _open_pick.get_selected_metadata()
	var result: Dictionary
	if selection.has("local_id"):
		result = repository.load_local(selection["local_id"])
	elif repository.dev_mode:
		result = repository.open_data_map(selection["data_id"])
	else:
		result = repository.read_file(selection["path"])
	if not result.has("document"):
		_notice(result["error"])
		return
	var value: MapDocument = result["document"]
	if value.is_data_map():
		bind_document(value)
		_status.text = "Opened bundled map in place · data/maps/%s.json" % selection["data_id"]
		return
	if selection.has("path") and not value.read_only():
		var title_text := str(value.definition().get("name", "Copied map"))
		value = value.copy_as("custom:" + _suggest_id(title_text), title_text)
	bind_document(value)
	_status.text = "Read-only map" if value.read_only() else ("Opened local map" if selection.has("local_id") else "Opened as an unsaved local copy")


func _request_replacement(action: Callable) -> void:
	canvas.finish_stroke()
	if document != null and document.is_dirty():
		_pending_action = action
		_discard.popup_centered()
	else:
		action.call()


func _close() -> void:
	if _playtest_controller != null:
		return_from_playtest()
	canvas.cancel_stroke()
	if document != null and document.is_dirty():
		document.changed.disconnect(_update_document)
		document = null
	_restore_window_close()
	hide()
	closed.emit()


func _on_window_close() -> void:
	if _playtest_controller != null:
		return_from_playtest()
	_request_replacement(func():
		_close()
		quit_requested.emit())


func _restore_window_close() -> void:
	if _owns_window_close:
		get_window().close_requested.disconnect(_on_window_close)
		get_tree().auto_accept_quit = _previous_auto_quit
		_owns_window_close = false


func _exit_tree() -> void:
	_restore_window_close()


func _check_placement() -> void:
	canvas.finish_stroke()
	var errors := MapPlayability.errors(document.definition(), _data)
	if document.is_data_map():
		errors = document.placement_errors()
		if errors.is_empty():
			errors.assign(MapValidator.validate(document.definition(), _data))
		_notice("Valid bundled map." if errors.is_empty() else "\n".join(errors.slice(0, 12)) + ("\n… and %d more issues." % (errors.size() - 12) if errors.size() > 12 else ""))
		return
	_notice("Ready to play. Save to list this map in New Game, or use Playtest for the current draft." if errors.is_empty() else "\n".join(errors.slice(0, 12)) + ("\n… and %d more issues." % (errors.size() - 12) if errors.size() > 12 else ""))


func start_playtest() -> void:
	if _playtest_controller != null or _modal_open():
		return
	canvas.finish_stroke()
	var definition := document.definition()
	var errors := MapPlayability.errors(definition, _data)
	if not errors.is_empty():
		_check_placement()
		return
	var test_session := GameSession.new_game_from_definition(_data, definition, int(_playtest_seed.value))
	if test_session == null:
		_notice("The playtest could not be started.")
		return
	_playtest_directory = "user://editor_playtests/session_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_playtest_faction = UiStyle.faction
	var controller: Node = load("res://scenes/main.tscn").instantiate()
	controller.initial_session = test_session
	controller.editor_playtest = true
	controller.save_directory = _playtest_directory
	controller.process_mode = Node.PROCESS_MODE_ALWAYS
	controller.playtest_return_requested.connect(return_from_playtest)
	_playtest_controller = controller
	hide()
	get_tree().root.add_child(controller)


func return_from_playtest() -> void:
	if _playtest_controller == null:
		return
	var controller := _playtest_controller
	_playtest_controller = null
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	controller.get_parent().remove_child(controller)
	controller.queue_free()
	# This directory is created only by start_playtest; normal saves are never used.
	for file in DirAccess.get_files_at(_playtest_directory):
		DirAccess.remove_absolute(_playtest_directory.path_join(file))
	DirAccess.remove_absolute(_playtest_directory)
	_playtest_directory = ""
	UiStyle.apply_faction(self, _playtest_faction)
	AudioManager.set_music("menu")
	show()
	canvas.editing_enabled = not _modal_open()
	_status.text = "Returned from playtest. Your draft and undo history are unchanged."
	_update_document()


func _notice(text: String) -> void:
	_message.dialog_text = text
	_message.popup_centered()


func _modal_open() -> bool:
	for dialog in [_new_dialog, _open_dialog, _save_dialog, _discard, _overwrite, _message, _entity_dialog, _players_dialog]:
		if dialog != null and dialog.visible:
			return true
	return false


func _suggest_id(title_text: String) -> String:
	var prefix := ""
	for ch in title_text.to_lower():
		if ch in "abcdefghijklmnopqrstuvwxyz0123456789":
			prefix += ch
		elif not prefix.ends_with("-"):
			prefix += "-"
	prefix = prefix.substr(0, 32).strip_edges().trim_suffix("-")
	if prefix.is_empty():
		prefix = "map"
	var base := prefix + "-" + str(Time.get_ticks_usec())
	var candidate := base
	var suffix := 2
	while FileAccess.file_exists(repository.directory.path_join(candidate + ".json")):
		candidate = base + "-" + str(suffix)
		suffix += 1
	return candidate


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _modal_open() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var modified: bool = event.ctrl_pressed or event.meta_pressed
	if event.keycode == KEY_ESCAPE:
		if canvas._stroke:
			canvas.cancel_stroke()
		elif canvas.tool in ["place_entity", "move_entity", "duplicate_entity"]:
			_select_tool("inspect")
		else:
			_request_replacement(_close)
	elif modified and event.keycode == KEY_S:
		if event.shift_pressed:
			_show_save_as()
		else:
			save_current()
	elif modified and event.keycode in [KEY_Z, KEY_Y]:
		canvas.finish_stroke()
		if event.shift_pressed or event.keycode == KEY_Y:
			document.redo()
		else:
			document.undo()
	else:
		return
	get_viewport().set_input_as_handled()
