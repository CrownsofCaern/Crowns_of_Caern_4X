class_name HeroScreen
extends ModalPanel
## Hero overview: portrait, level and class, primary attributes, experience
## and movement, equipment and pack, class trait and battle art, skills,
## renown, and army management (with the garrison when the hero stands in one
## of the player's towns, and with adjacent heroes).
## A view: army changes go through GameSession.transfer_stack via ArmyExchange,
## equipment through equip_artifact / unequip_artifact / give_artifact.

signal closed
signal learn_pressed
signal changed

const LEVEL_NAMES := ["Untrained", "Basic", "Advanced", "Expert", "Master"]

var session: GameSession
var hero_id := ""
var exchange: ArmyExchange
var _equip_hint: Label
var _active_tab := 0


func open(s: GameSession, id: String) -> void:
	session = s
	hero_id = id
	refresh()
	show()
	UiStyle.fade_in(self)


func close_screen() -> void:
	hide()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and event.keycode in [KEY_ESCAPE, KEY_H]:
		close_screen()
		get_viewport().set_input_as_handled()


## Army rows: the hero, then the garrison of the town they stand in, then
## their own heroes on adjacent tiles.
func army_rows(h: Hero) -> Array:
	var rows := [[h.id, "%s's army" % h.name]]
	var here := session.state.map.object_at(h.pos)
	if not here.is_empty() and here["type"] == "town" and session.visiting_hero(here["id"]) == h:
		rows.append([GameSession.garrison_ref(here["id"]), "Garrison of %s" % here["name"]])
	for other in session.state.heroes_of(h.owner):
		var d: Vector2i = other.pos - h.pos
		if other != h and maxi(absi(d.x), absi(d.y)) <= 1:
			rows.append([other.id, "%s's army (alongside)" % other.name])
	return rows


