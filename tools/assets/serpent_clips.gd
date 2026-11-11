extends SceneTree
## Procedural clips for legless serpent rigs (Tripo "serpentine": Root, Tail_*,
## Spine_*, Head_* chains), which no Mixamo clip fits:
##
##   godot --headless --path . --script res://tools/assets/serpent_clips.gd -- RIGGED.glb OUT_DIR ID [avian]
##
## Writes OUT_DIR/ID_px_<action>.glb for idle (slow sway, head up), move (a
## slither: a sideways wave running from head to tail), attack (rear back, then
## strike) and death (roll onto the side and go limp). Each file holds the rigged
## model plus one clip named after the action, like retarget_mixamo.gd's output,
## so bake_models.py and export_live_units.gd use them unchanged.
##
## With "avian" (Tripo avian rigs on dragons, whose limb names do not say which
## chains are wings) the body runs from the Tail_* to the Head_* bones, the wings
## are the bones held high and far out to the side, and they beat, spread and droop
## on top of a calmer body motion.

const FPS := 30.0

var _sk: Skeleton3D
var _chain: Array[int] = []  ## body bones, ordered head (0) to tail (1)
var _s := {}  ## bone -> position along the body, 0 at the head tip, 1 at the tail tip
var _axis := Vector3.FORWARD  ## model-space direction from tail to head
var _head: Array[int] = []
var _wing := {}  ## avian: wing bone -> [side sign, depth along the wing]
var _avian := false
var _slender := 1.0  ## body length over width, from the bone heads


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- RIGGED.glb OUT_DIR ID")
		quit(1)
		return
	_avian = args.size() > 3 and args[3] == "avian"
	_run.call_deferred(args[0], args[1], args[2])


func _run(rigged: String, out_dir: String, id: String) -> void:
	for action in ["idle", "move", "attack", "death"]:
		var scene := _load(rigged)
		root.add_child(scene)
		_sk = scene.find_children("*", "Skeleton3D", true, false)[0]
		_measure()
		var anim := _clip(action, scene.get_path_to(_sk))
		var player := AnimationPlayer.new()
		player.name = "AnimationPlayer"
		scene.add_child(player)
		player.owner = scene
		var lib := AnimationLibrary.new()
		lib.add_animation(action, anim)
		player.add_animation_library("", lib)
		player.root_node = player.get_path_to(scene)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var out := out_dir.path_join("%s_px_%s.glb" % [id, action])
		if doc.append_from_scene(scene, state) != OK or doc.write_to_filesystem(state, out) != OK:
			push_error("cannot write " + out)
			quit(1)
			return
		print("%s: %s (%.2f s, %d bones)" % [id, out, anim.length, _chain.size()])
		scene.free()
	quit()


