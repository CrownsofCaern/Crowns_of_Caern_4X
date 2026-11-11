extends "res://tests/test_case.gd"
## Balance goals and army-synergy mechanics. Statistical tests use fixed seeds
## and generous bounds; tools/balance_report.gd prints the same matchups.

const RUNS := 150
## Per direction in the stack-splitting tests: 2 x 100 fights per case keep the
## standard error near 0.035, well inside their 0.4-0.65 band.
const SPLIT_RUNS := 100

var bs: BalanceScenarios


func before_each() -> void:
	bs = BalanceScenarios.new(data)


## A simulator with a private copy of the combat config, for A/B tests.
func _sim_with(overrides: Dictionary) -> CombatSimulator:
	var s := CombatSimulator.new(data)
	s.cfg = data.combat.duplicate(true)
	s.cfg.merge(overrides, true)
	return s


func _rate(sim: CombatSimulator, a: Array, b: Array, runs: int = RUNS) -> float:
	var wins := 0
	for i in runs:
		var r := sim.simulate(CombatSimulator.make_setup(BalanceScenarios.side(a), BalanceScenarios.side(b), "rough", 7000 + i), false)
		if r["winner"] == 0:
			wins += 1
	return float(wins) / runs


func _log(a: Array, b: Array, seed_value: int) -> Dictionary:
	return CombatSimulator.new(data).simulate(CombatSimulator.make_setup(BalanceScenarios.side(a, null, "A"), BalanceScenarios.side(b, null, "B"), "rough", seed_value))


# --- goal: a balanced army beats an equal-gold doom stack ---------------------

func test_balanced_army_beats_every_doom_stack() -> void:
	for faction in ["concord", "ashen"]:
		var bal := bs.balanced_army(faction)
		var total := 0.0
		var n := 0
		for tier in range(1, 7):
			var c := bs.creature_at(tier, faction)
			var wr := bs.win_rate(bal, bs.doom_stack(c), "rough", RUNS)
			assert_gt(wr, 0.5, "%s balanced vs doom %s: %.2f" % [faction, c, wr])
			total += wr
			n += 1
		assert_gt(total / n, 0.7, "%s mean vs doom stacks %.2f" % [faction, total / n])


func test_ultimate_doom_stack_is_beatable() -> void:
	# Tier 7 grows one per week, so its stacks stay small; at equal gold a
	# balanced army should usually win, because its cavalry and flyers wait for
	# the line to hold the giants before they strike, but the giants must stay a
	# real threat.
	for faction in ["concord", "ashen"]:
		var c := bs.creature_at(7, faction)
		var wr := bs.win_rate(bs.balanced_army(faction), bs.doom_stack(c), "rough", RUNS)
		assert_between(wr, 0.55, 0.95, "%s balanced vs %s stack: %.2f" % [faction, c, wr])


func test_mixed_roles_beat_cheap_mass_stack() -> void:
	# The original diagnostic: pikes, archers, cavalry and a healer vs. pikes only.
	var mixed := [["pike_militia", 20], ["longbowman", 12], ["lancer", 3], ["lightbearer", 2]]
	var mass := bs.doom_stack("pike_militia", bs.army_gold(mixed))
	var wr := bs.win_rate(mixed, mass, "rough", RUNS)
	assert_gt(wr, 0.6, "mixed vs %d pikes: %.2f" % [mass[0][1], wr])


# --- goal: same-tier faction matchups are near parity -------------------------

func test_balanced_factions_near_parity_on_neutral_ground() -> void:
	var wr := bs.win_rate(bs.balanced_army("concord"), bs.balanced_army("ashen"), "rough", 300)
	assert_between(wr, 0.35, 0.65, "concord vs ashen on rough %.2f" % wr)


func test_same_tier_creatures_near_parity() -> void:
	var total := 0.0
	for tier in range(1, 8):
		var pair := bs.tier_swap(tier, "concord", "ashen")
		var wr := bs.win_rate(pair[0], pair[1], "rough", RUNS)
		assert_between(wr, 0.25, 0.75, "tier %d: %s vs %s %.2f" % [tier, bs.describe(pair[0]), bs.describe(pair[1]), wr])
		total += wr
	assert_between(total / 7.0, 0.4, 0.6, "mean same-tier win rate %.2f" % (total / 7.0))


func test_home_terrain_matters_but_away_games_are_winnable() -> void:
	var cb := bs.balanced_army("concord")
	var ab := bs.balanced_army("ashen")
	var grass := bs.win_rate(cb, ab, "grass", RUNS)
	var infernal := bs.win_rate(cb, ab, "infernal", RUNS)
	# Infernal is both Ashen home ground and hostile to the Concord, so this
	# pair shows the widest swing a terrain can make; it should stay a real
	# edge without deciding the fight (roughly 35-65).
	assert_gt(grass, infernal + 0.1, "grass %.2f vs infernal %.2f" % [grass, infernal])
	assert_between(grass, 0.45, 0.7, "concord at home %.2f" % grass)
	assert_between(infernal, 0.28, 0.55, "concord away %.2f" % infernal)


