class_name MapView
extends Node2D
## Draws the adventure map from the built art (assets/manifest.json) with
## TileMapLayers: ground, one blend layer per terrain (transitions), roads,
## a y-sorted world layer (decorations, objects, heroes), path overlay and a
## fog layer with soft edges. Turns mouse and touch input into tile events
## (TouchGestures: tap, long press, drag to pan, two fingers cancel). Holds no
## game rules: it only reads GameSession.

signal tile_clicked(tile: Vector2i)
signal tile_hovered(tile: Vector2i)
signal cancel_requested
## Mouse wheel or trackpad pinch: zoom `steps` levels closer (negative: farther)
## around the screen point `at`.
signal zoom_requested(steps: int, at: Vector2)
## Scroll the map by `delta` screen pixels: a trackpad two-finger swipe, or a
## finger dragging the map (sent reversed, so the map follows the finger).
signal pan_requested(delta: Vector2)
## Emitted as an animated hero sets foot on each tile (footsteps, pickups).
signal hero_stepped(hero_id: String, tile: Vector2i)

const TILE := 40                       # on-screen pixels per map cell
const TERRITORY_RADIUS := 3
const NEUTRAL_TERRITORY := Color("#999999")
const TOWN_GATE_NUDGE := 2.0           # native pixels a hero in a town stands below its feet
const SITE_FLAG := [30, 14]                  # owner pennant on a held dwelling site (sprite pixels; landmark sprites carry no flag spot)

var session: GameSession
## Static document preview (map editor): no players, fog, turn progression or gameplay input.
var _preview_map: AdventureMap
var _preview_starts: Array[Vector2i] = []
var path: Array = []                   # Array[Vector2i]
var path_reachable: int = 0
var path_is_attack: bool = false
var hovered := Vector2i(-1, -1)
## Tiles of the viewer's towns an enemy hero could reach soon (GameSession.town_threats):
## each gets a red warning badge over its gate.
var threatened: Array = []              # Array[Vector2i]
var input_enabled := true
## Pinch accumulated towards the next zoom step (1.0 = none).
var _pinch := 1.0
var selected_hero_id := ""
var touch := TouchGestures.new()
var _touch_index := -1                 # the finger TouchGestures follows
var _touch_last := Vector2.ZERO        # where that finger is now
var pinch := PinchGesture.new()        # two fingers: zoom, or a tap that cancels
## Presentation switch for reduced-motion modes and static visual comparisons.
var motion_enabled := true
var _motion_time := 0.0

var tiles: TerrainTiles
var _art_scale := 2.0                  # TILE / native tile size
var _native := 20
var _ground: TileMapLayer
var _surface: TileMapLayer             # cosmetic ground variants (map scenery terrain art)
var _surface_sources: Dictionary = {}  # scenery terrain id -> TileSet source id
var _details: TileMapLayer
var _blends: Dictionary = {}           # terrain id -> TileMapLayer
var _blend_order: Array = []           # terrain ids by priority
var _edges: Dictionary = {}            # one layer per pair-specific edge material
var _roads: TileMapLayer
var _highres_roads: TileMapLayer
var _barriers: TileMapLayer
var _barrier_biomes: Dictionary = {}
var _barrier_styles: Dictionary = {}
var _territory: Node2D
var _under: Node2D                     # hero rings
var _world: Node2D                     # y-sorted: deco tiles, objects, heroes
var _deco: TileMapLayer
var _objects: Node2D
var _unsprited: Array = []             # tiles of visible objects that have no art yet
var _hero_sprites: Dictionary = {}     # hero id -> Sprite2D
var _animating: Dictionary = {}        # hero id -> true while tweening
var _overlay: Node2D                   # path + hover
var _glow: Node2D                      # additive ember light over infernal ground
var _glow_cells: Array = []
var _glow_tex: GradientTexture2D
var _fog: TileMapLayer
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tiles = TerrainTiles.new(Art.terrain_info())
	if tiles.is_valid():
		_native = int(tiles.info["tile_size"])
		_art_scale = float(TILE) / _native
	_ground = _layer("Ground")
	_surface = TileMapLayer.new()
	_surface.name = "GroundVariants"
	_surface.tile_set = _surface_tile_set()
	_surface.scale = Vector2(_art_scale, _art_scale)
	add_child(_surface)
	_details = _layer("GroundDetails")
	_territory = Node2D.new()
	_territory.name = "Territory"
	_territory.draw.connect(_draw_territory)
	_under = Node2D.new()
	_under.name = "Under"
	_under.draw.connect(_draw_under)
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	_world.scale = Vector2(_art_scale, _art_scale)
	_deco = TileMapLayer.new()
	_deco.name = "Deco"
	_deco.y_sort_enabled = true
	_deco.tile_set = tiles.tile_set
	_world.add_child(_deco)
	_objects = Node2D.new()
	_objects.name = "Objects"
	_objects.y_sort_enabled = true
	_world.add_child(_objects)
	_glow = Node2D.new()
	_glow.name = "Glow"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.draw.connect(_draw_glow)
	_glow_tex = GradientTexture2D.new()
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 128
	_glow_tex.height = 128
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.36, 0.08, 0.22))
	g.set_color(1, Color(0.6, 0.05, 0.0, 0.0))
	_glow_tex.gradient = g
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.draw.connect(_draw_overlay)



## The drawing layers live outside the tree until a map is bound (_build_static);
## free them with the view when it never got one (the title menu, an editor-only run).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for n in [_territory, _under, _world, _glow, _overlay]:
			if n != null and is_instance_valid(n) and n.get_parent() == null:
				n.free()