func _load(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot read " + path)
		quit(1)
	return doc.generate_scene(state) as Node3D


func _rest(b: int) -> Transform3D:
	return _sk.get_bone_global_rest(b)


func _measure() -> void:
	# The body runs along the longest horizontal extent of the bone heads.
	_chain.clear()
	_s.clear()
	_head.clear()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for b in _sk.get_bone_count():
		var p := _rest(b).origin
		lo = lo.min(p)
		hi = hi.max(p)
	_axis = Vector3.RIGHT if hi.x - lo.x >= hi.z - lo.z else Vector3.BACK
	var dx := hi.x - lo.x
	var dz := hi.z - lo.z
	_slender = maxf(dx, dz) / maxf(0.001, minf(dx, dz))
	var centre := _rest(0).origin.dot(_axis)
	var tail_tip := NAN
	var head_tip := NAN
	for b in _sk.get_bone_count():
		var name := _sk.get_bone_name(b).to_lower()
		var d := _rest(b).origin.dot(_axis)
		if "head" in name:
			_head.append(b)
			if is_nan(head_tip) or absf(d - centre) > absf(head_tip - centre):
				head_tip = d
		if "tail" in name and (is_nan(tail_tip) or absf(d - centre) > absf(tail_tip - centre)):
			tail_tip = d
	var top := hi.dot(_axis)
	var bottom := lo.dot(_axis)
	if is_nan(tail_tip):
		tail_tip = bottom if is_nan(head_tip) or head_tip > centre else top
	# The body ends: the tail tip, and the extreme on the other side of the root.
	var tail_end := bottom if tail_tip < centre else top
	var head_end := top if tail_tip < centre else bottom
	if head_end < tail_end:
		# Make the axis point from tail to head.
		_axis = -_axis
		head_end = -head_end
		tail_end = -tail_end
	for b in _sk.get_bone_count():
		var d := _rest(b).origin.dot(_axis)
		_s[b] = clampf((head_end - d) / maxf(0.001, head_end - tail_end), 0.0, 1.0)
		_chain.append(b)
	if _avian:
		_measure_avian(lo, hi)


func _measure_avian(lo: Vector3, hi: Vector3) -> void:
	# Wings make the model as wide as it is long, so take the body line from the
	# farthest Head_* and Tail_* bones instead of the bounds.
	_wing.clear()
	var root_p := _rest(0).origin
	var head_p := root_p
	var tail_p := root_p
	for b in _sk.get_bone_count():
		var name := _sk.get_bone_name(b).to_lower()
		var p := _rest(b).origin
		if "head" in name and p.distance_to(root_p) > head_p.distance_to(root_p):
			head_p = p
		if "tail" in name and p.distance_to(root_p) > tail_p.distance_to(root_p):
			tail_p = p
	var line := Vector3(head_p.x - tail_p.x, 0.0, head_p.z - tail_p.z)
	if line.length() > 0.001:
		_axis = line.normalized()
	var side := Vector3.UP.cross(_axis).normalized()
	var head_end := -INF
	var tail_end := INF
	for b in _sk.get_bone_count():
		var d := _rest(b).origin.dot(_axis)
		head_end = maxf(head_end, d)
		tail_end = minf(tail_end, d)
	var length := maxf(0.001, head_end - tail_end)
	var high := lo.y + 0.45 * (hi.y - lo.y)
	var centre := root_p.dot(side)
	for b in _sk.get_bone_count():
		var p := _rest(b).origin
		_s[b] = clampf((head_end - p.dot(_axis)) / length, 0.0, 1.0)
		var out := p.dot(side) - centre
		if absf(out) > 0.15 * length and p.y > high:
			var depth := 0
			var up := _sk.get_bone_parent(b)
			while up >= 0 and _wing.has(up):
				depth += 1
				up = _sk.get_bone_parent(up)
			_wing[b] = [signf(out), depth]
	_slender = 2.5  # roll partway onto the side in death
	print("avian: %d wing bones, axis %s" % [_wing.size(), _axis])


func _clip(action: String, sk_path: NodePath) -> Animation:
	var length: float = {"idle": 2.4, "move": 1.2, "attack": 1.1, "death": 1.4}[action]
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if action in ["idle", "move"] else Animation.LOOP_NONE
	var steps := int(length * FPS)
	var tracks := {}
	for b in _chain:
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("%s:%s" % [sk_path, _sk.get_bone_name(b)]))
		tracks[b] = t
	var side := Vector3.UP.cross(_axis).normalized()
	for i in steps + 1:
		var time := length * i / steps
		var u := time / length
		var heading := {}  # bone -> model-space rotation of the body at that bone
		for b in _chain:
			heading[b] = _pose(action, u, float(_s[b]), b in _head, side)
			if _wing.has(b):
				heading[b] = _flap(action, u, _wing[b][0], _wing[b][1]) * _body_soft(action, u, float(_s[b]), side)
			elif _avian:
				heading[b] = _body_soft(action, u, float(_s[b]), side)
		for b in _chain:
			var parent := _sk.get_bone_parent(b)
			var mine: Basis = heading[b]
			var theirs: Basis = heading[parent] if parent >= 0 and heading.has(parent) else Basis()
			# The bone's own share of the curve, turned into its local frame.
			var delta := theirs.inverse() * mine
			var g := _rest(b).basis.orthonormalized()
			var local := _sk.get_bone_rest(b).basis.orthonormalized() * (g.inverse() * delta * g)
			anim.rotation_track_insert_key(tracks[b], time, local.get_rotation_quaternion())
	return anim


