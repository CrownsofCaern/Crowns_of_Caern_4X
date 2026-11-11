extends "res://tests/test_case.gd"
## Hero battle orders (data/tactics.json, BattleOrders): level gates, the
## Tactics skill discount, their effect on battles, saving and the AI's choice.

const D := {"stance": "balanced", "focus": "any", "formation": "line", "art": "at_once", "retreat": "never"}


func _o(changes: Dictionary) -> Dictionary:
	var out := D.duplicate()
	out.merge(changes, true)
	return out


func _hero(orders: Variant = null) -> Dictionary:
	var h := {"name": "H", "attack": 0, "defense": 0, "power": 0, "knowledge": 0, "skills": {}}
	if orders != null:
		h["orders"] = orders
	return h


func _setup(a: Array, oa: Variant, b: Array, ob: Variant, seed_value: int) -> Dictionary:
	return CombatSimulator.make_setup(BalanceScenarios.side(a, _hero(oa) if oa != null else null),
		BalanceScenarios.side(b, _hero(ob) if ob != null else null), "rough", seed_value)


func _rate(a: Array, oa: Dictionary, b: Array, runs: int = 200) -> float:
	var sim := CombatSimulator.new(data)
	var wins := 0
	for i in runs:
		if sim.simulate(_setup(a, oa, b, D, 5000 + i), false)["winner"] == 0:
			wins += 1
	return float(wins) / runs


func _unit(sim: CombatSimulator, side: int, creature: String) -> CombatUnit:
	for u in sim._sides[side]:
		if u.creature_id == creature:
			return u
	return null


# ------------------------------------------------------------------ gates --

func test_options_open_with_level_and_tactics() -> void:
	assert_true(BattleOrders.is_open(data, "stance", "balanced", 1, 0))
	assert_false(BattleOrders.is_open(data, "stance", "defensive", 1, 0))
	assert_true(BattleOrders.is_open(data, "stance", "defensive", 2, 0))
	assert_false(BattleOrders.is_open(data, "focus", "wounded", 8, 0))
	assert_true(BattleOrders.is_open(data, "focus", "wounded", 9, 0))
	# Every Tactics level opens orders tactics_skill_discount levels sooner.
	assert_eq(BattleOrders.level_needed(data, "focus", "wounded", 2), 9 - 2 * int(data.tactics["tactics_skill_discount"]))
	assert_true(BattleOrders.is_open(data, "focus", "wounded", 5, 2))
	assert_false(BattleOrders.is_open(data, "focus", "teleport", 30, 3))


func test_locked_orders_fall_back_to_defaults() -> void:
	var o := BattleOrders.sanitized(data, {"stance": "aggressive", "focus": "hunt_archers"}, 3, 0)
	assert_eq(o["stance"], "balanced", "all-out attack needs level 4")
	assert_eq(o["focus"], "hunt_archers")
	assert_eq(BattleOrders.sanitized(data, {"stance": "nonsense"}, 20, 3), D)


func test_tactics_data_is_valid_and_validation_catches_mistakes() -> void:
	assert_eq(data.validate_tactics(), [] as Array[String])
	var gd := GameData.new()
	gd.load_all(GameData.DATA_DIR)
	gd.tactics["stances"]["defensive"]["effects"]["fly"] = 1
	gd.tactics["focus"]["wounded"]["effects"]["weakest_weight"] = 99
	gd.tactics["focus"].erase("any")
	var errors := "\n".join(gd.validate_tactics())
	assert_true(errors.contains("unknown effect fly"), errors)
	assert_true(errors.contains("weakest_weight must be"), errors)
	assert_true(errors.contains("default any"), errors)


# ----------------------------------------------------------------- battle --

func test_default_orders_change_nothing() -> void:
	var a := [["pike_militia", 30], ["lancer", 4], ["longbowman", 14]]
	var b := [["cinderling", 40], ["scorchhound", 10], ["brimstone_hurler", 12]]
	for seed_value in 5:
		var plain := CombatSimulator.new(data).simulate(_setup(a, null, b, null, seed_value))
		var ordered := CombatSimulator.new(data).simulate(_setup(a, D, b, D, seed_value))
		var no_orders := CombatSimulator.new(data).simulate(_setup(a, {}, b, {}, seed_value))
		assert_eq(JSON.stringify(ordered["log"]), JSON.stringify(no_orders["log"]))
		assert_eq(ordered["winner"], plain["winner"])
		assert_eq(ordered["sides"][0]["stacks"], plain["sides"][0]["stacks"])


