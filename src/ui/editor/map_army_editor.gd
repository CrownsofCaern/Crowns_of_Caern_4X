class_name MapArmyEditor
extends VBoxContainer
## Edits authored creature/count pairs without instantiating or merging armies.
## Faction tabs (Wild last) and a search narrow every stack's creature list,
## which is ordered by tier with each upgrade after its base unit.

var _data: GameData
var _rows: Array[Dictionary] = []
var _list: VBoxContainer
var tabs: MapCategoryTabs
var _search: LineEdit
var _add: Button
var _invalid := false


## default_category is the tab to open on when the stacks don't already
## share one faction, e.g. the town's faction or "wilds" for guards.
func build(data: GameData, pairs: Variant, default_category: String = MapPaletteCatalog.ALL) -> void:
	_data = data
	add_theme_constant_override("separation", 6)
	tabs = MapCategoryTabs.new()
	tabs.set_categories(MapPaletteCatalog.categories(data, "neutral_army"), initial_category(data, pairs, default_category))
	tabs.changed.connect(func(_id): _refill())
	add_child(tabs)
	_search = LineEdit.new()
	_search.placeholder_text = "Search creatures"
	_search.text_changed.connect(func(_text): _refill())
	add_child(_search)
	_list = VBoxContainer.new()
	add_child(_list)
	_add = Button.new()
	_add.text = "Add stack"
	_add.pressed.connect(func(): _append([]))
	add_child(_add)
	_invalid = not pairs is Array
	if pairs is Array:
		for pair in pairs:
			if pair is Array and pair.size() >= 2:
				if not pair[0] is String or not MapDocument._integer(pair[1]):
					_invalid = true
				_append(pair)
			else:
				_invalid = true
	if _invalid:
		var reset := Button.new()
		reset.text = "Replace malformed stack data"
		reset.pressed.connect(func(): _invalid = false; reset.hide())
		add_child(reset)
	if _rows.is_empty():
		_append([])


func _append(pair: Array) -> void:
	var line := HBoxContainer.new()
	_list.add_child(line)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size.x = 280
	pick.clip_text = true
	line.add_child(pick)
	var count := SpinBox.new()
	count.min_value = 1
	count.max_value = 1000000
	count.allow_greater = true
	count.allow_lesser = true
	count.value = pair[1] if pair.size() >= 2 and (pair[1] is int or pair[1] is float) else 1
	count.custom_minimum_size.x = 120
	line.add_child(count)
	var remove := Button.new()
	remove.text = "Remove"
	line.add_child(remove)
	var id := str(pair[0]) if not pair.is_empty() else ""
	var row := {"pick": pick, "count": count, "original": pair.duplicate(true), "original_id": id}
	_rows.append(row)
	remove.pressed.connect(func():
		_rows.erase(row)
		_list.remove_child(line)
		line.queue_free()
		_add.disabled = _rows.size() >= Army.MAX_SLOTS)
	_fill(pick, id)
	_add.disabled = _rows.size() >= Army.MAX_SLOTS


## The faction all authored stacks share, else the default (mixed → All).
static func initial_category(data: GameData, pairs: Variant, default_category: String) -> String:
	var found := ""
	if pairs is Array:
		for pair in pairs:
			if not pair is Array or pair.is_empty() or not data.creatures.has(str(pair[0])):
				continue
			var faction := MapPaletteCatalog.category_of(data, "neutral_army", str(pair[0]))
			if found != "" and faction != found:
				return MapPaletteCatalog.ALL
			found = faction
	return found if found != "" else default_category


## Shows another tab, e.g. from tests or a caller that knows the faction.
func show_category(id: String) -> void:
	tabs.select(id)


func _refill() -> void:
	for row in _rows:
		_fill(row["pick"], str(row["pick"].get_selected_metadata()))


func _fill(pick: OptionButton, selected_id: String) -> void:
	pick.clear()
	pick.add_item("No stack")
	pick.set_item_metadata(0, "")
	var entries := MapPaletteCatalog.entries(_data, "neutral_army", tabs.current, _search.text)
	var listed := false
	for entry in entries:
		listed = listed or entry["id"] == selected_id
	if selected_id != "" and _data.creatures.has(selected_id) and not listed:
		# Keep the current choice visible even when the tab hides it.
		pick.add_item(MapPaletteCatalog.category_label(_data, "neutral_army", MapPaletteCatalog.category_of(_data, "neutral_army", selected_id)) + " · " + MapPaletteCatalog.entry_label(_data, "neutral_army", selected_id))
		pick.set_item_metadata(pick.item_count - 1, selected_id)
		pick.select(pick.item_count - 1)
	var heading := ""
	for entry in entries:
		if entry["group"] != heading:
			heading = entry["group"]
			pick.add_separator(heading)
		pick.add_item(entry["label"])
		pick.set_item_metadata(pick.item_count - 1, entry["id"])
		if entry["id"] == selected_id:
			pick.select(pick.item_count - 1)
	if selected_id != "" and not _data.creatures.has(selected_id):
		pick.add_item("Missing creature: " + selected_id)
		pick.set_item_metadata(pick.item_count - 1, selected_id)
		pick.select(pick.item_count - 1)


func problem() -> String:
	return "Replace malformed stack data explicitly before applying changes." if _invalid else ""


func pairs() -> Array:
	var out: Array = []
	for row in _rows:
		var id := str(row["pick"].get_selected_metadata())
		if id == "":
			continue
		var pair := [id, int(row["count"].value)]
		if row["original_id"] == id and row["original"].size() > 2:
			pair.append_array(row["original"].slice(2).duplicate(true))
		out.append(pair)
	return out
