class_name TownScene
extends Control
## A fixed composition whose building layers follow the real town's built IDs.

signal building_selected(id: String)

const BUILDING_LOOP = preload("res://src/ui/town_building_loop.gd")
const LOOP_SECONDS := 8.0

static var _manifest: Dictionary = {}
var _scene: Dictionary = {}
var _built: Array = []
var _definitions: Dictionary = {}
var _data: GameData
var _textures: Dictionary = {}
var _hits: Array = []
var _hover := ""
var _touch_pending := false
static var _ambience_manifest: Dictionary = {}
var _ambience: Dictionary = {}
var _faction := ""
var _building_loops: Dictionary = {}
var _animation_time := 0.0
var _frame_budget := 0.0
var animation_enabled := true


func _init() -> void:
	custom_minimum_size = Vector2(680, 450)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


static func animation_phase(seconds: float) -> float:
	return fposmod(seconds, LOOP_SECONDS) / LOOP_SECONDS


static func ambience_for(faction: String) -> Dictionary:
	if _ambience_manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/town_ambience.json"))
		if parsed is Dictionary:
			_ambience_manifest = parsed
	return _ambience_manifest.get("factions", {}).get(faction, {})


func _process(delta: float) -> void:
	if not animation_enabled or _scene.is_empty() or not is_visible_in_tree():
		return
	_animation_time = fposmod(_animation_time + delta, LOOP_SECONDS)
	_frame_budget += delta
	if _frame_budget >= 1.0 / 24.0:
		_frame_budget = fmod(_frame_budget, 1.0 / 24.0)
		_update_animation()


func set_animation_time(seconds: float) -> void:
	_animation_time = fposmod(seconds, LOOP_SECONDS)
	_update_animation()


func _update_animation() -> void:
	var phase := animation_phase(_animation_time)
	for layer in _building_loops.values():
		if layer.visible:
			layer.set_phase(phase)
	queue_redraw()


static func scene_for(faction: String) -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/towns/manifest.json"))
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest.get("factions", {}).get(faction, {})


static func resolved_buildings(scene: Dictionary, built: Array) -> Array:
	var result := []
	for slot in scene.get("slots", []):
		var variants: Array = slot["variants"]
		for i in range(variants.size() - 1, -1, -1):
			if variants[i] in built:
				result.append(variants[i])
				break
	return result


func setup(town: Dictionary, data: GameData) -> void:
	_data = data
	var faction := String(town["town_type"])
	if faction != _faction:
		for layer in _building_loops.values():
			remove_child(layer)
			layer.queue_free()
		_building_loops.clear()
	_faction = faction
	_ambience = ambience_for(faction)
	_scene = scene_for(faction)
	_built = town.get("built", []).duplicate()
	_definitions = data.town_types[town["town_type"]]["buildings"]
	_hover = ""
	tooltip_text = "Select a building or an empty site to inspect its construction options."
	queue_redraw()


func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


func _draw() -> void:
	_hits.clear()
	for layer in _building_loops.values():
		layer.hide()
	if _scene.is_empty():
		return
	var native := Vector2(_scene["size"][0], _scene["size"][1])
	var factor := minf(size.x / native.x, size.y / native.y)
	var origin := (size - native * factor) * 0.5
	var background := _texture(_scene["background"])
	if background != null:
		draw_texture_rect(background, Rect2(origin, native * factor), false)
	_draw_ambience(Rect2(origin, native * factor), factor)
	var selected := resolved_buildings(_scene, _built)
	var slots: Array = _scene["slots"].duplicate()
	slots.sort_custom(func(a, b): return a["at"][1] < b["at"][1])
	for slot in slots:
		var id := String(slot["variants"][0])
		var occupied := false
		for variant in slot["variants"]:
			if variant in selected:
				id = variant
				occupied = true
				break
		var feet := origin + Vector2(slot["at"][0], slot["at"][1]) * factor
		var hit: Rect2
		if occupied and not _scene.get("assets", {}).has(id):
			# Built, but its art is still pending: a name plaque keeps it visible and selectable.
			hit = _draw_plaque(feet, String(_definitions.get(id, {}).get("name", id)), _hover == id)
		elif occupied:
			var tex := _texture(_scene["assets"][id])
			if tex == null:
				continue
			var limit := Vector2(slot["size"][0], slot["size"][1]) * factor
			var scale_factor := minf(limit.x / tex.get_width(), limit.y / tex.get_height())
			var dimensions := tex.get_size() * scale_factor
			hit = Rect2(feet - Vector2(dimensions.x * 0.5, dimensions.y), dimensions)
			if not _building_loops.has(id):
				var layer = BUILDING_LOOP.new()
				var source_id := String(_scene["assets"][id]).get_file().get_basename()
				layer.configure(tex, _ambience, _ambience.get("buildings", {}).get(source_id, {}), _building_loops.size())
				add_child(layer)
				_building_loops[id] = layer
			var building = _building_loops[id]
			building.position = hit.position
			building.size = hit.size
			building.z_index = slots.find(slot)
			building.set_highlight(_hover == id)
			building.set_phase(animation_phase(_animation_time))
			building.show()
		else:
			hit = Rect2(feet - Vector2(12, 9), Vector2(24, 18))
			draw_circle(feet, 7, Color(0.05, 0.06, 0.08, 0.8))
			draw_arc(feet, 7, 0, TAU, 20, UiStyle.accent() if _hover == id else Color("#9b8b63"), 1.0, true)
			draw_line(feet - Vector2(3, 0), feet + Vector2(3, 0), UiStyle.accent())
			draw_line(feet - Vector2(0, 3), feet + Vector2(0, 3), UiStyle.accent())
		_hits.append({"id": id, "rect": hit})


