class_name MainMenu
extends Control
## Title screen: new game (map, player slots, factions, seed), campaign, load, quit.
## Emits the player's choice; the AdventureScreen starts or loads the game.

signal start_requested(map_id: String, seed_value: int, setup: Dictionary)
signal load_requested
signal resume_requested
signal quit_requested
signal sound_requested
signal editor_requested
signal editor_return_requested
## fresh: start the campaign over; otherwise continue its saved progress.
signal campaign_requested(campaign_id: String, fresh: bool)

const DISPLAY_FONT := preload("res://assets/fonts/Cinzel.ttf")
const BODY_FONT := preload("res://assets/fonts/Lora.ttf")

const TYPES := ["human", "computer", "closed"]
const TYPE_NAMES := {"human": "Human", "computer": "Computer", "closed": "Closed"}

var _data: GameData
var _maps: Array = []
var _home: VBoxContainer
var _setup_panel: PanelContainer
var _resume_btn: Button
var _return_editor_btn: Button
var _mode_pick: OptionButton
var _map_pick: OptionButton
var _map_info: Label
var _map_preview: Minimap
var _preview_legend: VBoxContainer
var _preview_timer: Timer
var _preview_seed := 0
var _preview_map_id := ""
var _preview_definition: Dictionary = {}
## Random-map options (shown when a random entry is picked): size, players,
## layout, teams, monsters, treasure.
var _random_row: Container
var _random_picks: Dictionary = {}   # option -> OptionButton
var _random_keys: Dictionary = {}    # option -> [key per item]
var _random_fields: Dictionary = {}  # option -> the field (caption and picker)
var _slots_box: GridContainer
var _seed_edit: LineEdit
var _hard_check: CheckBox
var _error: Label
var _setup_scroll: ScrollContainer
var _setup_footer: VBoxContainer
var _player_tabs: TabContainer
var _start_btn: Button
var _slot_rows: Array = []   # [{type: OptionButton, faction: OptionButton, difficulty: OptionButton}]
var _campaign_panel: CampaignJourneyScreen
var _art_background: TextureRect
var _wordmark: TextureRect
var _brand_label: Label
var _brand_gap: Control


func build(data: GameData) -> void:
	_data = data
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _menu_theme()
	var bg := ColorRect.new()
	bg.color = Color("#0b0a09")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_art_background = MenuArt.backdrop("title")
	add_child(_art_background)
	if is_inside_tree():
		get_window().title = MenuArt.TITLE
	var glow := TextureRect.new()
	glow.texture = _ember_gradient()
	glow.set_meta("ui_faction_glow", true)
	glow.self_modulate = UiStyle.accent()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if TouchGestures.touch_ui():
		TouchLayout.scroll_host(self).add_child(center)
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	_wordmark = TextureRect.new()
	_wordmark.texture = MenuArt.texture("wordmark")
	_wordmark.custom_minimum_size = (Vector2(600, 120) if TouchGestures.touch_ui() else Vector2(780, 260))
	_wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wordmark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wordmark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wordmark.visible = _wordmark.texture != null
	col.add_child(_wordmark)
	_brand_label = UiStyle.label(MenuArt.TITLE.to_upper(), 48, UiStyle.BRASS)
	_brand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brand_label.add_theme_color_override("font_outline_color", Color("#100b08"))
	_brand_label.add_theme_constant_override("outline_size", 4)
	_brand_label.visible = _wordmark.texture == null
	col.add_child(_brand_label)
	_brand_gap = _spacer(12)
	col.add_child(_brand_gap)

	_home = VBoxContainer.new()
	_home.add_theme_constant_override("separation", 10)
	_home.alignment = BoxContainer.ALIGNMENT_CENTER
	_home.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_home)
	_resume_btn = _menu_button("Resume", func(): resume_requested.emit())
	_return_editor_btn = _menu_button("Return to Editor", func(): editor_return_requested.emit())
	_return_editor_btn.hide()
	_menu_button("New Game", _show_setup)
	_menu_button("Campaign", show_campaigns)
	_menu_button("Load Game", func(): load_requested.emit())
	_menu_button("Map Editor", func(): editor_requested.emit())
	_menu_button("Sound", func(): sound_requested.emit())
	_menu_button("Quit", func(): quit_requested.emit())

	_setup_panel = PanelContainer.new()
	if TouchGestures.touch_ui():
		add_child(_setup_panel)
		TouchLayout.inset_full_rect(_setup_panel, 6)
	else:
		_setup_panel.custom_minimum_size = Vector2(800, 0)
		col.add_child(_setup_panel)
	_build_setup()
	_setup_panel.hide()
	_campaign_panel = CampaignJourneyScreen.new()
	add_child(_campaign_panel)
	_campaign_panel.build(_data)
	_campaign_panel.campaign_requested.connect(func(id: String, fresh: bool): campaign_requested.emit(id, fresh))
	_campaign_panel.back_requested.connect(func():
		_campaign_panel.hide()
		_home.show()
		_set_menu_screen("title"))
	_campaign_panel.hide()

	UiStyle.enlarge_touch_controls(self)
	hide()


