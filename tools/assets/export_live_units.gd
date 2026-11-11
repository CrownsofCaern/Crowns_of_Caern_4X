extends SceneTree
## Writes one light GLB per 3D unit for live 3D (the 3D battles):
##
##   godot --headless --path . --script res://tools/assets/export_live_units.gd -- [--tris N] [--tex PX] [--out DIR] [--spec PATH] [ids...]
##
## --spec reads another spec file of the same shape (default
## assets/specs/creature_models.json).
##
## Input: the spec clips in assets/specs/creature_models.json (mesh from the
## idle/move clip GLB, which already has its weapon made rigid; one Mixamo or
## Tripo clip per action). Units whose clip GLBs are not on disk are skipped.
## Output, assets/units3d/<id>.glb by default:
## - mesh decimated to about --tris triangles (default 6000), textures --tex px
##   (default 512) stored as JPEG;
## - clips idle, move, attack, death, cut to the class window the bake uses
##   and resampled at 30 fps (constant tracks dropped);
## - root scaled to the spec "height" in metres (feet on y = 0) and turned so the
##   unit faces +X.
## Pose-only clips (pole_thrust, quad_lunge, wings...) are made by the baker, not
## stored in a GLB, so they are left out: LiveUnit falls back to a lunge.

const SPEC := "res://assets/specs/creature_models.json"
var _spec_path := SPEC
const FPS := 30.0
const ACTIONS := ["idle", "move", "attack", "death", "idle_alt", "attack_alt"]
## Clips that loop (the live-only idle variant too).
const LOOPED := ["idle", "move", "idle_alt"]

var _tris := 6000
var _tex := 512
var _out := "res://assets/units3d/"
var _poser: Object  ## render_model.gd, for its pose scripts (see _bake_pose)


func _initialize() -> void:
	var ids: Array[String] = []
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--tris":
				i += 1
				_tris = int(args[i])
			"--tex":
				i += 1
				_tex = int(args[i])
			"--out":
				i += 1
				_out = args[i].trim_suffix("/") + "/"
			"--spec":
				i += 1
				_spec_path = args[i] if args[i].begins_with("res://") else "res://" + args[i]
			_:
				ids.append(args[i])
		i += 1
	_run.call_deferred(ids)


func _run(ids: Array[String]) -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_spec_path))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var done := 0
	var skipped: Array[String] = []
	for unit in spec["units"]:
		var id := String(unit["id"])
		if not ids.is_empty() and id not in ids:
			continue
		if not _sources_exist(unit):
			skipped.append(id)
			continue
		var report := _export(unit)
		if report != "":
			print(report)
			done += 1
		else:
			skipped.append(id)
	print("exported %d units; skipped (no clip GLBs on disk): %s" % [done, ", ".join(skipped)])
	quit()


func _sources_exist(unit: Dictionary) -> bool:
	var clips: Dictionary = unit.get("clips", {})
	if not (clips.has("idle") or clips.has("move")):
		return false
	for action in clips:
		var c: Dictionary = clips[action]
		if String(c.get("pose", "")) == "" and not FileAccess.file_exists("res://" + String(c["model"])):
			return false
	return true


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		push_error("cannot read " + path)
		return null
	return doc.generate_scene(st) as Node3D


