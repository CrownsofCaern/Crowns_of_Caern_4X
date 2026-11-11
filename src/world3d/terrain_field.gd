class_name TerrainField
extends RefCounted
## Heights and ground paint for a 3D map, as plain data (no Nodes).
## One metre per sim cell (CELL_PX pixels). RES samples per metre.
## Built from a cell grid for skirmishes (build_map, from a
## cell grid), or as a battlefield; other views can fill `heights` and `splat` themselves
## and hand the field to MapScene3D. No game-specific types here.

const RES := 2
const CELL_PX := 32
const PX := float(CELL_PX)  ## sim pixels per metre
## Cell kinds in build_map's grid (fixed numbers; callers fill the grid with these).
const KIND_GROUND := 0
const KIND_ROCK := 1
const KIND_WATER := 2
const KIND_FOREST := 4

var margin: int = 36  ## metres of scenery outside the play area on every side
var play_w: int = 0  ## play area in metres
var play_h: int = 0
var sw: int = 0  ## samples
var sh: int = 0
var origin := Vector2.ZERO  ## world xz of sample (0, 0)
var heights := PackedFloat32Array()
## R = dirt (roads, yards), G = rock, B = forest floor, A = ash.
var splat: Image
var water_level: float = -0.45
## Cell kinds of the play area, kept for decoration.
var kinds := PackedByteArray()
## Decoration wanted per sample, in objects per square metre (MapScene3D scatters them).
var tree_d := PackedFloat32Array()
var rock_d := PackedFloat32Array()
var bush_d := PackedFloat32Array()
## Above this z nothing taller than a tuft is placed (keeps a camera's near edge open).
var tall_max_z: float = INF
var roads: Array = []  ## [Vector2 a, Vector2 b] in metres
var yards: Array = []  ## [Vector2 centre, dirt radius, level radius] in metres (settlements)
## Biomes: [base, west, east] (Biomes.get_biome dictionaries) and how much of the west
## (R) and east (G) biome each sample has; the rest is the base biome.
var biomes: Array = []
var biome_names: Array = []
var biome_map: Image
var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _noise3 := FastNoiseLite.new()


static func to_world(px: Vector2) -> Vector2:
	return px / PX


static func to_sim(m: Vector2) -> Vector2:
	return m * PX


func size_m() -> Vector2:
	return Vector2(sw - 1, sh - 1) / float(RES)


func _setup(w: int, h: int, seed_value: int) -> void:
	play_w = w
	play_h = h
	sw = (w + margin * 2) * RES + 1
	sh = (h + margin * 2) * RES + 1
	origin = Vector2(-margin, -margin)
	heights.resize(sw * sh)
	tree_d.resize(sw * sh)
	tree_d.fill(0.0)
	rock_d.resize(sw * sh)
	rock_d.fill(0.0)
	bush_d.resize(sw * sh)
	bush_d.fill(0.0)
	splat = Image.create(sw, sh, false, Image.FORMAT_RGBA8)
	_noise.seed = seed_value
	_noise.frequency = 0.045
	_noise.fractal_octaves = 4
	_noise2.seed = seed_value + 7
	_noise2.frequency = 0.012
	_noise2.fractal_octaves = 3
	_noise3.seed = seed_value + 13
	_noise3.frequency = 0.09
	_noise3.fractal_octaves = 2
	biome_map = Image.create(sw, sh, false, Image.FORMAT_RG8)
	if biomes.is_empty():
		set_biomes(Biomes.data()["base"], "", "")


## Base biome everywhere, and optionally a west and an east home biome.
func set_biomes(base: String, west: String, east: String) -> void:
	biome_names = [base, west if west != "" else base, east if east != "" else base]
	biomes = biome_names.map(func(n: String) -> Dictionary: return Biomes.get_biome(n))


## Blended number from the biomes at sample (i, j).
func biome_value(i: int, j: int, key: String) -> float:
	var c := biome_map.get_pixel(i, j)
	var wb := maxf(0.0, 1.0 - c.r - c.g)
	return float(biomes[0][key]) * wb + float(biomes[1][key]) * c.r + float(biomes[2][key]) * c.g


## Ground sinking softly into a pool: a shallow bank from thr - 0.06, under water past thr.
func _pool_height(h: float, pn: float, thr: float) -> float:
	var target := water_level - 0.04 - maxf(0.0, pn - thr) * 0.8
	# Fades out on rising ground, so a pool never cuts a wall into a slope.
	var t := smoothstep(thr - 0.06, thr + 0.03, pn) * (1.0 - smoothstep(0.3, 1.6, h))
	return minf(h, lerpf(h, target, t))


