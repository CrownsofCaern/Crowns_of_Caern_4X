extends "res://tests/test_case.gd"
## Mines, income, trading, sieges, battle spoils, save/load of the economy.

var session: GameSession
var bank: ResourceBank
var hero: Hero


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 5)
	bank = session.current_player()["resources"]
	hero = session.hero("hero_wren")
	# These tests count garrison troops from zero: drop the starting garrison.
	for t in session.towns_of(0):
		Town.set_garrison(t, Army.new())


func _make_strong() -> void:
	hero.army = Army.from_pairs([["shieldwarden", 60], ["longbowman", 80], ["lancer", 30], ["sunhawk_rider", 12]])


func test_building_data_is_valid() -> void:
	assert_eq(Economy.validate(data), [] as Array[String])
	for tt in data.town_types:
		assert_true(data.town_types[tt]["buildings"].size() >= 15, tt)


func test_validation_catches_bad_buildings() -> void:
	var d := GameData.new()
	d.load_all(GameData.DATA_DIR)
	d.town_types["concord"]["buildings"]["c_dw2"]["requires"] = ["c_fletchers"]
	d.town_types["concord"]["buildings"]["c_market"]["effects"] = [{"type": "magic_carpet"}]
	d.town_types["ashen"]["buildings"]["a_dw1"]["effects"] = [{"type": "dwelling", "creature": "pike_militia"}]
	var errors := " | ".join(Economy.validate(d))
	assert_true(errors.contains("cyclic"), errors)
	assert_true(errors.contains("magic_carpet"), errors)
	assert_true(errors.contains("foreign creature"), errors)
	assert_true(errors.contains("no dwelling for tier 1"), errors)


func test_capture_unguarded_mine_and_collect_income() -> void:
	var r := session.move_hero("hero_wren", Vector2i(3, 4))
	assert_eq(hero.pos, Vector2i(3, 4))
	assert_eq(r["captured"], ["mine_wood"])
	assert_eq(int(session.state.map.objects["mine_wood"]["owner"]), 0)
	assert_eq(session.mines_of(0).size(), 1)
	assert_eq(session.daily_income(0), {"gold": 500, "wood": 2})
	var wood := bank.get_amount("wood")
	session.end_turn()
	assert_eq(bank.get_amount("wood"), wood + 2)


func test_guarded_mine_requires_battle() -> void:
	var mine: Dictionary = session.state.map.objects["mine_mercury"]
	var plan := session.plan_path("hero_wren", Vector2i(6, 16))
	assert_eq(plan["path"][-1], Vector2i(6, 16))
	hero.pos = Vector2i(6, 14)
	var r := session.move_hero("hero_wren", Vector2i(6, 16))
	assert_eq(r["battle"], "mine_mercury", "stops at the guards")
	assert_eq(hero.pos, Vector2i(6, 15))
	assert_eq(int(mine["owner"]), -1)
	_make_strong()
	var res := session.attack("hero_wren", "mine_mercury")
	assert_eq(res["winner"], 0)
	assert_eq(int(mine["owner"]), 0, "captured after the fight")
	assert_false(mine.has("guard"))
	assert_eq(hero.pos, Vector2i(6, 16))
	assert_true(session.state.map.objects.has("mine_mercury"), "mines stay on the map")


func test_guarded_objects_block_paths_through_them() -> void:
	hero.pos = Vector2i(5, 16)
	# Walking past the guarded mercury seep must route around it.
	var plan := session.plan_path("hero_wren", Vector2i(7, 16))
	assert_false(plan["path"].has(Vector2i(6, 16)))
	session.state.map.objects["mine_mercury"].erase("guard")
	plan = session.plan_path("hero_wren", Vector2i(7, 16))
	assert_eq(plan["path"].size(), 2, "unguarded mine is walkable")


