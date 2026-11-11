extends "res://tests/test_case.gd"
## Towns: building tree, one build per day, dwellings, weekly growth, recruitment,
## garrisons, hiring heroes.

const TOWN := "town_greyhold"

var session: GameSession
var bank: ResourceBank


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 11)
	bank = session.current_player()["resources"]
	# These tests count garrison troops from zero: drop the starting garrison.
	for t in session.towns_of(0):
		Town.set_garrison(t, Army.new())


func _town() -> Dictionary:
	return session.town(TOWN)


func _rich() -> void:
	for res in data.resource_order:
		bank.add(res, 100000)


func _next_day() -> void:
	session.end_turn()


func test_town_starts_with_starting_buildings() -> void:
	var t := _town()
	assert_eq(int(t["owner"]), 0)
	assert_eq(t["built"], data.town_types["concord"]["starting_buildings"])
	assert_eq(Town.dwellings(t, data), ["pike_militia"])
	assert_eq(int(t["available"]["pike_militia"]), int(data.creature("pike_militia")["growth"]), "first week's pool is ready")
	var fresh := GameSession.new_game(data, "ember_ford", 11).town(TOWN)
	assert_eq(Town.garrison(fresh).total_creatures(), int(data.creature("pike_militia")["growth"]),
		"a new game's town holds a week of its tier-1 dwelling as a garrison")


