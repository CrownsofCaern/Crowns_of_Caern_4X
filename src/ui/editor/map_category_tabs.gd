class_name MapCategoryTabs
extends HFlowContainer
## A wrapping row of toggle buttons that works like tabs in a narrow panel.
## Fed by MapPaletteCatalog.categories(); hidden when there is nothing to pick.

signal changed(id: String)

var current := MapPaletteCatalog.ALL
var _buttons: Dictionary = {}
var _group := ButtonGroup.new()


func _init() -> void:
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)


func set_categories(categories: Array[Dictionary], selected: String = MapPaletteCatalog.ALL) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_group = ButtonGroup.new()
	visible = categories.size() > 2
	for category in categories:
		var button := Button.new()
		button.text = str(category["label"])
		button.tooltip_text = str(category.get("tooltip", ""))
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		var id := str(category["id"])
		button.pressed.connect(func(): _choose(id))
		add_child(button)
		_buttons[id] = button
	select(selected if _buttons.has(selected) else MapPaletteCatalog.ALL, false)


func select(id: String, notify: bool = true) -> void:
	if not _buttons.has(id):
		id = MapPaletteCatalog.ALL
	current = id
	for key in _buttons:
		_buttons[key].set_pressed_no_signal(key == id)
	if notify:
		changed.emit(id)


func has_category(id: String) -> bool:
	return _buttons.has(id)


func set_locked(locked: bool) -> void:
	for button in _buttons.values():
		button.disabled = locked


func _choose(id: String) -> void:
	if id != current:
		select(id)
