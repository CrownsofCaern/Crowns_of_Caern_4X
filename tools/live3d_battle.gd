extends SceneTree
## Prototype: the Concord vs Ashen battle played with LIVE 3D models instead of
## the baked pixel sheets, to judge the look (not wired into the game yet).
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --write-movie /tmp/live3d/frame.avi --script res://tools/live3d_battle.gd -- [seconds] [matchup]
##
## Units come from assets/units3d/<id>.glb through LiveUnit (export them with
## tools/assets/export_live_units.gd). The world is in metres: a human soldier
## is 1.8 m tall. Trees, rocks and the ground texture are optional CC0 assets in
## res://_nature/ (Quaternius Ultimate Stylized Nature and ambientCG Ground037,
## git-ignored); without them the ground is plain.
## The choreography is scripted (march, volleys, clash, deaths), not a replay
## of a real battle log.

const NATURE := "res://_nature/"
## Gap between soldiers in a line and between rows, in metres.
const SPACING := 1.6
## How far the melee blocks march before the lines touch.
const ADVANCE := 7.7

var _seconds := 26.0
var _figures: Array = []
var _shots: Array = []
var _bursts: Array = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _cam: Camera3D
var _world: Node3D
var _fx_mat := {}
var _loaded := false

## Units per side: id, count, x of the block front, rows, role, z of the block centre.
## The caster element per side colours spell bolts; the defender picks the ground.
const MATCHUPS := {
	"concord_ashen": {
		"left": [
			["shieldwarden", 12, -8.8, 2, "melee", 0.0],
			["pike_militia", 12, -11.6, 2, "pike", 0.0],
			["bastion_colossus", 1, -11.0, 1, "melee", -7.5],
			["longbowman", 12, -17.5, 2, "bow", 0.0],
			["lightbearer", 4, -21.5, 1, "caster", 0.0],
		],
		"right": [
			["flayer", 12, 8.8, 2, "melee", 0.0],
			["scorchhound", 8, 11.6, 2, "hound", 0.0],
			["pyre_titan", 1, 11.0, 1, "melee", -7.5],
			["brimstone_hurler", 10, 17.5, 2, "thrower", 0.0],
			["ash_witch", 5, 21.5, 1, "caster", 0.0],
		],
		"spells": ["holy", "fire"],
		"defender": "ashen",
	},
	"frostmarch_hollow": {
		"left": [
			["clan_raider", 12, -8.8, 2, "melee", 0.0],
			["oathless_berserker", 8, -11.6, 2, "melee", 0.0],
			["cairn_giant", 1, -11.0, 1, "melee", -7.5],
			["rimefang_hound", 6, -12.5, 2, "hound", 7.0],
			["frost_shaman", 4, -18.5, 1, "caster", 0.0],
		],
		"right": [
			["shambler", 14, 8.8, 2, "melee", 0.0],
			["gibbet_knight", 6, 11.6, 1, "melee", 0.0],
			["charnel_hulk", 1, 11.0, 1, "melee", -7.5],
			["marrow_archer", 12, 17.5, 2, "bow", 0.0],
			["corpse_weaver", 4, 21.5, 1, "caster", 0.0],
		],
		"spells": ["frost", "necro"],
		"defender": "hollow",
	},
}
const BIG := ["bastion_colossus", "pyre_titan", "cairn_giant", "charnel_hulk"]

var _matchup: Dictionary


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_seconds = float(args[0])
	_matchup = MATCHUPS[args[1] if args.size() > 1 else "concord_ashen"]
	_rng.seed = 31
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_stage()
	if not _world_layer():
		_ground()
		_dress()
	_deploy(_matchup["left"], 1.0)
	_deploy(_matchup["right"], -1.0)
	print("on screen: %d figures" % _figures.size())
	_loaded = true
	process_frame.connect(_tick)


# --- stage -----------------------------------------------------------------