func test_starting_garrison_scales_with_the_faction() -> void:
	var weeks: Dictionary = data.rules["starting_garrison_weeks"]
	for f in GameSetup.playable_factions(data):
		var s := GameSession.new_game(data, "twin_marches", 3, {"players": [
			{"type": "human", "faction": f}, {"type": "computer", "faction": f}]})
		for i in 2:
			var t: Dictionary = s.towns_of(i)[0]
			var g := Town.garrison(t)
			assert_false(g.is_empty(), "%s town %d has a garrison" % [f, i])
			for st in g.to_combat_stacks():
				var c := data.creature(st["creature"])
				assert_eq(c["faction"], f, "the town's own creatures")
				assert_true(weeks.has(str(int(c["tier"]))), "only tiers %s" % str(weeks.keys()))
				assert_eq(int(st["count"]), int(round(Town.weekly_growth(t, st["creature"], data) * float(weeks[str(int(c["tier"]))]))))
	var neutral := GameSession.new_game(data, "mournfield", 3, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "ashen"},
		{"type": "closed", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
	for t in neutral.towns_of(-1):
		assert_false(Town.garrison(t).is_empty(), "closed slots' towns keep their neutral garrison")


func test_requirements_block_construction() -> void:
	_rich()
	assert_eq(session.can_build(TOWN, "c_dw3"), "requires Palisade")
	var r := session.build(TOWN, "c_dw3")
	assert_false(r["ok"])
	assert_false(Town.has_building(_town(), "c_dw3"))
	assert_true(session.build(TOWN, "c_palisade")["ok"])
	_next_day()
	assert_eq(session.can_build(TOWN, "c_dw3"), "")


func test_one_building_per_day() -> void:
	_rich()
	assert_true(session.build(TOWN, "c_market")["ok"])
	assert_eq(session.can_build(TOWN, "c_palisade"), "already built today")
	assert_false(session.build(TOWN, "c_palisade")["ok"])
	_next_day()
	assert_true(session.build(TOWN, "c_palisade")["ok"])


func test_build_spends_exact_cost_and_fails_without_resources() -> void:
	var gold := bank.get_amount("gold")
	var wood := bank.get_amount("wood")
	assert_true(session.build(TOWN, "c_dw2")["ok"])
	assert_eq(bank.get_amount("gold"), gold - 1000)
	assert_eq(bank.get_amount("wood"), wood - 5)
	_next_day()
	bank.spend({"gold": bank.get_amount("gold")})
	assert_eq(session.can_build(TOWN, "c_market"), "not enough resources")
	var before := bank.to_dict()
	assert_false(session.build(TOWN, "c_market")["ok"])
	assert_eq(bank.to_dict(), before, "failed build changes nothing")


func test_cannot_build_twice_or_in_foreign_town() -> void:
	_rich()
	assert_eq(session.can_build(TOWN, "c_hall"), "already built")
	assert_eq(session.can_build("town_cindermaw", "a_market"), "not your town")
	assert_eq(session.can_build(TOWN, "no_such_building"), "unknown building")


func test_build_discount_reduces_timber_and_ore() -> void:
	var t := _town()
	var before := Town.build_cost(t, "c_dw4", data)
	assert_eq(before, {"gold": 3000, "wood": 10, "ore": 5})
	t["built"].append_array(["c_market", "c_yard", "c_masons"])
	var after := Town.build_cost(t, "c_dw4", data)
	assert_eq(after["gold"], 3000, "gold unaffected")
	assert_eq(after["wood"], 7)
	assert_eq(after["ore"], 4)


func test_new_dwelling_gets_a_week_of_creatures() -> void:
	assert_true(session.build(TOWN, "c_dw2")["ok"])
	assert_eq(int(_town()["available"]["longbowman"]), 9)
	assert_eq(Town.dwellings(_town(), data), ["pike_militia", "longbowman"])


func test_weekly_growth_accumulates_on_week_start() -> void:
	var start := int(_town()["available"]["pike_militia"])
	for i in 6:
		_next_day()
	assert_eq(session.state.day, 7)
	assert_eq(int(_town()["available"]["pike_militia"]), start, "no growth mid-week")
	_next_day()
	assert_eq(session.state.day_of_week(), 1)
	assert_eq(int(_town()["available"]["pike_militia"]), start + 14)


func test_growth_buildings_raise_weekly_growth() -> void:
	var t := _town()
	assert_eq(Town.weekly_growth(t, "pike_militia", data), 14)
	t["built"].append("c_drill")
	assert_eq(Town.weekly_growth(t, "pike_militia", data), 20)
	t["built"].append_array(["c_palisade", "c_keep"])
	assert_eq(Town.weekly_growth(t, "pike_militia", data), 25, "floor(20 * 1.25)")
	t["built"].append_array(["c_court", "c_bastion"])
	assert_eq(Town.weekly_growth(t, "pike_militia", data), 30)


func test_recruit_into_garrison_without_hero() -> void:
	var gold := bank.get_amount("gold")
	var r := session.recruit(TOWN, "pike_militia", 5)
	assert_true(r["ok"], r.get("reason", ""))
	assert_eq(r["to"], "garrison")
	assert_eq(bank.get_amount("gold"), gold - 5 * int(data.creature("pike_militia")["cost"]["gold"]))
	assert_eq(int(_town()["available"]["pike_militia"]), 9)
	assert_eq(Town.garrison(_town()).total_creatures(), 5)


func test_recruit_into_visiting_hero() -> void:
	var h := session.hero("hero_wren")
	session.move_hero("hero_wren", Vector2i(1, 8))
	assert_eq(session.visiting_hero(TOWN), h)
	var before := h.army.total_creatures()
	var r := session.recruit(TOWN, "pike_militia", 14)
	assert_true(r["ok"])
	assert_eq(r["to"], "hero_wren")
	assert_eq(h.army.total_creatures(), before + 14)
	assert_eq(int(_town()["available"]["pike_militia"]), 0)
	assert_false(session.recruit(TOWN, "pike_militia", 1)["ok"], "pool empty")


func test_recruit_limits() -> void:
	assert_eq(session.recruit(TOWN, "pike_militia", 15)["reason"], "only 14 available")
	assert_eq(session.recruit(TOWN, "longbowman", 1)["reason"], "no dwelling for this creature")
	assert_eq(session.recruit(TOWN, "pike_militia", 0)["reason"], "nothing to recruit")
	bank.spend({"gold": bank.get_amount("gold") - 200})
	assert_eq(session.max_recruitable(TOWN, "pike_militia"), 2)
	assert_eq(session.recruit(TOWN, "pike_militia", 3)["reason"], "not enough resources")
	assert_true(session.recruit(TOWN, "pike_militia", 2)["ok"])


func test_recruit_needs_free_slot() -> void:
	var h := session.hero("hero_wren")
	for c in ["cinderling", "scorchhound", "flayer", "hellmaw_hound", "sunhawk_rider", "lightbearer"]:
		h.army.add(c, 1)
	assert_eq(h.army.stack_count(), Army.MAX_SLOTS)
	session.move_hero("hero_wren", Vector2i(1, 8))
	assert_eq(session.recruit(TOWN, "pike_militia", 1)["ok"], true, "merges into existing militia")
	_rich()
	_town()["built"].append("c_dw7")
	_town()["available"]["bastion_colossus"] = 1
	assert_eq(session.recruit(TOWN, "bastion_colossus", 1)["reason"], "no free army slot")
	assert_true(session.recruit(TOWN, "bastion_colossus", 1, true)["ok"], "garrison has room")


func test_recruit_options_for_ui_and_ai() -> void:
	session.build(TOWN, "c_dw2")
	var opts := session.recruit_options(TOWN)
	assert_eq(opts.size(), 2)
	assert_eq(opts[0]["creature"], "pike_militia")
	assert_eq(opts[1]["available"], 9)
	assert_eq(opts[1]["max"], 9)
	var b := session.build_options(TOWN)
	assert_eq(b.size(), data.town_types["concord"]["buildings"].size())
	for o in b:
		if o["id"] == "c_dw2":
			assert_true(o["built"])
		if o["id"] == "c_palisade":
			assert_eq(o["reason"], "already built today")


func test_move_stacks_between_garrison_and_hero() -> void:
	var h := session.hero("hero_wren")
	session.recruit(TOWN, "pike_militia", 4)
	assert_eq(session.move_stack(TOWN, 0, true)["reason"], "no hero in town")
	session.move_hero("hero_wren", Vector2i(1, 8))
	var before := h.army.total_creatures()
	assert_true(session.move_stack(TOWN, 0, true)["ok"])
	assert_eq(h.army.total_creatures(), before + 4)
	assert_true(Town.garrison(_town()).is_empty())
	# Hero to garrison, but never the last stack.
	assert_true(session.move_stack(TOWN, 3, false)["ok"])
	assert_eq(Town.garrison(_town()).total_creatures(), 3)
	for s in [1, 2]:
		session.move_stack(TOWN, s, false)
	assert_eq(h.army.stack_count(), 1)
	assert_eq(session.move_stack(TOWN, 0, false)["reason"], "a hero needs at least one stack")


func test_hire_hero_from_tavern() -> void:
	assert_eq(session.can_hire_hero(TOWN), "")
	var gold := bank.get_amount("gold")
	var r := session.hire_hero(TOWN)
	assert_true(r["ok"])
	var h := session.hero(r["hero_id"])
	assert_eq(h.name, "Maud Ferrow")
	assert_eq(h.class_id, "knight")
	assert_eq(h.pos, Vector2i(1, 8))
	assert_eq(h.owner, 0)
	assert_eq(h.army.total_creatures(), 14)
	assert_eq(h.movement_left, h.max_movement(data))
	assert_eq(bank.get_amount("gold"), gold - 2500)
	assert_eq(session.state.heroes_of(0).size(), 3, "two starting heroes plus the hire")
	assert_eq(session.can_hire_hero(TOWN), "Maud Ferrow stands in the town: march out to make room for a new hero",
		"the reason names the hero and says what to do")
	session.move_hero(h.id, Vector2i(3, 9))
	assert_eq(session.hire_offer(TOWN)["name"], "Corwen Ashby", "next hero in the pool")


func test_hire_requires_tavern_and_gold() -> void:
	_town()["built"].erase("c_tavern")
	assert_eq(session.can_hire_hero(TOWN), "no tavern")
	_town()["built"].append("c_tavern")
	bank.spend({"gold": bank.get_amount("gold")})
	assert_eq(session.can_hire_hero(TOWN), "not enough gold")
	assert_false(session.hire_hero(TOWN)["ok"])


func test_daily_income_from_town() -> void:
	var gold := bank.get_amount("gold")
	assert_eq(session.daily_income(0), {"gold": 500})
	_next_day()
	assert_eq(bank.get_amount("gold"), gold + 500)


func test_income_buildings_stack() -> void:
	var t := _town()
	t["built"].append_array(["c_court", "c_market", "c_assembly", "c_yard"])
	assert_eq(Town.daily_income(t, data), {"gold": 2000, "wood": 1, "ore": 1})


func test_garrison_defends_with_walls() -> void:
	var t := session.town("town_cindermaw")
	var side := session._defender_side(session.battle_target(t["id"]))
	assert_eq(side["hero"]["defense"], 2, "Spiked Trench")
	assert_eq(side["stacks"].size(), 3)


func test_hero_with_town_is_not_defeated_without_heroes() -> void:
	var h := session.hero("hero_wren")
	h.alive = false
	session.state.heroes.erase("hero_maelis")
	VictoryRules.update(session)
	assert_false(session.current_player()["defeated"], "still owns Greyhold")


func test_economy_is_scarce() -> void:
	# The brief: you cannot build everything at once. Starting stock plus a
	# month of base income must fall far short of the full tree.
	for tt in data.town_types:
		var total := {}
		for b in data.town_types[tt]["buildings"].values():
			for res in b["cost"]:
				total[res] = int(total.get(res, 0)) + int(b["cost"][res])
		var month_gold := int(data.starting_resources["gold"]) + 28 * 500
		assert_gt(total["gold"], month_gold * 2, "%s gold" % tt)
		var materials := int(total.get("wood", 0)) + int(total.get("ore", 0))
		var start := int(data.starting_resources["wood"]) + int(data.starting_resources["ore"])
		assert_gt(materials, start * 3, "%s timber and ore" % tt)


func test_factions_need_different_resources() -> void:
	var sums := {}
	for tt in data.town_types:
		var total := {}
		for b in data.town_types[tt]["buildings"].values():
			for res in b["cost"]:
				total[res] = int(total.get(res, 0)) + int(b["cost"][res])
		sums[tt] = total
	assert_gt(sums["concord"].get("wood", 0), sums["ashen"].get("wood", 0) * 3, "humans build in timber")
	assert_gt(sums["ashen"].get("sulfur", 0), sums["concord"].get("sulfur", 0) + 15, "demons need brimstone")
	assert_gt(sums["concord"].get("gems", 0) + sums["concord"].get("crystal", 0), sums["ashen"].get("gems", 0) + sums["ashen"].get("crystal", 0))


func test_convert_captured_town_resets_buildings_and_pools() -> void:
	_rich()
	var t := session.town("town_cindermaw")
	t["owner"] = 0
	t["built"].append("a_market")
	t["available"]["old_creature"] = 42
	t["last_build_day"] = session.state.day
	var garrison: Array = t["garrison"].duplicate(true)
	var before := bank.get_amount("gold")
	assert_true(session.convert_town("town_cindermaw")["ok"])
	assert_eq(bank.get_amount("gold"), before - int(data.economy["conversion_cost"]["gold"]))
	assert_eq(t["town_type"], "concord")
	assert_eq(t["built"], data.town_types["concord"]["starting_buildings"])
	assert_eq(t["available"], {"pike_militia": Town.weekly_growth(t, "pike_militia", data)})
	assert_eq(t["garrison"], garrison)
	assert_eq(session.can_build("town_cindermaw", "c_market"), "already built today")
	assert_eq(session.can_convert_town("town_cindermaw"), "already your faction")


func test_convert_rejects_foreign_town_and_insufficient_gold() -> void:
	var t := session.town("town_cindermaw")
	assert_false(session.convert_town("town_cindermaw")["ok"])
	t["owner"] = 0
	bank.spend({"gold": bank.get_amount("gold")})
	var before := t.duplicate(true)
	assert_eq(session.can_convert_town("town_cindermaw"), "not enough resources")
	assert_false(session.convert_town("town_cindermaw")["ok"])
	assert_eq(t, before)
