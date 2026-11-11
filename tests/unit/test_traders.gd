extends "res://tests/test_case.gd"


func _shop() -> GameSession:
	var s := GameSession.new_game(data, "twin_marches", 3)
	var h := s.hero("hero_west")
	var p := s._free_tile_near(h.pos)
	var obj := {"id": "test_trader", "type": "site", "site": MapTraders.SITE_ID,
		"pos": [p.x, p.y], "stock": MapTraders.make_stock(data, GameRng.new(42))}
	s.state.map.add_object(obj)
	MapSites.normalize(obj, data)
	s.state.player(h.owner)["fog"].reveal(p, 1)
	h.movement_left = 1000
	var move := s.move_hero(h.id, p)
	assert_eq(move["site"], "test_trader", "normal map visits open the shop")
	s._bank(0).add("gold", 50000)
	return s


func test_trader_data_art_and_scaling() -> void:
	assert_true(MapTraders.validate(data).is_empty())
	assert_true(Art.has_sprite("site_road_trader"))
	assert_true(ResourceLoader.exists("res://assets/illustrations/trader_shop.png"))
	assert_true(absf(MapTraders.spawn_chance(70, 70, data) - 0.5) < 0.0001)
	assert_true(absf(MapTraders.spawn_chance(140, 70, data) - 0.75) < 0.0001)
	assert_gt(MapTraders.spawn_chance(140, 140, data), MapTraders.spawn_chance(70, 70, data))
	var cfg: Dictionary = data.sites[MapTraders.SITE_ID]["trade"]
	var old: Variant = cfg["map_tiles"]
	cfg["map_tiles"] = -1
	assert_false(MapTraders.validate(data).is_empty())
	cfg["map_tiles"] = old


func test_seeded_stock_and_spawn_distribution() -> void:
	assert_eq(MapTraders.make_stock(data, GameRng.new(4)), MapTraders.make_stock(data, GameRng.new(4)))
	var seen := 0
	for seed_value in 1000:
		if GameRng.new(seed_value).chance(MapTraders.spawn_chance(70, 70, data)):
			seen += 1
	assert_true(seen > 430 and seen < 570, "small map encounter rate: %d/1000" % seen)
	for seed_value in [1, 17]:   # determinism of whole maps: test_mapgen
		var a := generated_map("crossing", seed_value)
		assert_true(MapValidator.validate(a, data).is_empty())
		var traders: Array = a["objects"].filter(func(o): return o.get("site", "") == MapTraders.SITE_ID)
		assert_true(traders.size() <= 1)
		for trader in traders:
			assert_eq(trader["stock"].size(), 4)
			assert_false(a["heroes"].any(func(h): return h["pos"] == trader["pos"]))


func test_buy_artifact_cost_delivery_and_sold_out() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	var offer: Dictionary = s.trader_info("test_trader", h.id)[0]
	var gold := s._bank(0).get_amount("gold")
	var count := h.all_artifacts(data).size()
	assert_true(s.trader_buy("test_trader", h.id, 0)["ok"])
	assert_eq(s._bank(0).get_amount("gold"), gold - int(offer["price"]))
	assert_eq(h.all_artifacts(data).size(), count + 1)
	assert_true(h.all_artifacts(data).has(offer["artifact"]))
	var before := s.state.to_dict()
	assert_false(s.trader_buy("test_trader", h.id, 0)["ok"])
	assert_eq(s.state.to_dict(), before, "sold-out purchases change nothing")


func test_map_reveals_fresh_tiles_and_saves_stock_and_rng() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	var fog: FogOfWar = s.state.player(0)["fog"]
	var before := fog.explored_count()
	var gold := s._bank(0).get_amount("gold")
	var r := s.trader_buy("test_trader", h.id, 3)
	assert_true(r["ok"])
	assert_eq(r["revealed"], 40)
	assert_eq(fog.explored_count(), before + 40)
	assert_eq(s._bank(0).get_amount("gold"), gold - 750)
	var save: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	var loaded := GameSession.from_state(data, GameState.from_dict(save, data))
	assert_eq(loaded.state.map.objects["test_trader"]["stock"][3]["remaining"], 2)
	assert_eq(loaded.state.player(0)["fog"].explored, fog.explored)
	s.trader_buy("test_trader", h.id, 3)
	loaded.trader_buy("test_trader", h.id, 3)
	assert_eq(loaded.state.player(0)["fog"].explored, fog.explored, "same next chart after loading")
	assert_eq(loaded.state.rng.state, s.state.rng.state)


