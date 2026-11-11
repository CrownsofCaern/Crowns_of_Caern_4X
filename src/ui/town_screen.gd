class_name TownScreen
extends Control
## Town screen: building tree, recruitment, garrison and visiting hero,
## tavern and market. A view only: every action is a GameSession command.

signal closed
signal changed

const CATEGORY_ORDER := ["civic", "defense", "dwelling", "upgrade", "growth", "special", "ultimate"]
const CATEGORY_TITLES := {"civic": "Civic", "defense": "Fortifications", "dwelling": "Dwellings", "upgrade": "Dwelling upgrades", "growth": "Dwelling improvements", "special": "Faction", "ultimate": "Ultimate"}

var session: GameSession
var town_id := ""
var _data: GameData
var _title: Label
var _town_pic: TownPicture
var _faction_emblem: TextureRect
var _subtitle: Label
var _status: HBoxContainer
var exchange: ArmyExchange
var _town_tabs: TabContainer
var _unit_content: VBoxContainer
var _unit_index := 0
var _scene: TownScene
var _building_scroll: ScrollContainer
var _building_rows: Dictionary = {}
var _buildings: VBoxContainer
var _right: VBoxContainer
var _sell: OptionButton
var _buy: OptionButton
var _amount: SpinBox
var _quote: Label
var _prev_btn: Button
var _next_btn: Button
var _town_pick: OptionButton
var _building_preview: PanelContainer
var _preview_content: VBoxContainer
var _preview_site := ""
var _conversion_dialog: ConfirmationDialog


func build_ui(data: GameData) -> void:
	_data = data
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.make_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	if TouchGestures.touch_ui():
		# A phone shows the town full screen, inside the safe area; the tabs scroll.
		add_child(panel)
		TouchLayout.inset_full_rect(panel, 6)
	else:
		panel.custom_minimum_size = Vector2(1200, 740)
		center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)
	_town_pic = TownPicture.new()
	header.add_child(_town_pic)
	_town_pic.visible = not TouchGestures.touch_ui()
	_faction_emblem = UiStyle.icon(null, Vector2(56, 56))
	_faction_emblem.name = "FactionEmblem"
	header.add_child(_faction_emblem)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 4)
	header.add_child(titles)
	_title = UiStyle.label("", 28, UiStyle.BRASS)
	titles.add_child(_title)
	_subtitle = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	if TouchGestures.touch_ui():
		# The header shares its row with the town switcher on a phone.
		_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_subtitle.custom_minimum_size.x = 200
	titles.add_child(_subtitle)
	_status = HBoxContainer.new()
	_status.add_theme_constant_override("separation", 8)
	titles.add_child(_status)
	var navigation := header
	navigation.add_child(_build_switcher())
	var close := Button.new()
	close.text = "Leave town"
	close.tooltip_text = "Back to the map  (Esc)"
	close.custom_minimum_size = Vector2(150, 38)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_screen)
	navigation.add_child(close)
	root.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	_town_tabs = TabContainer.new()
	_town_tabs.custom_minimum_size = Vector2(600, 0) if TouchGestures.touch_ui() else Vector2(700, 0)
	_town_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_town_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_town_tabs)
	_conversion_dialog = ConfirmationDialog.new()
	_conversion_dialog.title = "Convert town"
	_conversion_dialog.ok_button_text = "Convert"
	_conversion_dialog.confirmed.connect(func():
		_act(session.convert_town(town_id), "build")
		AudioManager.set_music("town", String(session.town(town_id)["town_type"])))
	add_child(_conversion_dialog)
	_scene = TownScene.new()
	_scene.name = "Town view"
	_scene.building_selected.connect(_inspect_building)
	_town_tabs.add_child(_scene)
	_building_preview = PanelContainer.new()
	_building_preview.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_building_preview.offset_left = -280
	_building_preview.offset_right = -10
	_building_preview.offset_top = 10
	_building_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(_building_preview)
	_preview_content = VBoxContainer.new()
	_preview_content.add_theme_constant_override("separation", 6)
	_preview_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_building_preview.add_child(_preview_content)
	_building_preview.hide()
	var left := ScrollContainer.new()
	left.name = "Buildings"
	_building_scroll = left
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_town_tabs.add_child(left)
	_buildings = VBoxContainer.new()
	_buildings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buildings.add_theme_constant_override("separation", 3)
	left.add_child(_buildings)
	var unit_scroll := ScrollContainer.new()
	unit_scroll.name = "Units"
	unit_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_town_tabs.add_child(unit_scroll)
	_unit_content = VBoxContainer.new()
	_unit_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_content.add_theme_constant_override("separation", 12)
	unit_scroll.add_child(_unit_content)
	if not TouchGestures.touch_ui():
		body.add_child(VSeparator.new())
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if TouchGestures.touch_ui():
		right_scroll.name = "Recruit & town"
		_town_tabs.add_child(right_scroll)
	else:
		body.add_child(right_scroll)
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 6)
	right_scroll.add_child(_right)
	hide()


