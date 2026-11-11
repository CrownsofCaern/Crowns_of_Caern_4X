extends "res://tests/test_case.gd"
## Strategic AI: very hard level, announced invasions, garrison sorties, town
## captures that would be retaken at once, and forecast screening.


func _duel(seed_value: int) -> GameSession:
	var s := GameSession.new_game(data, "twin_marches", seed_value)
	for p in s.state.players:
		p["is_human"] = false
	return s


func _put_hero(s: GameSession, hero_id: String, pos: Vector2i, pairs: Array) -> Hero:
	var h := s.hero(hero_id)
	h.pos = pos
	h.army = Army.from_pairs(pairs)
	h.movement_left = h.max_movement(data)
	s._reveal_around(h)
	return h


func _watch() -> GameSession:
	var s := GameSession.new_game(data, "last_watch", 7, {}, {"random_events": false})
	for p in s.state.players:
		p["is_human"] = false
	return s


# -------------------------------------------------------------- very hard --

func test_very_hard_is_the_top_level() -> void:
	var levels := data.difficulty_levels()
	assert_eq(levels.back(), "very_hard")
	var vh := data.difficulty("very_hard")
	assert_gt(int(vh["income_percent"]), int(data.difficulty("hard")["income_percent"]))
	assert_true(data._validate_ai_difficulty().is_empty())
	var ps := [{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "ashen", "difficulty": "very_hard"}]
	var s := GameSession.new_game(data, "twin_marches", 3, {"players": ps})
	assert_eq(s.difficulty_of(1), "very_hard")
	var ai := StrategicAI.new(s, 1)
	assert_eq(int(ai.settings["forecasts_per_decision"]), int(vh["ai"]["forecasts_per_decision"]))
	assert_gt(float(ai.settings["screen_width"]), 1.0, "very hard screens fights before forecasting them in full")
	assert_gt(float(ai.settings["danger_days"]), float(StrategicAI.DEFAULT_SETTINGS["danger_days"]), "and looks further ahead")


func test_very_hard_waves_are_stronger_than_hard_ones() -> void:
	var counts := []
	for level in ["hard", "very_hard"]:
		var s := _watch()
		s.state.player(1)["difficulty"] = level
		s.state.day = 7
		WaveDirector.on_day(s)
		counts.append(s.hero("watch_commander_0").army.total_creatures())
	assert_lt(counts[0], counts[1], "a map without a very_hard preset scales its hard waves up")


func test_scaled_army_matches_the_spawned_wave() -> void:
	var s := _watch()
	s.state.player(1)["difficulty"] = "hard"
	var wave: Dictionary = WaveDirector.waves(s.state)[0]
	var expected := WaveDirector.scaled_army(s, wave)
	s.state.day = 7
	WaveDirector.on_day(s)
	var total := 0
	for pair in expected:
		total += int(pair[1])
	assert_eq(s.hero("watch_commander_0").army.total_creatures(), total, "the warning shows the army that comes")


# -------------------------------------------------------------- invasions --

func test_an_announced_wave_puts_its_target_in_danger() -> void:
	var s := _watch()
	s.state.day = 4
	WaveDirector.on_day(s)   # warns of the first wave (day 7, against Northwatch)
	var ai := StrategicAI.new(s, 0)
	ai._compute_threats()
	assert_true(ai.in_danger("town_northwatch"), "the garrison stays for the wave")
	var deaf := StrategicAI.new(s, 0, {"reads_invasions": false})
	deaf._compute_threats()
	assert_false(deaf.in_danger("town_northwatch"))
	s.state.day = 6
	ai._compute_threats()
	assert_true(ai.is_threatened("town_northwatch"), "a day before the wave the town is threatened")


func test_an_unannounced_wave_is_unknown() -> void:
	var s := _watch()
	s.state.day = 2
	var ai := StrategicAI.new(s, 0)
	ai._compute_threats()
	assert_false(ai.in_danger("town_northwatch"), "no peeking at the schedule before the warning")


func test_a_marching_invader_threatens_its_target() -> void:
	var s := _watch()
	s.state.day = 7
	WaveDirector.on_day(s)
	var commander := s.hero("watch_commander_0")
	assert_true(commander != null)
	Town.set_garrison(s.town("town_northwatch"), Army.new())
	var ai := StrategicAI.new(s, 0)
	ai._compute_threats()
	assert_true(ai.in_danger("town_northwatch"))
	assert_true(ai.is_threatened("town_northwatch"), "an empty town before a marching wave")


