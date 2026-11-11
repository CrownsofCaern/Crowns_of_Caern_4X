class_name MapScene3D
extends Node3D
## The 3D world of a map: terrain, water, trees, rocks, bushes, sky and light.
## Built from a TerrainField (plain data). Used by the 3D battle
## (BattleStage3D): `MapScene3D.create(field)` returns a ready node to add anywhere.
## Assets are CC0: ambientCG ground/rock textures, Quaternius nature models.

const CHUNK := 32  ## metres per terrain chunk and decoration batch
const NATURE := "res://assets/nature/%s.glb"
const TEX := "res://assets/terrain3d/%s.png"
## Model -> [min height, max height] in metres (models are rescaled to these).
const TREES := {"pine_tree_1": [3.8, 5.5], "pine_tree_2": [3.5, 5.0], "pine_tree_3": [3.8, 5.5],
	"pine_tree_5": [3.2, 4.5], "normal_tree_2": [3.2, 4.4], "normal_tree_4": [3.2, 4.4]}
const DEAD := {"dead_tree_1": [3.0, 4.2], "dead_tree_3": [2.6, 3.8], "dead_tree_4": [3.0, 4.2],
	"dead_tree_7": [2.6, 3.8], "dead_tree_9": [2.6, 3.4]}
const ROCKS := {"rock_1": [1.1, 2.2], "rock_2": [1.1, 2.2], "rock_3": [1.0, 2.0], "rock_4": [1.0, 1.9],
	"rock_5": [1.1, 2.2]}
const GRASS := {"grass": [0.28, 0.5]}
## Tufts per square metre on open grass (cheap crossed cards, drawn only near the camera).
const GRASS_DENSITY := 1.6
const BUSHES := {"bush": [0.6, 1.0], "bush_large": [0.8, 1.3], "bush_small": [0.4, 0.7], "plant_1": [0.35, 0.6]}

var field: TerrainField
var terrain_material: ShaderMaterial
var sun: DirectionalLight3D
var environment: Environment
## Counts of placed decoration, for tests and tools.
var stats: Dictionary = {}
var _protos: Dictionary = {}  ## model -> [Mesh, Transform3D base, float native height]
var _batches: Dictionary = {}
var _colors: Dictionary = {}  ## batch key -> Array[Color] (grass tufts tinted per biome)
var _biome_tex: ImageTexture  ## "model:cx:cz" -> Array[Transform3D]


static func create(f: TerrainField, seed_value: int = 1, with_environment: bool = true) -> MapScene3D:
	var m := MapScene3D.new()
	m.name = "MapScene3D"
	m.build(f, seed_value, with_environment)
	return m


func build(f: TerrainField, seed_value: int = 1, with_environment: bool = true) -> void:
	field = f
	_terrain()
	_water()
	_decorate(seed_value)
	if with_environment:
		_environment()


# --- Terrain -------------------------------------------------------------------

func _terrain() -> void:
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://src/world3d/terrain.gdshader")
	terrain_material.set_shader_parameter("grass_alb", load(TEX % "ground037_alb_ht"))
	terrain_material.set_shader_parameter("grass_nrm", load(TEX % "ground037_nrm_rgh"))
	terrain_material.set_shader_parameter("rock_alb", load(TEX % "rock023_alb_ht"))
	terrain_material.set_shader_parameter("rock_nrm", load(TEX % "rock023_nrm_rgh"))
	terrain_material.set_shader_parameter("splat", ImageTexture.create_from_image(field.splat))
	var mn := NoiseTexture2D.new()
	mn.width = 256
	mn.height = 256
	mn.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.012
	fn.fractal_octaves = 3
	mn.noise = fn
	terrain_material.set_shader_parameter("macro_noise", mn)
	_biome_params(terrain_material, {"grass": "b_grass", "lush": "b_lush", "dry": "b_dry", "dirt": "b_dirt",
		"rock": "b_rock", "moss": "b_moss", "ash": "b_ash"})
	var snow := PackedFloat32Array()
	for b in field.biomes:
		snow.append(clampf(float(b.get("snow", 0.0)), 0.0, 1.0))
	terrain_material.set_shader_parameter("b_snow", snow)
	# Sample (i, j) sits at the centre of splat pixel (i, j).
	terrain_material.set_shader_parameter("origin", field.origin - Vector2.ONE * 0.5 / TerrainField.RES)
	terrain_material.set_shader_parameter("size", Vector2(field.sw, field.sh) / TerrainField.RES)
	var step := CHUNK * TerrainField.RES
	var root := Node3D.new()
	root.name = "Terrain"
	add_child(root)
	for j0 in range(0, field.sh - 1, step):
		for i0 in range(0, field.sw - 1, step):
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(i0, j0, mini(i0 + step, field.sw - 1), mini(j0 + step, field.sh - 1))
			mi.material_override = terrain_material
			root.add_child(mi)