func open(s: GameSession, id: String) -> void:
	session = s
	town_id = id
	refresh()
	_town_tabs.current_tab = 0 if not TownScene.scene_for(String(session.town(id)["town_type"])).is_empty() else 1
	show()
	UiStyle.fade_in(self)
	AudioManager.play("ui_open")
	AudioManager.set_music("town", String(session.town(id).get("town_type", "")))


func close_screen() -> void:
	hide()
	AudioManager.play("ui_close")
	AudioManager.set_music("map")
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed:
		return
	if event.keycode in [KEY_ESCAPE, KEY_T]:
		close_screen()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB:
		switch_town(-1 if event.shift_pressed else 1)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ town switch --

## Previous / next buttons around a list of the player's towns.
func _build_switcher() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prev_btn = Button.new()
	_prev_btn.text = "<"
	_prev_btn.tooltip_text = "Previous town  (Shift+Tab)"
	_prev_btn.custom_minimum_size = Vector2(38, 38)
	_prev_btn.focus_mode = Control.FOCUS_NONE
	_prev_btn.pressed.connect(func(): switch_town(-1))
	box.add_child(_prev_btn)
	_town_pick = OptionButton.new()
	_town_pick.custom_minimum_size = Vector2(190, 38)
	_town_pick.focus_mode = Control.FOCUS_NONE
	_town_pick.clip_text = true
	_town_pick.tooltip_text = "Jump to another of your towns"
	_town_pick.item_selected.connect(func(i: int):
		var ids := own_town_ids()
		if i >= 0 and i < ids.size():
			show_town(ids[i]))
	box.add_child(_town_pick)
	_next_btn = Button.new()
	_next_btn.text = ">"
	_next_btn.tooltip_text = "Next town  (Tab)"
	_next_btn.custom_minimum_size = Vector2(38, 38)
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.pressed.connect(func(): switch_town(1))
	box.add_child(_next_btn)
	return box


## The current player's towns, in map order: what Tab cycles through.
func own_town_ids() -> Array[String]:
	var out: Array[String] = []
	for t in session.towns_of(session.state.current_player):
		out.append(String(t["id"]))
	return out


## Moves to the next (step 1) or previous (step -1) of the player's towns.
## From a town that is not in the list (an ally's), it starts at the first.
func switch_town(step: int) -> void:
	var ids := own_town_ids()
	if ids.is_empty():
		return
	var i := ids.find(town_id)
	var to: String = ids[0] if i < 0 else ids[posmod(i + step, ids.size())]
	if to != town_id:
		show_town(to)


## Shows another town without closing the screen.
func show_town(id: String) -> void:
	if id == town_id or session.town(id).is_empty():
		return
	town_id = id
	refresh()
	AudioManager.play("ui_click")
	AudioManager.set_music("town", String(session.town(id).get("town_type", "")))


func _refresh_switcher() -> void:
	var ids := own_town_ids()
	_town_pick.clear()
	for id in ids:
		_town_pick.add_item(String(session.town(id)["name"]))
	var here := ids.find(town_id)
	if here < 0:
		_town_pick.add_item(String(session.town(town_id).get("name", "")))
		here = ids.size()
	_town_pick.select(here)
	var many := ids.size() > 1 or (ids.size() == 1 and ids[0] != town_id)
	_prev_btn.disabled = not many
	_next_btn.disabled = not many
	_town_pick.disabled = ids.is_empty()


