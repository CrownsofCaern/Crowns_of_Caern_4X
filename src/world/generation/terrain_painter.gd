class_name TerrainPainter
extends RefCounted
## The map generator's terrain pass and the decoration pass (data/terrain_painting.json).
##
## paint_terrain() runs after the zone layout and town anchors, before roads and
## objects, so roads route around lakes and nothing is placed on deep water:
##   1. every zone keeps its main biome and gets 1-2 secondary biomes as
##      noise-shaped patches (exact share per zone, dithered and smoothed edges);
##   2. zones joined by a pass bleed into each other around the pass;
##   3. rivers (passable fords) meander across a zone from wall to wall;
##   4. lakes (deep water) that never cut a zone apart, with soft shores.
## Zones of one template group share a plan (same secondaries, share, rivers,
## lakes); rotate180 templates are painted point-symmetrically.
##
## decorate() is pure over a map definition, so it also works for frozen or
## hand-made maps: weighted pools per biome, clustered by noise with clearings,
## and no tile shares kind and variant with a neighbour. A definition with
## "decor": "painted" tells the map view to show only these decorations on land
## instead of its hash-based fallback.
##
## Headless and deterministic: all randomness comes from the GameRng passed in.

const DECOR_MODE := "painted"
const SCENERY_MANIFEST := "res://assets/map_scenery/manifest.json"
static var _scenery_cache: Dictionary = {}
const NEIGHBORS8 := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

var data: GameData
var cfg: Dictionary
var rng: GameRng
var layout: ZoneLayout
var w: int = 0
var h: int = 0
var terrain := PackedStringArray()
var reserved := PackedByteArray()
var anchors := PackedInt32Array()
## Per zone: {profile, group, biome, patches, river, player?}.
var zones: Array = []
var symmetric: bool = false
## Landmarks placed by paint_terrain: [{pos, kind, footprint}] (pos = top-left).
var landmarks: Array = []
var _field: _Noise
var _split: _Noise
var _meander: _Noise


func _init(game_data: GameData, painter_rng: GameRng) -> void:
	data = game_data
	cfg = game_data.terrain_painting
	rng = painter_rng


# ----------------------------------------------------------------- terrain --

## Paints biomes, rivers and lakes into `terrain_in` and returns the result.
## `zone_info[z]` = {profile, group, biome, patches (profile hint list), river (bool),
## player (start zones only)}.
func paint_terrain(zone_layout: ZoneLayout, terrain_in: PackedStringArray, reserved_in: PackedByteArray,
		anchor_tiles: PackedInt32Array, zone_info: Array, point_symmetric: bool) -> PackedStringArray:
	layout = zone_layout
	terrain = terrain_in.duplicate()
	reserved = reserved_in
	anchors = anchor_tiles
	zones = zone_info
	symmetric = point_symmetric
	w = layout.width
	h = layout.height
	if cfg.is_empty():
		return terrain
	_field = _Noise.new(w, h, 6, rng)
	_split = _Noise.new(w, h, 9, rng)
	_meander = _Noise.new(w, h, 4, rng)
	var plans := _plan_zones()
	_paint_secondaries(plans)
	_blend_gates()
	for z in zones.size():
		_smooth(z, layout.open_tiles(z), String(zones[z]["biome"]))
	_paint_rivers(plans)
	if symmetric:
		_mirror_passable()
	_place_lakes(plans)
	_place_landmarks()
	return terrain


## Settings for zone z: the profile's entry over `default`.
func _settings(z: int) -> Dictionary:
	var profiles: Dictionary = cfg.get("profiles", {})
	var s: Dictionary = (profiles.get("default", {}) as Dictionary).duplicate()
	s.merge(profiles.get(String(zones[z].get("profile", "")), {}), true)
	return s


## One plan per template group; all player start zones of a profile share one
## too (marches templates give every start its own group). Zones of a shared
## plan on another main biome roll their own secondaries but keep the share,
## rivers and lakes.
func _plan_zones() -> Array:
	var by_group := {}
	var secs_by := {}
	var plans: Array = []
	for z in zones.size():
		var key := String(zones[z].get("group", str(z)))
		if zones[z].has("player"):
			key = "player:" + String(zones[z].get("profile", ""))
		if not by_group.has(key):
			by_group[key] = _roll_plan(z)
		var plan: Dictionary = (by_group[key] as Dictionary).duplicate()
		var skey := key + "/" + String(zones[z]["biome"])
		if not secs_by.has(skey):
			secs_by[skey] = plan["secondaries"] if String(plan["biome"]) == String(zones[z]["biome"]) else _roll_secondaries(z)
		plan["secondaries"] = secs_by[skey]
		plans.append(plan)
	return plans