func _export(unit: Dictionary) -> String:
	var id := String(unit["id"])
	var clips: Dictionary = unit["clips"]
	var mesh_from := String(clips.get("idle", clips.get("move", {}))["model"])
	var model := _load_glb("res://" + mesh_from)
	if model == null:
		return ""
	root.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		player = AnimationPlayer.new()
		player.name = "AnimationPlayer"
		model.add_child(player)
	# Measure the rest pose before any clip moves the bones.
	var box := _bounds(model)
	var lib := AnimationLibrary.new()
	var body: Node3D = null
	for action in ACTIONS:
		if clips.has(action) and String(clips[action].get("pose", "")).begins_with("body_"):
			body = _body_node(model, player)
			break
	for action in ACTIONS:
		if not clips.has(action):
			continue
		var c: Dictionary = clips[action]
		if c.get("live_skip", false):
			continue   # looks wrong in 3D (a collapse that rears up): LiveUnit topples instead
		if body != null:
			lib.add_animation(action, _bake_body(String(c.get("pose", "body_still")), float(c.get("amount", 1.0)), action, box, unit))
			continue
		if String(c.get("pose", "")) != "":
			var posed := _bake_pose(model, player, String(c["pose"]), float(c.get("amount", 1.0)), action, unit)
			if posed != null:
				lib.add_animation(action, posed)
			continue
		var src := _load_glb("res://" + String(c["model"]))
		if src == null:
			continue
		var sp := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if sp != null and not sp.get_animation_list().is_empty():
			var name := String(c.get("clip", ""))
			var anim: Animation = sp.get_animation(name) if sp.has_animation(name) else sp.get_animation(sp.get_animation_list()[0])
			var a := float(c.get("start", 0.0)) * anim.length
			var b := float(c.get("end", 1.0)) * anim.length
			var cut := _cut(anim, a, b)
			_bind_to_skeleton(cut, model, player)
			cut.loop_mode = Animation.LOOP_LINEAR if action in LOOPED else Animation.LOOP_NONE
			lib.add_animation(action, cut)
		src.free()
	for existing in player.get_animation_library_list():
		player.remove_animation_library(existing)
	player.add_animation_library("", lib)
	if String(unit.get("weapon", {}).get("kind", "")) == "pole":
		_hold_pole(model, player, unit["weapon"])
	# Ground speed of the move clip (model units per second), from the feet.
	var stride := _stride_speed(model, player)
	var head := _head_top(model)
	# Share the triangle budget between all meshes (some models come in parts).
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var all_tris := 0
	for node in meshes:
		all_tris += _mesh_tris((node as MeshInstance3D).mesh as ArrayMesh)
	var tris := 0
	for node in meshes:
		var mi := node as MeshInstance3D
		tris += _slim(mi, int(float(_tris) * _mesh_tris(mi.mesh as ArrayMesh) / maxf(1.0, all_tris)))
		_smooth_weights(mi, int(unit.get("smooth_weights", 3)))
	# A pole weapon (pike, spear) was cut out of the fused mesh for the bakes,
	# which draw a clean one: carry one in the hand here, its shaft through the
	# grip (a third of the way up), along the pole's bind-space direction.
	if String(unit.get("weapon", {}).get("kind", "")) == "pole":
		_add_pole(model, unit["weapon"])
	# Rigs whose rest pose differs from the bind pose (Tripo quadrupeds) draw the
	# mesh away from its bind-pose bounds: stand the model on its posed feet.
	var posed := _posed_bounds(model, player)
	if posed.size != Vector3.ZERO:
		box.position.y = posed.position.y
		box.end.y = posed.end.y
	# Idle loops end where they start (a whole line snapping every loop reads badly).
	for loop in ["idle", "idle_alt"]:
		if player.has_animation(loop):
			_close_loop(player.get_animation(loop))
	var flyer := _is_flyer(unit)
	_in_place(model, player, box.size.y)
	_ground_clips(model, player, box.position.y, box.size.y, flyer)
	var impact := 0.45 if body != null and lib.has_animation("attack") else _impact(model, player)
	var impact_alt := _impact(model, player, "attack_alt")
	# Wrap: scale to the spec height, feet on the ground, facing +X.
	root.remove_child(model)
	var height := float(unit.get("height", 1.8))
	# Size by the top of the head, so a raised pike or staff does not shrink the body.
	var top := minf(box.end.y, head)
	var k := height / maxf(0.001, top - box.position.y)
	var yaw := float(unit.get("view", {}).get("yaw_degrees", 45.0))
	var turn_deg := 45.0 + (45.0 if yaw == 60.0 else yaw)
	var fix := _facing_fix(model, player, turn_deg, String(unit.get("tripo", {}).get("rig_type", "")) in ["hexapod", "octopod"], flyer)
	if fix != 0.0:
		print("%s: turned %+d deg to face +X" % [id, int(fix)])
		turn_deg += fix
	# A hand-checked extra turn when the automatic one is wrong (seen from the
	# top in live_sheet.gd --top, the head must point right).
	turn_deg += float(unit.get("view", {}).get("live_turn", 0.0))
	var wrap := Node3D.new()
	wrap.name = id
	var turn := Node3D.new()
	turn.name = "Turn"
	turn.rotation_degrees.y = turn_deg
	turn.scale = Vector3.ONE * k
	turn.position.y = -box.position.y * k
	wrap.add_child(turn)
	turn.owner = wrap
	model.position -= Vector3(box.get_center().x, 0.0, box.get_center().z)
	turn.add_child(model)
	_own(model, wrap)
	# The player looks up tracks from its root node; keep it on the model.
	var path := _out + id + ".glb"
	var doc := GLTFDocument.new()
	doc.image_format = "JPEG"
	doc.lossy_quality = 0.82
	var st := GLTFState.new()
	if doc.append_from_scene(wrap, st) != OK or doc.write_to_filesystem(st, ProjectSettings.globalize_path(path)) != OK:
		push_error("cannot write " + path)
		wrap.free()
		return ""
	wrap.free()
	# A stride under a quarter of the height (flyers, shades, gliders) is no
	# real step: let LiveUnit play the clip at its own pace instead.
	var speed := snappedf(stride * k, 0.01) if stride * k >= 0.25 * height else 0.0
	var entry := {"height": height, "move_speed": speed,
		"clips": Array(lib.get_animation_list()).map(func(n): return String(n))}
	if impact >= 0.0:
		entry["impact"] = snappedf(impact, 0.01)
	if impact_alt >= 0.0:
		entry["impact_alt"] = snappedf(impact_alt, 0.01)
	_record(id, entry)
	var size := FileAccess.get_file_as_bytes(path).size()
	return "%s: %d tris, %.1f m, clips %s, %d KB" % [id, tris, height, lib.get_animation_list(), size / 1024]


## A motion-only clip (retarget_mixamo.gd anim_only: no skin) comes in with
## its joints as plain nodes, its tracks on "Armature/Root/.../mixamorig_Hips";
## points each track whose last name is a bone of the model's skeleton at that
## bone, or every such clip would export empty and be dropped.
func _bind_to_skeleton(anim: Animation, model: Node3D, player: AnimationPlayer) -> void:
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var base := String(player.get_node(player.root_node).get_path_to(sk))
	for t in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(t)
		if path.get_subname_count() > 0:
			continue   # already a bone track
		var bone := String(path.get_name(path.get_name_count() - 1))
		if sk.find_bone(bone) >= 0:
			anim.track_set_path(t, NodePath(base + ":" + bone))
		elif String(path).contains("mixamorig") or String(path).begins_with("Armature"):
			anim.remove_track(t)   # a joint the mesh rig does not have


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
	node.owner = owner_node


func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b: AABB = model.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Flyers hover: grounding only lifts them out of the ground.
func _is_flyer(unit: Dictionary) -> bool:
	if String(unit.get("tripo", {}).get("rig_type", "")) == "avian":
		return true
	for c in unit.get("clips", {}).values():
		if String(c.get("pose", "")).begins_with("wing_"):
			return true
	return false


## Every vertex (every `step`-th) of the skinned meshes in the model's frame,
## at the skeleton's current pose.
func _skinned_points(model: Node3D, step: int = 4) -> PackedVector3Array:
	var out := PackedVector3Array()
	var to_model := model.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if sk == null or mi.skin == null:
			continue
		var skin := mi.skin
		var binds: Array[Transform3D] = []
		for i in skin.get_bind_count():
			var bone := skin.get_bind_bone(i)
			if bone < 0:
				bone = sk.find_bone(skin.get_bind_name(i))
			binds.append(sk.get_bone_global_pose(maxi(0, bone)) * skin.get_bind_pose(i))
		var to_skel := to_model * sk.global_transform
		for surf in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty() or verts.is_empty():
				continue
			var per := bones.size() / verts.size()
			for v in range(0, verts.size(), step):
				var q := Vector3.ZERO
				for j in per:
					var w := weights[v * per + j]
					if w > 0.0:
						q += w * (binds[bones[v * per + j]] * verts[v])
				out.append(to_skel * q)
	return out


