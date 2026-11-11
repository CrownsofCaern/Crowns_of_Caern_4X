extends "res://tests/test_case.gd"
## Map-overhaul scenario mechanics: villages, the townless recipe, objective
## gating and the week-one rule, ally objectives and the scripted betrayal.


# ---------------------------------------------------------------- helpers --

func _ember(sc: Dictionary = {}) -> GameSession:
	var rules := {"random_events": false}
	if not sc.is_empty():
		rules["scenario"] = sc
	return GameSession.new_game(data, "ember_ford", 7, {}, rules)


## Mournfield with teams: 0 (human) + 3 against 1 + 2.
func _mournfield(sc: Dictionary) -> GameSession:
	var setup := {"players": [
		{"type": "human", "faction": "concord", "team": 1},
		{"type": "computer", "faction": "ashen", "team": 2},
		{"type": "computer", "faction": "ashen", "team": 2},
		{"type": "computer", "faction": "concord", "team": 1}]}
	return GameSession.new_game(data, "mournfield", 7, setup, {"scenario": sc, "random_events": false})


func _betrayal_scenario(trigger: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var b := {"player": 3, "joins": 1, "trigger": trigger}
	b.merge(extra)
	return {"name": "Broken Oath", "player": 0, "betrayal": b, "objectives": [
		{"id": "save_ally", "type": "ally_survives", "player": 3, "until_betrayal": true},
		{"id": "win", "type": "conquer", "after_betrayal": true, "text": "Crush the traitor and the Ashen"}]}


func _village_site() -> String:
	var ids: Array = data.sites.keys()
	ids.sort()
	for sid in ids:
		if data.sites[sid]["kind"] == "village" and int(data.sites[sid].get("stock_types", 1)) == 2:
			return sid
	return ""


func _put_village(s: GameSession, h: Hero, extra: Dictionary = {}) -> Dictionary:
	var p := s._free_tile_near(h.pos)
	var o := {"id": "test_village", "type": "site", "site": _village_site(), "pos": [p.x, p.y]}
	o.merge(extra, true)
	s.state.map.add_object(o)
	MapSites.normalize(o, data)
	return o


# --------------------------------------------------------------- villages --

func test_village_data_and_default_stock() -> void:
	var sid := _village_site()
	assert_ne(sid, "", "a two-folk village exists")
	assert_true(MapSites.validate(data).is_empty(), "\n".join(MapSites.validate(data)))
	var s := _ember()
	var o := _put_village(s, s.hero("hero_wren"))
	assert_eq(int(o["owner"]), -1)
	assert_eq((o["stock"] as Array).size(), 2, "stock_types creatures")
	var again := {"id": "test_village", "type": "site", "site": sid, "pos": o["pos"]}
	MapSites.normalize(again, data)
	assert_eq(again["stock"], o["stock"], "the default stock depends only on the object")
	for pair in o["stock"]:
		assert_true(MapSites.creature_pool(data.sites[sid], data).has(pair[0]))
		assert_gt(int(pair[1]), 0)
	assert_true(MapSites.summary(o, data).contains("once only"))


func test_village_is_freed_once_and_sells_its_stock_once() -> void:
	var s := _ember()
	var h := s.hero("hero_wren")
	var o := _put_village(s, h, {"stock": [["pike_militia", 10], ["longbowman", 4]]})
	h.movement_left = 3000
	var mv := s.move_hero(h.id, AdventureMap.object_pos(o))
	assert_true(mv["captured"].has("test_village"), str(mv))
	assert_eq(int(o["owner"]), 0)
	var info := s.site_info("test_village", h.id)
	assert_eq(info["kind"], "village")
	assert_eq(info["offers"].size(), 2)
	assert_eq(s.site_recruit_error("test_village", h.id, 1, "lancer"), "nobody here offers that creature")
	var before := (s.current_player()["resources"] as ResourceBank).get_amount("gold")
	var r := s.site_recruit("test_village", h.id, 3, "longbowman")
	assert_true(r["ok"], str(r))
	assert_eq(MapSites.available(o, "longbowman", data), 1)
	assert_lt((s.current_player()["resources"] as ResourceBank).get_amount("gold"), before)
	assert_false(s.site_recruit("test_village", h.id, 2, "longbowman")["ok"], "only 1 left")
	s._weekly_growth()
	assert_eq(MapSites.available(o, "longbowman", data), 1, "a village never refills")
	assert_eq(MapSites.available(o, "pike_militia", data), 10)


func test_village_stays_with_whoever_freed_it() -> void:
	var s := _ember()
	var h := s.hero("hero_wren")
	var o := _put_village(s, h, {"owner": 1, "stock": [["pike_militia", 10]]})
	h.movement_left = 3000
	var mv := s.move_hero(h.id, AdventureMap.object_pos(o))
	assert_true(mv["captured"].is_empty())
	assert_eq(int(o["owner"]), 1)
	assert_eq(StrategicAI.new(s, 0).site_value(h, o), 0.0, "a village freed by someone else is worth nothing")
	o["owner"] = -1
	assert_gt(StrategicAI.new(s, 0).site_value(h, o), 0.0, "an unclaimed village is worth its stock")


func test_ai_buys_from_its_village() -> void:
	var s := _ember()
	var h := s.hero("hero_wren")
	var o := _put_village(s, h, {"owner": 0, "stock": [["pike_militia", 10], ["longbowman", 4]]})
	h.pos = AdventureMap.object_pos(o)
	var ai := StrategicAI.new(s, 0)
	var troops := h.army.total_creatures()
	ai._recruit_at_site(h, "test_village")
	assert_eq(h.army.total_creatures(), troops + 14, "both offers bought")
	assert_eq(MapSites.available(o, "pike_militia", data), 0)


func test_village_stock_is_validated() -> void:
	var def: Dictionary = data.load_map("ember_ford")
	def["objects"].append({"id": "v", "type": "site", "site": _village_site(), "pos": [5, 9], "stock": [["no_such_folk", 3]]})
	assert_true(", ".join(MapValidator.validate(def, data)).contains("bad village stock"))


func test_random_generator_never_places_villages() -> void:
	for seed_value in [1, 2, 3]:
		for o in MapGenerator.generate(data, "twin_marches", seed_value)["objects"]:
			if o["type"] == "site":
				assert_ne(data.sites[o["site"]]["kind"], "village")


# -------------------------------------------------------------- townless --

func test_townless_recipe_builds_a_fair_hard_start() -> void:
	assert_eq(ScenarioGenerator.validate(data), [] as Array[String])
	for seed_value in [1, 2]:
		var def := ScenarioGenerator.generate(data, "townless_v1", seed_value)
		assert_false(def.is_empty(), "seed %d builds" % seed_value)
		if def.is_empty():
			continue
		assert_true(MapValidator.validate(def, data).is_empty(), ", ".join(MapValidator.validate(def, data)))
		var sc: Dictionary = def["scenario"]
		assert_eq(sc["townless_players"], [0])
		for o in def["objects"]:
			if o["type"] == "town":
				assert_ne(int(o["owner"]), 0, "the player starts without a town")
		var report: Dictionary = sc["townless"]
		assert_between(report["villages"].size(), 3, 5)
		assert_between(float(report["gold"]) / float(report["stock_gold"]), 0.55, 0.75, "gold buys about two thirds of the stock")
		assert_lt(float(report["start_win"]), 0.5, "the starting army alone should usually lose")
		assert_gt(float(report["best_win"]), 0.95, "the best affordable army takes the town")
		var s := GameSession.new_game(data, String(def["id"]), 3)
		assert_eq(s.state.heroes_of(0).size(), 1)
		for _i in 8 * s.state.players.size():
			s.end_turn()
		assert_false(bool(s.state.player(0)["defeated"]), "a townless player is not eliminated for having no town")


# ------------------------------------------------------- gating, optional --

func test_unlock_day_and_optional_objectives() -> void:
	var sc := {"name": "Gated", "player": 0, "objectives": [
		{"id": "centre", "type": "reach", "hero": "hero_wren", "pos": [5, 8], "unlock_day": 3},
		{"id": "bonus", "type": "reach", "hero": "hero_maelis", "pos": [20, 15], "optional": true}]}
	var s := _ember(sc)
	s.move_hero("hero_wren", Vector2i(5, 8))
	assert_false(s.state.game_over, "a gated goal cannot be done early")
	assert_true(s.scenario_objectives()[0]["text"].contains("from day 3"))
	assert_true(s.scenario_objectives()[1]["text"].begins_with("Optional"))
	s.state.day = 3
	var h := s.hero("hero_wren")
	h.movement_left = 3000
	s.move_hero(h.id, Vector2i(4, 8))
	s.move_hero(h.id, Vector2i(5, 8))
	assert_eq(s.state.end_reason, "scenario_victory", "the optional goal is not needed")


func test_scenario_validation_of_new_fields() -> void:
	var bad := {"name": "x", "player": 0, "objectives": [{"id": "a", "type": "conquer", "optional": true}]}
	assert_true(", ".join(ScenarioRules.validate(bad)).contains("required"))
	bad["objectives"] = [{"id": "a", "type": "conquer", "unlock_day": 0}]
	assert_true(", ".join(ScenarioRules.validate(bad)).contains("unlock_day"))
	bad["objectives"] = [{"id": "a", "type": "conquer", "after_betrayal": true}]
	assert_true(", ".join(ScenarioRules.validate(bad)).contains("need a betrayal"))
	bad["objectives"] = [{"id": "a", "type": "ally_survives", "player": 0}]
	assert_true(", ".join(ScenarioRules.validate(bad)).contains("another player"))
	var map_def := {"width": 10, "height": 10, "heroes": [], "objects": [],
		"players": [{"team": 1}, {"team": 2}, {"team": 2}, {"team": 0}]}
	bad["objectives"] = [{"id": "a", "type": "ally_survives", "player": 3}]
	assert_true(", ".join(ScenarioRules.validate(bad, map_def)).contains("start allied"))
	var b := _betrayal_scenario({"day": 3})
	assert_true(", ".join(ScenarioRules.validate(b, map_def)).contains("traitor must start allied"))
	map_def["players"][3]["team"] = 1
	assert_eq(ScenarioRules.validate(b, map_def), [] as Array[String])
	b["betrayal"]["trigger"] = {"week": 2}
	assert_true(", ".join(ScenarioRules.validate(b, map_def)).contains("unknown betrayal trigger"))


func test_mission_site_unlock_day_blocks_its_action() -> void:
	var s := _ember({"name": "Sites", "player": 0, "objectives": [{"id": "hold", "type": "survive", "through_day": 30}]})
	var h := s.hero("hero_wren")
	var p := s._free_tile_near(h.pos)
	s.state.map.add_object({"id": "tower", "type": "scenario_site", "kind": "watchtower", "name": "Old Tower", "pos": [p.x, p.y], "unlock_day": 9})
	h.pos = p
	var opts := s.scenario_options(h.id, "tower")
	assert_eq(opts["actions"].size(), 1)
	assert_true(String(opts["actions"][0]["reason"]).contains("day 9"))
	assert_false(s.scenario_act(h.id, "tower", "claim")["ok"])
	s.state.day = 9
	assert_eq(String(s.scenario_options(h.id, "tower")["actions"][0]["reason"]), "")


func test_week_one_rule_flags_easy_optional_goals_only() -> void:
	var sc := {"name": "Week one", "player": 0, "objectives": [{"id": "hold", "type": "survive", "through_day": 30}]}
	var s := _ember(sc)
	var h := s.hero("hero_wren")
	var p := s._free_tile_near(h.pos + Vector2i(3, 0))
	var site := {"id": "supplies", "type": "scenario_site", "kind": "supplies", "name": "Grain Cart", "pos": [p.x, p.y]}
	s.state.map.add_object(site)
	var problems := ScenarioGating.week_one_problems(s)
	assert_eq(problems.size(), 1, str(problems))
	assert_true(problems[0].contains("Grain Cart"))
	site["unlock_day"] = 10
	assert_eq(ScenarioGating.week_one_problems(s), [] as Array[String], "gated by day")
	site.erase("unlock_day")
	site["guard"] = [["pyre_titan", 40]]
	assert_eq(ScenarioGating.week_one_problems(s), [] as Array[String], "gated by a guard the starting army loses to")


# ------------------------------------------------------- allies, betrayal --

func test_conquer_and_ally_survives() -> void:
	var sc := {"name": "Two against two", "player": 0, "objectives": [
		{"id": "ally", "type": "ally_survives", "player": 3},
		{"id": "win", "type": "conquer"}]}
	var s := _mournfield(sc)
	assert_true(s.allied(0, 3))
	VictoryRules.eliminate(s, 1, "test")
	VictoryRules.update(s)
	assert_false(s.state.game_over)
	VictoryRules.eliminate(s, 2, "test")
	VictoryRules.update(s)
	assert_eq(s.state.end_reason, "scenario_victory")
	var lost := _mournfield(sc)
	VictoryRules.eliminate(lost, 3, "test")
	VictoryRules.update(lost)
	assert_eq(lost.state.end_reason, "scenario_defeat")
	assert_true(lost.game_result()["text"].contains("ally has fallen"))


func test_betrayal_on_a_day_switches_sides_and_survives_a_save() -> void:
	var s := _mournfield(_betrayal_scenario({"day": 3}, {"reinforcements": [["pike_militia", 20]]}))
	assert_eq(s.scenario_objectives().size(), 1, "the betrayal objective is hidden")
	var garrison_before := Town.garrison(s.town("town_sallowmoor")).total_creatures()
	while s.state.day < 3:
		s.end_turn()
	assert_true(ScenarioBetrayal.happened(s.state))
	assert_eq(ScenarioBetrayal.day(s.state), 3)
	assert_false(s.allied(0, 3), "the ally turned")
	assert_true(s.allied(3, 1), "it fights for the Ashen now")
	assert_eq(Town.garrison(s.town("town_sallowmoor")).total_creatures(), garrison_before + 20)
	assert_eq(s.scenario_objectives().size(), 2, "the new objective shows")
	assert_true(", ".join(s.state.player(0)["news"]).contains("breaks the alliance"), str(s.state.player(0)["news"]))
	VictoryRules.eliminate(s, 3, "test")
	VictoryRules.update(s)
	assert_false(s.state.game_over, "after the turn, losing the traitor is no defeat")
	var save: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	assert_eq(int(save["version"]), GameState.SAVE_VERSION)
	assert_true(GameState.validate_save(save).is_empty(), ", ".join(GameState.validate_save(save)))
	var loaded := GameSession.from_state(data, GameState.from_dict(save, data))
	assert_true(ScenarioBetrayal.happened(loaded.state))
	assert_false(loaded.allied(0, 3))
	VictoryRules.eliminate(loaded, 1, "test")
	VictoryRules.eliminate(loaded, 2, "test")
	VictoryRules.update(loaded)
	assert_eq(loaded.state.end_reason, "scenario_victory")


func test_betrayal_when_the_common_enemy_loses_its_towns() -> void:
	var s := _mournfield(_betrayal_scenario({"towns_lost": 1}))
	VictoryRules.update(s)
	assert_false(ScenarioBetrayal.happened(s.state))
	s.town("town_pyrewatch")["owner"] = 0
	VictoryRules.update(s)
	assert_true(ScenarioBetrayal.happened(s.state))
	assert_false(s.allied(0, 3))


func test_betrayal_when_the_player_side_takes_listed_towns() -> void:
	var s := _mournfield(_betrayal_scenario({"towns_taken": {"towns": ["town_pyrewatch", "town_rimecairn"], "count": 2}}))
	VictoryRules.update(s)
	assert_false(ScenarioBetrayal.happened(s.state))
	s.town("town_pyrewatch")["owner"] = 0
	VictoryRules.update(s)
	assert_false(ScenarioBetrayal.happened(s.state), "one of two is not enough")
	s.town("town_rimecairn")["owner"] = 3
	VictoryRules.update(s)
	assert_true(ScenarioBetrayal.happened(s.state), "a town the ally took counts for the player's side")
	assert_false(s.allied(0, 3))


func test_betrayal_towns_taken_defaults_to_every_listed_town() -> void:
	var s := _mournfield(_betrayal_scenario({"towns_taken": {"towns": ["town_pyrewatch", "town_mournfield"]}}))
	s.town("town_pyrewatch")["owner"] = 0
	VictoryRules.update(s)
	assert_false(ScenarioBetrayal.happened(s.state), "the neutral town is not the player's yet")
	s.town("town_mournfield")["owner"] = 0
	VictoryRules.update(s)
	assert_true(ScenarioBetrayal.happened(s.state))


func test_betrayal_when_the_enemy_takes_one_of_the_players_towns() -> void:
	var s := _mournfield(_betrayal_scenario({"towns_taken": {"towns": ["town_lanternholm", "town_sallowmoor"], "count": 1, "by": 1}}))
	VictoryRules.update(s)
	assert_false(ScenarioBetrayal.happened(s.state))
	s.town("town_lanternholm")["owner"] = 2
	VictoryRules.update(s)
	assert_true(ScenarioBetrayal.happened(s.state), "player 2 is player 1's ally, so the Ashen side took a town")


func test_betrayal_towns_taken_is_validated() -> void:
	var def := data.load_map("mournfield")
	for p in def["players"]:
		p["team"] = 1 if int(p["id"]) in [0, 3] else 2
	var ok := _betrayal_scenario({"towns_taken": {"towns": ["town_pyrewatch"], "count": 1}})
	assert_eq(ScenarioBetrayal.validate(ok, def, data), [] as Array[String])
	for bad in [{"towns": []}, {"towns": ["town_pyrewatch"], "count": 2}, {"towns": ["town_pyrewatch"], "count": 0}, {"count": 1}, "town_pyrewatch", {"towns": ["town_pyrewatch"], "by": 9}, {"towns": ["town_pyrewatch"], "by": -1}]:
		assert_false(ScenarioBetrayal.validate(_betrayal_scenario({"towns_taken": bad}), def, data).is_empty(), "rejects %s" % str(bad))
	var errors := ScenarioBetrayal.validate(_betrayal_scenario({"towns_taken": {"towns": ["town_nowhere"]}}), def, data)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("town_nowhere"))


func test_betrayal_when_a_hero_reaches_a_spot_and_no_early_win() -> void:
	var s := _mournfield(_betrayal_scenario({"reach": {"pos": [14, 10], "radius": 2}}))
	VictoryRules.eliminate(s, 1, "test")
	VictoryRules.eliminate(s, 2, "test")
	VictoryRules.update(s)
	assert_false(s.state.game_over, "the conquest waits for the betrayal")
	var h: Hero = s.state.heroes_of(0)[0]
	h.pos = Vector2i(13, 9)
	VictoryRules.update(s)
	assert_true(ScenarioBetrayal.happened(s.state))
	assert_true(s.allied(3, 1))
	assert_false(s.state.game_over, "the traitor is still in the field")


func test_old_saves_have_no_betrayal() -> void:
	var s := _mournfield(_betrayal_scenario({"day": 9}))
	var save: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	save["version"] = 18
	var loaded := GameState.from_dict(save, data)
	assert_false(ScenarioBetrayal.happened(loaded))
	save["scenario_runtime"]["betrayal"] = {"day": "soon"}
	assert_false(GameState.validate_save(save).is_empty())
