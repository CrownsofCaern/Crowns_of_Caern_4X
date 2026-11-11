class_name AdventureMap
extends RefCounted
## Static terrain grid plus mutable map objects (resources, neutral armies...).
## Objects are plain dictionaries keyed by id so they serialize trivially and
## new object types can be added from data without new classes.

var map_id: String = ""
var name: String = ""
var width: int = 0
var height: int = 0
var terrain: PackedStringArray = PackedStringArray()
var road: PackedByteArray = PackedByteArray()
var objects: Dictionary = {}
var _gates: Dictionary = {}
var _army_tiles: Dictionary = {}
var _army_tiles_dirty := true
var decorations: Dictionary = {}  # Vector2i -> atlas kind, cosmetic only
var decoration_variants: Dictionary = {}  # Vector2i -> atlas variant, where the map fixes it
## "painted": the decorations are the complete set for land tiles (TerrainPainter),
## so the map view adds none of its own there. "" = authored extras only.
var decor_mode: String = ""
## Map scenery pieces (TerrainPainter): [{pos (top-left), kind, footprint}], cosmetic
## art over their footprint; landmark footprints are impassable terrain anyway.
var scenery: Array = []
var scenery_cover: Dictionary = {}  # Vector2i -> index into scenery
## Cosmetic ground variants: Vector2i -> map scenery terrain asset id.
var surface: Dictionary = {}
var _data: GameData


static func from_definition(def: Dictionary, data: GameData) -> AdventureMap:
	var m := AdventureMap.new()
	m._data = data
	m.map_id = def["id"]
	m.name = def.get("name", m.map_id)
	m.width = int(def["width"])
	m.height = int(def["height"])
	m.terrain.resize(m.width * m.height)
	m.road.resize(m.width * m.height)
	var rows: Array = def["terrain"]
	assert(rows.size() == m.height, "map %s: expected %d rows" % [m.map_id, m.height])
	for y in m.height:
		var row: String = rows[y]
		assert(row.length() == m.width, "map %s row %d: expected width %d" % [m.map_id, y, m.width])
		for x in m.width:
			var ch := row[x]
			assert(data.terrain_by_char.has(ch), "map %s: unknown terrain char '%s'" % [m.map_id, ch])
			m.terrain[y * m.width + x] = data.terrain_by_char[ch]
	for seg in def.get("roads", []):
		var a := Vector2i(int(seg["from"][0]), int(seg["from"][1]))
		var b := Vector2i(int(seg["to"][0]), int(seg["to"][1]))
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var p := a
		while true:
			m.road[m.index(p)] = 1
			if p == b:
				break
			p += step
	for d in def.get("decorations", []):
		var p := Vector2i(int(d["pos"][0]), int(d["pos"][1]))
		if m.in_bounds(p):
			m.decorations[p] = String(d["kind"])
			if d.has("variant"):
				m.decoration_variants[p] = int(d["variant"])
	m.decor_mode = String(def.get("decor", ""))
	for e in def.get("scenery", []):
		var fp: Array = e.get("footprint", [1, 1])
		var entry := {"pos": [int(e["pos"][0]), int(e["pos"][1])], "kind": String(e["kind"]), "footprint": [int(fp[0]), int(fp[1])]}
		m.scenery.append(entry)
		for dy in int(fp[1]):
			for dx in int(fp[0]):
				var q := Vector2i(int(e["pos"][0]) + dx, int(e["pos"][1]) + dy)
				if m.in_bounds(q):
					m.scenery_cover[q] = m.scenery.size() - 1
	var sf: Dictionary = def.get("surface", {})
	var skinds: Array = sf.get("kinds", [])
	var srows: Array = sf.get("rows", [])
	for y in mini(srows.size(), m.height):
		var row := String(srows[y])
		for x in mini(row.length(), m.width):
			var k := row.unicode_at(x) - 97
			if k >= 0 and k < skinds.size():
				m.surface[Vector2i(x, y)] = String(skinds[k])
	for o in def.get("objects", []):
		m.add_object(o.duplicate(true))
	return m


