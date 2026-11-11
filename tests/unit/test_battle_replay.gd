extends "res://tests/test_case.gd"
## The live battle view: the log carries enough to replay a battle, the replay
## ends on the result's survivors, drawn animation strips are well formed, and
## the animation loader supports drawn clips and still-sprite fallback.

const TMP_SETTINGS := "user://test_battle_viewer.cfg"


func _side(stacks: Array, name: String) -> Dictionary:
	var out := []
	for i in stacks.size():
		out.append({"slot": i, "creature": stacks[i][0], "count": stacks[i][1]})
	return {"name": name, "hero": null, "stacks": out}


func _battle(seed_value: int) -> Dictionary:
	var a := _side([["pike_militia", 30], ["longbowman", 20], ["thornwolf", 6]], "Wren")
	var b := _side([["thornwolf", 14], ["longbowman", 10]], "Wolves")
	return CombatSimulator.new(data).simulate(CombatSimulator.make_setup(a, b, "grass", seed_value), true)


func test_log_names_the_stacks_by_side_and_slot() -> void:
	var r := _battle(5)
	assert_gt(r["log"].size(), 3)
	for e in r["log"]:
		assert_true(e.has("actor_slot") and e.has("target_slot") and e.has("target_count"), str(e))
		if int(e["target_slot"]) >= 0:
			assert_true(int(e["target_side"]) in [0, 1], str(e))


func test_replay_ends_on_the_result_survivors() -> void:
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var r := _battle(seed_value)
		var rep := BattleReplay.from_result(r)
		var counts := rep.final_counts()
		for s in 2:
			for st in r["sides"][s]["stacks"]:
				assert_eq(int(counts[BattleReplay.key(s, int(st["slot"]))]), int(st["end"]), "seed %d %s" % [seed_value, st["name"]])


func test_replay_steps_point_at_known_stacks() -> void:
	var rep := BattleReplay.from_result(_battle(3))
	var keys := rep.all_keys()
	var kinds := {}
	for st in rep.steps:
		kinds[st["kind"]] = true
		if st["kind"] in [BattleReplay.MELEE, BattleReplay.ANSWER, BattleReplay.SHOT]:
			assert_true(keys.has(st["actor"]) and keys.has(st["target"]), str(st))
	assert_true(kinds.has(BattleReplay.ROUND))
	assert_true(kinds.has(BattleReplay.MELEE))
	assert_true(kinds.has(BattleReplay.SHOT), "longbowmen shoot")


func test_battalions_split_one_group_per_enemy() -> void:
	var parts := BattleViewer.split_evenly([0, 1, 2, 3, 4, 5, 6, 7, 8], ["1:0", "1:1", "1:2"])
	assert_eq(parts["1:0"], [0, 1, 2])
	assert_eq(parts["1:1"], [3, 4, 5])
	assert_eq(parts["1:2"], [6, 7, 8])
	var uneven := BattleViewer.split_evenly([0, 1, 2, 3, 4], ["a", "b"])
	assert_eq(uneven["a"].size() + uneven["b"].size(), 5, "every figure fights")
	var lone := BattleViewer.split_evenly([4], ["a", "b"])
	assert_eq(lone["a"], [4], "a lone figure fights every foe")
	assert_eq(lone["b"], [4])


func test_figures_fall_where_they_were_struck() -> void:
	var f := BattleFigure.new()
	f.key = "1:0"
	f.setup("pike_militia", 40, -1.0, 0.0)
	var fell := f.apply_count(30, [0, 1], 1.0, false)
	assert_eq(fell, [0, 1], "the struck figures fall first")
	assert_false(f.is_member_alive(0))
	assert_true(f.is_member_alive(8))
	assert_eq(f.standing_count(), BattleFigure.standing(30, 40, 9))
	fell = f.apply_count(20, [], 1.0, false)
	assert_eq(fell, [8, 7], "then from the back of the block")
	assert_true(_lies_down(f.sprite), "the fallen lie down")
	f.free()


