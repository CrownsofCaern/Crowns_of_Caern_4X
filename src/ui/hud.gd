class_name Hud
extends Control
## Top resource bar with the calendar, minimap, and the right-hand panel
## (heroes, hero card, army, tile info, log, commands). Read-only view of the session;
## buttons are forwarded as signals to the AdventureScreen controller.

signal objectives_pressed
signal end_turn_pressed
signal save_pressed
signal load_pressed
signal menu_pressed
signal hero_selected(hero_id: String)
signal skills_pressed
signal town_pressed
signal next_hero_pressed
signal hero_screen_pressed

const PANEL_W := 320
## Army slot size in the side panel: two rows of five fit its width.
const HUD_SLOT := 56
const TOP_H := 44
const BOTTOM_H := 66

var minimap: Minimap
var _minimap_frame: PanelContainer
var _res_labels: Dictionary = {}
var _res_last: Dictionary = {}
var _res_player := -1
var _day_label: Label
var _player_label: Label
var _faction_emblem: TextureRect
var _portrait: HeroPortrait
var _hero_name: Label
var _hero_sub: Label
var _stats: HBoxContainer
var _xp_bar: ProgressBar
var _mp_bar: ProgressBar
var _army_box: GridContainer
var _tile_label: Label
var _log: RichTextLabel
var _end_turn: Button
var _roster: Container
var _skills_btn: Button
var _objectives_btn: Button


static func top_height() -> int:
	return TOP_H


## Canvas units the HUD covers on each side of the map, safe area included:
## x left, y top, z right, w bottom.
static func map_margins() -> Vector4:
	var inset := TouchLayout.insets()
	return Vector4(inset.x, top_height() + inset.y, PANEL_W + inset.z, BOTTOM_H + inset.w)


## Fills the safe-area strips beside the top bar and the side panel, so the
## notch side and the far edge read as part of the frame, not as stray map.
func _build_safe_area_backing() -> void:
	var inset := TouchLayout.insets()
	var col := Color("#15110d")
	if inset.x > 0.0:
		var left := ColorRect.new()
		left.color = col
		left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left.position = Vector2(-inset.x, -inset.y)
		left.size = Vector2(inset.x, top_height() + inset.y)
		add_child(left)
	if inset.z > 0.0 or inset.w > 0.0:
		var right := ColorRect.new()
		right.color = col
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.anchor_left = 1.0
		right.anchor_right = 1.0
		right.anchor_bottom = 1.0
		right.offset_left = -PANEL_W
		right.offset_right = inset.z
		right.offset_top = -inset.y
		right.offset_bottom = inset.w
		add_child(right)
	if inset.w > 0.0:
		var bottom := ColorRect.new()
		bottom.color = col
		bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom.anchor_top = 1.0
		bottom.anchor_bottom = 1.0
		bottom.anchor_right = 1.0
		bottom.offset_left = -inset.x
		bottom.offset_bottom = inset.w
		add_child(bottom)