func _pose(action: String, u: float, s: float, is_head: bool, side: Vector3) -> Basis:
	# Absolute body rotation (model space) at position s along the body (0 head, 1 tail).
	var tau := TAU
	match action:
		"move":
			# A travelling wave, stronger toward the tail; the head stays steadier.
			var amp := 0.32 * smoothstep(0.0, 0.5, s) + 0.06
			return Basis(Vector3.UP, amp * sin(tau * (u - 1.6 * s)))
		"idle":
			var sway := 0.1 * sin(tau * (u - 0.8 * s)) * smoothstep(0.0, 0.6, s)
			var lift := (0.18 if is_head else 0.0) + 0.03 * sin(tau * u)
			return Basis(Vector3.UP, sway) * Basis(side, -lift * (1.0 - s))
		"attack":
			# 0-0.45 rear back and up, 0.45-0.6 strike down and forward, then recover.
			var k := 0.0
			if u < 0.45:
				k = -smoothstep(0.0, 0.45, u)
			elif u < 0.6:
				k = lerpf(-1.0, 0.8, smoothstep(0.45, 0.6, u))
			else:
				k = lerpf(0.8, 0.0, smoothstep(0.6, 1.0, u))
			var front := 1.0 - smoothstep(0.0, 0.45, s)
			return Basis(side, 0.55 * k * front)
		_:
			# death: roll onto the side and sag, the wave dying out. A squat,
			# wide body (a moss mound) would stand up if rolled, so it only slumps.
			var r := smoothstep(0.0, 0.7, u)
			var twitch := 0.2 * sin(tau * (u * 2.0 - s)) * (1.0 - r)
			var roll := 1.3 * clampf((_slender - 1.5) / 2.0, 0.0, 1.0)
			var slump := Basis(side, 0.35 * r * (1.0 - s))
			return slump * Basis(_axis, roll * r * (0.6 + 0.4 * s)) * Basis(Vector3.UP, twitch)


func _body_soft(action: String, u: float, s: float, side: Vector3) -> Basis:
	# Avian bodies: the serpent motion, but calmer; a flier does not slither.
	var full := _pose(action, u, s, false, side)
	var calm := 1.0 if action in ["attack", "death"] else 0.35
	return Basis(Quaternion.IDENTITY.slerp(full.get_rotation_quaternion(), calm))


func _flap(action: String, u: float, dir: float, depth: int) -> Basis:
	# Raises the wing (positive) or lowers it about the body line; the tips lag.
	var lag := 0.07 * depth
	var tau := TAU
	var up := 0.0
	match action:
		"move":
			up = 0.15 + 0.65 * sin(tau * (2.0 * u - lag))
		"idle":
			up = 0.1 + 0.12 * sin(tau * (u - lag))
		"attack":
			# Spread high while rearing, a hard downbeat on the strike.
			var k := smoothstep(0.0, 0.45, u) * (1.0 - smoothstep(0.45, 0.6, u))
			up = 0.1 + 0.7 * k - 0.4 * smoothstep(0.45, 0.6, u) * (1.0 - smoothstep(0.6, 1.0, u))
		_:
			up = lerpf(0.1, -0.6, smoothstep(0.0, 0.8, u)) + 0.25 * sin(tau * (3.0 * u - lag)) * (1.0 - u)
	return Basis(_axis, dir * up * (1.0 + 0.15 * depth))
