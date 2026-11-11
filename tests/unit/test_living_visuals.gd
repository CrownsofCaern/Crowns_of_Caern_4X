extends "res://tests/test_case.gd"


func test_town_layers_replace_their_predecessors() -> void:
	var scene := TownScene.scene_for("concord")
	assert_false(scene.is_empty())
	var built := ["c_hall", "c_court", "c_exchequer", "c_dw1", "c_up1", "c_palisade", "c_keep"]
	var result := TownScene.resolved_buildings(scene, built)
	assert_true("c_exchequer" in result)
	assert_true("c_up1" in result)
	assert_true("c_keep" in result)
	for id in ["c_hall", "c_court", "c_dw1", "c_palisade"]:
		assert_false(id in result, "only the highest constructed state occupies a slot")


func test_every_faction_has_a_town_scene_covering_its_roster() -> void:
	var data := GameData.get_default()
	for faction in data.town_types:
		var scene := TownScene.scene_for(faction)
		assert_false(scene.is_empty(), "%s has a town view" % faction)
		assert_true(ResourceLoader.exists(String(scene["background"])), "%s background loads" % faction)
		var ids := []
		for slot in scene["slots"]:
			ids.append_array(slot["variants"])
		assert_eq(ids.size(), data.town_types[faction]["buildings"].size(), "%s slots name each building once" % faction)
		for id in data.town_types[faction]["buildings"]:
			assert_true(id in ids, "%s/%s has a site" % [faction, id])
		for id in scene["assets"]:
			assert_true(ResourceLoader.exists(String(scene["assets"][id])), "%s/%s art loads" % [faction, id])


func test_thornwood_buildings_have_art_and_upgrades_reuse_it() -> void:
	var scene := TownScene.scene_for("thornwood")
	for id in ["t_hall", "t_court", "t_assembly", "t_exchequer", "t_market", "t_yard", "t_tavern", "t_special",
			"t_fort1", "t_fort2", "t_fort3", "t_dw1", "t_dw8", "t_up1", "t_up8"]:
		assert_true(scene["assets"].has(id), id)
	assert_eq(scene["assets"]["t_up3"], scene["assets"]["t_dw3"])
	var result := TownScene.resolved_buildings(scene, ["t_hall", "t_court", "t_dw3", "t_up3", "t_fort1", "t_grow1"])
	assert_true("t_court" in result)
	assert_true("t_up3" in result)
	assert_true("t_grow1" in result, "a built site without art still resolves (drawn as a plaque)")
	assert_false("t_hall" in result)


func test_connected_ground_follows_neighbouring_cells_and_wraps() -> void:
	var tiles := TerrainTiles.new(Art.terrain_info())
	var info: Dictionary = tiles.info["terrains"]["grass"]["field"]
	var start := int(info["column"])
	var width := int(info["cells"][0])
	var height := int(info["cells"][1])
	assert_true(width >= 12)
	assert_eq(tiles.ground_coords("grass", Vector2i(0, 0)).x, start)
	assert_eq(tiles.ground_coords("grass", Vector2i(1, 0)).x, start + 1)
	assert_eq(tiles.ground_coords("grass", Vector2i(0, 1)).x, start + width)
	assert_eq(tiles.ground_coords("grass", Vector2i(width, height)), tiles.ground_coords("grass", Vector2i(0, 0)))
	assert_eq(tiles.ground_coords("grass", Vector2i(-1, -1)).x, start + width * height - 1)


func test_single_sprite_motion_is_small_and_riding_stays_above_anchor() -> void:
	for i in 240:
		var idle := SpriteMotion.pose(i / 30.0, 0.8, false)
		assert_between(idle.y, 0.987, 1.013)
		assert_eq(idle.z, 0.0, "breathing retains the feet anchor")
		var ride := SpriteMotion.pose(i / 30.0, 0.8, true)
		assert_between(ride.z, -2.001, 0.001)
		assert_between(ride.x, 0.993, 1.007)


func test_every_faction_shows_art_for_its_halls_and_dwellings() -> void:
	var data := GameData.get_default()
	for faction in data.town_types:
		var scene := TownScene.scene_for(faction)
		for slot in scene["slots"]:
			if String(slot["id"]) in ["civic", "fortification"] or String(slot["id"]).begins_with("dw"):
				for id in slot["variants"]:
					assert_true(scene["assets"].has(id), "%s/%s has art" % [faction, id])
	var hollow := TownScene.scene_for("hollow")
	assert_eq(hollow["assets"]["h_up5"], hollow["assets"]["h_dw5"], "upgrades reuse the base dwelling")