func test_invalid_purchases_are_atomic() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	for index in [-1, 999]:
		var before := s.state.to_dict()
		assert_false(s.trader_buy("test_trader", h.id, index)["ok"])
		assert_eq(s.state.to_dict(), before)
	h.pos = s._free_tile_near(h.pos)
	assert_ne(s.trader_buy_error("test_trader", h.id, 0), "")
	h.pos = AdventureMap.object_pos(s.state.map.objects["test_trader"])
	s._bank(0).spend({"gold": s._bank(0).get_amount("gold")})
	var before := s.state.to_dict()
	assert_false(s.trader_buy("test_trader", h.id, 0)["ok"])
	assert_eq(s.state.to_dict(), before)
	s._bank(0).add("gold", 50000)
	var offer: Dictionary = s.state.map.objects["test_trader"]["stock"][0]
	var aid := String(offer["artifact"])
	h.equipment[data.artifacts[aid]["slot"]] = aid
	h.pack.clear()
	for i in int(data.artifact_rules["pack_size"]):
		h.pack.append(aid)
	before = s.state.to_dict()
	assert_false(s.trader_buy("test_trader", h.id, 0)["ok"])
	assert_eq(s.state.to_dict(), before)
	var fog: FogOfWar = s.state.player(0)["fog"]
	fog.explored.fill(1)
	before = s.state.to_dict()
	assert_false(s.trader_buy("test_trader", h.id, 3)["ok"])
	assert_eq(s.state.to_dict(), before)


func test_forced_spawn_and_authored_maps() -> void:
	var cfg: Dictionary = data.sites[MapTraders.SITE_ID]["trade"]
	var old: Variant = cfg["small_map_chance"]
	cfg["small_map_chance"] = 0.0
	var no_shop := MapGenerator.generate(data, "crossing", 17)
	assert_false(no_shop["objects"].any(func(o): return o.get("site", "") == MapTraders.SITE_ID))
	cfg["small_map_chance"] = 1.0
	var with_shop := MapGenerator.generate(data, "crossing", 17)
	var traders: Array = with_shop["objects"].filter(func(o): return o.get("site", "") == MapTraders.SITE_ID)
	assert_eq(traders.size(), 1)
	assert_eq(with_shop["terrain"], no_shop["terrain"], "shop roll cannot reshuffle terrain")
	assert_eq(with_shop["heroes"], no_shop["heroes"], "shop roll cannot move heroes")
	var a := GameSession.new_game(data, "twin_marches", 77)
	var b := GameSession.new_game(data, "twin_marches", 77)
	assert_true(a.state.map.objects.values().any(func(o): return o.get("site", "") == MapTraders.SITE_ID))
	assert_eq(a.state.map.objects, b.state.map.objects, "authored maps also roll deterministically")
	cfg["small_map_chance"] = old


func test_last_tiles_allied_reveal_and_old_save() -> void:
	var s := _shop()
	var h := s.hero("hero_west")
	s.state.players[0]["team"] = 1
	s.state.players[1]["team"] = 1
	var fog: FogOfWar = s.state.player(0)["fog"]
	fog.explored.fill(1)
	for i in 7:
		fog.explored[i] = 0
	var r := s.trader_buy("test_trader", h.id, 3)
	assert_eq(r["revealed"], 7, "near full exploration reveals every remaining tile")
	for i in 7:
		assert_eq((s.state.player(1)["fog"] as FogOfWar).explored[i], 1, "charts share vision with allies")
	var stock: Array = s.state.map.objects["test_trader"]["stock"]
	stock[0]["remaining"] = 0
	MapSites.normalize(s.state.map.objects["test_trader"], data)
	assert_eq(stock[0]["remaining"], 0, "normalization never replenishes stock")
	var save := s.state.to_dict()
	save["version"] = 15
	save["objects"].erase("test_trader")
	var loaded := GameSession.from_state(data, GameState.from_dict(save, data))
	assert_false(loaded.state.map.objects.has("test_trader"), "old saves load without spawning new traders")