## Height at world xz (metres), bilinear.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) * RES, 0.0, sw - 1.001)
	var fz := clampf((z - origin.y) * RES, 0.0, sh - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := heights[iz * sw + ix]
	var b := heights[iz * sw + ix + 1]
	var c := heights[(iz + 1) * sw + ix]
	var d := heights[(iz + 1) * sw + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## Distance (in cells, chamfer) from every play cell to the nearest cell of `kind`.
func _distance_to(kind: int) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(play_w * play_h)
	for i in d.size():
		d[i] = 0.0 if kinds[i] == kind else 999.0
	for pass_i in 2:
		var ys := range(play_h) if pass_i == 0 else range(play_h - 1, -1, -1)
		var xs := range(play_w) if pass_i == 0 else range(play_w - 1, -1, -1)
		var s := 1 if pass_i == 0 else -1
		for y in ys:
			for x in xs:
				var i: int = y * play_w + x
				var best := d[i]
				var px: int = x - s
				var py: int = y - s
				if px >= 0 and px < play_w:
					best = minf(best, d[y * play_w + px] + 1.0)
				if py >= 0 and py < play_h:
					best = minf(best, d[py * play_w + x] + 1.0)
					if px >= 0 and px < play_w:
						best = minf(best, d[py * play_w + px] + 1.414)
				d[i] = best
	return d


func _cell_dist(d: PackedFloat32Array, x: float, z: float) -> float:
	# Bilinear between cell centres, so ponds and mounds get round edges, not steps.
	var fx := clampf(x - 0.5, 0.0, play_w - 1.001)
	var fz := clampf(z - 0.5, 0.0, play_h - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := d[iz * play_w + ix]
	var b := d[iz * play_w + mini(ix + 1, play_w - 1)]
	var c := d[mini(iz + 1, play_h - 1) * play_w + ix]
	var e := d[mini(iz + 1, play_h - 1) * play_w + mini(ix + 1, play_w - 1)]
	return lerpf(lerpf(a, b, tx), lerpf(c, e, tx), tz)


## Builds the field for a sector skirmish: gentle ground, rock mounds, ponds, woods,
## roads between settlements, mountains and woods all around the play area. Each
## side's home third takes its faction's biome (data/biomes.json).
##   cells: grid_w x grid_h cell kinds (KIND_*), row-major.
##   homes: [[centre (px), faction]]; road_segments: [[a (px), b (px)]];
##   settlements: [[centre (px), small (bool)]]. Positions are in sim pixels.
func build_map(grid_w: int, grid_h: int, cells: PackedByteArray, homes: Array, road_segments: Array,
		settlements: Array, seed_value: int = 1, base_biome: String = "") -> void:
	var west := ""
	var east := ""
	for hm in homes:
		var f := Biomes.for_faction(hm[1])
		if (hm[0] as Vector2).x < grid_w * PX * 0.5:
			west = f
		else:
			east = f
	set_biomes(base_biome if base_biome != "" else Biomes.data()["base"], west, east)
	_setup(grid_w, grid_h, seed_value)
	kinds = cells.duplicate()
	var d_rock := _distance_to(KIND_ROCK)
	var d_water := _distance_to(KIND_WATER)
	var d_forest := _distance_to(KIND_FOREST)
	roads.clear()
	yards.clear()
	for sg in road_segments:
		roads.append([to_world(sg[0]), to_world(sg[1])])
	for st in settlements:
		var small: bool = st[1]
		yards.append([to_world(st[0]), 3.2 if small else 5.0, 4.0 if small else 11.0])
	for j in sh:
		for i in sw:
			var x := origin.x + float(i) / RES
			var z := origin.y + float(j) / RES
			var n := _noise.get_noise_2d(x, z)
			var n2 := _noise2.get_noise_2d(x, z)
			var h := 0.12 + absf(n) * 0.35 + n2 * 0.25
			var inside := x >= 0.0 and z >= 0.0 and x < play_w and z < play_h
			# Distance outside the play area, in metres.
			var ox := maxf(maxf(-x, x - play_w), 0.0)
			var oz := maxf(maxf(-z, z - play_h), 0.0)
			var out_d := Vector2(ox, oz).length()
			var rock_w := 0.0
			var dirt_w := 0.0
			var forest_w := 0.0
			var k := j * sw + i
			# Home biomes fill each side's outer third, with a ragged edge.
			var nb := _noise.get_noise_2d(x * 0.6 + 40.0, z * 0.6) * 6.0
			var bw := clampf((play_w * 0.36 - x + nb) / 8.0, 0.0, 1.0)
			var be := clampf((x - play_w * 0.64 + nb) / 8.0, 0.0, 1.0)
			biome_map.set_pixel(i, j, Color(bw, be, 0.0))
			if inside:
				var dr := _cell_dist(d_rock, x, z)
				var dw := _cell_dist(d_water, x, z)
				var df := _cell_dist(d_forest, x, z)
				var mound := clampf(1.0 - (dr - 0.3) / 2.2, 0.0, 1.0)
				h += pow(mound, 1.4) * (1.5 + n * 0.8)
				rock_w = clampf(1.0 - (dr - 0.6) / 1.2, 0.0, 1.0)
				var pond := clampf(1.0 - (dw - 0.2) / 1.8, 0.0, 1.0)
				h = lerpf(h, -1.1, smoothstep(0.0, 1.0, pond))
				forest_w = clampf(1.0 - (df - 0.4) / 2.0, 0.0, 1.0)
				h += forest_w * 0.2
				# Gentle rise toward the edge so the mountains do not start like a wall.
				var edge := minf(minf(x, z), minf(play_w - x, play_h - z))
				h += clampf(1.0 - edge / 6.0, 0.0, 1.0) * 0.6
				var kind: int = kinds[clampi(int(z), 0, play_h - 1) * play_w + clampi(int(x), 0, play_w - 1)]
				if kind == KIND_FOREST:
					tree_d[k] = 0.4
				elif kind == KIND_ROCK:
					rock_d[k] = 0.5
				elif kind == KIND_GROUND:
					bush_d[k] = 0.35 if df > 0.5 and df < 2.5 else 0.02
			else:
				var ridge := 14.0 + 10.0 * _noise2.get_noise_2d(x * 2.0, z * 2.0) + 5.0 * n
				h += pow(clampf(out_d / 26.0, 0.0, 1.0), 1.6) * ridge + clampf(out_d / 4.0, 0.0, 1.0) * 0.7
				rock_w = clampf((h - 5.0) / 4.0, 0.0, 1.0)
				forest_w = clampf(1.0 - out_d / 10.0, 0.0, 1.0) * 0.7
				var clump := clampf(_noise.get_noise_2d(x * 1.7 + 91.0, z * 1.7) * 2.0 + 0.6, 0.0, 1.0)
				if out_d > 1.0:
					tree_d[k] = clampf(1.0 - out_d / 14.0, 0.0, 1.0) * 0.32 + clump * 0.1 * (1.0 - rock_w)
				rock_d[k] = 0.012 * rock_w
				bush_d[k] = 0.06 * (1.0 - rock_w)
			var p := Vector2(x, z)
			for y in yards:
				var yd := p.distance_to(y[0])
				var r: float = y[1]
				dirt_w = maxf(dirt_w, clampf((r - yd) / 1.6 + n * 0.6, 0.0, 1.0))
				# Settlements (and their 3D houses) sit on level ground.
				var flat: float = y[2]
				h = lerpf(h, 0.15, clampf((flat + 1.5 - yd) / 2.5, 0.0, 1.0))
			for rd in roads:
				var q := Geometry2D.get_closest_point_to_segment(p, rd[0], rd[1])
				var dd := p.distance_to(q)
				var width := 1.1 + n * 0.5
				dirt_w = maxf(dirt_w, clampf((width - dd) / 0.7, 0.0, 1.0))
			# Bog pools (or lava pockets) in wet or burnt biomes, never on roads or
			# yards; lava only where nobody walks.
			var wet := biome_value(i, j, "puddles")
			var near_yard := false
			for y in yards:
				if p.distance_to(y[0]) < float(y[2]) + 2.0:
					near_yard = true
			if wet > 0.0 and dirt_w < 0.05 and not near_yard and rock_w < 0.3:
				var lava := biome_value(i, j, "lava") if biomes.size() == 3 else 0.0
				var cell_ok := not inside
				if inside:
					var kd: int = kinds[clampi(int(z), 0, play_h - 1) * play_w + clampi(int(x), 0, play_w - 1)]
					cell_ok = kd == KIND_GROUND and lava < 0.5
				var pn := _noise3.get_noise_2d(x, z) * 0.5 + 0.5
				var thr := 1.0 - wet * 0.45
				if cell_ok and pn > thr - 0.06 and h < 1.6:
					h = _pool_height(h, pn, thr)
					forest_w = maxf(forest_w, 0.6 * smoothstep(thr - 0.06, thr, pn))
			heights[k] = h
			if dirt_w > 0.2 or h < water_level + 0.25:
				tree_d[k] = 0.0
				bush_d[k] = 0.0
				rock_d[k] = 0.0
			var ash := clampf(-n2 * 1.5 - 0.6, 0.0, 1.0) * (1.0 - dirt_w)
			splat.set_pixel(i, j, Color(dirt_w, rock_w, forest_w, ash))


## A battlefield centred on the origin: w x h metres, flat at y = 0 where the armies
## stand (|x| < flat.x, |z| < flat.y), hills, woods and rocks around it, ridges beyond.
## Nothing tall south of `keep_open_z` (a camera looking toward -z sits there).
func build_battlefield(w: int = 80, h: int = 50, seed_value: int = 1, flat := Vector2(30.0, 13.0),
		keep_open_z: float = 12.0, biome: String = "") -> void:
	margin = 30
	set_biomes(biome if biome != "" else Biomes.data()["base"], "", "")
	_setup(w, h, seed_value)
	origin = Vector2(-w * 0.5 - margin, -h * 0.5 - margin)
	tall_max_z = keep_open_z
	kinds = PackedByteArray()
	roads.clear()
	yards.clear()
	for j in sh:
		for i in sw:
			var x := origin.x + float(i) / RES
			var z := origin.y + float(j) / RES
			var k := j * sw + i
			var n := _noise.get_noise_2d(x, z)
			var n2 := _noise2.get_noise_2d(x, z)
			# How far outside the flat battle ground, and outside the whole field.
			var off := Vector2(maxf(absf(x) - flat.x, 0.0), maxf(absf(z) - flat.y, 0.0)).length()
			var out_d := Vector2(maxf(absf(x) - w * 0.5, 0.0), maxf(absf(z) - h * 0.5, 0.0)).length()
			var hill := (absf(n) * 1.6 + n2 * 1.2 + 0.6) * smoothstep(0.0, 10.0, off)
			# Rolling ground behind the battle line (the camera looks that way).
			if z < -flat.y:
				hill += (absf(n2) * 3.5 + absf(n) * 1.5) * smoothstep(0.0, 14.0, -z - flat.y)
			var ridge := (9.0 + 6.0 * _noise2.get_noise_2d(x * 2.0, z * 2.0) + 3.0 * n) \
				* pow(clampf(out_d / 24.0, 0.0, 1.0), 1.5)
			var near := z > keep_open_z
			var hh := hill + ridge
			if near:
				# The camera side only dips and swells gently; it must not block the view.
				hh = minf(hh, 0.3 + n * 0.3) * smoothstep(0.0, 6.0, off)
			# Pools (bog water or lava) off the fighting ground, in wet or burnt biomes.
			var wet := float(biomes[0]["puddles"])
			if wet > 0.0 and off > 3.0 and hh < 1.6:
				var pn := _noise3.get_noise_2d(x, z) * 0.5 + 0.5
				var thr := 1.0 - wet * 0.45
				if pn > thr - 0.06:
					hh = _pool_height(hh, pn, thr)
			heights[k] = hh
			var rock_w := clampf((hh - 6.0) / 4.0, 0.0, 1.0)
			var clump := clampf(_noise.get_noise_2d(x * 1.7 + 91.0, z * 1.7) * 2.2 + 0.2, 0.0, 1.0)
			var wood := clump * smoothstep(3.0, 9.0, off)
			var forest_w := clampf(wood * 1.3, 0.0, 1.0)
			# Trampled ground where the armies meet.
			var dirt_w := clampf((0.25 - absf(n) * 1.4 + n2 * 0.5) * 1.2, 0.0, 1.0) * (1.0 - smoothstep(0.0, 6.0, off))
			var ash := clampf(-n2 * 1.5 - 0.7, 0.0, 1.0) * (1.0 - dirt_w)
			splat.set_pixel(i, j, Color(dirt_w, rock_w, forest_w, ash))
			if not near:
				tree_d[k] = (wood * 0.16 + (0.02 if off > 4.0 else 0.0)) * (1.0 - rock_w)
				rock_d[k] = (0.01 + 0.03 * rock_w) * smoothstep(2.0, 6.0, off)
			bush_d[k] = (0.25 if wood > 0.05 and wood < 0.5 else 0.03) * smoothstep(1.0, 4.0, off)
			if hh < water_level + 0.2:
				tree_d[k] = 0.0
				rock_d[k] = 0.0
				bush_d[k] = 0.0
