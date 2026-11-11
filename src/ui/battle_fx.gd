class_name BattleFx
extends RefCounted
## Elemental battle effects drawn with CPU particles: chunky square "pixels"
## in a few palette colours, no textures, so they suit the pixel art and run
## on phones. Which element a creature or a log event uses comes from
## res://assets/battle_fx.json. Pure presentation: nothing here touches rules
## or GameRng; particle spread uses Godot's own particle randomness, which
## never feeds back into the game.

const PATH := "res://assets/battle_fx.json"
const ELEMENTS := ["fire", "frost", "storm", "poison", "shadow", "blast", "arcane", "holy", "life", "blood", "tide"]

## Per element: colours (bright to dark), whether particles rise (gravity
## sign), burst speed, amount and the projectile core colour.
const STYLES := {
	"fire": {"colors": ["#fff2a8", "#ffb238", "#f0561c", "#8a1a10"], "gravity": -160.0, "speed": 120.0, "amount": 34, "core": "#ffcf5a", "size": 4.0},
	"frost": {"colors": ["#ffffff", "#c8f0ff", "#6cc2ef", "#2c5f9e"], "gravity": 260.0, "speed": 190.0, "amount": 28, "core": "#d8f6ff", "size": 4.0},
	"storm": {"colors": ["#ffffff", "#e6f2ff", "#8fb8ff", "#4a58c8"], "gravity": 0.0, "speed": 260.0, "amount": 24, "core": "#e8f0ff", "size": 3.0},
	"poison": {"colors": ["#e4ff8a", "#9ee04a", "#4f9a2a", "#24521c"], "gravity": -70.0, "speed": 70.0, "amount": 30, "core": "#b6f052", "size": 5.0},
	"shadow": {"colors": ["#f0c8ff", "#b46ef0", "#6a2ab0", "#2a0f4a"], "gravity": 0.0, "speed": -90.0, "amount": 30, "core": "#c890ff", "size": 4.0},
	"blast": {"colors": ["#ffe0a0", "#c8783a", "#5a4a42", "#2a2422"], "gravity": 120.0, "speed": 210.0, "amount": 40, "core": "#3a3030", "size": 5.0},
	"arcane": {"colors": ["#ffffff", "#ffe6a8", "#e0a8ff", "#7a5ad8"], "gravity": -30.0, "speed": 140.0, "amount": 26, "core": "#ffe6c0", "size": 3.0},
	"holy": {"colors": ["#ffffff", "#fff2b8", "#f0c860", "#a87a28"], "gravity": -120.0, "speed": 50.0, "amount": 24, "core": "#fff2b8", "size": 3.0},
	"life": {"colors": ["#f4ffd0", "#b8f07a", "#5ac85a", "#2a7a3a"], "gravity": -110.0, "speed": 40.0, "amount": 20, "core": "#b8f07a", "size": 3.0},
	"blood": {"colors": ["#ffb0a0", "#e0402a", "#a01a1a", "#4a0a0e"], "gravity": 40.0, "speed": 110.0, "amount": 26, "core": "#e0402a", "size": 4.0},
	"tide": {"colors": ["#e0fff8", "#7ae0d0", "#2a9aa8", "#164a6a"], "gravity": 220.0, "speed": 170.0, "amount": 32, "core": "#9af0e0", "size": 4.0},
}

static var _table: Dictionary = {}
static var _element_cache: Dictionary = {}


static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_table = parsed if parsed is Dictionary else {"creatures": {}, "events": {}}
	return _table


## The element of a creature's attacks, or "" for a plain arrow or blow.
static func element_of(creature_id: String) -> String:
	if _element_cache.has(creature_id):
		return _element_cache[creature_id]
	var listed: Dictionary = table().get("creatures", {})
	var element := String(listed.get(creature_id, ""))
	if element == "":
		element = element_from(GameData.get_default().creature(creature_id))
	_element_cache[creature_id] = element
	return element


## Fallback element from creature data when the table does not list it.
static func element_from(c: Dictionary) -> String:
	if c.is_empty():
		return ""
	var abilities := []
	for a in c.get("abilities", []):
		abilities.append(String(a.get("id", "")) if a is Dictionary else String(a))
	if "poison" in abilities:
		return "poison"
	if "splash" in abilities:
		return "blast"
	if "caster" in c.get("tags", []):
		return "arcane"
	return ""


## The burst for a combat log entry type over its target, or "".
## Splash, cleave and breath borrow the attacker's element.
static func element_for_event(type: String, actor_creature: String = "") -> String:
	if type in ["splash", "breath"]:
		var e := element_of(actor_creature)
		return e if e != "" else "blast"
	return String(table().get("events", {}).get(type, ""))