func _layer(layer_name: String) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.name = layer_name
	l.tile_set = tiles.tile_set
	l.scale = Vector2(_art_scale, _art_scale)
	add_child(l)
	return l


func bind(s: GameSession) -> void:
	if session != null and session.state_changed.is_connected(refresh):
		session.state_changed.disconnect(refresh)
	session = s
	_preview_map = null
	_preview_starts.clear()
	session.state_changed.connect(refresh)
	_animating.clear()
	_build_static()
	clear_path()
	refresh()


## Document rendering foundation. Call after _ready; caller owns the snapshot.
func bind_terrain_preview(map: AdventureMap, starts: Array[Vector2i] = []) -> void:
	if session != null and session.state_changed.is_connected(refresh):
		session.state_changed.disconnect(refresh)
	session = null
	_preview_map = map
	_preview_starts = starts.duplicate()
	touch.reset()
	_animating.clear()
	_hero_sprites.clear()
	_unsprited.clear()
	for child in _objects.get_children():
		child.queue_free()
	_build_static()
	clear_path()
	_territory.queue_redraw()
	_under.queue_redraw()
	_overlay.queue_redraw()
	_glow.queue_redraw()


func _display_map() -> AdventureMap:
	return _preview_map if _preview_map != null else session.state.map


## Paint only the affected region. Terrain changes can influence the nearest-land
## barrier biome eight tiles away, and its transition one tile farther away.
func update_terrain_preview(map: AdventureMap, cells: Array[Vector2i], radius: int = 1) -> void:
	if _preview_map == null or not tiles.is_valid():
		bind_terrain_preview(map, _preview_starts)
		return
	_preview_map = map
	_barrier_biomes.clear()
	_barrier_styles.clear()
	var affected := {}
	for cell in cells:
		for y in range(cell.y - radius, cell.y + radius + 1):
			for x in range(cell.x - radius, cell.x + radius + 1):
				var p := Vector2i(x, y)
				if map.in_bounds(p):
					affected[p] = true
	var occupied := {}
	for object in map.objects.values():
		occupied[AdventureMap.object_pos(object)] = true
	for start in _preview_starts:
		occupied[start] = true
	for cell in affected:
		for layer in [_ground, _surface, _details, _deco, _roads, _highres_roads, _barriers] + _blends.values() + _edges.values():
			layer.erase_cell(cell)
		_glow_cells.erase(cell)
		_paint_static_cell(map, cell, occupied)
	_glow.queue_redraw()


## Authored objects and heroes are visual dictionaries, not initialized runtime
## entities. Missing optional properties show a marker so incomplete drafts work.
func show_document_entities(definition: Dictionary, data: GameData) -> void:
	for child in _objects.get_children():
		_objects.remove_child(child)
		child.queue_free()
	_hero_sprites.clear()
	for object in definition["objects"]:
		var sid := ""
		if object.get("sprite") is String:
			sid = object["sprite"]
		elif object["type"] == "site":
			sid = String(data.sites.get(str(object.get("site", "")), {}).get("sprite", ""))
		elif object["type"] == "neutral_army":
			var stacks: Variant = object.get("stacks", [])
			if stacks is Array and not stacks.is_empty() and stacks[0] is Array and not stacks[0].is_empty():
				sid = "creature_" + str(stacks[0][0])
		else:
			sid = object_sprite_id(object)
		_add_document_entity(object, sid, definition["players"])
	for hero in definition["heroes"]:
		var sid := Art.hero_sprite_id(str(hero.get("class", "")))
		var sprite := _add_document_entity(hero, sid, definition["players"])
		if sprite != null:
			var town := _preview_map.object_at(AdventureMap.object_pos(hero))
			if town.get("type", "") == "town":
				sprite.position.y += TOWN_GATE_NUDGE


func _add_document_entity(entity: Dictionary, sid: String, players: Array) -> Sprite2D:
	var pos := AdventureMap.object_pos(entity)
	if not Art.has_sprite(sid):
		var marker := Label.new()
		marker.text = str(entity.get("type", "hero")).capitalize()
		marker.position = _feet_native(pos) - Vector2(12, 16)
		marker.add_theme_font_size_override("font_size", 10)
		marker.add_theme_color_override("font_color", UiStyle.WARN)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_objects.add_child(marker)
		return null
	var sprite := _make_sprite(sid)
	sprite.position = _feet_native(pos)
	_objects.add_child(sprite)
	if Art.sprite_info(sid).has("flag"):
		var flag := _make_sprite("object_flag")
		flag.scale = Vector2.ONE
		var at: Array = Art.sprite_info(sid)["flag"]
		flag.position = sprite.offset + Vector2(at[0], at[1])
		flag.modulate = _document_owner_colour(entity.get("owner", -1), players)
		sprite.add_child(flag)
	return sprite


func _document_owner_colour(owner: Variant, players: Array) -> Color:
	for player in players:
		if player.get("id", -2) == owner and player.get("color") is String and Color.html_is_valid(player["color"]):
			return Color(player["color"])
	return Color("#8a8478")


## Re-reads the session: objects, heroes and fog. Terrain is static per map.
func refresh() -> void:
	if session == null or not is_inside_tree():
		return
	_sync_objects()
	_sync_heroes()
	_sync_fog()
	_territory.queue_redraw()
	_under.queue_redraw()
	_glow.queue_redraw()
	_overlay.queue_redraw()


func set_path(p: Array, reachable: int, is_attack: bool) -> void:
	path = p
	path_reachable = reachable
	path_is_attack = is_attack
	_overlay.queue_redraw()


