extends SceneTree
## Renders the battle poses of one rigged 3D model (GLB) for the bake tool.
##
##   godot --path . --rendering-driver opengl3 --script res://tools/assets/render_model.gd -- <job.json> <out_dir>
##   godot ... --script res://tools/assets/render_model.gd -- --list <model.glb>
##
## The job (written by tools/assets/bake_models.py) lists actions, each with a
## model, a clip name and a frame count. Frames are sampled evenly over the
## clip (a looping clip leaves out its closing frame, a one-shot clip keeps it)
## and saved as <out_dir>/<action>_<n>.png on transparency. Models load straight
## from the GLB file through GLTFDocument, so they can stay under the
## Godot-ignored assets/source tree. The camera is orthographic and fixed per
## job, so every frame of a unit shares one scale and ground line; the bake
## tool aligns that ground line with the battle anchor afterwards.
##
## A job "weapon" (from tools/assets/split_weapon.py) puts a rigid pole in the
## hand bone. An action with "pose": "pole_thrust" ignores its clip's motion and
## poses a two-handed thrust on that pole instead (spine, hips, arm IK);
## "quad_lunge" poses a leaping bite on a Tripo quadruped rig; "wing_hover"
## and "wing_dive" flap and swoop a flyer (a rigged model with no clips works).
## "quad_idle" lets a quadruped (or a mount and rider) breathe and shift.
## A job "lance" (capsule [a, b, r] in mesh space, a = the grip) cuts a
## rider's welded weapon into a rigid piece that rides on the mount's spine
## and drops level toward the enemy in the charge (quad_charge, quad_lunge);
## "aim" (mesh space) gives the couch direction when the weapon is carried
## sideways, "level_degrees" how far below level the tip ends.
##
## Lighting follows docs/ART_BIBLE.md: a warm key light from the top left, a
## cool dim fill and a faint red rim from behind.

var _job: Dictionary = {}
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--list":
		_list.call_deferred(args[1])
		return
	if args.size() < 2:
		push_error("usage: render_model.gd -- <job.json> <out_dir>")
		quit(2)
		return
	_job = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	_out = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_render.call_deferred()


func _load_model(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot read model " + path)
		return null
	return doc.generate_scene(state) as Node3D


func _list(path: String) -> void:
	var model := _load_model(path)
	var info := {"clips": {}}
	var ok := model != null
	if ok:
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null:
			for clip in player.get_animation_list():
				info["clips"][clip] = player.get_animation(clip).length
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		info["bones"] = skeleton.get_bone_count() if skeleton != null else 0
		model.free()
	print(JSON.stringify(info))
	quit(0 if ok else 1)


func _stage() -> SubViewport:
	var px: Array = _job.get("render_size", [640, 512])
	var vp := SubViewport.new()
	vp.size = Vector2i(int(px[0]), int(px[1]))
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.45, 0.55)
	env.ambient_light_energy = float(_job.get("ambient", 0.8))
	var world := WorldEnvironment.new()
	world.environment = env
	vp.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = float(_job.get("key", 1.5))
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_color = Color(0.9, 0.18, 0.12)
	rim.light_energy = float(_job.get("rim", 1.2))
	vp.add_child(rim)
	return vp


## Fits an orthographic camera around the rest pose of the first model so
## every action of the unit renders at one scale.
func _camera(vp: SubViewport, bounds: AABB) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var pitch := deg_to_rad(float(_job.get("pitch_degrees", 18.0)))
	# Height of the frame in world units: the model's height plus headroom for
	# weapons swung overhead and bodies thrown down, as a share of the frame.
	var fill := float(_job.get("fill", 0.5))
	cam.size = maxf(bounds.size.y, bounds.size.x * 0.8) / fill
	var centre := bounds.get_center()
	var look := Vector3(centre.x, bounds.position.y + cam.size * 0.36, centre.z)
	cam.position = look + Vector3(0, sin(pitch), cos(pitch)) * 20.0
	vp.add_child(cam)
	cam.look_at(look)


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## A clean rigid pole weapon in the hand bone, replacing the one
## split_weapon.py cut out of the fused mesh. `start`/`end` are in the mesh's
## bind space, so the skin's bind pose maps them into the bone.
func _attach_pole(model: Node3D, spec: Dictionary, free := false) -> Dictionary:
	var skeleton := model.find_child("*", true, false) as Skeleton3D
	for node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node
	var mesh: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			mesh = node
	if skeleton == null or mesh == null:
		push_error("weapon: no skinned mesh")
		return {}
	# Godot's importer turns ':' in bone names into '_'.
	var bone := String(spec["bone"]).replace(":", "_")
	var bind := Transform3D.IDENTITY
	var found := false
	for i in mesh.skin.get_bind_count():
		var name := String(mesh.skin.get_bind_name(i))
		if name == "" and mesh.skin.get_bind_bone(i) >= 0:
			name = skeleton.get_bone_name(mesh.skin.get_bind_bone(i))
		if name == bone:
			bind = mesh.skin.get_bind_pose(i)
			found = true
	if not found:
		push_error("weapon: bone %s not in the skin" % bone)
		return {}
	var a: Array = spec["start"]
	var b: Array = spec["end"]
	var p0 := bind * Vector3(a[0], a[1], a[2])
	var p1 := bind * Vector3(b[0], b[1], b[2])
	var length := p0.distance_to(p1)
	var blade := minf(float(spec.get("blade_length", length * 0.12)), length * 0.4)
	var radius := float(spec.get("radius", 0.02))
	var up := (p1 - p0).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up))
	var holder: Node3D
	if free:
		# Posed by a pose script: the pole lives in skeleton space, base at
		# the origin, pointing along +Y.
		holder = Node3D.new()
		var rest := skeleton.get_bone_global_rest(skeleton.find_bone(bone))
		var q0 := rest * p0
		var q1 := rest * p1
		length = q0.distance_to(q1)
		p0 = Vector3.ZERO
		up = Vector3.UP
		side = Vector3.RIGHT
		basis = Basis.IDENTITY
		blade = minf(float(spec.get("blade_length", length * 0.12)) * length / maxf(0.001, (bind * Vector3(a[0], a[1], a[2])).distance_to(bind * Vector3(b[0], b[1], b[2]))), length * 0.4)
	else:
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone
		holder = attachment
	skeleton.add_child(holder)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.33, 0.22, 0.13)
	wood.roughness = 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.62, 0.6)
	steel.metallic = 0.6
	steel.roughness = 0.45
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = radius
	shaft_mesh.bottom_radius = radius * 1.1
	shaft_mesh.height = length - blade
	shaft_mesh.radial_segments = 8
	shaft_mesh.material = wood
	var shaft := MeshInstance3D.new()
	shaft.mesh = shaft_mesh
	shaft.transform = Transform3D(basis, p0 + up * (length - blade) * 0.5)
	holder.add_child(shaft)
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = float(spec.get("blade_width", radius * 4)) * 0.5
	head_mesh.height = blade
	head_mesh.radial_segments = 4
	head_mesh.material = steel
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	# Four-sided and squashed: a leaf blade, not a cone.
	head.transform = Transform3D(basis.scaled_local(Vector3(1.0, 1.0, 0.35)), p0 + up * (length - blade * 0.5))
	holder.add_child(head)
	return {"holder": holder, "skeleton": skeleton, "length": length, "bone": skeleton.find_bone(bone),
		"local": [bind * Vector3(a[0], a[1], a[2]), bind * Vector3(b[0], b[1], b[2])]}


## Pose scripts: hand-made attacks on the shared humanoid (Mixamo-named)
## skeleton, for weapons no preset animation knows. `u` runs 0..1 over the
## clip. The body comes from the clip at its first frame (a natural stance);
## the script moves the hips and spine and puts both hands on the weapon with
## IK.
func _bone_pos(sk: Skeleton3D, name: String) -> Vector3:
	return sk.get_bone_global_pose(sk.find_bone(name)).origin


