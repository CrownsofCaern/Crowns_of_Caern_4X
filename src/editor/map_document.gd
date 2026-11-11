class_name MapDocument
extends RefCounted
## Authored map data and reversible edits. No gameplay state or scene dependencies.

signal changed

const MAX_SIDE := 256
const MAX_HISTORY_BYTES := 8 * 1024 * 1024
const EDITABLE_TYPES := ["town", "mine", "resource", "neutral_army", "encounter", "artifact", "site"]

var _definition: Dictionary = {}
var _data: GameData
var _history: Array = []
var _cursor := 0
var _revision := 0
var _saved_revision := -1
var _next_revision := 1
var _history_bytes := 0
var _group_open := false
var _group_label := ""
var _pending: Array = []
var _pending_indices: Dictionary = {}
## A bundled data/maps file opened in dev mode: everything is editable and the
## parts the editor has no tools for (scenario, objectives, quests, teams,
## unknown object types and keys) ride along untouched.
var _data_map := false


static func blank(data: GameData, map_id: String, title: String, width: int,
		height: int, terrain_id: String = "grass") -> MapDocument:
	if width < 1 or height < 1 or width > MAX_SIDE or height > MAX_SIDE or not data.terrains.has(terrain_id):
		return null
	var rows: Array = []
	for y in height:
		rows.append(String(data.terrains[terrain_id]["char"]).repeat(width))
	return from_definition({"id": map_id, "name": title, "width": width, "height": height,
		"terrain": rows, "roads": [], "decorations": [], "players": [], "heroes": [], "objects": []}, data)


static func from_definition(definition: Dictionary, data: GameData) -> MapDocument:
	if not structural_errors(definition, data).is_empty():
		return null
	var document := MapDocument.new()
	document._definition = definition.duplicate(true)
	document._data = data
	return document


## Defensive document checks, deliberately allowing incomplete gameplay drafts.
## Do not call gameplay constructors/validators until their stronger preconditions hold.
static func structural_errors(definition: Dictionary, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	if not definition.get("id") is String or String(definition.get("id", "")).is_empty():
		errors.append("Map needs a non-empty string ID.")
	if definition.has("name") and not definition["name"] is String:
		errors.append("Map name must be a string.")
	for key in ["generator", "scenario"]:
		if definition.has(key) and not definition[key] is Dictionary:
			errors.append("%s must be a dictionary." % key)
	for key in ["width", "height"]:
		if not _integer(definition.get(key)) or int(definition[key]) < 1 or int(definition[key]) > MAX_SIDE:
			errors.append("%s must be an integer between 1 and %d." % [key, MAX_SIDE])
	for key in ["terrain", "players", "heroes", "objects"]:
		if not definition.get(key) is Array:
			errors.append("%s must be an array." % key)
	for key in ["roads", "decorations"]:
		if definition.has(key) and not definition[key] is Array:
			errors.append("%s must be an array." % key)
	if not errors.is_empty():
		return errors
	var size := Vector2i(int(definition["width"]), int(definition["height"]))
	if definition["terrain"].size() != size.y:
		errors.append("Terrain row count does not match height.")
	for row in definition["terrain"]:
		if not row is String or row.length() != size.x:
			errors.append("Terrain row width does not match width.")
			continue
		for ch in row:
			if not data.terrain_by_char.has(ch):
				errors.append("Unknown terrain character: %s." % ch)
	var ids := {}
	for key in ["objects", "heroes"]:
		for entity in definition[key]:
			if not entity is Dictionary:
				errors.append("%s entries must be dictionaries." % key)
				continue
			var id: Variant = entity.get("id")
			if not id is String or String(id).is_empty() or ids.has(id):
				errors.append("Entity IDs must be non-empty unique strings.")
			else:
				ids[id] = true
			if not _position(entity.get("pos"), size):
				errors.append("Entity %s needs an in-bounds integer position." % str(id))
			if key == "objects" and not entity.get("type") is String:
				errors.append("Object %s needs a type." % str(id))
			if entity.has("owner") and (not _integer(entity["owner"]) or entity["owner"] < -1):
				errors.append("Entity %s owner must be -1 or a non-negative player ID." % str(id))
	var player_ids := {}
	for player in definition["players"]:
		if not player is Dictionary:
			errors.append("Player entries must be dictionaries.")
			continue
		if not _integer(player.get("id")) or int(player["id"]) < 0 or player_ids.has(player["id"]):
			errors.append("Player IDs must be unique non-negative whole numbers.")
		else:
			player_ids[player["id"]] = true
		for key in ["name", "faction", "difficulty"]:
			if player.has(key) and not player[key] is String:
				errors.append("Player %s must be text." % key)
		if player.has("color") and (not player["color"] is String or not Color.html_is_valid(player["color"])):
			errors.append("Player colour must be a valid colour string.")
		if player.has("team") and not _integer(player["team"]):
			errors.append("Player team must be a whole number.")
		if player.has("is_human") and not player["is_human"] is bool:
			errors.append("Player controller must be human or computer.")
	for segment in definition.get("roads", []):
		if not segment is Dictionary or not _position(segment.get("from"), size) or not _position(segment.get("to"), size):
			errors.append("Road endpoints must be in-bounds integer positions.")
			continue
		var dx := absi(int(segment["from"][0]) - int(segment["to"][0]))
		var dy := absi(int(segment["from"][1]) - int(segment["to"][1]))
		if dx != 0 and dy != 0 and dx != dy:
			errors.append("Road segments must be straight or 45-degree diagonal.")
	for decoration in definition.get("decorations", []):
		if not decoration is Dictionary or not _position(decoration.get("pos"), size) or not decoration.get("kind") is String:
			errors.append("Decorations need an in-bounds position and a kind.")
	return errors


static func _integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value) and absf(value) <= 2147483647.0)


