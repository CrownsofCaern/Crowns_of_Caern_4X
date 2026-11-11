class_name GameOverDialog
extends ModalPanel
## End-of-game screen: victory or defeat, how it ended, and the standings.

signal main_menu_pressed
signal view_map_pressed
## The campaign button: next chapter after a win, retry after a loss.
signal campaign_pressed


## campaign: {title, lines: [String], action: button text or "", art: the won
## chapter's illustration or null} for a campaign chapter (what carried over,
## what comes next); empty for a skirmish.

const CAMPAIGN_ART_SIZE := Vector2(330, 220)   # the illustrations are 3:2

var _narrow_width := -1.0


func open(result: Dictionary, campaign: Dictionary = {}) -> void:
	_clear()
	# A chapter illustration sits beside the campaign text: the panel widens by
	# its width, so the standings and the text keep their usual measure.
	if _narrow_width < 0.0:
		_narrow_width = _panel.custom_minimum_size.x
	var art := campaign.get("art") as Texture2D
	_panel.custom_minimum_size.x = _narrow_width if art == null else _narrow_width + CAMPAIGN_ART_SIZE.x + 14.0
	_panel.reset_size()
	var won: bool = result["human_won"]
	var title := UiStyle.label(String(result["title"]).to_upper(), 34, UiStyle.BRASS if won else UiStyle.BAD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color("#1a0805"))
	title.add_theme_constant_override("outline_size", 8)
	_body.add_child(title)
	var text := _wrapped(result["text"], 15)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(text)
	_body.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	for h in ["Player", "Faction", "Towns", "Heroes", "Mines", "Fate"]:
		grid.add_child(UiStyle.label(h, 12, UiStyle.TEXT_DIM))
	for row in result["standings"]:
		var col := UiStyle.TEXT if not row["defeated"] else UiStyle.TEXT_DIM
		var level: String = _data.difficulty(String(row.get("difficulty", ""))).get("name", "")
		var who := "%s%s" % [row["name"], "" if row["is_human"] else " (computer, %s)" % level.to_lower()]
		if int(row.get("team", 0)) > 0:
			who += "  [team %d]" % int(row["team"])
		var victor: bool = row.get("won", row["player"] == result["winner"])
		grid.add_child(UiStyle.label(who, 14, UiStyle.BRASS if victor else col))
		grid.add_child(UiStyle.label(_data.factions[row["faction"]]["name"], 13, col))
		grid.add_child(UiStyle.label(str(row["towns"]), 14, col))
		grid.add_child(UiStyle.label(str(row["heroes"]), 14, col))
		grid.add_child(UiStyle.label(str(row["mines"]), 14, col))
		var fate := "Victor" if victor else ("Fell on day %d" % row["eliminated_day"] if row["defeated"] else "Survived")
		grid.add_child(UiStyle.label(fate, 14, UiStyle.GOOD if victor else (UiStyle.BAD if row["defeated"] else col)))
	_body.add_child(grid)
	_body.add_child(UiStyle.label("The war lasted %s." % VictoryRules._days(int(result["day"])), 13, UiStyle.TEXT_DIM))
	var buttons := [["View map", func():
		hide()
		view_map_pressed.emit()], ["Main menu", func():
		hide()
		main_menu_pressed.emit()]]
	if not campaign.is_empty():
		_body.add_child(HSeparator.new())
		var text_box: Container = _body
		if art != null:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			var pic := TextureRect.new()
			pic.name = "ChapterArt"
			pic.texture = art
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			pic.custom_minimum_size = CAMPAIGN_ART_SIZE
			pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(pic)
			text_box = VBoxContainer.new()
			text_box.add_theme_constant_override("separation", 6)
			text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(text_box)
			_body.add_child(row)
		text_box.add_child(UiStyle.label(String(campaign.get("title", "")), 17, UiStyle.BRASS))
		for line in campaign.get("lines", []):
			var l := _wrapped(String(line), 13)
			l.custom_minimum_size.x = _narrow_width - 24.0
			text_box.add_child(l)
		if String(campaign.get("action", "")) != "":
			buttons.append([String(campaign["action"]), func():
				hide()
				campaign_pressed.emit()])
	_buttons(buttons)
	show()
	UiStyle.fade_in(self)


## The chapter illustration on a campaign end screen, or null (for tests).
func art_rect() -> TextureRect:
	return _body.find_child("ChapterArt", true, false) as TextureRect
