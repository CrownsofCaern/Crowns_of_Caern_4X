extends "res://tests/test_case.gd"
## Personal hero specialties (data/hero_specialties.json, HeroSpecialties).


func _hero(hero_name: String, cls: String, army: Array = [["pike_militia", 5]]) -> Hero:
	return Hero.create({"id": "h_spec", "name": hero_name, "class": cls, "pos": [0, 0], "army": army}, data)


func test_data_is_valid() -> void:
	var errors := HeroSpecialties.validate(data)
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_every_tavern_hero_has_its_own_specialty() -> void:
	var used := {}
	for fid in data.town_types:
		for h in data.town_types[fid].get("hire", {}).get("heroes", []):
			assert_true(data.specialty_by_hero.has(h["name"]), "%s has a named specialty" % h["name"])
			var sid := String(data.specialty_by_hero.get(h["name"], ""))
			assert_false(used.has(sid), "%s shares %s with %s" % [h["name"], sid, used.get(sid, "")])
			used[sid] = h["name"]
	assert_eq(used.size(), 40, "40 tavern heroes")


func test_factions_get_a_similar_number_of_specialties() -> void:
	for fid in data.factions:
		if bool(data.factions[fid].get("neutral", false)):
			continue
		var n := HeroSpecialties.faction_pool(fid, data).size()
		assert_between(n, 11, 15, "%s has %d specialties" % [fid, n])


func test_campaign_heroes_have_named_specialties() -> void:
	for hname in ["Aldous Wren", "Skarn Ashborn", "Ysmay Vane", "Cerrid Ashbark", "Gunnra Sootmantle", "Ulvra Kettleborn",
			"Serane Nhalvor", "Thunn Reefbreaker"]:
		assert_true(data.specialty_by_hero.has(hname), hname)


func test_unnamed_heroes_get_a_stable_faction_specialty() -> void:
	var a := HeroSpecialties.id_for("Some Hired Captain", "forge", data)
	assert_ne(a, "")
	assert_eq(String(data.hero_specialties[a]["faction"]), "forge")
	assert_eq(HeroSpecialties.id_for("Some Hired Captain", "forge", data), a, "deterministic")
	assert_eq(HeroSpecialties.checksum("abc"), HeroSpecialties.checksum("abc"))
	# Different names spread across the pool.
	var seen := {}
	for i in 30:
		seen[HeroSpecialties.id_for("Captain %d" % i, "ashen", data)] = true
	assert_gt(seen.size(), 4, "pool picks vary by name")


func test_line_specialty_grows_with_level_and_caps() -> void:
	var h := _hero("Maud Ferrow", "knight")
	assert_eq(h.specialty(data)["id"], "pike_wall")
	assert_eq(HeroModifiers.sub(h.modifiers(data), "creature_attack", "pike_militia"), 2.0)
	h.level = 4
	assert_eq(HeroModifiers.sub(h.modifiers(data), "creature_attack", "pike_militia"), 3.0)
	h.level = 7
	assert_eq(HeroModifiers.sub(h.modifiers(data), "creature_defense", "pike_militia"), 4.0)
	h.level = 40
	assert_eq(HeroModifiers.sub(h.modifiers(data), "creature_attack", "pike_militia"), 6.0, "growth stops at max")


func test_line_bonus_covers_the_upgrade_and_nothing_else() -> void:
	var h := _hero("Maud Ferrow", "knight")
	var p := h.combat_profile(data)
	var mods: Dictionary = p["mods"]
	var base := HeroBattleEffects.stat_bonus(p, mods, data.creature("pike_militia"), "pike_militia")
	var up := HeroBattleEffects.stat_bonus(p, mods, data.creature("pike_veteran"), "pike_veteran")
	var other := HeroBattleEffects.stat_bonus(p, mods, data.creature("longbowman"), "longbowman")
	assert_eq(base["attack"], other["attack"] + 2)
	assert_eq(up["defense"], other["defense"] + 2)
	assert_eq(p["specialty"], "Pike Wall")


func test_line_specialty_wins_battles_more_often() -> void:
	var sim := CombatSimulator.new(data)
	var mine := [{"slot": 0, "creature": "pike_militia", "count": 40}]
	var theirs := [{"slot": 0, "creature": "cinderling", "count": 48}]
	var with_spec := _hero("Maud Ferrow", "knight").combat_profile(data)
	var without := with_spec.duplicate(true)
	without["mods"].erase("creature_attack")
	without["mods"].erase("creature_defense")
	var hp_with := 0
	var hp_without := 0
	for i in 8:
		var r1 := sim.simulate(CombatSimulator.make_setup({"name": "A", "hero": with_spec, "stacks": mine},
			{"name": "B", "hero": null, "stacks": theirs}, "grass", 900 + i), false)
		var r2 := sim.simulate(CombatSimulator.make_setup({"name": "A", "hero": without, "stacks": mine},
			{"name": "B", "hero": null, "stacks": theirs}, "grass", 900 + i), false)
		hp_with += int(r1["sides"][0]["hp_end"])
		hp_without += int(r2["sides"][0]["hp_end"])
	assert_gt(hp_with, hp_without, "the specialty keeps more pikes alive")


func test_income_specialty_reaches_the_economy_keys() -> void:
	var h := _hero("Durgan Coalbeard", "artificer")
	var trait_ore := int(data.hero_classes["artificer"]["trait"]["mods"].get("income", {}).get("ore", 0))
	assert_eq(int(h.modifiers(data)["income"]["ore"]), trait_ore + 2)
	h.level = 9
	assert_eq(int(h.modifiers(data)["income"]["ore"]), trait_ore + 4, "+1 every 4 levels")


func test_pct_specialty_and_its_cap() -> void:
	var h := _hero("Maelis Thorne", "ranger")
	var base := HeroModifiers.num(h.modifiers(data), "ranged_damage_pct")
	assert_between(HeroModifiers.num(h.specialty(data)["mods"], "ranged_damage_pct"), 0.039, 0.041)
	h.level = 30
	assert_between(HeroModifiers.num(h.specialty(data)["mods"], "ranged_damage_pct"), 0.119, 0.121, "4% + 8 x 1%")
	assert_between(HeroModifiers.num(h.modifiers(data), "ranged_damage_pct") - base, 0.079, 0.081, "summed into the hero")


func test_formation_hooks_are_exposed() -> void:
	var spec := _hero("Castellan Odo Brack", "knight").specialty(data)
	assert_true(spec["formations"].has("shield_wall"))
	assert_true(bool(spec["formations"]["shield_wall"]["unlock"]))
	assert_eq(_hero("Odo Brack", "knight").specialty(data)["id"], spec["id"], "aliases share a specialty")
	assert_true(_hero("Maud Ferrow", "knight").specialty(data)["formations"].is_empty())


func test_ai_prefers_its_specialty_line() -> void:
	var session := GameSession.new_game(data, "ember_ford", 3)
	var ai := StrategicAI.new(session, 0)
	var h := _hero("Maud Ferrow", "knight")
	assert_between(ai.specialty_factor(h, "pike_militia"), 1.19, 1.21)
	assert_between(ai.specialty_factor(h, "pike_veteran"), 1.19, 1.21)
	assert_eq(ai.specialty_factor(h, "longbowman"), 1.0)
