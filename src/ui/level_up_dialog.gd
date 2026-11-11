class_name LevelUpDialog
extends ModalPanel
## Skill choice on level-up: one card per offered skill (from
## GameSession.skill_offers), plus "Decide later" so points can be banked.

signal skill_chosen(skill_id: String)
signal closed

const LEVEL_NAMES := ["Untrained", "Basic", "Advanced", "Expert", "Master"]


func show_offers(hero: Hero, offers: Array) -> void:
	_clear()
	var cls: Dictionary = _data.hero_classes[hero.class_id]
	_body.add_child(UiStyle.label("%s, level %d %s" % [hero.name, hero.level, cls["name"]], 22, UiStyle.BRASS))
	_body.add_child(UiStyle.label("%d skill point%s to spend. Choose what the campaign has taught." % [hero.skill_points, "" if hero.skill_points == 1 else "s"], 14, UiStyle.TEXT_DIM))
	var tr: Dictionary = cls.get("trait", {})
	var art: Dictionary = cls.get("art", {})
	var spec := hero.specialty(_data)
	var spec_line := ("Specialty %s: %s\n" % [spec["name"], spec["text"]]) if not spec.is_empty() else ""
	var who := UiStyle.label("%s%s: %s\n%s: %s" % [spec_line, tr.get("name", ""), tr.get("text", ""), art.get("name", ""), art.get("text", "")], 13, UiStyle.TEXT_DIM)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.custom_minimum_size.x = 520
	_body.add_child(who)
	_body.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for sk in offers:
		row.add_child(_card(hero, String(sk)))
	_body.add_child(row)
	if offers.is_empty():
		_body.add_child(UiStyle.label("Every skill this hero can learn is mastered.", 14))
	_buttons([["Decide later", func(): hide(); closed.emit()]])
	show()
	UiStyle.fade_in(self)


func _card(hero: Hero, sk: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.card_box())
	panel.custom_minimum_size = Vector2(250, 150)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var cur := hero.skill_level(sk)
	v.add_child(UiStyle.label(_data.skills[sk]["name"], 18, UiStyle.BRASS))
	v.add_child(UiStyle.label("%s  >  %s" % [_level_name(cur), _level_name(cur + 1)], 13, UiStyle.TEXT_DIM))
	var levels: Array = _data.skills[sk]["levels"]
	var eff := UiStyle.label(String(levels[mini(cur, levels.size() - 1)]["text"]), 14)
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff.custom_minimum_size.x = 226
	eff.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(eff)
	var b := Button.new()
	b.text = "Learn"
	b.custom_minimum_size.y = 34
	b.pressed.connect(func(): skill_chosen.emit(sk))
	v.add_child(b)
	return panel


static func _level_name(lvl: int) -> String:
	return LEVEL_NAMES[clampi(lvl, 0, LEVEL_NAMES.size() - 1)]
