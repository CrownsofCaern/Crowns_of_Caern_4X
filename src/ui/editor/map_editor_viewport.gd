class_name MapEditorViewport
extends Control
## Clipped map canvas. All authored edits go through MapDocument.

signal tile_selected(tile: Vector2i)
signal terrain_sampled(terrain_id: String)
signal zoom_changed(value: float)
signal entity_requested(action: String, tile: Vector2i)

const INVALID := Vector2i(-1, -1)
var document: MapDocument
var map_view: MapView
var tool := "terrain"
var terrain_id := "grass"
var decoration_kind := "boulders"
var brush_side := 1
var show_grid := false
var editing_enabled := true
var selected := INVALID
var hovered := INVALID
var zoom_level := MapCamera.DEFAULT_LEVEL
var focus := Vector2.ZERO
var _data: GameData
var _snapshot: Dictionary = {}
var _overlay: Node2D
var _refresh_queued := false
var _stroke := false
var _panning := false
var _last_cell := INVALID
var _rectangle_start := INVALID


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	map_view = MapView.new()
	map_view.motion_enabled = false
	add_child(map_view)
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_guides)
	add_child(_overlay)
	resized.connect(_position_map)
	mouse_exited.connect(func():
		hovered = INVALID
		if _rectangle_start == INVALID:
			_last_cell = INVALID
		_overlay.queue_redraw())


func bind(value: MapDocument, data: GameData) -> void:
	finish_stroke()
	if document != null and document.changed.is_connected(_queue_refresh):
		document.changed.disconnect(_queue_refresh)
	document = value
	_data = data
	_snapshot = {}
	selected = INVALID
	hovered = INVALID
	document.changed.connect(_queue_refresh)
	refresh_document()
	focus = _map_size() * 0.5
	_position_map()


func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		call_deferred("refresh_document")


func refresh_document() -> void:
	_refresh_queued = false
	if document == null or map_view == null:
		return
	var next := document.definition()
	if next == _snapshot:
		return
	var map := AdventureMap.from_definition(next, _data)
	var actors_changed: bool = _snapshot.is_empty() or next["objects"] != _snapshot["objects"] or next["heroes"] != _snapshot["heroes"] or next["players"] != _snapshot["players"]
	if actors_changed or next["width"] != _snapshot.get("width") or next["height"] != _snapshot.get("height"):
		var starts: Array[Vector2i] = []
		for hero in next["heroes"]:
			starts.append(AdventureMap.object_pos(hero))
		map_view.bind_terrain_preview(map, starts)
		map_view.show_document_entities(next, _data)
	else:
		var changed: Array[Vector2i] = []
		var terrain_changed := false
		var old_map := map_view._preview_map
		for y in map.height:
			for x in map.width:
				var pos := Vector2i(x, y)
				var terrain_diff: bool = next["terrain"][y][x] != _snapshot["terrain"][y][x]
				if terrain_diff or map.has_road(pos) != old_map.has_road(pos) or map.decorations.get(pos) != old_map.decorations.get(pos):
					changed.append(pos)
					terrain_changed = terrain_changed or terrain_diff
		if not changed.is_empty():
			map_view.update_terrain_preview(map, changed, 9 if terrain_changed else 1)
	_snapshot = next
	_position_map()
	_overlay.queue_redraw()


func _map_size() -> Vector2:
	return Vector2(float(_snapshot.get("width", 0)), float(_snapshot.get("height", 0))) * MapView.TILE


func _position_map() -> void:
	if map_view == null or _snapshot.is_empty():
		return
	var zoom := MapCamera.zoom_of(zoom_level)
	focus = MapCamera.clamp_focus(focus, size, _map_size(), zoom)
	map_view.position = MapCamera.map_origin(size, _map_size(), focus, zoom)
	map_view.set_zoom(zoom)
	_overlay.queue_redraw()


func zoom_by(steps: int, anchor: Vector2) -> void:
	finish_stroke()
	var point := (anchor - map_view.position) / MapCamera.zoom_of(zoom_level)
	zoom_level = MapCamera.stepped(zoom_level, steps)
	focus = MapCamera.focus_for_anchor(point, anchor, size, MapCamera.zoom_of(zoom_level))
	_position_map()
	zoom_changed.emit(MapCamera.zoom_of(zoom_level))


func tile_at(local: Vector2) -> Vector2i:
	return Vector2i(((local - map_view.position) / (MapView.TILE * MapCamera.zoom_of(zoom_level))).floor())


func _valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(_snapshot.get("width", 0)) and cell.y < int(_snapshot.get("height", 0))


