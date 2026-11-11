class_name BattlePanels
extends Control
## Modal battle forecast and battle report, styled after the art reference:
## a battlefield picture band, a clear verdict, and each army as portraits
## with counts (losses in red). Enter confirms, Esc withdraws.

signal attack_confirmed
signal attack_cancelled
signal incoming_choice(flee: bool)
signal report_closed
## The player asked for a scout from the forecast (see show_forecast).
signal scout_requested
## The player asked to watch the battle on the report (see show_report).
signal watch_requested(result: Dictionary)
## The player changed the hero's battle orders on the forecast
## ({stance, focus, formation, art, retreat}).
signal orders_changed(orders: Dictionary)

## Where the "watch the battle" choice is remembered (tests point it elsewhere).
var settings_path := BattleViewer.SETTINGS_PATH
## The result the report shows (tools replay it).
var last_result: Dictionary = {}

const WIDTH := 720

var _data: GameData
var _dim: ColorRect
var _panel: PanelContainer
var _footer: VBoxContainer
var _body: VBoxContainer
var _mode := ""             # "forecast" or "report"
var _details: VBoxContainer
var _details_toggle: Button


func build(data: GameData) -> void:
	_data = data
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.make_theme()
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
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
	_details = null


func _open(mode: String) -> void:
	_mode = mode
	show()
	UiStyle.fade_in(self)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed:
		return
	if event.keycode == KEY_S and _mode == "forecast":
		scout_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if _mode == "incoming":
			hide()
			incoming_choice.emit(false)
		elif _mode == "forecast":
			_confirm()
		else:
			_continue()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		if _mode == "incoming":
			return
		if _mode == "forecast":
			_cancel()
		else:
			_continue()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	hide()
	attack_confirmed.emit()


func _cancel() -> void:
	hide()
	attack_cancelled.emit()


func _continue() -> void:
	hide()
	report_closed.emit()