## Menu-local theme: leave the rest of the game's faction UI unchanged.
func _menu_theme() -> Theme:
	var t := Theme.new()
	t.merge_with(UiStyle.make_theme())
	t.default_font = BODY_FONT
	t.set_font("font", "Button", DISPLAY_FONT)
	t.set_font("font", "OptionButton", BODY_FONT)
	# CheckBox inherits Button; keep its indicator and avoid a full-width plaque.
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		t.set_icon(icon, "CheckBox", _check_icon(icon.begins_with("checked"), icon.ends_with("disabled")))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {"normal": Color("#211c18ed"), "hover": Color("#3b2e20f5"),
			"pressed": Color("#15110ff5"), "disabled": Color("#201c1bc9")}[state]
		box.border_color = {"normal": Color("#826c45"), "hover": Color("#d4b46b"),
			"pressed": Color("#b08a4d"), "disabled": Color("#524a3a")}[state]
		box.set_border_width_all(1)
		box.set_corner_radius_all(1)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		box.shadow_color = Color(0, 0, 0, 0.6)
		box.shadow_size = 3
		t.set_stylebox(state, "Button", box)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#e6c67c")
	focus.set_border_width_all(2)
	focus.set_content_margin_all(0)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color("#eadcba"))
	t.set_color("font_hover_color", "Button", Color("#fff0c8"))
	t.set_color("font_pressed_color", "Button", Color("#d8b879"))
	t.set_color("font_disabled_color", "Button", Color("#887d6b"))
	t.set_color("font_outline_color", "Button", Color("#17100b"))
	t.set_constant("outline_size", "Button", 1)
	return t


func _check_icon(checked: bool, disabled: bool) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var edge := Color("#6d6046") if disabled else Color("#b69a61")
	var fill := Color("#211c18")
	for y in range(16):
		for x in range(16):
			image.set_pixel(x, y, edge if x == 0 or y == 0 or x == 15 or y == 15 else fill)
	if checked:
		var ink := Color("#e2c27a") if not disabled else Color("#847861")
		for point in [Vector2i(3, 8), Vector2i(4, 9), Vector2i(5, 10), Vector2i(6, 11),
				Vector2i(7, 10), Vector2i(8, 9), Vector2i(9, 8), Vector2i(10, 7),
				Vector2i(11, 6), Vector2i(12, 5)]:
			image.set_pixelv(point, ink)
			image.set_pixelv(point + Vector2i(0, 1), ink)
	return ImageTexture.create_from_image(image)


func _heading(text: String, font_size: int) -> Label:
	var heading := UiStyle.label(text, font_size, UiStyle.BRASS)
	heading.add_theme_font_override("font", DISPLAY_FONT)
	return heading


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(292, 45)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_font_override("font", DISPLAY_FONT)
	b.pressed.connect(cb)
	_home.add_child(b)
	return b