static func _position(value: Variant, size: Vector2i) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1]) and value[0] >= 0 and value[1] >= 0 and value[0] < size.x and value[1] < size.y


func definition() -> Dictionary:
	return _definition.duplicate(true)


func enable_data_editing() -> void:
	_data_map = true
	changed.emit()


func is_data_map() -> bool:
	return _data_map


func read_only() -> bool:
	if _data_map:
		return false
	if _definition.has("scenario"):
		return true
	for object in _definition["objects"]:
		if not object["type"] in EDITABLE_TYPES:
			return true
	return false


func is_dirty() -> bool:
	return _revision != _saved_revision or _pending.any(func(patch): return patch["before"] != patch["after"])


func mark_saved() -> void:
	if not _group_open:
		_saved_revision = _revision
		changed.emit()


func has_open_action() -> bool:
	return _group_open


func begin_action(label: String) -> bool:
	if _group_open or read_only():
		return false
	_group_open = true
	_group_label = label
	_pending = []
	_pending_indices.clear()
	return true


func end_action() -> void:
	if not _group_open:
		return
	_group_open = false
	_record(_group_label, _pending)
	_pending = []
	_pending_indices.clear()
	changed.emit()


func cancel_action() -> void:
	if not _group_open:
		return
	_apply(_pending, false)
	_pending = []
	_pending_indices.clear()
	_group_open = false
	changed.emit()


func can_undo() -> bool:
	return not _group_open and _cursor > 0


func can_redo() -> bool:
	return not _group_open and _cursor < _history.size()


func undo() -> void:
	if not can_undo():
		return
	_cursor -= 1
	var action: Dictionary = _history[_cursor]
	_apply(action["patches"], false)
	_revision = action["before_revision"]
	changed.emit()


func redo() -> void:
	if not can_redo():
		return
	var action: Dictionary = _history[_cursor]
	_apply(action["patches"], true)
	_revision = action["after_revision"]
	_cursor += 1
	changed.emit()


func paint_terrain(cells: Array[Vector2i], terrain_id: String) -> bool:
	if not _data.terrains.has(terrain_id):
		return false
	var character := String(_data.terrains[terrain_id]["char"])
	var patches: Array = []
	var seen := {}
	for cell in cells:
		if not _in_bounds(cell):
			return false
		if seen.has(cell):
			continue
		seen[cell] = true
		var old: String = _definition["terrain"][cell.y][cell.x]
		if old != character:
			patches.append({"field": "terrain", "cell": cell, "before": old, "after": character})
	return _edit("Paint terrain", patches)


func paint_roads(cells: Array[Vector2i], enabled: bool) -> bool:
	var map := AdventureMap.from_definition(_definition, _data)
	for cell in cells:
		if not _in_bounds(cell):
			return false
		map.road[map.index(cell)] = int(enabled)
	return _replace("roads", map.static_definition()["roads"], "Paint roads")


func set_decorations(decorations: Array) -> bool:
	return _replace("decorations", decorations, "Edit decorations")


func set_players(players: Array) -> bool:
	return _replace("players", players, "Edit players")


func set_title(title: String) -> bool:
	return _replace("name", title, "Rename map")


func put_entity(entity: Dictionary, hero: bool = false) -> bool:
	if not hero and not entity.get("type", "") in EDITABLE_TYPES:
		return false
	var field := "heroes" if hero else "objects"
	var entities: Array = _definition[field].duplicate(true)
	var found := false
	for i in entities.size():
		if entities[i]["id"] == entity.get("id"):
			entities[i] = entity.duplicate(true)
			found = true
			break
	if not found:
		entities.append(entity.duplicate(true))
	return _replace(field, entities, "Edit entity")


func remove_entity(id: String, hero: bool = false) -> bool:
	var field := "heroes" if hero else "objects"
	return _replace(field, _definition[field].filter(func(entity): return entity["id"] != id), "Delete entity")