## specs: [[text, callable, tooltip?, disabled?], ...]
func _buttons(specs: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	for s in specs:
		var b := Button.new()
		b.text = s[0]
		b.tooltip_text = s[2] if s.size() > 2 else ""
		b.disabled = s.size() > 3 and bool(s[3])
		b.custom_minimum_size = Vector2(150, 38)
		b.pressed.connect(s[1])
		row.add_child(b)
	(_footer if _footer != null else _body).add_child(row)
	return row


func _centered(text: String, size: int, color: Color) -> Label:
	var l := UiStyle.label(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _forecast_color(p: float) -> Color:
	if p >= 0.8: return UiStyle.GOOD
	if p >= 0.4: return UiStyle.WARN
	return UiStyle.BAD


## A creature portrait with a caption under it (count word, or a loss).
func _card(creature: String, count: int, caption: String, caption_color: Color, tip: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var slot := ArmySlot.new().setup(0, creature, count, tip)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(slot)
	var l := _centered(caption, 15 if caption.length() < 6 else 12, caption_color)
	l.custom_minimum_size.x = ArmySlot.SIZE
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(l)
	return v


func _column(title: String, cards: Array, empty_text: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UiStyle.label(title, 15, UiStyle.TEXT_DIM))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for c in cards:
		flow.add_child(c)
	if cards.is_empty():
		flow.add_child(UiStyle.label(empty_text, 14, UiStyle.TEXT_DIM))
	col.add_child(flow)
	return col


func _two_columns(a: Control, b: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(a)
	var sep := VSeparator.new()
	row.add_child(sep)
	row.add_child(b)
	_body.add_child(row)


func show_forecast(enemy_name: String, pred: Dictionary) -> void:
	_clear()
	if pred.get("concealed", false):
		_show_cobolt_commitment(enemy_name, pred)
		return
	var vig := BattleVignette.new()
	var mine := []
	for st in pred["stacks"]:
		mine.append({"creature": st["creature"], "alive": true})
	var theirs := []
	for st in pred["enemy"]["stacks"]:
		theirs.append({"creature": st["creature"], "alive": true})
	vig.setup(String(pred.get("visual_terrain",pred["terrain"])), mine, theirs, int(pred.get("visual_seed",0)))
	_body.add_child(vig)
	_body.add_child(_centered("Engage %s?" % enemy_name, 24, UiStyle.BRASS))
	var ter: Dictionary = _data.terrain(pred["terrain"])
	_body.add_child(_centered("Battlefield: %s  ·  forecast from %d simulated battles" % [ter.get("name", pred["terrain"]), pred["simulations"]], 13, UiStyle.TEXT_DIM))

	# What the player may know (GameSession.odds_shown): "exact" once scouted,
	# a worded verdict only before, nothing in hard mode.
	var odds := String(pred.get("odds", "exact"))
	var scouted := bool(pred.get("scouted", true))
	var p: float = pred["win_probability"]
	var verdict := HBoxContainer.new()
	verdict.alignment = BoxContainer.ALIGNMENT_CENTER
	verdict.add_theme_constant_override("separation", 14)
	if odds == "none":
		verdict.add_child(UiStyle.label("The odds are hidden", 22, UiStyle.TEXT_DIM))
	else:
		verdict.add_child(UiStyle.label(pred["label"], 24, _forecast_color(p) if odds == "exact" else MapTip.verdict_color(pred["label"])))
	if odds == "exact":
		var meter := ProgressBar.new()
		meter.custom_minimum_size = Vector2(220, 18)
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meter.max_value = 100
		meter.value = roundi(p * 100)
		meter.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = _forecast_color(p).darkened(0.1)
		fill.set_corner_radius_all(3)
		meter.add_theme_stylebox_override("fill", fill)
		meter.tooltip_text = "Share of simulated battles won"
		verdict.add_child(meter)
		verdict.add_child(UiStyle.label("%d%% to win" % roundi(p * 100), 16, UiStyle.TEXT))
	_body.add_child(verdict)
	if odds == "exact":
		_body.add_child(_centered("Expected losses: %d%% of your strength  (likely %d%% to %d%%)" % [
			roundi(pred["expected_loss_fraction"] * 100), roundi(pred["loss_fraction_low"] * 100), roundi(pred["loss_fraction_high"] * 100)], 14, UiStyle.TEXT))
	elif odds == "label":
		_body.add_child(_centered("Send a scout for exact numbers, the win chance and your expected losses.", 14, UiStyle.TEXT_DIM))
	elif not scouted:
		_body.add_child(_centered("Hard mode: send a scout to count the enemy exactly.", 14, UiStyle.TEXT_DIM))
	_body.add_child(HSeparator.new())

	var my_cards := []
	for st in pred["stacks"]:
		if odds == "exact":
			var lost := roundi(st["expected_lost"])
			var tip := UiStyle.creature_tooltip(_data, st["creature"], int(st["count"])) + "\nExpected losses: ~%d (likely %d to %d)" % [lost, st["low"], st["high"]]
			my_cards.append(_card(st["creature"], int(st["count"]), "-%d" % lost if lost > 0 else "safe",
				UiStyle.BAD if lost > 0 else UiStyle.GOOD, tip))
		else:
			my_cards.append(_card(st["creature"], int(st["count"]), "", UiStyle.TEXT,
				UiStyle.creature_tooltip(_data, st["creature"], int(st["count"]))))
	var foe_cards := []
	for st in pred["enemy"]["stacks"]:
		var n := int(st["count"])
		if scouted:
			foe_cards.append(_card(st["creature"], n, "", UiStyle.TEXT,
				UiStyle.creature_tooltip(_data, st["creature"], n) + "\nScouted: exactly %d" % n))
		else:
			foe_cards.append(_card(st["creature"], 0, UiStyle.count_caption(n), UiStyle.TEXT,
				UiStyle.creature_tooltip(_data, st["creature"]) + "\nRough count: %s (%s)" % [UiStyle.count_caption(n).to_lower(), UiStyle.count_range(n)]))
	_two_columns(_column("Your army (expected losses)" if odds == "exact" else "Your army", my_cards, "No troops"),
		_column("Scouts report (exact)" if scouted else "Rough estimate", foe_cards, "Unknown"))
	if pred.has("orders"):
		_body.add_child(_orders_row(pred["orders"]))
	var buttons := [["Withdraw", _cancel, "Back away  (Esc)"]]
	if not scouted:
		var why := String(pred.get("scout_reason", ""))
		var cost := int(pred.get("scout_cost", 0))
		buttons.append(["Send scout", func(): scout_requested.emit(),
			why if why != "" else "Exact numbers%s for %s  (S)" % ["" if odds == "none" else " and odds", "no movement" if cost <= 0 else "%d movement" % cost],
			why != ""])
	buttons.append(["Attack!", _confirm, "Fight  (Enter)"])
	var row := _buttons(buttons)
	var watch := CheckBox.new()
	watch.text = "Watch the battle"
	watch.tooltip_text = "Play the fight out on a battlefield before the report.\nThe outcome is the same either way."
	watch.focus_mode = Control.FOCUS_NONE
	watch.button_pressed = BattleViewer.watch_enabled(settings_path)
	watch.toggled.connect(func(on: bool): BattleViewer.set_watch_enabled(on, settings_path))
	var three_d := _three_d_box(watch)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(watch)
	row.add_child(three_d)
	row.add_child(spacer)
	row.move_child(watch, 0)
	row.move_child(three_d, 1)
	row.move_child(spacer, 2)
	_open("forecast")


## Battle order pickers, all set before the fight: stance and focus on the
## first line, formation, art timing and retreat order on the second.
## orders: {stance, focus, formation, art, retreat, options: {kind: [{id, name,
## desc, open, level, drilled}]}}.
func _orders_row(orders: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Orders"
	box.add_theme_constant_override("separation", 4)
	var lines := [["Orders:", "How your hero has the army fight. More options open as the hero gains levels (and with the Tactics skill).",
			[BattleOrders.STANCE, BattleOrders.FOCUS]],
		["Deploy:", "How the army forms up, when the hero looses the battle art, and whether it falls back when the fight turns. A hero's class and skills know some formations by heart: they open early and work better (drilled).",
			[BattleOrders.FORMATION, BattleOrders.ART, BattleOrders.RETREAT]]]
	var pickers := {}
	for line in lines:
		var row := HFlowContainer.new()
		row.alignment = FlowContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 4)
		var lbl := UiStyle.label(String(line[0]), 14, UiStyle.TEXT_DIM)
		lbl.tooltip_text = String(line[1])
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(lbl)
		for kind in line[2]:
			if not (orders.get("options", {}) as Dictionary).has(kind):
				continue
			var ob := OptionButton.new()
			ob.name = String(kind).capitalize()
			ob.focus_mode = Control.FOCUS_NONE
			ob.add_theme_font_size_override("font_size", 13)
			var opts: Array = orders["options"][kind]
			for i in opts.size():
				var o: Dictionary = opts[i]
				var text := String(o["name"])
				var drilled := float(o.get("drilled", 0.0))
				if drilled > 0.0:
					text += " (drilled)"
				if not o["open"]:
					text = "%s (level %d)" % [o["name"], int(o["level"])]
				ob.add_item(text, i)
				ob.set_item_disabled(i, not o["open"])
				var tip := String(o["desc"])
				if drilled > 0.0:
					tip += "\nDrilled: its benefits are %d%% stronger for this hero." % int(round(drilled * 100.0))
				ob.set_item_tooltip(i, tip)
				ob.set_item_metadata(i, String(o["id"]))
				if String(o["id"]) == String(orders.get(kind, BattleOrders.DEFAULT[kind])):
					ob.select(i)
					ob.tooltip_text = tip
			pickers[kind] = ob
			row.add_child(ob)
		box.add_child(row)
	for kind in pickers:
		pickers[kind].item_selected.connect(func(_i: int):
			var out := {}
			for k in pickers:
				var ob: OptionButton = pickers[k]
				out[k] = String(ob.get_item_metadata(ob.selected))
			orders_changed.emit(out))
	return box


## An incoming attack cannot be withdrawn from. Fleeing abandons the army.
func show_incoming(setup: Dictionary, can_flee: bool, forecast: Dictionary = {}) -> void:
	_clear()
	var vig := BattleVignette.new()
	var sides := []
	for side in setup["sides"]:
		var figures := []
		for st in side["stacks"]:
			figures.append({"creature": st["creature"], "alive": true})
		sides.append(figures)
	vig.setup(String(setup.get("visual_terrain", setup["terrain"])), sides[0], sides[1], int(setup.get("visual_seed", 0)))
	_body.add_child(vig)
	_body.add_child(_centered("%s attacks %s!" % [setup["sides"][0]["name"], setup["sides"][1]["name"]], 24, UiStyle.BRASS))
	if not forecast.is_empty():
		var chance := 1.0 - float(forecast["win_probability"])
		_body.add_child(_centered("Your defense: %s" % CombatPredictor.label_for(chance), 20, _forecast_color(chance)))
	var columns := []
	for side in setup["sides"]:
		var cards := []
		for st in side["stacks"]:
			cards.append(_card(st["creature"], int(st["count"]), "", UiStyle.TEXT, UiStyle.creature_tooltip(_data, st["creature"], int(st["count"]))))
		columns.append(_column(side["name"], cards, "No troops"))
	_two_columns(columns[0], columns[1])
	_body.add_child(_centered("Flee: your hero escapes without an army. Abandoned troops deal 50% less damage.", 14, UiStyle.TEXT_DIM))
	var row := _buttons([["Flee", func(): hide(); incoming_choice.emit(true), "Your hero returns to a held town." if can_flee else "No safe held town is available.", not can_flee],
		["Defend!", func(): hide(); incoming_choice.emit(false), "Fight the attacker."]])
	var watch := CheckBox.new()
	watch.text = "Watch the battle"
	watch.button_pressed = BattleViewer.watch_enabled(settings_path)
	watch.toggled.connect(func(on: bool): BattleViewer.set_watch_enabled(on, settings_path))
	var three_d := _three_d_box(watch)
	row.add_child(watch)
	row.add_child(three_d)
	row.move_child(watch, 0)
	row.move_child(three_d, 1)
	_open("incoming")


## The "3D" box beside "Watch the battle": the 3D battlefield, or the sprite
## one when unticked. Only offered where the 3D battlefield is installed, and
## only usable while watching is on.
func _three_d_box(watch: CheckBox) -> CheckBox:
	var box := CheckBox.new()
	box.text = "3D"
	box.tooltip_text = "Watch on the 3D battlefield.\nUntick for the classic sprite battlefield."
	box.focus_mode = Control.FOCUS_NONE
	box.button_pressed = BattleViewer.three_d_enabled(settings_path)
	box.toggled.connect(func(on: bool): BattleViewer.set_three_d_enabled(on, settings_path))
	box.visible = BattleStage3D.available()
	box.disabled = not watch.button_pressed
	watch.toggled.connect(func(on: bool): box.disabled = not on)
	return box


func show_report(result: Dictionary, perspective: int = 0) -> void:
	_clear()
	last_result = result
	var won: bool = result["winner"] == perspective
	var vig := BattleVignette.new()
	var sides := []
	for s in 2:
		var arr := []
		for st in result["sides"][s]["stacks"]:
			arr.append({"creature": st["creature"], "alive": int(st["end"]) > 0})
		sides.append(arr)
	vig.setup(String(result.get("visual_terrain",result.get("terrain","grass"))), sides[0], sides[1], int(result.get("visual_seed",result.get("seed",0))))
	_body.add_child(vig)
	var title := "Victory!" if won else ("Fell back" if int(result.get("withdrew", -1)) == perspective else ("Withdrawal" if perspective == 0 and result["outcome"] == "attacker_withdrew" else "Defeat"))
	_body.add_child(_centered(title, 36, UiStyle.BRASS.lightened(0.2) if won else UiStyle.BAD))
	var summary: Array = result.get("summary", [])
	if not summary.is_empty():
		_body.add_child(_centered(summary[0], 14, UiStyle.TEXT_DIM))
	_body.add_child(HSeparator.new())
	var cols := []
	for s in 2:
		var cards := []
		for st in result["sides"][s]["stacks"]:
			if int(st["lost"]) <= 0:
				continue
			var tip := "%s: %d of %d fell, %d remain" % [st["name"], int(st["lost"]), int(st["start"]), int(st["end"])]
			cards.append(_card(st["creature"], 0, "-%d" % int(st["lost"]), UiStyle.BAD if s == perspective else UiStyle.TEXT, tip))
		cols.append(_column("Your losses:" if s == perspective else "Enemy losses (%s):" % result["sides"][s]["name"], cards, "None"))
	_two_columns(cols[0], cols[1])
	var xp := int(result.get("xp_gained" if perspective == 0 else "defender_xp", 0))
	var levels := int(result.get("levels_gained" if perspective == 0 else "defender_levels_gained", 0))
	if xp > 0:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		row.add_child(UiStyle.ui_icon("xp", 24))
		var txt := "+%d experience" % xp
		if levels > 0:
			txt += "   Level up! (+%d)" % levels
		row.add_child(UiStyle.label(txt, 16, UiStyle.BRASS))
		_body.add_child(row)
	# Narrative and modifiers stay one click away.
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 2)
	_details.visible = false
	for i in range(1, summary.size()):
		_details.add_child(_wrapped("- " + summary[i], 13))
	var notes: Array = result["sides"][0]["notes"] + result["sides"][1]["notes"].map(func(n): return "Enemy: " + n)
	if not notes.is_empty():
		_details.add_child(UiStyle.label("Combat modifiers", 13, UiStyle.TEXT_DIM))
		for n in notes:
			_details.add_child(_wrapped("- " + n, 13))
	var toggle := Button.new()
	toggle.text = "Battle details"
	toggle.toggle_mode = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 13)
	toggle.toggled.connect(func(on: bool): _details.visible = on)
	toggle.disabled = _details.get_child_count() == 0
	_details_toggle = toggle
	var row2 := HBoxContainer.new()
	row2.add_child(toggle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(spacer)
	if result.has("log"):
		var watch := Button.new()
		watch.text = "Watch the battle"
		watch.tooltip_text = "Play the fight out on a battlefield"
		watch.custom_minimum_size = Vector2(170, 38)
		watch.pressed.connect(func(): watch_requested.emit(result))
		row2.add_child(watch)
	var cont := Button.new()
	cont.text = "Continue"
	cont.tooltip_text = "Enter"
	cont.custom_minimum_size = Vector2(150, 38)
	cont.pressed.connect(_continue)
	row2.add_child(cont)
	_body.add_child(_details)
	_body.add_child(row2)
	_open("report")


## Expands the details section (tools, tests).
func show_details(on: bool = true) -> void:
	if _details_toggle != null and not _details_toggle.disabled:
		_details_toggle.button_pressed = on


func _wrapped(text: String, size: int) -> Label:
	var l := UiStyle.label(text, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40
	return l


func _show_cobolt_commitment(enemy_name: String, pred: Dictionary) -> void:
	_body.add_child(_centered("Rob %s?" % enemy_name, 24, UiStyle.BRASS))
	for line in pred.get("report", ["Guards concealed"]):
		var label := _centered(String(line), 15, UiStyle.TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH - 40
		_body.add_child(label)
	for text in ["Committing starts combat and ends this post's trade with you, even if you lose or retreat.",
		"Victory gives loot and permanently ends this post's trade for EVERYONE."]:
		var label := _centered(text, 15, UiStyle.WARN)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH - 40
		_body.add_child(label)
	var buttons := [["Cancel", _cancel]]
	if not pred.get("scouted", false):
		var why := String(pred.get("scout_reason", ""))
		buttons.append(["Send scout", func(): scout_requested.emit(), why, why != ""])
	buttons.append(["Commit robbery", _confirm])
	_buttons(buttons)
	_open("forecast")
