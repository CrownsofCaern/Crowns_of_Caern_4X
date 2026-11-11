extends "res://tests/test_case.gd"
## Enemy intel on the map: rough troop counts and a worded verdict by default,
## scouts that spend movement for exact counts and odds, the Scouting skill's
## cheaper scouts, and hard mode, which never shows the odds.

const WOLVES := "neutral_wolves"   # ember_ford, at (12, 8)


func _game(hard: bool = false) -> GameSession:
	var setup := {"hide_odds": true} if hard else {}
	var s := GameSession.new_game(data, "ember_ford", 11, setup)
	var h := s.hero("hero_wren")
	h.pos = Vector2i(9, 8)
	(s.current_player()["fog"] as FogOfWar).reveal(h.pos, 6)
	return s


func _duel() -> GameSession:
	return GameSession.new_game(data, "mournfield", 5, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "ashen"},
		{"type": "closed", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})


func test_scout_rules_data_is_valid() -> void:
	assert_eq(data._validate_rules(), [] as Array[String])
	assert_gt(int(data.rules["scout_movement"]), 0)
	assert_gt(int(data.combat["hover_simulations"]), 0)
	var bad := data.rules.duplicate()
	bad.erase("scout_movement")
	var saved := data.rules
	data.rules = bad
	var errs := data._validate_rules()
	data.rules = saved
	assert_false(errs.is_empty(), "a missing scout_movement is reported")


func test_hostile_targets() -> void:
	var s := _game()
	assert_eq(s.hostile_target_at(Vector2i(12, 8), 0), WOLVES)
	assert_eq(s.hostile_target_at(Vector2i(1, 8), 0), "", "your own town is no target")
	assert_eq(s.hostile_target_at(Vector2i(0, 0), 0), "")
	var d := _duel()
	var foe := d.hero("hero_gaul")
	assert_eq(d.hostile_target_at(foe.pos, 0), foe.id, "an enemy hero in the open")
	assert_eq(d.hostile_target_at(foe.pos, 1), "", "not your own hero")


func test_default_intel_is_rough_with_a_verdict() -> void:
	var s := _game()
	var it := s.intel("hero_wren", WOLVES)
	assert_false(it["scouted"])
	assert_eq(it["odds"], "label")
	assert_true(CombatPredictor.LABELS.any(func(p): return p[1] == it["label"]), "a worded verdict")
	assert_eq(float(it["win_probability"]), -1.0, "no exact odds before scouting")
	assert_false(it["stacks"].is_empty())
	for st in it["stacks"]:
		assert_false(st["known"])
	assert_eq(it["scout_reason"], "")
	assert_eq(int(it["scout_cost"]), int(data.rules["scout_movement"]))
	var pred := s.preview_battle("hero_wren", WOLVES)
	assert_eq(pred["odds"], "label")
	assert_false(pred["scouted"])


func test_scout_spends_movement_and_reveals_exact_odds() -> void:
	var s := _game()
	var h := s.hero("hero_wren")
	var before := h.movement_left
	var r := s.scout(h.id, WOLVES)
	assert_true(r["ok"], r.get("reason", ""))
	assert_eq(h.movement_left, before - int(data.rules["scout_movement"]))
	var it := s.intel(h.id, WOLVES)
	assert_true(it["scouted"])
	assert_eq(it["odds"], "exact")
	assert_between(float(it["win_probability"]), 0.0, 1.0)
	for st in it["stacks"]:
		assert_true(st["known"])
	# The exact odds match the full forecast.
	var pred := s.preview_battle(h.id, WOLVES)
	assert_eq(pred["odds"], "exact")
	assert_eq(float(it["win_probability"]), float(pred["win_probability"]))
	var again := s.scout(h.id, WOLVES)
	assert_false(again["ok"])
	assert_eq(h.movement_left, before - int(data.rules["scout_movement"]), "a refused scout costs nothing")


func test_scout_needs_range_and_movement() -> void:
	var s := _game()
	var h := s.hero("hero_wren")
	h.pos = Vector2i(12 - s.scout_range(h.id) - 1, 8)
	(s.current_player()["fog"] as FogOfWar).reveal(Vector2i(12, 8), 2)
	assert_true(s.can_scout(h.id, WOLVES).begins_with("Too far"))
	h.pos = Vector2i(12 - s.scout_range(h.id), 8)
	assert_eq(s.can_scout(h.id, WOLVES), "")
	h.movement_left = s.scout_cost(h.id) - 1
	assert_true(s.can_scout(h.id, WOLVES).begins_with("Not enough movement"))
	assert_false(s.scout(h.id, WOLVES)["ok"])
	assert_eq(h.movement_left, s.scout_cost(h.id) - 1)
	assert_false(s.scout(h.id, "enc_toll")["ok"], "an encounter is not an army")
	assert_false(s.scout(h.id, "no_such_thing")["ok"])