func build(data: GameData) -> void:
	# On a phone the whole HUD sits inside the safe area (notch, home indicator).
	TouchLayout.inset_full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.make_theme()
	_build_safe_area_backing()

	# --- top bar: resources, then whose turn and the calendar
	var top := PanelContainer.new()
	var sb := UiStyle.panel_box(Color("#15110d"), UiStyle.BRASS, 0)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = PANEL_W + 8
	top.add_theme_stylebox_override("panel", sb)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = top_height()
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	top.add_child(row)
	for res in data.resource_order:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.custom_minimum_size.x = 92 if res == "gold" else 72
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.tooltip_text = data.resources[res]["name"]
		var tex := Art.resource_icon(res)
		if tex != null:
			var ic := UiStyle.icon(tex, Vector2(32, 32))
			ic.tooltip_text = data.resources[res]["name"]
			box.add_child(ic)
		else:
			var swatch := ColorRect.new()
			swatch.color = Color(data.resources[res]["color"])
			swatch.custom_minimum_size = Vector2(12, 12)
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(swatch)
		var l := UiStyle.label("0", 16)
		l.tooltip_text = data.resources[res]["name"]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(l)
		_res_labels[res] = l
		row.add_child(box)
		var div := ColorRect.new()
		div.color = UiStyle.BRASS.darkened(0.6)
		div.custom_minimum_size = Vector2(1, 24)
		div.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(div)

	# --- calendar badge over the top of the side panel
	var cal := PanelContainer.new()
	var csb := UiStyle.panel_box(Color("#15110d"), UiStyle.BRASS, 0)
	csb.border_width_bottom = 2
	csb.border_width_left = 2
	csb.set_corner_radius_all(0)
	csb.set_content_margin_all(4)
	csb.content_margin_left = 10
	cal.add_theme_stylebox_override("panel", csb)
	cal.anchor_left = 1.0
	cal.anchor_right = 1.0
	cal.offset_left = -PANEL_W
	cal.offset_bottom = top_height()
	add_child(cal)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	cal.add_child(crow)
	_faction_emblem = UiStyle.icon(null, Vector2(36, 36))
	_faction_emblem.name = "FactionEmblem"
	crow.add_child(_faction_emblem)
	crow.add_child(UiStyle.ui_icon("day", 32))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -4)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_child(cv)
	_day_label = UiStyle.label("", 17, UiStyle.BRASS)
	cv.add_child(_day_label)
	_player_label = UiStyle.label("", 12, UiStyle.TEXT_DIM)
	cv.add_child(_player_label)

	# --- message bar under the map: log on the left, hovered tile on the right
	var bottom := PanelContainer.new()
	var bsb := UiStyle.panel_box(Color("#15110d"), UiStyle.BRASS, 0)
	bsb.border_width_top = 2
	bsb.set_corner_radius_all(0)
	bsb.set_content_margin_all(6)
	bsb.content_margin_left = 12
	bsb.shadow_size = 0
	bottom.add_theme_stylebox_override("panel", bsb)
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_top = -BOTTOM_H
	bottom.offset_right = -PANEL_W
	add_child(bottom)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	bottom.add_child(brow)
	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_stretch_ratio = 1.6
	_log.bbcode_enabled = true
	_log.add_theme_font_size_override("normal_font_size", 13)
	brow.add_child(_log)
	var bdiv := ColorRect.new()
	bdiv.color = UiStyle.BRASS.darkened(0.6)
	bdiv.custom_minimum_size.x = 1
	brow.add_child(bdiv)
	_tile_label = UiStyle.label("Point at a tile to inspect it.", 13, UiStyle.TEXT_DIM)
	_tile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tile_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_label.clip_text = true
	brow.add_child(_tile_label)

	# --- right panel
	var side := PanelContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -PANEL_W
	side.offset_top = top_height()
	add_child(side)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var command_parent := v
	if TouchGestures.touch_ui():
		command_parent = VBoxContainer.new()
		side.add_child(command_parent)
		var side_scroll := ScrollContainer.new()
		side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		command_parent.add_child(side_scroll)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side_scroll.add_child(v)
	else:
		side.add_child(v)
	# minimap, framed, at the top of the panel
	_minimap_frame = PanelContainer.new()
	var msb: StyleBox = UiStyle.slot_box(4.0)
	if msb == null:
		msb = UiStyle.panel_box(Color("#120f0b"), UiStyle.BRASS.darkened(0.3), 2)
		msb.set_content_margin_all(4)
	_minimap_frame.add_theme_stylebox_override("panel", msb)
	_minimap_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var touch := TouchGestures.touch_ui()
	# A phone shows the hero first; the minimap waits at the bottom of the scroll.
	if not touch:
		v.add_child(_minimap_frame)
	minimap = Minimap.new()
	_minimap_frame.add_child(minimap)
	if touch:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		_roster = grid
	else:
		_roster = VBoxContainer.new()
		_roster.add_theme_constant_override("separation", 2)
	v.add_child(_roster)

	# hero card: portrait, name, class, attributes
	var card := HBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	v.add_child(card)
	_portrait = HeroPortrait.new(1)
	_portrait.tooltip_text = "Hero overview and army  (H)"
	_portrait.pressed.connect(func(): hero_screen_pressed.emit())
	card.add_child(_portrait)
	var cinfo := VBoxContainer.new()
	cinfo.add_theme_constant_override("separation", 0)
	cinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(cinfo)
	_hero_name = UiStyle.label("", 19, UiStyle.BRASS)
	_hero_name.clip_text = true
	cinfo.add_child(_hero_name)
	_hero_sub = UiStyle.label("", 12, UiStyle.TEXT_DIM)
	_hero_sub.mouse_filter = Control.MOUSE_FILTER_PASS
	cinfo.add_child(_hero_sub)
	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override("separation", 10)
	cinfo.add_child(_stats)
	_xp_bar = _bar_row(v, "xp", "Experience")
	_mp_bar = _bar_row(v, "move", "Movement")
	_skills_btn = Button.new()
	_skills_btn.custom_minimum_size.y = 30
	_skills_btn.pressed.connect(func(): skills_pressed.emit())
	v.add_child(_skills_btn)
	_army_box = GridContainer.new()
	_army_box.columns = 5
	_army_box.add_theme_constant_override("h_separation", 4)
	_army_box.add_theme_constant_override("v_separation", 4)
	v.add_child(_army_box)
	_objectives_btn = Button.new()
	_objectives_btn.text = "Mission objectives"
	_objectives_btn.custom_minimum_size.y = 34
	_objectives_btn.pressed.connect(func(): objectives_pressed.emit())
	v.add_child(_objectives_btn)
	if touch:
		v.add_child(_minimap_frame)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	var buttons := GridContainer.new()
	# A phone keeps one row of commands: the portrait and army open the hero,
	# and Load lives in the main menu.
	buttons.columns = 4 if touch else 3
	buttons.add_theme_constant_override("h_separation", 4)
	buttons.add_theme_constant_override("v_separation", 4)
	command_parent.add_child(buttons)
	for spec in [["Hero", "hero", "Hero overview and army  (H)", hero_screen_pressed],
			["Town", "town", "Open your town  (T)", town_pressed],
			["Next", "", "Select the next hero  (Tab)", next_hero_pressed],
			["Save", "", "Save the game  (F5)", save_pressed],
			["Load", "", "Load a game  (F9)", load_pressed],
			["Menu", "", "Main menu  (Esc)", menu_pressed]]:
		if touch and spec[0] in ["Hero", "Load"]:
			continue
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[2]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 32
		b.add_theme_font_size_override("font_size", 14)
		if spec[1] != "" and not touch:
			UiStyle.button_icon(b, spec[1], 24)
		var sig: Signal = spec[3]
		b.pressed.connect(func(): sig.emit())
		buttons.add_child(b)
	_end_turn = Button.new()
	_end_turn.text = "End Turn"
	UiStyle.button_icon(_end_turn, "day", 30)
	_end_turn.tooltip_text = "End the day  (E)"
	_end_turn.focus_mode = Control.FOCUS_NONE
	_end_turn.custom_minimum_size.y = 42
	_end_turn.add_theme_font_size_override("font_size", 17)
	_end_turn.pressed.connect(func(): end_turn_pressed.emit())
	command_parent.add_child(_end_turn)
	UiStyle.enlarge_touch_controls(self)


