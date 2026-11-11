class_name TerrainTiles
extends RefCounted
## Builds the adventure-map TileSet from the terrain atlas and computes
## which transition / road / fog tile each cell needs. The mask maths is
## static and pure so it is unit-tested headless; it mirrors
## tools/assets/crowns_of_cinder_assets/procedural.py (reduce_mask, all_transition_masks).

const SOURCE_TERRAIN := 0
const SOURCE_DECO := 1
const SOURCE_EDGES := 2

# Neighbour bits, clockwise from north.
const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128
const DIRS := [
	[N, Vector2i(0, -1)], [NE, Vector2i(1, -1)], [E, Vector2i(1, 0)], [SE, Vector2i(1, 1)],
	[S, Vector2i(0, 1)], [SW, Vector2i(-1, 1)], [W, Vector2i(-1, 0)], [NW, Vector2i(-1, -1)],
]
# Road connections (4-neighbour).
const RN := 1
const RE := 2
const RS := 4
const RW := 8

var info: Dictionary
var tile_set: TileSet
var highres_tile_set: TileSet
var _mask_column: Dictionary = {}   # reduced mask -> atlas column
var _specific_pairs: Dictionary = {} # directed terrain pair keys


func _init(terrain_info: Dictionary) -> void:
	info = terrain_info
	var masks: Array = info.get("transition_masks", [])
	for i in masks.size():
		_mask_column[int(masks[i])] = int(info["transition_column"]) + i
	tile_set = _build_tile_set()
	highres_tile_set = _build_highres_tile_set()
	if tile_set != null and tile_set.has_source(SOURCE_EDGES):
		for entry in info.get("edges", {}).get("types", {}).values():
			var base := String(entry["base"])
			for neighbor in entry["neighbors"]:
				_specific_pairs[base + ":" + String(neighbor)] = true
				_specific_pairs[String(neighbor) + ":" + base] = true


func is_valid() -> bool:
	return tile_set != null


## 8-bit neighbour mask of cells where `pred(cell)` is true.
static func neighbor_bits(pred: Callable, t: Vector2i) -> int:
	var bits := 0
	for d in DIRS:
		if pred.call(t + d[1]):
			bits |= int(d[0])
	return bits


## Corners only count when neither adjacent edge does (the edge fringe
## already covers that corner). 256 inputs collapse to 47 masks.
static func reduce_mask(bits: int) -> int:
	var m := bits & (N | E | S | W)
	for c in [[NE, N, E], [SE, S, E], [SW, S, W], [NW, N, W]]:
		if bits & c[0] and not bits & c[1] and not bits & c[2]:
			m |= c[0]
	return m


static func road_mask(has_road: Callable, t: Vector2i) -> int:
	var m := 0
	if has_road.call(t + Vector2i(0, -1)): m |= RN
	if has_road.call(t + Vector2i(1, 0)): m |= RE
	if has_road.call(t + Vector2i(0, 1)): m |= RS
	if has_road.call(t + Vector2i(-1, 0)): m |= RW
	return m


## Stable per-cell hash in [0, n) for variant picking (no RNG: purely visual).
static func cell_hash(t: Vector2i, n: int, salt: int = 0) -> int:
	var h := (t.x * 374761393 + t.y * 668265263 + salt * 1442695041) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return (h ^ (h >> 16)) % maxi(n, 1)


func terrain_row(terrain_id: String) -> int:
	return int(info["terrains"].get(terrain_id, {}).get("row", -1))


func priority(terrain_id: String) -> int:
	return int(info["terrains"].get(terrain_id, {}).get("priority", -1))


func ground_coords(terrain_id: String, t: Vector2i) -> Vector2i:
	var terrain: Dictionary = info["terrains"].get(terrain_id, {})
	if terrain.has("field"):
		var field: Dictionary = terrain["field"]
		var cells: Array = field["cells"]
		var x := posmod(t.x, int(cells[0]))
		var y := posmod(t.y, int(cells[1]))
		return Vector2i(int(field["column"]) + y * int(cells[0]) + x, terrain_row(terrain_id))
	return Vector2i(cell_hash(t, int(info["variants"])), terrain_row(terrain_id))


