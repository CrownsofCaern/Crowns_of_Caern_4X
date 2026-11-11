class_name BattleFigure
extends Node2D
## One creature stack on the live battlefield, shown as a battalion of up to
## MAX_MEMBERS figures (fewer for big creatures, see squad_size) plus a badge
## with the real creature count. The node stays where the stack formed up;
## every figure walks on its own (its own start, pace and stride), so a
## battalion can split into groups that fight different enemies. As the stack
## loses creatures, figures fall in proportion (the viewer says which ones, so
## the fallen lie where their killers struck); heals and rebirth raise them.
## Each figure plays the creature's drawn clips when it has them (idle, move,
## attack and, once drawn, death), otherwise its still sprite with simple
## placeholder motion. BattleViewer drives it; time runs at the viewer's
## playback speed.
##
## On a 3D stage (`stage` set before setup) each figure with a live model
## (LiveUnit, assets/units3d) is mirrored by a 3D unit standing where the
## camera shows the figure's feet; the 2D sprite stays as the invisible clock
## that drives it. Creatures without a model keep their sprite.

const SCALE := 0.85
const LUNGE_SECONDS := 0.3
const LUNGE_PX := 16.0
const MAX_MEMBERS := 9
## A squad shows about this many hit points per figure, so a horde of small
## creatures fills a block and a giant stands alone.
const HP_PER_SQUAD := 260.0
const FALLEN_COLOR := Color(0.56, 0.46, 0.42, 0.78)
## Walking pace of a figure in pixels per second (before its own pace).
const WALK_PX := 165.0
## How fast a figure gets up to pace and slows down (px per second squared).
const ACCEL := 520.0
const DIE_SECONDS := 0.5
## How often fighters locked in melee swing between the logged blows
## (1 = about one swing every 1.1 to 2.7 seconds).
const SWING_RATE := 1.8
## 3D figures longer or wider than this (metres) face only left or right.
const BROADSIDE_M := 2.4
## How long a shoved figure takes to give ground and step back in.
const SHOVE_SECONDS := 0.5

## A swing between the logged blows (a brawl) reached its blow; the viewer
## shows it landing on whoever this figure is locked with.
signal brawl_hit(fig: BattleFigure, i: int)

var key := ""
var creature_id := ""
var veteran_level := 1
var facing := 1.0          # +1 looks right, -1 looks left (towards the enemy)
## Centre of the battalion's formation, in field coordinates.
var home := Vector2.ZERO
var count := 0
var start_count := 0
var speed := 1.0
var has_move := false
var has_attack := false
## Drawn idle loop (from the idle sheets); without one the still breathes.
var has_idle := false
## Drawn death clip; without one the figure falls in code (see BattleGore).
var has_death := false
## Element of this creature's attacks (BattleFx), "" for plain blows.
var element := ""
## What it bleeds (BattleGore kind).
var gore := "blood"
## Width of one figure on screen, for spacing and shadows.
var figure_width := 40.0
## How the battalion forms up: "front" (a line), "flank" (a wedge),
## "back" (a loose skirmish line) or "support" (a cluster).
var formation := "front"
## Most room the formation may take up and down the field, in pixels.
var span_y := 160.0
## The army's battle formation shaping this block (BattleOrders formation):
## "wall" (one tight, shoulder-to-shoulder line), "wedge" (an arrowhead,
## the point towards the enemy) or "" (as the battalion's role says).
var shape := ""
## Colour of the ring under each figure that tells the sides apart, or clear.
var side_color := Color(0, 0, 0, 0)
## The 3D battlefield to mirror the figures on, or null for plain 2D.
var stage: BattleStage3D
## Per figure: its LiveUnit on the stage, or null (2D sprite).
var _live: Array = []
## Per figure: clip speed (before the viewer's speed) of what its LiveUnit plays.
var _live_rate: Array[float] = []
## Faction ultimate treatment on every standing figure (UltimateCreatureArt), or null.
var _glow: ShaderMaterial

## The lead figure (members[0]); kept for callers that look at one sprite.
var sprite: AnimatedSprite2D
## Every figure of the squad, lead first.
var members: Array[AnimatedSprite2D] = []
var _holders: Array[Node2D] = []   # per-figure place, local to this node
var _shadows: Array[Sprite2D] = []
var _rings: Array[Sprite2D] = []
var _member_scale := SCALE
var _badge: Label
var _t := 0.0
var _phase := 0.0

# Per figure:
var _alive: Array[bool] = []
var _goal: Array[Vector2] = []     # where it walks to (local)
var _delay: Array[float] = []      # seconds before it sets off
var _pace: Array[float] = []       # its own walking pace (x WALK_PX)
var _look: Array[float] = []       # where it faces when it stands
var _moving: Array[bool] = []
var _atk_wait: Array[float] = []   # seconds until its attack starts, < 0 none
var _atk_t: Array[float] = []      # attack clock (lean / lunge), < 0 none
var _hurt: Array[float] = []
var _flash: Array[float] = []
var _die_t: Array[float] = []      # death clock, < 0 when not dying
var _die_dir: Array[float] = []    # the way it is thrown when it falls
var _rise_t: Array[float] = []     # raised from the dead, < 0 otherwise
var _vel: Array[Vector2] = []      # walking velocity (local)
var _brawl: Array[bool] = []       # locked in a melee: swings between blows
var _brawl_t: Array[float] = []    # seconds until its next swing
var _swing_brawl: Array[bool] = [] # the running attack is a brawl swing
var _rush: Array[float] = []       # pace boost while charging (1 = none)
## figure -> its place (field) in its army's melee block, see BattleViewer.
var block_spots: Dictionary = {}
var _aim: Array[Vector2] = []      # the foe it squares up to in a melee (field), ZERO none
var _shove_t: Array[float] = []    # shove clock, < 0 none
var _shove_px: Array[float] = []   # how far (and which way) it is shoved
var _impact := 0.0
var _total := 0.0
var _badge_at := Vector2.ZERO


