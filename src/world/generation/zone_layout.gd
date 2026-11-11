class_name ZoneLayout
extends RefCounted
## Splits the map into template zones and walls them off from each other.
##
## 1. Every zone gets a seed point (its anchor plus a little jitter).
## 2. Tiles go to the zone with the lowest power-diagram score
##    (|p - seed|^2 - size bias), sampled through a smooth warp field so that
##    borders are organic instead of straight.
## 3. Stray fragments are merged into a neighbouring zone.
## 4. Every zone tile that touches a lower-numbered zone becomes a wall, which
##    gives one-tile borders that no 4- or diagonal step can cross.
## 5. Each template connection carves a pass of `width` tiles through the wall
##    near the midpoint between the two zones: these are the chokepoints.
##
## 6. Optional `walls` {water, thick: [lo, hi]}: every border between two zones
##    is mountain or lake (chance `water`), and walls grow by lo-hi tiles on
##    each side along a noise field, so borders become ridges and lakes of
##    varying thickness. The ground around every pass stays open.
##
## With symmetry "rotate180", seeds and the warp field are point-symmetric, so
## mirrored zones get mirrored shapes.

const WALL_ROCK := 0
const WALL_WATER := 1

var width: int = 0
var height: int = 0
var zone_ids: Array[String] = []
var zone_index: Dictionary = {}          # zone id -> index
var seeds: Array[Vector2] = []
var zone_of := PackedInt32Array()        # tile -> zone index
var wall := PackedByteArray()            # tile -> 1 if border wall
var wall_kind := PackedByteArray()       # tile -> WALL_ROCK or WALL_WATER (walls only)
var gates: Array = []                    # per connection: {a, b, tiles: PackedInt32Array, center: int}
var errors: Array[String] = []


func build(template: Dictionary, rng: GameRng) -> bool:
	width = int(template["width"])
	height = int(template["height"])
	var zones: Array = template["zones"]
	for i in zones.size():
		zone_ids.append(String(zones[i]["id"]))
		zone_index[zone_ids[i]] = i
	var symmetric := String(template.get("symmetry", "none")) == "rotate180"
	_place_seeds(zones, float(template.get("jitter", 0.0)), symmetric, rng)
	_partition(zones, float(template.get("warp", 0.0)), symmetric, rng)
	_merge_fragments()
	_build_walls()
	_drop_cut_off_pockets()
	if template.get("graph", "fixed") == "spatial":
		template["connections"] = MapTopology.select(self, template, rng)
	for c in template["connections"]:
		_carve_gate(int(zone_index[c["a"]]), int(zone_index[c["b"]]), int(c.get("width", 1)))
	wall_kind.resize(width * height)
	var walls: Dictionary = template.get("walls", {})
	if not walls.is_empty() and errors.is_empty():
		_dress_walls(zones, walls, symmetric, rng)
	return errors.is_empty()


func idx(p: Vector2i) -> int:
	return p.y * width + p.x


func pos(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)


func mirror_index(i: int) -> int:
	return width * height - 1 - i


