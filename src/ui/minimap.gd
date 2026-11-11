class_name Minimap
extends Control
## Shared terrain overview for the HUD and pre-game map preview.
## Reads live fog in game; previews show the full map and numbered player starts.

signal tile_picked(tile: Vector2i)

const MAX_SIZE := Vector2(284, 150)
const DETAIL := 6
const FOG := Color("#0b0a09")
const ROAD := Color("#c5aa76")
const NEUTRAL := Color("#a39788")
const INK := Color("#120d0b")

var session: GameSession
var view_rect := Rect2i()
var _tex: ImageTexture
var _cell := 4.0
var _map: AdventureMap
var _data: GameData
var _preview := false
var _starts: Array = []
var _players: Array = []
var _owner_ids: Array = []
var _terrain_image: Image


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_update_input()


func _update_input() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if _preview else Control.MOUSE_FILTER_STOP
	tooltip_text = "" if _preview else "Click or drag to look around the map (C returns to the hero)\nSquares: towns · diamonds: mines · circles: heroes · crosses: sites"


func bind(s: GameSession) -> void:
	session = s
	_map = s.state.map
	_data = s.data
	_preview = false
	_starts.clear()
	_fit(MAX_SIZE)
	_build_terrain()
	_update_input()
	refresh()


## Definition remains untouched; slot numbers refer to the setup rows, even
## when a preceding slot is closed. No game session or gameplay RNG is used.
func bind_preview(def: Dictionary, data: GameData, players: Array, bounds := Vector2(320, 190)) -> void:
	session = null
	_preview = true
	_data = data
	_map = AdventureMap.from_definition(def, data)
	_players = players
	_owner_ids.clear()
	for player in def.get("players", []):
		_owner_ids.append(int(player["id"]))
	_starts.clear()
	for i in def.get("players", []).size():
		var owner := int(def["players"][i]["id"])
		var pos := Vector2i(-1, -1)
		# Prefer the main town; hero-only starts still get a marker.
		for o in def.get("objects", []):
			if o["type"] == "town" and int(o.get("owner", -1)) == owner:
				pos = AdventureMap.object_pos(o)
				break
		if pos.x < 0:
			for h in def.get("heroes", []):
				if int(h.get("owner", -1)) == owner:
					pos = AdventureMap.object_pos(h)
					break
		if pos.x >= 0:
			_starts.append({"pos": pos, "slot": i})
	_fit(bounds)
	_build_terrain()
	_update_input()
	refresh()


func _fit(bounds: Vector2) -> void:
	_cell = minf(bounds.x / _map.width, bounds.y / _map.height)
	custom_minimum_size = Vector2(_map.width, _map.height) * _cell
	size = custom_minimum_size


## Cached, six pixels per tile: relief, tree silhouettes, shores and connected
## roads remain legible when reduced to the compact HUD. Pure visual hashes.
func _build_terrain() -> void:
	var img := Image.create(_map.width * DETAIL, _map.height * DETAIL, false, Image.FORMAT_RGBA8)
	for y in _map.height:
		for x in _map.width:
			var p := Vector2i(x, y)
			var tid := _map.terrain_at(p)
			var base := Color(_data.terrain(tid)["color"]).darkened(0.12)
			var water := tid in ["water", "river"]
			for py in DETAIL:
				for px in DETAIL:
					var c := base.lightened(float(TerrainTiles.cell_hash(Vector2i(x * DETAIL + px, y * DETAIL + py), 9)) * 0.012)
					if tid == "mountain" and py >= 1 and absi(px - 2) <= py / 2:
						c = base.lightened(0.38) if px <= 2 else base.darkened(0.35)
					elif tid == "forest" and py >= 1 and py <= 4 and absi(px - 2) <= py / 2:
						c = base.lightened(0.22) if px < 2 else base.darkened(0.4)
					elif water:
						if py == 2 and (px + x + y) % 5 < 3:
							c = base.lightened(0.16)
						var n := p + Vector2i(-1, 0)
						if px == 0 and _map.in_bounds(n) and _map.terrain_at(n) not in ["water", "river"]:
							c = base.lightened(0.35)
					elif tid == "swamp" and py == 4 and px % 3 != 0:
						c = base.darkened(0.3)
					elif tid == "infernal" and (px + py * 2 + x) % 11 == 0:
						c = base.lightened(0.3)
					img.set_pixel(x * DETAIL + px, y * DETAIL + py, c)
			if _map.has_road(p):
				var origin := p * DETAIL
				img.fill_rect(Rect2i(origin + Vector2i(2, 2), Vector2i(2, 2)), ROAD)
				for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = p + dir
					if _map.in_bounds(n) and _map.has_road(n):
						img.fill_rect(Rect2i(origin + Vector2i(2, 2) + dir * 2, Vector2i(2, 2)), ROAD)
	_terrain_image = img