func _roll_plan(z: int) -> Dictionary:
	var s := _settings(z)
	var secs := _roll_secondaries(z)
	var cov: Array = s.get("coverage", [0.0, 0.0])
	var cells: Array = cfg.get("noise_cell", [6, 6])
	var lake_span: Array = s.get("lakes", [0, 0])
	var size_span: Array = s.get("lake_size", [6, 12])
	var lake_sizes: Array = []
	for _l in rng.next_int(int(lake_span[0]), int(lake_span[1])):
		lake_sizes.append(rng.next_int(int(size_span[0]), int(size_span[1])))
	return {
		"biome": String(zones[z]["biome"]),
		"secondaries": secs,
		"coverage": rng.next_float_range(float(cov[0]), float(cov[1])),
		"scale": 6.0 / rng.next_float_range(float(cells[0]), float(cells[1])),
		"river": bool(zones[z].get("river", false)) or rng.chance(float(s.get("river_chance", 0.0))),
		"lakes": lake_sizes,
	}


func _roll_secondaries(z: int) -> Array[String]:
	var s := _settings(z)
	var biome := String(zones[z]["biome"])
	var weights: Dictionary = (cfg.get("affinity", {}).get(biome, {}) as Dictionary).duplicate()
	for t in zones[z].get("patches", []):
		weights[String(t)] = float(weights.get(String(t), 0.0)) + float(cfg.get("patch_hint_weight", 1.0))
	weights.erase(biome)
	var keys: Array = weights.keys()
	keys.sort()
	var secs: Array[String] = []
	var span: Array = s.get("secondaries", [1, 1])
	var count := rng.next_int(int(span[0]), int(span[1]))
	for _k in count:
		var ws: Array = []
		var any := false
		for k in keys:
			var wt := 0.0 if secs.has(String(k)) else float(weights[k])
			ws.append(wt)
			any = any or wt > 0.0
		if not any:
			break
		secs.append(String(keys[rng.weighted_index(ws)]))
	return secs


func _home(i: int, z: int) -> bool:
	if anchors.size() <= z or anchors[z] < 0:
		return false
	var a := layout.pos(anchors[z])
	var p := layout.pos(i)
	return maxi(absi(a.x - p.x), absi(a.y - p.y)) <= int(cfg.get("keep_home_radius", 2))


func _paint_secondaries(plans: Array) -> void:
	var dither := float(cfg.get("dither", 0.0))
	for z in zones.size():
		var plan: Dictionary = plans[z]
		var secs: Array = plan["secondaries"]
		if secs.is_empty():
			continue
		var base := String(zones[z]["biome"])
		var tiles := layout.open_tiles(z)
		var target := int(round(tiles.size() * float(plan["coverage"])))
		if target <= 0:
			continue
		var cand := PackedInt32Array()
		var vals := PackedFloat32Array()
		var k := float(plan["scale"])
		for i in tiles:
			if terrain[i] != base or _home(i, z):
				continue
			var p := Vector2(layout.pos(i)) * k
			cand.append(i)
			vals.append(_field.fbm(p) + rng.next_float_range(-dither, dither))
		if cand.is_empty():
			continue
		var sorted := vals.duplicate()
		sorted.sort()
		var threshold := sorted[maxi(0, sorted.size() - target)]
		for j in cand.size():
			if vals[j] < threshold:
				continue
			var i := cand[j]
			var pick := 0
			if secs.size() > 1 and _split.fbm(Vector2(layout.pos(i)) * k) < 0.0:
				pick = 1
			terrain[i] = String(secs[pick])


## One cellular pass: lone patch tiles revert, tiles surrounded by a patch join it.
func _smooth(z: int, tiles: PackedInt32Array, base: String) -> void:
	var changes := {}
	for i in tiles:
		if _home(i, z):
			continue
		var p := layout.pos(i)
		var counts := {}
		var same := 0
		for d in NEIGHBORS8:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				continue
			var n := layout.idx(q)
			if layout.zone_of[n] != z or layout.wall[n] != 0:
				continue
			if terrain[n] == terrain[i]:
				same += 1
			if terrain[n] != base and terrain[n] != terrain[i]:
				counts[terrain[n]] = int(counts.get(terrain[n], 0)) + 1
		if terrain[i] != base and same <= 1:
			changes[i] = base
		elif terrain[i] == base:
			for t in counts:
				if int(counts[t]) >= 6:
					changes[i] = t
	for i in changes:
		terrain[i] = String(changes[i])


## Around each pass, tiles take the neighbouring zone's biome with a chance that
## falls off with distance, so biome changes at passes are not a hard line.
func _blend_gates() -> void:
	var radius := int(cfg.get("gate_blend", 0))
	if radius <= 0:
		return
	for g in layout.gates:
		var center := int(g.get("center", -1))
		if center < 0:
			continue
		var za := int(g["a"])
		var zb := int(g["b"])
		var ba := String(zones[za]["biome"])
		var bb := String(zones[zb]["biome"])
		if ba == bb:
			continue
		var c := layout.pos(center)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var q := c + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
					continue
				var i := layout.idx(q)
				var z := layout.zone_of[i]
				if layout.wall[i] != 0 or (z != za and z != zb) or _home(i, z):
					continue
				var d := maxi(absi(dx), absi(dy))
				if rng.chance(0.65 * (1.0 - float(d) / float(radius + 1))):
					terrain[i] = bb if z == za else ba