## Tiles of a zone that are not walls (gate tiles count as their zone's tiles).
func open_tiles(zone: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in zone_of.size():
		if zone_of[i] == zone and wall[i] == 0:
			out.append(i)
	return out


# ------------------------------------------------------------------ steps --

func _place_seeds(zones: Array, jitter: float, symmetric: bool, rng: GameRng) -> void:
	var c := Vector2(width - 1, height - 1)
	for z in zones:
		var mirror := String(z.get("mirror", ""))
		if symmetric and mirror == "self":
			seeds.append(c * 0.5)
		elif symmetric and mirror != "":
			seeds.append(c - seeds[int(zone_index[mirror])])
		else:
			var a: Array = z["anchor"]
			var j := Vector2(rng.next_float_range(-jitter, jitter) * width, rng.next_float_range(-jitter, jitter) * height)
			seeds.append(Vector2(float(a[0]) * c.x, float(a[1]) * c.y) + j)


func _partition(zones: Array, warp: float, symmetric: bool, rng: GameRng) -> void:
	var noise_x := _ValueNoise.new(width, height, 7, rng)
	var noise_y := _ValueNoise.new(width, height, 7, rng)
	var unit := 0.12 * float(mini(width, height))
	zone_of.resize(width * height)
	for i in width * height:
		var p := Vector2(pos(i))
		var w := Vector2(noise_x.at(p), noise_y.at(p))
		if symmetric:
			var m := Vector2(pos(mirror_index(i)))
			w = (w - Vector2(noise_x.at(m), noise_y.at(m))) * 0.5
		var q := p + w * warp
		var best := 0
		var best_score := INF
		for z in zones.size():
			var bias := (float(zones[z].get("size", 1.0)) - 1.0) * unit * unit
			var score := q.distance_squared_to(seeds[z]) - bias
			if score < best_score - 0.0001:
				best_score = score
				best = z
		zone_of[i] = best


## Keeps the largest 4-connected piece of every zone and hands the other
## pieces to the zone they touch most.
func _merge_fragments() -> void:
	for _pass in 4:
		var changed := false
		for z in zone_ids.size():
			var open := PackedByteArray()
			open.resize(width * height)
			var members := PackedInt32Array()
			for i in zone_of.size():
				if zone_of[i] == z:
					open[i] = 1
					members.append(i)
			if members.is_empty():
				errors.append("zone %s is empty" % zone_ids[z])
				continue
			var seed_tile := idx(Vector2i(clampi(int(round(seeds[z].x)), 0, width - 1), clampi(int(round(seeds[z].y)), 0, height - 1)))
			var start := seed_tile if zone_of[seed_tile] == z else members[0]
			var main := GridSearch.flood(width, height, open, PackedInt32Array([start]))
			for i in members:
				if main[i] != 0:
					continue
				for n in GridSearch.neighbors4(width, height, i):
					if zone_of[n] != z:
						zone_of[i] = zone_of[n]
						changed = true
						break
		if not changed:
			return


func _build_walls() -> void:
	wall.resize(width * height)
	for i in zone_of.size():
		for n in GridSearch.neighbors4(width, height, i):
			if zone_of[n] < zone_of[i]:
				wall[i] = 1
				break


## Walls can pinch off a sliver of a zone; those slivers become walls too.
func _drop_cut_off_pockets() -> void:
	for z in zone_ids.size():
		var open := PackedByteArray()
		open.resize(width * height)
		var members := open_tiles(z)
		for i in members:
			open[i] = 1
		if members.is_empty():
			errors.append("zone %s has no open tiles" % zone_ids[z])
			continue
		# Largest component wins.
		var assigned := PackedByteArray()
		assigned.resize(width * height)
		var best_mask := PackedByteArray()
		var best_count := -1
		for i in members:
			if assigned[i] != 0:
				continue
			var comp := GridSearch.flood(width, height, open, PackedInt32Array([i]))
			var cnt := 0
			for j in members:
				if comp[j] != 0:
					assigned[j] = 1
					cnt += 1
			if cnt > best_count:
				best_count = cnt
				best_mask = comp
		for i in members:
			if best_mask[i] == 0:
				wall[i] = 1


func _carve_gate(a: int, b: int, gate_width: int) -> void:
	var mid := (seeds[a] + seeds[b]) * 0.5
	var candidates: Array[int] = []
	for i in zone_of.size():
		if wall[i] == 0 or (zone_of[i] != a and zone_of[i] != b):
			continue
		var other := b if zone_of[i] == a else a
		var touches_own := false
		var touches_other := false
		for n in GridSearch.neighbors4(width, height, i):
			if wall[n] != 0:
				continue
			if zone_of[n] == zone_of[i]:
				touches_own = true
			elif zone_of[n] == other:
				touches_other = true
		if touches_own and touches_other and not _is_gate(i):
			candidates.append(i)
	if candidates.is_empty():
		errors.append("zones %s and %s do not touch" % [zone_ids[a], zone_ids[b]])
		gates.append({"a": a, "b": b, "tiles": PackedInt32Array(), "center": -1})
		return
	var best := candidates[0]
	for i in candidates:
		if Vector2(pos(i)).distance_squared_to(mid) < Vector2(pos(best)).distance_squared_to(mid):
			best = i
	var tiles := PackedInt32Array([best])
	# Widen along the border: nearest other candidates within reach.
	while tiles.size() < gate_width:
		var next := -1
		for i in candidates:
			if tiles.has(i):
				continue
			var near := false
			for t in tiles:
				if absi(pos(i).x - pos(t).x) + absi(pos(i).y - pos(t).y) <= 2:
					near = true
			if near and (next < 0 or Vector2(pos(i)).distance_squared_to(Vector2(pos(best))) < Vector2(pos(next)).distance_squared_to(Vector2(pos(best)))):
				next = i
		if next < 0:
			break
		tiles.append(next)
	for t in tiles:
		wall[t] = 0
	gates.append({"a": a, "b": b, "tiles": tiles, "center": best})


## Picks rock or water per border and thickens the walls (see step 6).
func _dress_walls(zones: Array, cfg: Dictionary, symmetric: bool, rng: GameRng) -> void:
	var mirror_of := {}
	for z in zones.size():
		var m := String(zones[z].get("mirror", ""))
		if m == "self":
			mirror_of[z] = z
		elif m != "" and zone_index.has(m):
			mirror_of[z] = int(zone_index[m])
			mirror_of[int(zone_index[m])] = z
	# 1. One material per border (pair of zones); mirrored borders match.
	var pair_of := PackedInt32Array()
	pair_of.resize(width * height)
	pair_of.fill(-1)
	var pairs := {}
	var n_zones := zone_ids.size()
	for i in wall.size():
		if wall[i] == 0:
			continue
		var own := zone_of[i]
		var other := own
		for n in GridSearch.neighbors4(width, height, i):
			if zone_of[n] < other:
				other = zone_of[n]
		if other == own:
			for n in GridSearch.neighbors4(width, height, i):
				if zone_of[n] != own:
					other = zone_of[n]
					break
		var key := mini(own, other) * n_zones + maxi(own, other)
		pair_of[i] = key
		pairs[key] = true
	var keys := pairs.keys()
	keys.sort()
	var water := float(cfg.get("water", 0.0))
	var kind_of := {}
	for key in keys:
		if kind_of.has(key):
			continue
		var kind := WALL_WATER if rng.chance(water) else WALL_ROCK
		kind_of[key] = kind
		if symmetric:
			var a := int(key) / n_zones
			var b := int(key) % n_zones
			if mirror_of.has(a) and mirror_of.has(b):
				var ma := int(mirror_of[a])
				var mb := int(mirror_of[b])
				kind_of[mini(ma, mb) * n_zones + maxi(ma, mb)] = kind
	for i in wall.size():
		if wall[i] != 0 and pair_of[i] >= 0:
			wall_kind[i] = int(kind_of[pair_of[i]])
	# 2. Thicken along a noise field, keeping the ground around passes open.
	var thick: Array = cfg.get("thick", [0, 0])
	var lo := int(thick[0])
	var hi := int(thick[1])
	if hi <= 0:
		return
	var ones := PackedInt32Array()
	ones.resize(width * height)
	ones.fill(1)
	var gate_tiles := PackedInt32Array()
	for g in gates:
		gate_tiles.append_array(g["tiles"])
	var near_gate := GridSearch.distances(width, height, ones, gate_tiles, hi + 3)
	var noise := _ValueNoise.new(width, height, 6, rng)
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	var src_kind := PackedByteArray()
	src_kind.resize(width * height)
	var queue := PackedInt32Array()
	for i in wall.size():
		if wall[i] != 0:
			dist[i] = 0
			src_kind[i] = wall_kind[i]
			queue.append(i)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		if dist[cur] >= hi:
			continue
		for n in GridSearch.neighbors4(width, height, cur):
			if dist[n] < 0:
				dist[n] = dist[cur] + 1
				src_kind[n] = src_kind[cur]
				queue.append(n)
	for i in wall.size():
		if wall[i] != 0 or dist[i] <= 0 or (near_gate[i] >= 0):
			continue
		var v := noise.at(Vector2(pos(i)))
		if symmetric:
			v = (v + noise.at(Vector2(pos(mirror_index(i))))) * 0.5
		var t := lo + int(floor((v + 1.0) * 0.5 * float(hi - lo + 1)))
		if dist[i] <= mini(t, hi):
			wall[i] = 1
			wall_kind[i] = src_kind[i]
	_drop_cut_off_pockets()
	for g in gates:
		for t in g["tiles"]:
			if wall[t] != 0:
				errors.append("the pass between %s and %s was walled in" % [zone_ids[int(g["a"])], zone_ids[int(g["b"])]])
				return


func _is_gate(i: int) -> bool:
	for g in gates:
		if (g["tiles"] as PackedInt32Array).has(i):
			return true
	return false


## Smooth value noise in [-1, 1] on a coarse lattice, bilinearly interpolated.
class _ValueNoise:
	var cell: int
	var cols: int
	var values := PackedFloat32Array()

	func _init(w: int, h: int, cell_size: int, rng: GameRng) -> void:
		cell = cell_size
		cols = w / cell_size + 2
		var rows := h / cell_size + 2
		values.resize(cols * rows)
		for i in values.size():
			values[i] = rng.next_float_range(-1.0, 1.0)

	func at(p: Vector2) -> float:
		var fx := p.x / cell
		var fy := p.y / cell
		var x0 := int(floor(fx))
		var y0 := int(floor(fy))
		var tx := fx - x0
		var ty := fy - y0
		var v00 := values[y0 * cols + x0]
		var v10 := values[y0 * cols + x0 + 1]
		var v01 := values[(y0 + 1) * cols + x0]
		var v11 := values[(y0 + 1) * cols + x0 + 1]
		return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)
