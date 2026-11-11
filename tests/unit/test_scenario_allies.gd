extends "res://tests/test_case.gd"


func _allied_game() -> GameSession:
	var s := GameSession.new_game(data, "last_watch", 7)
	var h := s.hero("hero_watch")
	h.pos = Vector2i(8, 6)
	s.state.day = 9 # The envoy arrives in the second week.
	s.scenario_act(h.id, "site_pact", "accept")
	s.state.map.remove_object("guardian_oath")
	ScenarioQuests.collect(s, h, s.state.map.objects["relic_oath"])
	s.scenario_act(h.id, "site_pact", "deliver")
	s.state.day = 1
	return s


func test_earned_ally_marches_to_defend_the_players_northern_town() -> void:
	var s := _allied_game()
	var h := s.hero("hero_reedwarden")
	var target := AdventureMap.object_pos(s.town("town_northwatch"))
	var before := AiDistanceField.build(s.state.map, target, {}).cost_to(h.pos)
	s.state.current_player = 2
	StrategicAI.new(s, 2).play_turn()
	var after := AiDistanceField.build(s.state.map, target, {}).cost_to(h.pos)
	assert_lt(after, before)
	assert_eq(s.state.scenario_runtime["orders"][h.id]["target"], "town_northwatch")
	assert_eq(int(s.town("town_northwatch")["owner"]), 0, "allies do not occupy or take the player's town")


func test_earned_ally_intercepts_invaders_near_its_defence_target() -> void:
	var s := _allied_game()
	var h := s.hero("hero_reedwarden")
	h.pos = Vector2i(22, 6)
	s._reveal_around(h)
	s.state.day = 7
	WaveDirector.on_day(s)
	var invader := s.hero("watch_commander_0")
	invader.pos = Vector2i(25, 6)
	s.state.current_player = 2
	var before := s.state.battles_fought
	WaveDirector.play_order(s, h)
	assert_gt(s.state.battles_fought, before)
	assert_false(invader.alive, "the ally must contribute to the actual siege")