func _stage() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.03, 0.03)
	sm.sky_horizon_color = Color(0.58, 0.17, 0.08)
	sm.sky_curve = 0.12
	sm.ground_horizon_color = Color(0.2, 0.1, 0.06)
	sm.ground_bottom_color = Color(0.06, 0.04, 0.03)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.32, 0.13, 0.09)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.4
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	# Warm key from the top left, cool dim fill (art bible).
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.8, 0.62)
	key.light_energy = 1.35
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 60.0
	key.rotation_degrees = Vector3(-42, -35, 0)
	_world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.6, 0.85)
	fill.light_energy = 0.3
	fill.rotation_degrees = Vector3(-20, 150, 0)
	_world.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 400.0
	_world.add_child(_cam)
	_place_camera(0.0)
	_fx()


func _world_layer() -> bool:
	# The world3d terrain module (TerrainField + MapScene3D), when this runs in a
	# project that has it; loaded by path so this script also parses without it.
	const FIELD := "res://src/world3d/terrain_field.gd"
	const SCENE := "res://src/world3d/map_scene_3d.gd"
	if not (ResourceLoader.exists(FIELD) and ResourceLoader.exists(SCENE)):
		return false
	var field = load(FIELD).new()
	# The defender's home ground (swamp, ashland, meadow), when the module has biomes.
	const BIOMES := "res://src/world3d/biomes.gd"
	if ResourceLoader.exists(BIOMES):
		var biome: String = load(BIOMES).for_faction(String(_matchup.get("defender", "")))
		field.build_battlefield(80, 50, 7, Vector2(30.0, 13.0), 12.0, biome)
	else:
		field.build_battlefield(80, 50, 7)
	_world.add_child(load(SCENE).create(field, 7, false))
	return true


func _ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 160)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.roughness = 1.0
	var alb := NATURE + "ground/ground037_alb_ht.png"
	if FileAccess.file_exists(alb):
		gm.albedo_texture = _texture(alb)
		gm.normal_enabled = true
		gm.normal_texture = _texture(NATURE + "ground/ground037_nrm_rgh.png")
		gm.albedo_color = Color(0.42, 0.42, 0.34)
		gm.uv1_scale = Vector3(60, 40, 1)
	else:
		gm.albedo_color = Color(0.14, 0.15, 0.08)
	ground.material_override = gm
	_world.add_child(ground)


func _fx() -> void:
	for kind in ["arrow", "boulder", "fire", "holy", "frost", "necro"]:
		var m := StandardMaterial3D.new()
		match kind:
			"arrow":
				m.albedo_color = Color(0.25, 0.18, 0.12)
			"boulder":
				m.albedo_color = Color(0.3, 0.26, 0.22)
				m.emission_enabled = true
				m.emission = Color(0.9, 0.3, 0.05)
				m.emission_energy_multiplier = 0.6
			"fire":
				m.albedo_color = Color(1.0, 0.45, 0.1)
				m.emission_enabled = true
				m.emission = Color(1.0, 0.4, 0.05)
				m.emission_energy_multiplier = 3.0
			"holy":
				m.albedo_color = Color(1.0, 0.95, 0.7)
				m.emission_enabled = true
				m.emission = Color(1.0, 0.9, 0.55)
				m.emission_energy_multiplier = 3.0
			"frost":
				m.albedo_color = Color(0.7, 0.9, 1.0)
				m.emission_enabled = true
				m.emission = Color(0.45, 0.75, 1.0)
				m.emission_energy_multiplier = 3.0
			"necro":
				m.albedo_color = Color(0.5, 0.9, 0.4)
				m.emission_enabled = true
				m.emission = Color(0.35, 0.85, 0.25)
				m.emission_energy_multiplier = 3.0
		_fx_mat[kind] = m


