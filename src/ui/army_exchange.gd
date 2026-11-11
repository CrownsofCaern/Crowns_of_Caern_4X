class_name ArmyExchange
extends VBoxContainer
## Army management widget: one row of slots per army (a hero, a garrison, or
## both when the hero stands in the town). Click a stack to pick it up, then
## click a slot: an empty slot or the same creature takes the whole stack, a
## different creature swaps places. "Split" (or Shift+click on the target)
## moves only the number on the slider. Every change is a
## GameSession.transfer_stack command; this widget only shows the result.

signal changed

## Slots per row. Ten in one row fit the wide hero screen; the town screen
## uses two rows of five.
var columns := Army.MAX_SLOTS
var show_veteran_details := false

var session: GameSession
var _rows: Array = []          # [{ref, title}]
var _slots: Dictionary = {}    # ref -> Array[ArmySlot]
var _sel_ref := ""
var _sel_slot := -1
var _split_btn: Button
var _amount: SpinBox
var _hint: Label
var _strips: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_strips = VBoxContainer.new()
	_strips.add_theme_constant_override("separation", 6)
	add_child(_strips)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	add_child(tools)
	_split_btn = Button.new()
	_split_btn.text = "Split"
	_split_btn.toggle_mode = true
	_split_btn.focus_mode = Control.FOCUS_NONE
	_split_btn.custom_minimum_size = Vector2(70, 30)
	_split_btn.add_theme_font_size_override("font_size", 13)
	_split_btn.tooltip_text = "Move only part of the picked stack (or Shift+click the target slot)"
	_split_btn.toggled.connect(func(_on): _update_hint())
	tools.add_child(_split_btn)
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 1
	_amount.custom_minimum_size.x = 84
	_amount.tooltip_text = "How many creatures a split moves"
	tools.add_child(_amount)
	_hint = UiStyle.label("", 12, UiStyle.TEXT_DIM)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tools.add_child(_hint)


## rows: [[ref, title], ...]; refs as in GameSession.transfer_stack.
func setup(s: GameSession, rows: Array) -> void:
	session = s
	_rows = rows
	_sel_ref = ""
	_sel_slot = -1
	_split_btn.button_pressed = false
	refresh()


func army_of(ref: String) -> Army:
	if ref.begins_with("garrison:"):
		var t := session.town(ref.trim_prefix("garrison:"))
		return Town.garrison(t) if not t.is_empty() else Army.new()
	var h := session.hero(ref)
	return h.army if h != null else Army.new()


func refresh() -> void:
	for c in _strips.get_children():
		_strips.remove_child(c)
		c.queue_free()
	_slots.clear()
	for row in _rows:
		var ref: String = row[0]
		_strips.add_child(UiStyle.label(row[1], 13, UiStyle.TEXT_DIM))
		var strip := GridContainer.new()
		strip.columns = columns
		strip.add_theme_constant_override("h_separation", 4)
		strip.add_theme_constant_override("v_separation", 4)
		_strips.add_child(strip)
		var army := army_of(ref)
		var list: Array = []
		for i in Army.MAX_SLOTS:
			var st: Dictionary = army.slots[i]
			var slot := ArmySlot.new()
			if st.is_empty():
				slot.setup(i, "", 0, "Empty slot")
			else:
				slot.setup(i, st["creature"], int(st["count"]), UiStyle.creature_tooltip(session.data, st["creature"], int(st["count"]), Army.veteran_level(st)) + "\n" + Army.veteran_description(st), Army.veteran_level(st))
			if not st.is_empty():
				slot.veteran_level = Army.veteran_level(st)
			slot.set_selected(ref == _sel_ref and i == _sel_slot)
			slot.clicked.connect(_on_slot_clicked.bind(ref))
			strip.add_child(slot)
			list.append(slot)
		_slots[ref] = list
		if show_veteran_details:
			for i in Army.MAX_SLOTS:
				var stack: Dictionary = army.slots[i]
				if stack.is_empty():
					continue
				var detail := VBoxContainer.new()
				detail.add_theme_constant_override("separation", 2)
				_strips.add_child(detail)
				var creature_name := String(Army.creature_stats(stack, session.data)["name"])
				detail.add_child(UiStyle.label("Slot %d · %d %s · Level %d" % [i + 1, int(stack["count"]), creature_name, Army.veteran_level(stack)], 14, UiStyle.BRASS))
				detail.add_child(UiStyle.label(Army.veteran_description(stack), 13, UiStyle.TEXT_DIM))
				var progress := ProgressBar.new()
				progress.custom_minimum_size.y = 8
				progress.show_percentage = false
				var level := Army.veteran_level(stack)
				if level >= 5:
					progress.value = 100
				else:
					progress.max_value = Army.VETERAN_THRESHOLDS[level] - Army.VETERAN_THRESHOLDS[level - 1]
					progress.value = int(stack.get("veteran_xp", 0)) - Army.VETERAN_THRESHOLDS[level - 1]
				detail.add_child(progress)
	_update_hint()


func selected() -> Array:
	return [_sel_ref, _sel_slot]


func _selected_count() -> int:
	if _sel_ref == "":
		return 0
	var st: Dictionary = army_of(_sel_ref).slots[_sel_slot]
	return 0 if st.is_empty() else int(st["count"])


func _update_hint(error: String = "") -> void:
	var n := _selected_count()
	_amount.max_value = maxi(1, n - 1) if n > 1 else 1
	_amount.editable = n > 1
	_split_btn.disabled = n <= 1
	if n <= 1:
		_split_btn.button_pressed = false
	if error != "":
		_hint.text = UiStyle.sentence(error) + "."
		_hint.add_theme_color_override("font_color", UiStyle.BAD)
		return
	_hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	if _sel_ref == "":
		_hint.text = "Click a stack to pick it up."
	elif _split_btn.button_pressed:
		_hint.text = "Click a slot to move %d of them there." % int(_amount.value)
	else:
		_hint.text = "Click a slot to move, merge or swap. Shift+click splits."


## Picks a stack up, or moves the picked stack (whole, or the split amount).
func click(ref: String, index: int, shift: bool = false) -> Dictionary:
	var army := army_of(ref)
	if _sel_ref == "":
		if not army.slots[index].is_empty():
			_sel_ref = ref
			_sel_slot = index
			var n := _selected_count()
			_amount.max_value = maxi(1, n - 1)
			_amount.value = maxi(1, n / 2)
			refresh()
		return {"ok": false, "reason": ""}
	if ref == _sel_ref and index == _sel_slot:
		_sel_ref = ""
		_sel_slot = -1
		refresh()
		return {"ok": false, "reason": ""}
	var split := (shift or _split_btn.button_pressed) and _selected_count() > 1
	var r := session.transfer_stack(_sel_ref, _sel_slot, ref, index, int(_amount.value) if split else 0)
	_sel_ref = ""
	_sel_slot = -1
	_split_btn.button_pressed = false
	refresh()
	if r["ok"]:
		changed.emit()
	else:
		AudioManager.play("ui_error")
		_update_hint(r["reason"])
	return r


func _on_slot_clicked(slot: ArmySlot, shift: bool, ref: String) -> void:
	click(ref, slot.index, shift)
