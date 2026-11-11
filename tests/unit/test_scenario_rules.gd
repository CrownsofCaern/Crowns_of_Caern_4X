extends "res://tests/test_case.gd"


func _scenario(objs: Array) -> Dictionary:
	return {"name": "The Last Road", "player": 0, "objectives": objs}


func _reach(pos: Array = [5, 8]) -> Dictionary:
	return {"id": "centre", "type": "reach", "hero": "hero_wren", "pos": pos}


func _game(sc: Dictionary) -> GameSession:
	return GameSession.new_game(data, "ember_ford", 7, {}, {"scenario": sc, "random_events": false})


func test_reach_on_last_day_and_result_text() -> void:
	var sc := _scenario([_reach()])
	sc["deadline_day"] = 21
	var s := _game(sc)
	s.state.day = 21
	s.move_hero("hero_wren", Vector2i(5, 8))
	assert_true(s.state.game_over)
	assert_eq(s.state.winner, 0)
	assert_eq(s.state.end_reason, "scenario_victory")
	assert_true(s.game_result()["human_won"])
	assert_true(s.game_result()["text"].contains("The Last Road"))


func test_deadline_expires_only_after_full_last_day() -> void:
	var sc := _scenario([_reach()])
	sc["deadline_day"] = 21
	var s := _game(sc)
	s.state.day = 21
	VictoryRules.update(s)
	assert_false(s.state.game_over)
	s.end_turn()
	assert_eq(s.state.day, 22)
	assert_eq(s.state.end_reason, "scenario_defeat")
	assert_true(s.game_result()["text"].contains("deadline"))


func test_visiting_intermediate_tile_counts_and_survives_json() -> void:
	var sc := _scenario([_reach([4, 8]), {"id": "wait", "type": "survive", "through_day": 2}])
	var s := _game(sc)
	s.move_hero("hero_wren", Vector2i(5, 8))
	assert_false(s.state.game_over)
	assert_true(s.scenario_objectives()[0]["completed"])
	var save: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	assert_true(GameState.validate_save(save).is_empty())
	var loaded := GameSession.from_state(data, GameState.from_dict(save, data))
	assert_true(loaded.scenario_objectives()[0]["completed"])
	loaded.end_turn()
	assert_false(loaded.state.game_over, "survive through day 2, not just reach its morning")
	loaded.end_turn()
	assert_eq(loaded.state.end_reason, "scenario_victory")


func test_survival_with_matching_deadline_wins_at_boundary() -> void:
	var sc := _scenario([{"id": "hold", "type": "survive", "through_day": 2}])
	sc["deadline_day"] = 2
	var s := _game(sc)
	s.end_turn()
	s.end_turn()
	assert_eq(s.state.end_reason, "scenario_victory")


func test_protected_town_loss_beats_completed_objective() -> void:
	var sc := _scenario([_reach()])
	sc["protected_towns"] = ["town_greyhold"]
	var s := _game(sc)
	s.town("town_greyhold")["owner"] = -1
	s.move_hero("hero_wren", Vector2i(5, 8))
	assert_eq(s.state.end_reason, "scenario_defeat")
	assert_true(s.game_result()["text"].contains("Greyhold"))


func test_required_hero_loss() -> void:
	var sc := _scenario([_reach()])
	sc["required_heroes"] = ["hero_maelis"]
	var s := _game(sc)
	s.hero("hero_maelis").alive = false
	VictoryRules.update(s)
	assert_eq(s.state.end_reason, "scenario_defeat")


func test_control_objective_uses_current_ownership() -> void:
	var sc := _scenario([{"id": "town", "type": "control_towns", "towns": ["town_greyhold"]},
		{"id": "wait", "type": "survive", "through_day": 2}])
	var s := _game(sc)
	assert_true(s.scenario_objectives()[0]["completed"])
	s.town("town_greyhold")["owner"] = -1
	assert_false(s.scenario_objectives()[0]["completed"])
	s.end_turn()
	s.end_turn()
	assert_false(s.state.game_over, "an earlier ownership check must not latch")
	s.town("town_greyhold")["owner"] = 0
	VictoryRules.update(s)
	assert_eq(s.state.end_reason, "scenario_victory")


