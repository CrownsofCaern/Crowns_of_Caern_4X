extends "res://tests/test_case.gd"


func _shop(sid: String = "cobolt_yard") -> GameSession:
	var s := GameSession.new_game(data, "twin_marches", 3)
	var h := s.hero("hero_west")
	var p := s._free_tile_near(h.pos)
	var obj := {"id": "test_cobolt", "type": "site", "site": sid, "pos": [p.x, p.y]}
	MapSites.normalize(obj, data)
	s.state.map.add_object(obj)
	h.movement_left = 1000
	(s.state.player(h.owner)["fog"] as FogOfWar).reveal(p, 1)
	var r := s.move_hero(h.id, p)
	assert_eq(r["battle"], "", "peaceful visits never attack hidden guards")
	assert_eq(r["site"], "test_cobolt")
	for res in data.resource_order:
		s._bank(0).add(res, 100000)
	return s


func test_roster_sites_and_non_playable_faction() -> void:
	assert_eq(MapCobolts.validate(data), [] as Array[String])
	assert_false(GameSetup.playable_factions(data).has("cobolts"))
	assert_eq(data.creatures.values().filter(func(c): return c["faction"] == "cobolts").size(), 5)
	for sid in MapCobolts.POSTS:
		assert_true(Art.has_sprite(String(data.sites[sid]["sprite"])))
	for cid in MapCobolts.ROSTER:
		assert_true(Art.has_sprite("creature_" + cid))
	var cfg: Dictionary = data.sites["cobolt_stall"]["cobolt"]
	cfg["discount"] = 0.2
	assert_false(MapCobolts.validate(data).is_empty())
	cfg["discount"] = 0.4


func test_offers_discount_fixed_stock_and_atomic_purchases() -> void:
	var s := _shop()
	var obj: Dictionary = s.state.map.objects["test_cobolt"]
	var h := s.hero("hero_west")
	var pristine := s.state.to_dict()
	var roundtrip := GameSession.from_state(data, GameState.from_dict(JSON.parse_string(JSON.stringify(pristine)), data))
	assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(roundtrip.state.to_dict()))), JSON.stringify(JSON.parse_string(JSON.stringify(pristine))), "new posts normalize identically before and after load")
	var offers := s.cobolt_offers("test_cobolt", h.id)
	assert_eq(offers.size(), 3)
	assert_eq(offers.map(func(o): return o["kind"]), ["recruit", "artifact", "exchange"])
	var exchange: Dictionary = offers[2]
	var baseline := Economy.trade_price(exchange["sell"], exchange["buy"], int(exchange["output"]), 1, data)
	assert_eq(int(exchange["input"]), int(ceil(baseline * 0.6)))
	var before_sell := s._bank(0).get_amount(exchange["sell"])
	var before_buy := s._bank(0).get_amount(exchange["buy"])
	assert_true(s.cobolt_buy("test_cobolt", h.id, 2, 2)["ok"])
	assert_eq(s._bank(0).get_amount(exchange["sell"]), before_sell - int(exchange["input"]) * 2)
	assert_eq(s._bank(0).get_amount(exchange["buy"]), before_buy + int(exchange["output"]) * 2)
	var before := s.state.to_dict()
	for bad in [-1, 9]:
		assert_false(s.cobolt_buy("test_cobolt", h.id, bad)["ok"])
	for quantity in [0, -1, 99999]:
		assert_false(s.cobolt_buy("test_cobolt", h.id, 2, quantity)["ok"])
	assert_eq(s.state.to_dict(), before)
	assert_true(s.cobolt_buy("test_cobolt", h.id, 0, 2)["ok"])
	assert_true(h.army.to_combat_stacks().any(func(st): return st["creature"] == offers[0]["creature"] and st["count"] == 2))
	assert_true(s.cobolt_buy("test_cobolt", h.id, 1)["ok"])
	assert_false(s.cobolt_buy("test_cobolt", h.id, 1)["ok"])
	var saved := obj.duplicate(true)
	MapSites.normalize(obj, data)
	assert_eq(obj, saved, "visits and normalization do not refresh stock or guards")