## Sparse small-scale surface details; never affects the terrain or game rules.
func detail_coords(terrain_id: String, t: Vector2i) -> Vector2i:
	var count := int(info.get("detail_variants", 0))
	if count <= 0 or cell_hash(t, 100, 29) >= 60:
		return Vector2i(-1, -1)
	return Vector2i(int(info["detail_column"]) + cell_hash(t, count, 31), terrain_row(terrain_id))


## Pair-specific edges follow all eight neighbors. World-coordinate phases
## continue across tiles, with a gradual shift between different shorelines.
func edge_coords(terrain_id: String, kind: String, bits: int, t: Vector2i) -> Vector2i:
	var edges: Dictionary = info.get("edges", {})
	if bits == 0 or tile_set == null or not tile_set.has_source(SOURCE_EDGES):
		return Vector2i(-1, -1)
	var entry: Dictionary = edges.get("types", {}).get(kind, {})
	if entry.is_empty() or String(entry["base"]) != terrain_id:
		return Vector2i(-1, -1)
	var period := int(edges["period"])
	var px := posmod(t.x + floori(float(t.y) / 6.0), period)
	var py := posmod(t.y + floori(float(t.x) / 6.0), period)
	return Vector2i(int(entry["column"]) + py * period + px, bits & 255)


## A dedicated contour replaces the general diffuse blend on both sides.
func has_specific_edge(a: String, b: String) -> bool:
	return _specific_pairs.has(a + ":" + b)


## Atlas coords of the overlay for `reduced_mask` in `row`, or (-1, -1).
func transition_coords(row: int, reduced_mask: int, cell: Vector2i = Vector2i.ZERO) -> Vector2i:
	if reduced_mask == 0 or not _mask_column.has(reduced_mask):
		return Vector2i(-1, -1)
	var variant := cell_hash(cell, int(info.get("transition_variants", 1)), 23)
	return Vector2i(int(_mask_column[reduced_mask]) + variant * _mask_column.size(), row)


func fog_coords(t: Vector2i, unexplored_bits: int, explored: bool) -> Vector2i:
	var row := int(info["fog"]["row"])
	if not explored:
		var field: Dictionary = info["fog"].get("field", {})
		if not field.is_empty():
			var cells: Array = field["cells"]
			return Vector2i(int(field["column"]) + posmod(t.y, int(cells[1])) * int(cells[0]) + posmod(t.x, int(cells[0])), row)
		return Vector2i(cell_hash(t, int(info["variants"]), 7), row)
	# Fog has a single set of fringe tiles, independent of terrain variants.
	var mask := reduce_mask(unexplored_bits)
	return Vector2i(int(_mask_column[mask]), row) if mask != 0 and _mask_column.has(mask) else Vector2i(-1, -1)


func road_coords(mask: int, bridge: bool) -> Vector2i:
	var r: Dictionary = info["roads"]
	return Vector2i(int(r["bridge_column" if bridge else "road_column"]) + mask, int(r["row"]))


## JSON numbers may be floats; compare their integer values when looking up masks.
static func mask_index(masks: Array, mask: int) -> int:
	for i in masks.size():
		if int(masks[i]) == mask:
			return i
	return -1


## A painted road uses the same 8-neighbour connections as barrier art.
func themed_road_coords(style: String, t: Vector2i, bits: int) -> Vector2i:
	var entry: Dictionary = info.get("roads", {}).get("styles", {}).get(style, {})
	if entry.is_empty():
		return Vector2i(-1, -1)
	var masks: Array = entry["masks"]
	var index := mask_index(masks, reduce_mask(bits))
	if index < 0:
		return Vector2i(-1, -1)
	var variant := posmod(t.x, 2) + 2 * posmod(t.y, 2)
	return Vector2i(int(entry["column"]) + index + variant * masks.size(), int(entry["row"]))


## Deco atlas coords for a cell, or (-1, -1) when the cell stays bare.
func deco_coords(terrain_id: String, t: Vector2i) -> Vector2i:
	var d: Dictionary = info["terrains"].get(terrain_id, {}).get("deco", {})
	var kinds: Array = d.get("kinds", [])
	if kinds.is_empty():
		return Vector2i(-1, -1)
	if cell_hash(t, 1000, 3) >= int(float(d.get("chance", 0.0)) * 1000.0):
		return Vector2i(-1, -1)
	var kind: String = kinds[cell_hash(t, kinds.size(), 5)]
	var deco: Dictionary = info["deco"]
	return Vector2i(cell_hash(t, int(deco["variants"]), 11), int(deco["kinds"][kind]["row"]))