func _paint_rivers(plans: Array) -> void:
	for z in zones.size():
		if not bool(plans[z]["river"]):
			continue
		var tiles := layout.open_tiles(z)
		var rim := PackedInt32Array()
		for i in tiles:
			if _on_rim(i) and reserved[i] == 0:
				rim.append(i)
		if rim.size() < 2:
			continue
		var a := rim[rng.next_int(0, rim.size() - 1)]
		var pa := layout.pos(a)
		# The far end: a random rim tile among the farthest third.
		var by_dist: Array = []
		for i in rim:
			by_dist.append([layout.pos(i).distance_squared_to(pa), i])
		by_dist.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
		var lo := by_dist.size() * 2 / 3
		var b := int(by_dist[rng.next_int(lo, by_dist.size() - 1)][1])
		var cost := PackedInt32Array()
		cost.resize(w * h)
		for i in tiles:
			if reserved[i] != 0 or _home(i, z) or not _passable_terrain(terrain[i]):
				continue
			cost[i] = 10 + int(30.0 * (_meander.fbm(Vector2(layout.pos(i))) + 1.0))
		cost[a] = maxi(cost[a], 1)
		cost[b] = maxi(cost[b], 1)
		for i in GridSearch.path(w, h, cost, a, b):
			terrain[i] = "river"


func _on_rim(i: int) -> bool:
	var p := layout.pos(i)
	if p.x == 0 or p.y == 0 or p.x == w - 1 or p.y == h - 1:
		return true
	for n in GridSearch.neighbors4(w, h, i):
		if layout.wall[n] != 0:
			return true
	return false


func _passable_terrain(t: String) -> bool:
	return bool(data.terrain(t).get("passable", false))


## rotate180 templates: the half with the lower tile index is the original and
## its passable paint is copied onto the point-mirrored tile of a zone on the
## same main biome.
func _mirror_passable() -> void:
	for i in w * h:
		var m := layout.mirror_index(i)
		if i <= m or layout.wall[i] != 0 or layout.wall[m] != 0:
			continue
		# Only between zones on the same main biome: mirrored starts of two
		# factions keep their own native ground and are painted from one plan.
		if String(zones[layout.zone_of[i]]["biome"]) != String(zones[layout.zone_of[m]]["biome"]):
			continue
		if _passable_terrain(terrain[i]) and _passable_terrain(terrain[m]):
			terrain[i] = terrain[m]


func _place_lakes(plans: Array) -> void:
	var done := {}
	for z in zones.size():
		if done.has(z):
			continue
		for size in plans[z]["lakes"]:
			for _try in 12:
				if _try_lake(z, int(size)):
					break
		done[z] = true
		if symmetric and anchors.size() > z:
			done[layout.zone_of[layout.mirror_index(anchors[z])]] = true


func _lake_ok(i: int, z: int) -> bool:
	if layout.zone_of[i] != z or layout.wall[i] != 0 or terrain[i] == "river" or not _passable_terrain(terrain[i]):
		return false
	var p := layout.pos(i)
	if p.x == 0 or p.y == 0 or p.x == w - 1 or p.y == h - 1:
		return false
	# Keep a ring around anchors, passes and their approaches.
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var q := p + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and reserved[layout.idx(q)] != 0:
				return false
	return true


func _try_lake(z: int, size: int) -> bool:
	var tiles := layout.open_tiles(z)
	var start := tiles[rng.next_int(0, tiles.size() - 1)]
	if not _lake_ok(start, z):
		return false
	var blob := PackedInt32Array([start])
	var frontier := PackedInt32Array()
	for _s in size * 4:
		if blob.size() >= size:
			break
		frontier.clear()
		var weights: Array = []
		for t in blob:
			for n in GridSearch.neighbors4(w, h, t):
				if blob.has(n) or frontier.has(n) or not _lake_ok(n, z):
					continue
				var touching := 0
				for m in GridSearch.neighbors4(w, h, n):
					if blob.has(m):
						touching += 1
				frontier.append(n)
				weights.append(touching * touching)
		if frontier.is_empty():
			break
		blob.append(frontier[rng.weighted_index(weights)])
	if blob.size() < maxi(3, size / 2):
		return false
	var all := blob.duplicate()
	var mz := -1
	if symmetric:
		mz = layout.zone_of[layout.mirror_index(start)]
		for t in blob:
			var m := layout.mirror_index(t)
			if all.has(m):
				continue
			if not _lake_ok(m, mz):
				return false
			all.append(m)
	var zs: Array[int] = [z]
	if mz >= 0 and mz != z:
		zs.append(mz)
	var before := {}
	for zz in zs:
		before[zz] = _reach(zz)
	var old := PackedStringArray()
	for t in all:
		old.append(terrain[t])
		terrain[t] = "water"
	for zz in zs:
		var lost := 0
		for t in all:
			if layout.zone_of[t] == zz:
				lost += 1
		if _reach(zz) != int(before[zz]) - lost:
			for j in all.size():
				terrain[all[j]] = old[j]
			return false
	_shore(all, old)
	return true