func test_guard_secrecy_scout_mastery_forecast_and_reports() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	var obj: Dictionary = s.state.map.objects["test_cobolt"]
	obj["guard"] = [["cobolt_caravan_spear", 37], ["cobolt_vault_warden", 13]]
	var before: Array = obj["guard"].duplicate(true)
	var it := s.intel(h.id, "test_cobolt")
	assert_eq(it["stacks"], [])
	assert_eq(it["report"], ["Guards concealed"])
	assert_eq(it["odds"], "none")
	assert_eq(it["win_probability"], -1.0)
	assert_eq(MapTip.troop_lines(it), ["Guards concealed"])
	h.skills["scouting"] = 3
	assert_true(s.scout(h.id, "test_cobolt")["ok"])
	it = s.intel(h.id, "test_cobolt")
	assert_true(it["scouted"])
	assert_eq(it["stacks"], [])
	assert_eq(it["odds"], "none")
	assert_true(String(it["report"][1]).contains("reserves unknown"))
	assert_false(JSON.stringify(it).contains("37"), "no exact count in the public payload")
	assert_eq(s.intel(h.id, "test_cobolt"), it)
	assert_false(s.scout(h.id, "test_cobolt")["ok"])
	var pred := s.preview_battle(h.id, "test_cobolt")
	assert_eq(pred["enemy"]["stacks"], [])
	assert_false(pred.has("expected_loss_fraction"))
	assert_false(pred.has("simulations"))
	assert_eq(obj["guard"], before)
	assert_false(s.is_scouted("test_cobolt", 1), "reports are player-local")
	s.state.day += 1
	assert_eq(s.intel(h.id, "test_cobolt")["report"], ["Guards concealed"])


func test_restock_caps_and_save_load() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	var obj: Dictionary = s.state.map.objects["test_cobolt"]
	s.cobolt_buy("test_cobolt", h.id, 0, 2)
	s.cobolt_buy("test_cobolt", h.id, 1)
	s.cobolt_buy("test_cobolt", h.id, 2)
	s.scout(h.id, "test_cobolt")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	var loaded := GameSession.from_state(data, GameState.from_dict(saved, data))
	assert_eq(loaded.state.map.objects["test_cobolt"], obj)
	assert_eq(loaded.intel(h.id, "test_cobolt"), s.intel(h.id, "test_cobolt"))
	s._weekly_growth()
	assert_eq(obj["stock"][0]["remaining"], obj["stock"][0]["cap"])
	assert_eq(obj["stock"][1]["remaining"], 0)
	assert_eq(obj["stock"][2]["remaining"], obj["stock"][2]["cap"])
	s._weekly_growth()
	assert_eq(obj["stock"][0]["remaining"], obj["stock"][0]["cap"])
	obj["plundered"] = true
	obj["stock"][0]["remaining"] = 0
	s._weekly_growth()
	assert_eq(obj["stock"][0]["remaining"], 0)


func test_robbery_victory_fixed_loot_and_no_duplicate_artifact() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	var obj: Dictionary = s.state.map.objects["test_cobolt"]
	s.cobolt_buy("test_cobolt", h.id, 1)
	var arts := h.all_artifacts(data).size()
	h.army = Army.from_pairs([["cobolt_vault_warden", 100]])
	obj["guard"] = [["cobolt_pack_runner", 1]]
	var gold := s._bank(0).get_amount("gold")
	var loot := int(obj["loot_gold"])
	var r := s.attack(h.id, "test_cobolt")
	assert_true(r.has("winner"))
	assert_eq(r["winner"], 0)
	assert_true(obj["plundered"])
	assert_eq(obj["loot_gold"], 0)
	assert_true(s._bank(0).get_amount("gold") >= gold + loot)
	assert_eq(h.all_artifacts(data).size(), arts)
	assert_ne(MapCobolts.access_error(obj, 1), "", "plunder closes it to everyone")
	assert_false(s.cobolt_buy("test_cobolt", h.id, 0)["ok"])
	assert_false(s.attack(h.id, "test_cobolt")["ok"])
	assert_eq(MapSites.site_name(obj, data), "Plundered Cobolt Post")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	var loaded := GameSession.from_state(data, GameState.from_dict(saved, data))
	assert_true(loaded.state.map.objects["test_cobolt"]["plundered"])
	assert_false(loaded.state.map.objects["test_cobolt"].has("guard"))


func test_failed_robbery_hostility_is_local_and_guards_persist() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	var obj: Dictionary = s.state.map.objects["test_cobolt"]
	h.army = Army.from_pairs([["cobolt_pack_runner", 1]])
	obj["guard"] = [["cobolt_vault_warden", 200]]
	var gold := int(obj["loot_gold"])
	var r := s.attack(h.id, "test_cobolt")
	assert_true(r.has("winner"))
	assert_ne(r["winner"], 0)
	assert_false(obj["plundered"])
	assert_ne(MapCobolts.access_error(obj, 0), "")
	assert_eq(MapCobolts.access_error(obj, 1), "")
	assert_eq(obj["loot_gold"], gold)
	assert_false((obj["guard"] as Array).is_empty())
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	var loaded := GameSession.from_state(data, GameState.from_dict(saved, data))
	assert_eq(loaded.state.map.objects["test_cobolt"]["hostile_players"], [0])


