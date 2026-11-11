extends "res://tests/test_case.gd"
## A generated map is built for the factions chosen on the new-game screen:
## each player's home zone gets its faction's native ground, whatever the
## template's default factions are, and for every seed.


func _entry() -> Dictionary:
	return GameSetup.random_entry(data, {"size": "s", "players": 2, "monsters": "normal", "treasure": "normal"})


func _setup(entry: Dictionary, factions: Array) -> Dictionary:
	var setup := GameSetup.default_setup(entry)
	for i in factions.size():
		setup["players"][i]["faction"] = factions[i]
	return setup


func _home_terrain(def: Dictionary, player: int) -> String:
	for z in def["generator"]["zones"]:
		if z.has("player") and int(z["player"]) == player:
			return String(z["terrain"])
	return ""


func _native(faction: String) -> String:
	return String(data.factions[faction]["native_terrain"][0])


func test_default_factions_keep_the_plain_id() -> void:
	var entry := _entry()
	var setup := GameSetup.default_setup(entry)
	assert_eq(GameSetup.map_id_for(entry, 4, setup), "gen:%s:4" % entry["template"])
	assert_eq(GameSetup.map_id_for(entry, 4), "gen:%s:4" % entry["template"])


func test_chosen_faction_paints_its_home_zone() -> void:
	var entry := _entry()
	var defaults: Array = entry["slots"].map(func(s): return String(s["faction"]))
	for faction in ["frostmarch", "ashen", "hollow", "thornwood"]:
		var setup := _setup(entry, [faction])
		var id := GameSetup.map_id_for(entry, 11, setup)
		assert_eq(id, "gen:%s:11:%s,%s" % [entry["template"], faction, defaults[1]])
		var def := data.load_map(id)
		assert_false(def.is_empty(), "%s map generates" % faction)
		assert_eq(String(def["players"][0]["faction"]), faction)
		assert_eq(_home_terrain(def, 0), _native(faction), "%s starts on its native ground" % faction)
		assert_eq(_home_terrain(def, 1), _native(defaults[1]), "the other player keeps its own ground")


func test_every_seed_follows_the_faction() -> void:
	var entry := _entry()
	var setup := _setup(entry, ["frostmarch", "ashen"])
	for s in [1, 2, 3]:
		var def := data.load_map(GameSetup.map_id_for(entry, s, setup))
		assert_eq(_home_terrain(def, 0), "snow", "seed %d" % s)
		assert_eq(_home_terrain(def, 1), "infernal", "seed %d" % s)


func test_faction_ids_round_trip_and_reject_bad_factions() -> void:
	var id := MapGenerator.make_id("twin_marches", 9, ["forge", "darkelf"])
	assert_eq(id, "gen:twin_marches:9:forge,darkelf")
	assert_eq(MapGenerator.parse_id(id), {"template": "twin_marches", "seed": 9, "factions": ["forge", "darkelf"]})
	assert_true(MapGenerator.parse_id("gen:twin_marches:9:forge,").is_empty())
	assert_true(MapGenerator.parse_id("gen:twin_marches:9:a:b").is_empty())
	var tpl: Dictionary = data.map_templates["templates"]["twin_marches"]
	assert_false(MapGenerator.can_use_factions(data, tpl, ["forge"]), "one faction per player")
	assert_false(MapGenerator.can_use_factions(data, tpl, ["forge", "cobolts"]), "neutral factions have no home")
	assert_true(MapGenerator.can_use_factions(data, tpl, ["forge", "darkelf"]))
	var entry := GameSetup.map_entry(data, id)
	assert_eq(entry["template"], "twin_marches")
	assert_eq(GameSetup.map_id_for(entry, 9, GameSetup.default_setup(entry)), id, "an entry keeps the factions its id names")


func test_session_starts_on_native_ground() -> void:
	var entry := _entry()
	var setup := _setup(entry, ["frostmarch"])
	var s := GameSession.new_game(data, GameSetup.map_id_for(entry, 5, setup), 5, setup)
	assert_eq(String(s.state.players[0]["faction"]), "frostmarch")
	var towns: Array = Economy.towns_of(s.state.map, 0)
	assert_eq(towns.size(), 1)
	var p: Array = towns[0]["pos"]
	assert_eq(s.state.map.terrain_at(Vector2i(int(p[0]), int(p[1]))), "snow")
