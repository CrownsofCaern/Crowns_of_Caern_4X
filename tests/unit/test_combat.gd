extends "res://tests/test_case.gd"
## Combat engine tests: unit math, determinism, and statistical behaviour.

var sim: CombatSimulator


func before_each() -> void:
	sim = CombatSimulator.new(data)


func _side(stacks: Array, hero: Variant = null, name: String = "Side") -> Dictionary:
	var out := []
	for i in stacks.size():
		out.append({"slot": i, "creature": stacks[i][0], "count": stacks[i][1]})
	return {"name": name, "hero": hero, "stacks": out}


func _win_rate(a: Array, b: Array, terrain: String, runs: int, hero_a: Variant = null, hero_b: Variant = null) -> float:
	var wins := 0
	for i in runs:
		var r := sim.simulate(CombatSimulator.make_setup(_side(a, hero_a), _side(b, hero_b), terrain, 1000 + i), false)
		if r["winner"] == 0:
			wins += 1
	return float(wins) / runs


func _avg_loss_fraction(a: Array, b: Array, terrain: String, runs: int, slot: int) -> float:
	var total := 0.0
	for i in runs:
		var r := sim.simulate(CombatSimulator.make_setup(_side(a), _side(b), terrain, 5000 + i), false)
		var st: Dictionary = r["sides"][0]["stacks"][slot]
		total += float(st["lost"]) / st["start"]
	return total / runs


# --- unit-level ------------------------------------------------------------

func test_take_damage_and_heal() -> void:
	var u := CombatUnit.new()
	u.hp_per = 10
	u.start_count = 5
	u.count = 5
	u.top_hp = 10
	assert_eq(u.take_damage(25), 2)
	assert_eq(u.count, 3)
	assert_eq(u.top_hp, 5)
	assert_eq(u.total_hp(), 25)
	assert_eq(u.heal(100), 25, "heal capped at starting hp")
	assert_eq(u.count, 5)
	assert_eq(u.take_damage(1000), 5)
	assert_false(u.is_alive())
	assert_eq(u.heal(10), 0, "dead stacks cannot be healed")


# --- determinism -----------------------------------------------------------

func test_same_seed_same_result() -> void:
	var a := _side([["pike_militia", 20], ["longbowman", 10], ["lancer", 3]])
	var b := _side([["thornwolf", 15]])
	var r1 := sim.simulate(CombatSimulator.make_setup(a, b, "grass", 4242))
	var r2 := CombatSimulator.new(data).simulate(CombatSimulator.make_setup(a, b, "grass", 4242))
	assert_eq(JSON.stringify(r1), JSON.stringify(r2))


func test_different_seeds_vary() -> void:
	var a := _side([["pike_militia", 20], ["longbowman", 10]])
	var b := _side([["thornwolf", 12]])
	var outcomes := {}
	for s in 20:
		var r := sim.simulate(CombatSimulator.make_setup(a, b, "grass", s), false)
		outcomes[JSON.stringify(r["sides"])] = true
	assert_gt(outcomes.size(), 5)


func test_casualty_bookkeeping() -> void:
	var r := sim.simulate(CombatSimulator.make_setup(
		_side([["shieldwarden", 8], ["longbowman", 12]]), _side([["flayer", 4], ["brimstone_hurler", 6]]), "rough", 9))
	for side in r["sides"]:
		for st in side["stacks"]:
			assert_eq(st["lost"], st["start"] - st["end"])
			assert_true(st["end"] >= 0 and st["end"] <= st["start"])
	var loser: int = 1 - int(r["winner"])
	if r["outcome"] != "attacker_withdrew":
		assert_eq(r["sides"][loser]["hp_end"], 0)
	assert_true(r["summary"].size() > 0)


# --- statistical behaviour ------------------------------------------------

func test_mirror_match_is_roughly_even() -> void:
	var army := [["pike_militia", 20], ["longbowman", 12], ["lancer", 3]]
	var wr := _win_rate(army, army, "rough", 400)
	assert_between(wr, 0.35, 0.65, "mirror win rate %.2f" % wr)


func test_stronger_army_usually_wins() -> void:
	var wr := _win_rate([["pike_militia", 30], ["longbowman", 15]], [["pike_militia", 20], ["longbowman", 10]], "rough", 300)
	assert_gt(wr, 0.85, "1.5x army win rate %.2f" % wr)