## Atlas coords of a decoration the map places itself; variant < 0 picks one by
## position (older maps and editor placements carry no variant).
func authored_deco_coords(kind: String, t: Vector2i, variant: int = -1) -> Vector2i:
	var deco: Dictionary = info.get("deco", {})
	if not deco.get("kinds", {}).has(kind):
		return Vector2i(-1, -1)
	var n := int(deco["variants"])
	var column := posmod(variant, n) if variant >= 0 else cell_hash(t, n, 11)
	return Vector2i(column, int(deco["kinds"][kind]["row"]))


## Coordinates in the compact double-resolution atlas, or fallback marker.
func highres_coords(kind: String, name: String, t: Vector2i, bits: int) -> Vector2i:
	if highres_tile_set == null:
		return Vector2i(-1, -1)
	var high: Dictionary = info.get("highres", {})
	var entry: Dictionary = high.get(kind, {}).get(name, {})
	if entry.is_empty():
		return Vector2i(-1, -1)
	var masks: Array = high.get("masks", [])
	var index := mask_index(masks, reduce_mask(bits))
	if index < 0:
		return Vector2i(-1, -1)
	return Vector2i(index, int(entry["row"]) + posmod(t.x, 2) + 2 * posmod(t.y, 2))


func _build_highres_tile_set() -> TileSet:
	var high: Dictionary = info.get("highres", {})
	var sheet := Art.texture_at(high.get("atlas", ""))
	if sheet == null:
		return null
	var size := int(high.get("tile_size", 0))
	if size <= 0:
		return null
	var ts := TileSet.new()
	ts.tile_size = Vector2i(size, size)
	var source := TileSetAtlasSource.new()
	source.texture = sheet
	source.texture_region_size = Vector2i(size, size)
	var grid := source.get_atlas_grid_size()
	for y in grid.y:
		for x in grid.x:
			source.create_tile(Vector2i(x, y))
	ts.add_source(source, SOURCE_TERRAIN)
	return ts


func _build_tile_set() -> TileSet:
	if info.is_empty():
		return null
	var sheet := Art.texture_at(info.get("atlas", ""))
	var deco_sheet := Art.texture_at(info.get("deco", {}).get("atlas", ""))
	if sheet == null or deco_sheet == null:
		return null
	var ts := TileSet.new()
	var t := int(info["tile_size"])
	ts.tile_size = Vector2i(t, t)
	var src := TileSetAtlasSource.new()
	src.texture = sheet
	src.texture_region_size = Vector2i(t, t)
	var grid := src.get_atlas_grid_size()
	for y in grid.y:
		for x in grid.x:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, SOURCE_TERRAIN)

	var cell: Array = info["deco"]["cell"]
	var dsrc := TileSetAtlasSource.new()
	dsrc.texture = deco_sheet
	dsrc.texture_region_size = Vector2i(cell[0], cell[1])
	var dgrid := dsrc.get_atlas_grid_size()
	# Deco sprites stand on the bottom of their cell and overhang upward.
	var lift := (int(cell[1]) - t) / 2
	for y in dgrid.y:
		for x in dgrid.x:
			dsrc.create_tile(Vector2i(x, y))
			var td := dsrc.get_tile_data(Vector2i(x, y), 0)
			td.texture_origin = Vector2i(0, lift)
			td.y_sort_origin = t / 2 - 1
	ts.add_source(dsrc, SOURCE_DECO)
	var edge_sheet := Art.texture_at(info.get("edges", {}).get("atlas", ""))
	if edge_sheet != null:
		var esrc := TileSetAtlasSource.new()
		esrc.texture = edge_sheet
		esrc.texture_region_size = Vector2i(t, t)
		var egrid := esrc.get_atlas_grid_size()
		for y in egrid.y:
			for x in egrid.x:
				esrc.create_tile(Vector2i(x, y))
		ts.add_source(esrc, SOURCE_EDGES)
	return ts
