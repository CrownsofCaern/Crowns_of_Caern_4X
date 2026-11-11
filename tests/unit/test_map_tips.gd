extends "res://tests/test_case.gd"
## The map's hover card: every kind of map object says what it is, who holds it
## and what it does (MapTipInfo), and the card shows that with the hostile-army
## intel on top (MapTip).


func _session() -> GameSession:
	var s := GameSession.new_game(data, "twin_marches", 3)
	var fog: FogOfWar = s.current_player()["fog"]
	for y in s.state.map.height:
		for x in s.state.map.width:
			fog.reveal(Vector2i(x, y), 0)
	return s


func _first(s: GameSession, type: String, pred: Callable = func(_o): return true) -> Dictionary:
	var ids := s.state.map.objects.keys()
	ids.sort()
	for id in ids:
		var o: Dictionary = s.state.map.objects[id]
		if o["type"] == type and pred.call(o) and s.state.hero_at(AdventureMap.object_pos(o)) == null:
			return o
	return {}


func _texts(info: Dictionary) -> String:
	return "\n".join(info["lines"].map(func(l): return String(l[0])))


func _put(s: GameSession, o: Dictionary) -> Dictionary:
	var h: Hero = s.state.heroes_of(0)[0]
	var p := s._free_tile_near(h.pos)
	o["pos"] = [p.x, p.y]
	s.state.map.add_object(o)
	return o


func test_every_map_object_type_is_described() -> void:
	var s := _session()
	var h: Hero = s.state.heroes_of(0)[0]
	for type in ["town", "mine", "resource", "neutral_army"]:
		var o := _first(s, type)
		assert_false(o.is_empty(), "twin_marches has a %s" % type)
		var info := MapTipInfo.describe(s, AdventureMap.object_pos(o), h)
		assert_false(info.is_empty(), type)
		assert_ne(String(info["title"]), "", type)
		assert_ne(String(info["kind"]), "", type)
	var art := _put(s, {"id": "test_art", "type": "artifact", "artifact": "notched_falchion"})
	var info := MapTipInfo.describe(s, AdventureMap.object_pos(art), h)
	assert_eq(info["title"], "Notched Falchion")
	assert_true(info["kind"].begins_with("Artifact"))
	assert_true(_texts(info).contains("+1 attack"))
	var enc_id: String = data.encounters.keys()[0]
	var enc := _put(s, {"id": "test_enc", "type": "encounter", "encounter": enc_id})
	info = MapTipInfo.describe(s, AdventureMap.object_pos(enc), h)
	assert_eq(info["title"], data.encounters[enc_id]["name"])
	assert_true(_texts(info).contains("Choices: "))


func test_plain_ground_and_fog_say_nothing() -> void:
	var s := GameSession.new_game(data, "twin_marches", 3)
	var h: Hero = s.state.heroes_of(0)[0]
	var far := Vector2i(s.state.map.width - 1, s.state.map.height - 1)
	assert_true(MapTipInfo.describe(s, far, h).is_empty(), "unexplored")
	var fog: FogOfWar = s.current_player()["fog"]
	for y in s.state.map.height:
		for x in s.state.map.width:
			var p := Vector2i(x, y)
			if fog.is_explored(p) and s.state.map.object_at(p).is_empty() and s.state.hero_at(p) == null:
				assert_true(MapTipInfo.describe(s, p, h).is_empty(), "plain ground")
				return
	_fail("no plain explored tile")


func test_mine_shows_income_and_owner() -> void:
	var s := _session()
	var m := _first(s, "mine")
	var info := MapTipInfo.describe(s, AdventureMap.object_pos(m), null)
	assert_eq(info["kind"], "Mine")
	assert_true(_texts(info).contains("+%d %s a day" % [Economy.mine_income(m, data), data.resources[m["resource"]]["name"]]))
	m["owner"] = 0
	assert_true(_texts(MapTipInfo.describe(s, AdventureMap.object_pos(m), null)).contains("Yours"))
	m["owner"] = 1
	assert_true(_texts(MapTipInfo.describe(s, AdventureMap.object_pos(m), null)).contains("Enemy: "))


func test_rare_buildings_say_what_they_do() -> void:
	var s := _session()
	var h: Hero = s.state.heroes_of(0)[0]
	for site_id in data.sites:
		var o := _put(s, {"id": "test_site_" + site_id, "type": "site", "site": site_id})
		MapSites.normalize(o, data)
		var info := MapTipInfo.describe(s, AdventureMap.object_pos(o), h)
		assert_eq(info["title"], MapSites.site_name(o, data))
		assert_true(info["kind"].begins_with("Rare building"))
		assert_true(_texts(info).contains(MapSites.summary(o, data)), site_id)
		s.state.map.remove_object(o["id"])
	var lore := _put(s, {"id": "test_lore", "type": "site", "site": "elder_rings", "visitors": [h.id]})
	MapSites.normalize(lore, data)
	assert_true(_texts(MapTipInfo.describe(s, AdventureMap.object_pos(lore), h)).contains(MapSites.visit_block(h, lore, data)),
		"a visited site says so")


func test_heroes_are_described() -> void:
	var s := _session()
	var mine: Hero = s.state.heroes_of(0)[0]
	var town_info := MapTipInfo.describe(s, mine.pos, mine)
	if s.state.map.object_at(mine.pos).get("type", "") == "town":
		assert_true(_texts(town_info).contains("%s stands in the town" % mine.name), "a hero in a town is named with it")
	mine.pos = s._free_tile_near(mine.pos)
	var info := MapTipInfo.describe(s, mine.pos, mine)
	assert_eq(info["title"], mine.name)
	assert_true(_texts(info).contains("Movement left"))
	var foe: Hero = s.state.heroes_of(1)[0]
	foe.pos = s._free_tile_near(foe.pos)
	info = MapTipInfo.describe(s, foe.pos, mine)
	assert_true(info["kind"].begins_with("Hero"))
	assert_true(_texts(info).contains("Enemy: ") or _texts(info).contains("Ally: "))
	assert_false(_texts(info).contains("Movement left"), "an enemy's movement stays hidden")


func test_flavor_text_is_cut_at_a_sentence() -> void:
	assert_eq(MapTipInfo.flavor_text("Short."), "Short.")
	var long := "The first sentence is here and it is long enough to matter. " + "More words follow ".repeat(10)
	assert_eq(MapTipInfo.flavor_text(long), "The first sentence is here and it is long enough to matter.")
	assert_true(MapTipInfo.flavor_text("word ".repeat(60)).length() <= MapTipInfo.FLAVOR_CHARS + 1)


func test_card_combines_info_and_intel() -> void:
	var s := _session()
	var h: Hero = s.state.heroes_of(0)[0]
	var tip := MapTip.new()
	var m := _first(s, "mine", func(o): return not (o.get("guard", []) as Array).is_empty())
	var p := AdventureMap.object_pos(m)
	var target := s.hostile_target_at(p, 0)
	assert_eq(target, m["id"], "a guarded mine is hostile")
	tip.show_card(MapTipInfo.describe(s, p, h), s.intel(h.id, target), Vector2(50, 50), Rect2(0, 0, 900, 700))
	assert_true(tip.visible)
	tip.show_card({}, {}, Vector2.ZERO, Rect2(0, 0, 900, 700))
	assert_false(tip.visible, "nothing to say hides the card")
	tip.free()