func _cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts := []
	for res in _data.resource_order:
		if int(cost.get(res, 0)) > 0:
			parts.append("%d %s" % [int(cost[res]), _data.resources[res]["name"]])
	return ", ".join(parts)


## Runs a command result through the log; sound_event plays on success.
func _act(r: Dictionary, sound_event: String = "") -> void:
	if r.get("ok", false):
		if sound_event != "":
			AudioManager.play(sound_event)
	else:
		AudioManager.play("ui_error")
		session.message.emit("[color=#d96a52]%s[/color]" % UiStyle.sentence(String(r.get("reason", "Not possible"))))
	refresh()
	changed.emit()


func refresh() -> void:
	_clear_building_preview()
	var t := session.town(town_id)
	if t.is_empty():
		return
	var tt: Dictionary = _data.town_types[t["town_type"]]
	_title.text = t["name"]
	var faction := String(t["town_type"])
	_faction_emblem.texture = Art.faction_emblem(faction)
	_faction_emblem.visible = _faction_emblem.texture != null
	_faction_emblem.tooltip_text = String(_data.factions.get(faction, {}).get("name", faction))
	_refresh_switcher()
	var owner := int(t["owner"])
	_town_pic.setup(Art.sprite("town_" + String(t["town_type"])), Color(session.state.player(owner)["color"]) if owner >= 0 else UiStyle.TEXT_DIM)
	_scene.setup(t, _data)
	var has_scene := not TownScene.scene_for(String(t["town_type"])).is_empty()
	_town_tabs.set_tab_hidden(0, not has_scene)
	if not has_scene:
		_town_tabs.current_tab = 1
	var built_today := int(t["last_build_day"]) == session.state.day
	_subtitle.text = "%s  ·  Week %d, Day %d  ·  %s" % [tt["name"], session.state.week(), session.state.day_of_week(),
		"Already built today" if built_today else "One building may be raised today"]
	for c in _status.get_children():
		_status.remove_child(c)
		c.queue_free()
	_status.add_child(UiStyle.label("Income a day:", 13, UiStyle.TEXT_DIM))
	_status.add_child(UiStyle.cost_row(Town.daily_income(t, _data), _data))
	_status.add_child(UiStyle.ui_icon("defense", 20))
	var def := UiStyle.label("Garrison defense +%d" % Town.defense_bonus(t, _data), 13, UiStyle.TEXT_DIM)
	_status.add_child(def)
	_fill_buildings()
	_fill_units(t)
	_fill_right(t)
	UiStyle.enlarge_touch_controls(self)


## The dwelling and its upgrade are separate entries, ordered by tier.
func _town_units(t: Dictionary) -> Array:
	var units := []
	for id in _data.creatures:
		var c: Dictionary = _data.creature(id)
		if c.get("faction", "") == t["town_type"]:
			units.append(id)
	units.sort_custom(func(a, b):
		var ca: Dictionary = _data.creature(a)
		var cb: Dictionary = _data.creature(b)
		if int(ca["tier"]) != int(cb["tier"]):
			return int(ca["tier"]) < int(cb["tier"])
		return not ca.has("upgrade_of") and cb.has("upgrade_of"))
	return units


func _unit_building(t: Dictionary, cid: String) -> String:
	var creature := _data.creature(cid)
	for id in _data.town_types[t["town_type"]]["buildings"]:
		var building: Dictionary = _data.town_types[t["town_type"]]["buildings"][id]
		for effect in building.get("effects", []):
			if (effect.get("type") == "dwelling" and effect.get("creature") == cid) or (effect.get("type") == "dwelling_upgrade" and effect.get("creature") == creature.get("upgrade_of", "")):
				return String(id)
	return ""