## The static part of the map (terrain and roads) as a map definition without
## objects. Saves of generated maps store this so they do not depend on the
## generator producing the same map again.
func static_definition() -> Dictionary:
	var rows: Array = []
	for y in height:
		var row := ""
		for x in width:
			row += String(_data.terrain(terrain[y * width + x])["char"])
		rows.append(row)
	var roads: Array = []
	for y in height:
		var x := 0
		while x < width:
			if road[y * width + x] == 1:
				var x2 := x
				while x2 + 1 < width and road[y * width + x2 + 1] == 1:
					x2 += 1
				roads.append({"from": [x, y], "to": [x2, y]})
				x = x2 + 1
			else:
				x += 1
	var deco: Array = []
	for p in decorations:
		var entry := {"pos": [p.x, p.y], "kind": decorations[p]}
		if decoration_variants.has(p):
			entry["variant"] = decoration_variants[p]
		deco.append(entry)
	var out := {"id": map_id, "name": name, "width": width, "height": height, "terrain": rows, "roads": roads,
		"decorations": deco, "objects": []}
	if decor_mode != "":
		out["decor"] = decor_mode
	if not scenery.is_empty():
		out["scenery"] = scenery.duplicate(true)
	if not surface.is_empty():
		var kinds: Array = []
		for p in surface:
			if not kinds.has(surface[p]):
				kinds.append(surface[p])
		kinds.sort()
		var srows: Array = []
		for y in height:
			var row := ""
			for x in width:
				var p := Vector2i(x, y)
				row += String.chr(97 + kinds.find(surface[p])) if surface.has(p) else "."
			srows.append(row)
		out["surface"] = {"kinds": kinds, "rows": srows}
	return out


func set_data(data: GameData) -> void:
	_data = data


func index(p: Vector2i) -> int:
	return p.y * width + p.x


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func terrain_at(p: Vector2i) -> String:
	return terrain[index(p)]


func has_road(p: Vector2i) -> bool:
	return road[index(p)] == 1


func is_passable(p: Vector2i) -> bool:
	if not in_bounds(p):
		return false
	if _gates.has(p) and bool(objects[_gates[p]].get("closed", false)):
		return false
	# A road makes any tile passable (bridges over rivers or water).
	return has_road(p) or bool(_data.terrain(terrain_at(p))["passable"])


## Movement points needed to enter tile p orthogonally.
func move_cost(p: Vector2i) -> int:
	if has_road(p):
		return int(_data.road["move_cost"])
	return int(_data.terrain(terrain_at(p))["move_cost"])


func combat_terrain(p: Vector2i) -> String:
	return String(_data.terrain(terrain_at(p))["combat_terrain"])


func vision_mod(p: Vector2i) -> int:
	return int(_data.terrain(terrain_at(p))["vision_mod"])


func add_object(o: Dictionary) -> void:
	if o.get("type", "") == "gate":
		_gates[object_pos(o)] = String(o["id"])
	objects[o["id"]] = o
	_army_tiles_dirty = true


func remove_object(object_id: String) -> void:
	if objects.has(object_id) and objects[object_id].get("type", "") == "gate":
		_gates.erase(object_pos(objects[object_id]))
	objects.erase(object_id)
	_army_tiles_dirty = true


## Neutral army ids on the 8 tiles around p (not p itself), sorted. Used by the
## guard rule: a pickup or mine next to a neutral army cannot be claimed
## until that army is beaten (see GameSession.claim_guard()).
func armies_around(p: Vector2i) -> Array[String]:
	if _army_tiles_dirty:
		_army_tiles = {}
		for id in objects:
			var o: Dictionary = objects[id]
			if o.get("type", "") == "neutral_army":
				var at := object_pos(o)
				if not _army_tiles.has(at):
					_army_tiles[at] = []
				_army_tiles[at].append(String(id))
		_army_tiles_dirty = false
	var out: Array[String] = []
	if _army_tiles.is_empty():
		return out
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				for id in _army_tiles.get(p + Vector2i(dx, dy), []):
					out.append(String(id))
	out.sort()
	return out


func object_at(p: Vector2i) -> Dictionary:
	for id in objects:
		var o: Dictionary = objects[id]
		if int(o["pos"][0]) == p.x and int(o["pos"][1]) == p.y:
			return o
	return {}


static func object_pos(o: Dictionary) -> Vector2i:
	return Vector2i(int(o["pos"][0]), int(o["pos"][1]))


## Positions that block movement unless they are the destination.
func blocking_positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in objects:
		var o: Dictionary = objects[id]
		if o["type"] == "neutral_army" or o["type"] == "encounter":
			out.append(object_pos(o))
	return out
