class_name ArenaScreen
extends Control
## The Battle Arena (see Arena): a setup page (sandbox or rogue, factions,
## heroes, options) and the arena page with both armies, the town and hero
## screens, the battle forecast, the battle viewer and the report.
## Self-contained: it keeps its own Arena session and its own dialogs, so it
## can also open over an online game while the other players move.

signal closed

const SETTINGS_PATH := "user://arena.cfg"

var data: GameData
var arena: Arena
## True when opened while waiting in an online game (no music changes).
var mini_game := false
var _setup: PanelContainer
var _page: PanelContainer
var _mode_pick: OptionButton
var _faction_pick: OptionButton
var _class_pick: OptionButton
var _level_pick: OptionButton
var _enemy_mode_pick: OptionButton
var _enemy_faction_pick: OptionButton
var _enemy_class_pick: OptionButton
var _enemy_level_pick: OptionButton
var _terrain_pick: OptionButton
var _difficulty_pick: OptionButton
var _infinite_check: CheckBox
var _ultimate_check: CheckBox
var _enemy_ultimate_check: CheckBox
var _sandbox_box: VBoxContainer
var _rogue_box: VBoxContainer
var _record_label: Label
var _title: Label
var _subtitle: Label
var _treasury: HBoxContainer
var _you_box: VBoxContainer
var _foe_box: VBoxContainer
var _buttons: HFlowContainer
var _status: Label
var _keep_losses: CheckBox
var _fight_btn: Button
var town_screen: TownScreen
var hero_screen: HeroScreen
var panels: BattlePanels
var viewer: BattleViewer
var level_up: LevelUpDialog
var found_dialog: ArtifactFoundDialog
var _editing_enemy := false
var _points_before := 0


func build(game_data: GameData) -> void:
	data = game_data
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.make_theme()
	var bg := ColorRect.new()
	bg.color = Color("#0b0a09")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var backdrop := MenuArt.backdrop("title")
	if backdrop != null:
		backdrop.modulate = Color(1, 1, 1, 0.35)
		add_child(backdrop)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var col := VBoxContainer.new()
	center.add_child(col)
	_setup = PanelContainer.new()
	_setup.add_theme_stylebox_override("panel", UiStyle.frame_panel(18))
	_setup.custom_minimum_size = Vector2(760, 0)
	col.add_child(_setup)
	_build_setup()
	_page = PanelContainer.new()
	_page.add_theme_stylebox_override("panel", UiStyle.frame_panel(18))
	_page.custom_minimum_size = Vector2(980, 0)
	col.add_child(_page)
	_build_page()
	_page.hide()

	town_screen = TownScreen.new()
	add_child(town_screen)
	town_screen.build_ui(data)
	town_screen.closed.connect(_after_town)
	town_screen.changed.connect(func():
		arena.refill()
		_refresh())
	hero_screen = HeroScreen.new()
	add_child(hero_screen)
	hero_screen.build(data, 760)
	hero_screen.closed.connect(_refresh)
	hero_screen.changed.connect(_refresh)
	hero_screen.learn_pressed.connect(_open_level_up)
	panels = BattlePanels.new()
	add_child(panels)
	panels.build(data)
	panels.attack_confirmed.connect(_on_attack_confirmed)
	panels.orders_changed.connect(func(orders: Dictionary):
		arena.session.set_battle_orders(Arena.PLAYER_HERO, orders)
		_show_forecast())
	panels.report_closed.connect(_after_report)
	panels.watch_requested.connect(func(result: Dictionary):
		panels.hide()
		await viewer.play(result, "", 0, panels.settings_path)
		panels.show())
	viewer = BattleViewer.new()
	add_child(viewer)
	viewer.build()
	level_up = LevelUpDialog.new()
	add_child(level_up)
	level_up.build(data, 560)
	level_up.skill_chosen.connect(_on_skill_chosen)
	level_up.closed.connect(_refresh)
	found_dialog = ArtifactFoundDialog.new()
	add_child(found_dialog)
	found_dialog.build(data, 600)
	UiStyle.enlarge_touch_controls(self)
	hide()


## Opens the arena: back to the running arena if there is one, else the setup page.
func open(as_mini_game: bool = false) -> void:
	mini_game = as_mini_game
	show()
	if arena != null and not (arena.is_rogue() and arena.run_over):
		_show_page()
	else:
		_show_setup()
	if not mini_game:
		AudioManager.set_music("battle")


