class_name CampaignJourneyScreen
extends Control
## Regional paintings replace chapter lists; Campaign remains the authority on unlocks/saves.
signal back_requested
signal campaign_requested(campaign_id: String, fresh: bool)

var data: GameData
var catalog: Dictionary
var campaign_id := ""
var progress: Campaign
var had_save := false
var journey: CampaignJourneyMap
var picker: OptionButton
var title: Label
var state_label: Label
var description: Label
var limits: Label
var veterans: Label
var go: Button
var restart: Button
var confirm_restart: ConfirmationDialog
var content: BoxContainer
var details: PanelContainer
var ids: Array = []
var motion: CheckButton


func build(game_data: GameData) -> void:
	data = game_data
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/campaign_journeys.json"))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("101116")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	column.add_child(bar)
	var back := Button.new()
	back.text = "‹ Back"
	back.custom_minimum_size = Vector2(90, 44)
	back.pressed.connect(func(): back_requested.emit())
	bar.add_child(back)
	picker = OptionButton.new()
	picker.name = "CampaignPicker"
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.y = 44
	ids = data.campaigns.keys()
	ids.sort()
	for id in ids:
		picker.add_icon_item(Art.faction_emblem_icon(data.campaigns[id]["faction"]), data.campaigns[id]["name"])
	picker.item_selected.connect(func(index: int): show_campaign(ids[index]))
	bar.add_child(picker)
	motion = CheckButton.new()
	motion.text = "Hero motion"
	motion.button_pressed = true
	motion.tooltip_text = "Animate the hero travelling to the current chapter"
	bar.add_child(motion)
	content = BoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	column.add_child(content)
	journey = CampaignJourneyMap.new()
	journey.name = "JourneyMap"
	journey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journey.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journey.custom_minimum_size = Vector2(220, 220)
	journey.stop_selected.connect(_show_stop)
	content.add_child(journey)
	motion.toggled.connect(func(enabled: bool): journey.animate_travel = enabled)
	details = PanelContainer.new()
	details.custom_minimum_size.x = 330
	content.add_child(details)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.add_child(scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 14)
	scroll.add_child(inset)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 14)
	inset.add_child(info)
	title = _text(info, 23, UiStyle.BRASS)
	title.add_theme_font_override("font", preload("res://assets/fonts/Cinzel.ttf"))
	state_label = _text(info, 15, UiStyle.BRASS)
	description = _text(info, 16, UiStyle.TEXT)
	limits = _text(info, 13, UiStyle.TEXT_DIM)
	veterans = _text(info, 13, UiStyle.TEXT_DIM)
	go = Button.new()
	go.name = "PlaySelectedChapter"
	go.custom_minimum_size.y = 48
	go.pressed.connect(_launch_selected)
	info.add_child(go)
	restart = Button.new()
	restart.text = "Start over"
	restart.custom_minimum_size.y = 44
	restart.pressed.connect(func(): confirm_restart.popup_centered())
	info.add_child(restart)
	var legend := _text(info, 12, UiStyle.TEXT_DIM)
	legend.text = "Green: won · Gold: current · Grey: locked\nSelect a stop to read its story. Dashed routes travel underground."
	confirm_restart = ConfirmationDialog.new()
	confirm_restart.title = "Restart campaign?"
	confirm_restart.dialog_text = "Replace this campaign's saved progress and begin at chapter 1?"
	confirm_restart.confirmed.connect(func(): campaign_requested.emit(campaign_id, true))
	add_child(confirm_restart)
	resized.connect(_responsive_layout)
	_responsive_layout()


func _text(parent: Node, font_size: int, color: Color) -> Label:
	var label := UiStyle.label("", font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _responsive_layout() -> void:
	if content == null:
		return
	if motion != null:
		motion.text = "Hero motion" if size.x >= 600 else ""
	var portrait := size.x < 900
	content.vertical = portrait
	details.custom_minimum_size = Vector2(0, 230) if portrait else Vector2(330, 0)
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_FILL


func open() -> void:
	show()
	show_campaign(campaign_id if campaign_id != "" else "last_light")


func show_campaign(id: String, override_progress: Campaign = null) -> void:
	campaign_id = id
	picker.select(ids.find(id))
	var saved := override_progress if override_progress != null else Campaign.load_progress(data, id)
	had_save = saved != null
	progress = saved if saved != null else Campaign.start(data, id, 1)
	var definition: Dictionary = data.campaigns[id]
	var hero_id: String = definition["heroes"][0]
	var sprite := Art.hero_sprite_id(Art.CAMPAIGN_PORTRAIT_CLASSES.get(hero_id, "knight"))
	var record: Dictionary = catalog["campaigns"].get(id, {})
	var stops: Array = record.get("nodes", [])
	if stops.is_empty():
		var chapters: Array = definition["chapters"]
		for i in chapters.size():
			stops.append({"chapter": chapters[i]["id"], "layer": "surface",
				"at": [0.2 + 0.6 * i / maxf(1.0, chapters.size() - 1), 0.5]})
	journey.configure(CampaignArt.texture(id, "", "journey"), stops, progress.chapter_list(data), progress.chapter, sprite, Color(data.factions[definition["faction"]]["color"]).lightened(.25))
	restart.visible = had_save
	veterans.text = "Veterans: " + "; ".join(progress.roster_lines(data)) if not progress.roster.is_empty() else ""
	veterans.visible = not veterans.text.is_empty()
	_show_stop(journey.selected)


func _show_stop(index: int) -> void:
	if progress == null:
		return
	var chapter: Dictionary = progress.chapter_list(data)[index]
	title.text = chapter["name"]
	var status: String = {"done":"Won", "current":"Current destination", "locked":"Locked — complete earlier chapters"}[chapter["state"]]
	state_label.text = "Chapter %d of %d\n%s" % [index + 1, progress.definition(data)["chapters"].size(), status]
	description.text = chapter["text"]
	limits.text = "Hero level cap %d" % chapter["level_cap"]
	if int(chapter["max_tier"]) > 0:
		limits.text += " · creatures up to tier %d" % chapter["max_tier"]
	go.disabled = chapter["state"] != "current"
	if progress.is_finished(data):
		go.text = "Campaign complete"
	elif chapter["state"] == "locked":
		go.text = "Destination locked"
	elif chapter["state"] == "done":
		go.text = "Chapter won"
	elif not had_save:
		go.text = "Begin campaign"
	elif not progress.active_game.is_empty():
		go.text = "Continue chapter %d" % (index + 1)
	else:
		go.text = "Play chapter %d" % (index + 1)


func _launch_selected() -> void:
	if progress == null or progress.is_finished(data) or journey.selected != progress.chapter:
		return
	campaign_requested.emit(campaign_id, not had_save)
