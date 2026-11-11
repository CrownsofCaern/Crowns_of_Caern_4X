class_name BattleGore
extends RefCounted
## What a creature leaves behind when it is struck or falls in the live battle
## view: a spurt on each wound, a burst and a pool on the ground where a figure
## dies, a soft shadow under every standing figure, and the poison that clings
## to a poisoned squad. The kind of gore follows the creature's tags (bleeding
## flesh, bone dust, sparks and oil, embers, sap, ichor, ice). Chunky square
## particles and hard-edged pools in the art's palette; no textures, phone
## friendly. Pure presentation: no rules, no GameRng. Visual variation comes
## from hashes of the place and the creature, so the same battle looks the
## same every time it is watched.

## Ground layers (z_index inside the battlefield): pools under the fallen,
## the fallen under the shadows, everyone standing above.
const Z_POOL := -3
const Z_FALLEN := -2
const Z_SHADOW := -1

## Per gore kind: particle colours (bright to dark), gravity, burst speed,
## pool colour ("" for none), how the body falls ("fall", "crumble", "fade",
## "topple") and the tint the fallen keep.
const KINDS := {
	"blood": {"colors": ["#ff8a78", "#d0281c", "#8a1010", "#3a0608"], "gravity": 420.0, "speed": 150.0,
		"pool": "#5a0a0c", "death": "fall", "corpse": "#6e4a44"},
	"ichor": {"colors": ["#c8ffe0", "#4ac0a0", "#1e7a6a", "#0a3a34"], "gravity": 420.0, "speed": 140.0,
		"pool": "#123e38", "death": "fall", "corpse": "#4a6460"},
	"bone": {"colors": ["#f4ecd8", "#cfc3a4", "#8e846c", "#4a4436"], "gravity": 260.0, "speed": 110.0,
		"pool": "#4a4436", "death": "crumble", "corpse": "#8a8274"},
	"sparks": {"colors": ["#fff6c0", "#ffc040", "#d06018", "#3a3030"], "gravity": 380.0, "speed": 220.0,
		"pool": "#1e1a1a", "death": "topple", "corpse": "#4e4a4a"},
	"ember": {"colors": ["#fff0a0", "#ff9a30", "#c0300c", "#2a0a06"], "gravity": -140.0, "speed": 120.0,
		"pool": "#2a0c08", "death": "fall", "corpse": "#5a3028"},
	"sap": {"colors": ["#e8f0a0", "#9ab840", "#5a6a20", "#2a2a10"], "gravity": 360.0, "speed": 120.0,
		"pool": "#2e3410", "death": "topple", "corpse": "#5a5a3a"},
	"ice": {"colors": ["#ffffff", "#d8f4ff", "#7ac0e8", "#2c5a8a"], "gravity": 380.0, "speed": 170.0,
		"pool": "#c8e4f0", "death": "crumble", "corpse": "#8aa4b4"},
	"wisp": {"colors": ["#f0e8ff", "#b8a0f0", "#6a50b0", "#20183a"], "gravity": -120.0, "speed": 80.0,
		"pool": "", "death": "fade", "corpse": "#000000"},
}

static var _kind_cache: Dictionary = {}
static var _shadow_tex: ImageTexture
static var _ring_tex: ImageTexture


## The gore kind of a creature.
static func kind_of(creature_id: String) -> String:
	if _kind_cache.has(creature_id):
		return _kind_cache[creature_id]
	var c := GameData.get_default().creature(creature_id)
	var kind := kind_from(c.get("tags", []), String(c.get("faction", "")))
	_kind_cache[creature_id] = kind
	return kind


## Gore kind from a creature's tags (and faction for the fish-folk).
static func kind_from(tags: Array, faction: String = "") -> String:
	if "spirit" in tags:
		return "wisp"
	if "undead" in tags:
		return "bone"
	if "construct" in tags or "siege" in tags:
		return "sparks"
	if "demon" in tags:
		return "ember"
	if "treant" in tags or "plant" in tags or "fungus" in tags:
		return "sap"
	if "fishmen" in tags or faction == "fishmen" or "insect" in tags:
		return "ichor"
	return "blood"