static func _ember_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.16))
	g.set_color(1, Color(0, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 1.05)
	t.fill_to = Vector2(0.5, 0.2)
	t.width = 256
	t.height = 256
	return t


## Shows the title screen; can_resume adds "Resume" for a game in progress.
## playtest: an editor playtest offers only Resume, Return to Editor, Load Game and Sound.
func open(can_resume: bool, playtest: bool = false) -> void:
	_set_menu_screen("title")
	for child in _home.get_children():
		if child is Button:
			child.visible = not playtest or child.text in ["Resume", "Return to Editor", "Load Game", "Sound"]
	_return_editor_btn.visible = playtest
	_resume_btn.visible = can_resume
	_setup_panel.hide()
	_campaign_panel.hide()
	_home.show()
	show()
	AudioManager.set_music("menu")


# ------------------------------------------------------------- new game --

func _build_setup() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_setup_panel.add_child(root)
	root.add_child(_heading("New Game", 23))
	# The form scrolls; the error line and Back/Begin stay fixed below it (_setup_footer).
	_setup_scroll = ScrollContainer.new()
	_setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if TouchGestures.touch_ui():
		_setup_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		_setup_scroll.custom_minimum_size = Vector2(1140, 540)
	root.add_child(_setup_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12 if TouchGestures.touch_ui() else 10)
	_setup_scroll.add_child(v)
	var mode_row := HBoxContainer.new()
	v.add_child(mode_row)
	mode_row.add_child(UiStyle.label("Mode", 15, UiStyle.TEXT_DIM))
	_mode_pick = OptionButton.new()
	_mode_pick.tooltip_text = "What kind of game: a conquest, or one of the generated missions."
	for mode in GameSetup.MODES:
		if mode != "conquest" and ScenarioGenerator.current_recipe(_data, mode) == "":
			continue
		_mode_pick.add_item(String(GameSetup.MODE_NAMES[mode]))
		_mode_pick.set_item_metadata(_mode_pick.item_count - 1, mode)
		_mode_pick.set_item_tooltip(_mode_pick.item_count - 1, String(GameSetup.MODE_TEXT[mode]))
	_mode_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_pick.item_selected.connect(func(_i): _refresh_map_choices())
	_prepare_picker(_mode_pick)
	mode_row.add_child(_mode_pick)
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 10)
	v.add_child(map_row)
	map_row.add_child(UiStyle.label("Map", 15, UiStyle.TEXT_DIM))
	_map_pick = OptionButton.new()
	_map_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_pick.item_selected.connect(func(_i): _fill_slots())
	_prepare_picker(_map_pick)
	map_row.add_child(_map_pick)
	if TouchGestures.touch_ui():
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		_random_row = grid
	else:
		_random_row = HBoxContainer.new()
	_random_row.add_theme_constant_override("separation", 16)
	v.add_child(_random_row)
	_build_random_row()
	var overview := HBoxContainer.new()
	overview.add_theme_constant_override("separation", 18)
	v.add_child(overview)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	overview.add_child(frame)
	_map_preview = Minimap.new()
	frame.add_child(_map_preview)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_child(details)
	details.add_child(UiStyle.label("Map overview", 17, UiStyle.BRASS))
	_map_info = UiStyle.label("", 13, UiStyle.TEXT_DIM)
	details.add_child(_map_info)
	_preview_legend = VBoxContainer.new()
	details.add_child(_preview_legend)
	var key := UiStyle.label("Numbered circles: player starts · squares: towns\nDiamonds: mines · crosses: sites and encounters", 12, UiStyle.TEXT_DIM)
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(key)
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.35
	_preview_timer.timeout.connect(_refresh_preview)
	add_child(_preview_timer)
	_map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(HSeparator.new())
	_slots_box = GridContainer.new()
	_slots_box.columns = 1 if TouchGestures.touch_ui() else 7
	_slots_box.add_theme_constant_override("h_separation", 12)
	_slots_box.add_theme_constant_override("v_separation", 6)
	v.add_child(_slots_box)
	v.add_child(HSeparator.new())
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	v.add_child(seed_row)
	seed_row.add_child(UiStyle.label("Seed", 15, UiStyle.TEXT_DIM))
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "random"
	_seed_edit.text_changed.connect(func(_text):
		if is_inside_tree():
			_preview_timer.start())
	_seed_edit.custom_minimum_size.x = 160
	seed_row.add_child(_seed_edit)
	var reroll := Button.new()
	reroll.text = "New seed"
	reroll.pressed.connect(func():
		_preview_seed = (_preview_seed + 104729) & 0x7FFFFFFF
		_seed_edit.text = str(_preview_seed)
		_refresh_preview())
	seed_row.add_child(reroll)
	var seed_hint := UiStyle.label("Same seed, same battles and the same generated map.", 12, UiStyle.TEXT_DIM)
	if TouchGestures.touch_ui():
		seed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		seed_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_hint)
	_hard_check = CheckBox.new()
	_hard_check.text = "Hide battle odds and encounter chances" if TouchGestures.touch_ui() else "Hard mode: battle odds and encounter chances are never shown"
	_hard_check.tooltip_text = "Hovering an enemy shows only its rough size; scouts still count it exactly."
	v.add_child(_hard_check)
	_setup_footer = VBoxContainer.new()
	root.add_child(_setup_footer)
	_error = UiStyle.label("", 13, UiStyle.BAD)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_footer.add_child(_error)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	_setup_footer.add_child(buttons)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(130, 38)
	back.pressed.connect(func():
		_setup_panel.hide()
		_home.show()
		_set_menu_screen("title"))
	buttons.add_child(back)
	_start_btn = Button.new()
	_start_btn.text = "Begin"
	_start_btn.custom_minimum_size = Vector2(160, 38)
	_start_btn.pressed.connect(_start)
	buttons.add_child(_start_btn)
	UiStyle.enlarge_touch_controls(_setup_panel)