func test_upsets_remain_possible() -> void:
	# Slightly stronger side should not win every single time.
	var wr := _win_rate([["pike_militia", 22], ["longbowman", 11]], [["pike_militia", 20], ["longbowman", 10]], "rough", 300)
	assert_between(wr, 0.5, 0.97, "small edge win rate %.2f" % wr)


func test_native_terrain_helps() -> void:
	var humans := [["pike_militia", 20], ["longbowman", 10], ["lancer", 3]]
	var demons := [["cinderling", 22], ["brimstone_hurler", 5], ["scorchhound", 7]]
	var on_grass := _win_rate(humans, demons, "grass", 300)
	var on_infernal := _win_rate(humans, demons, "infernal", 300)
	assert_gt(on_grass, on_infernal + 0.05, "grass %.2f vs infernal %.2f" % [on_grass, on_infernal])
	assert_gt(on_infernal, 0.02, "off-terrain fights stay winnable")


func test_frontline_protects_ranged() -> void:
	# Archers behind a pike wall lose a smaller share than archers alone against cavalry.
	var cav := [["thornwolf", 10]]
	var screened := _avg_loss_fraction([["longbowman", 15], ["pike_militia", 25]], cav, "rough", 200, 0)
	var exposed := _avg_loss_fraction([["longbowman", 15]], cav, "rough", 200, 0)
	assert_lt(screened, exposed - 0.1, "screened %.2f vs exposed %.2f" % [screened, exposed])


func test_mass_ranged_beats_slow_infantry_but_not_cavalry() -> void:
	var ranged := [["longbowman", 40]]
	var vs_slow := _win_rate(ranged, [["shieldwarden", 13]], "rough", 300)   # ~ equal gold
	var vs_fast := _win_rate(ranged, [["scorchhound", 31]], "rough", 300)   # ~ equal gold
	assert_gt(vs_slow, vs_fast + 0.2, "vs slow %.2f, vs fast %.2f" % [vs_slow, vs_fast])


func test_brace_blunts_charges() -> void:
	# Lancers charging a pike wall do worse than against an equal-cost unbraced wall.
	var lancers := [["lancer", 6]]
	var pikes := _win_rate(lancers, [["pike_militia", 40]], "rough", 300)
	var cinders := _win_rate(lancers, [["cinderling", 44]], "rough", 300)
	assert_lt(pikes, cinders, "vs pikes %.2f, vs cinderlings %.2f" % [pikes, cinders])


func test_hero_skills_matter() -> void:
	var army := [["pike_militia", 20], ["longbowman", 14]]
	var plain := {"name": "A", "attack": 0, "defense": 0, "power": 0, "skills": {}}
	var archer := {"name": "B", "attack": 0, "defense": 0, "power": 0, "skills": {"archery": 3}}
	var base := _win_rate(army, army, "rough", 300, plain, plain)
	var boosted := _win_rate(army, army, "rough", 300, archer, plain)
	assert_gt(boosted, base + 0.08, "archery %.2f vs %.2f" % [boosted, base])


# --- prediction -------------------------------------------------------------

func test_prediction_is_reasonable_and_deterministic() -> void:
	var setup := CombatSimulator.make_setup(_side([["pike_militia", 30], ["longbowman", 15]]), _side([["thornwolf", 8]]), "grass", 0)
	var pred := CombatPredictor.new(data).predict(setup, 150)
	assert_gt(pred["win_probability"], 0.9)
	assert_true(pred["label"] in ["Overwhelming advantage", "Strong advantage"])
	assert_true(pred["loss_fraction_low"] <= pred["expected_loss_fraction"] + 1e-6)
	assert_true(pred["expected_loss_fraction"] <= pred["loss_fraction_high"] + 1e-6)
	var again := CombatPredictor.new(data).predict(setup, 150)
	assert_eq(again["win_probability"], pred["win_probability"])


func test_prediction_labels() -> void:
	assert_eq(CombatPredictor.label_for(0.99), "Overwhelming advantage")
	assert_eq(CombatPredictor.label_for(0.5), "Even")
	assert_eq(CombatPredictor.label_for(0.05), "Severe disadvantage")