func _bone(sk: Skeleton3D, suffix: String) -> String:
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).ends_with(suffix):
			return sk.get_bone_name(i)
	return ""


func _rotate_bone(sk: Skeleton3D, bi: int, rot: Basis) -> void:
	# Applies a rotation given in skeleton space to bone bi.
	var pi := sk.get_bone_parent(bi)
	var parent := Basis.IDENTITY if pi < 0 else sk.get_bone_global_pose(pi).basis
	var global := sk.get_bone_global_pose(bi).basis
	sk.set_bone_pose_rotation(bi, (parent.inverse() * rot * global).get_rotation_quaternion())


func _turn(sk: Skeleton3D, bi: int, from: Vector3, to: Vector3) -> void:
	var axis := from.cross(to)
	if axis.length() < 1e-6:
		return
	_rotate_bone(sk, bi, Basis(axis.normalized(), from.signed_angle_to(to, axis)))


## A job "hold" list (from tools/assets/rigid_weapon.py) keeps a rigid staff,
## lantern or banner pointing the way it does in the model, however the clip
## turns the hand: {"bone", "axis" (bind/mesh space), "clips", "weight"}.
## The hand turns by the smallest rotation, so the grip's twist is kept.
func _hold(sk: Skeleton3D, action: String) -> void:
	for h in _job.get("hold", []):
		if not action in h.get("clips", ["idle", "move"]):
			continue
		var bi := sk.find_bone(String(h["bone"]).replace(":", "_"))
		if bi < 0:
			bi = sk.find_bone(String(h["bone"]))
		if bi < 0:
			push_error("hold: bone %s not found" % h["bone"])
			continue
		var a: Array = h["axis"]
		var axis := Vector3(a[0], a[1], a[2]).normalized()
		var local := sk.get_bone_global_rest(bi).basis.inverse() * axis
		var now := (sk.get_bone_global_pose(bi).basis * local).normalized()
		var target := now.slerp(axis, clampf(float(h.get("weight", 1.0)), 0.0, 1.0))
		_turn(sk, bi, now, target)


func _two_bone_ik(sk: Skeleton3D, side: String, target: Vector3, pole: Vector3) -> void:
	# Analytic arm IK: shoulder-elbow-wrist reaches target, elbow bends toward pole.
	var arm := sk.find_bone(_bone(sk, side + "Arm"))
	var fore := sk.find_bone(_bone(sk, side + "ForeArm"))
	var hand := sk.find_bone(_bone(sk, side + "Hand"))
	var s := sk.get_bone_global_pose(arm).origin
	var e := sk.get_bone_global_pose(fore).origin
	var w := sk.get_bone_global_pose(hand).origin
	var la := (e - s).length()
	var lb := (w - e).length()
	var to_t := target - s
	var d := clampf(to_t.length(), absf(la - lb) + 1e-4, (la + lb) * 0.999)
	var n := to_t.normalized()
	var cos_a := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var perp := (pole - n * pole.dot(n)).normalized()
	var elbow := s + n * la * cos_a + perp * la * sqrt(1.0 - cos_a * cos_a)
	_turn(sk, arm, e - s, elbow - s)
	e = sk.get_bone_global_pose(fore).origin
	w = sk.get_bone_global_pose(hand).origin
	_turn(sk, fore, w - e, s + n * d - e)


func _strike(u: float, back: float, out: float) -> float:
	# Shared attack timeline: draw back (0-0.35), drive (0.35-0.55), hold
	# (0.55-0.7), recover. Returns the reach, -back .. out.
	if u < 0.35:
		return -back * smoothstep(0.0, 0.35, u)
	if u < 0.55:
		return lerpf(-back, out, smoothstep(0.35, 0.55, u))
	if u < 0.7:
		return out
	return lerpf(out, 0.0, smoothstep(0.7, 1.0, u))


func _swing(sk: Skeleton3D, bone: String, toward: Vector3, amount: float) -> void:
	# Turns a bone's chain direction (bone -> first child) toward a direction.
	var bi := sk.find_bone(bone)
	if bi < 0 or amount == 0.0:
		return
	var kids := sk.get_bone_children(bi)
	if kids.is_empty():
		return
	var v := sk.get_bone_global_pose(kids[0]).origin - sk.get_bone_global_pose(bi).origin
	if v.length() < 1e-6:
		return
	var to := v.normalized().slerp(toward.normalized(), clampf(absf(amount), 0.0, 1.0))
	_turn(sk, bi, v, to)


func _quad_axes(sk: Skeleton3D) -> Array:
	# Up, forward, right and body length of a Tripo quadruped rig. Tripo names
	# the front legs 0_* and the hind legs 1_*; mounts and odd bodies often
	# have no Head bone, so the legs give the facing.
	var up := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var front := Vector3.ZERO
	var hind := Vector3.ZERO
	var nf := 0
	var nh := 0
	for bi in sk.get_bone_count():
		var name := sk.get_bone_name(bi)
		if not name.ends_with("_Limb_0"):
			continue
		if name.contains("__0_"):
			front += sk.get_bone_global_pose(bi).origin
			nf += 1
		elif name.contains("__1_"):
			hind += sk.get_bone_global_pose(bi).origin
			nh += 1
	var forward := Vector3.ZERO
	var length := 0.0
	if nf > 0 and nh > 0:
		forward = front / nf - hind / nh
		length = forward.length() * 1.6
	var head_bone := _bone(sk, "Head_0")
	if head_bone != "":
		var head := _bone_pos(sk, head_bone)
		var hips := _bone_pos(sk, _bone(sk, "Spine_0"))
		if forward == Vector3.ZERO:
			forward = head - hips
		length = maxf(length, (head - hips).length())
	forward = (forward - up * forward.dot(up)).normalized()
	return [up, forward, up.cross(forward).normalized(), maxf(length, 0.05)]


func _pose_charge(sk: Skeleton3D, u: float, amount := 1.0) -> void:
	# Cavalry charge for a mount and rider rigged as one quadruped: the mount
	# rears with its forelegs up, then crashes forward nose-down and drives
	# the rider's weapon through, then recovers.
	if sk == null:
		return
	var axes := _quad_axes(sk)
	var up: Vector3 = axes[0]
	var forward: Vector3 = axes[1]
	var right: Vector3 = axes[2]
	var length: float = axes[3] * amount
	var rear := smoothstep(0.0, 0.35, u) * (1.0 - smoothstep(0.35, 0.5, u))
	var reach := _strike(u, 0.1, 0.7)
	var drive := clampf(reach / 0.7, 0.0, 1.0)
	var pitch := deg_to_rad(30.0 * rear - 8.0 * drive)
	var root := sk.find_bone(_bone(sk, "Root"))
	var rp := sk.get_bone_parent(root)
	var to_parent := Basis.IDENTITY if rp < 0 else sk.get_bone_global_pose(rp).basis.inverse()
	# Pitch about the hind feet: the body rises as it tips back.
	var shift := forward * reach * length + up * (sin(absf(pitch)) * 0.45 * length + 0.05 * length * sin(drive * PI))
	sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + to_parent * shift)
	_rotate_bone(sk, root, Basis(right, pitch))
	for side in ["Left", "Right"]:
		_swing(sk, _bone(sk, "0_%s_Limb_0" % side), forward + up * 0.6, rear * 0.7)
		_swing(sk, _bone(sk, "0_%s_Limb_0" % side), forward - up * 0.5, drive * 0.5 * (1.0 - smoothstep(0.7, 1.0, u)))