func unique_entity_id(prefix: String = "object") -> String:
	var ids := {}
	for entity in _definition["objects"] + _definition["heroes"]:
		ids[entity["id"]] = true
	var suffix := 1
	while ids.has("%s_%d" % [prefix, suffix]):
		suffix += 1
	return "%s_%d" % [prefix, suffix]


func entity(id: String, hero: bool = false) -> Dictionary:
	for entry in _definition["heroes" if hero else "objects"]:
		if entry["id"] == id:
			return entry.duplicate(true)
	return {}


func entities_at(pos: Vector2i) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for field in ["objects", "heroes"]:
		for entry in _definition[field]:
			if AdventureMap.object_pos(entry) == pos:
				entries.append({"entity": entry.duplicate(true), "hero": field == "heroes"})
	return entries


## Placement issues do not prevent saving a draft. The UI can show these before
## full gameplay validation, which requires complete players/armies/object fields.
func placement_errors() -> Array[String]:
	var errors: Array[String] = []
	var map := AdventureMap.from_definition(_definition, _data)
	var occupied := {}
	for field in ["objects", "heroes"]:
		for entity in _definition[field]:
			var pos := AdventureMap.object_pos(entity)
			var id := String(entity["id"])
			# A gate is the blocker itself; it need not start on an open tile.
			if not map.is_passable(pos) and entity.get("type", "") != "gate":
				errors.append("%s is on impassable terrain at %s." % [id, pos])
			if occupied.has(pos):
				var previous: Dictionary = occupied[pos]
				var own_town: bool = field == "heroes" and previous.get("type", "") == "town" and int(entity.get("owner", -1)) >= 0 and entity.get("owner", -1) == previous.get("owner", -1)
				if not own_town:
					errors.append("%s shares %s with %s." % [id, pos, previous["id"]])
			occupied[pos] = entity
	return errors


## A copy of a bundled map stays bundled (dev mode Save As); anything else
## becomes a local draft.
func copy_as(map_id: String, title: String) -> MapDocument:
	if read_only():
		return null
	var copy := definition()
	copy["id"] = map_id
	copy["name"] = title
	if _data_map:
		var bundled := from_definition(copy, _data)
		if bundled != null:
			bundled._data_map = true
		return bundled
	# The validator is currently the only consumer of top-level generator data.
	# Retain the whole recipe/zone snapshot as provenance, without Fair certification.
	if copy.has("generator"):
		copy["editor_source"] = {"map_id": _definition["id"], "generator": copy["generator"].duplicate(true)}
		copy.erase("generator")
	return from_definition(copy, _data)


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(_definition["width"]) and cell.y < int(_definition["height"])


func _replace(field: String, value: Variant, label: String) -> bool:
	var candidate := definition()
	candidate[field] = value
	if not structural_errors(candidate, _data).is_empty():
		return false
	var before: Variant = _definition.get(field)
	if before == value:
		return true
	return _edit(label, [{"field": field, "before": before, "after": value,
		"existed": _definition.has(field)}])


func _edit(label: String, patches: Array) -> bool:
	if read_only():
		return false
	if patches.is_empty():
		return true
	patches = patches.duplicate(true)
	_apply(patches, true)
	if _group_open:
		for patch in patches:
			var key := "%s:%s" % [patch["field"], str(patch.get("cell", ""))]
			if _pending_indices.has(key):
				_pending[_pending_indices[key]]["after"] = patch["after"]
			else:
				_pending_indices[key] = _pending.size()
				_pending.append(patch)
	else:
		_record(label, patches)
	changed.emit()
	return true


func _apply(patches: Array, forward: bool) -> void:
	var ordered := patches.duplicate()
	if not forward:
		ordered.reverse()
	for patch in ordered:
		var value: Variant = patch["after" if forward else "before"]
		if patch.has("cell"):
			var cell: Vector2i = patch["cell"]
			var row: String = _definition["terrain"][cell.y]
			_definition["terrain"][cell.y] = row.substr(0, cell.x) + String(value) + row.substr(cell.x + 1)
		elif not forward and not patch.get("existed", true):
			_definition.erase(patch["field"])
		else:
			_definition[patch["field"]] = value.duplicate(true) if value is Array or value is Dictionary else value


func _record(label: String, patches: Array) -> void:
	patches = patches.filter(func(patch): return patch["before"] != patch["after"])
	if patches.is_empty():
		return
	while _history.size() > _cursor:
		_history_bytes -= int(_history.pop_back()["bytes"])
	var action := {"label": label, "patches": patches, "before_revision": _revision,
		"after_revision": _next_revision, "bytes": var_to_bytes(patches).size()}
	_next_revision += 1
	_revision = action["after_revision"]
	_history.append(action)
	_cursor += 1
	_history_bytes += int(action["bytes"])
	while _history_bytes > MAX_HISTORY_BYTES and not _history.is_empty():
		_history_bytes -= int(_history.pop_front()["bytes"])
		_cursor -= 1