func leave() -> void:
	for d in [town_screen, hero_screen, panels, level_up, found_dialog]:
		d.hide()
	hide()
	closed.emit()


# ------------------------------------------------------------------ setup --

func _picker(parent: Container, caption: String, tip: String = "") -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := UiStyle.label(caption, 15, UiStyle.TEXT_DIM)
	l.custom_minimum_size.x = 170
	row.add_child(l)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.tooltip_text = tip
	row.add_child(pick)
	return pick


func _check(parent: Container, text: String, tip: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.button_pressed = on
	parent.add_child(c)
	return c


func _build_setup() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_setup.add_child(v)
	v.add_child(UiStyle.label("Battle Arena", 26, UiStyle.BRASS))
	var intro := UiStyle.label("Quick battles away from the map. Sandbox: set up both sides and test any matchup. Rogue: a run of ever stronger foes, with rewards after every victory.", 13, UiStyle.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	_mode_pick = _picker(v, "Mode")
	_mode_pick.add_item("Sandbox")
	_mode_pick.add_item("Rogue")
	_mode_pick.item_selected.connect(func(_i): _sync_setup())
	v.add_child(HSeparator.new())
	_faction_pick = _picker(v, "Your faction")
	_class_pick = _picker(v, "Your hero")
	for f in GameSetup.playable_factions(data):
		_faction_pick.add_item(String(data.factions[f]["name"]))
		_faction_pick.set_item_metadata(_faction_pick.item_count - 1, f)
	_faction_pick.item_selected.connect(func(_i): _fill_classes(_class_pick, _faction_pick))
	_fill_classes(_class_pick, _faction_pick)

	_sandbox_box = VBoxContainer.new()
	_sandbox_box.add_theme_constant_override("separation", 10)
	v.add_child(_sandbox_box)
	_level_pick = _picker(_sandbox_box, "Your hero's level")
	_fill_levels(_level_pick)
	_infinite_check = _check(_sandbox_box, "Endless resources", "Both treasuries stay full: recruit anything.", true)
	_ultimate_check = _check(_sandbox_box, "Your town has its ultimate building", "Your creatures fight with your faction's ultimate upgrade.", false)
	_sandbox_box.add_child(HSeparator.new())
	_enemy_mode_pick = _picker(_sandbox_box, "Enemy army", "Build by hand: recruit the enemy in its own town.\nFight equal: the enemy is built to match your army's strength.")
	_enemy_mode_pick.add_item("Build by hand")
	_enemy_mode_pick.add_item("Fight equal (auto-built)")
	_enemy_faction_pick = _picker(_sandbox_box, "Enemy faction")
	_enemy_class_pick = _picker(_sandbox_box, "Enemy hero")
	for f in GameSetup.playable_factions(data):
		_enemy_faction_pick.add_item(String(data.factions[f]["name"]))
		_enemy_faction_pick.set_item_metadata(_enemy_faction_pick.item_count - 1, f)
	_enemy_faction_pick.select(mini(1, _enemy_faction_pick.item_count - 1))
	_enemy_faction_pick.item_selected.connect(func(_i): _fill_classes(_enemy_class_pick, _enemy_faction_pick))
	_fill_classes(_enemy_class_pick, _enemy_faction_pick)
	_enemy_level_pick = _picker(_sandbox_box, "Enemy hero's level")
	_fill_levels(_enemy_level_pick)
	_enemy_ultimate_check = _check(_sandbox_box, "Enemy town has its ultimate building", "The enemy's creatures fight with their faction's ultimate upgrade.", false)
	_terrain_pick = _picker(_sandbox_box, "Battlefield")
	for t in Arena.battle_terrains(data):
		_terrain_pick.add_item(String(data.terrains[t]["name"]))
		_terrain_pick.set_item_metadata(_terrain_pick.item_count - 1, t)

	_rogue_box = VBoxContainer.new()
	_rogue_box.add_theme_constant_override("separation", 10)
	v.add_child(_rogue_box)
	_difficulty_pick = _picker(_rogue_box, "Difficulty")
	for d in Arena.DIFFICULTIES:
		_difficulty_pick.add_item(String(Arena.ROGUE[d]["name"]))
		_difficulty_pick.set_item_metadata(_difficulty_pick.item_count - 1, d)
	_difficulty_pick.select(1)
	_difficulty_pick.item_selected.connect(func(_i): _sync_setup())
	var rules := UiStyle.label("Start with a small purse for a few tier 1-2 stacks. Your town is fully built and its troops never run out, but gold does. Every victory pays gold and resources, sometimes equipment; your hero levels up and your troops become veterans. Losses stay lost. The run ends when your hero falls.\nHard: every foe is built to match your own strength, veterans and hero included.", 13, UiStyle.TEXT_DIM)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rogue_box.add_child(rules)
	_record_label = UiStyle.label("", 14, UiStyle.BRASS)
	_rogue_box.add_child(_record_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(130, 38)
	back.pressed.connect(leave)
	buttons.add_child(back)
	var go := Button.new()
	go.text = "Enter the Arena"
	go.custom_minimum_size = Vector2(190, 38)
	go.pressed.connect(_start)
	buttons.add_child(go)
	_sync_setup()


func _fill_classes(pick: OptionButton, faction_pick: OptionButton) -> void:
	pick.clear()
	for id in GameSetup.classes_for_faction(data, String(faction_pick.get_selected_metadata())):
		pick.add_item(String(data.hero_classes[id]["name"]))
		pick.set_item_metadata(pick.item_count - 1, id)
		pick.set_item_tooltip(pick.item_count - 1, String(data.hero_classes[id].get("text", "")))


func _fill_levels(pick: OptionButton) -> void:
	for lv in range(1, Arena.max_level(data) + 1):
		pick.add_item(str(lv))


func _sync_setup() -> void:
	var rogue := _mode_pick.selected == 1
	_sandbox_box.visible = not rogue
	_rogue_box.visible = rogue
	var best := best_round(String(_difficulty_pick.get_selected_metadata()))
	_record_label.text = "Best run on %s: %d victories." % [_difficulty_pick.get_item_text(_difficulty_pick.selected), best] if best > 0 else ""


func _show_setup() -> void:
	_page.hide()
	_setup.show()
	_sync_setup()


func current_config() -> Dictionary:
	return {"mode": "rogue" if _mode_pick.selected == 1 else "sandbox",
		"faction": String(_faction_pick.get_selected_metadata()), "hero_class": String(_class_pick.get_selected_metadata()),
		"level": _level_pick.selected + 1, "infinite": _infinite_check.button_pressed, "ultimate": _ultimate_check.button_pressed,
		"enemy": "equal" if _enemy_mode_pick.selected == 1 else "build",
		"enemy_faction": String(_enemy_faction_pick.get_selected_metadata()), "enemy_class": String(_enemy_class_pick.get_selected_metadata()),
		"enemy_level": _enemy_level_pick.selected + 1, "enemy_ultimate": _enemy_ultimate_check.button_pressed,
		"terrain": String(_terrain_pick.get_selected_metadata()), "difficulty": String(_difficulty_pick.get_selected_metadata()),
		"seed": int(Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system()))}


func _start() -> void:
	arena = Arena.create(data, current_config())
	arena.session.message.connect(func(t: String): _status.text = t.replace("[color=#d96a52]", "").replace("[/color]", ""))
	_status.text = "Recruit your army in your town, then fight." if arena.config["enemy"] == "build" or arena.is_rogue() else "Recruit your army; the enemy is built to match it when you fight."
	_show_page()


# ------------------------------------------------------------- arena page --

func _build_page() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_page.add_child(v)
	_title = UiStyle.label("", 26, UiStyle.BRASS)
	v.add_child(_title)
	_subtitle = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_subtitle)
	_treasury = HBoxContainer.new()
	v.add_child(_treasury)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 24)
	v.add_child(sides)
	_you_box = VBoxContainer.new()
	_you_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_child(_you_box)
	sides.add_child(VSeparator.new())
	_foe_box = VBoxContainer.new()
	_foe_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_child(_foe_box)
	v.add_child(HSeparator.new())
	_status = UiStyle.label("", 14, UiStyle.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	_keep_losses = CheckBox.new()
	_keep_losses.text = "Keep losses after a fight"
	_keep_losses.tooltip_text = "Off: both armies stand as they were before every fight, so the same matchup can be fought again."
	v.add_child(_keep_losses)
	_buttons = HFlowContainer.new()
	_buttons.add_theme_constant_override("h_separation", 10)
	_buttons.add_theme_constant_override("v_separation", 8)
	v.add_child(_buttons)


func _button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(150, 40)
	b.pressed.connect(cb)
	_buttons.add_child(b)
	return b


func _show_page() -> void:
	_setup.hide()
	_page.show()
	_refresh()


func _refresh() -> void:
	if arena == null or not _page.visible:
		return
	var s := arena.session
	var rogue := arena.is_rogue()
	if rogue:
		_title.text = "Rogue run · %s · Fight %d" % [String(arena.difficulty()["name"]), arena.wins + 1]
		_subtitle.text = "Next foe: %s, on %s." % [arena.enemy_summary(), String(data.terrains[arena.field_terrain()]["name"])]
	else:
		_title.text = "Arena sandbox"
		_subtitle.text = "Battlefield: %s.%s" % [String(data.terrains[arena.field_terrain()]["name"]),
			" Enemy built to match your army when you fight." if arena.config["enemy"] == "equal" else ""]
	for c in _treasury.get_children():
		c.queue_free()
	if rogue or not bool(arena.config["infinite"]):
		_treasury.add_child(UiStyle.label("Treasury:", 14, UiStyle.TEXT_DIM))
		var bank: ResourceBank = s.state.player(0)["resources"]
		var amounts := {}
		for res in data.resource_order:
			if bank.get_amount(res) > 0 or res == "gold":
				amounts[res] = bank.get_amount(res)
		_treasury.add_child(UiStyle.cost_row(amounts, data))
	_fill_side(_you_box, arena.player_hero(), "You")
	_fill_side(_foe_box, arena.enemy_hero(), "Enemy")
	_keep_losses.visible = not rogue
	for c in _buttons.get_children():
		c.queue_free()
	var over := rogue and arena.run_over
	if not over:
		_button("Recruit", "Your fully built town: recruit into your hero's army (T)", _open_town)
		_button("Hero", "Your hero: skills, equipment and army (H)", _open_hero)
		if not rogue and arena.config["enemy"] == "build":
			_button("Enemy town", "Recruit the enemy's army", _open_enemy_town)
			_button("Enemy hero", "The enemy hero's equipment, skills and army", _open_enemy_hero)
		_fight_btn = _button("Fight!", "See the forecast, set your orders and formation, then fight (F)", _show_forecast)
		_fight_btn.disabled = arena.player_hero().army.is_empty()
	else:
		_button("New run", "Back to the arena setup", _show_setup)
	_button("Leave arena", "Back to where you came from" + (" (the run is kept until you start another)" if rogue and not over else ""), leave)
	UiStyle.enlarge_touch_controls(_page)


func _fill_side(box: VBoxContainer, h: Hero, caption: String) -> void:
	for c in box.get_children():
		c.queue_free()
	if h == null:
		box.add_child(UiStyle.label("%s: nobody" % caption, 16, UiStyle.TEXT_DIM))
		return
	box.add_child(UiStyle.label("%s: %s" % [caption, h.name], 18, UiStyle.BRASS))
	var p := h.combat_profile(data)
	box.add_child(UiStyle.label("Level %d %s of %s · Attack %d · Defense %d" % [h.level, String(data.hero_classes[h.class_id]["name"]),
		String(data.factions[h.faction]["name"]), int(p["attack"]), int(p["defense"])], 13, UiStyle.TEXT_DIM))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for st in h.army.slots:
		if st.is_empty():
			continue
		var lv := Army.veteran_level(st)
		grid.add_child(UiStyle.creature_slot(Art.creature(String(st["creature"]), lv), str(int(st["count"])),
			UiStyle.creature_tooltip(data, String(st["creature"]), int(st["count"]), lv)))
	if h.army.is_empty():
		box.add_child(UiStyle.label("No troops yet.", 13, UiStyle.TEXT_DIM))
	box.add_child(UiStyle.label("Strength about %d gold" % int(arena.power_of(h)), 13, UiStyle.TEXT_DIM))


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or not _page.visible or _modal_open():
		return
	match event.keycode:
		KEY_T:
			_open_town()
		KEY_H:
			_open_hero()
		KEY_F:
			if _fight_btn != null and is_instance_valid(_fight_btn) and not _fight_btn.disabled:
				_show_forecast()
		KEY_ESCAPE:
			leave()
		_:
			return
	get_viewport().set_input_as_handled()


func _modal_open() -> bool:
	return town_screen.visible or hero_screen.visible or panels.visible or level_up.visible or found_dialog.visible or viewer.is_playing()


func _open_town() -> void:
	if arena.run_over:
		return
	arena.end_enemy_edit()
	_editing_enemy = false
	town_screen.open(arena.session, Arena.PLAYER_TOWN)


func _open_enemy_town() -> void:
	arena.begin_enemy_edit()
	_editing_enemy = true
	town_screen.open(arena.session, Arena.ENEMY_TOWN)


func _after_town() -> void:
	if _editing_enemy:
		arena.end_enemy_edit()
		_editing_enemy = false
	if not mini_game:
		AudioManager.set_music("battle")
	_refresh()


func _open_hero() -> void:
	arena.end_enemy_edit()
	hero_screen.open(arena.session, Arena.PLAYER_HERO)


func _open_enemy_hero() -> void:
	# The enemy takes the turn while its screen is open, so its gear can be changed.
	arena.session.state.current_player = 1
	hero_screen.open(arena.session, arena.enemy_id)
	await hero_screen.closed
	arena.session.state.current_player = 0


# ----------------------------------------------------------------- battle --

func _show_forecast() -> void:
	var me := arena.player_hero()
	if me.army.is_empty():
		_status.text = "Recruit some troops first."
		return
	arena.end_enemy_edit()
	if not arena.is_rogue() and arena.config["enemy"] == "equal":
		arena.build_equal_enemy()
		_refresh()
	arena.reveal_enemy()
	var pred := arena.session.preview_battle(me.id, arena.enemy_id)
	pred["scout_cost"] = 0
	pred["scout_reason"] = "The arena shows every enemy in full."
	pred["orders"] = arena.session.order_choices(me.id)
	panels.show_forecast(String(pred["enemy"]["name"]), pred)


func _on_attack_confirmed() -> void:
	var me := arena.player_hero()
	_points_before = me.skill_points
	AudioManager.play("battle_start")
	var result := arena.fight()
	if not result.get("ok", true) or not result.has("winner"):
		_status.text = String(result.get("reason", "The fight could not start."))
		return
	if BattleViewer.watch_enabled(panels.settings_path) and result.has("log"):
		await viewer.play(result, me.name, 0, panels.settings_path)
	AudioManager.play_stinger("battle_victory" if result["winner"] == 0 else "battle_defeat")
	var after := arena.after_fight(result)
	if not arena.is_rogue() and not _keep_losses.button_pressed:
		arena.restore_armies()
	_status.text = _after_text(result, after)
	if after["run_over"]:
		record_run(String(arena.config["difficulty"]), arena.wins)
	_refresh()
	panels.show_report(result)
	if not (after["found"] as Array).is_empty():
		await panels.report_closed
		found_dialog.open(arena.player_hero(), after["found"])


func _after_text(result: Dictionary, after: Dictionary) -> String:
	var won := int(result["winner"]) == 0
	if not arena.is_rogue():
		return ("Victory! +%d XP." % int(result.get("xp_gained", 0)) if won else "Defeat.") + ("" if _keep_losses.button_pressed else " Both armies are back as they were.")
	if after["run_over"]:
		return "Your hero has fallen. The run ends after %d victor%s." % [arena.wins, "y" if arena.wins == 1 else "ies"]
	if not won:
		return "You fell back. The foe keeps its survivors; recruit and try again."
	var parts := ["+%d gold" % int(after["gold"])]
	for res in after["resources"]:
		parts.append("+%d %s" % [int(after["resources"][res]), String(data.resources[res]["name"]).to_lower()])
	return "Victory %d! Rewards: %s.%s A new foe steps up." % [arena.wins, ", ".join(parts),
		" You found equipment!" if not (after["found"] as Array).is_empty() else ""]


func _after_report() -> void:
	_refresh()
	var me := arena.player_hero()
	if me != null and me.alive and me.skill_points > _points_before:
		_open_level_up()


func _open_level_up() -> void:
	var me := arena.player_hero()
	if me == null or me.skill_points <= 0:
		return
	AudioManager.play("level_up")
	level_up.show_offers(me, arena.session.skill_offers(me.id))


func _on_skill_chosen(skill_id: String) -> void:
	var me := arena.player_hero()
	if not arena.session.learn_skill(me.id, skill_id):
		return
	_points_before = me.skill_points
	if me.skill_points > 0:
		level_up.show_offers(me, arena.session.skill_offers(me.id))
	else:
		level_up.hide()
	_refresh()


# ---------------------------------------------------------------- records --

static func best_round(difficulty: String, path: String = SETTINGS_PATH) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return 0
	return int(cfg.get_value("rogue", difficulty, 0))


static func record_run(difficulty: String, wins: int, path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	if wins > int(cfg.get_value("rogue", difficulty, 0)):
		cfg.set_value("rogue", difficulty, wins)
		cfg.save(path)