func clear_path() -> void:
	path = []
	path_reachable = 0
	if _overlay:
		_overlay.queue_redraw()


func tile_to_px(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE, t.y * TILE)


func center_px(t: Vector2i) -> Vector2:
	return tile_to_px(t) + Vector2(TILE, TILE) * 0.5


## Where a figure standing on `t` has its feet, in world (native) pixels.
func _feet_native(t: Vector2i) -> Vector2:
	return Vector2(t.x * _native + _native / 2, t.y * _native + _native - 3)


## Where a hero stands on a tile. In a town the hero waits just in front of the
## gate: a little lower than the town's own feet, so the y-sort draws the hero
## over the walls instead of hiding it (an enemy in your town must be visible).
func hero_feet(t: Vector2i) -> Vector2:
	var o := session.state.map.object_at(t) if session != null else {}
	return _feet_native(t) + (Vector2(0, TOWN_GATE_NUDGE) if not o.is_empty() and o["type"] == "town" else Vector2.ZERO)


## Animates a hero along `steps`; awaitable.
func animate_hero(hero_id: String, from: Vector2i, steps: Array) -> void:
	var spr: Sprite2D = _hero_sprites.get(hero_id)
	if spr == null:
		return
	_animating[hero_id] = _motion_time
	spr.position = hero_feet(from)
	var tw := create_tween()
	var prev := from
	for s in steps:
		var st: Vector2i = s
		if st.x != prev.x:
			tw.tween_callback(_face.bind(spr, st.x < prev.x))
		tw.tween_callback(hero_stepped.emit.bind(hero_id, st))
		tw.tween_property(spr, "position", hero_feet(st), 0.11)
		tw.parallel().tween_callback(_under.queue_redraw).set_delay(0.05)
		prev = st
	await tw.finished
	_animating.erase(hero_id)
	refresh()


func _face(spr: Sprite2D, left: bool) -> void:
	# Anchors are horizontally centred, so mirroring keeps the feet in place.
	spr.flip_h = left
	for c in spr.get_children():
		if c is Sprite2D:
			(c as Sprite2D).flip_h = left


func _unhandled_input(event: InputEvent) -> void:
	if session == null or not input_enabled:
		touch.reset()        # a finger held while a panel opened must not tap later
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_input(event)
		return
	# Touches also arrive as emulated mouse events; the touch handler owns them.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		hover_at(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_requested.emit(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		_pinch *= event.factor
		if _pinch >= 1.35 or _pinch <= 1.0 / 1.35:
			zoom_requested.emit(1 if _pinch > 1.0 else -1, event.position)
			_pinch = 1.0
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		pan_requested.emit(event.delta)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var t := _event_tile(event.position)
		if not session.state.map.in_bounds(t):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			tile_clicked.emit(t)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_requested.emit()
			get_viewport().set_input_as_handled()


## Re-reads the tile under a screen point (pointer moves, or the map moved or
## zoomed under a still pointer).
func hover_at(screen_pos: Vector2) -> void:
	var t := _event_tile(screen_pos)
	if t != hovered:
		hovered = t
		tile_hovered.emit(t)
		_overlay.queue_redraw()


## Shows the map at `zoom` times its normal size. Zoomed out, the art is
## filtered so that halving it blends pixels instead of dropping every other one.
func set_zoom(zoom: float) -> void:
	scale = Vector2(zoom, zoom)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if zoom < 1.0 else CanvasItem.TEXTURE_FILTER_NEAREST


func _touch_input(event: InputEvent) -> void:
	var now := Time.get_ticks_msec()
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if pinch.is_active():
				pass                       # a third finger changes nothing
			elif touch.is_down() and st.index != _touch_index:
				# Second finger: the one-finger press is spent; pinch or two-finger tap.
				pinch.begin(_touch_index, _touch_last, st.index, st.position, now)
				touch.reset()
			elif not touch.is_down():
				_touch_index = st.index
				_touch_last = st.position
				touch.press(st.position, now)
		elif pinch.tracks(st.index):
			if pinch.finish(now):
				cancel_requested.emit()
			_touch_index = -1
		elif st.index == _touch_index:
			_touch_index = -1
			var kind := touch.release(st.position, now)
			var t := _event_tile(touch.start_position())
			if kind == TouchGestures.Kind.TAP and session.state.map.in_bounds(t):
				_hover(t)
				tile_clicked.emit(t)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if pinch.tracks(sd.index):
			var steps := pinch.move(sd.index, sd.position)
			if steps != 0:
				zoom_requested.emit(steps, pinch.midpoint())
		elif sd.index == _touch_index:
			_touch_last = sd.position
			var d := touch.move(sd.position)
			if d != Vector2.ZERO:
				pan_requested.emit(-d)
		get_viewport().set_input_as_handled()


## A long press shows what is on the tile (the hover card) without moving.
## Called every frame from _process.
func _poll_touch() -> void:
	if touch.is_down() and not input_enabled:
		touch.reset()
	elif touch.is_down() and session != null and touch.poll_long_press(Time.get_ticks_msec()):
		var t := _event_tile(touch.start_position())
		if session.state.map.in_bounds(t):
			_hover(t)


func _hover(t: Vector2i) -> void:
	hovered = t
	tile_hovered.emit(t)
	_overlay.queue_redraw()


func _event_tile(screen_pos: Vector2) -> Vector2i:
	var local := get_global_transform_with_canvas().affine_inverse() * screen_pos
	return Vector2i(floori(local.x / TILE), floori(local.y / TILE))