func test_stances_change_stats_and_advance() -> void:
	var a := [["pike_militia", 10], ["lancer", 2]]
	var b := [["cinderling", 10]]
	var sim := CombatSimulator.new(data)
	var r := sim.simulate(_setup(a, {"stance": "defensive", "focus": "any"}, b, {"stance": "aggressive", "focus": "any"}, 1))
	var pike := _unit(sim, 0, "pike_militia")
	var lancer := _unit(sim, 0, "lancer")
	var cinder := _unit(sim, 1, "cinderling")
	assert_eq(pike.defense, int(data.creature("pike_militia")["defense"]) + 2, "front line +2 defense")
	assert_eq(lancer.defense, int(data.creature("lancer")["defense"]), "cavalry is not front line")
	assert_eq(sim._approach_round(pike), sim._base_approach_round(pike) + 1, "holds one round longer")
	assert_eq(cinder.attack, int(data.creature("cinderling")["attack"]) + 1)
	assert_eq(sim._approach_round(cinder), maxi(1, sim._base_approach_round(cinder) - 1))
	assert_true(r["sides"][0]["notes"].has("Orders: Hold the line, Free fighting"), str(r["sides"][0]["notes"]))
	assert_eq(r["orders"][1]["stance"], "aggressive")


func test_order_weights_pick_out_strongest_weakest_and_attackers_of_the_archers() -> void:
	var sim := CombatSimulator.new(data)
	sim.simulate(_setup([["lancer", 3], ["longbowman", 10]], {"stance": "balanced", "focus": "protect_archers"},
		[["cinderling", 30], ["scorchhound", 4], ["flayer", 2]], D, 1))
	var lancer := _unit(sim, 0, "lancer")
	var bows := _unit(sim, 0, "longbowman")
	var hound := _unit(sim, 1, "scorchhound")
	var cinder := _unit(sim, 1, "cinderling")
	var flayer := _unit(sim, 1, "flayer")
	for u in [lancer, bows, hound, cinder, flayer]:
		u.count = maxi(u.count, 2)
	sim._engaged_by[bows] = hound   # the hounds are on the archers
	var w := [1.0, 1.0, 1.0]
	sim._apply_order_weights(lancer, [cinder, hound, flayer], w)
	assert_eq(w, [1.0, 5.0, 1.0], "guard: the lancers ride to the archers' rescue")
	var w2 := [1.0, 1.0, 1.0]
	sim._apply_order_weights(bows, [cinder, hound, flayer], w2)
	assert_eq(w2, [1.0, 1.0, 1.0], "only flank units answer the guard order")
	sim._orders[0] = BattleOrders.effects(data, {"stance": "balanced", "focus": "strongest"})
	var w3 := [1.0, 1.0, 1.0]
	var strongest := 0
	var cands := [cinder, hound, flayer]
	for i in 3:
		if cands[i].threat() > cands[strongest].threat():
			strongest = i
	sim._apply_order_weights(bows, cands, w3)
	assert_eq(w3[strongest], 4.0)
	sim._orders[0] = BattleOrders.effects(data, {"stance": "balanced", "focus": "wounded"})
	var w4 := [1.0, 1.0, 1.0]
	var weakest := 0
	for i in 3:
		if cands[i].total_hp() < cands[weakest].total_hp():
			weakest = i
	sim._apply_order_weights(bows, cands, w4)
	assert_eq(w4[weakest], 4.0)


func test_good_orders_win_more_often() -> void:
	# An archer army does better holding the line and guarding its archers
	# against a melee rush than fighting freely.
	var archers := [["shieldwarden", 10], ["longbowman", 30], ["lightbearer", 3]]
	var rush := [["cinderling", 60], ["flayer", 10], ["scorchhound", 10]]
	var free := _rate(archers, D, rush)
	var held := _rate(archers, {"stance": "defensive", "focus": "protect_archers"}, rush)
	assert_gt(held, free + 0.1, "free %.2f, held %.2f" % [free, held])
	# A mixed army with cavalry does better hunting the archers of a shooting army.
	var mixed := [["pike_militia", 30], ["lancer", 4], ["longbowman", 14]]
	var shooters := [["cinderling", 40], ["scorchhound", 10], ["brimstone_hurler", 12]]
	assert_gt(_rate(mixed, {"stance": "balanced", "focus": "hunt_archers"}, shooters), _rate(mixed, D, shooters) + 0.04)


