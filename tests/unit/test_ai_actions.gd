extends "res://tests/test_case.gd"
## Strategic AI use of the newer player commands: hero spells, stack upgrades,
## road traders and resource gifts to allies.

const TOWN := "town_greyhold"


func _ember(seed_value: int = 5) -> GameSession:
	return GameSession.new_game(data, "ember_ford", seed_value)


## The first artifact (by id) whose slot the hero has free.
func _free_slot_artifact(h: Hero) -> String:
	var ids := data.artifacts.keys()
	ids.sort()
	for aid in ids:
		if String(h.equipment.get(data.artifacts[aid]["slot"], "")) == "":
			return aid
	return ""


## A road trader on a free tile next to the hero, with the given stock; the hero walks onto it.
func _trader_with(s: GameSession, h: Hero, stock: Array) -> String:
	var p := s._free_tile_near(h.pos)
	var obj := {"id": "test_trader", "type": "site", "site": MapTraders.SITE_ID, "pos": [p.x, p.y], "stock": stock}
	s.state.map.add_object(obj)
	MapSites.normalize(obj, data)
	s.state.player(h.owner)["fog"].reveal(p, 1)
	h.movement_left = 1000
	assert_eq(s.move_hero(h.id, p)["site"], "test_trader")
	return "test_trader"


# ----------------------------------------------------------------- spells --

func test_battle_plan_tries_the_spell_without_casting_it() -> void:
	var s := _ember()
	var h := s.hero("hero_wren")
	h.spells.append("warfire")
	h.mana = h.max_mana(data)
	h.army = Army.from_pairs([["shieldwarden", 60], ["longbowman", 80]])
	h.pos = Vector2i(6, 15)
	var eager := StrategicAI.new(s, 0, {"mana_value": -1000})
	var plan := eager.battle_plan(h, "mine_mercury")
	assert_eq(plan["spell"], "warfire", "the strongest battle spell")
	assert_eq(h.battle_spell_damage, 0.0, "only tried on the forecast")
	assert_eq(h.mana, h.max_mana(data), "no mana spent by planning")
	# A sure win does not need a spell when mana is dear.
	var thrifty := StrategicAI.new(s, 0, {"mana_value": 1000000})
	assert_eq(thrifty.battle_plan(h, "mine_mercury")["spell"], "")
	var off := StrategicAI.new(s, 0, {"casts_spells": false, "mana_value": -1000})
	assert_eq(off.battle_plan(h, "mine_mercury")["spell"], "")


func test_ai_casts_the_planned_spell_before_attacking() -> void:
	var s := _ember()
	var h := s.hero("hero_wren")
	h.spells.append("warfire")
	h.mana = h.max_mana(data)
	h.army = Army.from_pairs([["shieldwarden", 60], ["longbowman", 80]])
	h.pos = Vector2i(6, 15)
	h.movement_left = h.max_movement(data)
	var ai := StrategicAI.new(s, 0, {"mana_value": -1000})
	var report := ai._new_report()
	ai._report = report
	var obj: Dictionary = s.state.map.objects["mine_mercury"]
	var r := s.move_hero(h.id, AdventureMap.object_pos(obj))
	assert_eq(r["battle"], "mine_mercury")
	var plan := ai.battle_plan(h, r["battle"])
	assert_true(ai._cast(h, plan["spell"]))
	assert_true(h.battle_spell_damage >= 0.2)
	assert_eq(int(report["spells"]), 1)
	s.attack(h.id, "mine_mercury")
	assert_eq(h.battle_spell_damage, 0.0, "used up in the battle")


func test_standing_spell_only_when_mana_would_overflow() -> void:
	var s := _ember()
	var h := s.hero("hero_wren")
	h.spells.append("keen_edge")
	var ai := StrategicAI.new(s, 0)
	h.mana = h.max_mana(data) - 5
	ai._standing_spell(h)
	assert_eq(h.battle_spell_damage, 0.0, "mana kept while it still grows")
	h.mana = h.max_mana(data)
	ai._standing_spell(h)
	assert_true(h.battle_spell_damage > 0.0, "full mana goes into a standing battle spell")
	var mana := h.mana
	ai._standing_spell(h)
	assert_eq(h.mana, mana, "never stacks a second one")


func test_movement_spell_only_when_it_reaches_the_target() -> void:
	var s := _ember(3)
	var h := s.hero("hero_wren")
	h.spells.append("swiftwind")
	h.mana = h.max_mana(data)
	h.movement_left = 0
	var ai := StrategicAI.new(s, 0)
	var full := h.max_movement(data)
	var boost := int(round(full * 0.5))
	var far := Vector2i(-1, -1)
	for target in [Vector2i(2, 17), Vector2i(17, 10), Vector2i(8, 12), Vector2i(3, 6)]:
		if int(s.plan_path(h.id, target)["total_cost"]) > boost and not (s.plan_path(h.id, target)["path"] as Array).is_empty():
			far = target
	if far != Vector2i(-1, -1):
		assert_false(ai._cast_for_movement(h, far), "no spell for a target still out of reach")
		assert_eq(h.mana, h.max_mana(data))
	var near := Vector2i(5, 8)   # three road tiles away
	assert_true(int(s.plan_path(h.id, near)["total_cost"]) <= boost)
	assert_true(ai._cast_for_movement(h, near))
	assert_true(h.movement_left >= int(s.plan_path(h.id, near)["total_cost"]))
	assert_eq(h.mana, h.max_mana(data) - int(data.magic["spells"]["swiftwind"]["cost"]))