## Blends the last fifth of a loop (at most 0.4 s) into its first frame.
func _close_loop(anim: Animation) -> void:
	var win := minf(0.4, anim.length * 0.2)
	if win <= 0.0:
		return
	for t in anim.get_track_count():
		var kind := anim.track_get_type(t)
		if anim.track_get_key_count(t) < 2:
			continue
		var first: Variant = anim.track_get_key_value(t, 0)
		for i in anim.track_get_key_count(t):
			var at := anim.track_get_key_time(t, i)
			if at < anim.length - win:
				continue
			var w := smoothstep(0.0, 1.0, (at - (anim.length - win)) / win)
			var v: Variant = anim.track_get_key_value(t, i)
			if kind == Animation.TYPE_ROTATION_3D:
				anim.track_set_key_value(t, i, (v as Quaternion).slerp(first as Quaternion, w))
			elif kind == Animation.TYPE_POSITION_3D or kind == Animation.TYPE_SCALE_3D:
				anim.track_set_key_value(t, i, (v as Vector3).lerp(first as Vector3, w))


## Keeps attacks and idles on the spot, facing the foe: mocap swings that leap
## forward, spin round or show the back (Mixamo jump attacks, club combos)
## read as glitches in a melee block. Per key of the root bone, the drift on
## the ground is capped at IN_PLACE_DRIFT of the height and the turn about the
## vertical at IN_PLACE_YAW radians; the rest of the motion stays.
const IN_PLACE_DRIFT := 0.12
const IN_PLACE_YAW := 0.45


func _in_place(model: Node3D, player: AnimationPlayer, tall: float) -> void:
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var root := -1
	for b in sk.get_bone_count():
		if sk.get_bone_parent(b) < 0:
			root = b
			break
	# Mocap moves the hips; Tripo rigs put a still Root bone above them.
	for b in sk.get_bone_count():
		if sk.get_bone_name(b).to_lower().ends_with("hips"):
			root = b
			break
	if root < 0:
		return
	var to_bone := (model.global_transform.affine_inverse() * sk.global_transform).basis.inverse()
	var parent := sk.get_bone_parent(root)
	if parent >= 0:
		to_bone = sk.get_bone_global_rest(parent).basis.inverse() * to_bone
	var up := (to_bone * Vector3.UP).normalized()
	var lim := (to_bone * Vector3(0.0, tall * IN_PLACE_DRIFT, 0.0)).length()
	var base := String(player.get_node(player.root_node).get_path_to(sk))
	var path := NodePath(base + ":" + sk.get_bone_name(root))
	for clip in ["attack", "idle", "attack_alt", "idle_alt"]:
		if not player.has_animation(clip):
			continue
		var anim := player.get_animation(clip)
		var pt := anim.find_track(path, Animation.TYPE_POSITION_3D)
		if pt >= 0 and anim.track_get_key_count(pt) > 1:
			var p0: Vector3 = anim.track_get_key_value(pt, 0)
			for i in anim.track_get_key_count(pt):
				var d: Vector3 = anim.track_get_key_value(pt, i) - p0
				var dv := up * d.dot(up)
				var dh := d - dv
				if dh.length() > lim:
					anim.track_set_key_value(pt, i, p0 + dv + dh.normalized() * lim)
		var rt := anim.find_track(path, Animation.TYPE_ROTATION_3D)
		if rt < 0 or anim.track_get_key_count(rt) < 2:
			continue
		var q0: Quaternion = anim.track_get_key_value(rt, 0)
		# Measure the turn on whichever bone axis lies flattest at the start.
		var axis := Vector3.FORWARD
		var best := -1.0
		for a: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]:
			var v := q0 * a
			var flat := (v - up * v.dot(up)).length()
			if flat > best:
				best = flat
				axis = a
		var f0 := q0 * axis
		f0 = (f0 - up * f0.dot(up)).normalized()
		var last := 0.0  # unwrapped, so a full turn does not flip at 180 deg
		for i in anim.track_get_key_count(rt):
			var q: Quaternion = anim.track_get_key_value(rt, i)
			var f := q * axis
			f -= up * f.dot(up)
			if f.length() < 0.25:
				continue
			var yaw := last + angle_difference(last, f0.signed_angle_to(f.normalized(), up))
			last = yaw
			var extra := yaw - clampf(yaw, -IN_PLACE_YAW, IN_PLACE_YAW)
			if extra != 0.0:
				anim.track_set_key_value(rt, i, (Quaternion(up, -extra) * q).normalized())


## Keeps clips on the ground: per frame, the lowest skinned point is brought
## back to the standing ground level `ground` (model frame) by moving the
## skeleton's root bone. Ground units are lifted out of the ground in every
## clip and pulled down when floating in idle and move; flyers are only lifted.
func _ground_clips(model: Node3D, player: AnimationPlayer, ground: float, tall: float, flyer: bool) -> void:
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var root := -1
	for b in sk.get_bone_count():
		if sk.get_bone_parent(b) < 0:
			root = b
			break
	if root < 0:
		return
	var to_skel := (model.global_transform.affine_inverse() * sk.global_transform).basis.inverse()
	var base := String(player.get_node(player.root_node).get_path_to(sk))
	var path := NodePath(base + ":" + sk.get_bone_name(root))
	for clip in ACTIONS:
		if not player.has_animation(clip):
			continue
		var anim := player.get_animation(clip)
		var steps := maxi(2, int(round(anim.length * 15.0)))
		var times := []
		var offs := []
		var poses := []
		var any := false
		for i in steps + 1:
			var t := anim.length * float(i) / float(steps)
			player.play(clip)
			player.seek(t, true)
			player.pause()
			var pts := _skinned_points(model, 3)
			var lo := INF
			for q in pts:
				lo = minf(lo, q.y)
			var off := 0.0
			if lo < ground - 0.02 * tall:
				off = ground - lo
			elif not flyer and clip in ["idle", "move", "death", "idle_alt"] and lo > ground + 0.03 * tall:
				off = ground - lo
			times.append(t)
			offs.append(off)
			poses.append(sk.get_bone_pose_position(root))
			any = any or off != 0.0
		player.stop()
		if not any:
			continue
		# Smooth, so a correction does not jitter frame to frame.
		var smooth := []
		for i in offs.size():
			var avg: float = (offs[maxi(0, i - 1)] + 2.0 * offs[i] + offs[mini(offs.size() - 1, i + 1)]) / 4.0
			# Never smooth a lift away: a frame under the ground stays fully lifted.
			smooth.append(maxf(avg, offs[i]) if offs[i] > 0.0 else avg)
		var track := anim.find_track(path, Animation.TYPE_POSITION_3D)
		if track >= 0:
			anim.remove_track(track)
		track = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(track, path)
		for i in times.size():
			anim.position_track_insert_key(track, times[i], poses[i] + to_skel * Vector3(0.0, smooth[i], 0.0))
	sk.reset_bone_poses()