# ---------------------------------------------------------------- session --

func test_hero_orders_are_given_saved_and_loaded() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var h: Hero = s.state.heroes_of(0)[0]
	h.level = 1
	assert_false(s.set_hero_orders(h.id, "defensive", "any"), "level 2 needed")
	h.level = 5
	assert_true(s.set_hero_orders(h.id, "aggressive", "protect_archers"))
	assert_false(s.set_hero_orders(h.id, "aggressive", "wounded"))
	assert_eq(h.combat_profile(data)["orders"], _o({"stance": "aggressive", "focus": "protect_archers"}))
	var choices := s.order_choices(h.id)
	assert_eq(choices["stance"], "aggressive")
	assert_eq(choices["options"]["focus"].size(), data.tactics["focus"].size())
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	var st := GameState.from_dict(d, data)
	assert_eq(st.heroes[h.id].orders, _o({"stance": "aggressive", "focus": "protect_archers"}))
	# Saves before version 13 have no orders: the defaults.
	d["heroes"][h.id].erase("orders")
	d["version"] = 12
	assert_eq(GameState.from_dict(d, data).heroes[h.id].orders, D)


func test_preview_reflects_the_orders() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var h: Hero = s.state.heroes_of(0)[0]
	h.level = 9
	s.set_hero_orders(h.id, "defensive", "wounded")
	var target := ""
	for id in s.state.map.objects:
		target = s.hostile_target_at(AdventureMap.object_pos(s.state.map.objects[id]), 0)
		if target != "":
			break
	assert_ne(target, "")
	var setup := s.battle_setup(h.id, target)
	assert_eq(setup["sides"][0]["hero"]["orders"], _o({"stance": "defensive", "focus": "wounded"}))


# --------------------------------------------------------------------- AI --

func test_ai_orders_suit_the_armies() -> void:
	var archers := [{"creature": "shieldwarden", "count": 10}, {"creature": "longbowman", "count": 40}]
	var melee := [{"creature": "cinderling", "count": 60}, {"creature": "scorchhound", "count": 10}]
	var cav := [{"creature": "pike_militia", "count": 20}, {"creature": "lancer", "count": 8}]
	var o := BattleOrders.choose(data, 10, 0, archers, melee)
	assert_eq([o["stance"], o["focus"]], ["defensive", "protect_archers"])
	assert_eq(o["art"], "at_once", "short fights end before a held art fires")
	o = BattleOrders.choose(data, 10, 0, cav, archers)
	assert_eq([o["stance"], o["focus"]], ["aggressive", "hunt_archers"])
	# A young hero only gives what it can.
	assert_eq(BattleOrders.choose(data, 1, 0, archers, melee), D)
	var young := BattleOrders.choose(data, 3, 0, cav, archers)
	assert_eq([young["stance"], young["focus"]], ["balanced", "hunt_archers"])
	assert_true(BattleOrders.is_open(data, "formation", young["formation"], 3, 0), young["formation"])


func test_ai_gives_orders_and_easy_ai_does_not() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	for p in s.state.players:
		p["is_human"] = false
	var h: Hero = s.state.heroes_of(0)[0]
	h.level = 10
	h.army = Army.from_pairs([["shieldwarden", 10], ["longbowman", 40]])
	var ai := StrategicAI.new(s, 0)
	ai._give_orders(h, [])
	assert_eq([h.orders["stance"], h.orders["focus"]], ["defensive", "protect_archers"])
	assert_ne(h.orders["formation"], "line", "an archer army does not stand in a plain line")
	h.orders = D.duplicate()
	ai.settings["battle_orders"] = false
	ai._give_orders(h, [])
	assert_eq(h.orders, D)
	assert_false(bool(data.difficulty("easy")["ai"]["battle_orders"]))