func test_movement_spell_keeps_mana_for_a_battle_spell() -> void:
	var s := _ember(3)
	var h := s.hero("hero_wren")
	h.spells.append_array(["swiftwind", "warfire"])
	h.mana = 12   # swiftwind (10) would leave too little for warfire (10)
	h.movement_left = 0
	var ai := StrategicAI.new(s, 0)
	assert_false(ai._cast_for_movement(h, Vector2i(5, 8)))
	assert_eq(h.mana, 12)


func test_main_hero_teleports_home_to_defend() -> void:
	var s := _ember(3)
	var h := s.hero("hero_wren")
	var home := s.town(TOWN)
	h.spells.append("homeward")
	h.mana = h.max_mana(data)
	h.pos = s._free_tile_near(Vector2i(17, 10))
	h.movement_left = 0
	var ai := StrategicAI.new(s, 0)
	assert_eq(ai.main_hero(), h)
	ai._threats[TOWN] = 1.0
	ai._teleport_to_defend(h)
	assert_eq(h.pos, AdventureMap.object_pos(home), "Homeward brings the hero back")
	# Nothing to defend: no spell.
	var s2 := _ember(3)
	var h2 := s2.hero("hero_wren")
	h2.spells.append("homeward")
	h2.mana = h2.max_mana(data)
	h2.pos = s2._free_tile_near(Vector2i(17, 10))
	h2.movement_left = 0
	var calm := StrategicAI.new(s2, 0)
	calm._teleport_to_defend(h2)
	assert_eq(h2.mana, h2.max_mana(data))


# --------------------------------------------------------------- upgrades --

func test_ai_upgrades_stacks_in_town() -> void:
	var s := _ember()
	var t := s.town(TOWN)
	(t["built"] as Array).append("c_up1")
	Town.set_garrison(t, Army.from_pairs([["pike_militia", 12]]))
	s._bank(0).add("gold", 20000)
	s._bank(0).add("wood", 20)
	var ai := StrategicAI.new(s, 0)
	assert_eq(ai._upgrade_stacks(t), 1)
	var up := String(data.creature("pike_militia")["upgrade"])
	assert_eq(Town.garrison(t).slots[0]["creature"], up)
	assert_eq(int(Town.garrison(t).slots[0]["count"]), 12)
	assert_eq(ai._upgrade_stacks(t), 0, "nothing left to upgrade")
	# Disabled by a setting.
	var s2 := _ember()
	var t2 := s2.town(TOWN)
	(t2["built"] as Array).append("c_up1")
	Town.set_garrison(t2, Army.from_pairs([["pike_militia", 12]]))
	s2._bank(0).add("gold", 20000)
	s2._bank(0).add("wood", 20)
	assert_eq(StrategicAI.new(s2, 0, {"upgrades": false})._upgrade_stacks(t2), 0)


# ---------------------------------------------------------------- traders --

func test_ai_buys_artifacts_it_would_wear() -> void:
	var s := GameSession.new_game(data, "twin_marches", 3)
	var h := s.hero("hero_west")
	var aid := _free_slot_artifact(h)
	assert_true(aid != "")
	var price := int(data.artifacts[aid]["value"])
	var site := _trader_with(s, h, [{"kind": "artifact", "artifact": aid, "price": price, "remaining": 1}])
	var bank := s._bank(h.owner)
	bank.spend({"gold": bank.get_amount("gold")})
	var ai := StrategicAI.new(s, h.owner)
	bank.add("gold", price + int(ai.settings["trader_reserve_gold"]) - 1)
	assert_eq(ai._shop_at_trader(h, site), 0, "keeps the reserve")
	bank.add("gold", 1)
	assert_true(ai.site_value(h, s.state.map.objects[site]) > 0.0, "a trader with useful wares is worth a visit")
	assert_eq(ai._shop_at_trader(h, site), 1)
	assert_eq(String(h.equipment[data.artifacts[aid]["slot"]]), aid, "worn at once")
	assert_eq(bank.get_amount("gold"), int(ai.settings["trader_reserve_gold"]))
	assert_eq(ai.site_value(h, s.state.map.objects[site]), 0.0, "sold out")