# ------------------------------------------------------------ static layers --

func _build_static() -> void:
	for l in _blends.values():
		l.queue_free()
	_blends.clear()
	for layer in _edges.values():
		layer.queue_free()
	_edges.clear()
	if _roads:
		_roads.queue_free()
	if _highres_roads:
		_highres_roads.queue_free()
	if _barriers:
		_barriers.queue_free()
	if _fog:
		_fog.queue_free()
		_fog = null
	for n in [_territory, _under, _world, _glow, _overlay]:
		if n.get_parent() == self:
			remove_child(n)
	_ground.clear()
	_surface.clear()
	_details.clear()
	_deco.clear()
	_glow_cells.clear()
	if not tiles.is_valid():
		for node in [_territory, _under, _world, _glow, _overlay]:
			add_child(node)
		push_warning("MapView: assets/manifest.json or atlases missing; run tools/assets/pipeline.py build")
		return
	var map := _display_map()
	_barrier_biomes.clear()
	_barrier_styles.clear()
	_blend_order = tiles.info["order"].duplicate()
	for tid in _blend_order:
		_blends[tid] = _layer("Blend_" + tid)
	for kind in tiles.info.get("edges", {}).get("types", {}):
		_edges[kind] = _layer("TerrainEdge_" + String(kind))
	_roads = _layer("Roads")
	_barriers = _layer("Barriers")
	_highres_roads = _layer("HighResolutionRoads")
	if tiles.highres_tile_set != null:
		var high_scale := _art_scale * float(_native) / float(tiles.info["highres"]["tile_size"])
		_barriers.tile_set = tiles.highres_tile_set
		_barriers.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_barriers.scale = Vector2(high_scale, high_scale)
		_highres_roads.tile_set = tiles.highres_tile_set
		_highres_roads.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_highres_roads.scale = Vector2(high_scale, high_scale)
	add_child(_territory)
	add_child(_under)
	add_child(_world)
	add_child(_glow)
	add_child(_overlay)
	_fog = _layer("Fog")
	var occupied := {}
	for o in map.objects.values():
		occupied[AdventureMap.object_pos(o)] = true
	if session != null:
		for hero in session.state.heroes.values():
			occupied[hero.pos] = true
	else:
		for start in _preview_starts:
			occupied[start] = true
	for y in map.height:
		for x in map.width:
			_paint_static_cell(map, Vector2i(x, y), occupied)
	_build_scenery(map)


## Sprites for the map's scenery pieces, y-sorted with objects; their feet sit
## on the bottom centre of their footprint.
func _build_scenery(map: AdventureMap) -> void:
	for c in _objects.get_children():
		if c.has_meta("scenery"):
			c.free()
	var lib := TerrainPainter.scenery_library()
	for e in map.scenery:
		var info: Dictionary = lib.get(String(e["kind"]), {})
		var tex := Art.texture_at(String(info.get("texture", "")))
		if tex == null:
			continue
		var fp: Array = e["footprint"]
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		var anchor: Array = info.get("anchor", [tex.get_width() / 2, tex.get_height() - 1])
		spr.offset = -Vector2(float(anchor[0]), float(anchor[1]))
		spr.position = Vector2((int(e["pos"][0]) + int(fp[0]) / 2.0) * _native, (int(e["pos"][1]) + int(fp[1])) * _native - 2)
		var cells: Array[Vector2i] = []
		for dy in int(fp[1]):
			for dx in int(fp[0]):
				cells.append(Vector2i(int(e["pos"][0]) + dx, int(e["pos"][1]) + dy))
		spr.set_meta("scenery", cells)
		spr.set_meta("sprite_id", String(e["kind"]))
		_objects.add_child(spr)


## Ground-variant tiles: one atlas source per map scenery terrain texture, with
## alternatives 0-3 (flips), 4-7 and 8-11 (the same, fading out towards a patch edge).
func _surface_tile_set() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(_native, _native)
	var lib := TerrainPainter.scenery_library()
	var ids: Array = lib.keys()
	ids.sort()
	for id in ids:
		if String(lib[id].get("category", "")) != "terrain":
			continue
		var tex := Art.texture_at(String(lib[id].get("texture", "")))
		if tex == null:
			continue
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(_native, _native)
		src.create_tile(Vector2i.ZERO)
		for alt in range(1, 12):
			src.create_alternative_tile(Vector2i.ZERO, alt)
		for alt in 12:
			var td := src.get_tile_data(Vector2i.ZERO, alt)
			var turn := alt % 4
			td.flip_h = turn == 1 or turn == 3
			td.flip_v = turn == 2 or turn == 3
			td.modulate = Color(1, 1, 1, [1.0, 0.65, 0.3][alt / 4])
		_surface_sources[id] = ts.add_source(src)
	return ts