static func style(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS["blood"])


## Cheap deterministic 0..1 noise from a position and a salt.
static func noise(at: Vector2, salt: int) -> float:
	return float(posmod(hash(Vector3i(int(at.x), int(at.y), salt)), 1000)) / 999.0


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var n := colors.size()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in n:
		offsets.append(0.8 * float(i) / float(maxi(1, n - 1)))
		cols.append(Color(colors[i]))
	g.offsets = offsets
	g.colors = cols
	g.add_point(1.0, Color(Color(colors[n - 1]), 0.0))
	return g


static func _particles(parent: Node, at: Vector2, kind: String, amount: int, dir: Vector2, spread: float, speed_scale: float, size: float) -> CPUParticles2D:
	var st := style(kind)
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(2, amount)
	p.lifetime = 0.6
	p.speed_scale = speed_scale
	p.direction = dir
	p.spread = spread
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	var v := float(st["speed"])
	p.initial_velocity_min = v * 0.45
	p.initial_velocity_max = v
	p.gravity = Vector2(0, float(st["gravity"]))
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.color_ramp = _ramp(st["colors"])
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.z_index = 5
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## A small spurt where a blow lands; `dir` points the way the blow travelled.
static func spurt(parent: Node, at: Vector2, kind: String, dir: float, speed_scale: float = 1.0) -> CPUParticles2D:
	return _particles(parent, at, kind, 10, Vector2(dir, -0.6).normalized(), 40.0, speed_scale, 3.5)


## A small spurt for a swing between the logged blows: a nick, not a wound.
static func nick(parent: Node, at: Vector2, kind: String, dir: float, speed_scale: float = 1.0) -> CPUParticles2D:
	return _particles(parent, at, kind, 5, Vector2(dir, -0.7).normalized(), 35.0, speed_scale, 3.0)


## Where two lines crash together: steel sparks flying up and out between
## the fronts, and dust kicked up both ways. `heavy` (0..1) for a charge or
## a big creature. Returns the sparks.
static func contact(parent: Node, at: Vector2, heavy: float, speed_scale: float = 1.0) -> CPUParticles2D:
	var p := _particles(parent, at, "sparks", int(8.0 + heavy * 12.0), Vector2(0, -1), 75.0, speed_scale, 3.0 + heavy * 1.5)
	p.initial_velocity_max *= 1.0 + heavy * 0.4
	p.lifetime = 0.45
	dust(parent, at + Vector2(0, 26), 1.0, speed_scale)
	dust(parent, at + Vector2(0, 26), -1.0, speed_scale)
	return p


## The burst of a figure falling: a bigger spray thrown away from the killer.
static func death_burst(parent: Node, at: Vector2, kind: String, dir: float, speed_scale: float = 1.0) -> CPUParticles2D:
	return _particles(parent, at, kind, 22, Vector2(dir, -1.0).normalized(), 70.0, speed_scale, 4.5)