## Figures a stack of `n` creatures of this kind shows at full strength.
static func squad_size(id: String, n: int) -> int:
	if n <= 1:
		return 1
	var c := GameData.get_default().creature(id)
	var hp := float(c.get("hp", HP_PER_SQUAD)) if not c.is_empty() else HP_PER_SQUAD
	return clampi(mini(n, int(round(HP_PER_SQUAD / maxf(1.0, hp)))), 1, MAX_MEMBERS)


## Standing figures for `n` of `start` creatures: in proportion, at least one
## while any creature lives.
static func standing(n: int, start: int, size: int) -> int:
	if n <= 0:
		return 0
	return clampi(int(ceil(float(n) / maxf(1.0, float(start)) * size)), 1, size)


## Deterministic 0..1 jitter for figure `i` of stack `k` (visual only).
static func jitter(k: String, i: int, salt: int) -> float:
	return float(posmod(hash("%s/%d/%d" % [k, i, salt]), 1000)) / 999.0


## upgraded: the stack fights with its faction's ultimate upgrade, so its
## figures wear the faction's ultimate shader.
func setup(id: String, n: int, face: float, phase: float, upgraded: bool = false, level: int = 1) -> void:
	veteran_level = level
	creature_id = id
	element = BattleFx.element_of(id)
	gore = BattleGore.kind_of(id)
	if upgraded:
		_glow = UltimateCreatureArt.material_for(String(GameData.get_default().creature(id).get("faction", "")))
	facing = face
	_phase = phase
	start_count = n
	y_sort_enabled = true
	var frames := _make_frames(id)
	has_move = not CreatureAnims.frames(id, "move", veteran_level).is_empty()
	has_attack = not CreatureAnims.frames(id, "attack", veteran_level).is_empty()
	has_idle = veteran_level < 5 and not CreatureAnims.frames(id, "idle").is_empty()
	has_death = not CreatureAnims.frames(id, "death", veteran_level).is_empty()
	var timing := CreatureAnims.attack_timing(id, veteran_level) if has_attack else [LUNGE_SECONDS * 0.5, LUNGE_SECONDS]
	_impact = float(timing[0])
	_total = float(timing[1])
	var size := squad_size(id, n)
	_member_scale = SCALE * (1.0 if size == 1 else (0.74 if size <= 4 else 0.64))
	figure_width = _still_width(id) * _member_scale
	for i in size:
		var holder := Node2D.new()
		holder.y_sort_enabled = true
		holder.position = _slot(i, size)
		add_child(holder)
		_holders.append(holder)
		var sh := BattleGore.shadow(figure_width * 0.8)
		holder.add_child(sh)
		_shadows.append(sh)
		var ring := BattleGore.ring(figure_width * 0.8, side_color)
		holder.add_child(ring)
		_rings.append(ring)
		var s := AnimatedSprite2D.new()
		s.sprite_frames = frames
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.animation_changed.connect(_sync_frame_anchor.bind(s))
		s.animation_finished.connect(_on_animation_finished.bind(s))
		holder.add_child(s)
		members.append(s)
		s.play("idle")
		# Squad members breathe out of step.
		s.frame = (i * 2 + int(phase)) % maxi(1, s.sprite_frames.get_frame_count("idle"))
		_sync_frame_anchor(s)
		_alive.append(true)
		_goal.append(holder.position)
		_delay.append(0.0)
		_pace.append(0.85 + jitter(key, i, 1) * 0.35)
		_look.append(face)
		_moving.append(false)
		_atk_wait.append(-1.0)
		_atk_t.append(-1.0)
		_hurt.append(0.0)
		_flash.append(0.0)
		_die_t.append(-1.0)
		_die_dir.append(0.0)
		_rise_t.append(-1.0)
		_vel.append(Vector2.ZERO)
		_brawl.append(false)
		_brawl_t.append((0.6 + jitter(key, i, 31) * 1.4) / SWING_RATE)
		_swing_brawl.append(false)
		_aim.append(Vector2.ZERO)
		_rush.append(1.0)
		_shove_t.append(-1.0)
		_shove_px.append(0.0)
		_live.append(_spawn_live(s, i))
		_live_rate.append(1.0)
		if _live[i] != null:
			# The model casts its own shadow; the sides stand apart on the field.
			sh.visible = false
			ring.visible = false
	sprite = members[0]
	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 14)
	_badge.add_theme_color_override("font_color", UiStyle.TEXT)
	_badge.add_theme_color_override("font_outline_color", Color.BLACK)
	_badge.add_theme_constant_override("outline_size", 5)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.size = Vector2(60, 20)
	_badge.z_index = 20   # above the stack standing in front
	add_child(_badge)
	set_count(n)
	_badge_at = _lead_local()
	_badge.position = _badge_at + Vector2(-30, -2)
	face_forward()


