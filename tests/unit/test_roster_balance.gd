extends "res://tests/test_case.gd"
## Faction parity for the full roster (docs/FACTIONS.md): equal-value armies of
## every playable faction fight each other on neutral desert. No faction may
## dominate or be helpless on average. Mirrors tools/roster_report.gd.

const PLAYABLE := ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch", "darkelf", "fishmen"]
const RESOURCE_VALUE := {"gold": 1, "wood": 100, "ore": 100, "mercury": 250, "sulfur": 250, "crystal": 250, "gems": 250}
const RUNS := 30

var sim: CombatSimulator


func before_each() -> void:
	sim = CombatSimulator.new(data)


func _value(id: String) -> float:
	var v := 0.0
	var cost: Dictionary = data.creature(id)["cost"]
	for r in cost:
		v += float(cost[r]) * float(RESOURCE_VALUE[r])
	return v


func _army(fid: String, max_tier: int, budget: float) -> Dictionary:
	var picks := []
	for t in range(1, max_tier + 1):
		var ids: Array = data.creatures.keys()
		ids.sort()
		for id in ids:
			var c: Dictionary = data.creatures[id]
			if c["faction"] == fid and int(c["tier"]) == t and not c.has("upgrade_of"):
				picks.append(id)
	while picks.size() > 7:
		picks.pop_front()
	var stacks := []
	for i in picks.size():
		stacks.append({"slot": i, "creature": picks[i], "count": maxi(1, roundi(budget / picks.size() / _value(picks[i])))})
	return {"name": fid, "hero": null, "stacks": stacks}


func _faction_averages(max_tier: int, budget: float) -> Dictionary:
	var wins := {}
	for f in PLAYABLE:
		wins[f] = 0.0
	for i in PLAYABLE.size():
		for j in range(i + 1, PLAYABLE.size()):
			var a: Dictionary = _army(PLAYABLE[i], max_tier, budget)
			var b: Dictionary = _army(PLAYABLE[j], max_tier, budget)
			var w := 0.0
			for k in RUNS:
				if k % 2 == 0:
					w += 1.0 if sim.simulate(CombatSimulator.make_setup(a, b, "desert", 4400 + k), false)["winner"] == 0 else 0.0
				else:
					w += 1.0 if sim.simulate(CombatSimulator.make_setup(b, a, "desert", 4400 + k), false)["winner"] == 1 else 0.0
			wins[PLAYABLE[i]] += w / RUNS
			wins[PLAYABLE[j]] += 1.0 - w / RUNS
	for f in PLAYABLE:
		wins[f] /= PLAYABLE.size() - 1
	return wins


func test_early_game_faction_parity() -> void:
	var avg := _faction_averages(4, 12000)
	for f in PLAYABLE:
		assert_between(avg[f], 0.25, 0.75, "%s early-game average win rate %.2f" % [f, avg[f]])


func test_mid_game_faction_parity() -> void:
	# Tiers 1-6 without the top tiers, which could otherwise hide weak low tiers.
	# Small armies hinge on rounding (one stack of 1 vs 2 creatures), so the
	# check averages five nearby budgets instead of trusting one.
	var budgets := [8000.0, 9000.0, 10000.0, 11000.0, 12000.0]
	var avg := {}
	for f in PLAYABLE:
		avg[f] = 0.0
	for budget in budgets:
		var one := _faction_averages(6, budget)
		for f in PLAYABLE:
			avg[f] += one[f] / budgets.size()
	for f in PLAYABLE:
		assert_between(avg[f], 0.35, 0.65, "%s mid-game average win rate %.2f" % [f, avg[f]])


func test_late_game_faction_parity() -> void:
	var avg := _faction_averages(8, 90000)
	for f in PLAYABLE:
		assert_between(avg[f], 0.25, 0.75, "%s late-game average win rate %.2f" % [f, avg[f]])


func test_upgrades_are_worth_buying_but_not_mandatory() -> void:
	# An upgraded stack vs its base at equal value, across the roster: on
	# average upgrades are fairly priced (neither always better nor a trap).
	var total := 0.0
	var n := 0
	var ids: Array = data.creatures.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = data.creatures[id]
		if not c.has("upgrade_of"):
			continue
		var b: String = c["upgrade_of"]
		var budget := maxf(3000.0, 3.0 * _value(id))
		var a := {"name": "u", "hero": null, "stacks": [{"slot": 0, "creature": id, "count": maxi(1, roundi(budget / _value(id)))}]}
		var d := {"name": "b", "hero": null, "stacks": [{"slot": 0, "creature": b, "count": maxi(1, roundi(budget / _value(b)))}]}
		for k in 6:
			var r := sim.simulate(CombatSimulator.make_setup(a if k % 2 == 0 else d, d if k % 2 == 0 else a, "desert", 5100 + k), false)
			total += 1.0 if (r["winner"] == 0) == (k % 2 == 0) else 0.0
			n += 1
	assert_between(total / n, 0.3, 0.75, "average upgrade-vs-base win rate %.2f" % (total / n))