func _h(i: int, j: int) -> float:
	return field.heights[clampi(j, 0, field.sh - 1) * field.sw + clampi(i, 0, field.sw - 1)]


func _chunk_mesh(i0: int, j0: int, i1: int, j1: int) -> ArrayMesh:
	var cw := i1 - i0 + 1
	var ch := j1 - j0 + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var idx := PackedInt32Array()
	verts.resize(cw * ch)
	normals.resize(cw * ch)
	tangents.resize(cw * ch * 4)
	var d := 1.0 / TerrainField.RES
	for j in ch:
		for i in cw:
			var gi := i0 + i
			var gj := j0 + j
			var v := j * cw + i
			verts[v] = Vector3(field.origin.x + gi * d, _h(gi, gj), field.origin.y + gj * d)
			var dx := _h(gi + 1, gj) - _h(gi - 1, gj)
			var dz := _h(gi, gj + 1) - _h(gi, gj - 1)
			var n := Vector3(-dx, 2.0 * d, -dz).normalized()
			normals[v] = n
			var t := Vector3(2.0 * d, dx, 0.0)
			t = (t - n * n.dot(t)).normalized()
			tangents[v * 4] = t.x
			tangents[v * 4 + 1] = t.y
			tangents[v * 4 + 2] = t.z
			tangents[v * 4 + 3] = 1.0
	for j in ch - 1:
		for i in cw - 1:
			var a := j * cw + i
			idx.append_array([a, a + 1, a + cw, a + 1, a + cw + 1, a + cw])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Water ---------------------------------------------------------------------

## Hands the three biomes' colours (base, west, east) and the biome map to a shader.
func _biome_params(mat: ShaderMaterial, keys: Dictionary) -> void:
	if _biome_tex == null:
		_biome_tex = ImageTexture.create_from_image(field.biome_map)
	mat.set_shader_parameter("biome_map", _biome_tex)
	for k in keys:
		var arr := PackedVector3Array()
		for b in field.biomes:
			var c := Biomes.color(b, k)
			arr.append(Vector3(c.r, c.g, c.b))
		mat.set_shader_parameter(keys[k], arr)


func _water() -> void:
	var lowest := INF
	for v in field.heights:
		lowest = minf(lowest, v)
	if lowest >= field.water_level:
		return
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var waves := NoiseTexture2D.new()
	waves.width = 256
	waves.height = 256
	waves.seamless = true
	waves.as_normal_map = true
	waves.bump_strength = 4.0
	waves.noise = noise
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/world3d/water.gdshader")
	mat.set_shader_parameter("waves", waves)
	_biome_params(mat, {"water_deep": "b_deep", "water_sky": "b_sky"})
	var lava := PackedFloat32Array()
	for b in field.biomes:
		lava.append(1.0 if b["lava"] else 0.0)
	mat.set_shader_parameter("b_lava", lava)
	mat.set_shader_parameter("origin", field.origin - Vector2.ONE * 0.5 / TerrainField.RES)
	mat.set_shader_parameter("size", Vector2(field.sw, field.sh) / TerrainField.RES)
	var pm := PlaneMesh.new()
	pm.size = field.size_m()
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(field.origin.x + pm.size.x * 0.5, field.water_level, field.origin.y + pm.size.y * 0.5)
	add_child(mi)


# --- Decoration ----------------------------------------------------------------

