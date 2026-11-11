extends "res://tests/test_case.gd"

func test_legacy_saves_migrate_and_new_saves_keep_stack_progress() -> void:
	var session := GameSession.new_game(data, "ember_ford", 11)
	var record := session.state.to_dict()
	record["version"] = 16
	var army: Array = record["heroes"]["hero_wren"]["army"]
	army[0]["creature"] = "pike_veteran"
	for stack in army:
		stack.erase("veteran_xp")
	var state := GameState.from_dict(record, data)
	assert_eq(Army.veteran_level(state.heroes["hero_wren"].army.slots[0]), 3)
	state.heroes["hero_wren"].army.slots[0]["veteran_xp"] = 6000
	var restored := GameState.from_dict(state.to_dict(), data)
	assert_eq(int(restored.heroes["hero_wren"].army.slots[0]["veteran_xp"]), 6000)

func test_transfers_preserve_progress_and_never_merge_different_levels() -> void:
	var session := GameSession.new_game(data, "ember_ford", 11)
	var h := session.hero("hero_wren")
	h.army.slots[0] = {"creature": "pike_militia", "count": 10, "veteran_xp": 1700}
	assert_true(session.transfer_stack(h.id, 0, h.id, 5, 4)["ok"])
	assert_eq(int(h.army.slots[5]["veteran_xp"]), 1700)
	h.army.slots[5]["veteran_xp"] = 2700
	assert_true(session.transfer_stack(h.id, 5, h.id, 0)["ok"])
	assert_eq(int(h.army.slots[0]["veteran_xp"]), 2100)
	h.army.slots[5] = {"creature": "pike_militia", "count": 2, "veteran_xp": 0}
	var result := session.transfer_stack(h.id, 5, h.id, 0)
	assert_true(result["swapped"])
	assert_eq(h.army.slots[0]["count"], 2)
	assert_eq(h.army.slots[5]["count"], 10)

func test_level_five_stats_and_visuals_reach_battle_and_replay() -> void:
	var army := Army.new()
	army.add("pike_veteran", 10, 35000)
	var c := Army.creature_stats(army.slots[0], data)
	assert_gt(c["hp"], data.creature("pike_veteran")["hp"])
	assert_gt(c["damage"][1], data.creature("pike_veteran")["damage"][1])
	var setup := CombatSimulator.make_setup({"name": "Veterans", "stacks": army.to_combat_stacks()}, {"name": "Foe", "stacks": [{"creature": "cinderling", "count": 1}]}, "grass", 3)
	var result := CombatSimulator.new(data).simulate(setup, true)
	assert_eq(result["sides"][0]["stacks"][0]["veteran_level"], 5)
	assert_eq(BattleReplay.from_result(result).stacks[0][0]["veteran_level"], 5)
	assert_ne(Art.creature("pike_veteran", 5), null)
	assert_eq(CreatureAnims.frames("pike_veteran", "move", 5).size(), 4)
	assert_eq(CreatureAnims.attack_timing("pike_veteran", 5), [0.18, 0.6])
	var figure := BattleFigure.new()
	figure.setup("pike_veteran", 10, 1, 0, false, 5)
	assert_eq(figure.veteran_level, 5)
	assert_eq(figure.sprite.sprite_frames.get_frame_count("attack"), 4)
	figure.free()

func test_all_eight_factions_have_live_level_five_art() -> void:
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/build/veteran_animations/manifest.json"))
	assert_true(pack["runtime_enabled"])
	assert_eq(pack["units"].size(), 64)
	for id in pack["units"]:
		assert_false(data.creature(id).is_empty(), id)
		assert_ne(Art.creature(id, 5), null, id)
		for action in ["move", "attack"]:
			assert_eq(CreatureAnims.frames(id, action, 5).size(), 4, id + "/" + action)
