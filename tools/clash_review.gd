extends SceneTree
## Plays one recorded battle in the live clash view, for recording a smooth
## review video with Godot's movie writer (fixed frame rate, every frame):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --write-movie /tmp/clash/frame.png --script res://tools/clash_review.gd -- armies
## Presets: "armies" (two full field armies), "orders" (Concord holding a
## line against an all-out Ashen attack) or "model3d" (Concord against Ashen
## with the units baked from 3D models).
## Quick stills instead of a video (fast-forwarded at 4x, needs a display):
##   xvfb-run -a godot --path . --script res://tools/clash_review.gd -- armies stills=/tmp/s at=8,16,24
## saves the view at those battle seconds as <dir>/still_<s>.png and quits.


func _initialize() -> void:
	_run.call_deferred()


func _side(pairs: Array, title: String, orders: Dictionary = {}) -> Dictionary:
	var stacks := []
	for i in pairs.size():
		stacks.append({"slot": i, "creature": pairs[i][0], "count": pairs[i][1]})
	var hero: Variant = null
	if not orders.is_empty():
		hero = {"name": title, "attack": 2, "defense": 2, "power": 0, "knowledge": 0, "skills": {}, "orders": orders}
	return {"name": title, "hero": hero, "stacks": stacks}


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var args := OS.get_cmdline_user_args()
	var preset := args[0] if not args.is_empty() else "armies"
	var left: Dictionary
	var right: Dictionary
	var seed_value := 11
	if preset == "model3d":
		# Concord against Ashen with the units baked from 3D models.
		left = _side([["pike_militia", 40], ["shieldwarden", 14], ["longbowman", 30], ["lightbearer", 4], ["lancer", 6], ["sunhawk_rider", 3], ["bastion_colossus", 1]], "Aldmere Concord")
		right = _side([["flayer", 16], ["brimstone_hurler", 20], ["ash_witch", 8], ["scorchhound", 12], ["gorgewing", 3], ["pyre_titan", 1]], "Ashen Host")
		seed_value = 31
	elif preset == "orders":
		left = _side([["pike_militia", 40], ["shieldwarden", 12], ["longbowman", 30], ["lancer", 6], ["lightbearer", 3], ["bastion_colossus", 1]],
			"Aldmere Concord", {"stance": "defensive", "focus": "protect_archers"})
		right = _side([["cinderling", 60], ["flayer", 14], ["brimstone_hurler", 20], ["scorchhound", 12], ["gorgewing", 2]],
			"Ashen Host", {"stance": "aggressive", "focus": "hunt_archers"})
		seed_value = 21
	else:
		left = _side([["pike_militia", 60], ["longbowman", 30], ["ash_witch", 12], ["shambler", 30], ["thornwolf", 14], ["cairn_giant", 3], ["frost_drake", 4]], "Host of the West")
		right = _side([["shambler", 70], ["marrow_archer", 30], ["pike_militia", 40], ["frost_shaman", 12], ["thornwolf", 16], ["winter_wyrm_ancient", 1], ["doom_bombard", 3]], "Host of the East")
	var result := CombatSimulator.new(GameData.get_default()).simulate(CombatSimulator.make_setup(left, right, "grass", seed_value), true)
	var viewer := BattleViewer.new()
	root.add_child(viewer)
	viewer.build()
	viewer.play(result)
	viewer._set_speed(1.0, false)
	var still_dir := ""
	var still_at: Array = []
	for a in args:
		if String(a).begins_with("stills="):
			still_dir = String(a).substr(7)
		elif String(a).begins_with("at="):
			for t in String(a).substr(3).split(","):
				still_at.append(float(t))
	if still_dir != "":
		viewer._set_speed(4.0, false)
		var clock := 0.0
		while viewer.is_playing() and not still_at.is_empty():
			await process_frame
			clock = viewer._clock
			if clock >= float(still_at[0]):
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/still_%d.png" % [still_dir, int(still_at[0])])
				print("STILL ", still_at[0])
				still_at.pop_front()
		quit()
		return
	# Effect pacing: every particle effect that starts, by frame.
	var fx_frames: Array = []
	var big_frames: Array = []
	var frames_box := [0]
	var count_fx := func(n: Node) -> void:
		if n is CPUParticles2D:
			fx_frames.append(frames_box[0])
		if n.has_meta("element") or (n.z_index == 6 and not n is CPUParticles2D):
			# Element effects: bursts, what they leave behind, missiles.
			big_frames.append(frames_box[0])
	viewer._overlay.child_entered_tree.connect(count_fx)
	viewer._field.child_entered_tree.connect(count_fx)
	var lit := {}   # second -> true when an element effect was on screen
	var stand := {"all": [0, 0], "big": [0, 0]}   # [idle with a foe in reach, in reach]
	while viewer.is_playing() and frames_box[0] < 30 * 120:
		await process_frame
		frames_box[0] += 1
		if frames_box[0] % 10 == 0:
			_count_standing(viewer, stand)
		for n in viewer._overlay.get_children():
			if n.has_meta("element") or (n.z_index == 6 and not n is CPUParticles2D):
				lit[frames_box[0] / 30] = true
				break
	print(pacing_report(fx_frames, frames_box[0], 30, "FX_ALL"))
	print(pacing_report(big_frames, frames_box[0], 30, "FX_ELEMENT"))
	var dark := []
	for k in range(2, frames_box[0] / 30 - 2):
		if not lit.has(k):
			dark.append(k)
	print("FX_PRESENCE element effects on screen %d of %d fight seconds; dark seconds %s" % [
		frames_box[0] / 30 - 4 - dark.size(), frames_box[0] / 30 - 4, str(dark)])
	for k in ["all", "big"]:
		var c: Array = stand[k]
		print("STANDING %s idle_in_reach=%d of %d samples (%.0f%%)" % [k, c[0], c[1], 100.0 * c[0] / maxf(1.0, c[1])])
	print("WHY ", stand)
	print("CLASH_REVIEW_OK ", frames_box[0])
	quit()


