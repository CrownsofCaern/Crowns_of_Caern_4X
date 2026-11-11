extends "res://tests/test_case.gd"


func test_walk_loops_and_attack_returns_to_rest() -> void:
	# Deserter Crossbows stay drawn (a group, not a 3D model), so they keep the painted 4-frame clips.
	var walk := UnitAnimation.clip("creature_deserter_crossbows", "move")
	var attack := UnitAnimation.clip("creature_deserter_crossbows", "attack")
	assert_eq(walk["frames"].size(), 4)
	assert_eq(UnitAnimation.frame_index(walk, 0.0), 0)
	assert_eq(UnitAnimation.frame_index(walk, 0.15), 1)
	assert_eq(UnitAnimation.frame_index(walk, 0.6), 0)
	assert_eq(UnitAnimation.frame_index(attack, 0.18), 1)
	assert_eq(UnitAnimation.frame_index(attack, 0.6), -1)
	assert_true(UnitAnimation.sample("unknown", "attack", 0.1).is_empty())
	assert_eq(UnitAnimation.events_between(attack, 0.0, 0.2), ["impact"])
	assert_eq(UnitAnimation.events_between(attack, 0.2, 0.3), [])


func test_horse_has_drawn_frames_and_no_whole_body_bob() -> void:
	for t in [0.0, 0.15, 0.3, 0.45]:
		var pose := SpriteMotion.pose(t, 0.0, true)
		assert_eq(pose, Vector3(1, 1, 0))
		var frame := UnitAnimation.sample("hero_knight", "move", t)
		assert_false(frame.is_empty())
		assert_eq(frame["anchor"], Vector2(160, 207))


func test_vignette_plays_visual_actions_without_mutating_input() -> void:
	var units := [{"creature": "pike_militia", "alive": true}]
	var picture := BattleVignette.new()
	picture.setup("grass", units, [])
	picture.play_action(false, 0, "attack")
	assert_eq(picture.left[0]["action"], "attack")
	assert_false(units[0].has("action"))
	picture.free()


## Creatures whose animation group is only planned (no sheet painted yet) in
## assets/specs/creature_animations.json. Today that is the cobolt group from
## #159: its sheet is still to be drawn, and the battle falls back to the lunge.
func _planned_animation_creatures() -> Array:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/creature_animations.json"))
	var planned := []
	for group in spec["groups"]:
		if String(group.get("generation_status", "")) == "planned":
			for unit in group["units"]:
				planned.append("creature_" + String(unit["id"]))
	return planned


func test_every_creature_has_both_actions_and_shared_anchors() -> void:
	var manifest := UnitAnimation.manifest()
	var planned := _planned_animation_creatures()
	var pending: Array = manifest["pending"].duplicate()
	# A planned unit may already play clips baked from its 3D model.
	for sid in pending:
		assert_true(planned.has(sid), "%s: only planned groups may be pending" % sid)
	for sid in planned:
		assert_true(String(sid).begins_with("creature_cobolt_"), "%s: only the cobolt sheet is still to be painted" % sid)
	for id in data.creatures:
		if pending.has("creature_" + String(id)):
			continue
		for action in ["move", "attack"]:
			var animation := UnitAnimation.clip("creature_" + String(id), action)
			assert_false(animation.is_empty(), String(id) + "/" + action)
			var frame := UnitAnimation.sample("creature_" + String(id), action, 0.22)
			assert_false(frame.is_empty(), String(id))
			if not frame.is_empty():
				assert_eq(frame["anchor"], Vector2(160, 207))


func test_live_battle_figures_use_atlas_poses_and_impact_timing() -> void:
	var figure := BattleFigure.new()
	figure.setup("deserter_crossbows",10,1.0,0.0)
	assert_true(figure.has_move and figure.has_attack)
	assert_eq(figure.sprite.offset,-Art.anchor("creature_deserter_crossbows"),"initial idle must also stand at its foot anchor")
	figure.set_walking(true)
	assert_eq(figure.sprite.offset, Vector2(-160,-207))
	assert_eq(figure.sprite.sprite_frames.get_frame_count("move"),4)
	var timing := figure.start_attack()
	assert_between(timing[0],0.179,0.181)
	assert_between(timing[1],0.599,0.601)
	assert_between(figure.sprite.sprite_frames.get_frame_duration("attack",0),1.799,1.801)
	figure.set_count(0)
	assert_eq(figure.sprite.animation,&"idle")
	figure.free()


func test_model_units_play_their_baked_clips_and_lie_on_the_last_death_frame() -> void:
	var figure := BattleFigure.new()
	figure.setup("pike_militia",10,1.0,0.0)
	assert_true(figure.has_move and figure.has_attack and figure.has_death, "the 3D bake gives move, attack and death")
	figure.set_walking(true)
	assert_eq(figure.sprite.sprite_frames.get_frame_count("move"),8)
	var timing := figure.start_attack()
	assert_gt(timing[1],timing[0],"the thrust lands after its wind-up")
	figure.set_count(0)
	var last := figure.sprite.sprite_frames.get_frame_count("death") - 1
	assert_eq(figure.sprite.animation,&"death","the fallen show the baked death clip")
	assert_eq(figure.sprite.frame,last,"and rest on its last frame")
	assert_eq(figure.sprite.rotation,0.0,"the clip already lies down; no extra topple")
	figure.free()


func test_creatures_without_a_sheet_still_fight_with_the_lunge() -> void:
	# The cobolts were the last units without a sheet; they now play baked 3D
	# clips. A figure set up with no clips at all still lunges.
	var figure := BattleFigure.new()
	figure.setup("cobolt_vault_warden", 10, 1.0, 0.0)
	figure.has_move = false
	figure.has_attack = false
	var timing := figure.start_attack()
	assert_gt(timing[1], timing[0], "the attack still lands after its wind-up")
	figure.free()
