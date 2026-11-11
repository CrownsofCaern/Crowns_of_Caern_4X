class_name BattleStage3D
extends SubViewportContainer
## The 3D battlefield behind BattleViewer: the world3d layer (TerrainField
## + MapScene3D in src/world3d) seen from a fixed
## camera, with the battle's LiveUnit figures standing on it. BattleViewer and
## BattleFigure keep working in their 2D field coordinates (viewer pixels); this
## stage turns a field point into the spot on the ground that the camera shows
## at that pixel, so 2D overlays (numbers, blood, missiles, badges) land on the
## 3D figures. Pure presentation.

## Camera: looks down this many degrees, with this vertical field of view.
const PITCH := 30.0
const FOV := 38.0
## Ground depth (metres, along -z) between the near and far edges of the field.
const DEPTH := 30.0
## World z at the near edge of the field (the camera stands behind it).
const NEAR_Z := 7.0
## Units taller than this (metres) are shown smaller than life, see size_factor.
const BIG_FROM := 2.2
## Map terrain -> world3d biome (data/biomes.json); anything else is the base biome.
const BIOME_OF := {"swamp": "swamp", "infernal": "ashland", "rough": "ashland", "snow": "snowfield", "forest": "deepwood"}

const OUTLINE_SHADER := preload("res://src/ui/shaders/unit_outline.gdshader")

var camera: Camera3D
## Parent of every LiveUnit of the battle.
var units: Node3D
var _view: SubViewport
var _world: Node3D
var _field_rect := Rect2()


## True when this build can show 3D battles (the world layer and the unit
## models are present).
static func available() -> bool:
	return ResourceLoader.exists("res://src/world3d/terrain_field.gd") and LiveUnit.exists("pike_militia")


func build() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_view)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.far = 400.0
	_view.add_child(camera)
	units = Node3D.new()
	units.name = "Units"
	_view.add_child(units)
	# A soft shadowless fill from behind the camera, so the faces turned to the
	# player read against the dark field (the world's sun is low and red).
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(1.0, 0.86, 0.74)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	fill.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(10.0), 0.0)
	units.add_child(fill)


## Builds the ground for a battle on `terrain` (map terrain id). `field` is the
## part of the viewer (pixels) where the armies stand; the camera is placed so
## it spans DEPTH metres of flat ground.
func setup(terrain: String, seed_value: int, field: Rect2) -> void:
	_field_rect = field
	if _world != null:
		_view.remove_child(_world)
		_world.queue_free()
		_world = null
	var f := TerrainField.new()
	f.build_battlefield(80, 50, seed_value, Vector2(30.0, 13.0), 12.0, String(BIOME_OF.get(terrain, "")))
	_world = MapScene3D.create(f, seed_value, true)
	_view.add_child(_world)
	_light_battle(_world)
	_place_camera()


## Crisper sun shadows over the small battlefield than the world layer's
## map-sized default.
func _light_battle(world: MapScene3D) -> void:
	if world.sun != null:
		world.sun.directional_shadow_max_distance = 70.0
		world.sun.shadow_blur = 1.4
		world.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


## Dresses a battle unit in the art bible's look: a dark outline (see
## src/ui/shaders/unit_outline.gdshader).
func dress(unit: Node3D) -> void:
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	for node in unit.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.get_parent() != null and String(mi.get_parent().name) == "Ring":
			continue
		mi.material_overlay = outline


## Camera height and distance so the field's top and bottom pixel rows meet the
## ground DEPTH metres apart, the bottom row at NEAR_Z.
func _place_camera() -> void:
	var h := maxf(1.0, size.y)
	var half := tan(deg_to_rad(FOV * 0.5))
	var pitch := deg_to_rad(PITCH)
	var top := pitch + atan((2.0 * _field_rect.position.y / h - 1.0) * half)
	var bottom := pitch + atan((2.0 * _field_rect.end.y / h - 1.0) * half)
	var height := DEPTH / maxf(0.01, 1.0 / tan(top) - 1.0 / tan(bottom))
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
	camera.position = Vector3(0.0, height, NEAR_Z + height / tan(bottom))


## The point on the ground (y = 0) that the camera shows at viewer pixel `p`.
func field_to_world(p: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(p)
	var dir := camera.project_ray_normal(p)
	if dir.y > -0.001:
		return origin + dir * 200.0
	return origin + dir * (-origin.y / dir.y)


## Metres on the ground per viewer pixel at field point `p` (sideways).
func metres_per_pixel(p: Vector2) -> float:
	return field_to_world(p).distance_to(field_to_world(p + Vector2(10.0, 0.0))) / 10.0


## Scale for a unit `height` metres tall on the battlefield: people and beasts
## keep their size, the big ones grow only half as fast above BIG_FROM metres,
## so a giant towers over a soldier without hiding a whole army.
static func size_factor(height: float) -> float:
	if height <= BIG_FROM:
		return 1.0
	return (BIG_FROM + (height - BIG_FROM) * 0.5) / height


func clear_units() -> void:
	for c in units.get_children():
		units.remove_child(c)
		c.queue_free()