func _pose_lunge(sk: Skeleton3D, u: float, amount := 1.0) -> void:
	# Four-legged bite lunge for Tripo's quadruped rig (Spine_n, Head_n,
	# 0_* front limbs, 1_* hind limbs): crouch back, spring forward with the
	# forelegs reaching and the head driving in, land, recover.
	if sk == null:
		return
	var axes := _quad_axes(sk)
	var up: Vector3 = axes[0]
	var forward: Vector3 = axes[1]
	var length: float = axes[3] * amount
	var reach := _strike(u, 0.2, 0.75)
	var drive := clampf((reach + 0.2) / 0.95, 0.0, 1.0)
	var crouch := clampf(-reach / 0.2, 0.0, 1.0)
	var air := sin(clampf((u - 0.35) / 0.25, 0.0, 1.0) * PI)
	var root := sk.find_bone(_bone(sk, "Root"))
	var rp := sk.get_bone_parent(root)
	var to_parent := Basis.IDENTITY if rp < 0 else sk.get_bone_global_pose(rp).basis.inverse()
	var shift := forward * reach * length + up * (air * 0.18 - crouch * 0.06) * length
	sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + to_parent * shift)
	# Haunches drop in the crouch, the body tips nose-down into the bite.
	var right: Vector3 = axes[2]
	var spine := sk.find_bone(_bone(sk, "Spine_0"))
	if spine >= 0:
		_rotate_bone(sk, spine, Basis(right, deg_to_rad(10.0 * crouch - 12.0 * air)))
	# Forelegs reach out in the leap, hind legs push back.
	for side in ["Left", "Right"]:
		_swing(sk, _bone(sk, "0_%s_Limb_0" % side), forward - up * 0.4, air * 0.8)
		_swing(sk, _bone(sk, "1_%s_Limb_0" % side), -forward - up * 0.6, air * 0.6)
	# Head low in the crouch, stretched forward and down at the bite.
	var head_dir := forward - up * lerpf(0.5, 0.15, drive)
	_swing(sk, _bone(sk, "Head_0"), head_dir, 0.3 * crouch + 0.6 * drive * (1.0 - smoothstep(0.7, 1.0, u)))


func _tip(sk: Skeleton3D, bi: int, from: Vector3) -> Vector3:
	# The descendant of bone bi furthest from a point.
	var best := sk.get_bone_global_pose(bi).origin
	var stack := [bi]
	while not stack.is_empty():
		var b: int = stack.pop_back()
		var pos := sk.get_bone_global_pose(b).origin
		if (pos - from).length() > (best - from).length():
			best = pos
		stack.append_array(sk.get_bone_children(b))
	return best


func _wing_roots(sk: Skeleton3D, up: Vector3) -> Array:
	# Tripo leaves wing bones unnamed (and rigs some flyers as quadrupeds):
	# take the two unnamed side branches of the spine or head chain whose tips
	# lie furthest apart across the body.
	# A unit's "wings" (two bone names) overrides the search, for rigs whose
	# labels are scrambled.
	var forced: Array = _job.get("wings", [])
	if forced.size() == 2:
		var picked := []
		for name in forced:
			var bi := sk.find_bone(String(name).replace(":", "_"))
			if bi < 0:
				bi = sk.find_bone(String(name))
			picked.append(bi)
		if picked[0] >= 0 and picked[1] >= 0:
			var b0 := sk.get_bone_global_pose(sk.get_bone_parent(picked[0])).origin
			var b1 := sk.get_bone_global_pose(sk.get_bone_parent(picked[1])).origin
			return [picked[0], picked[1], _tip(sk, picked[0], b0), _tip(sk, picked[1], b1)]
	var named := ["Spine", "Head", "Limb", "Tail", "Root"]
	var cands: Array = []
	for pass_index in 2:
		for bi in sk.get_bone_count():
			var parent := sk.get_bone_parent(bi)
			if parent < 0:
				continue
			var pname := sk.get_bone_name(parent)
			# First pass: side branches of the spine or head chain. Second
			# pass (when that finds no pair): any unnamed branch off a fork,
			# for rigs that hang the wings off an unnamed bone.
			var off_spine := pname.contains("Spine") or pname.contains("Head")
			if pass_index == 0 and not off_spine:
				continue
			if pass_index == 1 and sk.get_bone_children(parent).size() < 2:
				continue
			if named.any(func(n): return sk.get_bone_name(bi).contains(n)) or sk.get_bone_children(bi).size() == 0:
				continue
			var base := sk.get_bone_global_pose(parent).origin
			cands.append([bi, _tip(sk, bi, base)])
		if cands.size() >= 2:
			break
	var pair := [-1, -1]
	var span := 0.0
	for i in cands.size():
		for j in range(i + 1, cands.size()):
			var d: Vector3 = cands[i][1] - cands[j][1]
			d -= up * d.dot(up)
			if d.length() > span:
				span = d.length()
				pair = [cands[i][0], cands[j][0], cands[i][1], cands[j][1]]
	return pair


func _deepest(sk: Skeleton3D, word: String, from: Vector3) -> Vector3:
	var best := from
	for bi in sk.get_bone_count():
		if sk.get_bone_name(bi).contains(word):
			var pos := sk.get_bone_global_pose(bi).origin
			if (pos - from).length() > (best - from).length():
				best = pos
	return best


func _pose_wings(sk: Skeleton3D, u: float, dive: bool) -> void:
	# Flyers: a wing-beat loop (hover) or a swoop with the head driving in
	# (dive). The body hangs above the ground so the downstroke stays in
	# frame; wings flap about the body's forward axis, the outer wing lags.
	if sk == null:
		return
	var up := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var wings := _wing_roots(sk, up)
	if wings[0] < 0:
		push_warning("no wings found on %s" % sk.name)
		return
	var right: Vector3 = wings[2] - wings[3]
	right = (right - up * right.dot(up)).normalized()
	var forward := right.cross(up).normalized()
	var spine := _bone_pos(sk, _bone(sk, "Spine_0"))
	var front := _deepest(sk, "Head", spine)
	if front == spine:
		front = _deepest(sk, "Spine", spine)
	var back := _deepest(sk, "Tail", spine)
	if (front - back).dot(forward) < 0.0:
		forward = -forward
		right = -right
		wings = [wings[1], wings[0], wings[3], wings[2]]
	var size := maxf((front - spine).length(), (wings[2] - wings[3]).length() * 0.4)
	var beat: float
	var lift: float
	var reach := 0.0
	if dive:
		# Rear up with wings high, then swoop forward with a hard downstroke.
		reach = _strike(u, 0.25, 0.8)
		beat = lerpf(0.9, -0.8, smoothstep(0.3, 0.55, u)) * (1.0 - smoothstep(0.7, 1.0, u))
		lift = 0.5 - reach * 0.08
	else:
		beat = sin(u * TAU)
		lift = 0.45 - 0.08 * sin(u * TAU)
	var root := sk.find_bone(_bone(sk, "Root"))
	var rp := sk.get_bone_parent(root)
	var to_parent := Basis.IDENTITY if rp < 0 else sk.get_bone_global_pose(rp).basis.inverse()
	var shift := (forward * reach * 0.8 + up * lift) * size
	sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + to_parent * shift)
	if dive:
		var s0 := sk.find_bone(_bone(sk, "Spine_0"))
		if s0 >= 0:
			_rotate_bone(sk, s0, Basis(right, deg_to_rad(-14.0 * clampf(reach / 0.8, -1.0, 1.0))))
		_swing(sk, _bone(sk, "Head_1"), forward - up * 0.3, 0.5 * clampf(reach / 0.8, 0.0, 1.0))
	for k in 2:
		var sign := 1.0 if k == 0 else -1.0
		var wing: int = wings[k]
		_rotate_bone(sk, wing, Basis(forward, sign * deg_to_rad(38.0) * beat))
		# The outer wing trails the stroke a little.
		var chain := wing
		for depth in 2:
			var kids := sk.get_bone_children(chain)
			if kids.is_empty():
				break
			chain = kids[0]
		if chain != wing:
			var lag := sin(u * TAU - 0.9) if not dive else beat
			_rotate_bone(sk, chain, Basis(forward, sign * deg_to_rad(18.0) * lag))