func test_figures_walk_on_their_own() -> void:
	var f := BattleFigure.new()
	f.key = "0:0"
	f.setup("pike_militia", 40, 1.0, 0.0)
	var paces := {}
	for i in f.members.size():
		paces[snappedf(f._pace[i], 0.001)] = true
	assert_gt(paces.size(), 1, "figures keep their own pace")
	f.send(0, f.member_pos(0) + Vector2(120, 0), 1.0)
	f.send(1, f.member_pos(1) + Vector2(120, 0), 1.0, 0.5)
	assert_false(f.arrived([0, 1]))
	for k in 6:
		f._process(0.1)
	assert_gt(f._holders[0].position.x, f._holders[1].position.x + 20.0, "the late starter is behind")
	for k in 40:
		f._process(0.1)
	assert_true(f.arrived([0, 1]))
	f.free()


func test_strips_are_split_into_square_frames() -> void:
	var img := Image.create(128 * 5, 128, false, Image.FORMAT_RGBA8)
	var frames := CreatureAnims.split(ImageTexture.create_from_image(img))
	assert_eq(frames.size(), 5)
	assert_eq((frames[4] as AtlasTexture).region, Rect2(512, 0, 128, 128))


func test_drawn_animations_are_well_formed() -> void:
	assert_eq(CreatureAnims.audit(data.creatures), [], "assets/animations")


func test_audit_flags_bad_files() -> void:
	var dir := "user://test_anims"
	DirAccess.make_dir_recursive_absolute(dir + "/thornwolf")
	DirAccess.make_dir_recursive_absolute(dir + "/no_such_beast")
	Image.create(128 * 4, 128, false, Image.FORMAT_RGBA8).save_png(dir + "/thornwolf/thornwolf_move.png")
	Image.create(100, 128, false, Image.FORMAT_RGBA8).save_png(dir + "/thornwolf/thornwolf_attack.png")
	Image.create(128, 128, false, Image.FORMAT_RGBA8).save_png(dir + "/thornwolf/wolf_idle.png")
	var problems := CreatureAnims.audit(data.creatures, dir)
	assert_eq(problems.size(), 3, str(problems))
	for p in ["thornwolf/thornwolf_move.png", "thornwolf/thornwolf_attack.png", "thornwolf/wolf_idle.png", "no_such_beast"]:
		DirAccess.remove_absolute(dir + "/" + p)


func test_missing_animation_falls_back_to_the_still_sprite() -> void:
	assert_eq(CreatureAnims.frames("no_such_creature", "attack"), [])
	# All real creatures now have clips; explicitly exercise missing-art fallback.
	var cached := CreatureAnims._cache.duplicate()
	var sources := CreatureAnims._manifest_used.duplicate()
	for kind in CreatureAnims.KINDS:
		var path := CreatureAnims.path("thornwolf", kind)
		CreatureAnims._cache[path] = []
		CreatureAnims._manifest_used[path] = false
	var f := BattleFigure.new()
	f.setup("thornwolf", 7, 1.0, 0.0)
	assert_eq(f.sprite.sprite_frames.get_frame_count("attack"), 1)
	var timing := f.start_attack()
	assert_gt(timing[1], timing[0])
	f.set_count(0)
	assert_true(f.is_dead())
	f.free()
	CreatureAnims._cache = cached
	CreatureAnims._manifest_used = sources


func test_watch_setting_is_remembered_and_off_by_default() -> void:
	DirAccess.remove_absolute(TMP_SETTINGS)
	assert_false(BattleViewer.watch_enabled(TMP_SETTINGS))
	BattleViewer.set_watch_enabled(true, TMP_SETTINGS)
	assert_true(BattleViewer.watch_enabled(TMP_SETTINGS))
	BattleViewer.set_watch_enabled(false, TMP_SETTINGS)
	assert_false(BattleViewer.watch_enabled(TMP_SETTINGS))
	DirAccess.remove_absolute(TMP_SETTINGS)


func test_3d_setting_is_remembered_and_on_by_default() -> void:
	DirAccess.remove_absolute(TMP_SETTINGS)
	assert_true(BattleViewer.three_d_enabled(TMP_SETTINGS), "3D unless unticked")
	BattleViewer.set_three_d_enabled(false, TMP_SETTINGS)
	assert_false(BattleViewer.three_d_enabled(TMP_SETTINGS), "the sprite battlefield")
	BattleViewer.set_watch_enabled(true, TMP_SETTINGS)
	assert_false(BattleViewer.three_d_enabled(TMP_SETTINGS), "other settings keep it")
	BattleViewer.set_three_d_enabled(true, TMP_SETTINGS)
	assert_true(BattleViewer.three_d_enabled(TMP_SETTINGS))
	DirAccess.remove_absolute(TMP_SETTINGS)