func test_ai_skips_pack_fodder_and_late_maps() -> void:
	var s := GameSession.new_game(data, "twin_marches", 3)
	var h := s.hero("hero_west")
	var aid := _free_slot_artifact(h)
	h.equipment[data.artifacts[aid]["slot"]] = aid   # the same piece is already worn
	var site := _trader_with(s, h, [{"kind": "artifact", "artifact": aid, "price": int(data.artifacts[aid]["value"]), "remaining": 1},
		{"kind": "map", "price": 750, "tiles": 40, "remaining": 3}])
	s._bank(h.owner).add("gold", 50000)
	var fog: FogOfWar = s.state.player(h.owner)["fog"]
	for i in fog.explored.size():
		fog.explored[i] = 1
	var ai := StrategicAI.new(s, h.owner)
	assert_eq(ai.trader_picks(h, s.state.map.objects[site]), [])
	# On a hidden map the chart is worth buying.
	for i in fog.explored.size():
		fog.explored[i] = 0
	var picks := ai.trader_picks(h, s.state.map.objects[site])
	assert_eq(picks.size(), 1)
	assert_eq(int(picks[0]["index"]), 1)
	assert_eq(StrategicAI.new(s, h.owner, {"trades_at_sites": false}).trader_picks(h, s.state.map.objects[site]), [])


# ----------------------------------------------------------------- allies --

func _allied_game() -> GameSession:
	var entry := GameSetup.map_entry(data, "mournfield")
	var setup := GameSetup.default_setup(entry)
	var teams := [1, 2, 2, 1]
	for i in teams.size():
		setup["players"][i]["team"] = teams[i]
	return GameSession.new_game(data, "mournfield", 7, setup)


func test_ai_shares_surplus_with_a_poorer_ally() -> void:
	var s := _allied_game()
	var mine: ResourceBank = s.state.player(0)["resources"]
	var ally: ResourceBank = s.state.player(3)["resources"]
	var enemy: ResourceBank = s.state.player(1)["resources"]
	ally.spend({"gold": ally.get_amount("gold")})
	mine.add("gold", 20000)
	var enemy_gold := enemy.get_amount("gold")
	var ai := StrategicAI.new(s, 0)
	var before := mine.get_amount("gold")
	assert_eq(ai._support_allies(), 1)
	var sent := before - mine.get_amount("gold")
	assert_eq(ally.get_amount("gold"), sent)
	assert_eq(sent, int(float(before - int(ai.settings["gift_reserve_gold"])) * float(ai.settings["gift_share"])))
	assert_true(mine.get_amount("gold") > int(ai.settings["gift_reserve_gold"]))
	assert_eq(enemy.get_amount("gold"), enemy_gold, "enemies get nothing")
	assert_eq(StrategicAI.new(s, 0, {"ally_gifts": false})._support_allies(), 0)


func test_ai_pays_for_a_heroless_allys_new_hero() -> void:
	var s := _allied_game()
	for h in s.state.heroes_of(3):
		h.alive = false
	var ally: ResourceBank = s.state.player(3)["resources"]
	ally.spend({"gold": ally.get_amount("gold")})
	var mine: ResourceBank = s.state.player(0)["resources"]
	mine.spend({"gold": mine.get_amount("gold")})
	var price := int(s.hire_cost(s.towns_of(3)[0]["id"])["gold"])
	mine.add("gold", price)   # no surplus above the reserve, but enough for the hire
	var ai := StrategicAI.new(s, 0)
	assert_eq(ai._support_allies(), 1)
	assert_eq(ally.get_amount("gold"), price)
	assert_eq(mine.get_amount("gold"), 0)


func test_ai_without_allies_sends_nothing() -> void:
	var s := _ember()
	s._bank(0).add("gold", 50000)
	assert_eq(StrategicAI.new(s, 0)._support_allies(), 0)


# ------------------------------------------------------------ integration --

func test_full_turns_report_new_actions_and_stay_valid() -> void:
	var s := GameSession.new_game(data, "twin_marches", 5)
	for p in s.state.players:
		p["is_human"] = false
	var totals := {"upgrades": 0, "spells": 0, "purchases": 0, "gifts": 0}
	while s.state.day <= 14 and not s.state.game_over:
		var rep := StrategicAI.new(s, s.state.current_player).play_turn()
		for k in totals:
			assert_true(rep.has(k), "report has %s" % k)
			totals[k] += int(rep[k])
		for i in s.state.players.size():
			for res in data.resource_order:
				assert_true(s.state.player(i)["resources"].get_amount(res) >= 0)
		s.end_turn()


func test_upgrades_keep_a_reserve_for_buildings() -> void:
	var s := _ember()
	var t := s.town(TOWN)
	(t["built"] as Array).append("c_up1")
	Town.set_garrison(t, Army.from_pairs([["pike_militia", 12]]))
	var bank := s._bank(0)
	bank.spend({"gold": bank.get_amount("gold")})
	bank.add("wood", 20)
	var ai := StrategicAI.new(s, 0)
	var cost: Dictionary = s.upgrade_options(TOWN)[0]["cost"]
	bank.add("gold", int(cost["gold"]) + int(ai.settings["upgrade_reserve_gold"]) - 1)
	assert_eq(ai._upgrade_stacks(t), 0, "the reserve stays for tomorrow's building")
	bank.add("gold", 1)
	assert_eq(ai._upgrade_stacks(t), 1)