func _biped_axes(sk: Skeleton3D) -> Array:
	# Up, forward, right and height of a humanoid (mixamo-named) skeleton.
	var head := _bone_pos(sk, _bone(sk, "Head"))
	var hips := _bone_pos(sk, _bone(sk, "Hips"))
	var up := (head - hips).normalized()
	var toe := _bone_pos(sk, _bone(sk, "RightToeBase")) - _bone_pos(sk, _bone(sk, "RightFoot"))
	var forward := (toe - up * toe.dot(up)).normalized()
	var right := up.cross(forward).normalized()
	if right.dot(_bone_pos(sk, _bone(sk, "RightArm")) - _bone_pos(sk, _bone(sk, "LeftArm"))) < 0.0:
		right = -right
	var height := (head - _bone_pos(sk, _bone(sk, "RightFoot"))).length()
	return [up, forward, right, height]


func _reach(sk: Skeleton3D, side: String, target: Vector3, weight: float, pole: Vector3, keep_hand := false) -> void:
	# Moves a hand toward a target, blended with the clip's pose by weight.
	# keep_hand holds the hand's orientation, so a welded bow stays upright.
	if weight <= 0.001:
		return
	var hi := sk.find_bone(_bone(sk, side + "Hand"))
	var before := sk.get_bone_global_pose(hi).basis.orthonormalized()
	_two_bone_ik(sk, side, sk.get_bone_global_pose(hi).origin.lerp(target, clampf(weight, 0.0, 1.0)), pole)
	if keep_hand:
		var now := sk.get_bone_global_pose(hi).basis.orthonormalized()
		_rotate_bone(sk, hi, before * now.inverse())


func _lean(sk: Skeleton3D, axis: Vector3, degrees: float) -> void:
	for name in ["Spine", "Spine1", "Spine2"]:
		var bi := sk.find_bone(_bone(sk, name))
		if bi >= 0:
			_rotate_bone(sk, bi, Basis(axis, deg_to_rad(degrees / 3.0)))


func _pose_arms(sk: Skeleton3D, u: float, kind: String, hand_turn := 0.0) -> void:
	# Ranged attacks on the human skeleton, posed over the idle clip:
	# bow_draw (draw to the cheek, loose), cast (staff up, then thrust it at
	# the enemy) and throw (overhead wind-up, hurl).
	if sk == null or _bone(sk, "RightHand") == "":
		return
	var axes := _biped_axes(sk)
	var up: Vector3 = axes[0]
	var forward: Vector3 = axes[1]
	var right: Vector3 = axes[2]
	var h: float = axes[3]
	var w := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.8, 1.0, u))
	var ls := _bone_pos(sk, _bone(sk, "LeftArm"))
	var rs := _bone_pos(sk, _bone(sk, "RightArm"))
	var arm := (_bone_pos(sk, _bone(sk, "RightForeArm")) - rs).length() + (_bone_pos(sk, _bone(sk, "RightHand")) - _bone_pos(sk, _bone(sk, "RightForeArm"))).length()
	match kind:
		"bow_draw":
			# Side-on to the target, bow arm straight, string hand to the cheek.
			_lean(sk, up, 35.0 * w)
			ls = _bone_pos(sk, _bone(sk, "LeftArm"))
			rs = _bone_pos(sk, _bone(sk, "RightArm"))
			var bow := ls + forward * arm * 0.95 + up * 0.04 * h
			var draw := smoothstep(0.15, 0.5, u)
			var loose := smoothstep(0.55, 0.62, u) * (1.0 - smoothstep(0.75, 0.95, u))
			var cheek := rs.lerp(ls, 0.35) + up * 0.08 * h - forward * 0.02 * h
			var string := bow.lerp(cheek, draw) - forward * 0.08 * h * loose - right * 0.05 * h * loose
			_reach(sk, "Left", bow, w, -up + right * 0.3, true)
			# A welded bow keeps its idle angle in the hand; "hand_turn" (degrees
			# about the facing axis) stands it upright, about 90 when the idle
			# holds it level across the body.
			if hand_turn != 0.0:
				_rotate_bone(sk, sk.find_bone(_bone(sk, "LeftHand")), Basis(forward, deg_to_rad(hand_turn) * w))
			_reach(sk, "Right", string, w, -up + right * 0.6 - forward * 0.3)
		"cast":
			# Raise the staff hand overhead, then drive it at the enemy.
			var raise := smoothstep(0.1, 0.35, u) * (1.0 - smoothstep(0.35, 0.55, u))
			var drive := smoothstep(0.35, 0.55, u) * (1.0 - smoothstep(0.7, 1.0, u))
			_lean(sk, right, -8.0 * raise + 16.0 * drive)
			rs = _bone_pos(sk, _bone(sk, "RightArm"))
			ls = _bone_pos(sk, _bone(sk, "LeftArm"))
			var high := rs + up * arm * 0.95 + forward * 0.05 * h
			var point := rs + forward * arm * 0.95 + up * 0.08 * h
			var r_target := high * raise + point * drive + _bone_pos(sk, _bone(sk, "RightHand")) * maxf(0.0, 1.0 - raise - drive)
			_reach(sk, "Right", r_target, w, -up + right * 0.5)
			_reach(sk, "Left", ls + forward * arm * 0.8 - up * 0.05 * h + right * 0.05 * h, drive * w, -up - right * 0.5)
		"throw":
			# Wind the throwing arm back overhead, then hurl forward and down.
			var wind := smoothstep(0.1, 0.4, u) * (1.0 - smoothstep(0.4, 0.55, u))
			var hurl := smoothstep(0.4, 0.55, u) * (1.0 - smoothstep(0.7, 1.0, u))
			_lean(sk, right, -12.0 * wind + 22.0 * hurl)
			_lean(sk, up, 25.0 * wind - 10.0 * hurl)
			rs = _bone_pos(sk, _bone(sk, "RightArm"))
			ls = _bone_pos(sk, _bone(sk, "LeftArm"))
			var back := rs + up * arm * 0.7 - forward * arm * 0.6
			var out := rs + forward * arm * 0.9 - up * 0.05 * h
			var r_target := back * wind + out * hurl + _bone_pos(sk, _bone(sk, "RightHand")) * maxf(0.0, 1.0 - wind - hurl)
			_reach(sk, "Right", r_target, w, -up + right * 0.5)
			_reach(sk, "Left", ls + forward * arm * 0.85 + up * 0.05 * h, wind * w, -up - right * 0.5)