func _spawn_live(s: AnimatedSprite2D, i: int) -> LiveUnit:
	if stage == null or not LiveUnit.exists(creature_id):
		return null
	var u := LiveUnit.spawn(creature_id)
	if u == null:
		return null
	u.name = "%s_%d" % [key.replace(":", "_"), i]
	u.scale = Vector3.ONE * BattleStage3D.size_factor(u.height)
	stage.units.add_child(u)
	stage.dress(u)
	u.vary(i)
	u.play("idle", 1.0, 0.0, jitter(key, i, 9))
	u.set_ring(side_color)
	# The sprite keeps time and anchors the overlays; the model is what shows.
	s.self_modulate = Color(1, 1, 1, 0)
	return u


## The figure's LiveUnit, or null when it is drawn as a sprite.
func live_unit(i: int) -> LiveUnit:
	return _live[i] if i >= 0 and i < _live.size() else null


## Width of the creature's still sprite in pixels (opaque part), cached.
static var _width_cache: Dictionary = {}
static func _still_width(id: String) -> float:
	if _width_cache.has(id):
		return _width_cache[id]
	var w := 60.0
	var tex := Art.creature(id)
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			w = clampf(float(img.get_used_rect().size.x), 24.0, 200.0)
	_width_cache[id] = w
	return w


