extends SceneTree
## Puts a Mixamo animation (FBX, "Without Skin") on a Tripo-rigged model and
## writes the result as a GLB with one clip, ready for bake_models.py:
##
##   godot --headless --script res://tools/assets/retarget_mixamo.gd -- \
##       <rigged.glb> <clip.fbx> <out.glb> [clip_name] [in_place] [grip=Bone,ax,ay,az,dx,dy,dz]
##
## Both rigs use Mixamo bone names. The Tripo rest pose is the painting's
## pose, Mixamo's is a T-pose, so the target is first swung into the source's
## rest pose bone by bone (each bone turned so it points at its child the way
## the Mixamo bone does, and the hips and chest turned to face the same way,
## so every retargeted unit faces the way Mixamo's character does). Each frame then applies the Mixamo bone's rotation
## away from its rest, in model space, on top of that matched rest:
##   target_global(t) = source_global(t) * source_rest^-1 * matched_rest
## The hips move by the source's hip offset scaled to the target's leg
## length; "in_place" drops the horizontal part (for walk and run cycles).
## "grip" turns a weapon hand in the matched rest so the weapon (axis in the
## model's mesh space, from rigid_weapon.py) points along dir in the T-pose,
## the way Mixamo's sword clips hold one (forward, +Z). "twist" (same
## fields) only rolls the bone about its length: a shield's outward face on
## the forearm turns forward. "mirror" plays the clip left-right mirrored
## (each bone follows its opposite-side source bone, reflected across the
## model's x plane), for units whose weapon sits in the left hand.

const FPS := 30.0
## Bones whose facing comes from a left-right pair below them.
## Reflection across the model's x plane (Mixamo's left-right axis).
const FLIP_X := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
const SIDES := {"Hips": ["LeftUpLeg", "RightUpLeg"], "Spine2": ["LeftArm", "RightArm"]}


var _anim_only := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: retarget_mixamo.gd -- <rigged.glb> <clip.fbx> <out.glb> [clip_name] [in_place]")
		quit(2)
		return
	var grips: Array = []
	var in_place := false
	var mirror := false
	for extra in args.slice(4):
		if extra == "in_place":
			in_place = true
		elif extra == "anim_only":
			# Only the motion is wanted (a live-only clip variant): drop the
			# meshes, so the file is a skeleton and a clip, not 30 MB.
			_anim_only = true
		elif extra == "mirror":
			mirror = true
		elif extra.begins_with("twist="):
			# twist=Bone,ax,ay,az,dx,dy,dz: like grip, but the bone only rolls
			# about its own length (a shield on the forearm faces forward).
			var v := extra.substr(6).split(",")
			grips.append({"bone": v[0], "axis": Vector3(float(v[1]), float(v[2]), float(v[3])),
					"dir": Vector3(float(v[4]), float(v[5]), float(v[6])), "twist": true})
		elif extra.begins_with("grip="):
			# grip=Bone,ax,ay,az,dx,dy,dz: the weapon axis in the model's mesh
			# space and the way it should point in Mixamo's T-pose.
			var v := extra.substr(5).split(",")
			grips.append({"bone": v[0], "axis": Vector3(float(v[1]), float(v[2]), float(v[3])),
					"dir": Vector3(float(v[4]), float(v[5]), float(v[6]))})
	_run.call_deferred(args[0], args[1], args[2], args[3] if args.size() > 3 else "clip", in_place, grips, mirror)


func _load(path: String) -> Node3D:
	var doc: GLTFDocument = FBXDocument.new() if path.to_lower().ends_with(".fbx") else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if path.to_lower().ends_with(".fbx") else GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot read " + path)
		return null
	return doc.generate_scene(state) as Node3D


func _skeleton(scene: Node) -> Skeleton3D:
	var found := scene.find_children("*", "Skeleton3D", true, false)
	return null if found.is_empty() else found[0] as Skeleton3D


func _key(name: String) -> String:
	# "mixamorig:LeftArm", "mixamorig_LeftArm" and "mixamorig1_LeftArm" all
	# become "LeftArm".
	var n := name.replace(":", "_")
	var cut := n.find("_")
	return n.substr(cut + 1) if n.begins_with("mixamorig") and cut >= 0 else n


## The child that gives a bone its direction: the spine chain for the hips,
## otherwise the first child that both rigs have.
func _lead(sk: Skeleton3D, bi: int, shared: Dictionary) -> int:
	var kids := sk.get_bone_children(bi)
	var key := _key(sk.get_bone_name(bi))
	for c in kids:
		var ck := _key(sk.get_bone_name(c))
		if key == "Hips" and ck == "Spine":
			return c
	for c in kids:
		if shared.has(_key(sk.get_bone_name(c))):
			return c
	return -1