## When the attack's blow lands, as a fraction of the clip: the moment the
## fastest of the hands, head and tail tips moves fastest (-1: no attack).
func _impact(model: Node3D, player: AnimationPlayer, clip: String = "attack") -> float:
	if not player.has_animation(clip):
		return -1.0
	if model.find_children("*", "Skeleton3D", true, false).is_empty():
		return -1.0
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var probes: Array[int] = []
	for b in sk.get_bone_count():
		var n := sk.get_bone_name(b)
		if n.ends_with("RightHand") or n.ends_with("LeftHand") or n.ends_with("Head") or n.ends_with("Head_0") \
				or (sk.get_bone_children(b).is_empty() and (n.contains("Head") or n.contains("Limb"))):
			probes.append(b)
	if probes.is_empty():
		return -1.0
	var anim := player.get_animation(clip)
	var steps := maxi(4, int(round(anim.length * 30.0)))
	var prev := []
	var best := -1.0
	var best_t := 0.6
	for i in steps + 1:
		var t := anim.length * float(i) / float(steps)
		player.play(clip)
		player.seek(t, true)
		player.pause()
		var now := []
		for b in probes:
			now.append(sk.get_bone_global_pose(b).origin)
		if not prev.is_empty():
			for j in now.size():
				var v: float = (now[j] - prev[j]).length()
				if v > best:
					best = v
					best_t = (float(i) - 0.5) / float(steps)
		prev = now
	player.stop()
	sk.reset_bone_poses()
	return clampf(best_t, 0.05, 0.95)


## Long-bodied units (wyrms, mounts, beasts) whose body lies across the view
## after the spec yaw: the extra turn (+-90 or 180 degrees) that lines the
## body up with +X, head forward. Bipeds and crawlers (wider than long) are
## trusted to the spec.
func _facing_fix(model: Node3D, player: AnimationPlayer, turn_deg: float, crawler: bool, flyer: bool = false) -> float:
	if model.find_children("*", "Skeleton3D", true, false).is_empty():
		return 0.0
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	if sk.find_bone("mixamorig_Head") >= 0 or crawler:
		return 0.0
	var clip := "idle" if player.has_animation("idle") else ("move" if player.has_animation("move") else "")
	if clip != "":
		player.play(clip)
		player.seek(0.0, true)
		player.pause()
	var rot := Basis(Vector3.UP, deg_to_rad(turn_deg))
	var pts := _skinned_points(model, 8)
	var head_b := -1
	for b in sk.get_bone_count():
		if sk.get_bone_name(b).ends_with("Head_0"):
			head_b = b
			break
	var head := Vector3.ZERO
	if head_b >= 0:
		head = rot * (model.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(head_b).origin)
	if clip != "":
		player.stop()
	sk.reset_bone_poses()
	if pts.is_empty():
		return 0.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		var r := rot * q
		lo = Vector2(minf(lo.x, r.x), minf(lo.y, r.z))
		hi = Vector2(maxf(hi.x, r.x), maxf(hi.y, r.z))
	var ext := hi - lo
	var centre := (lo + hi) * 0.5
	# Only clearly long bodies lying across the view (serpents, wyrms): head
	# bones of mounts belong to the rider, so they cannot be trusted for less.
	# Flyers: wings spread along X mean the body points at the camera; turn
	# it side-on so it flies the way it moves.
	var across := ext.x > ext.y * 1.3 if flyer else ext.y > ext.x * 1.6
	if across:
		if head_b >= 0:
			return 90.0 if head.z > centre.y else -90.0  # a +90 turn about Y takes +Z to +X
		return 90.0
	return 0.0


func _record(id: String, entry: Dictionary) -> void:
	# units3d.json beside the GLBs: what LiveUnit needs before a model is loaded.
	var path := _out + "units3d.json"
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data[id] = entry
	var keys := data.keys()
	keys.sort()
	var sorted := {}
	for key in keys:
		sorted[key] = data[key]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(sorted, "\t") + "\n")


func _stride_speed(model: Node3D, player: AnimationPlayer) -> float:
	# How fast the ground passes under a planted foot while the in-place move
	# clip plays: moving the unit at this speed keeps its feet from sliding.
	if not player.has_animation("move"):
		return 0.0
	var sk: Skeleton3D = null
	for node in model.find_children("*", "Skeleton3D", true, false):
		sk = node
		break
	if sk == null:
		return 0.0
	var feet: Array[int] = []
	for b in sk.get_bone_count():
		var bone_name := sk.get_bone_name(b).to_lower()
		if ("foot" in bone_name or "toe" in bone_name) and not "end" in bone_name:
			feet.append(b)
	if feet.is_empty():
		# No named feet: take the lowest bones of the rest pose.
		var low := INF
		for b in sk.get_bone_count():
			low = minf(low, sk.get_bone_global_rest(b).origin.y)
		for b in sk.get_bone_count():
			if sk.get_bone_global_rest(b).origin.y < low + 0.02:
				feet.append(b)
	var anim := player.get_animation("move")
	var steps := maxi(8, int(anim.length * FPS))
	var to_model := model.global_transform.affine_inverse() * sk.global_transform
	var tracks := {}
	player.play("move")
	for s in steps + 1:
		player.seek(anim.length * s / steps, true)
		for b in feet:
			tracks.get_or_add(b, []).append(to_model * sk.get_bone_global_pose(b).origin)
	player.stop()
	var total := 0.0
	var count := 0
	var dt := anim.length / steps
	for b in tracks:
		var pts: Array = tracks[b]
		var low := INF
		var high := -INF
		for p in pts:
			low = minf(low, (p as Vector3).y)
			high = maxf(high, (p as Vector3).y)
		# Planted: within the lowest fifth of the foot's lift.
		var planted := low + 0.2 * (high - low)
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			if a.y <= planted and c.y <= planted:
				total += Vector2(c.x - a.x, c.z - a.z).length() / dt
				count += 1
	return total / count if count > 0 else 0.0


