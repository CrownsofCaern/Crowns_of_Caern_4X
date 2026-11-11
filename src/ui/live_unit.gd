class_name LiveUnit
extends Node3D
## A live 3D unit made from assets/units3d/<id>.glb (written by
## tools/assets/export_live_units.gd). The model stands with its feet on y = 0,
## faces +X, and is sized in metres (a human soldier is about 1.8 m tall).
## Clips: idle, move, attack, death (any may be missing), and live-only
## variants idle_alt and attack_alt that vary() switches to. Kept free of game
## code so other views can reuse it unchanged.
##
##   var unit := LiveUnit.spawn("pike_militia")
##   add_child(unit)
##   unit.play("move")

const DIR := "res://assets/units3d/"
const LOOPS := ["idle", "move", "idle_alt"]
## A flinch (see flinch()): seconds, and how far (metres) and how much
## (radians) a full-strength hit throws the body back.
const FLINCH_SECONDS := 0.42
const FLINCH_BACK := 0.14
const FLINCH_TILT := 0.16

var id := ""
## Standing height and footprint radius in metres, from the rest-pose bounds.
var height := 1.8
var radius := 0.3
## Rest-pose footprint in metres: along the march (+X) and across it.
var length := 0.6
var width := 0.6
## Ground speed (m/s) at which the move clip's feet do not slide.
var move_speed := 0.0
## When the attack clip's blow lands, as a fraction of the clip (0..1).
var impact := 0.5
## The attack_alt clip's blow, likewise.
var impact_alt := 0.5
## Clip names played for "idle" and "attack" (see vary()).
var _idle_clip := "idle"
var _attack_clip := "attack"
var player: AnimationPlayer
var action := ""
var fighting := false
var _rest := -1.0
static var _manifests := {}
var _fall := -1.0
var _fall_dir := 1.0
var _swings := 0
var _ring: Node3D
## Seconds left before a queued attack starts (see attack_after).
var _attack_wait := -1.0
var _attack_rate := 1.0
var _model: Node3D
## Clip blends take this much longer: a long body (a wyrm) snapping from its
## winding move into a straight strike reads as a glitch.
var blend_scale := 1.0
var _flinch := -1.0
var _flinch_amp := 1.0


static func path_for(unit_id: String, dir: String = DIR) -> String:
	return dir + unit_id + ".glb"


static func exists(unit_id: String, dir: String = DIR) -> bool:
	var path := path_for(unit_id, dir)
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


## Spawns a unit, or returns null when it has no live model.
static func spawn(unit_id: String, dir: String = DIR) -> LiveUnit:
	var model := _load_model(path_for(unit_id, dir))
	if model == null:
		return null
	var unit := LiveUnit.new()
	unit.id = unit_id
	unit.name = unit_id
	unit.add_child(model)
	unit._setup(model)
	var entry: Dictionary = _manifest(dir).get(unit_id, {})
	unit.move_speed = float(entry.get("move_speed", 0.0))
	if unit.move_speed <= 0.0:
		unit.move_speed = unit.height
	unit.impact = clampf(float(entry.get("impact", 0.5)), 0.05, 0.95)
	unit.impact_alt = clampf(float(entry.get("impact_alt", unit.impact)), 0.05, 0.95)
	if unit.length > unit.width * 2.5:
		unit.blend_scale = 4.0
	return unit


static func _manifest(dir: String) -> Dictionary:
	if not _manifests.has(dir):
		var path := dir + "units3d.json"
		var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_manifests[dir] = data if data is Dictionary else {}
	return _manifests[dir]


