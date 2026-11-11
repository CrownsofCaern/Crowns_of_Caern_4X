extends "res://tests/test_case.gd"


func _river_battle() -> Dictionary:
	var session := GameSession.new_game(data,"ember_ford",11)
	for object in session.state.map.objects.values():
		if object.get("type","") == "neutral_army":
			var tile := AdventureMap.object_pos(object)
			session.state.map.terrain[session.state.map.index(tile)] = "river"
			return {"session":session,"target":String(object["id"])}
	return {}


func test_every_terrain_has_a_high_resolution_battlefield() -> void:
	for terrain in data.terrains:
		var scene := BattlefieldArt.select(terrain)
		assert_eq(scene["terrain"],terrain)
		assert_true(ResourceLoader.exists(scene["path"]),terrain)
		assert_true(int(scene["size"][0]) >= 1280 and int(scene["size"][1]) >= 768)


func test_alternate_scenes_are_stable_and_unknown_terrain_falls_back() -> void:
	assert_eq(BattlefieldArt.select("grass",28),BattlefieldArt.select("grass",28))
	assert_ne(BattlefieldArt.select("grass",0)["id"],BattlefieldArt.select("grass",1)["id"])
	assert_eq(BattlefieldArt.select("not_a_terrain")["terrain"],"grass")


func test_background_crops_preserve_aspect_and_horizon_without_gaps() -> void:
	var source := Vector2(1536,1024)
	for destination in [Vector2(1280,800),Vector2(680,132),Vector2(800,1280),Vector2(1920,800)]:
		for target_h in [0.30,0.52]:
			var crop := BattlefieldArt.source_rect(source,destination,0.30,target_h)
			assert_true(crop.position.x >= -0.01 and crop.position.y >= -0.01)
			assert_true(crop.end.x <= source.x+0.01 and crop.end.y <= source.y+0.01)
			assert_between(crop.size.x/crop.size.y-destination.x/destination.y,-0.001,0.001)
			var horizon := (source.y*0.30-crop.position.y)/crop.size.y
			assert_between(horizon-target_h,-0.001,0.001)


func test_river_art_preserves_grass_rules_and_does_not_consume_game_rng() -> void:
	var fixture := _river_battle()
	assert_false(fixture.is_empty())
	var session: GameSession = fixture["session"]
	var before := session.state.rng.state
	var setup := session.battle_setup("hero_wren",fixture["target"])
	assert_eq(setup["terrain"],"grass")
	assert_eq(setup["visual_terrain"],"river")
	BattlefieldArt.select(setup["visual_terrain"],setup["visual_seed"])
	assert_eq(session.state.rng.state,before)
	var old := setup.duplicate(true)
	old.erase("visual_terrain")
	old.erase("visual_seed")
	var sim := CombatSimulator.new(data)
	assert_eq(sim.simulate(setup,true),sim.simulate(old,true),"scenery metadata never changes a battle")


func test_preview_and_resolved_battle_keep_the_same_scene() -> void:
	var fixture := _river_battle()
	var session: GameSession = fixture["session"]
	var preview := session.preview_battle("hero_wren",fixture["target"])
	var result := session.attack("hero_wren",fixture["target"])
	assert_true(result.has("winner"))
	assert_eq(result["terrain"],"grass")
	assert_eq(result["visual_terrain"],"river")
	assert_eq(BattlefieldArt.select(preview["visual_terrain"],preview["visual_seed"])["id"],
		BattlefieldArt.select(result["visual_terrain"],result["visual_seed"])["id"])