## Poses the bake tool draws by script (render_model.gd), baked into real clips
## here: seconds per cycle for each.
## Unrigged models (war machines, wisps) move as one rigid body. Their clips
## animate a "Body" node wrapped round the mesh:
##   body_still  idle, motionless (a gun at rest)
##   body_float  idle or move, a slow hover bob with a little sway
##   body_roll   move, a cart rocking on rough ground
##   body_recoil attack, a gun's kick: snaps back and noses up, then settles
##   body_lunge  attack, swells and darts forward (a wisp striking)
##   body_topple death, tips over sideways and settles into the ground
##   body_fade   death, shrinks away into the air
## "forward" in the spec ([x, y, z], model space) is the way the model faces.
const BODY_SECONDS := {"body_still": 2.0, "body_float": 2.4, "body_roll": 0.8, "body_recoil": 1.0, "body_lunge": 0.9, "body_topple": 1.1, "body_fade": 1.0}


func _body_node(model: Node3D, player: AnimationPlayer) -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	for child in model.get_children():
		if child != player:
			model.remove_child(child)
			body.add_child(child)
	model.add_child(body)
	return body


func _bake_body(pose: String, amount: float, action: String, box: AABB, unit: Dictionary) -> Animation:
	var anim := Animation.new()
	anim.length = float(BODY_SECONDS.get(pose, 1.0))
	anim.loop_mode = Animation.LOOP_LINEAR if action in ["idle", "move"] else Animation.LOOP_NONE
	var pos_t := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_t, NodePath("Body"))
	var rot_t := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(rot_t, NodePath("Body"))
	var scl_t := anim.add_track(Animation.TYPE_SCALE_3D)
	anim.track_set_path(scl_t, NodePath("Body"))
	var f: Array = unit.get("forward", [0, 0, 1])
	var fwd := Vector3(float(f[0]), float(f[1]), float(f[2])).normalized()
	var side := Vector3.UP.cross(fwd).normalized()
	var tall := box.size.y
	var long := maxf(box.size.x, box.size.z)
	var pivot := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var n := int(ceil(anim.length * FPS))
	for i in n + 1:
		var t := anim.length * float(i) / float(n)
		var u := t / anim.length
		var off := Vector3.ZERO
		var rot := Quaternion.IDENTITY
		var scl := Vector3.ONE
		match pose:
			"body_float":
				off = Vector3.UP * sin(u * TAU) * 0.05 * tall * amount
				rot = Quaternion(fwd, sin(u * TAU + 1.0) * deg_to_rad(4.0) * amount)
			"body_roll":
				off = Vector3.UP * absf(sin(u * TAU)) * 0.015 * tall * amount
				rot = Quaternion(side, sin(u * TAU * 2.0) * deg_to_rad(1.5) * amount) * Quaternion(fwd, sin(u * TAU) * deg_to_rad(2.0) * amount)
			"body_recoil":
				# Kick at 0.45, back to rest by the end.
				var k := 0.0
				if u >= 0.4:
					k = exp(-(u - 0.45) * 7.0) * clampf((u - 0.4) / 0.05, 0.0, 1.0)
				off = -fwd * 0.12 * long * k * amount
				rot = Quaternion(side, -deg_to_rad(7.0) * k * amount)
			"body_lunge":
				var k := sin(clampf((u - 0.15) / 0.6, 0.0, 1.0) * PI)
				var draw := sin(clampf(u / 0.3, 0.0, 1.0) * PI) * 0.4
				off = fwd * (0.45 * k - 0.15 * draw) * long * amount
				scl = Vector3.ONE * (1.0 + 0.25 * k * amount)
			"body_topple":
				var k := smoothstep(0.0, 1.0, u)
				rot = Quaternion(fwd, deg_to_rad(28.0) * k * amount) * Quaternion(side, deg_to_rad(6.0) * k)
				off = Vector3.DOWN * 0.18 * tall * k * amount
			"body_fade":
				var k := smoothstep(0.0, 1.0, u)
				off = Vector3.UP * 0.4 * tall * k
				scl = Vector3.ONE * maxf(0.02, 1.0 - k)
		# Turn about the ground point under the middle, not the model origin.
		var p := pivot + off + rot * (-pivot)
		anim.position_track_insert_key(pos_t, t, p)
		anim.rotation_track_insert_key(rot_t, t, rot)
		anim.scale_track_insert_key(scl_t, t, scl)
	return anim


const POSE_SECONDS := {"quad_lunge": 0.9, "quad_charge": 1.0, "quad_idle": 2.4, "crawl": 0.8, "collapse": 1.1, "pole_thrust": 0.9, "wing_hover": 1.0, "wing_dive": 1.0}


func _thrust(sk: Skeleton3D, u: float, unit: Dictionary) -> void:
	# A pike thrust on the clip's stance: draw back, then both arms drive the
	# level pike forward and the upper body leans in, then recover. (The bake
	# tool's IK lunge overreaches on live rigs and flips the pike.)
	var w: Dictionary = unit.get("weapon", {})
	if w.is_empty():
		return
	var p := _poser
	var head: Vector3 = p._bone_pos(sk, p._bone(sk, "Head"))
	var hips: Vector3 = p._bone_pos(sk, p._bone(sk, "Hips"))
	var up := (head - hips).normalized()
	var toe: Vector3 = p._bone_pos(sk, p._bone(sk, "RightToeBase")) - p._bone_pos(sk, p._bone(sk, "RightFoot"))
	var forward := (toe - up * toe.dot(up)).normalized()
	var right := up.cross(forward).normalized()
	var reach: float = p._strike(u, 0.25, 0.5)
	var drive := clampf(reach / 0.5, 0.0, 1.0)
	var back := clampf(-reach / 0.25, 0.0, 1.0)
	for name in ["Spine", "Spine1", "Spine2"]:
		var bi := sk.find_bone(p._bone(sk, name))
		if bi >= 0:
			p._rotate_bone(sk, bi, Basis(right, deg_to_rad(6.0 * drive - 3.0 * back)))
	var aim := (forward - up * 0.35).normalized()
	# Upper arms forward of the body, elbows opening on the drive.
	p._swing(sk, p._bone(sk, "RightArm"), aim - forward * 0.6 * back, 0.55 + 0.25 * drive)
	p._swing(sk, p._bone(sk, "RightForeArm"), aim + up * 0.15, 0.4 + 0.5 * drive)
	p._swing(sk, p._bone(sk, "LeftArm"), aim + right * 0.3, 0.5 + 0.3 * drive)
	p._swing(sk, p._bone(sk, "LeftForeArm"), aim + up * 0.1, 0.5 + 0.4 * drive)
	# The pike stays level along the thrust.
	var a: Array = w["start"]
	var b: Array = w["end"]
	var axis := Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2]).normalized()
	var hand := sk.find_bone(String(w.get("bone", "mixamorig:RightHand")).replace(":", "_"))
	if hand < 0:
		return
	var local := _bind_dir(sk, hand, axis)
	var now := (sk.get_bone_global_pose(hand).basis * local).normalized()
	p._turn(sk, hand, now, (forward - up * 0.06).normalized())


