extends "res://tests/test_case.gd"
## Dwelling upgrades: recruiting upgraded creatures from the shared pool and
## converting stacks in town. Uses a data variant with one upgrade pair so the
## mechanism is tested independently of the creature roster.

const TOWN := "town_greyhold"

var d: GameData
var session: GameSession
var bank: ResourceBank


func _variant() -> GameData:
	var g := GameData.new()
	g.load_all(GameData.DATA_DIR)
	var vet: Dictionary = g.creatures["pike_militia"].duplicate(true)
	vet["name"] = "Pike Veteran"
	vet["attack"] = int(vet["attack"]) + 1
	vet["cost"] = {"gold": 110, "wood": 1}
	vet["upgrade_of"] = "pike_militia"
	g.creatures["pike_veteran"] = vet
	g.creatures["pike_militia"]["upgrade"] = "pike_veteran"
	g.town_types["concord"]["buildings"]["c_dw1_up"] = {"name": "Veterans' Barracks", "category": "dwelling",
		"cost": {"gold": 1000, "ore": 5}, "requires": ["c_dw1"],
		"effects": [{"type": "dwelling_upgrade", "creature": "pike_militia"}], "description": "Upgrade."}
	return g


func before_each() -> void:
	d = _variant()
	session = GameSession.new_game(d, "ember_ford", 3)
	bank = session.current_player()["resources"]
	# These tests count garrison troops from zero: drop the starting garrison.
	for t in session.towns_of(0):
		Town.set_garrison(t, Army.new())


func _t() -> Dictionary:
	return session.town(TOWN)


func test_variant_data_is_valid() -> void:
	assert_eq(Economy.validate(d), [] as Array[String])


func test_validation_rejects_bad_upgrade_buildings() -> void:
	d.town_types["concord"]["buildings"]["c_dw1_up"]["requires"] = []
	d.town_types["concord"]["buildings"]["c_dw2"]["effects"].append({"type": "dwelling_upgrade", "creature": "thornwolf"})   # a wild creature: no upgrade
	var errors := " | ".join(Economy.validate(d))
	assert_true(errors.contains("must require the dwelling of pike_militia"), errors)
	assert_true(errors.contains("without an upgrade"), errors)


func test_upgrade_needs_building() -> void:
	assert_eq(Town.recruitable(_t(), d), ["pike_militia"])
	assert_eq(session.recruit(TOWN, "pike_veteran", 1)["reason"], "no dwelling for this creature")
	assert_true(session.build(TOWN, "c_dw1_up")["ok"])
	assert_eq(Town.recruitable(_t(), d), ["pike_militia", "pike_veteran"])


func test_upgraded_recruits_share_the_base_pool() -> void:
	session.build(TOWN, "c_dw1_up")
	var gold := bank.get_amount("gold")
	var wood := bank.get_amount("wood")
	var r := session.recruit(TOWN, "pike_veteran", 4)
	assert_true(r["ok"], r.get("reason", ""))
	assert_eq(int(_t()["available"]["pike_militia"]), 10)
	assert_eq(bank.get_amount("gold"), gold - 440)
	assert_eq(bank.get_amount("wood"), wood - 4)
	assert_eq(session.recruit(TOWN, "pike_militia", 11)["reason"], "only 10 available")
	var opts := session.recruit_options(TOWN)
	assert_eq(opts.size(), 2)
	assert_eq(opts[1]["creature"], "pike_veteran")
	assert_eq(opts[1]["available"], 10)
	assert_eq(opts[1]["growth"], 14)


func test_upgrade_garrison_stack_for_cost_difference() -> void:
	session.recruit(TOWN, "pike_militia", 6)
	assert_eq(session.can_upgrade_stack(TOWN, 0, true), "this town cannot upgrade Pike Militia")
	session.build(TOWN, "c_dw1_up")
	var gold := bank.get_amount("gold")
	var wood := bank.get_amount("wood")
	assert_eq(session.upgrade_options(TOWN).size(), 1)
	var r := session.upgrade_stack(TOWN, 0, true)
	assert_true(r["ok"], r.get("reason", ""))
	assert_eq(r["cost"], {"gold": 150, "wood": 6})
	assert_eq(bank.get_amount("gold"), gold - 150)
	assert_eq(bank.get_amount("wood"), wood - 6)
	var g := Town.garrison(_t())
	assert_eq(g.slots[0], {"creature": "pike_veteran", "count": 6, "veteran_xp": 5000})
	assert_eq(session.upgrade_options(TOWN).size(), 0, "nothing left to upgrade")


func test_upgrade_hero_stack_merges_with_existing_upgrades() -> void:
	var h := session.hero("hero_wren")
	h.army.add("pike_veteran", 2)
	session.move_hero("hero_wren", Vector2i(1, 8))
	session.build(TOWN, "c_dw1_up")
	bank.add("wood", 30)
	var slot_vet := 4
	assert_eq(h.army.slots[slot_vet]["creature"], "pike_veteran")
	var r := session.upgrade_stack(TOWN, 0, false)
	assert_true(r["ok"], r.get("reason", ""))
	assert_true(h.army.slots[0].is_empty())
	assert_eq(int(h.army.slots[slot_vet]["count"]), 26)


func test_upgrade_fails_without_resources_and_changes_nothing() -> void:
	session.recruit(TOWN, "pike_militia", 6)
	session.build(TOWN, "c_dw1_up")
	bank.spend({"wood": bank.get_amount("wood")})
	assert_eq(session.can_upgrade_stack(TOWN, 0, true), "not enough resources")
	assert_false(session.upgrade_stack(TOWN, 0, true)["ok"])
	assert_eq(Town.garrison(_t()).slots[0]["creature"], "pike_militia")
	assert_eq(session.can_upgrade_stack(TOWN, 3, true), "empty slot")
	assert_eq(session.can_upgrade_stack(TOWN, 0, false), "no hero in town")