func _pose_thrust(info: Dictionary, u: float) -> void:
	var sk: Skeleton3D = info["skeleton"]
	var pole: Node3D = info["holder"]
	var length := float(info["length"])
	var head := _bone_pos(sk, _bone(sk, "Head"))
	var hips_name := _bone(sk, "Hips")
	var hips := _bone_pos(sk, hips_name)
	var up := (head - hips).normalized()
	var toe := _bone_pos(sk, _bone(sk, "RightToeBase")) - _bone_pos(sk, _bone(sk, "RightFoot"))
	var forward := (toe - up * toe.dot(up)).normalized()
	var right := up.cross(forward).normalized()
	if right.dot(_bone_pos(sk, _bone(sk, "RightArm")) - _bone_pos(sk, _bone(sk, "LeftArm"))) < 0.0:
		right = -right
	var height := (head - _bone_pos(sk, _bone(sk, "RightFoot"))).length()
	var reach := _strike(u, 0.3, 0.55)
	var drive := clampf((reach + 0.2) / 0.55, 0.0, 1.0)
	# Lunge: hips forward and down, spine leans over the thrust, chest turns square.
	var hi := sk.find_bone(hips_name)
	var hp := sk.get_bone_parent(hi)
	var to_parent := Basis.IDENTITY if hp < 0 else sk.get_bone_global_pose(hp).basis.inverse()
	var shift := forward * reach * 0.3 * height - up * drive * 0.06 * height
	sk.set_bone_pose_position(hi, sk.get_bone_pose_position(hi) + to_parent * shift)
	var lean := deg_to_rad(lerpf(-8.0, 18.0, drive))
	var twist := deg_to_rad(lerpf(-20.0, 10.0, drive))
	for name in ["Spine", "Spine1", "Spine2"]:
		var bi := sk.find_bone(_bone(sk, name))
		if bi >= 0:
			_rotate_bone(sk, bi, Basis(right, lean / 3.0) * Basis(up, twist / 3.0))
	# The pike: level at chest height on the right side, slightly down at the thrust.
	var shoulder := _bone_pos(sk, _bone(sk, "RightArm"))
	var chest := _bone_pos(sk, hips_name).lerp(shoulder, 0.7) + right * 0.05 * height
	var dir := (forward - up * lerpf(0.04, 0.1, drive)).normalized()
	var butt := chest - dir * length * 0.4 + forward * reach * 0.8 * height
	var x_axis := dir.cross(right).normalized()
	pole.transform = Transform3D(Basis(x_axis, dir, x_axis.cross(dir)), butt)
	info["dir"] = dir
	var rear := butt + dir * length * 0.3
	var front := butt + dir * length * 0.55
	_two_bone_ik(sk, "Right", rear, -up + right * 0.6 - forward * 0.3)
	_two_bone_ik(sk, "Left", front, -up - right * 0.5)


func _split_ball(model: Node3D, spec: Dictionary) -> Dictionary:
	# A thrown missile (a boulder, a bomb) welded into the mesh: its triangles
	# (inside spec "sphere" [x, y, z, r], mesh space) move to their own mesh,
	# carried in the throwing hand and let go at spec "release" of the attack.
	var skeleton: Skeleton3D = null
	for node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node
	var mesh: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			mesh = node
	if skeleton == null or mesh == null:
		push_error("throw: no skinned mesh")
		return {}
	var s: Array = spec["sphere"]
	var centre := Vector3(s[0], s[1], s[2])
	var radius := float(s[3])
	var source := mesh.mesh as ArrayMesh
	var body := ArrayMesh.new()
	var ball := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		var cut := PackedInt32Array()
		for t in range(0, index.size(), 3):
			var inside := true
			for k in 3:
				if verts[index[t + k]].distance_to(centre) > radius:
					inside = false
			for k in 3:
				(cut if inside else keep).append(index[t + k])
		var material := source.surface_get_material(surface)
		var body_arrays := arrays.duplicate()
		body_arrays[Mesh.ARRAY_INDEX] = keep
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body_arrays)
		body.surface_set_material(body.get_surface_count() - 1, material)
		if cut.size() > 0:
			var ball_arrays := arrays.duplicate()
			ball_arrays[Mesh.ARRAY_INDEX] = cut
			ball_arrays[Mesh.ARRAY_BONES] = null
			ball_arrays[Mesh.ARRAY_WEIGHTS] = null
			ball.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ball_arrays)
			ball.surface_set_material(ball.get_surface_count() - 1, material)
	if ball.get_surface_count() == 0:
		push_error("throw: no triangles inside the sphere")
		return {}
	mesh.mesh = body
	var holder := MeshInstance3D.new()
	holder.mesh = ball
	skeleton.add_child(holder)
	var bone := String(spec.get("bone", "mixamorig:RightHand")).replace(":", "_")
	var bi := skeleton.find_bone(bone)
	var bind := Transform3D.IDENTITY
	for i in mesh.skin.get_bind_count():
		var name := String(mesh.skin.get_bind_name(i))
		if name == "" and mesh.skin.get_bind_bone(i) >= 0:
			name = skeleton.get_bone_name(mesh.skin.get_bind_bone(i))
		if name == bone:
			bind = mesh.skin.get_bind_pose(i)
	return {"holder": holder, "skeleton": skeleton, "bone": bi, "bind": bind, "centre": centre,
		"radius": radius, "release": float(spec.get("release", 0.55)), "speed": float(spec.get("speed", 4.0))}


func _ball_in_hand(info: Dictionary) -> Transform3D:
	# The ball turns with the hand and sits just past the wrist, in the palm.
	var sk: Skeleton3D = info["skeleton"]
	var bi := int(info["bone"])
	var hand := sk.get_bone_global_pose(bi)
	var rigid: Transform3D = hand * Transform3D(info["bind"])
	var fore := sk.get_bone_global_pose(sk.get_bone_parent(bi)).origin
	var along := (hand.origin - fore).normalized()
	var target := hand.origin + along * float(info["radius"]) * 0.9
	var at: Vector3 = rigid * Vector3(info["centre"])
	return Transform3D(rigid.basis, rigid.origin + target - at)


func _place_ball(info: Dictionary, action: String, u: float) -> void:
	var holder: Node3D = info["holder"]
	if action != "attack":
		info.erase("thrown")
		holder.transform = _ball_in_hand(info)
		return
	var release := float(info["release"])
	if u < release or not info.has("thrown"):
		holder.transform = _ball_in_hand(info)
		if u < release:
			return
		# Let go: keep the hand's last velocity direction, forward and up.
		var sk: Skeleton3D = info["skeleton"]
		var head := sk.get_bone_global_pose(sk.find_bone(_bone(sk, "Head"))).origin
		var foot := sk.get_bone_global_pose(sk.find_bone(_bone(sk, "RightFoot"))).origin
		info["thrown"] = {"start": holder.transform, "u": u, "height": (head - foot).length()}
	var t: Dictionary = info["thrown"]
	var dt := u - float(t["u"])
	var h := float(t["height"])
	# Retargeted units face +Z: an arc toward the enemy that leaves the frame.
	var offset := Vector3(0.0, 0.5 * h * dt * float(info["speed"]) - 3.0 * h * dt * dt, h * dt * float(info["speed"]))
	# Tumble about the ball's own centre while it flies.
	var start: Transform3D = t["start"]
	var centre: Vector3 = start * Vector3(info["centre"])
	var basis := start.basis.rotated(Vector3.RIGHT, dt * 8.0)
	holder.transform = Transform3D(basis, centre + offset - basis * Vector3(info["centre"]))