## Keeps a pike in hand the way a pikeman carries it: upright at rest,
## sloped forward on the move (the clips' hand turns would swing it around),
## lying along the body in death. Rewrites the hand's rotation keys.
func _hold_pole(model: Node3D, player: AnimationPlayer, w: Dictionary) -> void:
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := String(w.get("bone", "mixamorig:RightHand")).replace(":", "_")
	var hand := sk.find_bone(bone)
	if hand < 0:
		return
	var a: Array = w["start"]
	var b: Array = w["end"]
	var local := _bind_dir(sk, hand, Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2]).normalized())
	if _poser == null:
		_poser = load("res://tools/assets/render_model.gd").new()
	var p: Object = _poser
	var base := String(player.get_node(player.root_node).get_path_to(sk))
	for clip in ["idle", "move", "death"]:
		if not player.has_animation(clip):
			continue
		var anim := player.get_animation(clip)
		var up := Vector3.ZERO
		var forward := Vector3.ZERO
		var track := anim.find_track(NodePath(base + ":" + bone), Animation.TYPE_ROTATION_3D)
		if track < 0:
			track = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(track, NodePath(base + ":" + bone))
		var steps := maxi(1, int(round(anim.length * FPS)))
		var keys := []
		for i in steps + 1:
			var t := anim.length * float(i) / float(steps)
			player.play(clip)
			player.seek(t, true)
			player.pause()
			if i == 0:
				# The facing of the clip's first frame, kept for the whole clip
				# (a running foot would swing the pike around).
				var head: Vector3 = p._bone_pos(sk, p._bone(sk, "Head"))
				var hips: Vector3 = p._bone_pos(sk, p._bone(sk, "Hips"))
				up = (head - hips).normalized()
				var toe: Vector3 = p._bone_pos(sk, p._bone(sk, "RightToeBase")) - p._bone_pos(sk, p._bone(sk, "RightFoot"))
				forward = (toe - up * toe.dot(up)).normalized()
			var want := (up + forward * (0.12 if clip == "idle" else 0.7)).normalized()
			if clip == "death":
				# The pike goes down with the body, along it, never into the ground.
				var body: Vector3 = p._bone_pos(sk, p._bone(sk, "Head")) - p._bone_pos(sk, p._bone(sk, "Hips"))
				want = body.normalized()
				if want.dot(up) < 0.03:
					want = (want - up * (want.dot(up) - 0.03)).normalized()
			var now := (sk.get_bone_global_pose(hand).basis * local).normalized()
			p._turn(sk, hand, now, want)
			keys.append([t, sk.get_bone_pose_rotation(hand)])
		player.stop()
		while anim.track_get_key_count(track) > 0:
			anim.track_remove_key(track, 0)
		for k in keys:
			anim.rotation_track_insert_key(track, k[0], k[1])
	sk.reset_bone_poses()


func _add_pole(model: Node3D, w: Dictionary) -> void:
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := String(w.get("bone", "mixamorig:RightHand")).replace(":", "_")
	var bi := sk.find_bone(bone)
	if bi < 0:
		return
	var a: Array = w["start"]
	var b: Array = w["end"]
	var p0 := Vector3(a[0], a[1], a[2])
	var p1 := Vector3(b[0], b[1], b[2])
	var dir := _bind_dir(sk, bi, (p1 - p0).normalized())
	var length := _bind_len(sk, bi, p1 - p0)
	var radius := float(w.get("radius", 0.02)) * length / maxf(0.001, (p1 - p0).length())
	var blade := minf(float(w.get("blade_length", length * 0.12)) * length / maxf(0.001, (p1 - p0).length()), length * 0.4)
	var bw := float(w.get("blade_width", radius * 4.0)) * length / maxf(0.001, (p1 - p0).length())
	var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, dir, side.cross(dir))
	var butt := -dir * length * 0.35
	var att := BoneAttachment3D.new()
	att.name = "Pole"
	att.bone_name = bone
	sk.add_child(att)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.33, 0.22, 0.13)
	wood.roughness = 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.62, 0.6)
	steel.metallic = 0.6
	steel.roughness = 0.45
	var shaft := CylinderMesh.new()
	shaft.top_radius = radius
	shaft.bottom_radius = radius * 1.1
	shaft.height = length - blade
	shaft.radial_segments = 8
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = bw * 0.5
	head.height = blade
	head.radial_segments = 4
	for part in [[shaft, wood, Transform3D(basis, butt + dir * (length - blade) * 0.5)],
			[head, steel, Transform3D(basis.scaled_local(Vector3(1.0, 1.0, 0.35)), butt + dir * (length - blade * 0.5))]]:
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (part[0] as PrimitiveMesh).get_mesh_arrays())
		am.surface_set_material(0, part[1])
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.transform = part[2]
		att.add_child(mi)


func _bind_len(sk: Skeleton3D, bi: int, v: Vector3) -> float:
	var name := sk.get_bone_name(bi)
	for node in sk.get_parent().find_children("*", "MeshInstance3D", true, false):
		var skin := (node as MeshInstance3D).skin
		if skin == null:
			continue
		for i in skin.get_bind_count():
			var bn := String(skin.get_bind_name(i))
			if bn == "" and skin.get_bind_bone(i) >= 0:
				bn = sk.get_bone_name(skin.get_bind_bone(i))
			if bn == name:
				return (skin.get_bind_pose(i).basis * v).length()
	return v.length()