# --- goal: mass ranged loses to cavalry, but not absolutely --------------------

func test_mass_ranged_loses_to_cavalry_but_not_hopelessly() -> void:
	var pairs := [["longbowman", "scorchhound"], ["longbowman", "thornwolf"], ["brimstone_hurler", "lancer"], ["crag_slinger", "scorchhound"]]
	var total := 0.0
	var best := 0.0
	for p in pairs:
		var n := bs.matched_counts(p[0], p[1], 6000)
		var wr := bs.win_rate([[p[0], n[0]]], [[p[1], n[1]]], "rough", RUNS)
		assert_lt(wr, 0.5, "%s vs %s should favour cavalry: %.2f" % [p[0], p[1], wr])
		total += wr
		best = maxf(best, wr)
	# Cavalry rides down archers (role_matchups), so mass ranged is a long shot.
	assert_between(total / pairs.size(), 0.05, 0.45, "mean ranged-vs-cavalry win rate %.2f" % (total / pairs.size()))
	assert_gt(best, 0.15, "at least one ranged matchup should be a real fight")


# --- synergy mechanics ----------------------------------------------------------

func test_splitting_one_unit_into_stacks_is_neutral() -> void:
	# Same creatures, same gold: how they are stacked must not decide the fight.
	var cases := [
		[[["pike_militia", 18], ["pike_militia", 18], ["pike_militia", 17], ["pike_militia", 17]], [["pike_militia", 70]]],
		[[["pike_militia", 35], ["pike_militia", 35]], [["pike_militia", 70]]],
		[[["pike_militia", 10], ["pike_militia", 10], ["pike_militia", 10], ["pike_militia", 10], ["pike_militia", 10], ["pike_militia", 10], ["pike_militia", 10]], [["pike_militia", 70]]],
		[[["lancer", 5], ["lancer", 5], ["lancer", 5]], [["lancer", 15]]],
		[[["cinderling", 23], ["cinderling", 23], ["cinderling", 23], ["cinderling", 23]], [["cinderling", 92]]],
		[[["sunhawk_rider", 3], ["sunhawk_rider", 3], ["sunhawk_rider", 3]], [["sunhawk_rider", 9]]],
		[[["longbowman", 20], ["longbowman", 20], ["longbowman", 20]], [["longbowman", 60]]],
	]
	var sim := _sim_with({})
	for c in cases:
		var split := _rate(sim, c[0], c[1], SPLIT_RUNS)
		var reverse := 1.0 - _rate(sim, c[1], c[0], SPLIT_RUNS)
		var wr := (split + reverse) / 2.0   # average over who attacks
		assert_between(wr, 0.4, 0.65, "%s vs %s: split wins %.2f" % [bs.describe(c[0]), bs.describe(c[1]), wr])


func test_splitting_into_ten_stacks_is_neutral() -> void:
	# Armies hold ten slots: a unit cut into ten small stacks must not win by it.
	var tens := func(c: String, n: int) -> Array:
		var out := []
		for i in 10:
			out.append([c, n])
		return out
	var cases := [
		[tens.call("pike_militia", 7), [["pike_militia", 70]]],
		[tens.call("cinderling", 9), [["cinderling", 90]]],
		[tens.call("longbowman", 6), [["longbowman", 60]]],
		[tens.call("lancer", 2), [["lancer", 20]]],
	]
	var sim := _sim_with({})
	for c in cases:
		var split := _rate(sim, c[0], c[1], SPLIT_RUNS)
		var reverse := 1.0 - _rate(sim, c[1], c[0], SPLIT_RUNS)
		var wr := (split + reverse) / 2.0
		assert_between(wr, 0.4, 0.65, "%s vs %s: split wins %.2f" % [bs.describe(c[0]), bs.describe(c[1]), wr])


func test_frontage_spreads_a_big_stack_instead_of_wasting_it() -> void:
	# Without wrap-around, frontage would hand split armies a free win.
	var split := [["pike_militia", 18], ["pike_militia", 18], ["pike_militia", 17], ["pike_militia", 17]]
	var doom := [["pike_militia", 70]]
	var with_overflow := _rate(_sim_with({}), split, doom)
	var without := _rate(_sim_with({"frontage_overflow": false}), split, doom)
	assert_gt(without, with_overflow + 0.15, "no wrap-around %.2f vs wrap-around %.2f" % [without, with_overflow])
	var r := _log(doom, split, 3)
	assert_gt(r["stats"]["overflow"], 0, "the big stack should engage several stacks at once")


func test_lone_healer_fights_instead_of_only_healing_itself() -> void:
	var r := _log([["lightbearer", 10]], [["pike_militia", 30]], 2)
	var attacked := false
	for e in r["log"]:
		if e["actor"] == "Lightbearer" and e["type"] in ["melee", "retaliation"]:
			attacked = true
		assert_false(e["type"] == "heal" and e["actor"] == "Lightbearer" and e["target"] == "Lightbearer", "lone healer healed itself")
	assert_true(attacked)