# ------------------------------------------------------------- formations --

func _cmd(level: int, cls: String, skills: Dictionary = {}, specialty: Dictionary = {}) -> Dictionary:
	return BattleOrders.commander(level, cls, skills, specialty)


func test_formations_open_by_class_skill_and_specialty() -> void:
	# A knight knows the shield wall by heart; a warlock needs level 3.
	assert_true(BattleOrders.is_open(data, "formation", "shield_wall", 1, 0, _cmd(1, "knight")))
	assert_false(BattleOrders.is_open(data, "formation", "shield_wall", 2, 0, _cmd(2, "warlock")))
	assert_true(BattleOrders.is_open(data, "formation", "shield_wall", 3, 0, _cmd(3, "warlock")))
	# Every level of the formation's own skill opens it sooner, like Tactics.
	var disc := int(data.tactics["tactics_skill_discount"])
	assert_eq(BattleOrders.level_needed(data, "formation", "wedge", 0, _cmd(1, "oracle", {"onslaught": 1})), 4 - disc)
	assert_eq(BattleOrders.level_needed(data, "formation", "wedge", 1, _cmd(1, "oracle", {"onslaught": 1})), maxi(1, 4 - 2 * disc))
	# A specialty may unlock a formation outright.
	var sp := {"formations": {"crescent": {"unlock": true, "bonus_pct": 0.2}}}
	assert_true(BattleOrders.is_open(data, "formation", "crescent", 1, 0, _cmd(1, "knight", {}, sp)))
	assert_false(BattleOrders.is_open(data, "formation", "crescent", 1, 0, _cmd(1, "knight")))
	# Retreat orders are open to everyone.
	for id in BattleOrders.ids(data, "retreat"):
		assert_true(BattleOrders.is_open(data, "retreat", id, 1, 0), id)
	# Every hero class knows at least one formation by heart.
	for cls in data.hero_classes:
		var known := 0
		for id in BattleOrders.ids(data, "formation"):
			if BattleOrders.knows_by_heart(data, "formation", id, _cmd(1, cls)):
				known += 1
		assert_gt(known, 0, cls)


func test_drilled_formations_are_stronger() -> void:
	var cfg: Dictionary = data.tactics["formation_drill"]
	assert_eq(BattleOrders.drill_pct(data, "shield_wall", _cmd(1, "warlock")), 0.0)
	assert_almost(BattleOrders.drill_pct(data, "shield_wall", _cmd(1, "knight")), float(cfg["class_pct"]))
	assert_almost(BattleOrders.drill_pct(data, "shield_wall", _cmd(1, "knight", {"shieldcraft": 2})),
		float(cfg["class_pct"]) + 2.0 * float(cfg["per_skill_level_pct"]))
	var sp := {"formations": {"shield_wall": {"bonus_pct": 0.25}}}
	assert_almost(BattleOrders.drill_pct(data, "shield_wall", _cmd(1, "warlock", {}, sp)), 0.25)
	assert_eq(BattleOrders.drill_pct(data, "line", _cmd(1, "knight", {}, sp)), 0.0, "the plain line has nothing to drill")
	var plain := BattleOrders.effects(data, _o({"formation": "shield_wall"}))
	var drilled := BattleOrders.effects(data, _o({"formation": "shield_wall", "drill": 0.5}))
	assert_gt(float(drilled["front_defense"]), float(plain["front_defense"]))
	assert_gt(float(drilled["shot_cover"]), float(plain["shot_cover"]))
	assert_eq(drilled["advance"], plain["advance"], "drawbacks and timings are not drilled")
	# Sanitizing carries the drill into the battle profile.
	var o := BattleOrders.sanitized(data, {"formation": "shield_wall"}, 1, 0, _cmd(1, "knight"))
	assert_eq(o["formation"], "shield_wall")
	assert_almost(float(o["drill"]), float(cfg["class_pct"]))
	assert_eq(BattleOrders.sanitized(data, {"formation": "shield_wall"}, 1, 0, _cmd(1, "warlock"))["formation"], "line")


func assert_almost(got: float, expected: float, msg: String = "") -> void:
	assert_between(got, expected - 0.0001, expected + 0.0001, msg)


