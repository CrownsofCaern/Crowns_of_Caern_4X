extends SceneTree
## Flags live 3D clips that look odd: pops (a bone jumps far between two
## frames), loop seams that do not close, bodies that sink or lie down in
## clips other than death, and figures that spin round.
##   godot --headless --path . --script res://tools/assets/anim_audit.gd -- [ids...]
## Prints one line per suspicious clip, worst first.

const STEPS := 24


func _initialize() -> void:
	var ids := Array(OS.get_cmdline_user_args())
	if ids.is_empty():
		for f in DirAccess.get_files_at("res://assets/units3d/"):
			if f.ends_with(".glb"):
				ids.append(f.get_basename())
	ids.sort()
	var found := []
	for id in ids:
		var unit := LiveUnit.spawn(id)
		if unit == null:
			continue
		root.add_child(unit)
		var skel := _skeleton(unit)
		if skel == null:
			unit.free()
			continue
		var h := maxf(0.3, unit.height)
		for clip in ["idle", "move", "attack", "death"]:
			if not unit.has_clip(clip):
				continue
			var anim := unit.player.get_animation(clip)
			unit.player.play(clip)
			unit.player.seek(0.0, true)
			await process_frame
			await process_frame
			var frames := []
			var heads := []
			for s in STEPS + 1:
				unit.player.seek(anim.length * float(s) / float(STEPS), true)
				unit.player.pause()
				await process_frame
				frames.append(_pose(skel))
				heads.append(_hips_heading(skel))
			var pop := 0.0
			for s in STEPS:
				pop = maxf(pop, _jump(frames[s], frames[s + 1]))
			var seam := _jump(frames[STEPS], frames[0]) if clip in LiveUnit.LOOPS else 0.0
			var top0 := _top(frames[0])
			var low := INF
			var spin := 0.0
			for s in STEPS + 1:
				low = minf(low, _top(frames[s]))
				if clip != "death":
					spin = maxf(spin, absf(angle_difference(float(heads[0]), float(heads[s]))))
			var sink := (top0 - low) / h if clip != "death" else 0.0
			var pop_ok: float = {"idle": 0.12, "move": 0.18, "attack": 0.3, "death": 0.4}[clip]
			var score := maxf(pop / h / pop_ok, maxf(seam / h / 0.15, maxf(sink / 0.35, spin / 0.9)))
			if OS.has_environment("AUDIT_ALL") or score >= 1.0:
				found.append([score, "%-24s %-6s pop %.2f seam %.2f sink %.2f spin %.0f deg" % [id, clip, pop / h, seam / h, sink, rad_to_deg(spin)]])
		unit.free()
	found.sort_custom(func(a, b): return a[0] > b[0])
	for f in found:
		print("%.1f  %s" % [f[0], f[1]])
	print("AUDIT %d suspicious clips" % found.size())
	quit(0)


func _skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _skeleton(c)
		if s != null:
			return s
	return null


## Bone positions in the unit's space (metres).
func _pose(skel: Skeleton3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var xf := Transform3D.IDENTITY
	var n: Node = skel
	while n is Node3D and not (n is LiveUnit):
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	for b in skel.get_bone_count():
		out.append(xf * skel.get_bone_global_pose(b).origin)
	return out


func _jump(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, a[i].distance_to(b[i]))
	return m


func _top(p: PackedVector3Array) -> float:
	var t := -INF
	for v in p:
		t = maxf(t, v.y)
	return t


## Facing of the root bone (hips) in the ground plane.
func _hips_heading(skel: Skeleton3D) -> float:
	var b := 0
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower().contains("hips"):
			b = i
			break
	var z := skel.get_bone_global_pose(b).basis.z
	return atan2(z.x, z.z)