## The opposite side's bone name ("LeftHand" <-> "RightHand").
func _other_side(key: String) -> String:
	if key.begins_with("Left"):
		return "Right" + key.substr(4)
	if key.begins_with("Right"):
		return "Left" + key.substr(5)
	return key


func _run(target_path: String, fbx_path: String, out_path: String, clip_name: String, in_place: bool, grips: Array, mirror: bool = false) -> void:
	var target := _load(target_path)
	var source := _load(fbx_path)
	if target == null or source == null:
		quit(1)
		return
	root.add_child(target)
	root.add_child(source)
	var tsk := _skeleton(target)
	var ssk := _skeleton(source)
	var player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if tsk == null or ssk == null or player == null:
		push_error("need a skeleton in both files and an animation in the FBX")
		quit(1)
		return
	var anim_name := ""
	for a in player.get_animation_list():
		if player.get_animation(a).get_track_count() > 0:
			anim_name = a
	var anim := player.get_animation(anim_name)

	# Model-space frames of both skeletons (FBX and GLB armatures may sit
	# under a rotated or scaled node).
	var tx := tsk.global_transform
	var sx := ssk.global_transform
	var src_of := {}  # key -> source bone index
	for i in ssk.get_bone_count():
		src_of[_key(ssk.get_bone_name(i))] = i
	var shared := {}
	for i in tsk.get_bone_count():
		var k := _key(tsk.get_bone_name(i))
		if src_of.has(k):
			shared[k] = i

	# Source rest in model space.
	var s_rest := {}
	for k in shared:
		s_rest[k] = sx * ssk.get_bone_global_rest(src_of[k])
	# Target rest swung into the source's rest pose, parents first.
	var order: Array[int] = []
	var stack: Array[int] = []
	for i in tsk.get_bone_count():
		if tsk.get_bone_parent(i) < 0:
			stack.push_back(i)
	while not stack.is_empty():
		var b: int = stack.pop_front()
		order.push_back(b)
		for c in tsk.get_bone_children(b):
			stack.push_back(c)
	var matched := {}  # target bone -> model-space Transform3D in matched rest
	for b in order:
		var p := tsk.get_bone_parent(b)
		var local := tsk.get_bone_rest(b)
		var g: Transform3D = (tx * local) if p < 0 else (matched[p] as Transform3D) * local
		var k := _key(tsk.get_bone_name(b))
		var lead := _lead(tsk, b, shared)
		if shared.has(k) and lead >= 0:
			var lk := _key(tsk.get_bone_name(lead))
			var t_dir := (tx * tsk.get_bone_global_rest(lead)).origin - (tx * tsk.get_bone_global_rest(b)).origin
			# Where the target's child points once its parents are matched.
			var t_now := g.basis * ((tx * tsk.get_bone_global_rest(b)).basis.inverse() * t_dir)
			var s_dir: Vector3 = (s_rest[lk] as Transform3D).origin - (s_rest[k] as Transform3D).origin
			if t_now.length() > 1e-6 and s_dir.length() > 1e-6:
				var axis := t_now.normalized().cross(s_dir.normalized())
				if axis.length() > 1e-6:
					var swing := Basis(axis.normalized(), t_now.normalized().signed_angle_to(s_dir.normalized(), axis.normalized()))
					g.basis = swing * g.basis
			# Turn about that direction too, so the hips and the chest face
			# the way the source's do (the left-right line of legs or arms).
			if SIDES.has(k) and shared.has(SIDES[k][0]) and shared.has(SIDES[k][1]):
				var l: int = shared[SIDES[k][0]]
				var r: int = shared[SIDES[k][1]]
				var rest_b := (tx * tsk.get_bone_global_rest(b)).basis
				var t_side := g.basis * (rest_b.inverse() * ((tx * tsk.get_bone_global_rest(l)).origin - (tx * tsk.get_bone_global_rest(r)).origin))
				var s_side: Vector3 = (s_rest[SIDES[k][0]] as Transform3D).origin - (s_rest[SIDES[k][1]] as Transform3D).origin
				var up := s_dir.normalized()
				t_side -= up * t_side.dot(up)
				s_side -= up * s_side.dot(up)
				if t_side.length() > 1e-6 and s_side.length() > 1e-6:
					g.basis = Basis(up, t_side.signed_angle_to(s_side, up)) * g.basis
		# A weapon hand turns so the weapon points the way Mixamo's clips
		# expect a held weapon to point in the T-pose (a sword forward).
		for grip in grips:
			if _key(String(grip["bone"])) == k:
				var rest_b := (tx * tsk.get_bone_global_rest(b)).basis
				var w: Vector3 = (g.basis * (rest_b.inverse() * (tx.basis * (grip["axis"] as Vector3)))).normalized()
				var d: Vector3 = (grip["dir"] as Vector3).normalized()
				if grip.get("twist", false) and lead >= 0:
					var along := (g.basis * (rest_b.inverse() * ((tx * tsk.get_bone_global_rest(lead)).origin
							- (tx * tsk.get_bone_global_rest(b)).origin))).normalized()
					w -= along * w.dot(along)
					d -= along * d.dot(along)
					if w.length() > 1e-6 and d.length() > 1e-6:
						g.basis = Basis(along, w.signed_angle_to(d, along)) * g.basis
					continue
				var ax := w.cross(d)
				if ax.length() > 1e-6:
					g.basis = Basis(ax.normalized(), w.signed_angle_to(d, ax.normalized())) * g.basis
		matched[b] = g

	# Hip height ratio for the root motion.
	var t_hips: int = shared.get("Hips", -1)
	var ratio := 1.0
	if t_hips >= 0:
		var th := (tx * tsk.get_bone_global_rest(t_hips)).origin.y - (tx * tsk.get_bone_global_rest(0)).origin.y
		var sh := (s_rest["Hips"] as Transform3D).origin.y
		if absf(sh) > 1e-6 and absf(th) > 1e-6:
			ratio = th / sh

	var out_anim := Animation.new()
	out_anim.length = anim.length
	out_anim.loop_mode = Animation.LOOP_LINEAR if in_place else Animation.LOOP_NONE
	var tracks := {}
	var sk_path := String(target.get_path_to(tsk))
	for k in shared:
		var t := out_anim.add_track(Animation.TYPE_ROTATION_3D)
		out_anim.track_set_path(t, NodePath("%s:%s" % [sk_path, tsk.get_bone_name(shared[k])]))
		tracks[k] = t
	var hip_track := -1
	if t_hips >= 0:
		hip_track = out_anim.add_track(Animation.TYPE_POSITION_3D)
		out_anim.track_set_path(hip_track, NodePath("%s:%s" % [sk_path, tsk.get_bone_name(t_hips)]))

	var frames := maxi(1, int(round(anim.length * FPS)))
	var s_hip0 := Vector3.ZERO
	for f in frames + 1:
		var time := minf(anim.length, f / FPS)
		player.play(anim_name)
		player.seek(time, true)
		player.pause()
		if f == 0 and src_of.has("Hips"):
			s_hip0 = (sx * ssk.get_bone_global_pose(src_of["Hips"])).origin
		var want := {}  # target bone -> model-space basis this frame
		for b in order:
			var k := _key(tsk.get_bone_name(b))
			var p := tsk.get_bone_parent(b)
			var parent_basis: Basis = (tx.basis if p < 0 else (want[p] as Basis))
			var g: Basis
			if shared.has(k):
				# Mirrored: follow the opposite bone and reflect its turn
				# across the x plane (M * R * M is again a rotation).
				var sk := _other_side(k) if mirror and src_of.has(_other_side(k)) and s_rest.has(_other_side(k)) else k
				var s_now := (sx * ssk.get_bone_global_pose(src_of[sk])).basis
				var turn := s_now * (s_rest[sk] as Transform3D).basis.inverse()
				if mirror:
					turn = FLIP_X * turn * FLIP_X
				g = turn * (matched[b] as Transform3D).basis
			else:
				g = parent_basis * tsk.get_bone_rest(b).basis
			want[b] = g
			if shared.has(k):
				var local := (parent_basis.inverse() * g).get_rotation_quaternion()
				out_anim.rotation_track_insert_key(tracks[k], time, local)
		if hip_track >= 0:
			var s_hip := (sx * ssk.get_bone_global_pose(src_of["Hips"])).origin
			var delta := (s_hip - (s_rest["Hips"] as Transform3D).origin) * ratio
			if mirror:
				delta.x = -delta.x
			if in_place:
				delta.x = 0.0
				delta.z = 0.0
			var p := tsk.get_bone_parent(t_hips)
			var parent_t: Transform3D = tx if p < 0 else tx * tsk.get_bone_global_rest(p)
			var model_pos := (tx * tsk.get_bone_global_rest(t_hips)).origin + delta
			out_anim.position_track_insert_key(hip_track, time, parent_t.affine_inverse() * model_pos)

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	target.add_child(ap)
	ap.owner = target
	ap.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	lib.add_animation(clip_name, out_anim)
	ap.add_animation_library("", lib)
	source.queue_free()
	if _anim_only:
		for mi in target.find_children("*", "MeshInstance3D", true, false):
			mi.get_parent().remove_child(mi)
			mi.free()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_scene(target, state) != OK or doc.write_to_filesystem(state, out_path) != OK:
		push_error("cannot write " + out_path)
		quit(1)
		return
	print("%s: %s -> %s (%d frames, hips x%.3f)" % [clip_name, fbx_path.get_file(), out_path, frames + 1, ratio])
	quit(0)