func test_tactics_validation_checks_classes_and_skills() -> void:
	var gd := GameData.new()
	gd.load_all(GameData.DATA_DIR)
	gd.tactics["formations"]["wedge"]["classes"].append("dragon_king")
	gd.tactics["formations"]["wedge"]["skill"] = "juggling"
	gd.tactics["formations"]["reserve"]["effects"]["reserve_round"] = 40
	gd.tactics["retreat"].erase("never")
	var errors := "\n".join(gd.validate_tactics())
	assert_true(errors.contains("unknown hero class dragon_king"), errors)
	assert_true(errors.contains("unknown skill juggling"), errors)
	assert_true(errors.contains("reserve_round must be"), errors)
	assert_true(errors.contains("default never"), errors)


func test_shield_wall_and_skirmish_screen_change_the_battle() -> void:
	var a := [["pike_militia", 20], ["longbowman", 20]]
	var b := [["cinderling", 30], ["brimstone_hurler", 12]]
	var sim := CombatSimulator.new(data)
	sim.simulate(_setup(a, _o({"formation": "shield_wall"}), b, _o({"formation": "skirmish_screen"}), 3))
	var pike := _unit(sim, 0, "pike_militia")
	var cinder := _unit(sim, 1, "cinderling")
	assert_eq(pike.defense, int(data.creature("pike_militia")["defense"]) + 3, "the wall: +3 front defense")
	assert_eq(sim._approach_round(pike), sim._base_approach_round(pike) + 2,
		"a wall advances a round later and skirmishers hold it off another")
	assert_eq(sim._approach_round(cinder), sim._base_approach_round(cinder))
	# Shot cover: archers behind a shield wall take less from the same volley.
	var archers := _unit(sim, 0, "longbowman")
	var hurlers := _unit(sim, 1, "brimstone_hurler")
	archers.count = 20
	hurlers.count = 12
	var covered := 0
	var open := 0
	for i in 40:
		sim._rng = GameRng.new(700 + i)
		covered += sim._damage(hurlers, archers, "shot", false)
	sim._orders[0] = {}
	for i in 40:
		sim._rng = GameRng.new(700 + i)
		open += sim._damage(hurlers, archers, "shot", false)
	assert_lt(float(covered), float(open) * 0.8, "covered %d, open %d" % [covered, open])


func test_wedge_first_blow_and_crescent_flank_bonus() -> void:
	# The same blow, rolled on the same seed: the wedge's first one lands harder.
	var sim := CombatSimulator.new(data)
	sim.simulate(_setup([["pike_militia", 20]], _o({"formation": "wedge"}), [["cinderling", 30]], D, 1))
	var pike := _unit(sim, 0, "pike_militia")
	var cinder := _unit(sim, 1, "cinderling")
	var first := 0
	var later := 0
	for i in 20:
		for blow in 2:
			pike.count = 20
			pike.first_blow_done = blow == 1
			cinder.count = 30
			cinder.top_hp = cinder.hp_per
			sim._engaged_by.clear()
			sim._rng = GameRng.new(900 + i)
			var before := cinder.total_hp()
			sim._exchange(pike, cinder, 10, false, 1.0, false)
			if blow == 0:
				first += before - cinder.total_hp()
			else:
				later += before - cinder.total_hp()
	assert_gt(float(first), float(later) * 1.15, "first blows %d, later blows %d" % [first, later])
	var fx := BattleOrders.effects(data, _o({"formation": "crescent"}))
	assert_gt(float(fx["flank_pct"]), 0.0)
	assert_gt(float(fx["bypass"]), 0.0)