func test_survival_chapter_holds_in_an_ai_game() -> void:
	# The Shuttered Halls survival chapter fell on day 14 when the AI marched
	# the hall's defenders out between waves.
	var probe = load("res://tools/scenario_probe.gd").new()
	probe.data = data
	var s: GameSession = probe.start_game("campaign:shuttered_halls:4", 1)
	for p in s.state.players:
		p["is_human"] = false
	while s.state.day <= 16 and not s.state.game_over:
		StrategicAI.new(s, s.state.current_player).play_turn()
		s.end_turn()
	assert_false(s.state.game_over and s.state.end_reason == "scenario_defeat", "day %d %s" % [s.state.day, s.state.end_reason])
	assert_eq(int(s.town("town_start_0")["owner"]), 0)


# ---------------------------------------------------------------- sorties --

func _sortie_setup() -> GameSession:
	var s := _duel(5)
	Town.set_garrison(s.town("town_greywatch"), Army.from_pairs([["pike_militia", 60], ["longbowman", 40], ["shieldwarden", 20]]))
	_put_hero(s, "hero_west", Vector2i(2, 10), [["pike_militia", 2]])
	_put_hero(s, "hero_east", Vector2i(6, 10), [["cinderling", 140]])
	s.state.player(0)["fog"].reveal(Vector2i(6, 10), 1)
	return s


func test_a_hero_rides_out_with_the_garrison() -> void:
	var s := _sortie_setup()
	var rep := StrategicAI.new(s, 0).play_turn()
	assert_false(s.hero("hero_east").alive, "the garrison beat the raider in the open: %s" % str(rep["actions"]))


func test_without_sorties_the_garrison_waits() -> void:
	var s := _sortie_setup()
	StrategicAI.new(s, 0, {"sorties": false}).play_turn()
	assert_true(s.hero("hero_east").alive, "the garrison stays home to hold the walls against a near rival")


func test_no_sortie_against_a_stronger_army() -> void:
	var s := _sortie_setup()
	_put_hero(s, "hero_east", Vector2i(6, 10), [["flayer", 60], ["scorchhound", 80]])
	StrategicAI.new(s, 0).play_turn()
	assert_true(s.hero("hero_east").alive)
	assert_eq(int(s.town("town_greywatch")["owner"]), 0)
	assert_gt(Town.garrison(s.town("town_greywatch")).stack_count(), 0, "the troops stay behind the walls")


# --------------------------------------------------------------- captures --

func test_does_not_take_a_town_it_would_lose_tomorrow() -> void:
	var s := _duel(5)
	Town.set_garrison(s.town("town_emberkeep"), Army.new())
	var h := _put_hero(s, "hero_west", Vector2i(21, 10), [["pike_militia", 30]])
	_put_hero(s, "hero_east", Vector2i(20, 3), [["flayer", 60], ["scorchhound", 80]])
	s.state.player(0)["fog"].reveal(Vector2i(20, 3), 1)
	var ai := StrategicAI.new(s, 0)
	ai._compute_threats()
	var c := {"id": "town_emberkeep", "pos": AdventureMap.object_pos(s.town("town_emberkeep"))}
	assert_true(ai._retaken(c, ai.army_value(h.army)), "the strong rival is a day away")
	assert_false(ai.is_decisive("town_emberkeep"), "and taking the town does not end the rival")
	ai.play_turn()
	assert_eq(int(s.town("town_emberkeep")["owner"]), 1, "not worth a hero for one night")


# -------------------------------------------------------------- screening --

func test_screening_drops_a_hopeless_fight() -> void:
	var s := _duel(5)
	var h := _put_hero(s, "hero_west", Vector2i(12, 10), [["pike_militia", 5]])
	var ai := StrategicAI.new(s, 0, {"screen_width": 2.0})
	var field := AiDistanceField.build(s.state.map, h.pos, ai._blocked_for(h))
	var cands := ai.candidate_targets(h, field)
	var crossing := cands.filter(func(c): return c["id"] == "neutral_crossing")
	if crossing.is_empty():
		# The strength prefilter already removed it; screen it directly.
		crossing = [{"id": "neutral_crossing", "guarded": true}]
	var dropped := ai._screen_fights(h, crossing, {})
	assert_true(dropped.has("neutral_crossing"))
	var off := StrategicAI.new(s, 0)
	assert_true(off._screen_fights(h, crossing, {}).is_empty(), "screening is off at screen_width 1")
