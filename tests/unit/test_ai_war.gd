extends "res://tests/test_case.gd"
## Computer players from normal up go to war: they know where rival towns
## and heroes are (rival_intel), value a neutral army barring the way to a
## rival town (gate_value_share) and prefer human rivals (human_bonus).

const GATE_MAP := "gen:random_m_2p_normal_normal:3"


func _game(map_id: String, seed_value: int, levels: Array) -> GameSession:
	var entry := GameSetup.map_entry(data, map_id)
	var setup := GameSetup.default_setup(entry)
	for i in levels.size():
		setup["players"][i]["type"] = "computer" if i > 0 else String(setup["players"][i]["type"])
		if String(levels[i]) != "":
			setup["players"][i]["difficulty"] = levels[i]
	return GameSession.new_game(data, map_id, seed_value, setup)


func _rival_targets(s: GameSession, ai: StrategicAI, h: Hero) -> Array:
	var field := AiDistanceField.build(s.state.map, h.pos, ai._blocked_for(h))
	var out := []
	for c in ai.candidate_targets(h, field):
		if c["kind"] == "town" and int(s.state.map.objects[c["id"]]["owner"]) == 0:
			out.append(c["id"])
	return out


func test_only_normal_and_up_go_to_war() -> void:
	for level in ["passive", "easy"]:
		var over: Dictionary = data.difficulty(level)["ai"]
		assert_false(bool(over.get("rival_intel", false)), level)
		assert_eq(float(over.get("gate_value_share", 0.0)), 0.0, level)
	for level in ["normal", "hard", "very_hard"]:
		var over: Dictionary = data.difficulty(level)["ai"]
		assert_true(bool(over["rival_intel"]), level)
		assert_gt(float(over["gate_value_share"]), 0.0, level)
		assert_gt(float(over["human_bonus"]), 1.0, level)


func test_hard_knows_rival_towns_in_the_fog() -> void:
	var found := []
	for level in ["easy", "hard"]:
		var s := _game("burning_ford", 3, ["", level])
		var ai := StrategicAI.new(s, 1, {"strength_prefilter": 0.0, "gate_value_share": 0.0})
		var h: Hero = s.state.heroes_of(1)[0]
		var fog: FogOfWar = s.state.player(1)["fog"]
		for t in s.towns_of(0):
			assert_false(fog.is_explored(AdventureMap.object_pos(t)), "the rival town starts in the fog")
		found.append(_rival_targets(s, ai, h).size())
	assert_eq(found[0], 0, "an easy AI only goes for towns it has seen")
	assert_gt(found[1], 0, "a hard AI knows where its rivals live")


func test_hard_does_not_fear_rivals_it_cannot_see() -> void:
	for level in ["easy", "hard"]:
		var s := _game("burning_ford", 3, ["", level])
		var ai := StrategicAI.new(s, 1)
		var fog: FogOfWar = s.state.player(1)["fog"]
		for t in s.towns_of(0):
			fog.reveal(AdventureMap.object_pos(t), 1)   # the town is known, its hero is not
		ai._begin_turn(ai._new_report())
		var guesses := ai._reach.filter(func(r): return not bool(r["seen"]))
		var rival_seen := ai._reach.filter(func(r): return bool(r["seen"]))
		if level == "easy":
			assert_gt(guesses.size(), 0, "easy assumes a hero as strong as its own troops behind every rival town")
		else:
			assert_eq(guesses.size(), 0, "hard knows where the rival heroes really are")
			assert_eq(rival_seen.size(), s.state.heroes_of(0).filter(func(e): return not e.army.is_empty()).size())


func test_gate_guard_carries_the_rival_town_value() -> void:
	var s := GameSession.new_game(data, GATE_MAP, 1)
	for p in s.state.players:
		p["is_human"] = false
		p["difficulty"] = "hard"
	var ai := StrategicAI.new(s, 1)
	var h: Hero = s.state.heroes_of(1)[0]
	var field := AiDistanceField.build(s.state.map, h.pos, ai._blocked_for(h))
	var rival: Dictionary = s.towns_of(0)[0]
	assert_eq(field.cost_to(AdventureMap.object_pos(rival)), AiDistanceField.UNREACHABLE, "guards seal the rival's lands")
	var gates := ai._gate_values(h, field, s.state.player(1)["fog"])
	assert_false(gates.is_empty(), "some neutral army bars the way")
	for id in gates:
		assert_eq(s.state.map.objects[id]["type"], "neutral_army")
		assert_between(float(gates[id]), 0.0, ai.capture_value(rival) * float(ai.settings["gate_value_share"]) + 1.0)
	var off := StrategicAI.new(s, 1, {"gate_value_share": 0.0})
	assert_true(off._gate_values(h, field, s.state.player(1)["fog"]).is_empty())


func test_human_rivals_are_worth_more() -> void:
	var s := _game("burning_ford", 3, ["", "hard"])
	var ai := StrategicAI.new(s, 1)
	var bonus := float(ai.settings["enemy_bonus"])
	s.state.player(0)["is_human"] = true
	assert_eq(ai.rival_factor(0), bonus * float(ai.settings["human_bonus"]))
	s.state.player(0)["is_human"] = false
	assert_eq(ai.rival_factor(0), bonus)