static func _load_model(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D
	if not FileAccess.file_exists(path):
		return null
	# Not imported (tools, fresh checkouts): read the GLB directly.
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _setup(model: Node3D) -> void:
	_model = model
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for name in LOOPS:
			if player.has_animation(name):
				player.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b: AABB = _local_transform(mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	height = box.end.y
	length = box.size.x
	width = box.size.z
	radius = maxf(0.15, 0.5 * minf(box.size.x, box.size.z))
	# Bipeds: measure to the skull top, so a raised pike or staff does not count
	# (the exporter sizes the model the same way).
	for node in model.find_children("*", "Skeleton3D", true, false):
		var sk := node as Skeleton3D
		var head := sk.find_bone("mixamorig_Head")
		var neck := sk.find_bone("mixamorig_Neck")
		if head < 0 or neck < 0:
			continue
		var to_unit := _local_transform(sk)
		var h := to_unit * sk.get_bone_global_rest(head).origin
		var n := to_unit * sk.get_bone_global_rest(neck).origin
		height = minf(height, h.y + 2.0 * h.distance_to(n))
		radius = 0.17 * height
		break


func _local_transform(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != self:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func has_clip(clip: String) -> bool:
	return player != null and player.has_animation(clip)


## Lets figure number [param n] of a group stand and swing its own way: odd
## figures play the idle_alt and attack_alt variants where the unit has them,
## so a block does not breathe and strike as one.
func vary(n: int) -> void:
	var alt := n % 2 == 1
	_idle_clip = "idle_alt" if alt and has_clip("idle_alt") else "idle"
	_attack_clip = "attack_alt" if alt and has_clip("attack_alt") else "attack"


## The clip that plays for [param clip] (idle and attack may be varied).
func _clip_name(clip: String) -> String:
	if clip == "idle":
		return _idle_clip
	if clip == "attack":
		return _attack_clip
	return clip


## Draws a flat ring of [param color] round the unit's feet, which tells the
## sides apart; a clear colour removes it.
func set_ring(color: Color) -> void:
	if color.a <= 0.0:
		if _ring != null:
			_ring.queue_free()
			_ring = null
		return
	if _ring == null:
		# A faint filled disc with a bold rim, flat on the ground: thick enough
		# to read from the battle camera (a thin line is a pixel or two).
		_ring = MeshInstance3D.new()
		_ring.name = "Ring"
		_ring.position.y = 0.03
		add_child(_ring)
		# Sized from the body, not a wingspan; long bodies (serpents, wyrms)
		# get an oval along their length.
		var r := minf(radius, 0.25 * height)
		if length > 2.5 * width:
			_ring.scale.x = clampf(0.5 * length / maxf(0.1, r * 1.5), 1.0, 4.0)
		var disc := CylinderMesh.new()
		disc.top_radius = r * 1.5
		disc.bottom_radius = r * 1.5
		disc.height = 0.01
		disc.radial_segments = 32
		disc.rings = 1
		var fill := MeshInstance3D.new()
		fill.name = "Fill"
		fill.mesh = disc
		_ring.add_child(fill)
		# A winding body does not fill its oval: the rim alone says whose it is.
		fill.visible = length <= 2.5 * width
		var torus := TorusMesh.new()
		torus.outer_radius = r * 1.6
		torus.inner_radius = r * 1.3
		torus.rings = 32
		torus.ring_segments = 4
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		rim.mesh = torus
		rim.scale = Vector3(1.0, 0.05, 1.0)
		_ring.add_child(rim)
		for part in [fill, rim]:
			(part as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for part in _ring.get_children():
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = false
		mat.albedo_color = Color(color, 0.3 if part.name == "Fill" else minf(color.a, 0.85))
		(part as MeshInstance3D).material_override = mat


## Holds the current pose and starts the attack clip [param delay] seconds from
## now at [param rate], so a slow swing still lands its blow on time.
func attack_after(delay: float, rate: float) -> void:
	fighting = false
	_attack_wait = delay
	_attack_rate = rate
	set_process(true)


## True while an attack_after() is still counting down.
func attack_pending() -> bool:
	return _attack_wait >= 0.0


## Seconds into the attack clip at which the blow lands, at normal speed.
func impact_time() -> float:
	if not has_clip("attack"):
		return 0.0
	return (impact_alt if _attack_clip == "attack_alt" else impact) * player.get_animation(_attack_clip).length


## A hit lands: the body is thrown back a little and tips away from the blow
## (along -X, away from the foe it faces), then recovers, on top of whatever
## clip plays. [param strength] 1 is an ordinary blow.
func flinch(strength: float = 1.0) -> void:
	if action == "death" or _model == null:
		return
	_flinch = 0.0
	_flinch_amp = clampf(strength, 0.2, 1.6)
	set_process(true)


## Share of a full flinch [param t] seconds after the hit: thrown back fast,
## then easing back in. 0 outside the flinch.
static func flinch_curve(t: float) -> float:
	if t < 0.0 or t >= FLINCH_SECONDS:
		return 0.0
	var hit := 0.07
	if t < hit:
		return sin(t / hit * PI * 0.5)
	return pow(1.0 - (t - hit) / (FLINCH_SECONDS - hit), 2.0)


## Plays a clip (loops for idle/move). Looping clips start at a random phase
## when [param phase] is negative, so a block of units does not move in step.
func play(clip: String, speed: float = 1.0, blend: float = 0.15, phase: float = -1.0) -> void:
	fighting = false
	_attack_wait = -1.0
	_play(clip, speed, blend, phase)


## Plays the move clip at the pace of a unit moving at [param speed] m/s, so the
## feet stay planted.
func walk(speed: float) -> void:
	var rate := clampf(speed / move_speed, 0.3, 2.5)
	if action == "move" and has_clip("move"):
		player.speed_scale = rate
		return
	play("move")
	if player != null:
		player.speed_scale = rate


## Swings again and again, with short random breaths between blows, until
## play(), walk() or die() is called. Without an attack clip it holds idle.
func fight() -> void:
	if fighting:
		return
	_play("attack" if has_clip("attack") else "idle", 1.0, 0.12, -1.0)
	fighting = true
	_rest = -1.0


func _play(clip: String, speed: float, blend: float, phase: float) -> void:
	action = clip
	if player != null:
		player.speed_scale = 1.0
	if not has_clip(clip):
		if clip == "idle" and has_clip("move"):
			# No idle (some beasts): hold the first walk frame, which stands on the
			# ground; the bare rest pose of such rigs may not.
			player.play("move", blend, 0.0)
			player.seek(0.0, true)
		return
	var real := _clip_name(clip)
	player.play(real, blend * blend_scale, speed)
	if clip in LOOPS:
		var length := player.get_animation(real).length
		player.seek(length * (phase if phase >= 0.0 else fposmod(float(get_instance_id() % 997) * 0.618, 1.0)), true)


## True while a one-shot clip (attack, death) is still running.
func busy() -> bool:
	return player != null and player.is_playing() and action not in LOOPS


## Plays the death clip, or topples the model sideways when it has none.
func die(away: float = 1.0) -> void:
	fighting = false
	_attack_wait = -1.0
	if _ring != null:
		_ring.visible = false
	if has_clip("death"):
		play("death", 1.0, 0.1)
		return
	action = "death"
	if player != null:
		player.pause()
	_fall = 0.0
	_fall_dir = away


## Stands a fallen unit up again (raised from the dead) and lets it idle.
func revive() -> void:
	_fall = -1.0
	rotation.x = 0.0
	if _ring != null:
		_ring.visible = true
	set_process(true)
	play("idle", 1.0, 0.2)


func _process(delta: float) -> void:
	if _flinch >= 0.0:
		_flinch += delta
		var k := flinch_curve(_flinch) * _flinch_amp
		_model.position.x = -FLINCH_BACK * k
		_model.rotation.z = FLINCH_TILT * k
		if _flinch >= FLINCH_SECONDS:
			_flinch = -1.0
			_model.position.x = 0.0
			_model.rotation.z = 0.0
	if _attack_wait >= 0.0:
		_attack_wait -= delta
		if _attack_wait < 0.0:
			play("attack", 1.0, 0.08)
			if player != null:
				player.speed_scale = _attack_rate
		return
	if fighting and action == "attack" and not player.is_playing():
		# Between blows: a short breath on the last frame, then the next swing.
		if _rest < 0.0:
			_rest = 0.05 + 0.35 * _wobble(1)
		_rest -= delta
		if _rest <= 0.0:
			_rest = -1.0
			_swings += 1
			player.play(_attack_clip, 0.08, 0.9 + 0.25 * _wobble(2))
			player.seek(0.0, true)
		return
	if _fall < 0.0:
		return
	_fall = minf(1.0, _fall + delta / 0.5)
	rotation.x = _fall_dir * _fall * 1.4
	if _fall >= 1.0:
		set_process(false)


## A repeatable 0..1 value per unit name and swing (no RNG: purely visual, and
## the same battle replays the same).
func _wobble(salt: int) -> float:
	return fposmod(float(hash("%s:%d:%d" % [name, _swings, salt]) % 10007) / 10007.0, 1.0)