func _paint_static_cell(map: AdventureMap, t: Vector2i, occupied: Dictionary) -> void:
	var tid := map.terrain_at(t)
	var visual_tid := _visual_terrain(map, t)
	_ground.set_cell(t, TerrainTiles.SOURCE_TERRAIN, tiles.ground_coords(visual_tid, t))
	var covered := map.scenery_cover.has(t)
	if map.surface.has(t) and _surface_sources.has(map.surface[t]):
		# Fades in over two tiles from the patch edge; a stable flip/turn per tile.
		var depth := 2
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := t + Vector2i(dx, dy)
				if map.in_bounds(n) and map.surface.get(n, "") != map.surface[t]:
					depth = mini(depth, maxi(absi(dx), absi(dy)) - 1)
		_surface.set_cell(t, int(_surface_sources[map.surface[t]]), Vector2i.ZERO, TerrainTiles.cell_hash(t, 4, 41) + 4 * (2 - depth))
	var detail := tiles.detail_coords(visual_tid, t)
	if detail.x >= 0:
		_details.set_cell(t, TerrainTiles.SOURCE_TERRAIN, detail)
	if tid == "mountain" and not map.has_road(t) and not covered:
		var style := _barrier_style(t)
		var name: String = ["", "wall", "lava", "jungle", "chasm", "sandstone", "ice", "bones"][style]
		var field: Dictionary = tiles.info.get("barriers", {}).get(name, {})
		if style > 0 and not field.is_empty():
			var connected := func(n: Vector2i) -> bool: return map.in_bounds(n) and map.terrain_at(n) == "mountain" and not map.has_road(n) and _barrier_style(n) == style
			var bits := TerrainTiles.neighbor_bits(connected, t)
			var coords := tiles.highres_coords("barriers", name, t, bits)
			if coords.x < 0 and tiles.highres_tile_set == null:
				var masks: Array = field.get("masks", [])
				if not masks.is_empty():
					var variant := posmod(t.x, 2) + 2 * posmod(t.y, 2)
					coords = Vector2i(int(field["column"]) + TerrainTiles.mask_index(masks, TerrainTiles.reduce_mask(bits)) + variant * masks.size(), int(field["row"]))
			if coords.x >= 0:
				_barriers.set_cell(t, TerrainTiles.SOURCE_TERRAIN, coords)
	if tid == "infernal" and TerrainTiles.cell_hash(t, 3, 17) == 0:
		_glow_cells.append(t)
	for other in _blend_order:
		if other == visual_tid or tiles.has_specific_edge(visual_tid, other):
			continue
		var bits := TerrainTiles.neighbor_bits(func(n: Vector2i) -> bool: return map.in_bounds(n) and _visual_terrain(map, n) == other, t)
		var c := tiles.transition_coords(tiles.terrain_row(other), TerrainTiles.reduce_mask(bits), t)
		if c.x >= 0:
			_blends[other].set_cell(t, TerrainTiles.SOURCE_TERRAIN, c)
	for kind in _edges:
		var entry: Dictionary = tiles.info["edges"]["types"][kind]
		if String(entry["base"]) != visual_tid:
			continue
		var neighbors: Array = entry["neighbors"]
		var bits := TerrainTiles.neighbor_bits(func(n: Vector2i) -> bool: return map.in_bounds(n) and _visual_terrain(map, n) in neighbors, t)
		var edge := tiles.edge_coords(visual_tid, kind, bits, t)
		if edge.x >= 0:
			_edges[kind].set_cell(t, TerrainTiles.SOURCE_EDGES, edge)
	if map.has_road(t):
		var has_road := func(n: Vector2i) -> bool: return map.in_bounds(n) and map.has_road(n)
		var rm := TerrainTiles.road_mask(has_road, t)
		var bridge: bool = tid in tiles.info["roads"]["bridge_over"]
		var coords := Vector2i(-1, -1)
		var placed_high := false
		if not bridge:
			var style := "desert" if tid == "desert" else ("dirt" if tid in ["grass", "forest", "swamp"] else "stone")
			var bits := TerrainTiles.neighbor_bits(has_road, t)
			var high := tiles.highres_coords("roads", style, t, bits)
			if high.x >= 0:
				_highres_roads.set_cell(t, TerrainTiles.SOURCE_TERRAIN, high)
				placed_high = true
			else:
				coords = tiles.themed_road_coords(style, t, bits)
		if not placed_high:
			if coords.x < 0:
				coords = tiles.road_coords(rm, bridge)
			_roads.set_cell(t, TerrainTiles.SOURCE_TERRAIN, coords)
	elif not occupied.has(t) and not covered and (tid != "mountain" or _barrier_style(t) == 0 or tiles.info.get("barriers", {}).is_empty()):
		var dc := Vector2i(-1, -1)
		if map.decorations.has(t):
			dc = tiles.authored_deco_coords(String(map.decorations[t]), t, int(map.decoration_variants.get(t, -1)))
		elif map.decor_mode != TerrainPainter.DECOR_MODE or not map.is_passable(t) or tid == "river":
			# Painted maps place every land decoration themselves; mountains and
			# water keep the view's own scenery.
			dc = tiles.deco_coords(tid, t)
		if dc.x >= 0:
			_deco.set_cell(t, TerrainTiles.SOURCE_DECO, dc)


# A barrier inherits the nearest land biome, rather than painting a random
# foreign biome beneath it. Cache this because transitions inspect neighbors.
func _barrier_biome(map: AdventureMap, t: Vector2i) -> String:
	if _barrier_biomes.has(t):
		return _barrier_biomes[t]
	for radius in range(1, 9):
		var counts := {}
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n := t + Vector2i(dx, dy)
				if not map.in_bounds(n):
					continue
				var terrain := map.terrain_at(n)
				if terrain in ["mountain", "water", "river"]:
					continue
				counts[terrain] = int(counts.get(terrain, 0)) + 1
		if not counts.is_empty():
			var keys := counts.keys()
			keys.sort()
			var best: String = keys[0]
			for key in keys:
				if counts[key] > counts[best]:
					best = key
			_barrier_biomes[t] = best
			return best
	_barrier_biomes[t] = "mountain"
	return "mountain"