## A mesh-space direction in bone `bi`'s own frame, through the skin's bind
## pose (Tripo rigs' rest pose differs from the bind pose).
func _bind_dir(sk: Skeleton3D, bi: int, dir: Vector3) -> Vector3:
	var name := sk.get_bone_name(bi)
	for node in sk.get_parent().find_children("*", "MeshInstance3D", true, false):
		var skin := (node as MeshInstance3D).skin
		if skin == null:
			continue
		for i in skin.get_bind_count():
			var bn := String(skin.get_bind_name(i))
			if bn == "" and skin.get_bind_bone(i) >= 0:
				bn = sk.get_bone_name(skin.get_bind_bone(i))
			if bn == name:
				return (skin.get_bind_pose(i).basis * dir).normalized()
	return (sk.get_bone_global_rest(bi).basis.inverse() * dir).normalized()


## Turns a scripted pose of the bake tool (quadruped lunge/charge/idle, wing
## hover/dive) into a clip on the model's skeleton, so live units that only had
## poses (beasts, flyers) still move. pole_thrust drives the arms with the bake
## tool's IK and turns the weapon hand so the pike (rigid in that hand, see
## the unit's "weapon") points along the thrust.
func _bake_pose(model: Node3D, player: AnimationPlayer, pose: String, amount: float, action: String, unit: Dictionary = {}) -> Animation:
	if not POSE_SECONDS.has(pose):
		return null
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var sk := skeletons[0] as Skeleton3D
	if _poser == null:
		_poser = load("res://tools/assets/render_model.gd").new()
	var loop := action in ["idle", "move"]
	var anim := Animation.new()
	anim.length = float(POSE_SECONDS[pose])
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var base := String(player.get_node(player.root_node).get_path_to(sk))
	var rot := {}
	var pos := {}
	for b in sk.get_bone_count():
		var track := base + ":" + sk.get_bone_name(b)
		rot[b] = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(rot[b], NodePath(track))
		pos[b] = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pos[b], NodePath(track))
	var steps := int(round(anim.length * FPS))
	# Weapon poses start from the stance of the model's own clip (as the bake
	# tool does), not the rig's rest pose, which faces another way.
	var stance := ""
	if pose == "pole_thrust" and not player.get_animation_list().is_empty():
		stance = String(player.get_animation_list()[0])
	for i in steps + 1:
		var u := float(i) / float(steps)
		sk.reset_bone_poses()
		if stance != "":
			player.play(stance)
			player.seek(0.0, true)
			player.pause()
		match pose:
			"quad_lunge":
				_poser._pose_lunge(sk, u, amount)
			"quad_charge":
				_poser._pose_charge(sk, u, amount)
			"quad_idle":
				_poser._pose_quad_idle(sk, u)
			"crawl":
				_poser._pose_crawl(sk, u, amount)
			"collapse":
				_poser._pose_collapse(sk, u, amount)
			"pole_thrust":
				_thrust(sk, u, unit)
			"wing_hover":
				_poser._pose_wings(sk, u, false)
			"wing_dive":
				_poser._pose_wings(sk, u, true)
		var t := anim.length * u
		for b in sk.get_bone_count():
			anim.rotation_track_insert_key(rot[b], t, sk.get_bone_pose_rotation(b))
			anim.position_track_insert_key(pos[b], t, sk.get_bone_pose_position(b))
	if stance != "":
		player.stop()
	sk.reset_bone_poses()
	# Same clean-up as cut clips: drop the tracks that never move.
	var out := _cut(anim, 0.0, anim.length)
	out.loop_mode = anim.loop_mode
	return out


func _posed_bounds(model: Node3D, player: AnimationPlayer) -> AABB:
	# Bounds of the skinned mesh at the first frame of idle (else move): the pose
	# LiveUnit shows standing still. Skins every vertex on the CPU.
	var clip := "idle" if player.has_animation("idle") else ("move" if player.has_animation("move") else "")
	if clip != "":
		player.play(clip)
		player.seek(0.0, true)
	var to_model := model.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if sk == null or mi.skin == null:
			continue
		var skin := mi.skin
		var binds: Array[Transform3D] = []
		for i in skin.get_bind_count():
			var bone := skin.get_bind_bone(i)
			if bone < 0:
				bone = sk.find_bone(skin.get_bind_name(i))
			binds.append(sk.get_bone_global_pose(maxi(0, bone)) * skin.get_bind_pose(i))
		var to_skel := to_model * sk.global_transform
		var mesh := mi.mesh
		for surf in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty() or verts.is_empty():
				continue
			var per := bones.size() / verts.size()
			for v in verts.size():
				var p := Vector3.ZERO
				for j in per:
					var w := weights[v * per + j]
					if w > 0.0:
						p += w * (binds[bones[v * per + j]] * verts[v])
				p = to_skel * p
				box = AABB(p, Vector3.ZERO) if first else box.expand(p)
				first = false
	if clip != "":
		player.stop()
	for node in model.find_children("*", "Skeleton3D", true, false):
		(node as Skeleton3D).reset_bone_poses()
	return box


func _head_top(model: Node3D) -> float:
	# Biped rigs: the skull top sits about two neck-to-head lengths above the head bone.
	for node in model.find_children("*", "Skeleton3D", true, false):
		var sk := node as Skeleton3D
		var head := sk.find_bone("mixamorig_Head")
		var neck := sk.find_bone("mixamorig_Neck")
		if head < 0 or neck < 0:
			continue
		var to_model := model.global_transform.affine_inverse() * sk.global_transform
		var h := to_model * sk.get_bone_global_rest(head).origin
		var n := to_model * sk.get_bone_global_rest(neck).origin
		return h.y + 2.0 * h.distance_to(n)
	return INF


