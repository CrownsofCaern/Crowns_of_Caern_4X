class_name BuildHammer
extends Button
## Hammer in the map's top-right corner, shown while one of the current
## player's towns can still put up a building today. Each click opens the
## next such town.

signal town_requested(town_id: String)

var _towns: Array[String] = []
var _last := ""


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(TouchLayout.MIN_TARGET, TouchLayout.MIN_TARGET) if TouchGestures.touch_ui() else Vector2(40, 40)
	pressed.connect(func():
		if not _towns.is_empty():
			_last = _towns[(_towns.find(_last) + 1) % _towns.size()]
			town_requested.emit(_last))
	hide()


## Town ids of the current player that could build something right now.
static func buildable_towns(session: GameSession) -> Array[String]:
	var out: Array[String] = []
	if session == null or session.state.game_over or not session.current_player()["is_human"]:
		return out
	for t in session.towns_of(session.state.current_player):
		for o in session.build_options(String(t["id"])):
			if not o["built"] and o["reason"] == "":
				out.append(String(t["id"]))
				break
	return out


func update(session: GameSession) -> void:
	_towns = buildable_towns(session)
	visible = not _towns.is_empty()
	if visible:
		var names := []
		for id in _towns:
			names.append(String(session.town(id)["name"]))
		tooltip_text = "Can still build today: %s\nClick to open the town." % ", ".join(names)


func _draw() -> void:
	var s := size
	var c := s * 0.5
	var ink := Color("#120d0b")
	var wood := Color("#8a5a32")
	var head := UiStyle.BRASS
	# Handle from the lower left up to the head, then the head across it.
	var a := c + Vector2(-s.x * 0.26, s.y * 0.26)
	var b := c + Vector2(s.x * 0.08, -s.y * 0.08)
	draw_line(a, b, ink, 7.0)
	draw_line(a, b, wood, 4.0)
	var dir := (b - a).normalized()
	var across := Vector2(dir.y, -dir.x)
	var mid := b + dir * s.x * 0.05
	var half_len := s.x * 0.2
	var half_w := s.x * 0.08
	var pts := PackedVector2Array([
		mid + across * half_len + dir * half_w, mid - across * half_len + dir * half_w,
		mid - across * half_len - dir * half_w, mid + across * half_len - dir * half_w])
	draw_colored_polygon(pts, head)
	pts.append(pts[0])
	draw_polyline(pts, ink, 2.0)