## Some tiles around a lake turn into the shore biome of what they were.
func _shore(lake: PackedInt32Array, _old: PackedStringArray) -> void:
	var shores: Dictionary = cfg.get("shores", {})
	var chance := float(cfg.get("shore_chance", 0.0))
	for t in lake:
		for n in GridSearch.neighbors4(w, h, t):
			if layout.wall[n] != 0 or reserved[n] != 0 or lake.has(n) or not shores.has(terrain[n]):
				continue
			var z := layout.zone_of[n]
			if _home(n, z):
				continue
			if rng.chance(chance):
				var to := String(shores[terrain[n]])
				terrain[n] = to
				if symmetric:
					var m := layout.mirror_index(n)
					if layout.wall[m] == 0 and _passable_terrain(terrain[m]) and not lake.has(m):
						terrain[m] = to


## Passable tiles of zone z reachable from its anchor (4-connected).
func _reach(z: int) -> int:
	var open := PackedByteArray()
	open.resize(w * h)
	for i in layout.open_tiles(z):
		if _passable_terrain(terrain[i]):
			open[i] = 1
	var src := anchors[z] if anchors.size() > z and anchors[z] >= 0 else layout.open_tiles(z)[0]
	return GridSearch.count(GridSearch.flood(w, h, open, PackedInt32Array([src])))


## Large impassable set pieces (terrain_painting.json "landmarks"). The
## footprint turns into mountain; zones must stay connected.
func _place_landmarks() -> void:
	landmarks = []
	var lcfg: Dictionary = cfg.get("landmarks", {})
	var lib := scenery_library()
	if lcfg.is_empty() or lib.is_empty():
		return
	var used := {}
	var done := {}
	var profiles: Array = lcfg.get("profiles", [])
	for z in zones.size():
		if done.has(z) or landmarks.size() >= int(lcfg.get("max", 0)):
			continue
		done[z] = true
		var mz := -1
		if symmetric and anchors.size() > z:
			mz = layout.zone_of[layout.mirror_index(anchors[z])]
			done[mz] = true
		if not profiles.has(String(zones[z].get("profile", ""))) or not rng.chance(float(lcfg.get("chance", 0.0))):
			continue
		var options: Array = []
		for key in [String(zones[z]["biome"]), "any"]:
			for id in lcfg.get("biomes", {}).get(key, []):
				if lib.has(String(id)) and not used.has(String(id)):
					options.append(String(id))
		if options.is_empty():
			continue
		var kind := String(options[rng.next_int(0, options.size() - 1)])
		var fp: Array = lib[kind].get("footprint", [1, 1])
		for _try in 40:
			if _try_landmark(z, mz, kind, int(fp[0]), int(fp[1])):
				used[kind] = true
				break


func _try_landmark(z: int, mz: int, kind: String, fw: int, fh: int) -> bool:
	var tiles := layout.open_tiles(z)
	var start := layout.pos(tiles[rng.next_int(0, tiles.size() - 1)])
	var blob := PackedInt32Array()
	for dy in fh:
		for dx in fw:
			var q := start + Vector2i(dx, dy)
			if q.x >= w or q.y >= h:
				return false
			var i := layout.idx(q)
			if not _lake_ok(i, z) or _home(i, z):
				return false
			blob.append(i)
	var all := blob.duplicate()
	var twin := Vector2i(-1, -1)
	if mz >= 0 and mz != z:
		for t in blob:
			var m := layout.mirror_index(t)
			if not _lake_ok(m, mz):
				return false
			all.append(m)
		twin = layout.pos(layout.mirror_index(layout.idx(start + Vector2i(fw - 1, fh - 1))))
	var zs: Array[int] = [z]
	if mz >= 0 and mz != z:
		zs.append(mz)
	var before := {}
	for zz in zs:
		before[zz] = _reach(zz)
	var old := PackedStringArray()
	for t in all:
		old.append(terrain[t])
		terrain[t] = "mountain"
	for zz in zs:
		var lost := 0
		for t in all:
			if layout.zone_of[t] == zz:
				lost += 1
		if _reach(zz) != int(before[zz]) - lost:
			for j in all.size():
				terrain[all[j]] = old[j]
			return false
	landmarks.append({"pos": [start.x, start.y], "kind": kind, "footprint": [fw, fh]})
	if twin.x >= 0:
		landmarks.append({"pos": [twin.x, twin.y], "kind": kind, "footprint": [fw, fh]})
	return true


## The map scenery library (assets/map_scenery/manifest.json "assets"): id ->
## {category, footprint, biome, texture, anchor, ...}; {} when it is missing.
static func scenery_library() -> Dictionary:
	if _scenery_cache.is_empty() and FileAccess.file_exists(SCENERY_MANIFEST):
		var parsed: Variant = GameData.read_json(SCENERY_MANIFEST)
		if parsed is Dictionary:
			_scenery_cache = parsed.get("assets", {})
	return _scenery_cache


# -------------------------------------------------------------- decoration --

## Everything cosmetic for a map definition, in place: single-tile scenery
## pieces (appended to def.scenery), decorations, ground-variant patches
## (def.surface) and the painted flag.
static func dress(def: Dictionary, game_data: GameData, seed_number: int) -> void:
	var scenery: Array = (def.get("scenery", []) as Array).duplicate(true)
	scenery.append_array(place_scenery(def, game_data, seed_number))
	if not scenery.is_empty():
		def["scenery"] = scenery
	def["decorations"] = decorate(def, game_data, seed_number)
	var surface := paint_surface(def, game_data, seed_number)
	if not surface.is_empty():
		def["surface"] = surface
	def["decor"] = DECOR_MODE


