class_name MapEntityPalette
extends VBoxContainer
## Catalogue is rebuilt from registered content; new entries need no UI code.
## Type buttons pick the kind of object, category tabs (faction, slot, kind)
## narrow the list, and the list is grouped under headings (tier, rarity).

signal place_requested

const TYPE_LABELS := {"town": "Towns", "hero": "Heroes", "mine": "Mines", "resource": "Resources",
	"neutral_army": "Monsters", "encounter": "Encounters", "artifact": "Artifacts", "site": "Sites"}

var type_buttons: Dictionary = {}
var tabs: MapCategoryTabs
var search: LineEdit
var items: ItemList
var owner_pick: OptionButton
var _owner_label: Label
var place_button: Button
var _data: GameData
var _document: MapDocument
var _players: Array = []
var _type := "town"
var _type_group := ButtonGroup.new()
## Last category per type, so switching types and back keeps the tab.
var _categories: Dictionary = {}


func build(data: GameData) -> void:
	_data = data
	add_theme_constant_override("separation", 6)
	add_child(UiStyle.label("OBJECTS & HEROES", 16, UiStyle.BRASS))
	var types := GridContainer.new()
	types.columns = 2
	types.add_theme_constant_override("h_separation", 4)
	types.add_theme_constant_override("v_separation", 4)
	add_child(types)
	for type in MapAuthoring.TYPES:
		var button := Button.new()
		button.text = str(TYPE_LABELS.get(type, str(type).capitalize()))
		button.toggle_mode = true
		button.button_group = _type_group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(func(): select_type(type))
		types.add_child(button)
		type_buttons[type] = button
	type_buttons[_type].set_pressed_no_signal(true)
	tabs = MapCategoryTabs.new()
	tabs.changed.connect(func(id):
		_categories[_type] = id
		_fill_items()
		_fill_owners())
	add_child(tabs)
	search = LineEdit.new()
	search.placeholder_text = "Search content"
	search.text_changed.connect(func(_text): _fill_items())
	add_child(search)
	items = ItemList.new()
	items.custom_minimum_size = Vector2(0, 220)
	items.fixed_icon_size = Vector2i(30, 30)
	items.fixed_column_width = 180
	items.max_columns = 1
	items.item_activated.connect(func(_index): place_requested.emit())
	items.item_selected.connect(func(_index): _fill_owners())
	add_child(items)
	_owner_label = UiStyle.label("Place for", 14, UiStyle.TEXT_DIM)
	add_child(_owner_label)
	owner_pick = OptionButton.new()
	add_child(owner_pick)
	place_button = Button.new()
	place_button.text = "Place selected"
	place_button.pressed.connect(func(): place_requested.emit())
	add_child(place_button)
	_fill_tabs()
	_fill_items()
	_fill_owners()


## Switches the object type, restoring that type's last category tab.
func select_type(value: String, tab: String = "") -> void:
	if not value in MapAuthoring.TYPES:
		return
	_type = value
	for key in type_buttons:
		type_buttons[key].set_pressed_no_signal(key == value)
	if tab != "":
		_categories[value] = tab
	_fill_tabs()
	_fill_items()
	_fill_owners()


func category() -> String:
	return tabs.current


func refresh(document: MapDocument, rebuild: bool = false) -> void:
	_document = document
	if rebuild:
		_fill_tabs()
		_fill_items()
	var next_players: Array = [] if document == null else document.definition()["players"]
	if next_players != _players or owner_pick.item_count == 0:
		_players = next_players.duplicate(true)
		_fill_owners()
	var locked := document != null and document.read_only()
	for button in type_buttons.values():
		button.disabled = locked
	tabs.set_locked(locked)
	search.editable = not locked
	items.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	owner_pick.disabled = locked
	place_button.disabled = locked or content() == ""


func type() -> String:
	return _type


func content() -> String:
	var selected := items.get_selected_items()
	return str(items.get_item_metadata(selected[0])) if not selected.is_empty() else ""


func selected_owner() -> int:
	return int(owner_pick.get_selected_metadata()) if owner_pick.item_count > 0 else -1


func _fill_tabs() -> void:
	tabs.set_categories(MapPaletteCatalog.categories(_data, _type), str(_categories.get(_type, MapPaletteCatalog.ALL)))


func _fill_items() -> void:
	var selected := content() if items.item_count > 0 else ""
	items.clear()
	var definitions := MapAuthoring.registry(_data, type())
	var heading := ""
	var first := -1
	for entry in MapPaletteCatalog.entries(_data, type(), tabs.current, search.text):
		var id: String = entry["id"]
		var definition: Dictionary = definitions[id]
		if entry["group"] != "" and entry["group"] != heading:
			heading = entry["group"]
			var index := items.add_item("— " + heading + " —", null, false)
			items.set_item_disabled(index, true)
			items.set_item_custom_fg_color(index, UiStyle.BRASS)
			items.set_item_metadata(index, "")
		items.add_item(entry["label"], _icon(id, definition))
		items.set_item_metadata(items.item_count - 1, id)
		items.set_item_tooltip(items.item_count - 1, str(id) + "\n" + str(definition.get("text", definition.get("desc", definition.get("description", "")))))
		if first < 0:
			first = items.item_count - 1
		if id == selected:
			items.select(items.item_count - 1)
	if first >= 0 and items.get_selected_items().is_empty():
		items.select(first)
	if place_button != null:
		place_button.disabled = first < 0 or (_document != null and _document.read_only())


func _fill_owners() -> void:
	var selected := selected_owner()
	owner_pick.clear()
	var owned := MapAuthoring.supports_owner(_data, type(), content())
	owner_pick.visible = owned
	_owner_label.visible = owned
	if type() != "hero":
		owner_pick.add_item("Neutral")
		owner_pick.set_item_metadata(0, -1)
	if _document != null:
		for player in _document.definition()["players"]:
			owner_pick.add_item("%d · %s" % [int(player["id"]) + 1, str(player.get("name", "Player"))])
			owner_pick.set_item_metadata(owner_pick.item_count - 1, player["id"])
			if player["id"] == selected:
				owner_pick.select(owner_pick.item_count - 1)
	if owner_pick.item_count == 0:
		owner_pick.add_item("Add a player first")
		owner_pick.set_item_metadata(0, -1)


func _icon(id: String, definition: Dictionary) -> Texture2D:
	match type():
		"town": return Art.sprite("town_" + id)
		"hero": return Art.hero(id)
		"neutral_army": return Art.creature(id)
		"resource": return Art.sprite("resource_" + id)
		"mine": return Art.sprite("mine_" + id)
		"encounter": return Art.sprite(EncounterSystem.sprite_id(id, GameData.get_default()))
		"site": return Art.sprite(str(definition.get("sprite", "")))
		"artifact": return Art.sprite("object_chest")
	return null