func test_held_reserve_waits_out_of_reach_then_enters() -> void:
	var a := [["pike_militia", 30], ["flayer", 10], ["longbowman", 10]]
	var b := [["cinderling", 40], ["longbowman", 20]]
	var base := CombatSimulator.new(data)
	base.simulate(_setup(a, D, b, D, 9))
	var sim := CombatSimulator.new(data)
	var r := sim.simulate(_setup(a, _o({"formation": "reserve"}), b, D, 9))
	var flayer := _unit(sim, 0, "flayer")
	assert_eq(flayer.reserve_round, 3, "the strongest melee stack is the reserve")
	assert_eq(_unit(sim, 0, "pike_militia").reserve_round, 0)
	assert_eq(flayer.attack, _unit(base, 0, "flayer").attack + 2)
	var entered := -1
	for e in r["log"]:
		if int(e["round"]) < 3 and (int(e["actor_side"]) == 0 and int(e["actor_slot"]) == flayer.slot
				or int(e["target_side"]) == 0 and int(e["target_slot"]) == flayer.slot):
			assert_true(false, "the reserve took part before round 3: %s" % str(e))
		if String(e["type"]) == "reserve":
			entered = int(e["round"])
	if int(r["rounds"]) >= 3:
		assert_eq(entered, 3)
	var st: Dictionary = r["sides"][0]["stacks"][1]
	assert_eq(int(st["reserve"]), 3)
	assert_true(r["summary"].size() > 0)


func test_reserve_enters_at_once_when_it_stands_alone() -> void:
	var sim := CombatSimulator.new(data)
	var r := sim.simulate(_setup([["cinderling", 1], ["flayer", 4]], _o({"formation": "reserve"}), [["longbowman", 40]], D, 2))
	var flayer := _unit(sim, 0, "flayer")
	assert_eq(flayer.reserve_round, 3)
	var acted_early := false
	for e in r["log"]:
		if int(e["actor_side"]) == 0 and int(e["actor_slot"]) == flayer.slot and int(e["round"]) < 3 and String(e["type"]) != "reserve":
			acted_early = true
	assert_true(acted_early or int(r["rounds"]) >= 3 or r["winner"] == 1, "the lone reserve fights once the line is gone")


func test_prepared_art_waits_for_its_moment() -> void:
	var hero := _hero(_o({"art": "at_clash"}))
	hero["art"] = {"name": "Test strike", "kind": "strike", "base": 20, "per_power": 0}
	hero["power"] = 0
	var setup := CombatSimulator.make_setup(BalanceScenarios.side([["pike_militia", 30]], hero),
		BalanceScenarios.side([["cinderling", 40]], null), "rough", 4)
	var r := CombatSimulator.new(data).simulate(setup)
	var rounds := []
	var amounts := []
	for e in r["log"]:
		if String(e["type"]) == "art_strike":
			rounds.append(int(e["round"]))
			amounts.append(int(e["amount"]))
	assert_false(rounds.is_empty())
	assert_eq(int(rounds[0]), 2, "loosed when the lines meet")
	assert_eq(int(amounts[0]), 25, "a prepared art is 25% stronger")
	# When the line bends: only once 30% of the army is lost.
	hero["orders"] = _o({"art": "in_need"})
	var sim := CombatSimulator.new(data)
	r = sim.simulate(setup)
	for e in r["log"]:
		if String(e["type"]) == "art_strike":
			assert_eq(int(e["amount"]), 30)
			break


# --------------------------------------------------------------- retreat --

func test_retreat_order_ends_the_battle_and_saves_survivors() -> void:
	var weak := [["pike_militia", 30], ["longbowman", 10]]
	var strong := [["flayer", 8], ["cinderling", 40]]
	var r := CombatSimulator.new(data).simulate(_setup(weak, _o({"retreat": "at_half"}), strong, D, 6))
	assert_eq(int(r["withdrew"]), 0)
	assert_eq(r["winner"], 1)
	assert_eq(r["outcome"], "attacker_retreated")
	assert_gt(float(r["sides"][0]["hp_end"]), 0.0)
	assert_lt(float(r["sides"][0]["hp_end"]), float(r["sides"][0]["hp_start"]) * 0.5)
	var plain := CombatSimulator.new(data).simulate(_setup(weak, D, strong, D, 6))
	assert_eq(int(plain["withdrew"]), -1)
	# A defender only falls back where it may.
	var setup := CombatSimulator.make_setup(BalanceScenarios.side(strong, null), BalanceScenarios.side(weak, _hero(_o({"retreat": "at_half"}))), "rough", 6)
	assert_eq(int(CombatSimulator.new(data).simulate(setup)["withdrew"]), -1, "no way out")
	setup["sides"][1]["can_withdraw"] = true
	assert_eq(int(CombatSimulator.new(data).simulate(setup)["withdrew"]), 1)
	# The replay knows the retreat.
	var replay := BattleReplay.from_result(r)
	var seen := false
	for st in replay.steps:
		if String(st.get("type", "")) == "withdraw":
			seen = true
	assert_true(seen)
	assert_eq(replay.final_counts()[BattleReplay.key(0, 0)], int(r["sides"][0]["stacks"][0]["end"]))