## Tiles taken by the definition's scenery footprints.
static func _scenery_tiles(def: Dictionary) -> Dictionary:
	var out := {}
	for e in def.get("scenery", []):
		var fp: Array = e.get("footprint", [1, 1])
		for dy in int(fp[1]):
			for dx in int(fp[0]):
				out[Vector2i(int(e["pos"][0]) + dx, int(e["pos"][1]) + dy)] = true
	return out


## Single-tile scenery pieces per biome (terrain_painting.json "scenery").
static func place_scenery(def: Dictionary, game_data: GameData, seed_number: int) -> Array:
	var scfg: Dictionary = game_data.terrain_painting.get("scenery", {})
	var lib := scenery_library()
	var out: Array = []
	if scfg.is_empty() or lib.is_empty():
		return out
	var mw := int(def["width"])
	var mh := int(def["height"])
	var map := AdventureMap.from_definition(def, game_data)
	var srng := GameRng.new(GameRng.mix(seed_number, 0x5CE7))
	var dcfg: Dictionary = game_data.terrain_painting.get("decoration", {})
	var blocked := _object_mask(def, map, int(dcfg.get("town_clearing", 2)), int(dcfg.get("object_margin", 1)))
	var taken := _scenery_tiles(def)
	var spacing := int(scfg.get("spacing", 4))
	var biomes: Dictionary = scfg.get("biomes", {})
	var keys: Array = biomes.keys()
	keys.sort()
	for b in keys:
		var cands := PackedInt32Array()
		for i in mw * mh:
			if map.terrain[i] == b and map.road[i] == 0 and blocked[i] == 0 and not taken.has(Vector2i(i % mw, i / mw)):
				cands.append(i)
		var n := int(round(float(cands.size()) / maxf(1.0, float(scfg.get("per_tiles", 200)))))
		var pool: Dictionary = biomes[b]
		var ids: Array = []
		var ws: Array = []
		var pkeys: Array = pool.keys()
		pkeys.sort()
		for id in pkeys:
			if lib.has(String(id)):
				ids.append(String(id))
				ws.append(float(pool[id]))
		if ids.is_empty():
			continue
		var placed := 0
		for _try in n * 25:
			if placed >= n or cands.is_empty():
				break
			var i := cands[srng.next_int(0, cands.size() - 1)]
			var p := Vector2i(i % mw, i / mw)
			var near := false
			for e in out:
				if maxi(absi(int(e["pos"][0]) - p.x), absi(int(e["pos"][1]) - p.y)) < spacing:
					near = true
					break
			if near:
				continue
			out.append({"pos": [p.x, p.y], "kind": String(ids[srng.weighted_index(ws)]), "footprint": [1, 1]})
			placed += 1
	return out


## Cosmetic ground variants (terrain_painting.json "surfaces") as
## {kinds: [ids], rows: [".aab.."]} (row char = "a" + kind index), or {}.
static func paint_surface(def: Dictionary, game_data: GameData, seed_number: int) -> Dictionary:
	var scfg: Dictionary = game_data.terrain_painting.get("surfaces", {})
	var per: Dictionary = scfg.get("kinds", {})
	var lib := scenery_library()
	if per.is_empty() or lib.is_empty():
		return {}
	var mw := int(def["width"])
	var mh := int(def["height"])
	var map := AdventureMap.from_definition(def, game_data)
	var srng := GameRng.new(GameRng.mix(seed_number, 0x50F7))
	var noise := _Noise.new(mw, mh, int(scfg.get("cell", 7)), srng)
	var kinds: Array = []
	var grid := PackedByteArray()
	grid.resize(mw * mh)
	var tids: Array = per.keys()
	tids.sort()
	for tid in tids:
		var kind := String(per[tid].get("kind", ""))
		if not lib.has(kind):
			continue
		var tiles := PackedInt32Array()
		var vals := PackedFloat32Array()
		var offset := Vector2(17.0, 29.0) * float(kinds.size() + 1)
		for i in mw * mh:
			if map.terrain[i] == tid:
				tiles.append(i)
				vals.append(noise.fbm(Vector2(i % mw, i / mw) + offset))
		var target := int(round(tiles.size() * float(per[tid].get("coverage", 0.0))))
		if target <= 0:
			continue
		var sorted := vals.duplicate()
		sorted.sort()
		var threshold := sorted[maxi(0, sorted.size() - target)]
		if not kinds.has(kind):
			kinds.append(kind)
		var code := kinds.find(kind) + 1
		for j in tiles.size():
			if vals[j] >= threshold:
				grid[tiles[j]] = code
	if kinds.is_empty():
		return {}
	var rows: Array = []
	for y in mh:
		var row := ""
		for x in mw:
			var c := grid[y * mw + x]
			row += "." if c == 0 else String.chr(96 + c)
		rows.append(row)
	return {"kinds": kinds, "rows": rows}


