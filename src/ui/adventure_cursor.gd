class_name AdventureCursor
extends Node
## Presentation-only cursor intent. Hidden objects never influence its shape.

const ACTIONS := ["default", "move", "town", "attack", "capture", "pickup", "encounter", "select", "blocked", "wait"]
var map_view: MapView
var current_action := ""
var _textures: Dictionary = {}
var _session: GameSession
var _dirty := true
var _key := ""


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(_texture("select"), Input.CURSOR_POINTING_HAND, Vector2(2, 2))
	show_action("default")


func _exit_tree() -> void:
	if _session != null and _session.state_changed.is_connected(_invalidate):
		_session.state_changed.disconnect(_invalidate)
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)


func _invalidate() -> void:
	_dirty = true


func _texture(action: String) -> Texture2D:
	if not _textures.has(action):
		var atlas_texture := Art.sprite("cursor_" + action)
		_textures[action] = ImageTexture.create_from_image(atlas_texture.get_image()) if atlas_texture != null else null
	return _textures[action]


func show_action(action: String) -> void:
	if action == current_action:
		return
	current_action = action
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(_texture(action), Input.CURSOR_ARROW, Vector2(2, 2))


func _process(_delta: float) -> void:
	if map_view == null:
		return
	var s := map_view.session
	if s != _session:
		if _session != null and _session.state_changed.is_connected(_invalidate):
			_session.state_changed.disconnect(_invalidate)
		_session = s
		if _session != null:
			_session.state_changed.connect(_invalidate)
		_dirty = true
	var gui := get_viewport().gui_get_hovered_control()
	if s == null or gui != null or not map_view.is_visible_in_tree() or s.state.game_over:
		show_action("default")
		_dirty = true
		return
	if not map_view.input_enabled or not s.current_player()["is_human"]:
		show_action("wait")
		_dirty = true
		return
	var tile := map_view._event_tile(get_viewport().get_mouse_position())
	var key := "%s:%s:%s" % [tile, map_view.selected_hero_id, s.state.current_player]
	if _dirty or key != _key:
		_key = key
		_dirty = false
		show_action(action_for(s, map_view.selected_hero_id, tile))


static func action_for(s: GameSession, hero_id: String, tile: Vector2i) -> String:
	if s == null or s.state.game_over or not s.current_player()["is_human"]:
		return "default"
	if not s.state.map.in_bounds(tile):
		return "default"
	var h := s.hero(hero_id)
	# Do not inspect terrain, heroes, guards or objects under the shroud.
	if not s.current_player()["fog"].is_explored(tile):
		return "move" if h != null and h.alive and h.owner == s.state.current_player and h.movement_left > 0 else "default"
	var other := s.state.hero_at(tile)
	if other != null and other.owner == s.state.current_player and other.id != hero_id:
		return "select"
	if h == null or not h.alive or h.owner != s.state.current_player:
		return "default"
	var object := s.state.map.object_at(tile)
	if h.pos == tile:
		return "town" if object.get("type", "") == "town" and int(object.get("owner", -1)) == h.owner else "default"
	if not s.state.map.is_passable(tile) or h.movement_left <= 0:
		return "blocked"
	var plan := s.plan_path(hero_id, tile)
	if plan["path"].is_empty() or int(plan["reachable"]) == 0:
		return "blocked"
	if (other != null and other.owner != h.owner) or s.is_guarded(object, h.owner):
		return "attack"
	match String(object.get("type", "")):
		"town": return "town" if int(object.get("owner", -1)) == h.owner or s.allied(int(object.get("owner", -1)), h.owner) else "capture"
		"resource", "artifact": return "pickup"
		"mine": return "move" if int(object.get("owner", -1)) == h.owner or s.allied(int(object.get("owner", -1)), h.owner) else "capture"
		"site":
			if MapSites.kind(object, s.data) == "dwelling" and not s.allied(int(object.get("owner", -1)), h.owner):
				return "capture"
			return "encounter"
		"encounter": return "encounter"
	return "move"