func _visual_terrain(map: AdventureMap, t: Vector2i) -> String:
	var tid := map.terrain_at(t)
	if tid == "mountain" and map.scenery_cover.has(t):
		return _barrier_biome(map, t)
	if tid != "mountain" or map.has_road(t) or tiles.info.get("barriers", {}).is_empty():
		return tid
	return _barrier_biome(map, t) if _barrier_style(t) != 0 else tid


# Choose a fitting style for each biome, consistently within broad regions.
func _barrier_style(t: Vector2i) -> int:
	if _barrier_styles.has(t):
		return _barrier_styles[t]
	var biome := _barrier_biome(_display_map(), t)
	var choices: Array = {
		"grass": [0, 4], "rough": [0, 4], "desert": [4, 5],
		"forest": [3], "swamp": [3, 7], "infernal": [2],
		"snow": [0, 1, 6], "mountain": [0],
	}.get(biome, [0])
	var region := Vector2i(floori(float(t.x) / 8.0), floori(float(t.y) / 8.0))
	var style := int(choices[TerrainTiles.cell_hash(region, choices.size(), 29)])
	_barrier_styles[t] = style
	return style


func _hero_start(t: Vector2i) -> bool:
	if session == null:
		return _preview_starts.has(t)
	for id in session.state.heroes:
		if session.state.heroes[id].pos == t:
			return true
	return false


# ----------------------------------------------------------- dynamic layers --

func _sync_objects() -> void:
	for c in _objects.get_children():
		if not c.has_meta("hero") and not c.has_meta("scenery"):
			c.queue_free()
	_unsprited.clear()
	var map := session.state.map
	var fog: FogOfWar = session.current_player()["fog"]
	for c in _objects.get_children():
		if c.has_meta("scenery"):
			c.visible = (c.get_meta("scenery") as Array).any(func(p: Vector2i) -> bool: return fog.is_explored(p))
	for id in map.objects:
		var o: Dictionary = map.objects[id]
		var p := AdventureMap.object_pos(o)
		if not fog.is_explored(p):
			continue
		var sid := object_sprite_id(o)
		if sid == "" or Art.sprite(sid) == null:
			_unsprited.append(p)
			continue
		var spr := _make_sprite(sid)
		spr.position = _feet_native(p)
		if o["type"] in ["scenario_site", "quest_item", "gate"]:
			var marker := Label.new()
			marker.text = "RELIC" if o["type"] == "quest_item" else ("SEALED" if o["type"] == "gate" and bool(o.get("closed", false)) else "!")
			if o["type"] == "scenario_site":
				marker.text = "GOAL" if o.get("kind", "") == "goal" else ("DONE" if bool(o.get("claimed", false)) else "!")
			if o["type"] == "gate" and not bool(o.get("closed", false)):
				spr.modulate.a = 0.45
			marker.add_theme_font_size_override("font_size", 11)
			marker.add_theme_color_override("font_color", UiStyle.BRASS)
			marker.add_theme_color_override("font_outline_color", Color.BLACK)
			marker.add_theme_constant_override("outline_size", 3)
			marker.position = spr.position + Vector2(-15, -56)
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_objects.add_child(marker)
		if o["type"] == "neutral_army":
			spr.flip_h = true       # neutrals face the approaching hero
		if Art.sprite_info(sid).has("flag"):
			_add_flag(spr, sid, int(o.get("owner", -1)))
		elif o["type"] == "site" and o.has("owner"):
			_add_flag(spr, sid, int(o["owner"]), SITE_FLAG)
		_objects.add_child(spr)
		if MapCobolts.is_post(o, session.data) and o.get("plundered", false):
			spr.modulate = Color(0.4, 0.34, 0.3)
		var guard: Array = [] if MapCobolts.is_post(o, session.data) else o.get("guard", [])
		if not guard.is_empty() and Art.creature(String(guard[0][0])) != null:
			# Guards stand in front of what they guard, facing the hero.
			var g := _make_sprite("creature_" + String(guard[0][0]))
			g.flip_h = true
			g.position = spr.position + Vector2(7, 2)
			_objects.add_child(g)

	if ScenarioRules.active(session.state):
		var entries := {}
		for wave in WaveDirector.waves(session.state):
			if session.state.scenario_runtime.get("spawned", []).has(wave["id"]) or not session.state.scenario_runtime.get("warned", []).has(wave["id"]):
				continue
			var p := Vector2i(int(wave["spawn"][0]), int(wave["spawn"][1]))
			if entries.has(p) or not fog.is_explored(p):
				continue
			entries[p] = true
			var label := Label.new()
			label.text = "ENTRY · DAY %d" % wave["day"]
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", UiStyle.WARN)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 4)
			label.position = _feet_native(p) + Vector2(-24, -40)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_objects.add_child(label)


## Sprite id for a map object, or "" (drawn as a placeholder marker).
func object_sprite_id(o: Dictionary) -> String:
	if o.has("sprite"):
		return String(o["sprite"])
	match String(o.get("type", "")):
		"resource":
			return "resource_" + String(o.get("resource", ""))
		"neutral_army":
			var stacks: Array = o.get("stacks", [])
			return "creature_" + String(stacks[0][0]) if not stacks.is_empty() else ""
		"town":
			return "town_" + String(o.get("town_type", o.get("faction", "")))
		"mine":
			return "mine_" + String(o.get("resource", ""))
		"encounter":
			return EncounterSystem.sprite_id(String(o.get("encounter", "")), session.data) if session != null else "encounter_" + String(o.get("encounter", ""))
		"site":
			return String(session.data.sites.get(String(o.get("site", "")), {}).get("sprite", "")) if session != null else ""
		"chest", "treasure", "artifact":
			return "object_chest"
	return ""