func _cut(anim: Animation, a: float, b: float) -> Animation:
	# Resample [a, b] at FPS into a new clip starting at 0; drop tracks that never move.
	var out := Animation.new()
	out.length = maxf(1.0 / FPS, b - a)
	var steps := maxi(1, int(round((b - a) * FPS)))
	for t in anim.get_track_count():
		var kind := anim.track_get_type(t)
		if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var values := []
		for s in steps + 1:
			var time := a + (b - a) * s / steps
			match kind:
				Animation.TYPE_POSITION_3D:
					values.append(anim.position_track_interpolate(t, time))
				Animation.TYPE_ROTATION_3D:
					values.append(anim.rotation_track_interpolate(t, time))
				_:
					values.append(anim.scale_track_interpolate(t, time))
		if kind != Animation.TYPE_ROTATION_3D and _constant(values):
			continue
		var n := out.add_track(kind)
		out.track_set_path(n, anim.track_get_path(t))
		for s in values.size():
			var time := float(s) / FPS if s < steps else out.length
			match kind:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(n, time, values[s])
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(n, time, values[s])
				_:
					out.scale_track_insert_key(n, time, values[s])
	return out


func _constant(values: Array) -> bool:
	for v in values:
		if (v as Vector3).distance_to(values[0]) > 1e-4:
			return false
	return true


func _compact(arrays: Array) -> Array:
	# Drop the vertices the decimated index list no longer uses.
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap := PackedInt32Array()
	remap.resize(count)
	remap.fill(-1)
	var keep := PackedInt32Array()
	for v in index:
		if remap[v] < 0:
			remap[v] = keep.size()
			keep.append(v)
	var new_index := PackedInt32Array()
	new_index.resize(index.size())
	for n in index.size():
		new_index[n] = remap[index[n]]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in Mesh.ARRAY_MAX:
		var src = arrays[slot]
		if src == null or slot == Mesh.ARRAY_INDEX:
			continue
		var stride: int = src.size() / count
		var dst = src.duplicate()
		dst.resize(keep.size() * stride)
		for n in keep.size():
			for c in stride:
				dst[n * stride + c] = src[keep[n] * stride + c]
		out[slot] = dst
	out[Mesh.ARRAY_INDEX] = new_index
	return out


func _mesh_tris(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


## Auto-rig weights jump from vertex to vertex (one robe vertex on the far
## thigh, the next on the hip), and those outliers tear into long spikes when
## the bones part. A few passes of averaging each vertex's weights with its
## mesh neighbours (seam duplicates welded) keep every influence but remove
## the outliers: on the critic's worst units it halves the stretched triangles
## and the longest spike. Runs on the slimmed mesh; spec "smooth_weights": 0
## turns it off.
func _smooth_weights(mi: MeshInstance3D, passes: int) -> void:
	if passes <= 0 or mi.skin == null:
		return
	var src := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	var changed := false
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var n := verts.size()
		var per := bones.size() / n if n > 0 else 0
		if per == 0 or index.is_empty():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(s, src.surface_get_material(s))
			continue
		changed = true
		# Neighbours: triangle edges, plus vertices at the same spot (UV seams).
		var nb: Array[PackedInt32Array] = []
		nb.resize(n)
		var seen: Array[Dictionary] = []
		seen.resize(n)
		for v in n:
			seen[v] = {}
		for t in range(0, index.size(), 3):
			for e in 3:
				var a := index[t + e]
				var b := index[t + (e + 1) % 3]
				seen[a][b] = true
				seen[b][a] = true
		var spot := {}
		for v in n:
			var k := Vector3i((verts[v] * 10000.0).round())
			if spot.has(k):
				for o in spot[k]:
					seen[v][o] = true
					seen[o][v] = true
				(spot[k] as Array).append(v)
			else:
				spot[k] = [v]
		for v in n:
			nb[v] = PackedInt32Array(seen[v].keys())
		# Sparse weights per vertex: bone -> weight.
		var w: Array[Dictionary] = []
		w.resize(n)
		for v in n:
			var d := {}
			for j in per:
				var k := v * per + j
				if weights[k] > 0.0:
					d[bones[k]] = float(d.get(bones[k], 0.0)) + weights[k]
			w[v] = d
		for _p in passes:
			var next: Array[Dictionary] = []
			next.resize(n)
			for v in n:
				var d := {}
				for b in w[v]:
					d[b] = 0.5 * float(w[v][b])
				var m := nb[v].size()
				if m == 0:
					next[v] = w[v]
					continue
				for o in nb[v]:
					for b in w[o]:
						d[b] = float(d.get(b, 0.0)) + 0.5 * float(w[o][b]) / m
				next[v] = d
			w = next
		# Back to the strongest [per] influences, renormalised.
		for v in n:
			var pairs := []
			for b in w[v]:
				pairs.append([float(w[v][b]), int(b)])
			pairs.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
			var sum := 0.0
			for j in mini(per, pairs.size()):
				sum += float(pairs[j][0])
			for j in per:
				var k := v * per + j
				if j < pairs.size():
					bones[k] = int(pairs[j][1])
					weights[k] = float(pairs[j][0]) / maxf(sum, 0.0001)
				else:
					bones[k] = 0
					weights[k] = 0.0
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
		out.surface_set_name(s, src.surface_get_name(s))
	if changed:
		mi.mesh = out


func _slim(mi: MeshInstance3D, budget: int) -> int:
	# Decimate each surface (skin weights stay) and shrink the textures.
	var src := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	var tris := 0
	var total := 0
	for s in src.get_surface_count():
		total += (src.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var want := maxi(12, int(float(budget) * index.size() / 3.0 / maxf(1.0, total))) * 3
		if want < index.size():
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays)
			var lod := st.generate_lod(0.5, want)
			if lod.size() >= 3:
				arrays[Mesh.ARRAY_INDEX] = lod
		arrays = _compact(arrays)
		tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := src.surface_get_material(s)
		if mat is StandardMaterial3D:
			mat = (mat as StandardMaterial3D).duplicate()
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC,
					BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, BaseMaterial3D.TEXTURE_EMISSION]:
				var tex: Texture2D = mat.get_texture(slot)
				if tex != null and tex.get_width() > _tex:
					var img := tex.get_image()
					if img.is_compressed():
						img.decompress()
					img.resize(_tex, _tex, Image.INTERPOLATE_LANCZOS)
					mat.set_texture(slot, ImageTexture.create_from_image(img))
		out.surface_set_material(s, mat)
	mi.mesh = out
	return tris