func _split_lance(model: Node3D, spec: Dictionary) -> Dictionary:
	# A rider's lance or spear welded into a mount-and-rider mesh, skinned to
	# whatever limb was nearest, so it bends and smears. Its triangles (inside
	# spec "capsule" [a, b, r], mesh space, a at the grip) move to their own
	# rigid mesh that rides on the spine bone nearest the grip.
	var skeleton: Skeleton3D = null
	for node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node
	var mesh: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			mesh = node
	if skeleton == null or mesh == null:
		push_error("lance: no skinned mesh")
		return {}
	var c: Array = spec["capsule"]
	var a := Vector3(c[0][0], c[0][1], c[0][2])
	var b := Vector3(c[1][0], c[1][1], c[1][2])
	var radius := float(c[2])
	var head_from := a.lerp(b, 0.7)
	var head_to := a.lerp(b, 1.15)
	var head_radius := float(spec.get("head_radius", radius * 2.5))
	var source := mesh.mesh as ArrayMesh
	var body := ArrayMesh.new()
	var piece := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		var cut := PackedInt32Array()
		for t in range(0, index.size(), 3):
			var inside := true
			for k in 3:
				var v := verts[index[t + k]]
				# The shaft is thin, the head (last third, a little past the
				# tip) broad: blades and flanges spread wider than the pole.
				if v.distance_to(Geometry3D.get_closest_point_to_segment(v, a, b)) > radius \
						and v.distance_to(Geometry3D.get_closest_point_to_segment(v, head_from, head_to)) > head_radius:
					inside = false
			for k in 3:
				(cut if inside else keep).append(index[t + k])
		var material := source.surface_get_material(surface)
		var body_arrays := arrays.duplicate()
		body_arrays[Mesh.ARRAY_INDEX] = keep
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body_arrays)
		body.surface_set_material(body.get_surface_count() - 1, material)
		if cut.size() > 0:
			var piece_arrays := arrays.duplicate()
			piece_arrays[Mesh.ARRAY_INDEX] = cut
			piece_arrays[Mesh.ARRAY_BONES] = null
			piece_arrays[Mesh.ARRAY_WEIGHTS] = null
			piece.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, piece_arrays)
			piece.surface_set_material(piece.get_surface_count() - 1, material)
	if piece.get_surface_count() == 0:
		push_error("lance: no triangles inside the capsule")
		return {}
	mesh.mesh = body
	var holder := MeshInstance3D.new()
	holder.mesh = piece
	skeleton.add_child(holder)
	# The carrying bone: the spec's, or the spine bone nearest the grip.
	var want := String(spec.get("bone", "")).replace(":", "_")
	var best := -1
	var best_d := INF
	var bind := Transform3D.IDENTITY
	for i in mesh.skin.get_bind_count():
		var name := String(mesh.skin.get_bind_name(i))
		if name == "" and mesh.skin.get_bind_bone(i) >= 0:
			name = skeleton.get_bone_name(mesh.skin.get_bind_bone(i))
		var pose := mesh.skin.get_bind_pose(i)
		var d := (pose.affine_inverse().origin).distance_to(a)
		var ok := name == want if want != "" else (name.contains("Spine") or name.contains("Root") or name.contains("Hips"))
		if ok and d < best_d:
			best_d = d
			best = skeleton.find_bone(name)
			bind = pose
	if best < 0:
		push_error("lance: no carrying bone")
		return {}
	return {"holder": holder, "skeleton": skeleton, "bone": best, "bind": bind, "grip": a, "tip": b,
		"level": float(spec.get("level_degrees", -6.0))}.merged(
			{"aim": Vector3(spec["aim"][0], spec["aim"][1], spec["aim"][2])} if spec.has("aim") else {})


func _place_lance(info: Dictionary, u: float) -> void:
	# Rides rigidly on its bone; in a charge (u >= 0) it swings down from its
	# carried angle to level at the enemy for the blow, and back up.
	var sk: Skeleton3D = info["skeleton"]
	var holder: Node3D = info["holder"]
	var rigid: Transform3D = sk.get_bone_global_pose(int(info["bone"])) * Transform3D(info["bind"])
	holder.transform = rigid
	if u < 0.0:
		return
	var couch := smoothstep(0.05, 0.4, u) * (1.0 - smoothstep(0.8, 1.0, u))
	if couch <= 0.0:
		return
	# Level along the lance's own heading (rig axes can be back to front):
	# the tip drops to the horizontal, then a little below it.
	var up := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var grip: Vector3 = rigid * Vector3(info["grip"])
	var dir: Vector3 = (rigid * Vector3(info["tip"]) - grip).normalized()
	# "aim" (mesh space) names the mount's forward when the weapon is carried
	# sideways or upright; otherwise the weapon's own heading.
	var heading: Vector3 = dir
	if info.has("aim"):
		heading = (rigid.basis * Vector3(info["aim"])).normalized()
	var flat := (heading - up * heading.dot(up)).normalized()
	if flat.length() < 1e-6:
		return
	var level := (flat + up * tan(deg_to_rad(float(info["level"])))).normalized()
	var goal := dir.slerp(level, couch).normalized()
	var ax := dir.cross(goal)
	if ax.length() < 1e-6:
		return
	var turn := Basis(ax.normalized(), dir.signed_angle_to(goal, ax.normalized()))
	holder.transform = Transform3D(turn * rigid.basis, grip + turn * (rigid.origin - grip))


func _pose_quad_idle(sk: Skeleton3D, u: float) -> void:
	# A beast or mount at rest: the chest rises and falls, the head nods.
	if sk == null:
		return
	var axes := _quad_axes(sk)
	var up: Vector3 = axes[0]
	var right: Vector3 = axes[2]
	var length: float = axes[3]
	var breath := sin(u * TAU)
	var root := sk.find_bone(_bone(sk, "Root"))
	if root >= 0:
		var rp := sk.get_bone_parent(root)
		var to_parent := Basis.IDENTITY if rp < 0 else sk.get_bone_global_pose(rp).basis.inverse()
		sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + to_parent * (up * breath * 0.012 * length))
	var spine := sk.find_bone(_bone(sk, "Spine_0"))
	if spine >= 0:
		_rotate_bone(sk, spine, Basis(right, deg_to_rad(1.5 * breath)))
	var head := sk.find_bone(_bone(sk, "Head_0"))
	if head >= 0:
		_rotate_bone(sk, head, Basis(right, deg_to_rad(4.0 * sin(u * TAU + 1.0))))


## Legs of a many-legged rig, found by geometry instead of bone names (Tripo
## scrambles crawler labels): ground tips (bone ends near the lowest point)
## that lie close together form one foot; each foot's leg root is its highest
## ancestor that no other foot shares. Cached per skeleton.
var _legs := {}


func _crawl_legs(sk: Skeleton3D, up: Vector3, forward: Vector3, _length: float) -> Array:
	var key := "%d:%d:%s" % [sk.get_instance_id(), sk.get_bone_count(), sk.get_bone_name(0)]
	if _legs.has(key):
		return _legs[key]
	var n := sk.get_bone_count()
	var lo := INF
	var hi := -INF
	for bi in n:
		if sk.get_bone_parent(bi) < 0:
			continue  # Tripo's Root can sit below the feet
		var y := sk.get_bone_global_pose(bi).origin.dot(up)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var tall := maxf(hi - lo, 1e-3)
	# Footprint diagonal, to tell an ankle fork (close to its toes) from the body.
	var box := AABB()
	var first := true
	for bi in n:
		if sk.get_bone_parent(bi) < 0:
			continue
		var o := sk.get_bone_global_pose(bi).origin
		box = AABB(o, Vector3.ZERO) if first else box.expand(o)
		first = false
	var span := Vector2(box.size.x, box.size.z).length()
	var height := func(b: int) -> float: return sk.get_bone_global_pose(b).origin.dot(up)
	# Foot candidates: bone chain ends in the lower half of the body.
	var is_tip := {}
	for bi in n:
		if sk.get_bone_parent(bi) >= 0 and sk.get_bone_children(bi).is_empty() and height.call(bi) - lo < 0.65 * tall:
			is_tip[bi] = true
	var reaches := {}  # bone -> true when a foot candidate hangs below it
	for t in is_tip:
		var b: int = t
		while b >= 0 and not reaches.has(b):
			reaches[b] = true
			b = sk.get_bone_parent(b)
	var legs: Array = []
	var seen := {}
	var right := up.cross(forward).normalized()
	for t in is_tip:
		# Climb while this branch is the only one with a foot below it; a fork
		# close to the tip is an ankle with toes, so climb past it too.
		var b: int = t
		while true:
			var p := sk.get_bone_parent(b)
			if p < 0 or sk.get_bone_parent(p) < 0:
				break
			var branches := 0
			for c in sk.get_bone_children(p):
				if reaches.has(c):
					branches += 1
			var ankle := (sk.get_bone_global_pose(p).origin - sk.get_bone_global_pose(t).origin).length() < 0.12 * span
			if branches > 1 and not ankle:
				break
			b = p
		if seen.has(b):
			continue
		seen[b] = true
		var tip := sk.get_bone_global_pose(t).origin
		# A leg has at least two segments; head, spine and tail chains that
		# reach the ground (a low head, an abdomen) are not legs.
		if b == t or _chain_named(sk, b, ["Head", "Spine", "Tail"]):
			continue
		legs.append({"bone": b, "tip": tip, "side": signf(tip.dot(right)), "ahead": tip.dot(forward)})
	_legs[key] = legs
	return legs