## Owner pennant on a town or mine: tinted with the owner's colour, grey if unowned.
func _add_flag(parent: Sprite2D, sid: String, owner: int, at: Array = []) -> void:
	var flag := _make_sprite("object_flag")
	if flag.texture == null:
		return
	if at.is_empty():
		at = Art.sprite_info(sid)["flag"]
	flag.scale = Vector2.ONE      # inherits the parent's map scale
	flag.position = parent.offset + Vector2(at[0], at[1])
	flag.modulate = Color(session.state.player(owner)["color"]).lightened(0.15) if owner >= 0 else Color("#8a8478")
	parent.add_child(flag)


func _make_sprite(sid: String) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = Art.sprite(sid)
	spr.centered = false
	spr.offset = -Art.anchor(sid)
	# High-detail sprites (64 px figures) carry their own map scale, so a
	# figure is about 1.6 tiles tall whatever its source resolution.
	var ms := float(Art.sprite_info(sid).get("map_scale", 1.0))
	spr.scale = Vector2(ms, ms)
	spr.set_meta("rest_scale", spr.scale)
	spr.set_meta("rest_offset", spr.offset)
	spr.set_meta("rest_texture", spr.texture)
	spr.set_meta("sprite_id", sid)
	if sid.begins_with("creature_"):
		spr.set_meta("motion_kind", "creature")
	return spr


func _sync_heroes() -> void:
	var live := {}
	for id in session.state.heroes:
		var h: Hero = session.state.heroes[id]
		if not h.alive:
			continue
		live[id] = true
		var spr: Sprite2D = _hero_sprites.get(id)
		if spr == null:
			spr = _make_sprite(Art.hero_sprite_id(h.class_id))
			spr.set_meta("hero", id)
			spr.set_meta("motion_kind", "hero")
			var banner := _make_sprite("hero_banner")
			banner.scale = Vector2.ONE      # inherits the hero sprite scale
			spr.add_child(banner)
			_objects.add_child(spr)
			_hero_sprites[id] = spr
		var banner_spr: Sprite2D = spr.get_child(0)
		banner_spr.modulate = Art.banner_tint(Color(session.state.player(h.owner)["color"]))
		if not _animating.has(id):
			spr.position = hero_feet(h.pos)
	for id in _hero_sprites.keys():
		if not live.has(id):
			_hero_sprites[id].queue_free()
			_hero_sprites.erase(id)


func _sync_fog() -> void:
	if _fog == null:
		return
	_fog.clear()
	var map := session.state.map
	var fog: FogOfWar = session.current_player()["fog"]
	var hidden := func(n: Vector2i) -> bool: return map.in_bounds(n) and not fog.is_explored(n)
	for y in map.height:
		for x in map.width:
			var t := Vector2i(x, y)
			var explored := fog.is_explored(t)
			var c := tiles.fog_coords(t, 0 if not explored else TerrainTiles.neighbor_bits(hidden, t), explored)
			if c.x >= 0:
				_fog.set_cell(t, TerrainTiles.SOURCE_TERRAIN, c)
	# Objects/heroes under the shroud are hidden by the fog layer itself.


# ------------------------------------------------------------------ drawing --

func _draw_glow() -> void:
	for t in _glow_cells:
		var r := TILE * 1.8
		_glow.draw_texture_rect(_glow_tex, Rect2(center_px(t) - Vector2(r, r), Vector2(r, r) * 2), false)


## A visual indication of influence, not a movement or ownership rule. Only
## explored structures contribute, so the overlay cannot reveal hidden sites.
func _draw_territory() -> void:
	if session == null:
		return
	var map := session.state.map
	var fog: FogOfWar = session.current_player()["fog"]
	var cells := {} # tile -> [squared distance, owner]
	var ids := map.objects.keys()
	ids.sort()
	for id in ids:
		var o: Dictionary = map.objects[id]
		if o.get("type", "") not in ["town", "mine", "site"] or not o.has("owner"):
			continue
		var pos := AdventureMap.object_pos(o)
		if not fog.is_explored(pos):
			continue
		var owner := int(o["owner"])
		for dy in range(-TERRITORY_RADIUS, TERRITORY_RADIUS + 1):
			for dx in range(-TERRITORY_RADIUS, TERRITORY_RADIUS + 1):
				var distance := dx * dx + dy * dy
				var p := pos + Vector2i(dx, dy)
				if distance > TERRITORY_RADIUS * TERRITORY_RADIUS or not map.in_bounds(p):
					continue
				if not cells.has(p) or distance < int(cells[p][0]):
					cells[p] = [distance, owner]
	for p in cells:
		var owner: int = cells[p][1]
		var color := NEUTRAL_TERRITORY if owner < 0 else Color(session.state.player(owner)["color"])
		var top_left := tile_to_px(p)
		var edges := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
		var corners := [Vector2(0, 0), Vector2(TILE, 0), Vector2(TILE, TILE), Vector2(0, TILE)]
		for i in 4:
			var neighbor: Vector2i = p + edges[i]
			if cells.has(neighbor) and int(cells[neighbor][1]) == owner:
				continue
			var a: Vector2 = top_left + corners[i]
			var b: Vector2 = top_left + corners[(i + 1) % 4]
			_territory.draw_line(a, b, Color(0, 0, 0, 0.65), 5.0)
			_territory.draw_line(a, b, Color(color.r, color.g, color.b, 0.9), 2.5)