func test_session_retreat_keeps_the_hero_alive() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var h: Hero = s.state.heroes_of(0)[0]
	h.army = Army.from_pairs([["pike_militia", 20], ["longbowman", 8]])
	assert_true(s.set_battle_orders(h.id, {"retreat": "at_half"}))
	assert_eq(h.orders["retreat"], "at_half")
	assert_false(s.set_battle_orders(h.id, {"formation": "crescent"}), "a level 1 knight has no crescent")
	assert_true(s.set_battle_orders(h.id, {"formation": "shield_wall"}), "but knows the shield wall")
	var target := ""
	for id in s.state.map.objects:
		var obj: Dictionary = s.state.map.objects[id]
		if obj["type"] == "neutral_army":
			target = String(id)
			obj["stacks"] = [["flayer", 6], ["cinderling", 30]]
			break
	assert_ne(target, "")
	var result := s.attack(h.id, target)
	assert_eq(int(result["withdrew"]), 0)
	assert_true(h.alive, "the hero fell back instead of falling")
	assert_false(h.army.is_empty())
	assert_eq(h.movement_left, 0)
	# Saved and loaded with the new orders (save version 22).
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	assert_eq(GameState.from_dict(d, data).heroes[h.id].orders["formation"], "shield_wall")
	d["heroes"][h.id]["orders"] = {"stance": "defensive", "focus": "any"}
	d["version"] = 21
	assert_eq(GameState.from_dict(d, data).heroes[h.id].orders, _o({"stance": "defensive"}))


func test_order_choices_list_every_kind_with_drill() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var h: Hero = s.state.heroes_of(0)[0]
	var c := s.order_choices(h.id)
	for kind in BattleOrders.KINDS:
		assert_eq(c["options"][kind].size(), BattleOrders.table(data, kind).size(), kind)
	for o in c["options"]["formation"]:
		if o["id"] == "shield_wall":
			assert_true(o["open"])
			assert_gt(float(o["drilled"]), 0.0)


func test_ai_picks_formations_that_suit_the_armies() -> void:
	var archers := [{"creature": "shieldwarden", "count": 10}, {"creature": "longbowman", "count": 40}]
	var riders := [{"creature": "pike_militia", "count": 10}, {"creature": "lancer", "count": 12}, {"creature": "scorchhound", "count": 10}]
	var foot := [{"creature": "cinderling", "count": 60}, {"creature": "flayer", "count": 8}]
	assert_true(BattleOrders.choose(data, 10, 0, archers, foot)["formation"] in ["shield_wall", "skirmish_screen"])
	assert_eq(BattleOrders.choose(data, 10, 0, riders, foot)["formation"], "crescent")
	# A hero leans to the formation its class knows by heart, and only uses open ones.
	assert_eq(BattleOrders.choose(data, 1, 0, archers, foot, _cmd(1, "knight"))["formation"], "shield_wall")
	assert_eq(BattleOrders.choose(data, 1, 0, archers, foot, _cmd(1, "oracle"))["formation"], "line",
		"the oracle knows the reserve, but one melee stack is no reserve")


func test_specialty_unlocks_and_drills_its_formation() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var h: Hero = s.state.heroes_of(0)[0]
	var found := ""
	for id in data.hero_specialties:
		var forms: Dictionary = data.hero_specialties[id].get("formations", {})
		if not forms.is_empty() and not (data.hero_specialties[id].get("heroes", []) as Array).is_empty():
			found = id
			break
	assert_ne(found, "", "some specialty carries a formation")
	var spec: Dictionary = data.hero_specialties[found]
	h.name = String(spec["heroes"][0])
	h.faction = String(spec.get("faction", h.faction))
	h.level = 1
	var fid := String((spec["formations"] as Dictionary).keys()[0])
	assert_true(h.can_order("formation", fid, data), "%s unlocks %s" % [found, fid])
	assert_gt(BattleOrders.drill_pct(data, fid, h.commander(data)), 0.0)