func _proto(model: String) -> Array:
	if _protos.has(model):
		return _protos[model]
	if model == "grass":
		_protos[model] = [_grass_mesh(), Transform3D.IDENTITY, 1.0]
		return _protos[model]
	var scn: Node3D = (load(NATURE % model) as PackedScene).instantiate()
	var mi: MeshInstance3D = scn.find_children("*", "MeshInstance3D", true, false)[0]
	var base := _rel_transform(scn, mi)
	var mesh: Mesh = mi.mesh
	if BUSHES.has(model):
		# Bushes come out lime green; pull them toward the darker ground.
		mesh = mesh.duplicate()
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as StandardMaterial3D
			if m != null:
				m = m.duplicate()
				m.albedo_color = m.albedo_color * Color(0.6, 0.6, 0.55)
				mesh.surface_set_material(i, m)
	var aabb := base * mesh.get_aabb()
	# Feet on the ground: lift so the model's lowest point sits at y = 0.
	base.origin.y -= aabb.position.y
	var p := [mesh, base, maxf(aabb.size.y, 0.01)]
	scn.free()
	_protos[model] = p
	return p


## A grass tuft: three crossed cards with a drawn blade texture, 1 m tall before scaling.
func _grass_mesh() -> ArrayMesh:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.42, 0.48, 0.28, 0.0))  # blade colour under the alpha, so mipmaps stay green
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for b in 16:
		var x0 := rng.randf_range(6.0, 58.0)
		var lean := rng.randf_range(-10.0, 10.0)
		var top := rng.randf_range(4.0, 30.0)
		var shade := rng.randf_range(0.75, 1.0)
		for y in range(63, int(top), -1):
			var t := (63.0 - y) / (63.0 - top)
			var cx := x0 + lean * t * t
			var half := lerpf(1.6, 0.3, t)
			for x in range(int(cx - half), int(cx + half) + 1):
				if x >= 0 and x < 64:
					var c := Color(0.55, 0.62, 0.38) * lerpf(0.45, 1.0, t) * shade
					img.set_pixel(x, y, Color(c, 1.0))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.vertex_color_use_as_albedo = true  # per-tuft biome tint (MultiMesh colours)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in 3:
		var a := q * PI / 3.0
		var d := Vector3(cos(a), 0.0, sin(a)) * 0.45
		var v := [-d, d, d + Vector3.UP, -d + Vector3.UP]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		# Both windings with an upward normal: lit like the ground from either side
		# (a culling-disabled card would flip the normal on its back and go black).
		for idx in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	st.set_material(mat)
	return st.commit()


func _rel_transform(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _place(model: String, sizes: Array, x: float, z: float, rng: RandomNumberGenerator, sink: float = 0.1,
		tilt: float = 0.0, color := Color.WHITE) -> void:
	var p := _proto(model)
	var want := rng.randf_range(sizes[0], sizes[1])
	var s: float = want / float(p[2])
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	if tilt > 0.0:
		b = Basis(Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5).normalized(), rng.randf() * tilt) * b
	var xf := Transform3D(b.scaled(Vector3.ONE * s), Vector3(x, field.height_at(x, z) - sink * want, z)) * (p[1] as Transform3D)
	var key := "%s:%d:%d" % [model, int(floor(x / CHUNK)), int(floor(z / CHUNK))]
	if not _batches.has(key):
		_batches[key] = []
	_batches[key].append(xf)
	if model == "grass":
		if not _colors.has(key):
			_colors[key] = []
		_colors[key].append(color)
	stats[model] = int(stats.get(model, 0)) + 1


