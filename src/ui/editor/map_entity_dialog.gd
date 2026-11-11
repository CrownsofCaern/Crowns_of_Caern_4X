class_name MapEntityDialog
extends ConfirmationDialog
## Type-specific authored properties. Unknown fields and immutable IDs survive.

signal applied(id: String, hero: bool, pos: Vector2i)

var _data: GameData
var _body: VBoxContainer
var _error: Label
var _value: Dictionary
var _hero := false
var _type := ""
var _document: MapDocument
var _fields: Dictionary = {}
var _army: MapArmyEditor
var _army_key := ""
var _building_box: VBoxContainer
var _building_checks: Dictionary = {}
var _dwelling_box: VBoxContainer
var _content: OptionButton
var _content_original := ""


func build(data: GameData) -> void:
	_data = data
	theme = UiStyle.make_theme().duplicate()
	theme.set_stylebox("panel", "AcceptDialog", UiStyle.panel_box())
	var frame := ThemeDB.get_default_theme().get_stylebox("embedded_border", "Window").duplicate()
	if frame is StyleBoxFlat:
		frame.bg_color = UiStyle.PANEL_BG
		frame.border_color = UiStyle.BRASS.darkened(0.4)
	theme.set_stylebox("embedded_border", "Window", frame)
	title = "Entity properties"
	min_size = Vector2i(650, 540)
	dialog_hide_on_ok = false
	get_ok_button().text = "Apply"
	var outer := VBoxContainer.new()
	add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	_error = UiStyle.label("", 14, UiStyle.BAD)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size.x = 600
	outer.add_child(_error)
	confirmed.connect(_apply)


func open_entity(document: MapDocument, id: String, hero: bool) -> void:
	_document = document
	_value = document.entity(id, hero)
	if _value.is_empty() or document.read_only():
		return
	_hero = hero
	_type = "hero" if hero else str(_value["type"])
	_fields.clear()
	_building_checks.clear()
	_army = null
	_building_box = null
	_dwelling_box = null
	_content = null
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_error.text = ""
	title = _type.capitalize() + " properties · " + id
	var name_edit := LineEdit.new()
	name_edit.text = str(_value.get("name", id))
	_field("Name", name_edit)
	var pos: Array = _value["pos"]
	var bounds := document.definition()
	_field("X", _number(pos[0], 0, int(bounds["width"]) - 1))
	_field("Y", _number(pos[1], 0, int(bounds["height"]) - 1))
	if _value.has("owner") or _type in MapAuthoring.OWNED_TYPES:
		var owners := {}
		if not hero:
			owners[-1] = "Neutral"
		for player in bounds["players"]:
			owners[player["id"]] = "Player %d · %s" % [int(player["id"]) + 1, str(player.get("name", ""))]
		_field("Owner", _choice(owners, _value.get("owner", -1)))
		if _type == "site":
			_fields["Owner"].get_parent().visible = MapAuthoring.supports_owner(_data, _type, str(_value.get("site", "")))
	var content_field := MapAuthoring.content_field(_type)
	if content_field != "":
		_content_original = str(_value.get(content_field, ""))
		_content = _choice(_labels(MapAuthoring.registry(_data, _type)), _content_original)
		_field(content_field.capitalize(), _content)
		_content.item_selected.connect(func(_index): _content_changed())
	if _type == "resource" or _value.has("amount"):
		_field("Amount", _number(_value.get("amount", 1), 1, 1000000))
	if not hero and _type != "neutral_army":
		var guards := {"": "None"}
		for object in bounds["objects"]:
			if object.get("type") == "neutral_army" and object["id"] != id:
				guards[object["id"]] = str(object.get("name", object["id"])) + " · " + str(object["id"])
		_field("Guarded by", _choice(guards, _value.get("guarded_by", "")))
	_army_key = {"hero": "army", "town": "garrison", "neutral_army": "stacks", "mine": "guard", "site": "guard"}.get(_type, "")
	if _type == "town":
		_add_army()
	if _type == "town":
		_building_box = VBoxContainer.new()
		_body.add_child(UiStyle.label("Built buildings", 16, UiStyle.BRASS))
		_body.add_child(_building_box)
		_fill_buildings(_content_original, _value.get("built", _data.town_types.get(_content_original, {}).get("starting_buildings", [])))
	if _type == "site":
		_dwelling_box = VBoxContainer.new()
		_body.add_child(_dwelling_box)
		_fill_dwelling(_content_original, _value)
	if _type != "town":
		_add_army()
	popup_centered(Vector2i(650, 540))


func _add_army() -> void:
	if _army_key == "":
		return
	_body.add_child(UiStyle.label(_army_key.capitalize(), 16, UiStyle.BRASS))
	_army = MapArmyEditor.new()
	_body.add_child(_army)
	_army.build(_data, _value.get(_army_key, []), _army_category())


## The faction tab a stack editor opens on: the town's or hero's own faction,
## and the wild creatures for neutral armies and guards.
func _army_category() -> String:
	match _type:
		"town": return str(_value.get("town_type", MapPaletteCatalog.ALL))
		"hero": return str(_data.hero_classes.get(str(_value.get("class", "")), {}).get("faction", MapPaletteCatalog.ALL))
	# Guards are wild creatures; other neutral peoples (the cobolts) only
	# garrison their own trading posts.
	if _data.factions.has("wilds"):
		return "wilds"
	for faction in MapPaletteCatalog.faction_order(_data):
		if bool(_data.factions[faction].get("neutral", false)):
			return faction
	return MapPaletteCatalog.ALL