func _bar_row(parent: Control, icon_name: String, tip: String) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = tip
	parent.add_child(row)
	var ic := UiStyle.ui_icon(icon_name, 20)
	ic.tooltip_text = tip
	row.add_child(ic)
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 14
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return bar


func set_minimap_visible(on: bool) -> void:
	_minimap_frame.visible = on


func minimap_visible() -> bool:
	return _minimap_frame.visible


func refresh(session: GameSession, hero: Hero) -> void:
	var st := session.state
	var bank: ResourceBank = session.current_player()["resources"]
	var income := session.income_breakdown(st.current_player)
	var same_player := _res_player == st.current_player
	_res_player = st.current_player
	for res in _res_labels:
		var amount := bank.get_amount(res)
		var l: Label = _res_labels[res]
		l.text = str(amount)
		if same_player and _res_last.has(res) and amount != int(_res_last[res]):
			UiStyle.flash(l, UiStyle.GOOD if amount > int(_res_last[res]) else UiStyle.BAD)
		_res_last[res] = amount
		var tip := income_tooltip(session.data.resources[res]["name"], amount, income[res])
		l.tooltip_text = tip
		for c in l.get_parent().get_children():
			(c as Control).tooltip_text = tip
		l.get_parent().tooltip_text = tip
	var faction := String(session.current_player()["faction"])
	_faction_emblem.texture = Art.faction_emblem(faction)
	_faction_emblem.visible = _faction_emblem.texture != null
	_faction_emblem.tooltip_text = String(session.data.factions.get(faction, {}).get("name", faction))
	var pcol := Color(session.current_player()["color"]).lightened(0.35)
	_player_label.text = session.current_player()["name"] if st.players.size() > 1 else ""
	_player_label.add_theme_color_override("font_color", pcol)
	var left := VictoryRules.days_left(session, st.current_player)
	_day_label.text = "Week %d, Day %d" % [st.week(), st.day_of_week()]
	var omen := session.current_omen()
	if not omen.is_empty() and String(omen["id"]) != "quiet_week":
		_day_label.text += "  ·  %s" % omen["name"]
	_day_label.tooltip_text = String(omen.get("text", ""))
	_day_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if left > 0:
		_player_label.text += "  ·  %d day%s to take a town!" % [left, "" if left == 1 else "s"]
		_player_label.add_theme_color_override("font_color", UiStyle.WARN)
	_objectives_btn.visible = ScenarioRules.active(st)
	if _objectives_btn.visible:
		var objectives := session.scenario_objectives()
		var done := objectives.filter(func(o): return o["completed"]).size()
		_objectives_btn.text = "Objectives %d/%d" % [done, objectives.size()]
		var next := WaveDirector.next_wave(st)
		if not next.is_empty():
			_objectives_btn.text += " · Wave in %dd" % maxi(0, int(next["day"]) - st.day)
		_objectives_btn.tooltip_text = "\n".join(objectives.map(func(o): return String(o["text"])))
	_end_turn.disabled = st.game_over
	minimap.refresh()
	for c in _army_box.get_children():
		_army_box.remove_child(c)
		c.queue_free()
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	_refresh_roster(session, hero)
	UiStyle.enlarge_touch_controls(_roster)
	_skills_btn.visible = hero != null and hero.alive and hero.skill_points > 0
	_portrait.visible = hero != null and hero.alive
	if hero == null or not hero.alive:
		_hero_name.text = "No hero"
		_hero_sub.text = ""
		_xp_bar.value = 0
		_mp_bar.value = 0
		return
	_portrait.set_owner_color(Color(st.player(hero.owner)["color"]))
	_portrait.set_hero(hero.id, hero.class_id)
	if hero.skill_points > 0:
		_skills_btn.text = "Learn a skill  (%d point%s)" % [hero.skill_points, "" if hero.skill_points == 1 else "s"]
	var cls: Dictionary = session.data.hero_classes[hero.class_id]
	_hero_name.text = hero.name
	_hero_sub.text = "Level %d %s" % [hero.level, cls["name"]]
	var skill_txt := []
	for s in hero.skills:
		skill_txt.append("%s %d" % [session.data.skills[s]["name"], hero.skills[s]])
	var d := session.data
	var worn := []
	for a in hero.all_artifacts(d):
		worn.append(d.artifacts[a]["name"])
	var spec := hero.specialty(d)
	_hero_sub.tooltip_text = "%sSkills: %s\n%s: %s\nBattle art %s: %s%s" % [
		("Specialty %s: %s\n" % [spec["name"], spec["text"]]) if not spec.is_empty() else "",
		", ".join(skill_txt) if not skill_txt.is_empty() else "none",
		cls["trait"]["name"], cls["trait"]["text"], cls["art"]["name"], cls["art"]["text"],
		("\nArtifacts: " + ", ".join(worn)) if not worn.is_empty() else ""]
	for a in ["attack", "defense", "power", "knowledge"]:
		var v := hero.total_attr(a, d)
		_stats.add_child(UiStyle.stat_chip(a, v, "%s %d" % [a.capitalize(), v], 24))
	var th: Array = session.data.progression["xp_thresholds"]
	var lo := int(th[hero.level - 1])
	var hi := int(th[mini(hero.level, th.size() - 1)])
	_xp_bar.min_value = lo
	_xp_bar.max_value = maxi(hi, lo + 1)
	_xp_bar.value = hero.xp
	_xp_bar.tooltip_text = "%d / %d experience" % [hero.xp, hi]
	_mp_bar.max_value = maxi(1, hero.max_movement(session.data))
	_mp_bar.value = hero.movement_left
	_mp_bar.tooltip_text = "%d / %d movement points" % [hero.movement_left, hero.max_movement(session.data)]
	for i in Army.MAX_SLOTS:
		var slot: Dictionary = hero.army.slots[i]
		var w := ArmySlot.new().with_size(HUD_SLOT)
		if slot.is_empty():
			w.setup(i, "", 0, "Empty slot. Click to manage the army (H).")
		else:
			w.setup(i, slot["creature"], int(slot["count"]), UiStyle.creature_tooltip(session.data, slot["creature"], int(slot["count"]), Army.veteran_level(slot)) + "\n" + Army.veteran_description(slot) + "\n\nClick to manage the army (H).", Army.veteran_level(slot))
			w.with_ultimate(UltimateCreatureArt.faction_if_upgraded(session, hero.owner, slot["creature"]))
		w.clicked.connect(func(_s, _shift): hero_screen_pressed.emit())
		_army_box.add_child(w)


