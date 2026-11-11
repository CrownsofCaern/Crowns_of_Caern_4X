class_name MapTip
extends PanelContainer
## Floating card shown while the pointer rests on anything on the map: what it
## is and what it does (MapTipInfo: towns, mines, resources, artifacts,
## encounters, rare buildings, heroes), and for a hostile army its troops
## (rough sizes, or exact counts once scouted), the odds for the selected hero
## (a worded verdict, the exact percentage once scouted, nothing in hard mode)
## and how to send a scout (GameSession.intel()).

const WIDTH := 270

var _box: VBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = WIDTH
	var sb := UiStyle.panel_box(Color("#15110dee"), UiStyle.BRASS, 2)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	hide()


## The colour of a worded verdict: that of its lowest win chance.
static func verdict_color(label: String) -> Color:
	for pair in CombatPredictor.LABELS:
		if pair[1] == label:
			return BattlePanels._forecast_color(float(pair[0]))
	return UiStyle.TEXT


## One line per stack: "A pack of Thornwolves" or "14 Thornwolves" (scouted).
static func troop_lines(intel: Dictionary) -> Array:
	if intel.get("concealed", false):
		return intel.get("report", ["Guards concealed"])
	var out := []
	for st in intel.get("stacks", []):
		var n := int(st["count"])
		out.append("%d %s" % [n, st["name"]] if st["known"] else "%s %s" % [UiStyle.count_word(n), st["name"]])
	return out


## The odds as shown to the player: [text, colour].
static func odds_line(intel: Dictionary) -> Array:
	if intel.get("concealed", false):
		return ["Battle odds unknown", UiStyle.TEXT_DIM]
	match String(intel.get("odds", "none")):
		"exact":
			var p := float(intel["win_probability"])
			if p < 0.0:
				return ["Odds: unknown (no army)", UiStyle.TEXT_DIM]
			return ["Odds: %d%% to win, %s" % [roundi(p * 100), String(intel["label"]).to_lower()], BattlePanels._forecast_color(p)]
		"label":
			if String(intel["label"]) == "":
				return ["Odds: unknown (no army)", UiStyle.TEXT_DIM]
			return ["Odds: " + String(intel["label"]), verdict_color(intel["label"])]
	return ["Odds hidden (hard mode)", UiStyle.TEXT_DIM]


## The scouting hint: [text, colour].
static func scout_line(intel: Dictionary) -> Array:
	if intel.get("scouted", false):
		return ["Scouted today", UiStyle.GOOD]
	var why := String(intel.get("scout_reason", ""))
	if why != "":
		return [why, UiStyle.TEXT_DIM]
	var cost := int(intel.get("scout_cost", 0))
	var price := "free" if cost <= 0 else "-%d movement" % cost
	if TouchGestures.touch_ui():
		return ["Tap it to attack; scout from the forecast (%s)" % price, UiStyle.BRASS]
	return ["S: send a scout (%s)" % price, UiStyle.BRASS]


func show_intel(intel: Dictionary, at: Vector2, bounds: Rect2) -> void:
	show_card({}, intel, at, bounds)


## info: MapTipInfo.describe() ({} for none); intel: GameSession.intel() of a
## hostile army there ({} for none). Hides the card when both are empty.
func show_card(info: Dictionary, intel: Dictionary, at: Vector2, bounds: Rect2) -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if info.is_empty() and intel.is_empty():
		hide()
		return
	_box.add_child(_line(String(info.get("title", intel.get("name", ""))), 15, UiStyle.BRASS))
	if info.has("kind"):
		_box.add_child(_line(String(info["kind"]), 12, UiStyle.TEXT_DIM))
	for l in info.get("lines", []):
		if String(l[0]) != "":
			_box.add_child(_line(l[0], 13, l[1]))
	if not intel.is_empty():
		if not info.is_empty():
			var sep := HSeparator.new()
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_box.add_child(sep)
			if String(info.get("title", "")) != String(intel["name"]):
				_box.add_child(_line(String(intel["name"]), 13, UiStyle.TEXT_DIM))
		for t in troop_lines(intel):
			_box.add_child(_line(t, 13, UiStyle.TEXT))
		var odds := odds_line(intel)
		_box.add_child(_line(odds[0], 14, odds[1]))
		var sc := scout_line(intel)
		_box.add_child(_line(sc[0], 12, sc[1]))
	show()
	reset_size()
	var sz := get_combined_minimum_size()
	var pos := at + Vector2(20, 20)
	if pos.x + sz.x > bounds.end.x:
		pos.x = at.x - sz.x - 12
	if pos.y + sz.y > bounds.end.y:
		pos.y = at.y - sz.y - 12
	position = Vector2(maxf(bounds.position.x, pos.x), maxf(bounds.position.y, pos.y))


func _line(text: String, size: int, color: Color) -> Label:
	var l := UiStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 20
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