func _draw_under() -> void:
	if session == null:
		return
	for id in _hero_sprites:
		var h: Hero = session.state.heroes.get(id)
		if h == null or h.owner != session.state.current_player:
			continue
		var feet: Vector2 = _hero_sprites[id].position * _art_scale
		var col := Color(session.state.player(h.owner)["color"])
		if id == selected_hero_id:
			col = UiStyle.BRASS.lightened(0.2)
		_draw_ellipse(_under, feet + Vector2(0, 2), Vector2(17, 7), Color(0, 0, 0, 0.45), true)
		_draw_ellipse(_under, feet + Vector2(0, 2), Vector2(17, 7), col.lightened(0.3), false)


func _draw_ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		ci.draw_polyline(pts, col, 2.0)


func _draw_overlay() -> void:
	if session == null:
		return
	if not tiles.is_valid():
		_draw_fallback_markers()
	for p in _unsprited:
		# Object types that have no art yet (new content) stay visible and clickable.
		_overlay.draw_circle(center_px(p), 11, Color(0, 0, 0, 0.6))
		_overlay.draw_circle(center_px(p), 9, UiStyle.WARN)
	for t in threatened:
		_draw_threat_badge(t)
	_draw_path()
	if session.state.map.in_bounds(hovered):
		var r := Rect2(tile_to_px(hovered), Vector2(TILE, TILE))
		_overlay.draw_rect(r.grow(-1), Color(0, 0, 0, 0.5), false, 3.0)
		_overlay.draw_rect(r.grow(-1), Color("#ead08a", 0.85), false, 1.0)


## A red warning diamond with an exclamation mark above a threatened town.
func _draw_threat_badge(t: Vector2i) -> void:
	var c := center_px(t) + Vector2(0, -TILE * 0.95)
	var r := 11.0
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	var outline := PackedVector2Array([c + Vector2(0, -r - 2), c + Vector2(r + 2, 0), c + Vector2(0, r + 2), c + Vector2(-r - 2, 0)])
	_overlay.draw_colored_polygon(outline, Color(0, 0, 0, 0.8))
	_overlay.draw_colored_polygon(pts, UiStyle.BAD)
	_overlay.draw_line(c + Vector2(0, -6), c + Vector2(0, 2), Color.WHITE, 2.5)
	_overlay.draw_circle(c + Vector2(0, 5.5), 1.6, Color.WHITE)


## Minimal marker drawing when no art is built (keeps the game usable).
func _draw_fallback_markers() -> void:
	var map := session.state.map
	for id in map.objects:
		var p := AdventureMap.object_pos(map.objects[id])
		_overlay.draw_circle(center_px(p), 10, UiStyle.BAD)
	for id in session.state.heroes:
		var h: Hero = session.state.heroes[id]
		if h.alive:
			_overlay.draw_circle(center_px(h.pos), 12, Color(session.state.player(h.owner)["color"]))


func _draw_path() -> void:
	for i in path.size():
		var t: Vector2i = path[i]
		var ok := i < path_reachable
		var col := UiStyle.GOOD if ok else UiStyle.BAD
		var c := center_px(t) + Vector2(0, 8)
		if i == path.size() - 1:
			if path_is_attack:
				for o in [Vector2(1, 1), Vector2(0, 0)]:
					var cc: Color = Color(0, 0, 0, 0.7) if o != Vector2.ZERO else col
					_overlay.draw_line(c + o + Vector2(-8, -8), c + o + Vector2(8, 8), cc, 3.0)
					_overlay.draw_line(c + o + Vector2(8, -8), c + o + Vector2(-8, 8), cc, 3.0)
			else:
				_draw_ellipse(_overlay, c, Vector2(10, 5), Color(0, 0, 0, 0.6), false)
				_draw_ellipse(_overlay, c - Vector2(0, 1), Vector2(10, 5), col, false)
		else:
			_overlay.draw_circle(c, 4.5, Color(0, 0, 0, 0.6))
			_overlay.draw_circle(c, 3.0, col)


func _process(delta: float) -> void:
	_poll_touch()
	if _objects == null or not is_visible_in_tree():
		return
	_motion_time += delta
	for child in _objects.get_children():
		if not child is Sprite2D or not child.has_meta("motion_kind") or child.is_queued_for_deletion():
			continue
		var spr := child as Sprite2D
		var rest_scale: Vector2 = spr.get_meta("rest_scale")
		var rest_offset: Vector2 = spr.get_meta("rest_offset")
		var hero := String(spr.get_meta("hero", ""))
		var riding := hero != "" and _animating.has(hero)
		var phase := float(TerrainTiles.cell_hash(Vector2i(spr.position), 1000, 17)) * TAU / 1000.0
		# A moving hero uses a fixed phase; map position must not jitter the stride.
		if hero != "":
			phase = 0.0
		var pose := Vector3.ONE
		pose.z = 0.0
		if motion_enabled and (hero == "" or riding):
			pose = SpriteMotion.pose(_motion_time, phase, riding)
		spr.scale = rest_scale * Vector2(pose.x, pose.y)
		spr.offset = rest_offset
		if hero != "":
			var frame := UnitAnimation.sample(String(spr.get_meta("sprite_id")), "move", _motion_time - float(_animating.get(hero, 0.0))) if riding and motion_enabled else {}
			spr.texture = frame.get("texture", spr.get_meta("rest_texture"))
			spr.offset = -frame["anchor"] if not frame.is_empty() else rest_offset
			if spr.get_child_count() > 0:
				(spr.get_child(0) as Sprite2D).position.y = 0.0
