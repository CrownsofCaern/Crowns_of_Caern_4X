class_name MapPlayersDialog
extends ConfirmationDialog
## Stages player edits; applying remaps ownership as a single undo action.

var _data: GameData
var _document: MapDocument
var _list: VBoxContainer
var _rows: Array[Dictionary] = []
var _error: Label
var _add: Button
var _next_id := 0


func build(data: GameData) -> void:
	_data = data
	theme = UiStyle.make_theme().duplicate()
	theme.set_stylebox("panel", "AcceptDialog", UiStyle.panel_box())
	var frame := ThemeDB.get_default_theme().get_stylebox("embedded_border", "Window").duplicate()
	if frame is StyleBoxFlat:
		frame.bg_color = UiStyle.PANEL_BG
		frame.border_color = UiStyle.BRASS.darkened(0.4)
	theme.set_stylebox("embedded_border", "Window", frame)
	title = "Players"
	min_size = Vector2i(920, 400)
	dialog_hide_on_ok = false
	get_ok_button().text = "Apply players"
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	var note := UiStyle.label("Changing a faction keeps existing towns, hero classes and armies. Reassign owned entities before removing a player.", 14, UiStyle.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 880
	outer.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	_add = Button.new()
	_add.text = "Add player"
	_add.pressed.connect(_add_player)
	outer.add_child(_add)
	_error = UiStyle.label("", 14, UiStyle.BAD)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size.x = 880
	outer.add_child(_error)
	confirmed.connect(_apply)


func open_players(document: MapDocument) -> void:
	if document.read_only():
		return
	_document = document
	_rows.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_next_id = 0
	for player in document.definition()["players"]:
		_next_id = maxi(_next_id, int(player.get("id", -1)) + 1)
		_append(player)
	_add.disabled = _rows.size() >= MapAuthoring.MAX_PLAYERS
	_error.text = ""
	popup_centered(Vector2i(920, 400))


func _add_player() -> void:
	var factions := GameSetup.playable_factions(_data)
	if factions.is_empty() or _rows.size() >= MapAuthoring.MAX_PLAYERS:
		return
	_append({"id": _next_id, "name": "Player %d" % (_rows.size() + 1),
		"faction": factions[_rows.size() % factions.size()], "color": GameSetup.PLAYER_COLORS[_rows.size()],
		"is_human": _rows.is_empty(), "difficulty": _data.default_difficulty(), "team": 0})
	_next_id += 1


func _pick(options: Dictionary, selected: Variant) -> OptionButton:
	var pick := OptionButton.new()
	pick.clip_text = true
	for key in options:
		pick.add_item(str(options[key]))
		pick.set_item_metadata(pick.item_count - 1, key)
		if key == selected:
			pick.select(pick.item_count - 1)
	if not options.has(selected):
		pick.add_item("Missing: " + str(selected))
		pick.set_item_metadata(pick.item_count - 1, selected)
		pick.select(pick.item_count - 1)
	return pick


func _append(player: Dictionary) -> void:
	var box := VBoxContainer.new()
	_list.add_child(box)
	var first := HBoxContainer.new()
	box.add_child(first)
	first.add_child(UiStyle.label("Player", 14))
	var name_edit := LineEdit.new()
	name_edit.text = str(player.get("name", ""))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first.add_child(name_edit)
	var faction_options := {}
	for id in GameSetup.playable_factions(_data):
		faction_options[id] = str(_data.factions[id].get("name", id))
	var faction := _pick(faction_options, player.get("faction", ""))
	faction.custom_minimum_size.x = 230
	first.add_child(faction)
	var control := _pick({true: "Human", false: "Computer"}, player.get("is_human", false))
	control.custom_minimum_size.x = 110
	first.add_child(control)
	var remove := Button.new()
	remove.text = "Remove"
	first.add_child(remove)
	var second := HBoxContainer.new()
	box.add_child(second)
	second.add_child(UiStyle.label("Colour", 14))
	var color := ColorPickerButton.new()
	color.color = Color(str(player.get("color", "#c94040")))
	color.edit_alpha = false
	color.custom_minimum_size = Vector2(80, 30)
	second.add_child(color)
	second.add_child(UiStyle.label("Computer difficulty", 14))
	var levels := {}
	for id in _data.difficulty_levels():
		levels[id] = str(_data.ai_difficulty["levels"][id].get("name", id))
	var difficulty := _pick(levels, player.get("difficulty", _data.default_difficulty()))
	difficulty.custom_minimum_size.x = 150
	second.add_child(difficulty)
	second.add_child(UiStyle.label("Team (0 = none)", 14))
	var team := SpinBox.new()
	team.min_value = 0
	team.max_value = GameSetup.MAX_TEAMS
	team.value = int(player.get("team", 0))
	second.add_child(team)
	var row := {"original": player.duplicate(true), "box": box, "name": name_edit,
		"faction": faction, "control": control, "color": color, "difficulty": difficulty, "team": team}
	_rows.append(row)
	remove.pressed.connect(func():
		_rows.erase(row)
		_list.remove_child(box)
		box.queue_free()
		_add.disabled = false)
	_add.disabled = _rows.size() >= MapAuthoring.MAX_PLAYERS


func player_rows() -> Array:
	var players: Array = []
	for row in _rows:
		var value: Dictionary = row["original"].duplicate(true)
		value["name"] = row["name"].text
		value["faction"] = row["faction"].get_selected_metadata()
		value["is_human"] = row["control"].get_selected_metadata()
		value["color"] = row["color"].color.to_html(false)
		value["difficulty"] = row["difficulty"].get_selected_metadata()
		value["team"] = int(row["team"].value)
		players.append(value)
	return players


func _apply() -> void:
	_error.text = MapAuthoring.replace_players(_document, _data, player_rows())
	if _error.text == "":
		hide()
