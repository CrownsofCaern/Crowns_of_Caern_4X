extends "res://tests/test_case.gd"

func test_data_validates() -> void:
	var errors := data.validate()
	assert_eq(errors.size(), 0, "\n".join(errors))


const PLAYABLE := ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch"]


func test_six_factions_with_eight_tiers_and_upgrades() -> void:
	for f in PLAYABLE:
		assert_true(data.factions.has(f), f)
		var bases := {}
		var upgrades := 0
		for id in data.creatures:
			var c: Dictionary = data.creatures[id]
			if c["faction"] != f:
				continue
			if c.has("upgrade_of"):
				upgrades += 1
			else:
				assert_true(c.has("upgrade"), "%s has no upgrade" % id)
				bases[int(c["tier"])] = true
		assert_eq(bases.size(), 8, "faction %s base tiers" % f)
		assert_eq(upgrades, 8, "faction %s upgrades" % f)


func test_about_thirty_wild_creatures() -> void:
	var n := 0
	for id in data.creatures:
		if data.creatures[id]["faction"] == "wilds":
			n += 1
	assert_between(n, 28, 40, "wild creatures: %d" % n)


func test_upgrades_are_stronger_and_gain_an_ability() -> void:
	for id in data.creatures:
		var u: Dictionary = data.creatures[id]
		if not u.has("upgrade_of"):
			continue
		var b := data.creature(u["upgrade_of"])
		assert_true(u["hp"] >= b["hp"] and u["attack"] >= b["attack"] and u["defense"] >= b["defense"], "%s stats" % id)
		assert_gt(u["abilities"].size(), b["abilities"].size() - 0.5, "%s abilities" % id)
		var base_ids: Array = b["abilities"].map(func(a): return a["id"])
		var gained: Array = u["abilities"].filter(func(a): return not base_ids.has(a["id"]))
		assert_gt(gained.size(), 0, "%s gains a new ability" % id)
		assert_gt(_gold_value(u["cost"]), _gold_value(b["cost"]), "%s costs more than its base" % id)


func test_faction_identities() -> void:
	# Role constraints promised in docs/FACTIONS.md.
	var roles := {}
	for f in PLAYABLE:
		roles[f] = {}
	for id in data.creatures:
		var c: Dictionary = data.creatures[id]
		if roles.has(c["faction"]) and not c.has("upgrade_of"):
			roles[c["faction"]][c["role"]] = int(roles[c["faction"]].get(c["role"], 0)) + 1
	assert_false(roles["forge"].has("flyer"), "forge has no flyers")
	assert_false(roles["frostmarch"].has("flyer"), "frostmarch has no flyers")
	assert_false(roles["frostmarch"].has("ranged"), "frostmarch has no archers")
	assert_false(roles["thornwood"].has("cavalry"), "thornwood has no cavalry")
	assert_true(int(roles["thornwood"].get("ranged", 0)) >= 4, "thornwood is mostly ranged")


func test_economy_curves_show_in_costs() -> void:
	# Early factions are cheap at tier 1-3; late factions pay more rare resources.
	var early := _avg_low_tier_gold("frostmarch")
	var late := _avg_low_tier_gold("forge")
	assert_lt(early, late, "frostmarch %.0f vs forge %.0f" % [early, late])
	assert_lt(_rare_total("frostmarch"), _rare_total("forge"))


func _gold_value(cost: Dictionary) -> float:
	var v := 0.0
	for r in cost:
		v += float(cost[r]) * (1.0 if r == "gold" else (100.0 if r in ["wood", "ore"] else 250.0))
	return v


func _avg_low_tier_gold(f: String) -> float:
	var total := 0.0
	var n := 0
	for id in data.creatures:
		var c: Dictionary = data.creatures[id]
		if c["faction"] == f and int(c["tier"]) <= 3 and not c.has("upgrade_of"):
			total += _gold_value(c["cost"]) / float(_tier_ref(int(c["tier"])))
			n += 1
	return total / n


func _tier_ref(t: int) -> int:
	return [0, 75, 140, 230, 350, 520, 800, 1300, 2800][t]


func _rare_total(f: String) -> int:
	var n := 0
	for id in data.creatures:
		var c: Dictionary = data.creatures[id]
		if c["faction"] == f:
			for r in c["cost"]:
				if not r in ["gold", "wood", "ore"]:
					n += int(c["cost"][r])
	return n


func test_seven_resources_and_enough_terrains() -> void:
	assert_eq(data.resource_order.size(), 7)
	var passable := 0
	for t in data.terrains:
		if data.terrains[t]["passable"]:
			passable += 1
	assert_true(passable >= 7, "passable terrains: %d" % passable)


func test_three_classes_per_faction() -> void:
	var playable := data.factions.keys().filter(func(f): return not data.factions[f].get("neutral", false))
	assert_true(playable.size() >= 6, "six playable factions")
	for f in playable:
		var n := 0
		for c in data.hero_classes:
			if data.hero_classes[c]["faction"] == f:
				n += 1
		assert_eq(n, 3, f)
