extends "res://tests/test_case.gd"
## Computer-player difficulty levels (data/ai_difficulty.json): per-slot setup,
## AI settings, income scaling, saves and a hard-versus-easy duel.


func _game(map_id: String, seed_value: int, levels: Array, rules: Dictionary = {}) -> GameSession:
	var entry := GameSetup.map_entry(data, map_id)
	var setup := GameSetup.default_setup(entry)
	for i in levels.size():
		if String(levels[i]) != "":
			setup["players"][i]["difficulty"] = levels[i]
	return GameSession.new_game(data, map_id, seed_value, setup, rules)


func test_levels_are_valid_data() -> void:
	assert_eq(data.difficulty_levels(), ["passive", "easy", "normal", "hard", "very_hard"])
	assert_eq(data.default_difficulty(), "normal")
	assert_eq(data.difficulty("normal")["ai"], {}, "normal is the standard AI")
	assert_eq(int(data.difficulty("normal")["income_percent"]), 100)
	assert_eq(data.difficulty("no_such_level")["name"], "Normal", "unknown ids fall back to the default")
	var errors := data._validate_ai_difficulty()
	assert_true(errors.is_empty(), "\n".join(errors))


func test_validation_catches_bad_levels() -> void:
	var original: Dictionary = data.ai_difficulty.duplicate(true)
	data.ai_difficulty["levels"]["hard"]["ai"]["bloodlust"] = 3
	data.ai_difficulty["levels"]["easy"]["ai"]["max_heroes"] = "two"
	data.ai_difficulty["levels"]["passive"]["income_percent"] = 0
	data.ai_difficulty["order"].append("nightmare")
	var errors := data._validate_ai_difficulty()
	data.ai_difficulty = original
	var text := "\n".join(errors)
	assert_true(text.contains("bloodlust"), text)
	assert_true(text.contains("max_heroes"), text)
	assert_true(text.contains("income_percent"), text)
	assert_true(text.contains("nightmare"), text)


func test_setup_sets_difficulty_per_slot() -> void:
	var s := _game("twin_marches", 3, ["", "hard"])
	assert_eq(s.difficulty_of(1), "hard")
	assert_eq(s.difficulty_of(0), "normal", "a human slot plays at the default level")
	var plain := GameSession.new_game(data, "twin_marches", 3)
	assert_eq(plain.difficulty_of(1), "normal", "a map without setup plays at the default level")
	var human_hard := _game("twin_marches", 3, ["hard", ""])
	assert_eq(human_hard.difficulty_of(0), "normal", "humans have no difficulty")


func test_setup_rejects_an_unknown_level() -> void:
	var def := data.load_map("twin_marches")
	var errors := GameSetup.validate(def, {"players": [{}, {"difficulty": "brutal"}]}, data)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("brutal"))
	var ch := {"setup": {"players": [{"type": "human"}, {"type": "computer", "difficulty": "brutal"}]}}
	assert_eq(Campaign._validate_setup(ch, data).size(), 1, "a campaign chapter's setup is checked too")
	ch["setup"]["players"][1]["difficulty"] = "easy"
	assert_true(Campaign._validate_setup(ch, data).is_empty())


func test_levels_tune_the_ai() -> void:
	for level in data.difficulty_levels():
		var s := _game("twin_marches", 3, ["", level])
		var ai := StrategicAI.new(s, 1)
		var over: Dictionary = data.difficulty(level)["ai"]
		for key in StrategicAI.DEFAULT_SETTINGS:
			var want: Variant = over.get(key, StrategicAI.DEFAULT_SETTINGS[key])
			assert_eq(ai.settings[key], want, "%s %s" % [level, key])
	var easy := StrategicAI.new(_game("twin_marches", 3, ["", "easy"]), 1).settings
	var hard := StrategicAI.new(_game("twin_marches", 3, ["", "hard"]), 1).settings
	assert_gt(float(easy["min_win_probability"]), float(hard["min_win_probability"]), "easy waits for surer fights")
	assert_gt(int(hard["max_heroes"]), int(easy["max_heroes"]))


func test_game_rules_override_the_level() -> void:
	var s := _game("twin_marches", 3, ["", "hard"], {"ai": {"max_heroes": 1, "passive": true}})
	var ai := StrategicAI.new(s, 1)
	assert_eq(int(ai.settings["max_heroes"]), 1, "a campaign chapter's ai settings win")
	assert_true(bool(ai.settings["passive"]))
	assert_eq(float(ai.settings["min_win_probability"]), float(data.difficulty("hard")["ai"]["min_win_probability"]),
		"the rest of the level still applies")
	assert_eq(int(StrategicAI.new(s, 1, {"max_heroes": 5}).settings["max_heroes"]), 5, "explicit overrides come last")