## The random map's option pickers: size, players, layout, teams, monsters and
## treasure. Players, layout and teams are refilled to fit the mode and the
## player count (_sync_random_pickers).
func _build_random_row() -> void:
	var cfg := _data.map_templates
	var rm := RandomMapTemplate.settings(cfg)
	if rm.is_empty():
		return
	var tips := {
		"size": "How much room every player gets. Larger maps add backwaters, approaches and outer wilds.",
		"players": "Player slots on the map. Close a slot below to leave it empty.",
		"family": "The shape of the land: how realms, passes and contested ground are laid out.\nAny lets the seed choose.",
		"teams": "Split the players into allied teams of neighbouring slots.\nThe team pickers below can still be changed per player.",
		"monsters": "Strength of every neutral army: guards, gates and wanderers.",
		"treasure": "How many guarded hoards and loose resource piles each zone holds."}
	var captions := {"size": "Size", "players": "Players", "family": "Layout", "teams": "Teams", "monsters": "Monsters", "treasure": "Treasure"}
	for opt in ["size", "players", "family", "teams", "monsters", "treasure"]:
		var field: BoxContainer
		if TouchGestures.touch_ui():
			field = VBoxContainer.new()
		else:
			field = HBoxContainer.new()
		field.add_theme_constant_override("separation", 4 if TouchGestures.touch_ui() else 6)
		if TouchGestures.touch_ui():
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_random_row.add_child(field)
		_random_fields[opt] = field
		field.add_child(UiStyle.label(captions[opt], 14, UiStyle.TEXT_DIM))
		var pick := OptionButton.new()
		pick.tooltip_text = tips[opt]
		pick.custom_minimum_size.x = {"players": 64, "family": 130, "teams": 120}.get(opt, 110)
		var keys := []
		if opt in ["size", "monsters", "treasure"]:
			var table := {"size": "sizes", "monsters": "monsters", "treasure": "treasure"}[opt] as String
			for k in RandomMapTemplate.option_keys(cfg, table):
				keys.append(String(k))
				pick.add_item(String(rm[table][k].get("name", k)))
		_random_keys[opt] = keys
		_random_picks[opt] = pick
		pick.item_selected.connect(func(_i): _random_changed())
		_prepare_picker(pick)
		field.add_child(pick)
	_sync_random_pickers(GameSetup.default_random_options(_data))


func _max_random_players() -> int:
	var hi := 0
	for k in RandomMapTemplate.option_keys(_data.map_templates, "sizes"):
		hi = maxi(hi, RandomMapTemplate.max_players(_data.map_templates, String(k)))
	return hi


## The mode the mode picker shows ("conquest" before the screen is built).
func current_mode() -> String:
	if _mode_pick == null or _mode_pick.selected < 0:
		return "conquest"
	return String(_mode_pick.get_selected_metadata())


## Selects a mode by id (no change if the picker does not offer it) and refreshes the list.
func select_mode(mode: String) -> void:
	for i in _mode_pick.item_count:
		if String(_mode_pick.get_item_metadata(i)) == mode:
			_mode_pick.select(i)
			_refresh_map_choices()
			return


## The options the random-map pickers show, with the current mode.
func random_options() -> Dictionary:
	var out := {"mode": current_mode()}
	for opt in _random_picks:
		var pick: OptionButton = _random_picks[opt]
		var keys: Array = _random_keys[opt]
		if not keys.is_empty():
			out[opt] = keys[clampi(pick.selected, 0, keys.size() - 1)]
	return out


## Sets the random-map pickers (missing keys keep their choice) and rebuilds the slots.
func set_random_options(options: Dictionary) -> void:
	var o := random_options()
	o.merge(options, true)
	_apply_random(o)


func _random_changed() -> void:
	_apply_random(random_options())


## Builds the random entry for these options, shows the options it settled on
## (a size that holds fewer players lowers the count, a layout or team split
## the count cannot use falls back) and, if a random entry is picked, replaces
## it and rebuilds the slots.
func _apply_random(options: Dictionary) -> void:
	options["mode"] = current_mode()
	var entry := GameSetup.random_entry(_data, options)
	if entry.is_empty():
		return
	_sync_random_pickers(entry["options"])
	var i := _map_pick.selected
	if i < 0 or i >= _maps.size() or not bool(_maps[i].get("random", false)):
		return
	_maps[i] = entry
	_map_pick.set_item_text(i, _map_label(entry))
	_fill_slots()


## Refills the players, layout and teams pickers for the mode and player count
## and selects the given options.
func _sync_random_pickers(o: Dictionary) -> void:
	if _random_picks.is_empty():
		return
	var cfg := _data.map_templates
	var conquest := String(o.get("mode", "conquest")) == "conquest"
	var hi := _max_random_players() if conquest else mini(_max_random_players(), GameSetup.SCENARIO_MAX_PLAYERS)
	var n := int(o.get("players", RandomMapTemplate.min_players(cfg)))
	var player_keys := range(RandomMapTemplate.min_players(cfg), hi + 1)
	_fill_pick("players", player_keys, player_keys.map(func(k): return str(k)))
	var families := [""]
	var family_names := ["Any"]
	for f in LayoutFamilies.for_players(cfg, n):
		families.append(String(f))
		family_names.append(String(LayoutFamilies.family(cfg, String(f)).get("name", f)))
	_fill_pick("family", families, family_names)
	var pick: OptionButton = _random_picks["family"]
	pick.set_item_tooltip(0, "The seed chooses one of the layouts that fit the player count.")
	for k in range(1, families.size()):
		pick.set_item_tooltip(k, String(LayoutFamilies.family(cfg, String(families[k])).get("description", "")))
	var teams := GameSetup.team_choices(n)
	_fill_pick("teams", teams, teams.map(func(t): return {0: "No teams", 2: "Two teams", 3: "Three teams"}.get(t, "%d teams" % t)))
	(_random_picks["teams"] as OptionButton).disabled = teams.size() < 2
	for opt in ["size", "players", "family", "teams", "monsters", "treasure"]:
		var k: int = (_random_keys[opt] as Array).find(o.get(opt, ""))
		if k >= 0:
			(_random_picks[opt] as OptionButton).select(k)
	_random_fields["teams"].visible = conquest