func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _dress() -> void:
	# Trees and rocks around the field, a few stones and bushes on it.
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(NATURE + "prefabs")):
		return
	for m in ["PineTree_Leaves", "NormalTree_Leaves", "Bush_Leaves", "Grass", "MapleTree_Leaves"]:
		var mat := load(NATURE + "materials/%s.tres" % m) as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.32, 0.36, 0.26)
	var rocks := load(NATURE + "materials/Rocks.tres") as StandardMaterial3D
	if rocks != null:
		rocks.albedo_color = Color(0.55, 0.5, 0.5)
	var trees := ["pine_tree_1", "pine_tree_3", "pine_tree_5", "normal_tree_2", "dead_tree_1", "dead_tree_4", "dead_tree_7"]
	var stones := ["rock_1", "rock_3", "rock_5"]
	var bushes := ["bush_small", "bush", "grass", "grass_large"]
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.05
	for n in 2600:
		var x := _rng.randf_range(-90.0, 90.0)
		var z := _rng.randf_range(-70.0, 30.0)
		var field := absf(x) < 30.0 and z > -16.0 and z < 10.0
		var clear := absf(x) < 36.0 and z > -24.0
		var name := ""
		var s := 1.0
		if field:
			if _rng.randf() < 0.06:
				name = stones[_rng.randi() % stones.size()] if _rng.randf() < 0.3 else bushes[_rng.randi() % bushes.size()]
				s = _rng.randf_range(0.5, 1.0)
		elif not clear and noise.get_noise_2d(x, z) > 0.05 and _rng.randf() < 0.3:
			name = trees[_rng.randi() % trees.size()]
			s = _rng.randf_range(2.0, 3.2)
		elif _rng.randf() < 0.15:
			name = stones[_rng.randi() % stones.size()] if _rng.randf() < 0.4 else bushes[_rng.randi() % bushes.size()]
			s = _rng.randf_range(0.8, 1.8)
		if name == "" or z > 10.0 and absf(x) < 40.0:
			continue
		var packed := load(NATURE + "prefabs/" + name + ".tscn") as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate() as Node3D
		node.position = Vector3(x, 0, z)
		node.rotation.y = _rng.randf() * TAU
		node.scale = Vector3.ONE * s
		_world.add_child(node)


func _place_camera(t: float) -> void:
	# A slow sweep: from a wide view behind the Concord flank in toward the clash.
	var k := smoothstep(0.0, 1.0, clampf(t / _seconds, 0.0, 1.0))
	_cam.position = Vector3(lerpf(-7.0, 2.5, k), lerpf(8.5, 5.5, k), lerpf(22.0, 15.0, k))
	_cam.look_at(Vector3(lerpf(-4.0, 0.5, k), 1.0, -1.0))


# --- figures ---------------------------------------------------------------

func _deploy(side: Array, dir: float) -> void:
	for u in side:
		var id := String(u[0])
		var count := int(u[1])
		var rows := int(u[3])
		var per_row := int(ceil(float(count) / rows))
		for i in count:
			var row := i / per_row
			var col := i % per_row
			var unit := LiveUnit.spawn(id)
			if unit == null:
				push_error("no live model for " + id + "; run tools/assets/export_live_units.gd")
				break
			_world.add_child(unit)
			var gap := maxf(SPACING, unit.radius * 2.6)
			var z := float(u[5]) + (col - (per_row - 1) / 2.0) * gap + _rng.randf_range(-0.15, 0.15)
			var x := float(u[2]) - dir * row * gap * 1.1 + _rng.randf_range(-0.12, 0.12)
			unit.position = Vector3(x, 0, z)
			unit.rotation.y = 0.0 if dir > 0 else PI
			unit.scale = Vector3.ONE * _rng.randf_range(0.96, 1.04)
			var f := {"node": unit, "id": id, "role": String(u[4]), "dir": dir, "home": unit.position,
				"state": "", "alive": true, "next": _rng.randf_range(0.0, 1.5), "lunge": -1.0}
			_figures.append(f)
			_play(f, "idle")


func _play(f: Dictionary, action: String) -> void:
	if f["state"] == action:
		return
	f["state"] = action
	(f["node"] as LiveUnit).play(action, _rng.randf_range(0.9, 1.1) if action in ["idle", "move"] else 1.0)