func _field(label: String, control: Control, parent: Node = null) -> void:
	var target := _body if parent == null else parent
	var line := HBoxContainer.new()
	var caption := UiStyle.label(label, 14, UiStyle.TEXT_DIM)
	caption.custom_minimum_size.x = 130
	line.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(control)
	target.add_child(line)
	_fields[label] = control


func _number(value: Variant, minimum: int, maximum: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = value if value is int or value is float else minimum
	return spin


func _choice(options: Dictionary, selected: Variant) -> OptionButton:
	var pick := OptionButton.new()
	pick.clip_text = true
	for id in options:
		pick.add_item(str(options[id]))
		pick.set_item_metadata(pick.item_count - 1, id)
		if id == selected:
			pick.select(pick.item_count - 1)
	if not options.has(selected):
		pick.add_item("Choose / missing: " + str(selected))
		pick.set_item_metadata(pick.item_count - 1, selected)
		pick.select(pick.item_count - 1)
	return pick


func _labels(definitions: Dictionary) -> Dictionary:
	var out := {}
	var ids := definitions.keys()
	ids.sort()
	for id in ids:
		out[id] = str(definitions[id].get("name", id))
	return out


func _fill_buildings(town_type: String, built: Variant) -> void:
	for child in _building_box.get_children():
		_building_box.remove_child(child)
		child.queue_free()
	_building_checks.clear()
	var definitions: Dictionary = _data.town_types.get(town_type, {}).get("buildings", {})
	var ids := definitions.keys()
	ids.sort()
	if built is Array:
		for id in built:
			if not ids.has(id):
				ids.append(id)
	for id in ids:
		var check := CheckBox.new()
		check.text = str(definitions.get(id, {}).get("name", "Missing: " + str(id)))
		check.button_pressed = built is Array and built.has(id)
		_building_box.add_child(check)
		_building_checks[id] = check


func _fill_dwelling(site: String, original: Dictionary) -> void:
	for child in _dwelling_box.get_children():
		_dwelling_box.remove_child(child)
		child.queue_free()
	_fields.erase("Creature")
	_fields.erase("Starting recruits")
	_fields.erase("Spell")
	if _data.sites.get(site, {}).get("kind") == "spell":
		var options := {}
		var ids: Array = _data.magic.get("spells", {}).keys()
		ids.sort()
		for id in ids:
			if _data.magic["spells"][id].get("source") == "rare":
				options[id] = _data.magic["spells"][id].get("name", id)
		_field("Spell", _choice(options, original.get("spell", options.keys()[0] if not options.is_empty() else "")), _dwelling_box)
		return
	if _data.sites.get(site, {}).get("kind") != "dwelling":
		return
	var pool := MapSites.creature_pool(_data.sites[site], _data)
	var options := {}
	for id in pool:
		options[id] = str(_data.creatures[id].get("name", id))
	_field("Creature", _choice(options, original.get("creature", pool[0] if not pool.is_empty() else "")), _dwelling_box)
	var count: Variant = original.get("available", 0)
	if not original.has("available") and not pool.is_empty():
		count = int(_data.creatures[pool[0]].get("growth", 0))
	_field("Starting recruits", _number(count, 0, 1000000), _dwelling_box)


func _content_changed() -> void:
	var id := str(_content.get_selected_metadata())
	if _type == "town":
		_fill_buildings(id, _data.town_types.get(id, {}).get("starting_buildings", []))
	elif _type == "site":
		_fill_dwelling(id, {})
		_fields["Owner"].get_parent().visible = MapAuthoring.supports_owner(_data, _type, id)


func edited_value() -> Dictionary:
	var value := _value.duplicate(true)
	value["name"] = _fields["Name"].text
	value["pos"] = [int(_fields["X"].value), int(_fields["Y"].value)]
	if _fields.has("Owner") and _fields["Owner"].get_parent().visible:
		value["owner"] = _fields["Owner"].get_selected_metadata()
	elif _type == "site" and str(_content.get_selected_metadata()) != _content_original:
		value.erase("owner")
	if _content != null:
		var id := str(_content.get_selected_metadata())
		value[MapAuthoring.content_field(_type)] = id
		if id != _content_original:
			value.erase("sprite")
	if _fields.has("Amount"):
		value["amount"] = int(_fields["Amount"].value)
	if _fields.has("Guarded by"):
		var guard := str(_fields["Guarded by"].get_selected_metadata())
		if guard == "":
			value.erase("guarded_by")
		else:
			value["guarded_by"] = guard
	if _building_box != null:
		value["built"] = []
		for id in _building_checks:
			if _building_checks[id].button_pressed:
				value["built"].append(id)
	if _fields.has("Creature"):
		value["creature"] = str(_fields["Creature"].get_selected_metadata())
		value["available"] = int(_fields["Starting recruits"].value)
	elif _type == "site" and str(_content.get_selected_metadata()) != _content_original:
		value.erase("creature")
		value.erase("available")
	if _fields.has("Spell"):
		value["spell"] = str(_fields["Spell"].get_selected_metadata())
	elif _type == "site" and str(_content.get_selected_metadata()) != _content_original:
		value.erase("spell")
	if _army != null:
		value[_army_key] = _army.pairs()
	return value


func _apply() -> void:
	if _army != null and _army.problem() != "":
		_error.text = _army.problem()
		return
	_error.text = MapAuthoring.store(_document, _data, edited_value(), _hero, str(_value["id"]))
	if _error.text == "":
		applied.emit(str(_value["id"]), _hero, AdventureMap.object_pos(edited_value()))
		hide()
