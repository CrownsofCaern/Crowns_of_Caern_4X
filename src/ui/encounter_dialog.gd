class_name EncounterDialog
extends ModalPanel
## Encounter choice dialog: flavour text, one button per choice with its cost,
## requirement and success chance; then the outcome. Reads only the plain
## dictionaries returned by GameSession.encounter_options / resolve_encounter.

signal choice_made(index: int)
signal result_closed


func show_options(opts: Dictionary) -> void:
	_clear()
	var ter: Dictionary = _data.terrain(opts.get("terrain", ""))
	_body.add_child(UiStyle.titled(Art.sprite(String(opts.get("sprite", "encounter_" + String(opts.get("id", ""))))), opts["name"], ter.get("name", "")))
	_body.add_child(_wrapped(opts["text"], 15))
	_body.add_child(HSeparator.new())
	for c in opts["choices"]:
		_body.add_child(_choice_button(c, bool(opts.get("hide_chances", false))))
	show()
	UiStyle.fade_in(self)


func _choice_button(c: Dictionary, hide_chance: bool = false) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 36)
	var extra := []
	if c["cost_text"] != "":
		extra.append(c["cost_text"])
	if c["has_check"]:
		extra.append("chance unknown" if hide_chance else "%d%% chance" % roundi(float(c["chance"]) * 100))
	b.text = "  " + c["text"] + ("   [" + ", ".join(extra) + "]" if not extra.is_empty() else "")
	b.disabled = not c["available"]
	var idx: int = c["index"]
	b.pressed.connect(func(): choice_made.emit(idx))
	box.add_child(b)
	if not c["available"]:
		b.tooltip_text = c["reason"]
		box.add_child(UiStyle.label("      " + c["reason"], 12, UiStyle.BAD))
	elif c["has_check"] and not hide_chance:
		b.add_theme_color_override("font_color", BattlePanels._forecast_color(float(c["chance"])).lerp(UiStyle.TEXT, 0.4))
	return box


func show_result(result: Dictionary) -> void:
	_clear()
	_body.add_child(UiStyle.titled(Art.sprite(String(result.get("sprite", "encounter_" + String(result.get("encounter", ""))))), result.get("name", "")))
	if result.has("success"):
		var won: bool = result["success"]
		if result.get("battle", "") != "":
			_body.add_child(UiStyle.label("Ambush!", 20, UiStyle.BAD))
		elif result.get("had_check", false):
			_body.add_child(UiStyle.label("Success" if won else "Failure", 20, UiStyle.GOOD if won else UiStyle.BAD))
	if result.get("text", "") != "":
		_body.add_child(_wrapped(result["text"], 15))
	if not result.get("lines", []).is_empty():
		_body.add_child(HSeparator.new())
		for line in result["lines"]:
			var col := UiStyle.BAD if String(line).begins_with("-") else (UiStyle.GOOD if String(line).begins_with("+") or line.contains("join") else UiStyle.TEXT)
			_body.add_child(UiStyle.label("  " + line, 14, col))
	if int(result.get("levels_gained", 0)) > 0:
		_body.add_child(UiStyle.label("Level up! (+%d)" % result["levels_gained"], 15, UiStyle.BRASS))
	_buttons([["To battle" if result.get("battle", "") != "" else "Continue", func(): hide(); result_closed.emit()]])
	show()