func _fill_units(t: Dictionary) -> void:
	for child in _unit_content.get_children():
		_unit_content.remove_child(child)
		child.queue_free()
	var units := _town_units(t)
	if units.is_empty():
		return
	_unit_index = clampi(_unit_index, 0, units.size() - 1)
	var cid: String = units[_unit_index]
	var c := _data.creature(cid)
	var building := _unit_building(t, cid)
	var available: bool = building != "" and building in t.get("built", [])
	var nav := HBoxContainer.new()
	_unit_content.add_child(nav)
	var prev := Button.new()
	prev.text = "<"
	prev.tooltip_text = "Previous unit"
	prev.custom_minimum_size = Vector2(48, 40)
	prev.disabled = _unit_index == 0
	prev.pressed.connect(func(): _unit_index -= 1; _fill_units(session.town(town_id)))
	nav.add_child(prev)
	var heading := UiStyle.label("Tier %d  ·  %s%s" % [int(c["tier"]), c["name"], " (upgrade)" if c.has("upgrade_of") else ""], 20, UiStyle.BRASS if available else UiStyle.TEXT_DIM)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(heading)
	var next := Button.new()
	next.text = ">"
	next.tooltip_text = "Next unit"
	next.custom_minimum_size = Vector2(48, 40)
	next.disabled = _unit_index == units.size() - 1
	next.pressed.connect(func(): _unit_index += 1; _fill_units(session.town(town_id)))
	nav.add_child(next)
	UiStyle.enlarge_touch_controls(nav)
	var portrait := UiStyle.icon(Art.creature(cid), Vector2(180, 180))
	portrait.modulate = Color.WHITE if available else Color(0.32, 0.32, 0.32, 0.8)
	_unit_content.add_child(portrait)
	if not available:
		var required := String(_data.town_types[t["town_type"]]["buildings"].get(building, {}).get("name", "its dwelling"))
		_unit_content.add_child(UiStyle.label("Unavailable · Build %s to unlock" % required, 16, UiStyle.TEXT_DIM))
		return
	var stats := UiStyle.label(UiStyle.creature_tooltip(_data, cid), 16)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_content.add_child(stats)
	_unit_content.add_child(UiStyle.label("Growth %d per week  ·  Cost: %s" % [int(c["growth"]), _cost_text(c["cost"])], 15))
	var desc := UiStyle.label(String(c.get("desc", "")), 14, UiStyle.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_content.add_child(desc)
	_unit_content.add_child(UiStyle.section("Effects"))
	for ability in c.get("abilities", []):
		var def: Dictionary = _data.abilities.get(ability.get("id", ""), {})
		var values := []
		for key in def.get("params", {}):
			var value: Variant = ability.get(key, def["params"][key])
			if value != "":
				values.append("%s: %s" % [String(key).capitalize(), str(value)])
		var detail := "  (%s)" % ", ".join(values) if not values.is_empty() else ""
		var effect := UiStyle.label("%s: %s%s" % [def.get("name", ability.get("id", "")), def.get("desc", ""), detail], 14)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.tooltip_text = effect.text
		effect.mouse_filter = Control.MOUSE_FILTER_PASS
		_unit_content.add_child(effect)


func _fill_buildings() -> void:
	for c in _buildings.get_children():
		_buildings.remove_child(c)
		c.queue_free()
	_building_rows.clear()
	var opts := session.build_options(town_id)
	for cat in CATEGORY_ORDER:
		var rows := opts.filter(func(o): return o["category"] == cat)
		if rows.is_empty():
			continue
		_buildings.add_child(UiStyle.section(CATEGORY_TITLES[cat], 15))
		for o in rows:
			var row := _building_row(o)
			_buildings.add_child(row)
			_building_rows[String(o["id"])] = row


func _building_row(o: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.tooltip_text = o["description"]
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size.y = 30
	var reason: String = o["reason"]
	var col := UiStyle.GOOD if o["built"] else (UiStyle.TEXT if reason == "" else UiStyle.TEXT_DIM)
	var title := UiStyle.label(o["name"], 14, col)
	title.custom_minimum_size.x = 190
	title.tooltip_text = o["description"]
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(title)
	var info: Control
	if o["built"]:
		info = UiStyle.label(o["description"], 12, UiStyle.TEXT_DIM)
	elif reason.begins_with("requires"):
		info = UiStyle.label("Requires " + reason.trim_prefix("requires "), 12, UiStyle.TEXT_DIM)
	else:
		info = UiStyle.cost_row(o["cost"], _data, session.current_player()["resources"], 12)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.tooltip_text = o["description"]
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	if info is Label:
		(info as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(info)
	if o["built"]:
		var done := UiStyle.label("Built", 13, UiStyle.GOOD.darkened(0.2))
		done.custom_minimum_size.x = 76
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(done)
		return row
	var b := Button.new()
	b.custom_minimum_size = Vector2(76, 26)
	b.add_theme_font_size_override("font_size", 13)
	b.text = "Build"
	b.disabled = reason != ""
	b.tooltip_text = o["description"] + "\nCost: " + _cost_text(o["cost"]) + ("" if reason == "" else "\n" + UiStyle.sentence(reason))
	var id: String = o["id"]
	b.pressed.connect(func(): _act(session.build(town_id, id), "build"))
	row.add_child(b)
	return row


func _clear_right() -> void:
	for c in _right.get_children():
		_right.remove_child(c)
		c.queue_free()


func _fill_right(t: Dictionary) -> void:
	_clear_right()
	if String(t["town_type"]) != String(session.current_player()["faction"]):
		var convert := Button.new()
		convert.text = "Convert town · " + _cost_text(_data.economy["conversion_cost"])
		var reason := session.can_convert_town(town_id)
		convert.disabled = reason != ""
		convert.tooltip_text = UiStyle.sentence(reason) if reason != "" else "Replace buildings and available recruits with your faction's starting town."
		convert.pressed.connect(func():
			_conversion_dialog.dialog_text = "Convert %s to %s for %s? Existing buildings and available recruits will be replaced. The garrison remains." % [t["name"], _data.town_types[session.current_player()["faction"]]["name"], _cost_text(_data.economy["conversion_cost"])]
			_conversion_dialog.popup_centered())
		_right.add_child(convert)
	var visitor := session.visiting_hero(town_id)
	_right.add_child(UiStyle.section("Recruit"))
	var target := UiStyle.label("Recruits join %s." % (visitor.name if visitor != null else "the garrison"), 12, UiStyle.TEXT_DIM)
	_right.add_child(target)
	var bank: ResourceBank = session.current_player()["resources"]
	for o in session.recruit_options(town_id):
		_right.add_child(_recruit_row(o, bank))
	_right.add_child(UiStyle.section("Garrison and visiting hero" if visitor != null else "Garrison"))
	var rows := [[GameSession.garrison_ref(town_id), "Garrison"]]
	if visitor != null:
		rows.append([visitor.id, "%s (visiting)" % visitor.name])
	else:
		_right.add_child(UiStyle.label("No hero in town: stacks can be rearranged within the garrison.", 12, UiStyle.TEXT_DIM))
	exchange = ArmyExchange.new()
	exchange.columns = 5
	exchange.setup(session, rows)
	exchange.changed.connect(func():
		refresh()
		changed.emit())
	_right.add_child(exchange)
	var ups := session.upgrade_options(town_id)
	if not ups.is_empty():
		_right.add_child(UiStyle.section("Upgrade stacks", 15))
		for u in ups:
			var ub := Button.new()
			ub.text = "%d %s -> %s  (%s)%s" % [u["count"], _data.creature(u["creature"])["name"], _data.creature(u["upgrade"])["name"],
				_cost_text(u["cost"]), "" if u["in_garrison"] else "  [hero]"]
			ub.disabled = u["reason"] != ""
			ub.tooltip_text = UiStyle.sentence(String(u["reason"]))
			ub.add_theme_font_size_override("font_size", 13)
			var slot: int = u["slot"]
			var in_g: bool = u["in_garrison"]
			ub.pressed.connect(func(): _act(session.upgrade_stack(town_id, slot, in_g), "upgrade"))
			_right.add_child(ub)
	_right.add_child(HSeparator.new())

	if Town.has_effect(t, "tavern", _data):
		_right.add_child(UiStyle.section("Tavern"))
		var offer := session.hire_offer(town_id)
		var hb := Button.new()
		var reason := session.can_hire_hero(town_id)
		if offer.is_empty():
			hb.text = "No heroes for hire"
		else:
			hb.text = "Hire %s, %s  (%s)" % [offer["name"], _data.hero_classes[offer["class"]]["name"], _cost_text(session.hire_cost(town_id))]
		hb.disabled = reason != ""
		hb.tooltip_text = UiStyle.sentence(reason)
		hb.pressed.connect(func(): _act(session.hire_hero(town_id), "hire_hero"))
		_right.add_child(hb)
		if not offer.is_empty():
			var spec := HeroSpecialties.describe(String(offer["name"]), String(_data.hero_classes[offer["class"]]["faction"]), 1, _data)
			if not spec.is_empty():
				var sl := UiStyle.label("Specialty %s: %s" % [spec["name"], spec["text"]], 12, UiStyle.TEXT_DIM)
				sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				sl.custom_minimum_size.x = 260
				_right.add_child(sl)
		if reason != "" and not offer.is_empty():
			_right.add_child(UiStyle.label(UiStyle.sentence(reason), 12, UiStyle.TEXT_DIM))
		_right.add_child(HSeparator.new())

	var markets := session.market_count(session.state.current_player)
	if markets > 0:
		_right.add_child(UiStyle.section("Market  (%d owned, rate %d%%)" % [markets, roundi(Economy.market_rate(markets, _data) * 100)]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UiStyle.label("Sell", 13))
		_sell = _resource_picker(1)
		row.add_child(_sell)
		_amount = SpinBox.new()
		_amount.min_value = 1
		_amount.max_value = 100000
		_amount.value = 5
		_amount.custom_minimum_size.x = 90
		row.add_child(_amount)
		row.add_child(UiStyle.label("for", 13))
		_buy = _resource_picker(0)
		row.add_child(_buy)
		_quote = UiStyle.label("", 13, UiStyle.BRASS)
		_quote.custom_minimum_size.x = 60
		row.add_child(_quote)
		var tb := Button.new()
		tb.text = "Trade"
		tb.pressed.connect(func(): _act(session.trade(_res_at(_sell), _res_at(_buy), int(_amount.value)), "trade"))
		row.add_child(tb)
		_sell.item_selected.connect(func(_i): _update_quote())
		_buy.item_selected.connect(func(_i): _update_quote())
		_amount.value_changed.connect(func(_v): _update_quote())
		_right.add_child(row)
		_update_quote()

	_add_ally_courier()


## Couriers to allies: send any amount of one resource to a living ally.
func _add_ally_courier() -> void:
	var allies := session.living_allies(session.state.current_player)
	if allies.is_empty():
		return
	if session.market_count(session.state.current_player) > 0:
		_right.add_child(HSeparator.new())   # the tavern section ends with one already
	_right.add_child(UiStyle.section("Couriers to allies"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiStyle.label("Send", 13))
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 100000
	amount.value = 500
	amount.custom_minimum_size.x = 90
	row.add_child(amount)
	var res := _resource_picker(0)
	row.add_child(res)
	row.add_child(UiStyle.label("to", 13))
	var to := OptionButton.new()
	for i in allies:
		to.add_item(String(session.state.player(i)["name"]))
	row.add_child(to)
	var send := Button.new()
	send.text = "Send"
	send.tooltip_text = "The resources reach your ally at once."
	send.pressed.connect(func():
		_act(session.send_resources(allies[to.selected], {_res_at(res): int(amount.value)}), "trade"))
	row.add_child(send)
	_right.add_child(row)


func _resource_picker(selected: int) -> OptionButton:
	var ob := OptionButton.new()
	for res in _data.resource_order:
		ob.add_item(_data.resources[res]["name"])
	ob.select(selected)
	return ob


func _res_at(ob: OptionButton) -> String:
	return _data.resource_order[ob.selected]


func _update_quote() -> void:
	if _quote == null or not is_instance_valid(_quote):
		return
	var got := session.trade_quote(_res_at(_sell), _res_at(_buy), int(_amount.value))
	_quote.text = "= %d" % got


## One dwelling: portrait with the creatures available, name, weekly growth,
## unit cost, an amount and Recruit / Max buttons.
func _recruit_row(o: Dictionary, bank: ResourceBank) -> Control:
	var cid: String = o["creature"]
	var c := _data.creature(cid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tip := UiStyle.creature_tooltip(_data, cid)
	var slot := ArmySlot.new().setup(0, cid, int(o["available"]), tip + "\n%d available" % int(o["available"]))
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(slot)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var n := UiStyle.label("%s  (tier %d)" % [c["name"], int(c["tier"])], 15)
	n.tooltip_text = tip
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(n)
	info.add_child(UiStyle.label("%d available  ·  +%d a week" % [o["available"], o["growth"]], 12, UiStyle.TEXT_DIM))
	var cost := HBoxContainer.new()
	cost.add_child(UiStyle.label("Each:", 12, UiStyle.TEXT_DIM))
	cost.add_child(UiStyle.cost_row(o["cost"], _data, bank, 12))
	info.add_child(cost)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = maxi(0, int(o["max"]))
	spin.value = int(o["max"])
	spin.custom_minimum_size.x = 84
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.editable = int(o["max"]) > 0
	spin.tooltip_text = "You can afford %d" % int(o["max"])
	row.add_child(spin)
	var rb := Button.new()
	rb.text = "Recruit"
	rb.disabled = int(o["max"]) <= 0
	rb.custom_minimum_size = Vector2(84, 32)
	rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rb.add_theme_font_size_override("font_size", 13)
	rb.tooltip_text = "Recruit the chosen number"
	rb.pressed.connect(func(): _act(session.recruit(town_id, cid, int(spin.value)), "recruit"))
	row.add_child(rb)
	return row


## The first click previews a site; a second click on that site builds it.
func _clear_building_preview() -> void:
	_preview_site = ""
	if _building_preview != null:
		_building_preview.hide()


func _inspect_building(id: String) -> void:
	if id == "":
		_clear_building_preview()
		return
	var town := session.town(town_id)
	var scene := TownScene.scene_for(String(town["town_type"]))
	var target := id
	for slot in scene.get("slots", []):
		var variants: Array = slot["variants"]
		if id in variants:
			for variant in variants:
				if variant not in town.get("built", []):
					target = String(variant)
					break
			break
	var option := {}
	for o in session.build_options(town_id):
		if o["id"] == target:
			option = o
			break
	if option.is_empty():
		_clear_building_preview()
		return
	if _preview_site == id:
		if not bool(option["built"]) and option["reason"] == "":
			_act(session.build(town_id, target), "build")
		return
	_preview_site = id
	for child in _preview_content.get_children():
		_preview_content.remove_child(child)
		child.queue_free()
	var title := UiStyle.label(String(option["name"]), 17, UiStyle.BRASS)
	_preview_content.add_child(title)
	var path := String(scene.get("assets", {}).get(target, ""))
	if path != "" and ResourceLoader.exists(path):
		var art := TextureRect.new()
		art.texture = load(path)
		art.custom_minimum_size = Vector2(240, 125)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_preview_content.add_child(art)
		var definition: Dictionary = _data.town_types[town["town_type"]]["buildings"].get(target, {})
		for effect in definition.get("effects", []):
			var cid := String(effect.get("creature", ""))
			if effect.get("type") == "dwelling_upgrade":
				cid = String(_data.creature(cid).get("upgrade", ""))
			elif effect.get("type") != "dwelling":
				continue
			if cid != "":
				var unit_art := UiStyle.icon(Art.creature(cid), Vector2(64, 64))
				unit_art.tooltip_text = String(_data.creature(cid).get("name", cid))
				unit_art.position = Vector2(170, 60)
				unit_art.size = Vector2(64, 64)
				art.add_child(unit_art)
	var description := UiStyle.label(String(option["description"]), 13)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_content.add_child(description)
	if option["built"]:
		_preview_content.add_child(UiStyle.label("Already built", 13, UiStyle.GOOD))
	else:
		_preview_content.add_child(UiStyle.label("Cost: " + _cost_text(option["cost"]), 13, UiStyle.BRASS))
		var status := "Click the site again to build" if option["reason"] == "" else UiStyle.sentence(String(option["reason"]))
		var label := UiStyle.label(status, 13, UiStyle.TEXT_DIM)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_preview_content.add_child(label)
	# The preview must not intercept the second click on the town scene.
	for child in _preview_content.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_building_preview.show()