func _chain_named(sk: Skeleton3D, bi: int, words: Array) -> bool:
	# True when bone bi or any bone below it carries one of the words.
	var stack := [bi]
	while not stack.is_empty():
		var b: int = stack.pop_back()
		for w in words:
			if sk.get_bone_name(b).contains(w):
				return true
		stack.append_array(sk.get_bone_children(b))
	return false


## A walk cycle for crawlers (spiders, crabs, beetles, cinderlings) on any
## rig: legs swing fore and aft in two alternating sets (front and back legs
## of one side with the middle of the other), lifting as they swing forward,
## and the body bobs. Stays in place; the game moves the unit.
func _pose_crawl(sk: Skeleton3D, u: float, amount := 1.0) -> void:
	if sk == null:
		return
	var axes := _quad_axes(sk)
	var up: Vector3 = axes[0]
	var forward: Vector3 = axes[1]
	var right: Vector3 = axes[2]
	var length: float = axes[3]
	var f: Array = _job.get("forward", [])
	if f.size() == 3:
		forward = Vector3(f[0], f[1], f[2])
		forward = (forward - up * forward.dot(up)).normalized()
		right = up.cross(forward).normalized()
	var legs := _crawl_legs(sk, up, forward, length)
	# Rank legs front to back on each side, for the alternating sets.
	var sides := {-1.0: [], 0.0: [], 1.0: []}
	for leg in legs:
		sides[leg["side"]].append(leg)
	var swing := deg_to_rad(20.0) * amount
	var lift := deg_to_rad(14.0) * amount
	for side in sides:
		var row: Array = sides[side]
		row.sort_custom(func(a, b): return a["ahead"] > b["ahead"])
		for i in row.size():
			var leg: Dictionary = row[i]
			var bi: int = leg["bone"]
			var phase := u * TAU + (PI if (i % 2 == 1) != (side < 0.0) else 0.0)
			var origin := sk.get_bone_global_pose(bi).origin
			var v: Vector3 = leg["tip"] - origin
			# Signs so that +swing moves the foot forward and +lift raises it.
			var s_fwd := 1.0 if (Basis(right, 0.1) * v - v).dot(forward) > 0.0 else -1.0
			var s_up := 1.0 if (Basis(forward, 0.1) * v - v).dot(up) > 0.0 else -1.0
			var raise := maxf(0.0, cos(phase))  # in the air while swinging forward
			_rotate_bone(sk, bi, Basis(forward, s_up * lift * raise) * Basis(right, s_fwd * swing * sin(phase)))
	var root := sk.find_bone(_bone(sk, "Root"))
	if root >= 0:
		var rp := sk.get_bone_parent(root)
		var to_parent := Basis.IDENTITY if rp < 0 else sk.get_bone_global_pose(rp).basis.inverse()
		sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + to_parent * (up * 0.015 * length * absf(sin(u * TAU * 2.0))))


## Death for rigs without a death clip (beasts, mounts, crawlers, flyers):
## the legs give way, the body sinks and rolls onto its side, the head drops.
var _collapse_roll := {}


func _pose_collapse(sk: Skeleton3D, u: float, amount := 1.0) -> void:
	if sk == null:
		return
	var axes := _quad_axes(sk)
	var up: Vector3 = axes[0]
	# Which way to roll over: the rig's own "forward" is a guess (wings and
	# mounts fool it), so try rolling about both level axes, both ways, and keep
	# the one that ends lowest (on its side, not standing on end).
	var key := "%d:%d:%s" % [sk.get_instance_id(), sk.get_bone_count(), sk.get_bone_name(0)]
	if not _collapse_roll.has(key):
		var saved := []
		for bi in sk.get_bone_count():
			saved.append([sk.get_bone_pose_position(bi), sk.get_bone_pose_rotation(bi), sk.get_bone_pose_scale(bi)])
		var best := INF
		var pick := Basis(axes[1], deg_to_rad(-70.0))
		for axis in [axes[1], axes[2]]:
			for sgn in [-1.0, 1.0]:
				var roll := Basis(axis, deg_to_rad(70.0) * sgn)
				_collapse_with(sk, 1.0, amount, up, axes, roll)
				var top := -INF
				var low := INF
				for bi in sk.get_bone_count():
					var h := sk.get_bone_global_pose(bi).origin.dot(up)
					top = maxf(top, h)
					low = minf(low, h)
				if top - low < best - 0.001:
					best = top - low
					pick = roll
				for bi in sk.get_bone_count():
					sk.set_bone_pose_position(bi, saved[bi][0])
					sk.set_bone_pose_rotation(bi, saved[bi][1])
					sk.set_bone_pose_scale(bi, saved[bi][2])
		_collapse_roll[key] = pick
	_collapse_with(sk, u, amount, up, axes, _collapse_roll[key])


func _collapse_with(sk: Skeleton3D, u: float, amount: float, up: Vector3, axes: Array, roll: Basis) -> void:
	var forward: Vector3 = axes[1]
	var right: Vector3 = axes[2]
	var legs := _crawl_legs(sk, up, forward, axes[3])
	var buckle := smoothstep(0.0, 0.45, u)
	var fall := smoothstep(0.25, 0.85, u)
	var root := sk.find_bone(_bone(sk, "Root"))
	if root < 0:
		root = 0
	var stand := 0.0
	for leg in legs:
		stand = maxf(stand, (sk.get_bone_global_pose(leg["bone"]).origin - leg["tip"]).dot(up))
	var rp := sk.get_bone_parent(root)
	var to_parent := Basis.IDENTITY if rp < 0 else sk.get_bone_global_pose(rp).basis.inverse()
	var floor_rest := _lowest(sk, up)
	sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + to_parent * (-up * stand * 0.3 * buckle * amount))
	_rotate_bone(sk, root, Basis(Quaternion.IDENTITY.slerp(roll.get_rotation_quaternion(), clampf(fall * amount, 0.0, 1.0))))
	# Legs fold under the body: front legs forward, hind legs back.
	var mid := 0.0
	for leg in legs:
		mid += float(leg["ahead"]) / maxf(1.0, legs.size())
	for leg in legs:
		var bi: int = leg["bone"]
		var v: Vector3 = leg["tip"] - sk.get_bone_global_pose(bi).origin
		var s_fwd := 1.0 if (Basis(right, 0.1) * v - v).dot(forward) > 0.0 else -1.0
		var fold := (1.0 if float(leg["ahead"]) >= mid else -1.0) * s_fwd
		_rotate_bone(sk, bi, Basis(right, fold * deg_to_rad(45.0) * buckle))
	var head := sk.find_bone(_bone(sk, "Head_0"))
	if head >= 0:
		_swing(sk, sk.get_bone_name(head), forward - up * 1.5, 0.5 * fall)
	# Rolling over swings bones below the ground: lift the body back onto it.
	var sunk := floor_rest - _lowest(sk, up)
	if sunk > 0.0:
		sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + to_parent * (up * sunk))