## A pool or stain on the ground where a figure fell; grows in, then stays.
## Returns null for kinds that leave nothing (spirits).
static func pool(parent: Node, at: Vector2, kind: String, width: float, speed_scale: float = 1.0) -> Node2D:
	var st := style(kind)
	if String(st["pool"]) == "":
		return null
	var root := Node2D.new()
	root.position = at
	root.z_index = Z_POOL
	var col := Color(String(st["pool"]))
	col.a = 0.62
	var main := Polygon2D.new()
	main.color = col
	main.polygon = blob(at, width * 0.36, width * 0.13, 14)
	root.add_child(main)
	# A few droplets beside the pool.
	for k in 4:
		var d := Polygon2D.new()
		d.color = col
		var r := 1.5 + noise(at, 40 + k) * 2.0
		var off := Vector2((noise(at, 50 + k) - 0.5) * width * 0.9, (noise(at, 60 + k) - 0.5) * width * 0.3)
		d.polygon = PackedVector2Array([off + Vector2(-r, -r * 0.5), off + Vector2(r, -r * 0.5), off + Vector2(r, r * 0.5), off + Vector2(-r, r * 0.5)])
		root.add_child(d)
	parent.add_child(root)
	root.scale = Vector2(0.2, 0.2)
	var tw := root.create_tween()
	tw.set_speed_scale(speed_scale)
	tw.tween_property(root, "scale", Vector2.ONE, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return root


## A ragged ellipse outline (hashed, so stable for a place).
static func blob(seed_at: Vector2, rx: float, ry: float, points: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points:
		var a := TAU * float(i) / float(points)
		var wobble := 0.7 + noise(seed_at, i) * 0.5
		# Pixel art: snap the outline to whole pixels.
		out.append(Vector2(roundf(cos(a) * rx * wobble), roundf(sin(a) * ry * wobble)))
	return out


## Poison clinging to a figure: green bubbles rising for a while.
static func poison_cloud(parent: Node, at: Vector2, speed_scale: float = 1.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.0
	p.amount = 14
	p.lifetime = 0.9
	p.speed_scale = speed_scale
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(14, 10)
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 40.0
	p.gravity = Vector2(0, -20)
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.0
	p.color_ramp = _ramp(["#e4ff8a", "#9ee04a", "#4f9a2a", "#24521c"])
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.z_index = 5
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Dust kicked up at the feet of a charging figure.
static func dust(parent: Node, at: Vector2, dir: float, speed_scale: float = 1.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = 8
	p.lifetime = 0.55
	p.speed_scale = speed_scale
	p.direction = Vector2(-dir, -0.35).normalized()
	p.spread = 35.0
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 60.0
	p.gravity = Vector2(0, -12)
	p.damping_min = 30.0
	p.damping_max = 60.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color_ramp = _ramp(["#b8a888", "#8a7a60", "#5a4e3e"])
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.z_index = Z_SHADOW
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## A soft, pixel-stepped oval shadow, white so it can be tinted; shared.
static func shadow_texture() -> ImageTexture:
	if _shadow_tex != null:
		return _shadow_tex
	var w := 32
	var h := 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (float(x) + 0.5 - w * 0.5) / (w * 0.5)
			var dy := (float(y) + 0.5 - h * 0.5) / (h * 0.5)
			var d := dx * dx + dy * dy
			var a := 0.0
			if d < 0.45:
				a = 0.5
			elif d < 1.0:
				a = 0.28
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_shadow_tex = ImageTexture.create_from_image(img)
	return _shadow_tex


## The shadow under one figure `width` pixels wide.
static func shadow(width: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = shadow_texture()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.modulate = Color(0.04, 0.02, 0.03, 0.9)
	var k := maxf(0.6, width / 32.0)
	s.scale = Vector2(k, k * 0.9)
	s.z_index = Z_SHADOW
	return s


## A thin oval ring in a side's colour under one figure, so the sides read
## apart in a melee. Invisible when `color` is clear.
static func ring(width: float, color: Color) -> Sprite2D:
	if _ring_tex == null:
		var w := 32
		var h := 12
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var dx := (float(x) + 0.5 - w * 0.5) / (w * 0.5)
				var dy := (float(y) + 0.5 - h * 0.5) / (h * 0.5)
				var d := dx * dx + dy * dy
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if d < 1.0 and d > 0.55 else 0.0))
		_ring_tex = ImageTexture.create_from_image(img)
	var s := Sprite2D.new()
	s.texture = _ring_tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.modulate = Color(color, color.a * 0.55)
	s.visible = color.a > 0.0
	var k := maxf(0.6, width / 32.0)
	s.scale = Vector2(k, k * 0.9)
	s.z_index = Z_SHADOW
	return s