static func style(element: String) -> Dictionary:
	return STYLES.get(element, STYLES["arcane"])


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var n := colors.size()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in n:
		offsets.append(0.85 * float(i) / float(maxi(1, n - 1)))
		cols.append(Color(colors[i]))
	g.offsets = offsets
	g.colors = cols
	# Fade out at the very end.
	g.add_point(1.0, Color(Color(colors[n - 1]), 0.0))
	return g


## A one-shot burst at `at` (in the parent's coordinates). `strength` scales
## the amount and size (1 = a normal hit). Frees itself when done.
static func burst(parent: Node, at: Vector2, element: String, strength: float = 1.0, speed_scale: float = 1.0) -> CPUParticles2D:
	var st := style(element)
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = int(clampf(float(st["amount"]) * strength * 1.3, 6.0, 120.0))
	p.lifetime = 0.7
	p.speed_scale = speed_scale
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 14.0 * strength
	var v := float(st["speed"])
	if v < 0.0:
		# Implodes: starts on a ring and is pulled to the centre.
		p.emission_sphere_radius = 34.0 * strength
		p.radial_accel_min = -260.0
		p.radial_accel_max = -180.0
		v = 10.0
	p.initial_velocity_min = v * 0.5
	p.initial_velocity_max = v
	p.gravity = Vector2(0, float(st["gravity"]))
	p.damping_min = 40.0
	p.damping_max = 90.0
	var px := float(st["size"]) * 1.25 * clampf(strength, 0.8, 1.6)
	p.scale_amount_min = px * 0.6
	p.scale_amount_max = px
	p.color_ramp = _ramp(st["colors"])
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.z_index = 5
	p.set_meta("element", element)
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	# A short flash ring under the burst for the bright elements (not for
	# the small hits, so a volley's sparks do not flash like its blast).
	if strength >= 0.6 and element in ["fire", "storm", "arcane", "holy", "blast", "frost"]:
		var flash := FxFlash.new()
		flash.position = at
		flash.color = Color(st["colors"][1])
		flash.radius = 22.0 * strength
		flash.speed = speed_scale
		parent.add_child(flash)
	return p


## Elements that leave something behind where they land, and how long it
## lasts (seconds at speed 1): embers on the grass, frost mist, motes.
const LINGER := {"fire": 2.6, "frost": 2.0, "holy": 1.6, "shadow": 1.6, "poison": 2.2, "blast": 1.8, "tide": 1.4}


## What an element leaves on the ground at `at` (feet level): a slow trickle
## of its particles for a while, so a fight keeps glowing between the big
## hits. Returns null for elements that leave nothing. Frees itself.
static func linger(parent: Node, at: Vector2, element: String, speed_scale: float = 1.0) -> CPUParticles2D:
	if not LINGER.has(element):
		return null
	var st := style(element)
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 7
	p.lifetime = 0.9
	p.speed_scale = speed_scale
	p.direction = Vector2(0, -1)
	p.spread = 20.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(16, 4)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 34.0
	# Embers and motes drift up; mist and dust settle.
	p.gravity = Vector2(0, -40.0 if float(st["gravity"]) < 0.0 else -8.0)
	var px := float(st["size"])
	p.scale_amount_min = px * 0.5
	p.scale_amount_max = px * 0.9
	p.color_ramp = _ramp(st["colors"])
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.z_index = 4
	p.set_meta("element", element)
	parent.add_child(p)
	p.emitting = true
	var tw := p.create_tween()
	tw.set_speed_scale(speed_scale)
	tw.tween_interval(float(LINGER[element]))
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(p.lifetime)
	tw.tween_callback(p.queue_free)
	return p


## A projectile for an element: a bright core with a particle trail. Move it
## by setting its position; free it when it lands.
static func projectile(element: String, speed_scale: float = 1.0) -> Node2D:
	var st := style(element)
	var root := Node2D.new()
	root.z_index = 6
	var trail := CPUParticles2D.new()
	trail.amount = 24
	trail.lifetime = 0.35
	trail.speed_scale = speed_scale
	trail.local_coords = false
	trail.spread = 180.0
	trail.initial_velocity_min = 5.0
	trail.initial_velocity_max = 25.0
	trail.gravity = Vector2(0, float(st["gravity"]) * 0.3)
	var px := float(st["size"])
	trail.scale_amount_min = px * 0.5
	trail.scale_amount_max = px
	trail.color_ramp = _ramp(st["colors"])
	root.add_child(trail)
	var core := FxFlash.new()
	core.color = Color(st["core"])
	core.radius = px * 1.4
	core.hold = true
	root.add_child(core)
	return root