func _draw_ambience(rect: Rect2, factor: float) -> void:
	var style := String(_ambience.get("particles", "motes"))
	var tint := Color(String(_ambience.get("particle_color", "#dccb99")))
	var phase := animation_phase(_animation_time)
	var count := 38 if style == "snow" else 20
	for i in count:
		var seed_x := fposmod(float(i) * 0.618034, 1.0)
		var seed_y := fposmod(float(i) * 0.381966 + 0.17, 1.0)
		var at := rect.position + Vector2(seed_x, seed_y) * rect.size
		var angle := TAU * (phase + seed_x)
		var alpha := (0.5 + 0.5 * sin(angle)) * 0.25
		if style == "snow":
			at.y = rect.position.y + fposmod(seed_y + phase, 1.0) * rect.size.y
			at.x += sin(angle) * 12.0 * factor
			alpha *= sin(PI * fposmod(seed_y + phase, 1.0))
		else:
			at += Vector2(sin(angle) * 13.0, cos(angle) * 9.0) * factor
		var color := tint
		color.a = alpha
		var radius := maxf(0.65, (1.4 + seed_y) * factor)
		if style == "bubbles":
			draw_arc(at, radius * 1.5, 0, TAU, 10, color, 0.7, true)
		else:
			draw_circle(at, radius, color)


func _draw_plaque(feet: Vector2, text: String, hovered: bool) -> Rect2:
	var font := get_theme_default_font()
	var font_size := 12
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 14
	var rect := Rect2(feet - Vector2(width * 0.5, 24), Vector2(width, 22))
	draw_rect(rect, Color(0.05, 0.05, 0.06, 0.82))
	draw_rect(rect, UiStyle.accent() if hovered else Color("#9b8b63"), false, 1.0)
	draw_string(font, rect.position + Vector2(7, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiStyle.TEXT)
	return rect


func _hit_at(point: Vector2) -> String:
	for i in range(_hits.size() - 1, -1, -1):
		var hit: Dictionary = _hits[i]
		if hit["rect"].has_point(point):
			return String(hit["id"])
	return ""


func _building_tooltip(id: String) -> String:
	var definition: Dictionary = _definitions.get(id, {})
	if definition.is_empty():
		return ""
	var lines := [String(definition.get("name", "")), String(definition.get("description", ""))]
	for effect in definition.get("effects", []):
		var cid := String(effect.get("creature", ""))
		if effect.get("type") == "dwelling_upgrade":
			cid = String(_data.creature(cid).get("upgrade", ""))
		elif effect.get("type") != "dwelling":
			continue
		if cid != "":
			lines.append("Recruits: " + String(_data.creature(cid).get("name", cid)))
	return "\n".join(lines)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var id := _hit_at(event.position)
		if id != _hover:
			_hover = id
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if id != "" else Control.CURSOR_ARROW
			tooltip_text = _building_tooltip(id)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if TouchGestures.touch_ui():
			if event.pressed:
				_touch_pending = true
			else:
				if _touch_pending and Rect2(Vector2.ZERO, size).has_point(event.position):
					building_selected.emit(_hit_at(event.position))
				_touch_pending = false
		elif event.pressed:
			building_selected.emit(_hit_at(event.position))
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN:
		_touch_pending = false
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = ""
		queue_redraw()