func test_owner_changes_when_mine_is_retaken() -> void:
	var mine: Dictionary = session.state.map.objects["mine_ore"]
	mine["owner"] = 1
	assert_false(session.is_guarded(mine, 0), "an empty mine is free to take")
	session.move_hero("hero_wren", Vector2i(6, 11))
	assert_eq(int(mine["owner"]), 0)


func test_siege_neutral_town() -> void:
	var t := session.town("town_cindermaw")
	assert_true(session.is_guarded(t, 0))
	hero.pos = Vector2i(21, 3)
	var r := session.move_hero("hero_wren", Vector2i(22, 2))
	assert_eq(r["battle"], "town_cindermaw")
	var setup := session.battle_setup("hero_wren", "town_cindermaw")
	assert_eq(setup["sides"][1]["hero"]["defense"], 2, "walls help the garrison")
	_make_strong()
	var res := session.attack("hero_wren", "town_cindermaw")
	assert_eq(res["winner"], 0)
	assert_eq(int(t["owner"]), 0)
	assert_true(Town.garrison(t).is_empty())
	assert_eq(hero.pos, Vector2i(22, 2))
	assert_eq(session.towns_of(0).size(), 2)
	# The captured demon town now pays its new owner and recruits demons.
	assert_eq(session.daily_income(0)["gold"], 1000)
	# Holding every town of a single-player map wins it; play on for the recruit check.
	assert_eq(session.state.end_reason, "domination")
	session.state.game_over = false
	assert_eq(session.recruit("town_cindermaw", "scorchhound", 2)["to"], "hero_wren")


func test_failed_siege_weakens_garrison() -> void:
	var t := session.town("town_cindermaw")
	hero.army = Army.from_pairs([["pike_militia", 5]])
	hero.pos = Vector2i(21, 3)
	var before := Town.garrison(t).total_creatures()
	var res := session.attack("hero_wren", "town_cindermaw")
	assert_eq(res["winner"], 1)
	assert_eq(int(t["owner"]), -1)
	assert_true(Town.garrison(t).total_creatures() <= before)
	assert_false(Town.garrison(t).is_empty())


func test_battle_spoils_from_trophy_pit() -> void:
	var t := session.town("town_cindermaw")
	t["owner"] = 0
	t["built"].append("a_spoils")
	assert_eq(Economy.battle_spoils_rate(session.state.map, 0, data), 1.0)
	_make_strong()
	session.move_hero("hero_wren", Vector2i(12, 8))
	var gold := bank.get_amount("gold")
	var res := session.attack("hero_wren", "neutral_wolves")
	assert_eq(res["winner"], 0)
	assert_gt(res["xp_gained"], 0)
	assert_eq(res["gold_gained"], res["xp_gained"])
	assert_eq(bank.get_amount("gold"), gold + res["gold_gained"])


func test_no_spoils_without_trophy_pit() -> void:
	_make_strong()
	session.move_hero("hero_wren", Vector2i(12, 8))
	var res := session.attack("hero_wren", "neutral_wolves")
	assert_eq(res["gold_gained"], 0)


func test_trade_requires_market() -> void:
	assert_eq(session.trade("wood", "gold", 5)["reason"], "you own no market")
	session.build("town_greyhold", "c_market")
	var wood := bank.get_amount("wood")
	var gold := bank.get_amount("gold")
	var r := session.trade("wood", "gold", 5)
	assert_true(r["ok"])
	assert_eq(r["received"], 500, "5 timber x 250 x 0.4")
	assert_eq(bank.get_amount("wood"), wood - 5)
	assert_eq(bank.get_amount("gold"), gold + 500)