# --- choreography ------------------------------------------------------------

const MARCH_START := 2.0
const CLASH := 7.0


func _tick() -> void:
	if not _loaded:
		return
	var dt := 1.0 / 30.0
	_t += dt
	_place_camera(_t)
	for f in _figures:
		if not f["alive"]:
			continue
		match String(f["role"]):
			"melee", "pike", "hound":
				_melee(f, dt)
			_:
				_ranged(f, dt)
	_fly(dt)
	_fade_bursts(dt)
	# Thin both armies once the lines meet; the Ashen lose more.
	if _t > CLASH + 0.5 and _rng.randf() < dt * 0.8:
		_kill(_victim(-1.0 if _rng.randf() < 0.6 else 1.0, true))
	if _t >= _seconds:
		quit()


func _melee(f: Dictionary, dt: float) -> void:
	var unit: LiveUnit = f["node"]
	var dir := float(f["dir"])
	var home: Vector3 = f["home"]
	var target := Vector3(home.x + dir * ADVANCE, 0, home.z)
	if f["role"] == "hound":
		target.x += dir * 1.2
	if _t < MARCH_START:
		_play(f, "idle")
		return
	if unit.position.distance_to(target) > 0.05:
		# March at the pace the move clip's feet were made for (within limits).
		var speed := clampf(unit.move_speed, 1.2, 3.6)
		unit.position = unit.position.move_toward(target, dt * speed)
		f["state"] = "move"
		unit.walk(speed)
		return
	# In contact: keep fighting until the end.
	f["state"] = "fight"
	unit.fight()
	f["next"] = float(f["next"]) - dt
	if float(f["next"]) <= 0.0:
		f["next"] = _rng.randf_range(0.9, 1.8)
		if not unit.has_clip("attack"):
			f["lunge"] = 0.0
		if _rng.randf() < 0.5:
			_burst(unit.position + Vector3(dir * 0.5, unit.height * 0.55, 0), "spark", 0.35)
	if float(f["lunge"]) >= 0.0:
		# Units without an attack clip (pikes, hounds) jab forward instead.
		f["lunge"] = float(f["lunge"]) + dt
		var l := float(f["lunge"])
		unit.position.x = target.x + dir * sin(clampf(l / 0.6, 0.0, 1.0) * PI) * 0.45
		if l > 0.6:
			f["lunge"] = -1.0


func _ranged(f: Dictionary, dt: float) -> void:
	var unit: LiveUnit = f["node"]
	if _t < 1.0:
		return
	f["next"] = float(f["next"]) - dt
	if f["state"] == "attack" and not unit.busy():
		_play(f, "idle")
	if float(f["next"]) > 0.0:
		return
	f["next"] = _rng.randf_range(2.4, 3.6)
	f["state"] = ""
	_play(f, "attack")
	var kind: String = {"bow": "arrow", "thrower": "boulder", "caster": _matchup["spells"][0 if f["dir"] > 0 else 1]}[f["role"]]
	var victim := _victim(-float(f["dir"]), false)
	if victim.is_empty():
		return
	var delay: float = {"arrow": 0.55, "boulder": 0.7}.get(kind, 0.45)
	_shots.append({"kind": kind, "from": unit.position + Vector3(float(f["dir"]) * 0.3, unit.height * 0.7, 0),
		"victim": victim, "t": -delay, "time": 1.2 if kind == "arrow" else 1.4, "node": null})


func _victim(dir: float, melee_first: bool) -> Dictionary:
	var pool := []
	for f in _figures:
		if f["alive"] and float(f["dir"]) == dir and f["id"] not in BIG:
			if not melee_first or f["role"] in ["melee", "pike", "hound"]:
				pool.append(f)
	if pool.is_empty():
		return {}
	return pool[_rng.randi() % pool.size()]