func test_generation_editor_and_old_saves() -> void:
	var a := generated_map("crossing", 17)   # determinism: test_mapgen
	var posts: Array = a["objects"].filter(func(o): return MapCobolts.is_post(o, data))
	assert_false(posts.is_empty())
	assert_eq(MapValidator.validate(a, data), [] as Array[String])
	for post in posts:
		assert_eq(post["stock"].size(), 3)
		assert_true((post["guard"] as Array).all(func(st): return data.creature(st[0])["faction"] == "cobolts"))
	var s := _shop()
	var saved := s.state.to_dict()
	saved["version"] = 18
	for id in saved["objects"].keys():
		if MapCobolts.is_post(saved["objects"][id], data):
			saved["objects"].erase(id)
	var loaded := GameSession.from_state(data, GameState.from_dict(saved, data))
	assert_false(loaded.state.map.objects.values().any(func(o): return MapCobolts.is_post(o, data)))


func test_cobolt_panels_build_and_masked_forecast() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	var dialog := SiteDialog.new()
	dialog.build(data, 620)
	dialog.open(s, "test_cobolt", h.id)
	assert_true(dialog.visible)
	var panels := BattlePanels.new()
	panels.build(data)
	panels.show_forecast("Cobolts", s.preview_battle(h.id, "test_cobolt"))
	assert_true(panels.visible)
	dialog.free()
	panels.free()


func test_ai_never_forecasts_hidden_defenders_and_can_hire() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	var obj: Dictionary = s.state.map.objects["test_cobolt"]
	var ai := StrategicAI.new(s, 0)
	s.state.day = int(ai.settings["cobolt_from_day"]) - 1
	assert_eq(ai.site_value(h, obj), 0.0, "no cobolt shopping in week one")
	s.state.day = int(ai.settings["cobolt_from_day"])
	var value := ai.site_value(h, obj)
	assert_gt(value, 0.0)
	obj["guard"] = [["cobolt_vault_warden", 99999]]
	assert_eq(ai.site_value(h, obj), value, "shop utility ignores private armies")
	assert_eq(ai.defender_value(obj), 0.0)
	assert_eq(ai.forecast(h, "test_cobolt")["win_probability"], -1.0)
	assert_false(s.is_guarded(obj, 0))
	assert_false(MapGenerator.blocks_path(obj))
	assert_false(MapCobolts.is_post({}, data))
	var pool_before := int(obj["stock"][0]["remaining"])
	ai._recruit_at_site(h, "test_cobolt")
	assert_lt(int(obj["stock"][0]["remaining"]), pool_before, "AI can hire without inspecting guards")


func test_authored_stock_validation_and_exact_discount_for_all_pairs() -> void:
	var s := _shop()
	var obj: Dictionary = s.state.map.objects["test_cobolt"]
	assert_true(MapCobolts.object_errors(obj, data).is_empty())
	var bad := obj.duplicate(true)
	bad["stock"][2]["input"] = -1
	assert_false(MapCobolts.object_errors(bad, data).is_empty())
	bad = obj.duplicate(true)
	bad["stock"][0]["creature"] = "thornwolf"
	assert_false(MapCobolts.object_errors(bad, data).is_empty())
	for sell in data.resource_order:
		for buy in data.resource_order:
			if sell == "gold" or buy == "gold" or sell == buy:
				continue
			var standard := Economy.trade_price(sell, buy, 8, 1, data)
			assert_eq(standard % 5, 0, "whole bundles permit an exact 40% discount")


func test_unsold_artifact_loot_survives_full_pack_and_no_drop_space() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	var obj: Dictionary = s.state.map.objects["test_cobolt"]
	var aid := String(obj["stock"][1]["artifact"])
	h.equipment[data.artifacts[aid]["slot"]] = aid
	h.pack.clear()
	for i in int(data.artifact_rules["pack_size"]):
		h.pack.append(aid)
	# A cramped custom-map post with no free adjacent tile must retain its loot.
	s.state.map.road.fill(0)
	for y in s.state.map.height:
		for x in s.state.map.width:
			if Vector2i(x, y) != h.pos:
				s.state.map.terrain[s.state.map.index(Vector2i(x, y))] = "mountain"
	s._plunder_cobolt(h, obj, {"summary": []})
	assert_eq(obj["unclaimed_artifact"], aid)
	assert_false(s.cobolt_claim_loot("test_cobolt", h.id)["ok"])
	h.pack.pop_back()
	assert_true(s.cobolt_claim_loot("test_cobolt", h.id)["ok"])
	assert_false(obj.has("unclaimed_artifact"))
	assert_false(s.cobolt_claim_loot("test_cobolt", h.id)["ok"], "loot can be claimed only once")