func test_battalions_show_figures_in_proportion_to_the_count() -> void:
	assert_eq(BattleFigure.squad_size("pike_militia", 40), BattleFigure.MAX_MEMBERS, "a horde fills the block")
	assert_eq(BattleFigure.squad_size("pike_militia", 4), 4, "never more figures than creatures")
	assert_eq(BattleFigure.squad_size("bastion_colossus", 3), 1, "a giant stands alone")
	assert_eq(BattleFigure.squad_size("pike_militia", 1), 1)
	assert_eq(BattleFigure.standing(40, 40, 9), 9)
	assert_eq(BattleFigure.standing(1, 40, 9), 1, "one figure while any creature lives")
	assert_eq(BattleFigure.standing(0, 40, 9), 0)
	assert_eq(BattleFigure.standing(20, 40, 9), 5)
	var f := BattleFigure.new()
	f.setup("pike_militia", 40, 1.0, 0.0)
	assert_eq(f.members.size(), 9)
	assert_true(f.sprite == f.members[0])
	f.set_count(20)
	assert_eq(f.standing_count(), 5)
	assert_eq(f.members[4].rotation, 0.0)
	assert_true(_lies_down(f.members[5]), "the fallen lie down")
	f.set_count(40)   # healed and raised
	assert_eq(f.members[8].rotation, 0.0)
	# The block forms up behind the lead figure, away from the enemy.
	for i in range(1, f.members.size()):
		assert_true(f._holders[i].position.x <= 0.0)
	f.free()


func test_viewer_forms_up_and_closes_by_stance() -> void:
	var v := BattleViewer.new()
	v._orders = [{"stance": "aggressive", "focus": "any"}, {"stance": "defensive", "focus": "any"}]
	assert_gt(v._advance_rate(0), v._advance_rate(1), "an all-out attack closes faster than a held line")
	assert_lt(v._stance_shift(0), 0.0, "attackers form up nearer the enemy")
	assert_gt(v._stance_shift(1), 0.0, "a held line forms up further back")
	v.free()


func test_first_fights_say_when_each_stack_meets_the_enemy() -> void:
	var rep := BattleReplay.new()
	rep.steps = [
		{"kind": BattleReplay.SHOT, "round": 0, "actor": "0:1", "target": "1:0"},
		{"kind": BattleReplay.MELEE, "round": 2, "actor": "1:0", "target": "0:0"},
		{"kind": BattleReplay.ANSWER, "round": 2, "actor": "0:0", "target": "1:0"},
		{"kind": BattleReplay.MELEE, "round": 3, "actor": "0:2", "target": "1:0"},
	]
	var first := BattleViewer.first_fights(rep)
	assert_eq(first, {"1:0": 2, "0:0": 2, "0:2": 3})
	assert_false(first.has("0:1"), "shooters never close in")


func test_formations_keep_their_shape() -> void:
	var line := BattleFigure.new()
	line.formation = "front"
	line.span_y = 400.0
	line.setup("pike_militia", 40, 1.0, 0.0)
	var wedge := BattleFigure.new()
	wedge.formation = "flank"
	wedge.span_y = 400.0
	wedge.setup("pike_militia", 40, 1.0, 0.0)
	var tall := func(f: BattleFigure) -> float:
		var lo := INF
		var hi := -INF
		for h in f._holders:
			lo = minf(lo, h.position.y)
			hi = maxf(hi, h.position.y)
		return hi - lo
	assert_gt(tall.call(line), tall.call(wedge), "a front line is wider than a flanking wedge")
	line.free()
	wedge.free()


