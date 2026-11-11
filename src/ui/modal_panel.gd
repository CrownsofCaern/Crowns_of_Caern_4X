class_name ModalPanel
extends Control
## Base for centred modal dialogs: dimmed backdrop, brass-framed panel, a
## vertical body that subclasses fill, and a right-aligned button row helper.

var _data: GameData
var _panel: PanelContainer
var _body: VBoxContainer
## Phones: button rows go here, below the scrolling body (TouchLayout.fit_dialog).
var _footer: VBoxContainer
var _menu_art_background: TextureRect


func build(data: GameData, width: float = 560.0) -> void:
	_data = data
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.make_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(width, 0)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	if TouchGestures.touch_ui():
		_footer = TouchLayout.fit_dialog(self, _panel, _body)
	else:
		center.add_child(_panel)
		_panel.add_child(_body)
	hide()


func _clear() -> void:
	for box in [_body, _footer]:
		if box == null:
			continue
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()


func _wrapped(text: String, size: int = 14, color: Color = UiStyle.TEXT) -> Label:
	var l := UiStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _panel.custom_minimum_size.x - 24
	return l


func _buttons(specs: Array) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	for s in specs:
		var b := Button.new()
		b.text = s[0]
		b.tooltip_text = String(s[2]) if s.size() > 2 else ""
		b.disabled = bool(s[3]) if s.size() > 3 else false
		b.custom_minimum_size = Vector2(130, 36)
		b.pressed.connect(s[1])
		row.add_child(b)
	(_footer if _footer != null else _body).add_child(row)


func set_menu_background(id: String) -> void:
	if _menu_art_background == null:
		_menu_art_background = MenuArt.backdrop(id)
		add_child(_menu_art_background)
		move_child(_menu_art_background, 0)
	else:
		_menu_art_background.texture = MenuArt.texture(id)