func _fill_pick(opt: String, keys: Array, labels: Array) -> void:
	var pick: OptionButton = _random_picks[opt]
	pick.clear()
	for label in labels:
		pick.add_item(String(label))
	_random_keys[opt] = keys


func _map_label(m: Dictionary) -> String:
	if bool(m.get("random", false)):
		if String(m.get("mode", "conquest")) == "conquest":
			return "Random map  (choose size, players and layout below)"
		if String(m.get("template", "")) == "":
			return "%s  (a new maze for every seed)" % m["name"]
		return "%s  (choose size and layout below)" % m["name"]
	var players := "%d player%s" % [m["slots"].size(), "" if m["slots"].size() == 1 else "s"]
	if bool(m.get("curated", false)):
		var family := String(m.get("layout_family", ""))
		var layout := String(LayoutFamilies.family(_data.map_templates, family).get("name", family))
		if bool(m.get("scenario", false)):
			return "%s  (%s)" % [m["name"], m["size"]] if layout == "" else "%s  (%s layout, %s)" % [m["name"], layout, m["size"]]
		return "%s  (%s, %s layout, %s)" % [m["name"], players, layout, m["size"]]
	return "%s%s  (%s, %s)" % ["Custom · " if m.get("custom", false) else "", m["name"], players, m["size"]]


func _show_setup() -> void:
	_set_menu_screen("setup")
	_preview_seed = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	_refresh_map_choices()
	_home.hide()
	_setup_panel.show()

func _refresh_map_choices() -> void:
	_maps = GameSetup.available_maps(_data, current_mode())
	_map_pick.clear()
	for m in _maps:
		_map_pick.add_item(_map_label(m))
		if String(m.get("text", "")) != "":
			_map_pick.set_item_tooltip(_map_pick.item_count - 1, String(m["text"]))
	if _maps.is_empty():
		_fill_slots()
		return
	_map_pick.select(0)
	if bool(_selected_map().get("random", false)):
		set_random_options(random_options())
	else:
		_fill_slots()


func _selected_map() -> Dictionary:
	return _maps[_map_pick.selected] if _map_pick.selected >= 0 and _map_pick.selected < _maps.size() else {}


## The overview text of a new-game entry.
func _map_text(m: Dictionary) -> String:
	var mode := String(m.get("mode", "conquest"))
	var cfg := _data.map_templates
	if mode != "conquest":
		var parts := [String(GameSetup.MODE_TEXT.get(mode, ""))]
		if String(m.get("text", "")) != "":
			parts.append(String(m["text"]))
		parts.append("A new map for every seed." if bool(m.get("random", false)) else "This map is always the same; the seed changes battles and events.")
		parts.append("Open Mission objectives after starting for your orders.")
		return " ".join(parts)
	if bool(m.get("random", false)):
		var o: Dictionary = m["options"]
		var family := String(o.get("family", ""))
		var fam := LayoutFamilies.family(cfg, family)
		var layout := "The seed picks the layout." if family == "" else "%s: %s" % [String(fam.get("name", family)), String(fam.get("description", ""))]
		var teams := "" if int(o.get("teams", 0)) < 2 else " in %d teams" % int(o["teams"])
		return "A new map for every seed: %s tiles, %d players%s. %s Every start has the same land and riches. Last player or team standing wins." % [m["size"], int(o["players"]), teams, layout]
	if bool(m.get("curated", false)):
		var family := String(m.get("layout_family", ""))
		return "%s Layout: %s. A chosen map: it is always the same, the seed changes battles and events. Last player or team standing wins." % [String(m.get("text", "")), String(LayoutFamilies.family(cfg, family).get("name", family))]
	if m.get("custom", false):
		return "Your saved map. Authored heroes and armies are kept; changing a faction or hero class changes that starting setup."
	return "Last player or team standing wins. A player who loses every town has %d days to take one back." % int(_data.rules["town_loss_grace_days"])


## The caption of a player slot: scenario roles, or "Player n".
func _slot_title(m: Dictionary, i: int) -> String:
	if not m.get("scenario", false):
		return "Player %d" % (i + 1)
	if String(m.get("mode", "")) in ["survival", "defence", "endless"]:
		return "Your realm" if i == 0 else ("Invaders" if i == 1 else "Potential ally")
	return "Your realm" if i == 0 else "Rival %d" % i