func _fly(dt: float) -> void:
	for s in _shots.duplicate():
		s["t"] = float(s["t"]) + dt
		if float(s["t"]) < 0.0:
			continue
		if s["node"] == null:
			var mi := MeshInstance3D.new()
			match String(s["kind"]):
				"arrow":
					var c := CylinderMesh.new()
					c.top_radius = 0.015
					c.bottom_radius = 0.015
					c.height = 0.75
					mi.mesh = c
				"boulder":
					var sp := SphereMesh.new()
					sp.radius = 0.22
					sp.height = 0.44
					mi.mesh = sp
				_:
					var sp := SphereMesh.new()
					sp.radius = 0.14
					sp.height = 0.28
					mi.mesh = sp
					var light := OmniLight3D.new()
					light.light_color = (_fx_mat[s["kind"]] as StandardMaterial3D).emission
					light.omni_range = 4.0
					light.light_energy = 1.5
					mi.add_child(light)
			mi.material_override = _fx_mat[s["kind"]]
			_world.add_child(mi)
			s["node"] = mi
		var v: Dictionary = s["victim"]
		var vu: LiveUnit = v["node"]
		var to: Vector3 = vu.position + Vector3(0, vu.height * 0.5, 0)
		var u := clampf(float(s["t"]) / float(s["time"]), 0.0, 1.0)
		var from: Vector3 = s["from"]
		var arc := 4.0 if s["kind"] in ["arrow", "boulder"] else 1.0
		var pos := from.lerp(to, u) + Vector3(0, sin(u * PI) * arc, 0)
		var mi: MeshInstance3D = s["node"]
		var ahead := from.lerp(to, minf(1.0, u + 0.02)) + Vector3(0, sin(minf(1.0, u + 0.02) * PI) * arc, 0)
		mi.position = pos
		if s["kind"] == "arrow" and ahead.distance_to(pos) > 1e-4:
			mi.look_at(ahead, Vector3.UP)
			mi.rotate_object_local(Vector3.RIGHT, PI / 2)
		if u >= 1.0:
			_burst(to, String(s["kind"]), 0.6 if s["kind"] == "boulder" else 0.4)
			if v["alive"] and _rng.randf() < (0.35 if s["kind"] == "boulder" else 0.15):
				_kill(v)
			mi.queue_free()
			_shots.erase(s)


func _burst(at: Vector3, kind: String, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 24
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 3.0 * size
	p.initial_velocity_max = 7.5 * size
	p.gravity = Vector3(0, -9, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = {"spark": Color(1, 0.8, 0.4), "arrow": Color(0.5, 0.05, 0.03), "boulder": Color(1, 0.45, 0.1),
		"fire": Color(1, 0.5, 0.1), "holy": Color(1, 0.95, 0.6), "frost": Color(0.6, 0.85, 1.0),
		"necro": Color(0.4, 0.85, 0.3), "blood": Color(0.45, 0.02, 0.02)}[kind]
	q.material = m
	p.mesh = q
	p.position = at
	_world.add_child(p)
	_bursts.append({"node": p, "t": 0.0})
	if kind in ["fire", "holy", "boulder", "frost", "necro"]:
		var light := OmniLight3D.new()
		light.light_color = m.albedo_color
		light.omni_range = 5.0
		light.light_energy = 2.5
		p.add_child(light)


func _fade_bursts(dt: float) -> void:
	for b in _bursts.duplicate():
		b["t"] = float(b["t"]) + dt
		var n: Node3D = b["node"]
		for c in n.get_children():
			if c is OmniLight3D:
				(c as OmniLight3D).light_energy = maxf(0.0, 2.5 * (1.0 - float(b["t"]) / 0.4))
		if float(b["t"]) > 1.0:
			n.queue_free()
			_bursts.erase(b)


func _kill(f: Dictionary) -> void:
	if f.is_empty() or not f["alive"]:
		return
	f["alive"] = false
	var unit: LiveUnit = f["node"]
	_burst(unit.position + Vector3(0, unit.height * 0.5, 0), "blood", 0.4)
	unit.die(-float(f["dir"]))
