extends "res://tests/test_case.gd"
## Faction ultimate buildings (army_upgrade): one per faction, expensive and
## late, upgrading every creature of the faction in the owner's armies.

const TOWN := "town_greyhold"
const FACTIONS := ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch"]


func _session(rules: Dictionary = {}) -> GameSession:
	var s := GameSession.new_game(data, "ember_ford", 11, {}, rules)
	for res in data.resource_order:
		s.current_player()["resources"].add(res, 1000000)
	return s


func _ultimate_id(faction: String) -> String:
	for b in data.town_types[faction]["buildings"]:
		for e in data.town_types[faction]["buildings"][b]["effects"]:
			if e["type"] == "army_upgrade":
				return b
	return ""


func test_every_faction_has_one_late_expensive_ultimate() -> void:
	for f in FACTIONS:
		var id := _ultimate_id(f)
		assert_ne(id, "", f)
		var b: Dictionary = data.town_types[f]["buildings"][id]
		assert_eq(b["category"], "ultimate", f)
		assert_true(int(b["cost"]["gold"]) >= 25000, "%s ultimate is very expensive" % f)
		var dw8 := ""
		for other in data.town_types[f]["buildings"]:
			for e in data.town_types[f]["buildings"][other]["effects"]:
				if e["type"] == "dwelling" and int(data.creature(e["creature"])["tier"]) == 8:
					dw8 = other
		assert_true((b["requires"] as Array).has(dw8), "%s ultimate needs the tier 8 dwelling" % f)
		var bs := BalanceScenarios.new(data)
		assert_false(bs.ultimate_of(f).is_empty(), f)


func test_validation_catches_bad_army_upgrades() -> void:
	var d := GameData.new()
	d.load_all(GameData.DATA_DIR)
	var b: Dictionary = d.town_types["concord"]["buildings"]["c_ultimate"]
	b["effects"] = [{"type": "army_upgrade", "name": "Broken", "luck": 2, "abilities": [{"id": "flight_of_fancy"}]}]
	d.town_types["concord"]["buildings"]["c_exchequer"]["effects"].append({"type": "army_upgrade", "name": ""})
	var errors := " | ".join(Economy.validate(d))
	assert_true(errors.contains("unknown field luck"), errors)
	assert_true(errors.contains("unknown ability flight_of_fancy"), errors)
	assert_true(errors.contains("needs a name"), errors)
	assert_true(errors.contains("at most one per faction"), errors)
	assert_true(errors.contains("ultimate category"), errors)
	assert_true(errors.contains("does nothing"), errors)


func test_building_it_upgrades_the_owners_faction_creatures_in_battle() -> void:
	var s := _session()
	var t := s.town(TOWN)
	assert_ne(s.can_build(TOWN, "c_ultimate"), "", "needs its requirements first")
	for b in ["c_dw8", "c_exchequer"] + Town.missing_requirements(t, "c_dw8", data) + Town.missing_requirements(t, "c_exchequer", data):
		if not Town.has_building(t, b):
			t["built"].append(b)
	# Close the requirement chains (dwellings need their own prerequisites).
	var changed := true
	while changed:
		changed = false
		for b in Town.missing_requirements(t, "c_dw8", data) + Town.missing_requirements(t, "c_exchequer", data):
			t["built"].append(b)
			changed = true
	assert_eq(s.army_upgrades(0), {})
	assert_eq(s.can_build(TOWN, "c_ultimate"), "")
	assert_true(s.build(TOWN, "c_ultimate")["ok"])
	assert_eq(s.army_upgrades(0).keys(), ["concord"])
	assert_eq(s.army_upgrades(1), {}, "only the owner")

	var a := BalanceScenarios.side([["pike_militia", 20], ["thornwolf", 4]])
	a["upgrades"] = s.army_upgrades(0)
	var plain := BalanceScenarios.side([["pike_militia", 20], ["thornwolf", 4]])
	var foe := BalanceScenarios.side([["shambler", 30]])
	var sim := CombatSimulator.new(data)
	var r := sim.simulate(CombatSimulator.make_setup(a, foe, "desert", 4), true)
	var stacks: Array = r["sides"][0]["stacks"]
	assert_eq(stacks[0]["ultimate"], "Holy Weapons", "a Concord stack fights upgraded")
	assert_eq(stacks[1]["ultimate"], "", "a wild creature in the same army does not")
	assert_true(" ".join(r["sides"][0]["notes"]).contains("Holy Weapons"), "the battle report names it")
	var r0 := sim.simulate(CombatSimulator.make_setup(plain, foe, "desert", 4), true)
	assert_eq(r0["sides"][0]["stacks"][0]["ultimate"], "")


func test_upgrade_changes_unit_stats_and_merges_abilities() -> void:
	var u := CombatUnit.new()
	u.attack = 5
	u.defense = 5
	u.hp_per = 100
	u.top_hp = 100
	u.abilities = {"poison": {"id": "poison", "fraction": 0.3}}
	ArmyUpgrade.apply(u, {"name": "Test", "attack": 2, "defense": 1, "initiative": 1, "hp_pct": 0.1,
		"damage_pct": 0.1, "ranged_damage_pct": 0.2, "shot_resist_pct": 0.2,
		"abilities": [{"id": "poison", "fraction": 0.15}, {"id": "armor_pierce", "fraction": 0.2}, {"id": "unwavering"}]}, data)
	assert_eq(u.attack, 7)
	assert_eq(u.defense, 6)
	assert_eq(u.initiative, 1)
	assert_eq(u.hp_per, 110)
	assert_eq(u.top_hp, 110)
	assert_between(u.melee_mult, 1.099, 1.101)
	assert_between(u.shot_mult, 1.319, 1.321)
	assert_between(u.shot_taken_mult, 0.799, 0.801)
	assert_between(float(u.param("poison", "fraction", 0)), 0.299, 0.301, "a stronger own copy wins")
	assert_between(float(u.param("armor_pierce", "fraction", 0)), 0.199, 0.201)
	assert_true(u.has("unwavering"))
	assert_eq(u.ultimate, "Test")
	assert_ne(ArmyUpgrade.describe({"name": "x", "attack": 2, "abilities": [{"id": "armor_pierce", "fraction": 0.2}]}, data), "")