func _refresh_roster(session: GameSession, selected: Hero) -> void:
	for c in _roster.get_children():
		_roster.remove_child(c)
		c.queue_free()
	for h in session.state.heroes_of(session.state.current_player):
		var b := Button.new()
		var cls: Dictionary = session.data.hero_classes[h.class_id]
		var pts := "  *" if h.skill_points > 0 else ""
		b.text = h.name.get_slice(" ", 0) + pts if TouchGestures.touch_ui() else "%s  L%d %s%s" % [h.name, h.level, cls["name"], pts]
		b.clip_text = TouchGestures.touch_ui()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 28
		UiStyle.button_icon(b, "hero", 22)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%d / %d movement points left%s" % [h.movement_left, h.max_movement(session.data), "\nHas a skill point to spend" if h.skill_points > 0 else ""]
		b.button_pressed = selected != null and h.id == selected.id
		if b.button_pressed:
			b.add_theme_color_override("font_color", UiStyle.accent())
			b.add_theme_color_override("font_pressed_color", UiStyle.accent())
		var id: String = h.id
		b.pressed.connect(func(): hero_selected.emit(id))
		_roster.add_child(b)


func show_tile(session: GameSession, t: Vector2i) -> void:
	var map := session.state.map
	if not map.in_bounds(t) or not session.current_player()["fog"].is_explored(t):
		_tile_label.text = "Unexplored"
		return
	var ter := session.data.terrain(map.terrain_at(t))
	var txt := "%s%s" % [ter["name"], " (road)" if map.has_road(t) else ""]
	if map.is_passable(t):
		txt += ": %d movement" % map.move_cost(t)
	else:
		txt += ": impassable"
	var foe := session.state.hero_at(t)
	if foe != null and foe.owner != session.state.current_player:
		txt += "\n%s (%s)" % [foe.name, session.state.player(foe.owner)["name"]]
	var o := map.object_at(t)
	if not o.is_empty():
		if o["type"] == "resource":
			txt += "\n%d %s" % [int(o["amount"]), session.data.resources[o["resource"]]["name"]]
		elif o["type"] == "encounter":
			txt += "\n%s" % session.data.encounters.get(o["encounter"], {}).get("name", "Encounter")
		elif o["type"] == "site":
			var owner := int(o.get("owner", -1))
			txt += "\n%s: %s" % [MapSites.site_name(o, session.data), MapSites.summary(o, session.data)]
			if MapCobolts.is_post(o, session.data) and not o.get("plundered", false):
				txt += "\nGuards concealed"
			if MapSites.RECRUIT_KINDS.has(MapSites.kind(o, session.data)):
				txt += ", %s" % ("unclaimed" if owner < 0 else session.state.player(owner)["name"])
			var guard: Array = [] if MapCobolts.is_post(o, session.data) else o.get("guard", [])
			if not guard.is_empty():
				var parts := []
				for s in guard:
					parts.append("%s %s" % [UiStyle.count_word(int(s[1])), session.data.creature(s[0])["name"]])
				txt += "\nGuarded by " + ", ".join(parts)
		elif o["type"] == "town":
			var owner := int(o["owner"])
			txt += "\n%s (%s), %s" % [o["name"], session.data.town_types[o["town_type"]]["name"],
				"neutral" if owner < 0 else session.state.player(owner)["name"]]
			var g := Town.garrison(o)
			if owner != session.state.current_player and not g.is_empty():
				txt += "\nGarrison: %s" % _army_words(session, g.to_combat_stacks())
		elif o["type"] == "mine":
			var owner := int(o["owner"])
			txt += "\n%s: +%d %s a day, %s" % [Economy.mine_name(o, session.data), Economy.mine_income(o, session.data),
				session.data.resources[o["resource"]]["name"], "unclaimed" if owner < 0 else session.state.player(owner)["name"]]
			var guard: Array = o.get("guard", [])
			if not guard.is_empty():
				var parts := []
				for s in guard:
					parts.append("%s %s" % [UiStyle.count_word(int(s[1])), session.data.creature(s[0])["name"]])
				txt += "\nGuarded by " + ", ".join(parts)
		elif o["type"] == "neutral_army":
			var parts := []
			for s in o["stacks"]:
				parts.append("%s %s" % [UiStyle.count_word(int(s[1])), session.data.creature(s[0])["name"]])
			txt += "\n%s: %s" % [o.get("name", "Neutral army"), ", ".join(parts)]
	_tile_label.text = txt


## A resource's tooltip: the stock, the daily total and where it comes from
## (entry: one resource of GameSession.income_breakdown()).
static func income_tooltip(res_name: String, amount: int, entry: Dictionary) -> String:
	var tip := "%s: %d in the treasury" % [res_name, amount]
	var total := int(entry.get("total", 0))
	if total <= 0:
		return tip + "\nNo daily income"
	tip += "\n%+d a day:" % total
	for src in entry.get("sources", []):
		tip += "\n   %s  %s" % [src[1], src[0]]
	return tip


static func _army_words(session: GameSession, stacks: Array) -> String:
	var parts := []
	for s in stacks:
		parts.append("%s %s" % [UiStyle.count_word(int(s["count"])), session.data.creature(s["creature"])["name"]])
	return ", ".join(parts)


func clear_log() -> void:
	_log.clear()


func log_message(text: String) -> void:
	_log.append_text(text + "\n")