func _fill_slots() -> void:
	for c in _slots_box.get_children():
		_slots_box.remove_child(c)
		c.queue_free()
	_slot_rows.clear()
	_player_tabs = null
	if TouchGestures.touch_ui():
		_player_tabs = TabContainer.new()
		_player_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slots_box.add_child(_player_tabs)
	var m := _selected_map()
	_map_preview.visible = not m.is_empty()
	_preview_legend.visible = not m.is_empty()
	if m.is_empty():
		_random_row.hide()
		_map_info.text = "No maps match these choices."
		_start_btn.disabled = true
		return
	_random_row.visible = bool(m.get("random", false)) and String(m.get("template", "")) != ""
	_map_info.text = _map_text(m)
	_map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var factions := GameSetup.playable_factions(_data)
	var defaults: Array = GameSetup.default_setup(m)["players"]
	for i in m["slots"].size():
		var slot_title := _slot_title(m, i)
		var slot_grid := _slots_box
		if TouchGestures.touch_ui():
			slot_grid = GridContainer.new()
			slot_grid.name = slot_title
			slot_grid.columns = 2
			slot_grid.add_theme_constant_override("h_separation", 12)
			slot_grid.add_theme_constant_override("v_separation", 12)
			_player_tabs.add_child(slot_grid)
		else:
			slot_grid.add_child(UiStyle.label(slot_title, 15))
		var color_pick := OptionButton.new()
		color_pick.tooltip_text = "Player color"
		for c in GameSetup.PLAYER_COLORS.size():
			var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
			image.fill(Color(GameSetup.PLAYER_COLORS[c]))
			color_pick.add_icon_item(ImageTexture.create_from_image(image), GameSetup.COLOR_NAMES[c])
			color_pick.set_item_metadata(c, GameSetup.PLAYER_COLORS[c])
		color_pick.select(i % GameSetup.PLAYER_COLORS.size())
		if m.get("custom", false):
			var authored: String = defaults[i].get("color", GameSetup.PLAYER_COLORS[i % GameSetup.PLAYER_COLORS.size()])
			var found := false
			for c in color_pick.item_count:
				if Color(str(color_pick.get_item_metadata(c))) == Color(authored):
					color_pick.select(c)
					found = true
					break
			if not found:
				var swatch_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
				swatch_image.fill(Color(authored))
				color_pick.add_icon_item(ImageTexture.create_from_image(swatch_image), "Authored colour")
				color_pick.set_item_metadata(color_pick.item_count - 1, authored)
				color_pick.select(color_pick.item_count - 1)
		_add_slot_field(slot_grid, color_pick, "Color")
		var type_pick := OptionButton.new()
		type_pick.custom_minimum_size.x = 150
		for t in TYPES:
			if t == "closed" and m["slots"].size() == 1:
				continue
			type_pick.add_item(TYPE_NAMES[t])
		type_pick.select(TYPES.find(defaults[i]["type"]))
		_add_slot_field(slot_grid, type_pick, "Control")
		var fac_pick := OptionButton.new()
		fac_pick.custom_minimum_size.x = 180
		for f in factions:
			fac_pick.add_icon_item(Art.faction_emblem_icon(f), _data.factions[f]["name"])
			var tip := String(_data.factions[f].get("roster", ""))
			var mech := FactionMechanics.describe(f, _data)
			if mech != "":
				tip += "\nMap mechanic: " + mech
			var n := _data.starting_heroes(f)
			if m.get("custom", false):
				tip += "\nKeeps authored heroes unless you change the starting setup."
			elif n != 1:
				tip += "\nStarts with %d heroes." % n
			fac_pick.set_item_tooltip(fac_pick.item_count - 1, tip)
		fac_pick.select(maxi(0, factions.find(defaults[i]["faction"])))
		_add_slot_field(slot_grid, fac_pick, "Faction")
		var class_pick := OptionButton.new()
		class_pick.custom_minimum_size.x = 160
		class_pick.tooltip_text = "Starting hero class"
		_add_slot_field(slot_grid, class_pick, "Hero class")
		_fill_class_picker(class_pick, factions[fac_pick.selected])
		fac_pick.item_selected.connect(func(index: int):
			_fill_class_picker(class_pick, factions[index])
			_validate()
			# Generated maps give each home zone its faction's native ground.
			_preview_timer.start())
		var level_pick := OptionButton.new()
		level_pick.custom_minimum_size.x = 130
		var levels := _data.difficulty_levels()
		if m.get("scenario", false):
			levels = levels.filter(func(lv): return lv != "passive")
		for lv in levels:
			level_pick.add_item(_data.difficulty(lv)["name"])
			level_pick.set_item_metadata(level_pick.item_count - 1, lv)
			level_pick.set_item_tooltip(level_pick.item_count - 1, _data.difficulty(lv).get("description", ""))
			if _siege_mode(m) and i == 1 and not (m.get("invasion_strength", {}) as Dictionary).is_empty():
				level_pick.set_item_tooltip(level_pick.item_count - 1, "Invasion armies: %d%% of standard strength. Arrival days and routes stay the same." % int(round(float(m.get("invasion_strength", {}).get(lv, 1.0)) * 100)))
		var level: String = defaults[i]["difficulty"] if defaults[i]["difficulty"] != "" else _data.default_difficulty()
		level_pick.select(maxi(0, levels.find(level)))
		level_pick.tooltip_text = "Computer difficulty"
		_add_slot_field(slot_grid, level_pick, "Difficulty")
		var team_pick := OptionButton.new()
		team_pick.custom_minimum_size.x = 110
		team_pick.add_item("No team")
		for t in GameSetup.MAX_TEAMS:
			team_pick.add_item("Team %d" % (t + 1))
		team_pick.select(clampi(int(defaults[i].get("team", 0)), 0, GameSetup.MAX_TEAMS))
		team_pick.tooltip_text = "Players on the same team are allies: they never fight, share what their heroes see,\ncan send each other resources and win together."
		_add_slot_field(slot_grid, team_pick, "Team")
		type_pick.item_selected.connect(func(_x): _validate())
		team_pick.item_selected.connect(func(_x): _validate())
		color_pick.item_selected.connect(func(_x): _validate())
		_slot_rows.append({"color": color_pick, "type": type_pick, "faction": fac_pick, "hero_class": class_pick, "difficulty": level_pick, "team": team_pick})
	UiStyle.enlarge_touch_controls(_slots_box)
	_validate()
	_refresh_preview()


