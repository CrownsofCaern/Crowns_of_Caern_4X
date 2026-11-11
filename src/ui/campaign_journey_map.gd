class_name CampaignJourneyMap
extends Control
## Presentation only: clicking a stop previews it; campaign progress is read-only.
signal stop_selected(index: int)

var painting: Texture2D
var nodes: Array = []
var chapters: Array = []
var buttons: Array[Button] = []
var selected := 0
var current := 0
var accent := Color("d6b576")
var hero_sprite := "hero_knight"
var elapsed := 0.0
var travel_duration := 2.4
var animate_travel := true
var zoom := 1.0
var pan := Vector2.ZERO
var _zoom_controls: VBoxContainer
var _auto_framed := false
var _last_width := 0.0


func _ready() -> void:
	clip_contents = true
	resized.connect(_layout_stops)
	var controls := VBoxContainer.new()
	_zoom_controls = controls
	controls.z_index = 5
	controls.position = Vector2(size.x - 52, 8)
	for entry in [["+", 1.35], ["−", 1.0 / 1.35]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(44, 44)
		button.tooltip_text = "Zoom in" if entry[1] > 1 else "Zoom out"
		button.pressed.connect(func(): zoom_at(entry[1], size * .5))
		controls.add_child(button)
	add_child(controls)
	set_process(true)


func configure(texture: Texture2D, stops: Array, states: Array, progress: int, sprite_id: String, color: Color) -> void:
	painting = texture
	nodes = stops
	chapters = states
	current = mini(progress, nodes.size() - 1)
	selected = current
	hero_sprite = sprite_id
	accent = color
	elapsed = 0
	zoom = 1.0
	pan = Vector2.ZERO
	_auto_framed = false
	for button in buttons:
		remove_child(button)
		button.queue_free()
	buttons.clear()
	for i in nodes.size():
		var button := Button.new()
		button.name = "ChapterStop_%d" % (i + 1)
		button.text = str(i + 1)
		button.custom_minimum_size = Vector2(44, 44)
		button.size = Vector2(44, 44)
		button.add_theme_font_size_override("font_size", 18)
		button.tooltip_text = "%d. %s · %s" % [i + 1, chapters[i]["name"], chapters[i]["state"].capitalize()]
		button.pressed.connect(func(): select_stop(i))
		add_child(button)
		buttons.append(button)
	select_stop(selected)
	_layout_stops()


func image_rect() -> Rect2:
	var ratio := 1.5 if painting == null else float(painting.get_width()) / painting.get_height()
	var fitted := Vector2(minf(size.x, size.y * ratio), minf(size.y, size.x / ratio))
	return Rect2((size - fitted * zoom) * .5 + pan, fitted * zoom)


func stop_position(index: int) -> Vector2:
	var rect := image_rect()
	var xy: Array = nodes[index]["at"]
	return rect.position + Vector2(xy[0], xy[1]) * rect.size


func _layout_stops() -> void:
	if size.x > 0 and not nodes.is_empty():
		if size.x < 600 and (not _auto_framed or _last_width >= 600):
			zoom = 1.6
			pan = Vector2.ZERO
			pan = size * .5 - stop_position(current)
			_clamp_pan()
		elif size.x >= 600 and _last_width > 0 and _last_width < 600:
			zoom = 1.0
			pan = Vector2.ZERO
		_auto_framed = true
		_last_width = size.x
	for i in buttons.size():
		buttons[i].position = stop_position(i) - buttons[i].size * .5
	if is_instance_valid(_zoom_controls):
		_zoom_controls.position = Vector2(maxf(4, size.x - 52), 8)
	queue_redraw()


func select_stop(index: int) -> void:
	if index < 0 or index >= nodes.size():
		return
	selected = index
	for i in buttons.size():
		var state: String = chapters[i]["state"]
		var color: Color = {"done":Color("b6dfc0"), "current":Color("ffe1a1"), "locked":Color("d0cdc5")}[state]
		var box := StyleBoxFlat.new()
		box.bg_color = Color("10151bea")
		box.border_color = Color("fff0bc") if i == selected else color
		box.set_border_width_all(3 if i == selected else 1)
		box.set_corner_radius_all(22)
		buttons[i].add_theme_stylebox_override("normal", box)
		buttons[i].add_theme_color_override("font_color", color)
	stop_selected.emit(index)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	elapsed += delta
	queue_redraw()


func _leg_points(index: int) -> PackedVector2Array:
	var start := stop_position(index - 1)
	var finish := stop_position(index)
	var points := PackedVector2Array()
	var normal := (finish - start).orthogonal().normalized() * minf(20, start.distance_to(finish) * .1)
	for step in 17:
		var t := float(step) / 16
		points.append(start.lerp(finish, t) + normal * sin(t * PI))
	return points


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b1015"))
	var rect := image_rect()
	if painting != null:
		draw_texture_rect(painting, rect, false)
	for i in range(1, nodes.size()):
		var points := _leg_points(i)
		var color := accent if i <= current else Color("c1b6a16b")
		if i <= current:
			draw_polyline(points, Color(0, 0, 0, .6), 4, true)
		var underground: bool = nodes[i]["layer"] != "surface" or nodes[i - 1]["layer"] != "surface"
		for j in range(points.size() - 1):
			if (not underground and i <= current) or j % 2 == 0:
				draw_line(points[j], points[j + 1], color, 1.6, true)
	if nodes.is_empty():
		return
	var travelling := animate_travel and current > 0 and elapsed < travel_duration
	var at := stop_position(current)
	var flip := false
	if travelling:
		var points := _leg_points(current)
		var progress := clampf(elapsed / travel_duration, 0, 1) * (points.size() - 1)
		var index := mini(int(progress), points.size() - 2)
		at = points[index].lerp(points[index + 1], progress - index)
		flip = points[-1].x < points[0].x
	var pose := UnitAnimation.sample(hero_sprite, "move" if travelling else "idle", elapsed)
	var texture: Texture2D = pose.get("texture", Art.sprite(hero_sprite))
	if texture != null:
		# Feet are above the node: the marker remains clickable and unobscured.
		var hero_rect := Rect2(at + _hero_offset(), Vector2(60, 60))
		if flip:
			hero_rect.position.x += hero_rect.size.x
			hero_rect.size.x *= -1
		draw_texture_rect(texture, hero_rect, false)


func zoom_at(factor: float, pivot: Vector2) -> void:
	var before := image_rect()
	if before.size.x <= 0 or before.size.y <= 0:
		return
	var point := (pivot - before.position) / before.size
	zoom = clampf(zoom * factor, 1, 3)
	var after := image_rect()
	pan += pivot - (after.position + point * after.size)
	_clamp_pan()
	_layout_stops()


func _clamp_pan() -> void:
	var excess := ((image_rect().size - size) * .5).max(Vector2.ZERO)
	pan = pan.clamp(-excess, excess)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(1.2, event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(1.0 / 1.2, event.position)
			accept_event()
	elif event is InputEventScreenDrag:
		pan += event.relative
		_clamp_pan()
		_layout_stops()
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		pan += event.relative
		_clamp_pan()
		_layout_stops()
		accept_event()


func _hero_offset() -> Vector2:
	var offsets := [Vector2(-30, -84), Vector2(-84, -55), Vector2(24, -55), Vector2(-30, 24)]
	var best: Vector2 = offsets[0]
	var best_score := 10000
	for offset in offsets:
		var rectangle := Rect2(stop_position(current) + offset, Vector2(60, 60))
		var score := 0
		if not Rect2(Vector2.ZERO, size).encloses(rectangle):
			score += 1
		for i in nodes.size():
			if rectangle.intersects(Rect2(stop_position(i) - Vector2(22, 22), Vector2(44, 44))):
				score += 1
		if score < best_score:
			best = offset
			best_score = score
	return best