func test_army_formations_deploy_differently() -> void:
	var line := BattleViewer.deployment("line")
	var wall := BattleViewer.deployment("shield_wall")
	var wedge := BattleViewer.deployment("wedge")
	var skirm := BattleViewer.deployment("skirmish_screen")
	var cres := BattleViewer.deployment("crescent")
	assert_lt(float(wall["front_span"]), float(line["front_span"]), "a shield wall stretches over the whole ground")
	assert_lt(float(wall["back"]), float(line["back"]), "archers stand right behind the wall")
	assert_eq(wall["shape"], "wall")
	assert_gt(float(wedge["arrow"]), 0.0, "the wedge's middle leads")
	assert_true(bool(wedge["flank_centre"]), "riders follow the point")
	assert_lt(float(skirm["back"]), float(skirm["front"]), "skirmishers stand ahead of their line")
	assert_gt(float(skirm["retire"]), float(skirm["front"]), "and fall back behind it")
	assert_lt(float(cres["flank"]), float(cres["front"]), "the crescent's horns reach forward")
	# Block shapes: a wall is wider and shallower than a line, a wedge has a point.
	var shapes := {}
	for shape in ["", "wall", "wedge"]:
		var f := BattleFigure.new()
		f.formation = "front"
		f.shape = shape
		f.span_y = 400.0
		f.setup("pike_militia", 40, 1.0, 0.0)
		var lo := INF
		var hi := -INF
		var deep := 0.0
		for h in f._holders:
			lo = minf(lo, h.position.y)
			hi = maxf(hi, h.position.y)
			deep = maxf(deep, absf(h.position.x))
		shapes[shape] = [hi - lo, deep, f._holders[0].position.y]
		f.free()
	assert_gt(float(shapes["wall"][0]), float(shapes[""][0]), "the wall is wider")
	assert_lt(float(shapes["wall"][1]), float(shapes[""][1]), "and shallower")
	assert_gt(float(shapes["wedge"][1]), float(shapes[""][1]), "the wedge runs deep behind its point")
	assert_between(float(shapes["wedge"][2]), -6.0, 6.0, "the point leads in the middle")


func test_reserve_entries_and_withdrawals_in_the_replay() -> void:
	var rep := BattleReplay.new()
	rep.steps = [
		{"kind": BattleReplay.NOTICE, "type": "reserve", "round": 3, "actor": "0:1", "target": ""},
		{"kind": BattleReplay.NOTICE, "type": "reserve", "round": 4, "actor": "0:1", "target": ""},
	]
	assert_eq(BattleViewer.reserve_entries(rep), {"0:1": 3})
	var step := BattleReplay._step({"type": "withdraw", "round": 5, "actor_side": 0, "actor_slot": 0, "actor_count": 8,
		"target_side": 0, "target_slot": 0, "target_count": 8, "amount": 20, "kills": 2})
	assert_eq(step["kind"], BattleReplay.EFFECT)
	assert_eq(step["text"], "Rear guard -2")
	var notice := BattleReplay._step({"type": "reserve", "round": 3, "actor_side": 0, "actor_slot": 1, "actor_count": 8,
		"target_side": -1, "target_slot": -1, "target_count": 0, "amount": 0, "kills": 0})
	assert_eq(notice["kind"], BattleReplay.NOTICE)


func test_formation_orders_change_the_viewers_advance() -> void:
	var v := BattleViewer.new()
	v._orders = [{"stance": "balanced", "formation": "wedge"}, {"stance": "balanced", "formation": "shield_wall"}]
	assert_gt(v._advance_rate(0), v._advance_rate(1), "a wedge drives in, a wall holds")
	v.free()


func test_locked_fighters_swing_and_walkers_ease_in() -> void:
	var f := BattleFigure.new()
	f.key = "0:0"
	f.setup("pike_militia", 40, 1.0, 0.0)
	f.set_brawling([0], true)
	var swung := false
	for k in 40:
		f._process(0.1)
		swung = swung or f._atk_t[0] >= 0.0
	assert_true(swung, "a fighter locked in melee swings between blows")
	f.form_up()
	assert_false(f._brawl[0], "forming up ends the brawl")
	f.send(1, f.member_pos(1) + Vector2(200, 0), 1.0)
	f._process(0.05)
	var first_step := f._vel[1].length()
	for k in 5:
		f._process(0.05)
	assert_gt(f._vel[1].length(), first_step, "speeds up from a stand")
	f.free()


## A fallen figure either rests on the last frame of its death clip (3D-baked
## units) or is toppled over (drawn units without a death clip).
func _lies_down(m: AnimatedSprite2D) -> bool:
	if m.animation == &"death":
		return not m.is_playing() and m.frame == m.sprite_frames.get_frame_count("death") - 1
	return m.rotation != 0.0