func test_scouting_skill_makes_scouts_cheaper() -> void:
	var s := _game()
	var h := s.hero("hero_wren")
	var base := int(data.rules["scout_movement"])
	h.skills.erase("scouting")
	assert_eq(s.scout_cost(h.id), base)
	var costs := []
	for lv in [1, 2, 3]:
		h.skills["scouting"] = lv
		costs.append(s.scout_cost(h.id))
	assert_lt(costs[0], base)
	assert_lt(costs[1], costs[0])
	assert_eq(costs[2], 0, "a master scout costs no movement")
	var before := h.movement_left
	assert_true(s.scout(h.id, WOLVES)["ok"])
	assert_eq(h.movement_left, before)
	assert_gt(s.scout_range(h.id), int(data.progression["base_vision"]) + int(data.rules["scout_range_bonus"]),
		"Scouting's vision also lengthens the scouts' reach")


func test_reports_last_one_day() -> void:
	var s := _game()
	assert_true(s.scout("hero_wren", WOLVES)["ok"])
	assert_true(s.is_scouted(WOLVES))
	s.end_turn()
	while s.state.current_player != 0:
		s.end_turn()
	assert_false(s.is_scouted(WOLVES), "a new day needs a new scout")


func test_hard_mode_hides_the_odds() -> void:
	var s := _game(true)
	assert_true(s.odds_hidden())
	var it := s.intel("hero_wren", WOLVES)
	assert_eq(it["odds"], "none")
	assert_eq(it["label"], "")
	assert_eq(float(it["win_probability"]), -1.0)
	assert_true(s.scout("hero_wren", WOLVES)["ok"], "scouts still go out in hard mode")
	it = s.intel("hero_wren", WOLVES)
	assert_eq(it["odds"], "none", "even scouted")
	for st in it["stacks"]:
		assert_true(st["known"], "but they count exactly")
	assert_eq(s.preview_battle("hero_wren", WOLVES)["odds"], "none")
	assert_true(s.encounter_options("hero_wren", "enc_toll")["hide_chances"])
	assert_false(_game().encounter_options("hero_wren", "enc_toll")["hide_chances"])


func test_scout_an_enemy_hero_in_a_town_as_the_town() -> void:
	var d := _duel()
	var a := d.hero("hero_osric")
	var foe := d.hero("hero_gaul")
	var town: Dictionary = d.towns_of(1)[0]
	foe.pos = AdventureMap.object_pos(town)
	a.pos = foe.pos + Vector2i(-2, 0)
	(d.current_player()["fog"] as FogOfWar).reveal(a.pos, 4)
	assert_eq(d.hostile_target_at(foe.pos, 0), town["id"])
	assert_true(d.scout(a.id, foe.id)["ok"])
	assert_true(d.is_scouted(town["id"]), "the hero and its town share one report")
	assert_true(d.intel(a.id, town["id"])["defending_hero"])


func test_scouting_and_hard_mode_survive_save_and_load() -> void:
	var s := _game(true)
	assert_true(s.scout("hero_wren", WOLVES)["ok"])
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	var back := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_true(back.is_scouted(WOLVES))
	assert_true(back.odds_hidden())
	# A v9 save has no reports.
	d["version"] = 9
	for p in d["players"]:
		p.erase("scouted")
	assert_true(GameState.validate_save(d).is_empty())
	var old := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_false(old.is_scouted(WOLVES))
	assert_true(old.scout("hero_wren", WOLVES)["ok"])


func test_intel_tip_and_forecast_build() -> void:
	var s := _game()
	var tip := MapTip.new()
	var it := s.intel("hero_wren", WOLVES)
	tip.show_intel(it, Vector2(100, 100), Rect2(0, 0, 800, 600))
	assert_true(tip.visible)
	assert_true(MapTip.troop_lines(it)[0].begins_with(UiStyle.count_word(int(it["stacks"][0]["count"]))))
	assert_true(String(MapTip.scout_line(it)[0]).begins_with("S: send a scout"))
	s.scout("hero_wren", WOLVES)
	it = s.intel("hero_wren", WOLVES)
	assert_true(MapTip.troop_lines(it)[0].begins_with(str(int(it["stacks"][0]["count"]))))
	assert_true(String(MapTip.odds_line(it)[0]).contains("%"))
	tip.free()
	var bp := BattlePanels.new()
	bp.build(data)
	for hard in [false, true]:
		var g := _game(hard)
		var pred := g.preview_battle("hero_wren", WOLVES)
		pred["scout_cost"] = g.scout_cost("hero_wren")
		pred["scout_reason"] = ""
		bp.show_forecast("Wolves", pred)
		assert_true(bp.visible)
	bp.free()
