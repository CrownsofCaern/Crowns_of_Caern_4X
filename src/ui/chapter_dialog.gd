class_name ChapterDialog
extends ModalPanel
## Campaign chapter briefing: the campaign, the chapter's name and orders, the
## veterans who march in it, and a button to take the field. With a chapter
## illustration (CampaignArt) the dialog widens and shows it beside the text.

signal begin_pressed

const ART_SIZE := Vector2(480, 320)     # the illustrations are 3:2
const ART_TEXT_WIDTH := 500.0

var _narrow_width := -1.0


func open(title: String, subtitle: String, lines: Array, button: String = "Take the field", art: Texture2D = null) -> void:
	_clear()
	if _narrow_width < 0.0:
		_narrow_width = _panel.custom_minimum_size.x
	_panel.custom_minimum_size.x = _narrow_width if art == null else ART_SIZE.x + ART_TEXT_WIDTH + 40.0
	_panel.reset_size()
	_body.add_child(UiStyle.label(title, 26, UiStyle.BRASS))
	_body.add_child(UiStyle.label(subtitle, 14, UiStyle.TEXT_DIM))
	_body.add_child(HSeparator.new())
	if art == null:
		for line in lines:
			_body.add_child(_wrapped(String(line), 14))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var pic := TextureRect.new()
		pic.name = "ChapterArt"
		pic.texture = art
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pic.custom_minimum_size = ART_SIZE
		pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(pic)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 8)
		for line in lines:
			var l := UiStyle.label(String(line), 14, UiStyle.TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = ART_TEXT_WIDTH
			text.add_child(l)
		row.add_child(text)
		_body.add_child(row)
	_buttons([[button, func():
		hide()
		begin_pressed.emit()]])
	show()
	UiStyle.fade_in(self)


## The illustration shown, or null (for tests and screenshots).
func art_rect() -> TextureRect:
	return _body.find_child("ChapterArt", true, false) as TextureRect