func _lowest(sk: Skeleton3D, up: Vector3) -> float:
	var lo := INF
	for bi in sk.get_bone_count():
		if sk.get_bone_parent(bi) >= 0:
			lo = minf(lo, sk.get_bone_global_pose(bi).origin.dot(up))
	return lo


func _drop_pole(info: Dictionary, u: float) -> void:
	# Death: the pole leaves the hand and topples flat beside the body, across
	# the view, instead of following the falling arm into the ground.
	var sk: Skeleton3D = info["skeleton"]
	var pole: Node3D = info["holder"]
	var hand := sk.get_bone_global_pose(int(info["bone"]))
	if u <= 0.0 or not info.has("dropped"):
		var p0: Vector3 = hand * info["local"][0]
		var p1: Vector3 = hand * info["local"][1]
		var dir := (p1 - p0).normalized()
		var flat := Vector3(dir.x, 0.0, dir.z)
		var side := sk.get_bone_global_pose(sk.find_bone(_bone(sk, "RightArm"))).origin - sk.get_bone_global_pose(sk.find_bone(_bone(sk, "LeftArm"))).origin
		side.y = 0.0
		# Topple sideways (across the view) rather than along the facing.
		if side.length() > 1e-4:
			flat = side.normalized() * (1.0 if side.dot(flat) >= 0.0 else -1.0)
		elif flat.length() > 1e-4:
			flat = flat.normalized()
		else:
			flat = Vector3.RIGHT
		var ground := minf(sk.get_bone_global_rest(sk.find_bone(_bone(sk, "RightToeBase"))).origin.y, p0.y)
		info["dropped"] = {"butt": p0, "dir": dir, "flat": flat, "ground": ground + float(info.get("radius", 0.02))}
	var d: Dictionary = info["dropped"]
	var fall := smoothstep(0.0, 1.0, clampf(u / 0.7, 0.0, 1.0))
	fall *= fall
	var dir0: Vector3 = d["dir"]
	var flat: Vector3 = d["flat"]
	var dir := dir0.slerp(flat, fall).normalized()
	var butt: Vector3 = d["butt"]
	butt = butt.lerp(Vector3(butt.x, float(d["ground"]), butt.z), fall)
	var x_axis := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	pole.transform = Transform3D(Basis(x_axis, dir, x_axis.cross(dir)), butt)
	info["dir"] = dir


func _render() -> void:
	var vp := _stage()
	var yaw := float(_job.get("yaw_degrees", 60.0))
	var scale := float(_job.get("model_scale", 1.0))
	var placed := false
	var report := {}
	for action in _job["actions"]:
		var spec: Dictionary = _job["actions"][action]
		var model := _load_model(String(spec["model"]))
		if model == null:
			quit(1)
			return
		model.rotation_degrees.y = yaw
		model.scale = Vector3.ONE * scale
		vp.add_child(model)
		var pose := String(spec.get("pose", ""))
		var weapon := {}
		if _job.has("weapon"):
			weapon = _attach_pole(model, _job["weapon"], pose != "" or action == "death")
		var ball := {}
		if _job.has("throw"):
			ball = _split_ball(model, _job["throw"])
		var lance := {}
		if _job.has("lance"):
			lance = _split_lance(model, _job["lance"])
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var clip := String(spec.get("clip", ""))
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		var sk: Skeleton3D = null if skeletons.is_empty() else skeletons[0] as Skeleton3D
		# A posed action may use a rigged model without clips (rest pose).
		var posed_rest := pose != "" and clip == "" and (player == null or player.get_animation_list().is_empty())
		if not posed_rest and (player == null or (clip != "" and not player.has_animation(clip))):
			push_error("%s: clip '%s' not found in %s" % [action, clip, spec["model"]])
			quit(1)
			return
		if not posed_rest and clip == "":
			clip = player.get_animation_list()[0]
		var anim: Animation = null if posed_rest else player.get_animation(clip)
		var length := 0.0 if anim == null else anim.length
		if not placed:
			if anim != null:
				player.play(clip)
				player.seek(0.0, true)
				player.pause()
			await process_frame
			var box := _bounds(model)
			# A beast's walk can drop the body below its rest pose (a mount's
			# hooves left the frame), so beasts frame their whole first clip.
			if anim != null and sk != null and sk.find_bone(_bone(sk, "Hips")) < 0:
				for k in 6:
					player.play(clip)
					player.seek(length * k / 5.0, true)
					player.pause()
					await process_frame
					box = box.merge(_bounds(model))
				player.seek(0.0, true)
			_camera(vp, box)
			placed = true
		var count := int(spec.get("frames", 6))
		var loop := bool(spec.get("loop", false))
		var start := float(spec.get("start", 0.0)) * length
		var stop := float(spec.get("end", 1.0)) * length
		# "in_place": cancel root motion that walks the unit out of its cell
		# (the hips drift linearly from the first to the last key).
		var hips := -1 if sk == null else sk.find_bone(_bone(sk, "Hips"))
		var drift := Vector3.ZERO
		if bool(spec.get("in_place", false)) and anim != null and hips >= 0:
			player.play(clip)
			player.seek(start, true)
			var p0 := sk.get_bone_pose_position(hips)
			player.seek(stop, true)
			drift = sk.get_bone_pose_position(hips) - p0
			player.pause()
		for i in count:
			var t := start + (stop - start) * float(i) / float(count if loop else maxi(1, count - 1))
			# Poses add to the current bone pose, and a clip may not key every
			# bone, so posed frames start from rest before the clip is applied.
			if pose != "" and sk != null:
				sk.reset_bone_poses()
			if anim != null:
				player.play(clip)
				player.seek(t if pose == "" else 0.0, true)
				player.pause()
				if drift != Vector3.ZERO and pose == "":
					var frac := (t - start) / maxf(stop - start, 1e-6)
					sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) - drift * frac)
			if pose != "":
				await process_frame
				var u := float(i) / float(count if loop else maxi(1, count - 1))
				if pose == "pole_thrust" and not weapon.is_empty():
					_pose_thrust(weapon, u)
				elif pose == "quad_lunge":
					_pose_lunge(sk, u, float(spec.get("amount", 1.0)))
				elif pose == "quad_charge":
					_pose_charge(sk, u, float(spec.get("amount", 1.0)))
				elif pose in ["bow_draw", "cast", "throw"]:
					_pose_arms(sk, u, pose, float(spec.get("hand_turn", 0.0)))
				elif pose == "quad_idle":
					_pose_quad_idle(sk, u)
				elif pose == "collapse":
					_pose_collapse(sk, u, float(spec.get("amount", 1.0)))
				elif pose == "crawl":
					_pose_crawl(sk, u, float(spec.get("amount", 1.0)))
				elif pose == "wing_hover":
					_pose_wings(sk, u, false)
				elif pose == "wing_dive":
					_pose_wings(sk, u, true)
				else:
					push_error("%s: unknown pose '%s'" % [action, pose])
					quit(1)
					return
			if sk != null:
				_hold(sk, action)
			if not lance.is_empty():
				await process_frame
				var couch := pose in ["quad_charge", "quad_lunge"]
				_place_lance(lance, float(i) / float(count if loop else maxi(1, count - 1)) if couch else -1.0)
			if not ball.is_empty():
				_place_ball(ball, action, float(i) / float(count if loop else maxi(1, count - 1)))
			if action == "death" and pose == "" and not weapon.is_empty():
				await process_frame
				_drop_pole(weapon, float(i) / float(maxi(1, count - 1)))
			await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.save_png("%s/%s_%d.png" % [_out, action, i])
		report[action] = {"clip": clip, "length": length, "frames": count}
		model.queue_free()
		await process_frame
	var f := FileAccess.open(_out.path_join("render.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	quit(0)