func test_trade_rates() -> void:
	assert_eq(Economy.market_rate(0, data), 0.0)
	assert_eq(Economy.trade_quote("gold", "wood", 625, 1, data), 1)
	assert_eq(Economy.trade_quote("gold", "wood", 624, 1, data), 0)
	assert_eq(Economy.trade_quote("wood", "crystal", 25, 1, data), 2)
	# More markets, better rates, capped.
	assert_gt(Economy.trade_quote("ore", "gold", 10, 3, data), Economy.trade_quote("ore", "gold", 10, 1, data))
	assert_eq(Economy.market_rate(50, data), 0.7)
	# A round trip always loses value.
	var gold := Economy.trade_quote("crystal", "gold", 10, 5, data)
	assert_lt(Economy.trade_quote("gold", "crystal", gold, 5, data), 10)
	assert_eq(Economy.trade_price("gold", "wood", 1, 1, data), 625)


func test_trade_rejects_bad_input() -> void:
	session.build("town_greyhold", "c_market")
	assert_false(session.trade("wood", "wood", 5)["ok"])
	assert_false(session.trade("wood", "gold", 0)["ok"])
	assert_false(session.trade("wood", "gold", 999)["ok"])
	assert_eq(session.trade("gold", "gems", 100)["reason"], "offer too small")


func test_save_load_keeps_towns_and_mines() -> void:
	session.build("town_greyhold", "c_dw2")
	session.recruit("town_greyhold", "pike_militia", 3)
	session.move_hero("hero_wren", Vector2i(3, 4))
	session.end_turn()
	var path := "user://test_econ_save.json"
	assert_eq(session.save_to_file(path), OK)
	var loaded := GameSession.load_from_file(data, path)
	assert_true(loaded != null)
	assert_eq(JSON.stringify(loaded.state.to_dict()), JSON.stringify(session.state.to_dict()))
	var t := loaded.town("town_greyhold")
	assert_true(Town.has_building(t, "c_dw2"))
	assert_eq(Town.garrison(t).total_creatures(), 3)
	assert_eq(int(loaded.state.map.objects["mine_wood"]["owner"]), 0)
	# Both continue identically through a week of income and growth.
	for i in 7:
		session.end_turn()
		loaded.end_turn()
	assert_eq(JSON.stringify(loaded.state.to_dict()), JSON.stringify(session.state.to_dict()))


func test_version_1_save_gains_towns_and_mines() -> void:
	var d := session.state.to_dict()
	d["version"] = 1
	for id in d["objects"].keys():
		if d["objects"][id]["type"] in ["town", "mine"]:
			d["objects"].erase(id)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	assert_eq(GameState.validate_save(parsed), [] as Array[String])
	var s := GameSession.from_state(data, GameState.from_dict(parsed, data))
	assert_eq(s.towns_of(0).size(), 1)
	assert_true(s.state.map.objects.has("mine_gold"))
	assert_eq(s.state.to_dict()["version"], GameState.SAVE_VERSION)


func test_economy_is_deterministic() -> void:
	var a := GameSession.new_game(data, "ember_ford", 99)
	var b := GameSession.new_game(data, "ember_ford", 99)
	for s in [a, b]:
		s.build("town_greyhold", "c_dw2")
		s.recruit("town_greyhold", "longbowman", 9)
		s.move_hero("hero_wren", Vector2i(3, 4))
		for i in 8:
			s.end_turn()
	assert_eq(JSON.stringify(a.state.to_dict()), JSON.stringify(b.state.to_dict()))


func test_every_town_hires_its_own_faction() -> void:
	for tt in data.town_types:
		var pool: Array = data.town_types[tt]["hire"]["heroes"]
		assert_true(pool.size() >= 3, "%s tavern offers heroes" % tt)
		var classes := {}
		for h in pool:
			assert_eq(data.hero_classes[h["class"]]["faction"], tt, h["name"])
			classes[h["class"]] = true
		assert_eq(classes.size(), 3, "%s offers all three classes" % tt)


func test_validation_rejects_foreign_hire_class() -> void:
	var d := GameData.new()
	d.load_all(GameData.DATA_DIR)
	d.town_types["forge"]["hire"]["heroes"][0]["class"] = "knight"
	assert_true(" | ".join(Economy.validate(d)).contains("another faction's class knight"))