## Samples every standing 3D figure that has an enemy figure in arm's reach:
## how often it just idles there instead of fighting (playtest note: "giants stand
## still half the time although surrounded"). "big" = stacks of 3 or fewer.
static func _count_standing(viewer: BattleViewer, stand: Dictionary) -> void:
	for k in viewer._figs:
		var f: BattleFigure = viewer._figs[k]
		if f.is_dead():
			continue
		var big := f.members.size() <= 3
		for i in f.alive_members():
			var u := f.live_unit(i)
			if u == null or f.is_moving(i):
				continue
			var near := viewer._nearest_foe(f, i)
			if near.is_empty() or float(near[2]) > viewer._reach(f, near[0]):
				# Front-line figures standing about, out of every fight: the
				# "few steps, then stand" of a stop-and-go march.
				if f.formation in ["front", "flank"] and not viewer._engaged.has(k) and viewer._round_at >= 0.0:
					var side := int(String(k).get_slice(":", 0))
					var w := "front_held" if viewer._held_side() == side else "front_waiting"
					var first := int(viewer._first_fight.get(k, -1))
					var now := int(viewer._replay.steps.size())
					w += "_nofight" if first < 0 else ("_mid" if absf(f.home.x - viewer._contact_x(side)) > 30.0 else "_at_line")
					if f.formation == "flank":
						w += "_flank"
					stand[w] = int(stand.get(w, 0)) + 1
				continue
			var idle := u.action in ["idle", "move"] and not u.attack_pending()
			if idle:
				var why := "brawl" if f.is_brawling(i) else "nobrawl"
				if not u.has_clip("attack"):
					why = "noclip"
				stand[why] = int(stand.get(why, 0)) + 1
				if why == "nobrawl":
					var kk: String = "eng" if viewer._engaged.has(k) else "free"
					stand[kk] = int(stand.get(kk, 0)) + 1
			for key in (["all", "big"] if big else ["all"]):
				stand[key][1] += 1
				if idle:
					stand[key][0] += 1


## Effects per second over the battle, and the longest stretch without one
## (after the first effect), so a change in pacing shows as numbers.
static func pacing_report(fx_frames: Array, frames: int, fps: int, title: String) -> String:
	var seconds := int(ceil(float(frames) / fps))
	var per := []
	per.resize(maxi(1, seconds))
	per.fill(0)
	for f in fx_frames:
		per[mini(per.size() - 1, int(f) / fps)] += 1
	var longest := 0
	for k in range(1, fx_frames.size()):
		longest = maxi(longest, int(fx_frames[k]) - int(fx_frames[k - 1]))
	var quiet := 0
	for k in per.size():
		if per[k] == 0 and k > 1 and k < per.size() - 2:
			quiet += 1
	return "%s total=%d seconds=%d quiet_seconds=%d longest_gap=%.2fs per_second=%s" % [
		title, fx_frames.size(), seconds, quiet, float(longest) / fps, str(per)]
