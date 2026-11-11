extends "res://tests/test_case.gd"


func _pack() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/dlc_factions.json"))


func test_pack_is_playable_and_separate_from_story() -> void:
	var pack := _pack()
	assert_eq(pack["activation"], "art_only_optional_pack")
	assert_eq(pack["story_links"], [])
	for fid in pack["factions"]:
		assert_true(data.factions.has(fid))
		assert_eq(pack["factions"][fid]["campaigns"], [])
	for cid in pack["creatures"]:
		assert_true(data.creatures.has(cid), "every illustrated creature is playable")


func test_every_declared_asset_loads_from_an_atlas() -> void:
	var pack := _pack()
	assert_eq(pack["assets"].size(), 120)
	for record in pack["assets"]:
		var sid := String(record["id"])
		assert_true(Art.has_sprite(sid), sid)
		var texture := Art.sprite(sid)
		assert_true(texture != null, sid)
		if texture != null:
			assert_eq(texture.get_size(), Vector2(record["size"][0], record["size"][1]), sid)
		assert_eq(Art.sprite_info(sid)["source"], "generated", sid)


func test_all_creature_actions_load_and_attack_recovers() -> void:
	# Drawn clips have 4 frames; units baked from 3D models have 8. Either way
	# the attack ends (returns to rest) and carries an impact marker inside it.
	for cid in _pack()["creatures"]:
		var sid := "creature_" + String(cid)
		for action in ["move", "attack"]:
			var clip := UnitAnimation.clip(sid, action)
			assert_true(clip["frames"].size() in [4, 8], sid + "/" + action)
			var pose := UnitAnimation.sample(sid, action, 0.2)
			assert_false(pose.is_empty(), sid)
			assert_eq(pose["anchor"], Vector2(160, 207))
		var attack := UnitAnimation.clip(sid, "attack")
		var length := 0.0
		for ms in attack["durations_ms"]:
			length += float(ms) / 1000.0
		assert_eq(UnitAnimation.frame_index(attack, length + 0.05), -1, sid + " attack recovers")
		assert_eq(UnitAnimation.events_between(attack, 0.0, length), ["impact"], sid + " attack lands")


func test_every_hero_has_four_drawn_movement_poses() -> void:
	for hid in _pack()["hero_classes"]:
		var sid := "hero_" + String(hid)
		var clip := UnitAnimation.clip(sid, "move")
		assert_eq(clip["frames"].size(), 4, sid)
		assert_true(clip["loop"], sid)
		assert_eq(UnitAnimation.frame_index(clip, 0.32), 0, sid)
		for phase in [0.0, 0.08, 0.16, 0.24]:
			assert_false(UnitAnimation.sample(sid, "move", phase).is_empty(), sid)


func test_building_progression_selects_one_variant_per_slot() -> void:
	for fid in _pack()["factions"]:
		assert_true(Art.has_sprite("town_" + String(fid)), "existing map and town UI lookup contract")
		assert_eq(Art.sprite_info("town_" + String(fid))["map_scale"], 0.5)
		var scene := TownScene.scene_for(fid)
		assert_eq(scene["slots"].size(), 18, fid)
		assert_eq(scene["assets"].size(), 31, fid)
		assert_eq(TownScene.resolved_buildings(scene, []), [])
		var built: Array = scene["assets"].keys()
		var final := TownScene.resolved_buildings(scene, built)
		assert_eq(final.size(), 18, fid)
		for slot in scene["slots"]:
			assert_true(slot["variants"][-1] in final, fid + "/" + slot["id"])