func test_each_ultimate_wins_most_equal_gold_fights_but_not_all() -> void:
	# Late-game armies of the same faction and gold, with and without the
	# faction's ultimate, on neutral ground in both attack directions. Target:
	# clearly stronger (about +15% army worth), never a sure win.
	var bs := BalanceScenarios.new(data)
	for f in FACTIONS:
		var edge := bs.ultimate_edge(f, 40000, 30)
		assert_between(edge, 0.6, 0.93, "%s ultimate edge %.2f" % [f, edge])
		var vs_richer := bs.ultimate_edge(f, 40000, 30, 52000)
		assert_lt(vs_richer, edge, "%s: a 30%% richer plain army narrows it" % f)
		assert_lt(vs_richer, 0.5, "%s: the upgrade is worth less than 30%% more troops (%.2f)" % [f, vs_richer])


func test_campaign_tier_cap_keeps_it_for_tier_8_chapters() -> void:
	var s := _session({"max_tier": 7})
	assert_eq(s.can_build(TOWN, "c_ultimate"), "unlocks in a later chapter")
	var t := s.town(TOWN)
	t["built"].append("c_ultimate")
	assert_eq(s.army_upgrades(0), {}, "a prebuilt ultimate idles below tier 8")
	var open := _session({"max_tier": 8})
	assert_ne(open.can_build(TOWN, "c_ultimate"), "unlocks in a later chapter")


func test_battle_setup_carries_both_sides_upgrades() -> void:
	var s := _session()
	s.town(TOWN)["built"].append("c_ultimate")
	var hero := s.hero("hero_wren")
	var targets := []
	for id in s.state.map.objects:
		if s.state.map.objects[id]["type"] in ["monster", "mine"]:
			targets.append(id)
	targets.sort()
	var setup := s.battle_setup(hero.id, targets[0])
	assert_eq(setup["sides"][0]["upgrades"].keys(), ["concord"])
	assert_eq(setup["sides"][1].get("upgrades", {}), {}, "neutrals have none")


func test_ai_values_the_ultimate_once_it_fields_the_faction() -> void:
	var s := _session()
	var ai := StrategicAI.new(s, 0)
	var t := s.town(TOWN)
	assert_gt(ai.building_value(t, "c_ultimate"), 1000.0)
	t["built"].append("c_ultimate")
	assert_eq(ai.army_upgrade_value(t), 0.0, "a second copy is worth nothing")


func test_upgraded_stacks_wear_their_factions_shader() -> void:
	for f in FACTIONS:
		var m := UltimateCreatureArt.material_for(f)
		assert_true(m != null and m.shader != null, f)
		assert_eq(int(m.get_shader_parameter("style")), int(UltimateCreatureArt.STYLES[f]), f)
	assert_true(UltimateCreatureArt.material_for("wilds") == null)
	var fig := BattleFigure.new()
	fig.setup("pike_militia", 10, 1.0, 0.0, true)
	assert_true(fig.sprite.material == UltimateCreatureArt.material_for("concord"), "upgraded stack glows")
	fig.set_count(0)
	assert_true(fig.sprite.material == null, "fallen figures drop the glow")
	fig.free()
	var plain := BattleFigure.new()
	plain.setup("pike_militia", 10, 1.0, 0.0)
	assert_true(plain.sprite.material == null)
	plain.free()
	var s := _session()
	assert_eq(UltimateCreatureArt.faction_if_upgraded(s, 0, "pike_militia"), "")
	s.town(TOWN)["built"].append("c_ultimate")
	assert_eq(UltimateCreatureArt.faction_if_upgraded(s, 0, "pike_militia"), "concord")
	assert_eq(UltimateCreatureArt.faction_if_upgraded(s, 0, "thornwolf"), "")
	var slot := ArmySlot.new().setup(0, "pike_militia", 5, "")
	slot.with_ultimate("concord")
	assert_eq(slot.get_child_count(), 2, "sprite and count layers")
	slot.free()


func test_replay_keeps_the_ultimate_flag() -> void:
	var a := BalanceScenarios.side([["pike_militia", 20]])
	a["upgrades"] = {"concord": BalanceScenarios.new(data).ultimate_of("concord")}
	var r := CombatSimulator.new(data).simulate(CombatSimulator.make_setup(a, BalanceScenarios.side([["shambler", 20]]), "desert", 2), true)
	var rep := BattleReplay.from_result(r)
	assert_eq(rep.stacks[0][0]["ultimate"], "Holy Weapons")
	assert_eq(rep.stacks[1][0]["ultimate"], "")


func test_ai_builds_the_ultimate_when_it_is_open() -> void:
	var s := _session()
	var t := s.town(TOWN)
	for b in data.town_types["concord"]["buildings"]:
		if b != "c_ultimate" and not Town.has_building(t, b):
			t["built"].append(b)
	t["last_build_day"] = 0
	var ai := StrategicAI.new(s, 0)
	assert_true(ai._build_best(t), "something is built")
	assert_true(Town.has_building(t, "c_ultimate"), "the AI raises the ultimate once it is the open choice")
