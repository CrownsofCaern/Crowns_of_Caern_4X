extends "res://tests/test_case.gd"


func _game() -> GameSession:
	return GameSession.new_game(data, "last_watch", 7, {}, {"random_events": false})


func test_authored_survival_map_is_valid() -> void:
	var errors := MapValidator.validate(data.load_map("last_watch"), data)
	assert_true(errors.is_empty(), "\n".join(errors))
	var s := _game()
	assert_false(s.state.player(1)["defeated"])
	assert_false(s.state.player(2)["defeated"])
	assert_false(s.state.game_over)


func test_warning_and_spawn_are_saved_and_fire_once() -> void:
	var s := _game()
	s.state.day = 4
	WaveDirector.on_day(s)
	var news := s.take_news(0)
	assert_eq(news.size(), 1)
	assert_true(String(news[0]).contains("Ember Scout"))
	WaveDirector.on_day(s)
	assert_true(s.take_news(0).is_empty())
	var copy := GameSession.from_state(data, GameState.from_dict(JSON.parse_string(JSON.stringify(s.state.to_dict())), data))
	copy.state.day = 7
	WaveDirector.on_day(copy)
	assert_true(copy.hero("watch_commander_0") != null)
	assert_eq(copy.state.heroes_of(1).size(), 1)
	WaveDirector.on_day(copy)
	assert_eq(copy.state.heroes_of(1).size(), 1)
	assert_true(WaveDirector.has_order(copy.state, "watch_commander_0"))


func test_blocked_entry_is_queued_and_cap_is_respected() -> void:
	var s := _game()
	var h := s.hero("hero_watch")
	h.pos = Vector2i(47, 6)
	s.state.rules["scenario"]["waves"][0]["entry_tiles"] = [[47, 6]]
	s.state.day = 7
	WaveDirector.on_day(s)
	assert_eq(s.state.heroes_of(1).size(), 0)
	h.pos = Vector2i(6, 18)
	WaveDirector.on_day(s)
	assert_eq(s.state.heroes_of(1).size(), 1)
	s.state.rules["scenario"]["max_active_invaders"] = 1
	s.state.day = 14
	WaveDirector.on_day(s)
	assert_eq(s.state.heroes_of(1).size(), 1)
	s.hero("watch_commander_0").alive = false
	WaveDirector.on_day(s)
	assert_eq(s.state.heroes_of(1).size(), 1)
	assert_true(s.hero("watch_commander_1") != null)


func test_invaders_follow_orders_instead_of_collecting_treasure() -> void:
	var s := _game()
	s.state.day = 7
	WaveDirector.on_day(s)
	var h := s.hero("watch_commander_0")
	var start := h.pos
	var target := AdventureMap.object_pos(s.town("town_northwatch"))
	var before := AiDistanceField.build(s.state.map, target, {}).cost_to(h.pos)
	s.state.current_player = 1
	StrategicAI.new(s, 1).play_turn()
	var after := AiDistanceField.build(s.state.map, target, {}).cost_to(h.pos)
	assert_ne(h.pos, start)
	assert_lt(after, before)
	assert_false(s.state.game_over)


func test_no_victory_between_waves_or_with_final_survivors() -> void:
	var s := _game()
	for day in [7, 14, 21, 28, 35, 36]:
		s.state.day = day
		WaveDirector.on_day(s)
		VictoryRules.update(s)
		assert_false(s.state.game_over)
		for h in s.state.heroes_of(1):
			if day < 35:
				h.alive = false
	assert_false(WaveDirector.cleared(s.state), "the final commanders still stand")
	for h in s.state.heroes_of(1):
		h.alive = false
	VictoryRules.update(s)
	assert_eq(s.state.end_reason, "scenario_victory")


func test_castle_loss_ends_survival() -> void:
	var s := _game()
	s.town("town_last_watch")["owner"] = 1
	VictoryRules.update(s)
	assert_eq(s.state.end_reason, "scenario_defeat")


func test_invaders_fight_a_hero_blocking_their_route() -> void:
	var s := _game()
	s.hero("hero_watch").pos = Vector2i(18, 18)
	s.state.day = 7
	WaveDirector.on_day(s)
	var commander := s.hero("watch_commander_0")
	commander.pos = Vector2i(23, 18)
	s.state.scenario_runtime["orders"][commander.id] = {"kind": "assault", "target": "town_last_watch", "targets": ["town_last_watch"]}
	s.state.current_player = 1
	var report := StrategicAI.new(s, 1).play_turn()
	assert_gt(report["battles"], 0, "a defending hero must not stall an invasion indefinitely")


func test_difficulty_changes_declared_wave_strength() -> void:
	var counts := []
	for level in ["easy", "normal", "hard"]:
		var s := _game()
		s.state.player(1)["difficulty"] = level
		s.state.day = 7
		WaveDirector.on_day(s)
		counts.append(s.hero("watch_commander_0").army.total_creatures())
	assert_lt(counts[0], counts[1])
	assert_lt(counts[1], counts[2])


func test_invalid_wave_definitions_and_runtime_are_rejected() -> void:
	var sc: Dictionary = data.load_map("last_watch")["scenario"]
	sc["waves"] = 3
	assert_false(ScenarioRules.validate(sc).is_empty())
	sc = data.load_map("last_watch")["scenario"]
	sc["invasion_players"] = "broken"
	assert_false(ScenarioRules.validate(sc).is_empty())
	sc = data.load_map("last_watch")["scenario"]
	sc["waves"][0]["hero"]["class"] = "missing"
	assert_false(ScenarioRules.validate(sc, {}, data).is_empty())
	var save := _game().state.to_dict()
	save["scenario_runtime"]["orders"] = []
	assert_false(GameState.validate_save(save).is_empty())


func test_entry_band_prevents_camping_a_single_tile() -> void:
	var s := _game()
	s.hero("hero_watch").pos = Vector2i(47, 6)
	s.state.day = 7
	WaveDirector.on_day(s)
	var h := s.hero("watch_commander_0")
	assert_true(h != null)
	assert_eq(h.pos, Vector2i(48, 6), "alternate entries remain on the outside of the defending army")