func _gui_input(event: InputEvent) -> void:
	if document == null or not editing_enabled:
		return
	if event is InputEventMouseButton:
		if event.pressed and not Rect2(Vector2.ZERO, size).has_point(event.position):
			return
		var cell := tile_at(event.position)
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			zoom_by(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1, event.position)
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			finish_stroke()
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _valid(cell):
			if tool in ["move_entity", "duplicate_entity"] and not event.alt_pressed and not document.read_only():
				entity_requested.emit(tool, cell)
				accept_event()
				return
			selected = cell
			tile_selected.emit(cell)
			if event.alt_pressed:
				terrain_sampled.emit(_data.terrain_by_char[document.definition()["terrain"][cell.y][cell.x]])
			elif tool == "place_entity" and not document.read_only():
				entity_requested.emit(tool, cell)
			elif tool != "inspect" and not document.read_only():
				_stroke = document.begin_action("Paint " + tool)
				_last_cell = cell
				if tool == "rectangle":
					_rectangle_start = cell
				elif _stroke:
					paint_cells(MapBrush.square(cell, brush_side, _bounds()))
			_overlay.queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		if _panning:
			focus -= event.relative / MapCamera.zoom_of(zoom_level)
			_position_map()
		var cell := tile_at(event.position)
		if not Rect2(Vector2.ZERO, size).has_point(event.position) or not _valid(cell):
			hovered = INVALID
			if _rectangle_start == INVALID:
				_last_cell = INVALID
		else:
			hovered = cell
			if _stroke:
				if tool != "rectangle":
					var cells := {}
					for centre in MapBrush.line(_last_cell if _last_cell != INVALID else cell, cell):
						for point in MapBrush.square(centre, brush_side, _bounds()):
							cells[point] = true
					var stroke_cells: Array[Vector2i] = []
					stroke_cells.assign(cells.keys())
					paint_cells(stroke_cells)
				_last_cell = cell
		_overlay.queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_by(1 if event.factor > 1 else -1, event.position)
		accept_event()
	elif event is InputEventPanGesture:
		focus += event.delta * 20.0 / MapCamera.zoom_of(zoom_level)
		_position_map()
		accept_event()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Release can arrive over a panel or outside the clipped canvas.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			finish_stroke()
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_panning = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_stroke()
		_panning = false


func finish_stroke() -> void:
	if not _stroke:
		return
	if _rectangle_start != INVALID and _valid(_last_cell):
		paint_cells(MapBrush.rectangle(_rectangle_start, _last_cell, _bounds()))
	_stroke = false
	_rectangle_start = INVALID
	document.end_action()
	_overlay.queue_redraw()


func cancel_stroke() -> void:
	if _stroke:
		document.cancel_action()
	_stroke = false
	_rectangle_start = INVALID
	if _overlay != null:
		_overlay.queue_redraw()


func _bounds() -> Vector2i:
	return Vector2i(int(_snapshot["width"]), int(_snapshot["height"]))


func paint_cells(cells: Array[Vector2i]) -> void:
	match tool:
		"terrain", "rectangle":
			document.paint_terrain(cells, terrain_id)
		"road", "erase_road":
			document.paint_roads(cells, tool == "road")
		"decoration", "erase_decoration":
			var decorations: Array = document.definition().get("decorations", [])
			var positions := {}
			for cell in cells:
				positions[cell] = true
			decorations = decorations.filter(func(entry): return not positions.has(AdventureMap.object_pos(entry)))
			for cell in cells:
				decorations.append({"pos": [cell.x, cell.y], "kind": decoration_kind if tool == "decoration" else ""})
			document.set_decorations(decorations)


func _draw_guides() -> void:
	if _snapshot.is_empty():
		return
	var zoom := MapCamera.zoom_of(zoom_level)
	var cell_size := MapView.TILE * zoom
	var origin := map_view.position
	if show_grid:
		var visible_cells := MapCamera.visible_cells(size, _bounds(), origin, zoom)
		for x in range(visible_cells.position.x, visible_cells.end.x + 1):
			_overlay.draw_line(origin + Vector2(x * cell_size, 0), origin + Vector2(x * cell_size, _map_size().y * zoom), Color(0.9, 0.85, 0.7, 0.16))
		for y in range(visible_cells.position.y, visible_cells.end.y + 1):
			_overlay.draw_line(origin + Vector2(0, y * cell_size), origin + Vector2(_map_size().x * zoom, y * cell_size), Color(0.9, 0.85, 0.7, 0.16))
	if _valid(selected):
		_overlay.draw_rect(Rect2(origin + Vector2(selected) * cell_size, Vector2.ONE * cell_size).grow(-1), UiStyle.BRASS, false, 2)
	if _valid(hovered):
		var cells := MapBrush.square(hovered, 1 if tool.ends_with("entity") or tool == "inspect" else brush_side, _bounds())
		if _rectangle_start != INVALID:
			cells = MapBrush.rectangle(_rectangle_start, _last_cell, _bounds())
		if not cells.is_empty():
			var area := Rect2(origin + Vector2(cells.front()) * cell_size, Vector2(cells.back() - cells.front() + Vector2i.ONE) * cell_size)
			_overlay.draw_rect(area, Color(1, 0.9, 0.6, 0.15))
			_overlay.draw_rect(area, UiStyle.TEXT, false, 1)