func test_passive_level_ignores_rival_heroes_and_towns() -> void:
	var counts := []
	for level in ["passive", "normal"]:
		var s := _game("burning_ford", 3, ["", level])
		# Wren stands right in front of the Ashen hero, in plain sight.
		var skarn: Hero = s.hero("hero_skarn")
		s.hero("hero_wren").pos = skarn.pos + Vector2i(-2, 0)
		s.state.player(1)["fog"].reveal(skarn.pos, 30)
		var ai := StrategicAI.new(s, 1, {"strength_prefilter": 0.0})
		var field := AiDistanceField.build(s.state.map, skarn.pos, ai._blocked_for(skarn))
		var rival := 0
		for c in ai.candidate_targets(skarn, field):
			if c["kind"] == "hero":
				rival += 1
			elif c["kind"] in ["town", "mine"] and int(s.state.map.objects[c["id"]].get("owner", -1)) == 0:
				rival += 1
		counts.append(rival)
	assert_eq(counts[0], 0, "the passive level never targets the player")
	assert_gt(counts[1], 0, "the normal level does")


func test_income_scales_with_the_level() -> void:
	var normal := _game("twin_marches", 3, ["", "normal"])
	var gold := int(normal.daily_income(1)["gold"])
	assert_gt(gold, 0)
	for level in ["easy", "hard"]:
		var s := _game("twin_marches", 3, ["", level])
		var pct := int(data.difficulty(level)["income_percent"])
		assert_eq(s.income_percent(1), pct)
		assert_eq(int(s.daily_income(1)["gold"]), int(round(float(gold) * float(pct) / 100.0)), level)
	var hard := _game("twin_marches", 3, ["", "hard"])
	assert_gt(int(hard.daily_income(1)["gold"]), gold)
	assert_eq(hard.daily_income(0), normal.daily_income(0), "the human's income is untouched")
	# The scaled income is what the bank receives at the start of a day.
	var bank: ResourceBank = hard.state.player(1)["resources"]
	var before := bank.get_amount("gold")
	var expect := int(hard.daily_income(1)["gold"])
	hard.end_turn()   # player 1's turn
	hard.end_turn()   # a new day
	assert_eq(bank.get_amount("gold") - before, expect)


func test_difficulty_survives_save_and_load() -> void:
	var s := _game("twin_marches", 3, ["", "easy"])
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	assert_true(GameState.SAVE_VERSION >= 9)
	var back := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_eq(back.difficulty_of(1), "easy")
	assert_eq(back.income_percent(1), int(data.difficulty("easy")["income_percent"]))


func test_v8_save_plays_at_the_default_level() -> void:
	var s := _game("twin_marches", 3, ["", "hard"])
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	d["version"] = 8
	for p in d["players"]:
		p.erase("difficulty")
	assert_true(GameState.validate_save(d).is_empty())
	var back := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_eq(back.difficulty_of(1), "normal")
	assert_eq(back.income_percent(1), 100)


func test_game_over_standings_name_the_level() -> void:
	var s := _game("twin_marches", 3, ["", "hard"])
	var found := false
	for row in s.game_result()["standings"]:
		if int(row["player"]) == 1:
			assert_eq(String(row["difficulty"]), "hard")
			found = true
	assert_true(found)


## Total worth of a player: troops (heroes and garrisons) plus resources, in gold.
func _worth(s: GameSession, player_idx: int) -> float:
	var ai := StrategicAI.new(s, player_idx)
	var v := 0.0
	for h in s.state.heroes_of(player_idx):
		v += ai.army_value(h.army)
	for t in s.towns_of(player_idx):
		v += ai.army_value(Town.garrison(t))
		# Count invested town development as well as liquid wealth.
		# Veteran-era recruitment can shift when the AI invests in upgrades.
		for building_id in t["built"]:
			v += ai.bundle_value(Town.build_cost(t, building_id, s.data))
	var bank: ResourceBank = s.state.player(player_idx)["resources"]
	for res in data.resource_order:
		v += float(bank.get_amount(res)) * ai.resource_value(res)
	return v


func test_hard_outgrows_easy_in_a_mirror_duel() -> void:
	# Same faction on both sides; the hard player swaps seats so the map's
	# layout cannot decide the result.
	for hard_seat in 2:
		var ps := []
		for seat in 2:
			ps.append({"type": "computer", "faction": "ashen", "difficulty": "hard" if seat == hard_seat else "easy"})
		var s := GameSession.new_game(data, "twin_marches", 9, {"players": ps})
		# This benchmark requires the mirror layout, without random shops.
		for obj in s.state.map.objects.values():
			if MapCobolts.is_post(obj, data):
				s.state.map.remove_object(obj["id"])
		assert_eq(s.difficulty_of(hard_seat), "hard")
		while s.state.day < 15 and not s.state.game_over:
			StrategicAI.new(s, s.state.current_player).play_turn()
			s.end_turn()
		var easy_seat := 1 - hard_seat
		var where := "hard in seat %d, day %d, over %s, winner %d" % [hard_seat, s.state.day, s.state.game_over, s.state.winner]
		if s.state.game_over:
			assert_eq(s.state.winner, hard_seat, where)
		else:
			assert_gt(_worth(s, hard_seat), _worth(s, easy_seat), where)