func _pick(d: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys := d.keys()
	keys.sort()
	return keys[rng.randi() % keys.size()]


## Scatters decoration by the field's densities. Purely visual: a seeded generator
## of its own, so the same map always looks the same.
func _decorate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	var cell := 1.0 / TerrainField.RES
	var area := cell * cell
	for j in field.sh:
		for i in field.sw:
			var k := j * field.sw + i
			var x := field.origin.x + i * cell
			var z := field.origin.y + j * cell
			var td: float = field.tree_d[k] * field.biome_value(i, j, "trees")
			var rd: float = field.rock_d[k]
			var bd: float = field.bush_d[k] * field.biome_value(i, j, "bushes")
			if td <= 0.0 and rd <= 0.0 and bd <= 0.0:
				continue
			var jx := x + rng.randf_range(-0.5, 0.5) * cell
			var jz := z + rng.randf_range(-0.5, 0.5) * cell
			var tall_ok := jz <= field.tall_max_z
			var roll := rng.randf()
			if tall_ok and roll < td * area:
				var sp := field.splat.get_pixel(i, j)
				var dead := sp.a > 0.35 or field.heights[k] > 9.0 or rng.randf() < field.biome_value(i, j, "dead_trees")
				var set: Dictionary = DEAD if dead else TREES
				var m := _pick(set, rng)
				_place(m, set[m], jx, jz, rng)
			elif tall_ok and roll < (td + rd) * area:
				var m := _pick(ROCKS, rng)
				_place(m, ROCKS[m], jx, jz, rng, 0.3, 0.5)
			elif roll < (td + rd + bd) * area:
				var bushes := BUSHES if tall_ok else {"plant_1": BUSHES["plant_1"], "bush_small": [0.3, 0.5]}
				var m := _pick(bushes, rng)
				_place(m, bushes[m], jx, jz, rng, 0.05)
	_grass(seed_value)
	_flush()


func _grass(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 104729 + 3
	var cell := 1.0 / TerrainField.RES
	var p := GRASS_DENSITY * cell * cell
	var clumps := FastNoiseLite.new()
	clumps.seed = seed_value + 31
	clumps.frequency = 0.09
	for j in field.sh:
		for i in field.sw:
			# Tufts grow in clumps: dense where the noise is high, none where it is low.
			var c := clampf(clumps.get_noise_2d(i * cell, j * cell) * 2.5 + 0.5, 0.0, 2.0)
			if rng.randf() >= p * c * field.biome_value(i, j, "tufts"):
				continue
			var k := j * field.sw + i
			var sp := field.splat.get_pixel(i, j)
			if sp.r > 0.25 or sp.g > 0.3 or field.heights[k] < field.water_level + 0.15 or field.heights[k] > 8.0:
				continue
			var x := field.origin.x + (i + rng.randf_range(-0.5, 0.5)) * cell
			var z := field.origin.y + (j + rng.randf_range(-0.5, 0.5)) * cell
			var bm := field.biome_map.get_pixel(i, j)
			var wb := maxf(0.0, 1.0 - bm.r - bm.g)
			var tint := Biomes.color(field.biomes[0], "tuft") * wb + Biomes.color(field.biomes[1], "tuft") * bm.r \
				+ Biomes.color(field.biomes[2], "tuft") * bm.g
			_place("grass", GRASS["grass"], x, z, rng, 0.0, 0.0, Color(tint, 1.0))


func _flush() -> void:
	var root := Node3D.new()
	root.name = "Decoration"
	add_child(root)
	var keys := _batches.keys()
	keys.sort()
	for key: String in keys:
		var model := key.split(":")[0]
		var xfs: Array = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = _colors.has(key)
		mm.mesh = _proto(model)[0]
		mm.instance_count = xfs.size()
		for n in xfs.size():
			mm.set_instance_transform(n, xfs[n])
			if mm.use_colors:
				mm.set_instance_color(n, _colors[key][n])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if BUSHES.has(model):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 90.0
		elif model == "grass":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 65.0
		root.add_child(mmi)
	_batches.clear()
	_colors.clear()


# --- Sky and light -------------------------------------------------------------

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.06, 0.08)
	sky_mat.sky_horizon_color = Color(0.55, 0.22, 0.14)
	sky_mat.ground_horizon_color = Color(0.3, 0.12, 0.08)
	sky_mat.ground_bottom_color = Color(0.05, 0.03, 0.03)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.4, 0.4, 0.48)
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.3, 0.2, 0.19)
	environment.fog_density = 0.0018
	environment.fog_sky_affect = 0.4
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.85
	environment.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.78)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.rotation_degrees = Vector3(-38, -128, 0)
	add_child(sun)
