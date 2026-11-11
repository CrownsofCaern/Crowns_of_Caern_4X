class_name ScenarioDialog
extends ModalPanel
## Mission journal, persistent quest conversations and adjacent relic transfers.

signal closed
signal focus_tile(tile: Vector2i)

var _session: GameSession
var _hero_id := ""
var _site_id := ""
var _feedback := ""


func open(session: GameSession, hero_id: String, site_id: String = "") -> void:
	_session = session
	_hero_id = hero_id
	_site_id = site_id
	_feedback = ""
	_render()
	show()


func _render() -> void:
	_clear()
	var sc := ScenarioRules.definition(_session.state)
	var opts := _session.scenario_options(_hero_id, _site_id) if _site_id != "" else {}
	_body.add_child(UiStyle.label(String(opts.get("title", sc.get("name", "Objectives"))), 23, UiStyle.BRASS))
	var scroll := ScrollContainer.new()
	var viewport_height := get_viewport_rect().size.y if is_inside_tree() else 800.0
	scroll.custom_minimum_size.y = minf(240.0 if not opts.is_empty() else 380.0, viewport_height * 0.5)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	if _feedback != "":
		content.add_child(_text(_feedback, 14, UiStyle.GOOD))
	if not opts.is_empty():
		content.add_child(_text(String(opts["text"])))
		for spec in opts["actions"]:
			var button := Button.new()
			button.text = String(spec["text"])
			button.disabled = String(spec["reason"]) != ""
			button.tooltip_text = String(spec["reason"])
			button.custom_minimum_size.y = 38
			var action := String(spec["id"])
			button.pressed.connect(func():
				var result: Dictionary = _session.scenario_act(_hero_id, _site_id, action)
				_feedback = String(result.get("text", result.get("reason", "")))
				_render())
			content.add_child(button)
			if String(spec["reason"]) != "":
				content.add_child(_text(String(spec["reason"]), 12, UiStyle.TEXT_DIM))
	else:
		content.add_child(_text(String(sc.get("briefing", "Complete the mission objectives."))))
		if int(sc.get("deadline_day", 0)) > 0:
			content.add_child(_text("Deadline: end of day %d. %d day(s) remain." % [sc["deadline_day"], maxi(0, int(sc["deadline_day"]) - _session.state.day + 1)], 14, UiStyle.WARN))
		for objective in _session.scenario_objectives():
			content.add_child(_text(("Complete: " if objective["completed"] else "Required: ") + String(objective["text"]), 14, UiStyle.GOOD if objective["completed"] else UiStyle.TEXT))
		for id in sc.get("protected_towns", []):
			var town := _session.town(String(id))
			content.add_child(_text("Protect throughout: " + String(town.get("name", id)), 13, UiStyle.WARN))
		var wave := WaveDirector.next_wave(_session.state)
		if not wave.is_empty():
			var warned: bool = _session.state.scenario_runtime.get("warned", []).has(wave["id"])
			content.add_child(_text("%s · day %d · %s" % [wave["hero"]["name"] if warned else "Next invasion", wave["day"], wave.get("entry_name", "marked entry")], 14, UiStyle.WARN))
			_add_focus(content, "Show invasion entry", Vector2i(int(wave["spawn"][0]), int(wave["spawn"][1])))
		for q in sc.get("quests", []):
			content.add_child(_text("%s — %s\n%s" % [String(q["id"]).capitalize(), ScenarioQuests.status(_session.state, String(q["id"])).capitalize(), q["text"]], 13))
			var giver: Dictionary = _session.state.map.objects.get(String(q["giver"]), {})
			if not giver.is_empty():
				_add_focus(content, "Show quest giver", AdventureMap.object_pos(giver))
		for objective in sc.get("objectives", []):
			if objective["type"] == "reach":
				_add_focus(content, "Show destination", Vector2i(int(objective["pos"][0]), int(objective["pos"][1])))
	_inventory(content)
	_buttons([["Close", func():
		hide()
		closed.emit()]])


func _add_focus(content: VBoxContainer, text: String, tile: Vector2i) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func():
		hide()
		closed.emit()
		focus_tile.emit(tile))
	content.add_child(button)


func _inventory(content: VBoxContainer) -> void:
	var h := _session.hero(_hero_id)
	if h == null:
		return
	for item in ScenarioQuests.items(_session.state, h.id):
		content.add_child(_text("Carried relic: " + String(item).capitalize(), 13, UiStyle.BRASS))
		for other in _session.state.heroes_of(h.owner):
			if other.id == h.id or maxi(absi(other.pos.x - h.pos.x), absi(other.pos.y - h.pos.y)) > 1:
				continue
			var button := Button.new()
			button.text = "Give relic to " + other.name
			var recipient := String(other.id)
			var relic := String(item)
			button.pressed.connect(func():
				var result: Dictionary = _session.transfer_quest_item(_hero_id, recipient, relic)
				_feedback = "Relic transferred." if result["ok"] else String(result["reason"])
				_render())
			content.add_child(button)


func _text(text: String, size: int = 14, color: Color = UiStyle.TEXT) -> Label:
	var label := _wrapped(text, size, color)
	label.custom_minimum_size.x = maxf(240.0, _panel.custom_minimum_size.x - 56.0)
	return label