func overview_image() -> Image:
	var img := _terrain_image.duplicate() as Image
	if not _preview:
		var fog: FogOfWar = session.current_player()["fog"]
		for y in _map.height:
			for x in _map.width:
				if not fog.is_explored(Vector2i(x, y)):
					img.fill_rect(Rect2i(x * DETAIL, y * DETAIL, DETAIL, DETAIL), FOG)
	return img


func refresh() -> void:
	if _map == null:
		return
	var img := overview_image()
	if _tex == null or _tex.get_size() != Vector2(img.get_size()):
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.update(img)
	queue_redraw()


func cell_size() -> float:
	return _cell


func tile_at(local: Vector2) -> Vector2i:
	if _map == null:
		return Vector2i(-1, -1)
	return Vector2i(clampi(int(local.x / _cell), 0, _map.width - 1), clampi(int(local.y / _cell), 0, _map.height - 1))


func _center(p: Vector2i) -> Vector2:
	return (Vector2(p) + Vector2(0.5, 0.5)) * _cell


func _owner_color(owner: int) -> Color:
	if owner < 0:
		return NEUTRAL
	if not _preview:
		return Color(session.state.player(owner)["color"])
	# Authored owner ids need not equal the index of their slot.
	var slot := _owner_ids.find(owner)
	if slot >= 0 and slot < _players.size():
		return NEUTRAL if _players[slot].get("type", "") == "closed" else Color(_players[slot]["color"])
	return NEUTRAL


func update_preview_players(players: Array) -> void:
	_players = players
	queue_redraw()


func _draw() -> void:
	if _map == null or _tex == null:
		return
	var extent := Vector2(_map.width, _map.height) * _cell
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, extent), false)
	var dot := maxf(1.5, _cell * 0.55)
	for id in _map.objects:
		var o: Dictionary = _map.objects[id]
		var p := AdventureMap.object_pos(o)
		if not _preview and not session.current_player()["fog"].is_explored(p):
			continue
		var at := _center(p)
		var col := _owner_color(int(o.get("owner", -1)))
		match String(o["type"]):
			"town":
				var r := Rect2(at - Vector2.ONE * dot, Vector2.ONE * dot * 2)
				draw_rect(r.grow(1), INK)
				draw_rect(r, col)
				draw_line(at + Vector2(-dot, -dot - 1), at + Vector2(dot, -dot - 1), UiStyle.TEXT, 1)
			"mine":
				var points := PackedVector2Array([at + Vector2(0, -dot - 1), at + Vector2(dot + 1, 0), at + Vector2(0, dot + 1), at + Vector2(-dot - 1, 0)])
				draw_colored_polygon(points, INK)
				for i in points.size():
					points[i] = at + (points[i] - at) * 0.65
				draw_colored_polygon(points, col)
			"site", "encounter":
				draw_line(at - Vector2(dot + 1, 0), at + Vector2(dot + 1, 0), INK, 3)
				draw_line(at - Vector2(0, dot + 1), at + Vector2(0, dot + 1), INK, 3)
				draw_line(at - Vector2(dot, 0), at + Vector2(dot, 0), ROAD, 1)
				draw_line(at - Vector2(0, dot), at + Vector2(0, dot), ROAD, 1)
	if _preview:
		for start in _starts:
			var slot := int(start["slot"])
			if slot >= _players.size() or _players[slot].get("type", "") == "closed":
				continue
			var at := _center(start["pos"]).clamp(Vector2(10, 10), extent - Vector2(10, 10))
			draw_circle(at, 10, INK)
			draw_circle(at, 8.5, Color(_players[slot]["color"]))
			var font := ThemeDB.fallback_font
			var label := str(slot + 1)
			var offset := Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5, 4)
			draw_string_outline(font, at + offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, INK)
			draw_string(font, at + offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	else:
		for id in session.state.heroes:
			var h: Hero = session.state.heroes[id]
			if h.alive and session.current_player()["fog"].is_explored(h.pos):
				draw_circle(_center(h.pos), dot + 1.5, INK)
				draw_circle(_center(h.pos), dot + 0.5, _owner_color(h.owner).lightened(0.3))
		if view_rect.size != Vector2i.ZERO:
			var vr := Rect2(Vector2(view_rect.position) * _cell, Vector2(view_rect.size) * _cell).intersection(Rect2(Vector2.ZERO, extent))
			draw_rect(vr, INK, false, 3.0)
			draw_rect(vr, UiStyle.TEXT, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if _preview or _map == null:
		return
	var press: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var drag: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if press or drag:
		tile_picked.emit(tile_at(event.position))
		accept_event()