## Survival, defence and endless: fixed defender, invaders and potential ally.
func _siege_mode(m: Dictionary) -> bool:
	return m.get("scenario", false) and String(m.get("mode", "")) in ["survival", "defence", "endless"]


## Phone forms use bounded, labelled fields instead of a seven-column table.
func _prepare_picker(pick: OptionButton) -> void:
	if TouchGestures.touch_ui():
		pick.fit_to_longest_item = false
		pick.clip_text = true
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _add_slot_field(grid: GridContainer, pick: OptionButton, caption: String) -> void:
	_prepare_picker(pick)
	if TouchGestures.touch_ui():
		var field := VBoxContainer.new()
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(field)
		field.add_child(UiStyle.label(caption, 14, UiStyle.TEXT_DIM))
		field.add_child(pick)
	else:
		grid.add_child(pick)


func _fill_class_picker(pick: OptionButton, faction: String) -> void:
	pick.clear()
	pick.add_item("Authored heroes" if _selected_map().get("custom", false) else "Default hero")
	pick.set_item_metadata(0, "")
	for id in GameSetup.classes_for_faction(_data, faction):
		var cls: Dictionary = _data.hero_classes[id]
		pick.add_item(String(cls["name"]))
		pick.set_item_metadata(pick.item_count - 1, id)
		pick.set_item_tooltip(pick.item_count - 1, String(cls.get("text", "")))


func current_setup() -> Dictionary:
	var factions := GameSetup.playable_factions(_data)
	var ps := []
	var levels := _data.difficulty_levels()
	for row in _slot_rows:
		var p := {"type": TYPES[row["type"].selected], "faction": factions[row["faction"].selected],
			"color": str(row["color"].get_selected_metadata()), "team": int(row["team"].selected), "hero_class": String(row["hero_class"].get_selected_metadata())}
		if p["type"] == "computer":
			p["difficulty"] = String(row["difficulty"].get_selected_metadata())
		if _selected_map().get("custom", false):
			p["name"] = _selected_map()["slots"][ps.size()].get("name", "")
		if _selected_map().get("scenario", false):
			var slot: Dictionary = _selected_map()["slots"][ps.size()]
			p["type"] = "human" if bool(slot["is_human"]) else "computer"
			p["team"] = int(slot.get("team", 0))
			if not bool(slot["is_human"]):
				p["faction"] = slot["faction"]
				p["hero_class"] = ""
		ps.append(p)
	# A skirmish: every player starts with its faction's number of heroes.
	var out := {"players": ps, "standard_start": true}
	if _selected_map().get("custom", false):
		out["standard_start"] = false
		out["preserve_authored"] = true
	if _hard_check != null and _hard_check.button_pressed:
		out["hide_odds"] = true
	return out