func test_flank_attacks_on_pinned_enemies_draw_no_retaliation() -> void:
	var army := [["pike_militia", 30], ["lancer", 6]]
	var doom := [["pike_militia", 61]]
	var on := _rate(_sim_with({}), army, doom)
	var off := _rate(_sim_with({"flank_attacks_prevent_retaliation": false}), army, doom)
	assert_gt(on, off + 0.1, "hammer and anvil %.2f vs without %.2f" % [on, off])
	var flank_total := 0
	for i in 20:
		flank_total += int(_log(army, doom, 300 + i)["stats"]["flank_attacks"])
	assert_gt(flank_total, 20, "lancers should regularly hit pinned pikes from the flank")


func test_cavalry_waits_for_the_anvil_instead_of_charging_pikes() -> void:
	var r := _log([["pike_militia", 30], ["lancer", 6]], [["pike_militia", 61]], 11)
	var first_lancer := {}
	for e in r["log"]:
		if e["actor"] == "Lancer" and e["actor_side"] == 0:
			first_lancer = e
			break
	assert_eq(first_lancer.get("type", ""), "hold", "lancers should hold while their pikes close in")
	assert_eq(r["stats"]["braced"], 0, "no charge should break on braced pikes")


func test_flyers_wait_for_the_line_before_striking_a_giant() -> void:
	var army := bs.balanced_army("concord")
	var doom := bs.doom_stack("bastion_colossus")
	var on := _rate(_sim_with({}), army, doom)
	var off := _rate(_sim_with({"flyers_hold_for_the_line": false}), army, doom)
	assert_gt(on, off + 0.1, "flyers hold %.2f vs charge in alone %.2f" % [on, off])
	var r := _log([["pike_militia", 30], ["sunhawk_rider", 3]], [["bastion_colossus", 2]], 4)
	var pinned := false
	for e in r["log"]:
		if e["actor_side"] == 0 and e["actor"] == "Pike Militia" and e["type"] in ["melee", "retaliation"]:
			pinned = true
		if e["actor_side"] == 1 and e["target"] == "Pike Militia" and e["type"] == "melee":
			pinned = true
		if e["actor"] == "Sunhawk Rider" and e["type"] in ["melee", "charge"]:
			assert_true(pinned, "sunhawks struck the colossus before the pikes held it")
			break


func test_unpinned_archers_stand_and_shoot_before_the_blow() -> void:
	var r := _log([["scorchhound", 20]], [["longbowman", 30]], 5)
	var saw := false
	for i in r["log"].size():
		var e: Dictionary = r["log"][i]
		if e["type"] == "stand_and_shoot":
			saw = true
			var next: Dictionary = r["log"][i + 1]
			assert_eq(next["actor"], "Scorchhound", "the charge lands after the volley")
			break
	assert_true(saw, "archers should fire at the first hounds to close in")


func test_opening_volleys_are_simultaneous() -> void:
	# Only the opening volley (no rounds): identical archer lines must trade
	# equal losses, whichever side's volley is resolved first.
	var sim := _sim_with({"max_rounds": 0})
	var lost := [0, 0]
	for i in 100:
		var r := sim.simulate(CombatSimulator.make_setup(BalanceScenarios.side([["longbowman", 30]]), BalanceScenarios.side([["longbowman", 30]]), "rough", 40 + i), false)
		for s in 2:
			lost[s] += int(r["sides"][s]["stacks"][0]["lost"])
	assert_gt(lost[0], 0)
	assert_between(float(lost[0]) / lost[1], 0.9, 1.1, "attacker lost %d, defender lost %d" % [lost[0], lost[1]])


func test_support_stays_behind_the_line_until_an_enemy_is_pinned() -> void:
	for seed_value in 10:
		var r := _log([["pike_militia", 20], ["lightbearer", 3]], [["flayer", 6]], 900 + seed_value)
		var pinned := false
		for e in r["log"]:
			if e["actor_side"] == 0 and e["actor"] == "Pike Militia" and e["type"] in ["melee", "charge", "retaliation"]:
				pinned = true
			if e["actor_side"] == 1 and e["type"] in ["melee", "charge"]:
				pinned = true   # the enemy engaged someone, so it is pinned now
			if e["actor"] == "Lightbearer" and e["type"] == "melee":
				assert_true(pinned, "lightbearer struck before the lines met (seed %d)" % seed_value)
				break


func test_no_flat_synergy_bonuses_remain() -> void:
	for key in ["focus_fire_bonus", "surround_bonus_per_stack", "surround_bonus_cap"]:
		assert_false(data.combat.has(key), "%s was replaced by role mechanics" % key)
	assert_true(data.validate_combat_config().is_empty(), str(data.validate_combat_config()))


func test_combat_config_validation_catches_bad_values() -> void:
	var saved := data.combat
	data.combat = saved.duplicate(true)
	data.combat["frontage_hp_ratio"] = -1
	data.combat.erase("opening_volley")
	var errors := data.validate_combat_config()
	data.combat = saved
	assert_eq(errors.size(), 2, str(errors))