func _make_frames(id: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	var still := Art.creature(id, veteran_level)
	var idle_poses: Array = CreatureAnims.frames(id, "idle") if veteran_level < 5 else []
	if not idle_poses.is_empty():
		frames.set_animation_speed("idle", CreatureAnims.FPS)
		frames.set_animation_loop("idle", true)
		var idle_ms := CreatureAnims.durations_ms(id, "idle")
		for index in idle_poses.size():
			var weight := float(idle_ms[index]) * CreatureAnims.FPS / 1000.0 if index < idle_ms.size() else 1.0
			frames.add_frame("idle", idle_poses[index], weight)
	elif still != null:
		frames.add_frame("idle", still)
	for kind in CreatureAnims.KINDS + ["death"]:
		var strip := CreatureAnims.frames(id, kind, veteran_level)
		if kind == "death" and strip.is_empty():
			continue
		frames.add_animation(kind)
		frames.set_animation_speed(kind, CreatureAnims.FPS)
		frames.set_animation_loop(kind, kind == "move")
		var poses: Array = strip if not strip.is_empty() else ([still] if still != null else [])
		var durations := CreatureAnims.durations_ms(id, kind, veteran_level)
		for index in poses.size():
			var weight := float(durations[index]) * CreatureAnims.FPS / 1000.0 if index < durations.size() else 1.0
			frames.add_frame(kind, poses[index], weight)
	return frames


## Place of figure i in a block of `size` around the formation centre:
## ranks of three, deeper ranks behind (away from the enemy), every other
## rank shifted half a step.
func _slot(i: int, size: int) -> Vector2:
	if size == 1:
		return Vector2.ZERO
	var dx := maxf(30.0, figure_width * 0.95) * _spread().x
	var dy := maxf(22.0, figure_width * 0.55) * _spread().y
	var fit := maxi(1, int(span_y / dy) + 1)
	var per_rank: int
	var stagger := 0.5
	match formation:
		"front":
			# A line facing the enemy, two or three deep.
			per_rank = clampi(int(ceil(size / 2.0)), 1, mini(5, fit))
			stagger = 0.0
		"back":
			# A loose skirmish line: wider gaps.
			dy *= 1.35
			dx *= 1.15
			fit = maxi(1, int(span_y / dy) + 1)
			per_rank = clampi(int(ceil(size / 2.0)), 1, mini(5, fit))
		"flank":
			# A wedge: the point leads.
			per_rank = mini(2, fit)
		_:
			per_rank = mini(3 if size > 4 else 2, fit)
	if shape == "wedge":
		return _wedge_slot(i, dx, dy)
	if shape == "wall":
		# Shoulder to shoulder: as wide as the ground allows, shallow ranks.
		dy *= 0.72
		fit = maxi(1, int(span_y / dy) + 1)
		per_rank = clampi(size, 1, fit)
		stagger = 0.0
	var rank := i / per_rank
	var file := i % per_rank
	var in_rank := mini(per_rank, size - rank * per_rank)
	var y := (file - (in_rank - 1) * 0.5) * dy + (dy * stagger if rank % 2 == 1 else 0.0)
	var x := rank * dx * (0.6 if shape == "wall" else 1.0)
	if formation == "flank":
		x += absf(file - (in_rank - 1) * 0.5) * dx * 0.5
	# A little unevenness, never ahead of the front rank.
	return Vector2(-facing * (x + jitter(key, i, 7) * 6.0), y + (jitter(key, i, 8) - 0.5) * 8.0)


## Arrowhead: one figure at the point, then ranks of 2, 3, ... widening
## behind it.
func _wedge_slot(i: int, dx: float, dy: float) -> Vector2:
	var rank := 0
	var first := 0
	while first + rank + 1 <= i:
		first += rank + 1
		rank += 1
	var file := i - first
	var y := (file - rank * 0.5) * dy
	var x := rank * dx * 0.75
	return Vector2(-facing * (x + jitter(key, i, 7) * 4.0), y + (jitter(key, i, 8) - 0.5) * 6.0)


## Extra room between figures on the 3D stage: models fill their footprint
## more than sprites do, so blocks read crowded at sprite spacing. Ranks
## sideways and files (front to back) both open up.
func _spread() -> Vector2:
	return Vector2(1.45, 1.8) if stage != null else Vector2.ONE


## Positions for `n` figures fighting around `centre` (field coordinates),
## facing `dir`: a little column, the first figure in front.
func group_spots(n: int, centre: Vector2, dir: float) -> Array:
	var out := []
	var per_rank := 1 if n <= 1 else (2 if n <= 4 else 3)
	var dx := maxf(28.0, figure_width * 0.85) * _spread().x
	var dy := maxf(22.0, figure_width * 0.6) * _spread().y
	var ranks := int(ceil(float(n) / per_rank))
	for k in n:
		var rank := k / per_rank
		var file := k % per_rank
		var in_rank := mini(per_rank, n - rank * per_rank)
		var y := (file - (in_rank - 1) * 0.5) * dy
		var x := -dir * (rank - (ranks - 1) * 0.0) * dx
		out.append(centre + Vector2(x, y) + Vector2(jitter(key, k, 11) - 0.5, jitter(key, k, 12) - 0.5) * 10.0)
	return out


func face(dir: float) -> void:
	for i in members.size():
		_look[i] = dir
		if _alive[i] and not _moving[i]:
			_face_member(i, dir)


## The way figure i faces along x: 1 right, -1 left.
func facing_of(i: int) -> float:
	return signf(members[i].scale.x) if members[i].scale.x != 0.0 else facing


func _face_member(i: int, dir: float) -> void:
	members[i].scale = Vector2(_member_scale * signf(dir), _member_scale)


func face_forward() -> void:
	face(facing)


func set_speed(s: float) -> void:
	speed = s
	for m in members:
		m.speed_scale = s


# --------------------------------------------------------------- figures ---

## Indices of the figures still standing.
func alive_members() -> Array:
	var out := []
	for i in members.size():
		if _alive[i]:
			out.append(i)
	return out


## Figures still standing.
func standing_count() -> int:
	var n := 0
	for a in _alive:
		if a:
			n += 1
	return n


func is_member_alive(i: int) -> bool:
	return i >= 0 and i < _alive.size() and _alive[i]


## Feet of figure i in field coordinates.
func member_pos(i: int) -> Vector2:
	return position + _holders[i].position


## Puts figure i at `at` (field) at once, facing `look`.
func place_member(i: int, at: Vector2, look: float) -> void:
	_holders[i].position = at - position
	_goal[i] = at - position
	_look[i] = look
	_vel[i] = Vector2.ZERO
	_moving[i] = false
	_face_member(i, look)


## Where figure i is going (field coordinates): its place once it stops.
func member_goal(i: int) -> Vector2:
	return position + _goal[i]


## Half the 3D body's length (along where it faces) and half its width, in
## field pixels; a circle of member_radius() for figures drawn as sprites.
func member_extent(i: int) -> Vector2:
	var u := live_unit(i)
	if u == null or stage == null:
		return Vector2.ONE * member_radius()
	var mpp := maxf(0.001, stage.metres_per_pixel(member_pos(i)))
	var k := u.scale.x / mpp * 0.5
	return Vector2(maxf(u.length, u.width) * k, minf(u.length, u.width) * k)


## Chest of figure i in field coordinates.
func member_chest(i: int) -> Vector2:
	var u := live_unit(i)
	if u != null and u.is_inside_tree():
		return stage.camera.unproject_position(u.position + Vector3.UP * u.height * u.scale.y * 0.55)
	return member_pos(i) + Vector2(0, -CreatureAnims.FRAME * _member_scale * 0.45)


## Middle of some figures' feet (field coordinates).
func centroid(ids: Array) -> Vector2:
	if ids.is_empty():
		return member_pos(_lead())
	var c := Vector2.ZERO
	for i in ids:
		c += member_pos(i)
	return c / float(ids.size())


## Sends figure i to `to` (field coordinates), setting off after `delay`
## seconds; it faces `look` once there. `rush` speeds up its pace for this
## run (a charge).
func send(i: int, to: Vector2, look: float, delay: float = 0.0, rush: float = 1.0) -> void:
	_goal[i] = to - position
	_look[i] = look
	_delay[i] = delay
	_rush[i] = rush
	_aim[i] = Vector2.ZERO
	if _holders[i].position.distance_to(_goal[i]) <= 1.5:
		_face_member(i, look)


## Seconds (at speed 1) until the last standing figure among `ids` reaches
## its place, counting its wait to set off.
func eta(ids: Array) -> float:
	var worst := 0.0
	for i in ids:
		if not _alive[i]:
			continue
		var dist := _holders[i].position.distance_to(_goal[i])
		if dist <= 2.0:
			continue
		worst = maxf(worst, maxf(0.0, _delay[i]) + dist / (WALK_PX * _pace[i] * _rush[i]))
	return worst


## Moves figure i and its goal by `by` (field pixels): room-making between
## figures that crowd each other.
func nudge(i: int, by: Vector2) -> void:
	_holders[i].position += by
	_goal[i] += by


## Figures `ids` give ground for a moment: thrown `px` pixels along x (sign
## is the way) and stepping back in, as when a charge hits home.
func shove(ids: Array, px: float) -> void:
	for i in ids:
		if _alive[i]:
			_shove_t[i] = 0.0
			_shove_px[i] = px * (0.7 + jitter(key, i, 41) * 0.6)


## Offset of a shoved figure `t` seconds after the shove, as a share of the
## shove: thrown back fast, then stepping in again. 0 outside the shove.
static func shove_curve(t: float) -> float:
	if t < 0.0 or t >= SHOVE_SECONDS:
		return 0.0
	var hit := 0.09
	if t < hit:
		return sin(t / hit * PI * 0.5)
	return pow(1.0 - (t - hit) / (SHOVE_SECONDS - hit), 2.0)


## Seconds (at speed 1) from the start of an attack to its blow.
func impact_seconds() -> float:
	return _impact


## Figure i's radius on the ground (field pixels), for keeping room.
func member_radius() -> float:
	return figure_width * 0.5


## True when the standing figures among `ids` have reached their places.
func arrived(ids: Array) -> bool:
	for i in ids:
		if _alive[i] and _holders[i].position.distance_to(_goal[i]) > 2.0:
			return false
	return true


## Back into formation around `home`; each figure sets off a little apart,
## at `pace` times its own walk (a slow, steady march below 1), after `wait`
## seconds.
func form_up(stagger: float = 0.3, pace: float = 1.0, wait: float = 0.0) -> void:
	var size := members.size()
	for i in size:
		_brawl[i] = false
		if _alive[i]:
			var to: Vector2 = block_spots[i] if block_spots.has(i) else home + _slot(i, size)
			send(i, to, facing, wait + jitter(key, i, 3) * stagger, pace)


## Figure i squares up to a foe standing `dir` away (field direction): it
## faces that way while it stands and fights.
func aim_member(i: int, dir: Vector2) -> void:
	if dir.length() < 0.001:
		return
	var ext := member_extent(i)
	var u := live_unit(i)
	var big := u != null and maxf(u.length, u.width) * u.scale.x > BROADSIDE_M
	if (big or ext.x > ext.y * BattleDirector.LONG) and absf(dir.x) > 0.001:
		# A long body (a wyrm) or a big beast (a drake's wingspan) fights
		# broadside to the camera: it turns along the line towards its foe,
		# never end-on into the screen.
		dir = Vector2(signf(dir.x), 0.0)
	_aim[i] = dir.normalized()
	if absf(dir.x) > 0.5:
		_look[i] = signf(dir.x)
		if not _moving[i] and _atk_t[i] < 0.0:
			_face_member(i, _look[i])


## True when figure i is locked in a melee.
func is_brawling(i: int) -> bool:
	return _brawl[i]


## True while figure i plays a logged blow (or waits to start one).
func is_striking(i: int) -> bool:
	return (_atk_t[i] >= 0.0 or _atk_wait[i] >= 0.0) and not _swing_brawl[i]


## True while figure i walks or waits to set off.
func is_moving(i: int) -> bool:
	return _moving[i] or _holders[i].position.distance_to(_goal[i]) > 2.0


## Figures `ids` are locked in a melee (they swing now and then between
## their real blows) or are no longer.
func set_brawling(ids: Array, on: bool) -> void:
	for i in ids:
		_brawl[i] = on


func stop_brawling() -> void:
	for i in members.size():
		_brawl[i] = false


## Puts every figure on its place at once (skipping to the end).
func snap() -> void:
	for i in members.size():
		_holders[i].position = _goal[i]
		_vel[i] = Vector2.ZERO
		_brawl[i] = false
		_delay[i] = 0.0
		_rush[i] = 1.0
		_shove_t[i] = -1.0
		if _moving[i]:
			_moving[i] = false
			if _alive[i]:
				members[i].play("idle")
		if _alive[i]:
			_face_member(i, _look[i])
		_sync_live(i)


func set_count(n: int) -> void:
	apply_count(n, [], 0.0, false)


## Shows `n` creatures. Figures that fall are taken from `prefer` first (the
## ones the blow landed on), then from the back of the block; risen figures
## stand up again. With `animate` the fallen are thrown towards `dir` and
## fall over, otherwise they lie down at once. Returns the figures that fell.
func apply_count(n: int, prefer: Array = [], dir: float = 0.0, animate: bool = true) -> Array:
	count = n
	_badge.text = str(n) if n > 0 else ""
	var want := standing(n, start_count, members.size())
	var up := standing_count()
	var fell := []
	if want < up:
		var order := []
		for i in prefer:
			if _alive[i] and not order.has(i):
				order.append(i)
		for i in range(members.size() - 1, -1, -1):
			if _alive[i] and not order.has(i):
				order.append(i)
		for k in up - want:
			fell.append(order[k])
		for i in fell:
			_alive[i] = false
			_fall(i, dir if dir != 0.0 else -_look[i], animate)
	elif want > up:
		var raised := 0
		for i in members.size():
			if raised >= want - up:
				break
			if not _alive[i]:
				_alive[i] = true
				_raise(i, animate)
				raised += 1
	for i in members.size():
		members[i].material = _glow if _alive[i] else null
	return fell


func _fall(i: int, dir: float, animate: bool) -> void:
	var m := members[i]
	_moving[i] = false
	_atk_wait[i] = -1.0
	_atk_t[i] = -1.0
	_shadows[i].visible = false
	_rings[i].visible = false
	_brawl[i] = false
	_shove_t[i] = -1.0
	_rush[i] = 1.0
	_vel[i] = Vector2.ZERO
	_die_dir[i] = signf(dir) if dir != 0.0 else 1.0
	_goal[i] = _holders[i].position
	_live_fall(i, animate)
	if animate:
		_die_t[i] = 0.0
		if has_death:
			m.play("death")
		else:
			m.play("idle")
			m.stop()
		return
	_die_t[i] = -1.0
	m.play("death" if has_death else "idle")
	_lie_down(i)


## The final pose of a fallen figure.
func _lie_down(i: int) -> void:
	var m := members[i]
	var style := String(BattleGore.style(gore)["death"])
	m.z_index = BattleGore.Z_FALLEN
	m.skew = 0.0
	m.position = Vector2.ZERO
	if has_death:
		m.animation = &"death"
		m.stop()
		m.frame = m.sprite_frames.get_frame_count("death") - 1
		m.rotation = 0.0
		m.modulate = FALLEN_COLOR
		return
	m.stop()
	m.frame = 0
	match style:
		"crumble":
			m.rotation = 0.0
			m.scale = Vector2(_member_scale * signf(m.scale.x), _member_scale * 0.28)
			m.modulate = Color(String(BattleGore.style(gore)["corpse"]), 0.85)
		"fade":
			m.rotation = 0.0
			m.modulate = Color(1, 1, 1, 0)
		"topple":
			m.rotation = _die_dir[i] * 1.45
			m.modulate = FALLEN_COLOR
			m.scale = Vector2(_member_scale * signf(m.scale.x), _member_scale) * 0.85
		_:
			m.rotation = _die_dir[i] * 1.35
			m.modulate = FALLEN_COLOR
			m.scale = Vector2(_member_scale * signf(m.scale.x), _member_scale) * 0.85
	if style == "fade":
		m.visible = false
		if live_unit(i) != null:
			live_unit(i).visible = false


func _raise(i: int, animate: bool) -> void:
	var m := members[i]
	_die_t[i] = -1.0
	m.visible = true
	m.z_index = 0
	m.skew = 0.0
	m.scale = Vector2(_member_scale * signf(_look[i]), _member_scale)
	m.play("idle")
	_shadows[i].visible = live_unit(i) == null
	_rings[i].visible = side_color.a > 0.0 and live_unit(i) == null
	if live_unit(i) != null:
		live_unit(i).visible = true
		live_unit(i).revive()
	if animate:
		_rise_t[i] = 0.0
	else:
		_rise_t[i] = -1.0
		m.rotation = 0.0
		m.modulate = Color.WHITE


func is_dead() -> bool:
	return count <= 0


## Every standing figure walks (or stands); used when the lines close.
func set_walking(on: bool) -> void:
	for i in members.size():
		if not _alive[i]:
			continue
		if on and has_move:
			members[i].play("move")
		elif not on and members[i].animation == "move":
			_moving[i] = false
			members[i].play("idle")


## Starts the attack of `ids` (every standing figure when empty), each a
## moment apart; returns [seconds until the first blows land, total seconds],
## both at speed 1.
func start_attack(ids: Array = []) -> Array:
	var who := ids if not ids.is_empty() else alive_members()
	if who.is_empty() and not members.is_empty():
		who = [0]
	var timing := CreatureAnims.attack_timing(creature_id, veteran_level) if has_attack else [LUNGE_SECONDS * 0.5, LUNGE_SECONDS]
	_impact = float(timing[0])
	_total = float(timing[1])
	for k in who.size():
		var i: int = who[k]
		_atk_wait[i] = 0.0 if k == 0 else jitter(key, i, int(_t * 10.0)) * 0.14
		_swing_brawl[i] = false
	return timing


func hurt(ids: Array = []) -> void:
	for i in (ids if not ids.is_empty() else alive_members()):
		_hurt[i] = 1.0
		_flash[i] = 1.0
		var u := live_unit(i)
		if u != null and _alive[i]:
			u.flinch(1.0)


## Chest height in field coordinates (the lead standing figure).
func chest() -> Vector2:
	return member_chest(_lead())


func _lead() -> int:
	for i in members.size():
		if _alive[i]:
			return i
	return 0


func _lead_local() -> Vector2:
	return _holders[_lead()].position


func _on_animation_finished(s: AnimatedSprite2D) -> void:
	if s.animation == "attack":
		var i := members.find(s)
		s.play("move" if i >= 0 and _moving[i] and has_move else "idle")


func _process(delta: float) -> void:
	var dt := delta * speed
	_t += dt
	for i in members.size():
		_step_member(i, dt)
	if count > 0:
		_badge_at = _badge_at.lerp(_lead_local(), minf(1.0, dt * 6.0))
		_badge.position = _badge_at + Vector2(-30, -2)


func _step_member(i: int, dt: float) -> void:
	var m := members[i]
	var holder := _holders[i]
	if _die_t[i] >= 0.0:
		_die_t[i] += dt
		_animate_death(i, minf(1.0, _die_t[i] / DIE_SECONDS))
		if _die_t[i] >= DIE_SECONDS and (not has_death or not m.is_playing()):
			_die_t[i] = -1.0
			_lie_down(i)
		_sync_live(i)
		return
	if not _alive[i]:
		return
	# Walking.
	var bob := 0.0
	if _delay[i] > 0.0:
		_delay[i] -= dt
	else:
		var to_goal := _goal[i] - holder.position
		var dist := to_goal.length()
		if dist > 1.5:
			if not _moving[i]:
				_moving[i] = true
				if has_move and m.animation != "attack":
					m.play("move")
					m.frame = int(jitter(key, i, 5) * 3.0)
			# Speeds up from a stand and slows into its place.
			var top := WALK_PX * _pace[i] * _rush[i]
			var want := to_goal / dist * minf(top, sqrt(2.0 * ACCEL * dist) + 8.0)
			_vel[i] = _vel[i].move_toward(want, ACCEL * dt)
			var step := _vel[i] * dt
			holder.position = _goal[i] if step.length() >= dist else holder.position + step
			if absf(_vel[i].x) > 12.0:
				_face_member(i, signf(_vel[i].x))
			if not has_move:
				bob = -absf(sin(_t * 14.0 + _phase + i * 0.9)) * 5.0   # placeholder stride
		elif _moving[i]:
			_moving[i] = false
			_rush[i] = 1.0
			_vel[i] = Vector2.ZERO
			if m.animation != "attack":
				m.play("idle")
			_face_member(i, _look[i])
	# Locked in melee: a swing now and then between the real blows.
	if _brawl[i] and not _moving[i] and _atk_wait[i] < 0.0 and _atk_t[i] < 0.0:
		_brawl_t[i] -= dt
		if _brawl_t[i] <= 0.0:
			_brawl_t[i] = brawl_pause(jitter(key, i, int(_t * 3.0)), live_unit(i) != null)
			_atk_wait[i] = 0.0
			_swing_brawl[i] = true
	# Attacking.
	var lean := 0.0
	var lunge := 0.0
	if _atk_wait[i] >= 0.0:
		_atk_wait[i] -= dt
		if _atk_wait[i] < 0.0:
			_atk_wait[i] = -1.0
			_atk_t[i] = 0.0
			_face_member(i, _look[i])
			if has_attack:
				m.play("attack")
			_live_attack(i)
	if _atk_t[i] >= 0.0:
		var before := _atk_t[i]
		_atk_t[i] += dt
		if _swing_brawl[i] and before < _impact and _atk_t[i] >= _impact:
			_swing_brawl[i] = false
			if _brawl[i]:
				brawl_hit.emit(self, i)
		lean = attack_lean(_atk_t[i], _impact, _total)
		if not has_attack and _atk_t[i] < LUNGE_SECONDS:
			lunge = sin(PI * _atk_t[i] / LUNGE_SECONDS) * LUNGE_PX
		if _atk_t[i] > _total + 0.25 or _live_swing_done(i):
			_atk_t[i] = -1.0
	_hurt[i] = maxf(0.0, _hurt[i] - dt * 3.0)
	_flash[i] = maxf(0.0, _flash[i] - dt * 12.0)
	var look := signf(m.scale.x)
	var pos := Vector2(lunge * look, bob)
	if _hurt[i] > 0.0:
		pos.x += sin(_t * 70.0 + i) * 4.0 * _hurt[i]
	if _brawl[i] and not _moving[i]:
		# Footwork: give and take a step.
		pos.x += sin(_t * 2.3 + _phase + i * 1.7) * 3.0 * look
	if _shove_t[i] >= 0.0:
		_shove_t[i] += dt
		pos.x += _shove_px[i] * shove_curve(_shove_t[i])
		if _shove_t[i] >= SHOVE_SECONDS:
			_shove_t[i] = -1.0
	var sy := _member_scale
	if m.animation == "idle" and not has_idle and not _moving[i]:
		sy = _member_scale * (1.0 + sin(_t * 1.7 + _phase + i * 0.9) * 0.012)  # breathing
	if _rise_t[i] >= 0.0:
		_rise_t[i] += dt
		var p := minf(1.0, _rise_t[i] / 0.5)
		m.rotation = -look * 1.35 * (1.0 - p)
		if p >= 1.0:
			_rise_t[i] = -1.0
	m.position = pos
	m.scale.y = sy
	m.skew = lean * look
	var tint := Color.WHITE.lerp(Color(1.0, 0.35, 0.3), _hurt[i])
	if _flash[i] > 0.0:
		tint = tint.lerp(Color(2.4, 2.4, 2.4), _flash[i])
	m.modulate = tint
	_sync_live(i)


## Seconds between brawl swings for a roll `r` in [0, 1). A 3D figure only
## takes a breath: its swing clip is already long, and standing idle in the
## middle of a melee reads as a freeze.
static func brawl_pause(r: float, live: bool) -> float:
	if live:
		return (0.1 + r * 0.35) / SWING_RATE
	return (1.1 + r * 1.6) / SWING_RATE


## A figure dying, `p` from 0 to 1: thrown back with a hop, then down in the
## creature's way of falling (or its drawn death clip).
func _animate_death(i: int, p: float) -> void:
	var m := members[i]
	var dir := _die_dir[i]
	var look := signf(m.scale.x)
	var k := 1.0 - pow(1.0 - p, 3.0)
	var throw := Vector2(dir * 16.0 * k, -sin(PI * minf(1.0, p * 1.6)) * 10.0)
	var red := Color(1.0, 0.45, 0.4).lerp(FALLEN_COLOR, k)
	m.position = throw
	if has_death:
		m.modulate = Color.WHITE.lerp(FALLEN_COLOR, maxf(0.0, p - 0.6) / 0.4)
		return
	match String(BattleGore.style(gore)["death"]):
		"crumble":
			m.rotation = 0.0
			m.scale = Vector2(_member_scale * look * (1.0 + k * 0.15), _member_scale * (1.0 - k * 0.72))
			m.modulate = Color.WHITE.lerp(Color(String(BattleGore.style(gore)["corpse"]), 0.85), k)
		"fade":
			m.position = Vector2(throw.x, -k * 24.0)
			m.modulate = Color(1.4, 1.3, 1.8, 1.0 - k)
		"topple":
			# Stiff: tips slowly, then slams down.
			m.rotation = dir * 1.45 * pow(p, 2.2)
			m.modulate = Color.WHITE.lerp(FALLEN_COLOR, k)
		_:
			m.rotation = dir * 1.35 * k
			m.modulate = red if p < 0.3 else Color(1.0, 0.45, 0.4).lerp(FALLEN_COLOR, k)


func _sync_frame_anchor(s: AnimatedSprite2D) -> void:
	var still := (s.animation == "idle" and not has_idle) or not CreatureAnims.has(creature_id, String(s.animation))
	s.offset = -Vector2(64, 127) if still and veteran_level >= 5 else -Art.anchor("creature_" + creature_id) if still else -CreatureAnims.anchor(creature_id, String(s.animation), veteran_level)


## Lean of an attacking figure (radians, + towards the target) at `t` seconds
## into an attack whose blow lands at `impact` seconds: draws back, snaps
## forward on the blow and settles. Zero outside the attack.
static func attack_lean(t: float, impact: float, total: float) -> float:
	if t < 0.0 or t > total + 0.25:
		return 0.0
	var hit := maxf(0.05, impact)
	if t < hit:
		return -0.07 * sin(t / hit * PI * 0.5)
	var after := t - hit
	if after < 0.08:
		return lerpf(-0.07, 0.11, after / 0.08)
	return 0.11 * exp(-(after - 0.08) * 9.0)


# ------------------------------------------------------------ 3D mirror ---

## Puts figure i's LiveUnit where the camera shows its feet, facing the way it
## walks or looks, playing what the sprite plays.
func _sync_live(i: int) -> void:
	var u := live_unit(i)
	if u == null or not u.is_inside_tree():
		return
	var m := members[i]
	var feet := position + _holders[i].position + Vector2(m.position.x, 0.0)
	var at := stage.field_to_world(feet)
	u.position = at
	if not _alive[i]:
		if u.player != null:
			u.player.speed_scale = speed
		return
	var walking := _moving[i] and _delay[i] <= 0.0 and _vel[i].length() > 4.0
	var way := _vel[i] if walking else (_aim[i] if _aim[i] != Vector2.ZERO else Vector2(signf(m.scale.x), 0.0))
	if walking and absf(_vel[i].x) > 6.0 and maxf(u.length, u.width) * u.scale.x > BROADSIDE_M:
		# Big beasts move broadside too: a drake flying up the field turns
		# its back to the camera otherwise.
		way = Vector2(signf(_vel[i].x), 0.0)
	var ahead := stage.field_to_world(feet + way.normalized() * 20.0) - at
	if ahead.length() > 0.001:
		# Long bodies (a 14 m wyrm) wheel slowly instead of spinning in place.
		u.rotation.y = lerp_angle(u.rotation.y, atan2(-ahead.z, ahead.x), 0.35 / maxf(1.0, u.length * u.scale.x / 3.0))
	if u.action == "attack" and u.busy():
		u.player.speed_scale = speed * _live_rate[i]
		return
	if u.attack_pending():
		return
	if walking:
		if u.action != "move":
			u.play("move", 1.0, 0.12, jitter(key, i, 5))
		# Feet in step: the clip's own ground speed against the figure's.
		var mps := _vel[i].length() * stage.metres_per_pixel(feet)
		_live_rate[i] = clampf(mps / maxf(0.1, u.move_speed), 0.4, 2.5)
	elif u.action != "idle" and not (_brawl[i] and u.action == "attack"):
		# (A brawler holds the end of its swing for the breath before the next.)
		u.play("idle", 1.0, 0.15)
		_live_rate[i] = 1.0
	if u.player != null:
		u.player.speed_scale = speed * _live_rate[i]


## True once figure i's 3D swing has played out after its blow: the next
## brawl swing may come without waiting for the sprite's longer timing.
func _live_swing_done(i: int) -> bool:
	if _atk_t[i] < _impact:
		return false
	var u := live_unit(i)
	return u != null and u.action == "attack" and not u.busy() and not u.attack_pending()


func _live_attack(i: int) -> void:
	var u := live_unit(i)
	if u == null or not u.has_clip("attack"):
		return
	# The model's blow lands when the sprite's does. The pace stays near the
	# clip's own (a 3D swing played much faster reads as a twitch); what is left
	# over is made up by starting the clip a little way in (long wind-up) or a
	# little later (quick jab).
	var hit := u.impact_time()
	var when := maxf(0.05, _impact)
	_live_rate[i] = clampf(hit / when, 0.6, 1.6)
	var skip := hit - _live_rate[i] * when
	if skip < -0.01:
		u.attack_after(-skip / _live_rate[i] / maxf(0.05, speed), speed * _live_rate[i])
		return
	u.play("attack", 1.0, 0.08)
	if skip > 0.0:
		u.player.seek(skip, true)
	u.player.speed_scale = speed * _live_rate[i]


func _live_fall(i: int, animate: bool) -> void:
	var u := live_unit(i)
	if u == null:
		return
	u.die(_die_dir[i])
	_live_rate[i] = 1.0
	if not animate and u.has_clip("death"):
		u.player.seek(u.player.get_animation("death").length, true)