func _validate() -> bool:
	var humans := 0
	var active := 0
	var sides := {}
	var colors := {}
	var duplicate_color := false
	var i := 0
	for p in current_setup()["players"]:
		if p["type"] != "closed":
			active += 1
			if colors.has(p["color"]):
				duplicate_color = true
			colors[p["color"]] = true
			sides[int(p["team"]) if int(p["team"]) > 0 else -1 - i] = true
		i += 1
		if p["type"] == "human":
			humans += 1
	var err := ""
	if humans == 0:
		err = "At least one player must be human."
	elif active < 2 and _slot_rows.size() > 1:
		err = "Open at least two player slots."
	elif duplicate_color:
		err = "Choose a different color for each active player."
	elif active >= 2 and sides.size() == 1:
		err = "Everyone is on the same team: put at least one player on another side."
	_error.text = err
	_start_btn.disabled = err != ""
	for idx in _slot_rows.size():
		var row: Dictionary = _slot_rows[idx]
		var fixed: bool = _selected_map().get("scenario", false)
		row["type"].disabled = fixed
		row["color"].disabled = TYPES[row["type"].selected] == "closed"
		row["faction"].disabled = TYPES[row["type"].selected] == "closed" or (fixed and idx > 0)
		row["hero_class"].disabled = TYPES[row["type"].selected] == "closed" or (fixed and idx > 0)
		row["difficulty"].disabled = TYPES[row["type"].selected] != "computer" or (_siege_mode(_selected_map()) and idx != 1)
		row["team"].disabled = fixed or TYPES[row["type"].selected] == "closed" or _slot_rows.size() < 3
	if _map_preview != null:
		_map_preview.update_preview_players(_preview_players())
	return err == ""


## Preview colours come from the same definition that game launch applies.
## Keep explicit setup colours when the menu supports choosing them.
func _preview_players() -> Array:
	var players: Array = current_setup()["players"]
	var defaults: Array = _preview_definition.get("players", [])
	for i in players.size():
		if not players[i].has("color"):
			players[i]["color"] = defaults[i]["color"] if i < defaults.size() else "#a39788"
	return players


## Empty input keeps the seed already used by the preview. Text seeds retain
## the same conversion as game launch; Begin also flushes a pending refresh.
func preview_seed() -> int:
	var text := _seed_edit.text.strip_edges()
	return int(text) if text.is_valid_int() else (text.hash() & 0x7FFFFFFF if text != "" else _preview_seed)


func _refresh_preview() -> void:
	var entry := _selected_map()
	if entry.is_empty():
		return
	_preview_timer.stop()
	var id := GameSetup.map_id_for(entry, preview_seed(), current_setup())
	if id != _preview_map_id or entry.get("custom", false):
		_preview_definition = _data.load_map(id)
		_preview_map_id = id
	if _preview_definition.is_empty():
		_error.text = "This map is missing or no longer playable. Reopen setup or fix it in the editor."
		_start_btn.disabled = true
		_map_preview.hide()
		return
	if entry.get("custom", false) and _preview_definition["players"].size() != entry["slots"].size():
		_error.text = "This map's player slots changed. Reopen New Game to refresh it."
		_start_btn.disabled = true
		_preview_definition = {}
		return
	_map_preview.bind_preview(_preview_definition, _data, _preview_players())
	for child in _preview_legend.get_children():
		_preview_legend.remove_child(child)
		child.queue_free()
	var present := {}
	for row in _preview_definition["terrain"]:
		for ch in String(row):
			present[_data.terrain_by_char[ch]] = true
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	_preview_legend.add_child(flow)
	for tid in _data.terrains:
		if present.has(tid):
			var item := HBoxContainer.new()
			var swatch := ColorRect.new()
			swatch.color = Color(_data.terrain(tid)["color"])
			swatch.custom_minimum_size = Vector2(10, 10)
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			item.add_child(swatch)
			item.add_child(UiStyle.label(_data.terrain(tid)["name"], 12, UiStyle.TEXT_DIM))
			flow.add_child(item)
	var seed_text := "Seed %d" % preview_seed()
	if entry.has("map_seed"):
		seed_text = "Map seed %d · game seed %d" % [int(entry["map_seed"]), preview_seed()]
	_preview_legend.add_child(UiStyle.label("%d × %d tiles · %s" % [int(_preview_definition["width"]), int(_preview_definition["height"]), seed_text], 12, UiStyle.TEXT_DIM))


func _start() -> void:
	if not _validate():
		return
	_refresh_preview()
	if _preview_definition.is_empty():
		return
	var m := _selected_map()
	var seed_value := preview_seed()
	start_requested.emit(GameSetup.map_id_for(m, seed_value, current_setup()), seed_value, current_setup())


func show_launch_error(message: String) -> void:
	if not _setup_panel.visible:
		_show_setup()
	_error.text = message
	_start_btn.disabled = true
	show()


# ------------------------------------------------------------- campaign --

## Opens the painted journey selector; chapter rules remain owned by Campaign.
func show_campaigns() -> void:
	_set_menu_screen("campaign")
	_home.hide()
	_setup_panel.hide()
	_campaign_panel.open()


func show_campaign_journey(id: String, progress: Campaign = null) -> void:
	show_campaigns()
	_campaign_panel.show_campaign(id, progress)


func _set_menu_screen(screen: String) -> void:
	if _art_background == null:
		return
	_art_background.texture = MenuArt.texture(screen)
	var compact := screen != "title"
	_wordmark.custom_minimum_size = Vector2(420, 92) if compact else (Vector2(600, 120) if TouchGestures.touch_ui() else Vector2(780, 260))
	_brand_label.add_theme_font_size_override("font_size", 30 if compact else 48)
	_brand_gap.visible = not compact