static func _object_mask(def: Dictionary, map: AdventureMap, town_r: int, margin: int) -> PackedByteArray:
	var mw := map.width
	var mh := map.height
	var blocked := PackedByteArray()
	blocked.resize(mw * mh)
	for id in map.objects:
		var o: Dictionary = map.objects[id]
		var r := town_r if String(o.get("type", "")) == "town" else margin
		_block(blocked, AdventureMap.object_pos(o), r, mw, mh)
	for hero in def.get("heroes", []):
		_block(blocked, Vector2i(int(hero["pos"][0]), int(hero["pos"][1])), margin, mw, mh)
	return blocked


## Decorations for a map definition: the definition's own (authored) entries
## first, then painted ones {pos, kind, variant} on undecorated land.
static func decorate(def: Dictionary, game_data: GameData, seed_number: int) -> Array:
	var dcfg: Dictionary = game_data.terrain_painting.get("decoration", {})
	var result: Array = (def.get("decorations", []) as Array).duplicate(true)
	var biomes: Dictionary = dcfg.get("biomes", {})
	if biomes.is_empty():
		return result
	var mw := int(def["width"])
	var mh := int(def["height"])
	var map := AdventureMap.from_definition(def, game_data)
	var drng := GameRng.new(GameRng.mix(seed_number, 0xDEC0))
	var cluster := _Noise.new(mw, mh, int(dcfg.get("cluster_cell", 5)), drng)
	var blocked := _object_mask(def, map, int(dcfg.get("town_clearing", 2)), int(dcfg.get("object_margin", 1)))
	for p in _scenery_tiles(def):
		if map.in_bounds(p):
			blocked[p.y * mw + p.x] = 1
	var clearing := float(dcfg.get("clearing", -1.0))
	var border_mix := float(dcfg.get("border_mix", 0.0))
	var grove := float(dcfg.get("grove", 0.0))
	var variants := maxi(1, int(dcfg.get("variants", 1)))
	var placed := {}   # Vector2i -> [kind, variant]
	for p in map.decorations:
		placed[p] = [map.decorations[p], -1]
	var pools := {}
	for b in biomes:
		var pool: Dictionary = biomes[b].get("pool", {})
		var keys: Array = pool.keys()
		keys.sort()
		var ws: Array = []
		for k in keys:
			ws.append(float(pool[k]))
		pools[b] = [keys, ws]
	for y in mh:
		for x in mw:
			var p := Vector2i(x, y)
			var i := y * mw + x
			var tid := map.terrain[i]
			if placed.has(p) or not biomes.has(tid) or map.road[i] == 1 or blocked[i] == 1:
				continue
			var v := cluster.fbm(Vector2(p))
			if v < clearing:
				continue
			# Dense clusters, thin scatter between them (mean factor about 1).
			var t := clampf((v - clearing) / (1.0 - clearing), 0.0, 1.0)
			var shape := 0.2 + 2.6 * t * t
			if drng.next_float() >= float(biomes[tid].get("density", 0.0)) * shape:
				continue
			var biome := tid
			if border_mix > 0.0 and drng.chance(border_mix):
				for d in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)]:
					var q: Vector2i = p + d
					if map.in_bounds(q) and biomes.has(map.terrain_at(q)) and map.terrain_at(q) != tid:
						biome = map.terrain_at(q)
						break
			var keys: Array = pools[biome][0]
			if keys.is_empty():
				continue
			var kind := String(keys[drng.weighted_index(pools[biome][1])])
			if grove > 0.0 and drng.chance(grove):
				for d in [Vector2i(-1, 0), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if placed.has(q) and keys.has(placed[q][0]):
						kind = String(placed[q][0])
						break
			# No neighbour may show the same sprite (kind and variant).
			var taken := {}
			for d in NEIGHBORS8:
				var q: Vector2i = p + d
				if placed.has(q) and String(placed[q][0]) == kind:
					taken[int(placed[q][1])] = true
			var free: Array[int] = []
			for vi in variants:
				if not taken.has(vi):
					free.append(vi)
			if free.is_empty():
				continue
			var variant: int = free[drng.next_int(0, free.size() - 1)]
			placed[p] = [kind, variant]
			result.append({"pos": [x, y], "kind": kind, "variant": variant})
	return result


static func _block(mask: PackedByteArray, c: Vector2i, r: int, mw: int, mh: int) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := c + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < mw and q.y < mh:
				mask[q.y * mw + q.x] = 1


# ------------------------------------------------------------------ stats --

## Variety measures for quality reports. `decorations` defaults to the map's
## own list; pass a simulated list to measure the map view's fallback.
## land_biomes: distinct passable non-river terrains; dominant_share: share of
## the most common one; mixed_share: land tiles whose 5x5 window holds 2+ land
## biomes; mean_patch: land tiles per 4-connected one-terrain patch (small =
## speckled, large = uniform); deco_density: decorated land tiles / land tiles; kind_entropy:
## normalised Shannon entropy of decoration kinds; same_kind_neighbors and
## identical_neighbors: share of decorations with an 8-neighbour of the same
## kind / the same kind and variant.
static func terrain_stats(def: Dictionary, game_data: GameData, decorations: Variant = null) -> Dictionary:
	var mw := int(def["width"])
	var mh := int(def["height"])
	var rows: Array = def["terrain"]
	var grid := PackedStringArray()
	grid.resize(mw * mh)
	for y in mh:
		for x in mw:
			grid[y * mw + x] = String(game_data.terrain_by_char[String(rows[y])[x]])
	var land := func(t: String) -> bool: return t != "river" and bool(game_data.terrain(t).get("passable", false))
	var counts := {}
	var land_tiles := 0
	var mixed := 0
	for y in mh:
		for x in mw:
			var t := grid[y * mw + x]
			if not land.call(t):
				continue
			land_tiles += 1
			counts[t] = int(counts.get(t, 0)) + 1
			var other := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var qx := x + dx
					var qy := y + dy
					if qx < 0 or qy < 0 or qx >= mw or qy >= mh:
						continue
					var u := grid[qy * mw + qx]
					if u != t and land.call(u):
						other = true
			if other:
				mixed += 1
	# Patches: 4-connected components of one land terrain.
	var seen := PackedByteArray()
	seen.resize(mw * mh)
	var patches := 0
	for start in mw * mh:
		if seen[start] == 1 or not land.call(grid[start]):
			continue
		patches += 1
		var stack := PackedInt32Array([start])
		seen[start] = 1
		while not stack.is_empty():
			var cur := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			for n in GridSearch.neighbors4(mw, mh, cur):
				if seen[n] == 0 and grid[n] == grid[start]:
					seen[n] = 1
					stack.append(n)
	var dominant := 0
	for t in counts:
		dominant = maxi(dominant, int(counts[t]))
	var decos: Array = def.get("decorations", []) if decorations == null else decorations
	var at := {}
	var kinds := {}
	var on_land := 0
	for d in decos:
		var p := Vector2i(int(d["pos"][0]), int(d["pos"][1]))
		at[p] = [String(d["kind"]), int(d.get("variant", -1))]
		kinds[String(d["kind"])] = int(kinds.get(String(d["kind"]), 0)) + 1
		if p.x >= 0 and p.y >= 0 and p.x < mw and p.y < mh and land.call(grid[p.y * mw + p.x]):
			on_land += 1
	var same_kind := 0
	var identical := 0
	for p in at:
		var s := false
		var ident := false
		for d in NEIGHBORS8:
			var q: Vector2i = p + d
			if at.has(q) and at[q][0] == at[p][0]:
				s = true
				ident = ident or (at[q][1] == at[p][1])
		same_kind += 1 if s else 0
		identical += 1 if ident else 0
	var entropy := 0.0
	var total := float(decos.size())
	for k in kinds:
		var pk := float(kinds[k]) / total
		entropy -= pk * log(pk)
	var max_entropy := log(float(maxi(2, kinds.size())))
	return {
		"land_biomes": counts.size(),
		"dominant_share": float(dominant) / maxf(1.0, land_tiles),
		"mixed_share": float(mixed) / maxf(1.0, land_tiles),
		"mean_patch": float(land_tiles) / maxf(1.0, patches),
		"deco_density": float(on_land) / maxf(1.0, land_tiles),
		"deco_kinds": kinds.size(),
		"kind_entropy": entropy / max_entropy if total > 0.0 else 0.0,
		"same_kind_neighbors": float(same_kind) / maxf(1.0, total),
		"identical_neighbors": float(identical) / maxf(1.0, total),
	}


# ------------------------------------------------------------- validation --

## Problems in data/terrain_painting.json. Called from GameData.validate().
static func validate_config(game_data: GameData, atlas_kinds: Array = [], atlas_variants: int = 0) -> Array[String]:
	var errors: Array[String] = []
	var c: Dictionary = game_data.terrain_painting
	if c.is_empty():
		return errors
	var land := func(t: String) -> bool:
		return game_data.terrains.has(t) and t != "river" and bool(game_data.terrains[t].get("passable", false))
	for base in c.get("affinity", {}):
		if not land.call(String(base)):
			errors.append("terrain_painting: affinity for non-land terrain %s" % base)
		for t in c["affinity"][base]:
			if not land.call(String(t)):
				errors.append("terrain_painting: %s affinity names non-land terrain %s" % [base, t])
			elif float(c["affinity"][base][t]) <= 0.0:
				errors.append("terrain_painting: %s affinity for %s must be positive" % [base, t])
	for base in c.get("shores", {}):
		if not land.call(String(base)) or not land.call(String(c["shores"][base])):
			errors.append("terrain_painting: shore %s -> %s must join land terrains" % [base, c["shores"][base]])
	var pairs := {"secondaries": [0, 2], "coverage": [0.0, 0.6], "lakes": [0, 6], "lake_size": [3, 40]}
	for pid in c.get("profiles", {}):
		var p: Dictionary = c["profiles"][pid]
		if pid != "default" and not game_data.map_templates.get("profiles", {}).has(pid):
			errors.append("terrain_painting: profile %s is not a map template profile" % pid)
		for key in pairs:
			if not p.has(key):
				if pid == "default":
					errors.append("terrain_painting: default profile needs %s" % key)
				continue
			var span: Variant = p[key]
			if not span is Array or (span as Array).size() != 2 or float(span[0]) > float(span[1]) \
					or float(span[0]) < float(pairs[key][0]) or float(span[1]) > float(pairs[key][1]):
				errors.append("terrain_painting: profile %s %s must be [min, max] within %s" % [pid, key, pairs[key]])
		var rc := float(p.get("river_chance", 0.0))
		if rc < 0.0 or rc > 1.0:
			errors.append("terrain_painting: profile %s river_chance must be 0-1" % pid)
	var dcfg: Dictionary = c.get("decoration", {})
	if atlas_variants > 0 and int(dcfg.get("variants", 0)) != atlas_variants:
		errors.append("terrain_painting: decoration variants %d, atlas has %d" % [int(dcfg.get("variants", 0)), atlas_variants])
	for b in dcfg.get("biomes", {}):
		var e: Dictionary = dcfg["biomes"][b]
		if not land.call(String(b)):
			errors.append("terrain_painting: decoration for non-land terrain %s" % b)
		var dens := float(e.get("density", -1.0))
		if dens < 0.0 or dens > 1.0:
			errors.append("terrain_painting: %s decoration density must be 0-1" % b)
		var pool: Dictionary = e.get("pool", {})
		if pool.is_empty():
			errors.append("terrain_painting: %s decoration pool is empty" % b)
		for k in pool:
			if float(pool[k]) <= 0.0:
				errors.append("terrain_painting: %s pool weight for %s must be positive" % [b, k])
			if not atlas_kinds.is_empty() and not atlas_kinds.has(String(k)):
				errors.append("terrain_painting: %s pool names %s, which the decoration atlas lacks" % [b, k])
	errors.append_array(_validate_scenery(c, land, scenery_library()))
	return errors


## Surfaces, scenery and landmarks must name map scenery assets of the right category.
static func _validate_scenery(c: Dictionary, land: Callable, lib: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var check := func(id: String, category: String, where: String) -> void:
		if lib.is_empty():
			return
		if not lib.has(id):
			errors.append("terrain_painting: %s names %s, which the map scenery library lacks" % [where, id])
		elif String(lib[id].get("category", "")) != category:
			errors.append("terrain_painting: %s needs a %s asset, %s is %s" % [where, category, id, lib[id].get("category", "")])
	var surfaces: Dictionary = c.get("surfaces", {}).get("kinds", {})
	for t in surfaces:
		if not land.call(String(t)):
			errors.append("terrain_painting: surface for non-land terrain %s" % t)
		check.call(String(surfaces[t].get("kind", "")), "terrain", "surface " + String(t))
		var cov := float(surfaces[t].get("coverage", -1.0))
		if cov < 0.0 or cov > 0.8:
			errors.append("terrain_painting: surface %s coverage must be 0-0.8" % t)
	var sb: Dictionary = c.get("scenery", {}).get("biomes", {})
	for b in sb:
		if not land.call(String(b)):
			errors.append("terrain_painting: scenery for non-land terrain %s" % b)
		for id in sb[b]:
			check.call(String(id), "decoration", "scenery " + String(b))
			if float(sb[b][id]) <= 0.0:
				errors.append("terrain_painting: scenery weight for %s must be positive" % id)
	var lb: Dictionary = c.get("landmarks", {}).get("biomes", {})
	for b in lb:
		if b != "any" and not land.call(String(b)):
			errors.append("terrain_painting: landmarks for non-land terrain %s" % b)
		for id in lb[b]:
			check.call(String(id), "landmark", "landmarks " + String(b))
	return errors


## Smooth value noise in [-1, 1] on a coarse lattice; fbm adds a finer octave.
## The lattice covers twice the map so scaled lookups stay in range.
class _Noise:
	var cell: float
	var cols: int
	var rows: int
	var values := PackedFloat32Array()

	func _init(mw: int, mh: int, cell_size: int, r: GameRng) -> void:
		cell = float(maxi(1, cell_size))
		cols = int(2.0 * mw / cell) + 3
		rows = int(2.0 * mh / cell) + 3
		values.resize(cols * rows)
		for i in values.size():
			values[i] = r.next_float_range(-1.0, 1.0)

	func at(p: Vector2) -> float:
		var fx := clampf(p.x / cell, 0.0, cols - 1.001)
		var fy := clampf(p.y / cell, 0.0, rows - 1.001)
		var x0 := int(floor(fx))
		var y0 := int(floor(fy))
		var tx := smoothstep(0.0, 1.0, fx - x0)
		var ty := smoothstep(0.0, 1.0, fy - y0)
		var v00 := values[y0 * cols + x0]
		var v10 := values[y0 * cols + x0 + 1]
		var v01 := values[(y0 + 1) * cols + x0]
		var v11 := values[(y0 + 1) * cols + x0 + 1]
		return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)

	func fbm(p: Vector2) -> float:
		return 0.7 * at(p) + 0.3 * at(p * 2.3 + Vector2(cell * 0.37, cell * 0.61))