func refresh() -> void:
	_clear()
	var h := session.hero(hero_id)
	if h == null:
		return
	var cls: Dictionary = _data.hero_classes[h.class_id]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	_body.add_child(top)
	var portrait := HeroPortrait.new(1 if TouchGestures.touch_ui() else 2)
	portrait.set_owner_color(Color(session.state.player(h.owner)["color"]))
	portrait.set_hero(h.id, h.class_id)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(portrait)
	var emblem := UiStyle.icon(Art.faction_emblem(h.faction), Vector2(60, 60))
	emblem.name = "FactionEmblem"
	emblem.tooltip_text = String(_data.factions.get(h.faction, {}).get("name", h.faction))
	emblem.visible = emblem.texture != null
	top.add_child(emblem)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(UiStyle.label(h.name, 28, UiStyle.BRASS))
	var fac: String = _data.factions.get(h.faction, {}).get("name", h.faction)
	var level_line := UiStyle.label("Level %d %s  ·  %s" % [h.level, cls["name"], fac], 15, UiStyle.TEXT_DIM)
	var mech := FactionMechanics.describe(h.faction, _data)
	if mech != "":
		level_line.tooltip_text = mech
		level_line.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(level_line)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 22)
	info.add_child(stats)
	stats.add_child(UiStyle.stat_chip("attack", h.total_attr("attack", _data), "Attack: added to every stack's attack in battle"))
	stats.add_child(UiStyle.stat_chip("defense", h.total_attr("defense", _data), "Defense: added to every stack's defense in battle"))
	stats.add_child(UiStyle.stat_chip("power", h.total_attr("power", _data), "Power: strength of the hero's battle art"))
	stats.add_child(UiStyle.stat_chip("knowledge", h.total_attr("knowledge", _data), "Knowledge: rounds the battle art lasts (1 + Knowledge / 2)"))
	info.add_child(_bar_row(h))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(700, 300)
	_body.add_child(tabs)
	var army_scroll := ScrollContainer.new()
	army_scroll.name = "Units"
	army_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(army_scroll)
	var army := VBoxContainer.new()
	army.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	army_scroll.add_child(army)
	army.add_child(UiStyle.section("Army"))
	exchange = ArmyExchange.new()
	exchange.show_veteran_details = true
	exchange.columns = 5 if TouchGestures.touch_ui() else Army.MAX_SLOTS
	exchange.setup(session, army_rows(h))
	exchange.changed.connect(func(): changed.emit())
	army.add_child(exchange)
	var inventory := VBoxContainer.new()
	inventory.name = "Inventory"
	inventory.add_theme_constant_override("separation", 12)
	tabs.add_child(inventory)
	inventory.add_child(_equipment_block(h))
	inventory.add_child(_pack_block(h))
	var spell_scroll := ScrollContainer.new()
	spell_scroll.name = "Spells"
	spell_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(spell_scroll)
	var spell_list := VBoxContainer.new()
	spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_list.add_theme_constant_override("separation", 8)
	spell_scroll.add_child(spell_list)
	spell_list.add_child(UiStyle.section("Mana: %d / %d" % [h.mana, h.max_mana(_data)]))
	spell_list.add_child(UiStyle.label("Recovers %d each day." % int(_data.rules["mana_daily_regen"]), 13, UiStyle.TEXT_DIM))
	if h.known_spells(_data).is_empty():
		spell_list.add_child(UiStyle.label("No spells known. Class magic unlocks at level %d." % int(_data.magic["class_level"]), 14, UiStyle.TEXT_DIM))
	for spell_id in h.known_spells(_data):
		var spell: Dictionary = _data.magic["spells"].get(spell_id, {})
		if spell.is_empty():
			continue
		var row := HBoxContainer.new()
		spell_list.add_child(row)
		var description := VBoxContainer.new()
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(description)
		description.add_child(UiStyle.label("%s  ·  %d mana" % [spell["name"], int(spell["cost"])], 15, UiStyle.BRASS))
		description.add_child(_wrapped_small(String(spell["description"]), UiStyle.TEXT_DIM))
		var destination := OptionButton.new()
		var destination_ids: Array[String] = []
		if spell["effect"] == "town_gate":
			for town in session.towns_of(h.owner):
				destination.add_item(String(town["name"]))
				destination_ids.append(String(town["id"]))
			row.add_child(destination)
		var cast := Button.new()
		cast.text = "Cast"
		row.add_child(cast)
		var selected_destination := func() -> String:
			return destination_ids[destination.selected] if destination.selected >= 0 and destination.selected < destination_ids.size() else ""
		var update_cast := func() -> void:
			var reason := session.can_cast_spell(hero_id, spell_id, selected_destination.call())
			cast.disabled = reason != ""
			cast.tooltip_text = UiStyle.sentence(reason) if reason != "" else String(spell["description"])
		update_cast.call()
		if spell["effect"] == "town_gate":
			destination.item_selected.connect(func(_index: int): update_cast.call())
		else:
			row.add_child(destination)
			destination.hide()
		cast.pressed.connect(func():
			var target: String = selected_destination.call() if spell["effect"] == "town_gate" else ""
			var result := session.cast_spell(hero_id, spell_id, target)
			if result.get("ok", false):
				AudioManager.play("ui_click")
				refresh()
				changed.emit()
			else:
				AudioManager.play("ui_error"))
	_deep_road_row(spell_list, h)
	var details_scroll := ScrollContainer.new()
	details_scroll.name = "Skills & details"
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(details_scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.add_child(details)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	details.add_child(cols)
	cols.add_child(_class_block(cls, h))
	var skills := VBoxContainer.new()
	skills.add_theme_constant_override("separation", 3)
	skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(skills)
	skills.add_child(UiStyle.section("Skills"))
	if h.skills.is_empty():
		skills.add_child(UiStyle.label("No skills yet.", 13, UiStyle.TEXT_DIM))
	for sk in h.skills:
		var lvl := int(h.skills[sk])
		var line := UiStyle.label("%s  ·  %s" % [_data.skills[sk]["name"], LEVEL_NAMES[clampi(lvl, 0, LEVEL_NAMES.size() - 1)]], 14)
		var lv_text := String(_data.skills[sk]["levels"][clampi(lvl, 1, _data.skills[sk]["levels"].size()) - 1]["text"])
		line.tooltip_text = lv_text
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		skills.add_child(line)
		var eff := UiStyle.label(lv_text, 12, UiStyle.TEXT_DIM)
		skills.add_child(eff)
	if h.skill_points > 0:
		var b := Button.new()
		b.text = "Learn a skill  (%d point%s)" % [h.skill_points, "" if h.skill_points == 1 else "s"]
		b.pressed.connect(func():
			hide()
			learn_pressed.emit())
		skills.add_child(b)
	if not h.marks.is_empty():
		var renown := VBoxContainer.new()
		renown.add_theme_constant_override("separation", 3)
		renown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(renown)
		renown.add_child(UiStyle.section("Renown"))
		var marks: Dictionary = _data.encounter_rules.get("marks", {})
		for m in h.marks:
			renown.add_child(UiStyle.label(marks.get(m, {}).get("name", m), 14))
			var t := UiStyle.label(marks.get(m, {}).get("text", ""), 12, UiStyle.TEXT_DIM)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t.custom_minimum_size.x = 260
			renown.add_child(t)

	tabs.current_tab = clampi(_active_tab, 0, tabs.get_tab_count() - 1)
	tabs.tab_changed.connect(func(index: int): _active_tab = index)
	_buttons([["Close  (H)", close_screen]])
	UiStyle.enlarge_touch_controls(self)


func _bar_row(h: Hero) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var th: Array = _data.progression["xp_thresholds"]
	var lo := int(th[h.level - 1])
	var hi := int(th[mini(h.level, th.size() - 1)])
	row.add_child(UiStyle.ui_icon("xp", 24))
	var xp := ProgressBar.new()
	xp.min_value = lo
	xp.max_value = maxi(hi, lo + 1)
	xp.value = h.xp
	xp.show_percentage = false
	xp.custom_minimum_size = Vector2(150, 14)
	xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp.tooltip_text = "%d / %d experience to the next level" % [h.xp, hi]
	row.add_child(xp)
	row.add_child(UiStyle.label("%d / %d" % [h.xp, hi], 12, UiStyle.TEXT_DIM))
	row.add_child(UiStyle.ui_icon("move", 24))
	var mp := ProgressBar.new()
	mp.max_value = maxi(1, h.max_movement(_data))
	mp.value = h.movement_left
	mp.show_percentage = false
	mp.custom_minimum_size = Vector2(150, 14)
	mp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mp.tooltip_text = "%d / %d movement points today" % [h.movement_left, h.max_movement(_data)]
	row.add_child(mp)
	row.add_child(UiStyle.label("%d / %d" % [h.movement_left, h.max_movement(_data)], 12, UiStyle.TEXT_DIM))
	return row


## Class panel: the hero's personal specialty, what the class is, its trait
## and its battle art.
func _class_block(cls: Dictionary, h: Hero) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spec := h.specialty(session.data)
	if not spec.is_empty():
		v.add_child(UiStyle.section("Specialty: %s" % spec["name"]))
		v.add_child(_wrapped_small(String(spec["text"]), UiStyle.TEXT_DIM))
	v.add_child(UiStyle.section("Class: %s" % cls["name"]))
	v.add_child(_wrapped_small(String(cls.get("text", "")), UiStyle.TEXT_DIM))
	var tr: Dictionary = cls.get("trait", {})
	if not tr.is_empty():
		v.add_child(UiStyle.label("Trait  ·  %s" % tr.get("name", ""), 14))
		v.add_child(_wrapped_small(String(tr.get("text", "")), UiStyle.TEXT_DIM))
	var art: Dictionary = cls.get("art", {})
	if not art.is_empty():
		v.add_child(UiStyle.label("Battle art  ·  %s" % art.get("name", ""), 14))
		v.add_child(_wrapped_small(String(art.get("text", "")), UiStyle.TEXT_DIM))
	return v


## Deep Roads (Sunken Forge heroes): travel to another mine or town of the player.
func _deep_road_row(parent: VBoxContainer, h: Hero) -> void:
	if not FactionMechanics.hero_has(h, "deep_roads", _data):
		return
	var def := FactionMechanics.of_faction(h.faction, _data)
	parent.add_child(UiStyle.section(String(def["name"])))
	parent.add_child(_wrapped_small(String(def["text"]), UiStyle.TEXT_DIM))
	var row := HBoxContainer.new()
	parent.add_child(row)
	var destination := OptionButton.new()
	destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids: Array[String] = []
	for o in FactionMechanics.deep_road_nodes(session.state, h.owner):
		destination.add_item(String(o["name"]) if o["type"] == "town" else Economy.mine_name(o, _data))
		ids.append(String(o["id"]))
	row.add_child(destination)
	var travel := Button.new()
	travel.text = "Travel"
	row.add_child(travel)
	var selected := func() -> String:
		return ids[destination.selected] if destination.selected >= 0 and destination.selected < ids.size() else ""
	var update := func() -> void:
		var reason := session.can_deep_road(hero_id, selected.call())
		travel.disabled = reason != ""
		travel.tooltip_text = UiStyle.sentence(reason) if reason != "" else String(def["text"])
	update.call()
	destination.item_selected.connect(func(_index: int): update.call())
	travel.pressed.connect(func():
		if session.deep_road(hero_id, selected.call()).get("ok", false):
			AudioManager.play("ui_click")
			refresh()
			changed.emit()
		else:
			AudioManager.play("ui_error"))


func _wrapped_small(text: String, color: Color) -> Label:
	var l := UiStyle.label(text, 12, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 220
	return l


## Worn equipment: one slot per artifact slot type, four to a row, and the
## set bonuses the worn pieces earn.
func _equipment_block(h: Hero) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(UiStyle.label("Equipment", 15, UiStyle.BRASS))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var tip := "\n\nClick to take it off" + _give_tip(h)
	for slot in _data.artifact_slots:
		var art := String(h.equipment.get(slot, ""))
		var w := ArtifactSlot.new().setup(slot, art, _data, tip if art != "" else "")
		w.clicked.connect(func(sl: ArtifactSlot, shift: bool): artifact_click(sl.artifact_id, true, shift))
		grid.add_child(w)
	for b in h.active_set_bonuses(_data):
		var l := UiStyle.label("%s, %s" % [b["name"], String(b["text"])], 12, UiStyle.GOOD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 220
		v.add_child(l)
	return v


## The pack: carried artifacts (click to wear) and the free places.
func _pack_block(h: Hero) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var size := int(_data.artifact_rules["pack_size"])
	v.add_child(UiStyle.section("Pack  (%d / %d)" % [h.pack.size(), size], 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	var tip := "\n\nClick to wear it" + _give_tip(h)
	for i in size:
		var art := h.pack[i] if i < h.pack.size() else ""
		var slot_type := String(_data.artifacts[art]["slot"]) if art != "" else ""
		var w := ArtifactSlot.new().setup(slot_type, art, _data, tip if art != "" else "")
		if art == "":
			w.tooltip_text = "Free place in the pack"
		w.clicked.connect(func(sl: ArtifactSlot, shift: bool): artifact_click(sl.artifact_id, false, shift))
		row.add_child(w)
	_equip_hint = UiStyle.label("", 12, UiStyle.TEXT_DIM)
	_equip_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equip_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_equip_hint)
	return v


## Own heroes on adjacent tiles, who can be handed artifacts.
func adjacent_heroes(h: Hero) -> Array:
	var out := []
	for other in session.state.heroes_of(h.owner):
		var d: Vector2i = other.pos - h.pos
		if other != h and maxi(absi(d.x), absi(d.y)) <= 1:
			out.append(other)
	return out


func _give_tip(h: Hero) -> String:
	var near := adjacent_heroes(h)
	return "" if near.is_empty() else "\nShift+click to hand it to %s" % (near[0] as Hero).name


## Takes off a worn artifact or wears a packed one; with shift, hands it to
## the first adjacent hero. Returns the command result.
func artifact_click(artifact_id: String, worn: bool, shift: bool = false) -> Dictionary:
	var h := session.hero(hero_id)
	if h == null or artifact_id == "":
		return {"ok": false, "reason": ""}
	var r: Dictionary
	var near := adjacent_heroes(h)
	if shift and not near.is_empty():
		r = session.give_artifact(h.id, (near[0] as Hero).id, artifact_id)
	elif worn:
		r = session.unequip_artifact(h.id, String(_data.artifacts[artifact_id]["slot"]))
	else:
		r = session.equip_artifact(h.id, artifact_id)
	if r["ok"]:
		refresh()
		changed.emit()
	else:
		AudioManager.play("ui_error")
		if _equip_hint != null:
			_equip_hint.text = UiStyle.sentence(String(r["reason"])) + "."
			_equip_hint.add_theme_color_override("font_color", UiStyle.BAD)
	return r