func test_expedition_exemption_does_not_remove_normal_elimination() -> void:
	var sc := _scenario([{"id": "wait", "type": "survive", "through_day": 30}])
	sc["townless_players"] = [0]
	var s := _game(sc)
	s.town("town_greyhold")["owner"] = -1
	for i in 10:
		s.end_turn()
	assert_false(s.state.player(0)["defeated"])
	assert_eq(VictoryRules.days_left(s, 0), -1)
	for h in s.state.heroes.values():
		h.alive = false
	VictoryRules.update(s)
	assert_eq(s.state.end_reason, "scenario_defeat")


func test_scenario_suppresses_ordinary_domination() -> void:
	var s := _game(_scenario([_reach()]))
	for t in s.state.map.objects.values():
		if t["type"] == "town":
			t["owner"] = 0
	VictoryRules.update(s)
	assert_false(s.state.game_over)


func test_older_saves_keep_standard_rules() -> void:
	var s := GameSession.new_game(data, "ember_ford", 7)
	var save := s.state.to_dict()
	save["version"] = 15
	save.erase("scenario_progress")
	var loaded := GameSession.from_state(data, GameState.from_dict(save, data))
	assert_false(ScenarioRules.active(loaded.state))
	assert_true(loaded.state.scenario_progress.is_empty())
	assert_true(loaded.scenario_objectives().is_empty())


func test_campaign_passes_and_validates_scenario() -> void:
	var original: Dictionary = data.campaigns["last_light"].duplicate(true)
	var ch: Dictionary = data.campaigns["last_light"]["chapters"][0]
	ch["scenario"] = _scenario([{"id": "hold", "type": "survive", "through_day": 21}])
	var errors := data.validate()
	var campaign := Campaign.start(data, "last_light", 7)
	var s := campaign.begin_chapter(data)
	ch["scenario"]["objectives"][0]["type"] = "unknown"
	var bad := Campaign.validate(data)
	data.campaigns["last_light"] = original
	assert_true(errors.is_empty(), "\n".join(errors))
	assert_true(ScenarioRules.active(s.state))
	assert_false(bad.is_empty())
	assert_eq(s.state.rules["scenario"]["objectives"][0]["type"], "survive", "definitions are snapshotted")


func test_schema_and_map_references() -> void:
	var sc := _scenario([_reach([9999, 8]), _reach()])
	sc["player"] = -1
	sc["deadline_day"] = 0
	assert_gt(ScenarioRules.validate(sc).size(), 2)
	assert_false(ScenarioRules.validate(_scenario([_reach([9999, 8])]), data.load_map("ember_ford")).is_empty())
	var unknown := _scenario([{"id": "town", "type": "control_towns", "towns": ["missing"]}])
	assert_false(ScenarioRules.validate(unknown, data.load_map("ember_ford")).is_empty())
	assert_false(ScenarioRules.validate({"name": "Broken", "objectives": "bad"}).is_empty())


func test_defeat_hero_in_multiplayer_scenario() -> void:
	var sc := _scenario([{"id": "commander", "type": "defeat_hero", "hero": "hero_skarn"}])
	var s := GameSession.new_game(data, "burning_ford", 7, {}, {"scenario": sc})
	assert_false(s.state.game_over)
	s.hero("hero_skarn").alive = false
	VictoryRules.update(s)
	assert_eq(s.state.end_reason, "scenario_victory")
	assert_eq(s.state.winner, 0)


func test_save_rejects_malformed_scenario_and_progress() -> void:
	var s := _game(_scenario([_reach()]))
	var save := s.state.to_dict()
	save["rules"]["scenario"]["objectives"][0]["type"] = "unknown"
	assert_false(GameState.validate_save(save).is_empty())
	save = s.state.to_dict()
	save["scenario_progress"] = []
	assert_false(GameState.validate_save(save).is_empty())


func test_campaign_rejects_unknown_objective_reference() -> void:
	var original: Dictionary = data.campaigns["last_light"].duplicate(true)
	data.campaigns["last_light"]["chapters"][0]["scenario"] = _scenario([
		{"id": "lost", "type": "reach", "hero": "missing_hero", "pos": [5, 8]}])
	var errors := data.validate()
	data.campaigns["last_light"] = original
	assert_true(errors.any(func(e): return e.contains("unknown objective hero")))
