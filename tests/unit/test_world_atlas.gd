extends "res://tests/test_case.gd"


func _atlas() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/world_atlas.json"))


func test_every_existing_campaign_has_one_shared_location_per_chapter() -> void:
	var atlas := _atlas()
	for cid in data.campaigns:
		if not atlas["campaign_routes"].has(cid) and (data.campaigns[cid]["chapters"] as Array).any(func(ch): return ScenarioGenerator.is_generated_id(String(ch["map"]))):
			continue # Procedural missions have a chapter route, not fixed world geography.
		assert_true(atlas["campaign_routes"].has(cid), cid)
		var route: Array = atlas["campaign_routes"][cid]
		assert_eq(route.size(), data.campaigns[cid]["chapters"].size(), cid)
		for i in route.size():
			var chapter_id: String = data.campaigns[cid]["chapters"][i]["id"]
			assert_eq(atlas["chapter_locations"][cid][chapter_id],route[i],chapter_id)
		for key in route:
			assert_true(atlas["landmarks"].has(key), key)
			var point: Array = atlas["landmarks"][key]["at"]
			assert_between(point[0], 0.0, 1.0, key)
			assert_between(point[1], 0.0, 1.0, key)
	assert_eq(atlas["campaign_routes"]["last_light"][7], atlas["campaign_routes"]["unsealing"][6], "both sides fight at the same ford")


func test_story_directions_and_dlc_layers_remain_consistent() -> void:
	var atlas := _atlas()
	var places: Dictionary = atlas["landmarks"]
	assert_lt(places["wyrm_glacier"]["at"][1], places["northern_granaries"]["at"][1])
	assert_gt(places["sallowmere_court"]["at"][1], places["greyhold"]["at"][1])
	assert_gt(places["burning_ford"]["at"][0], places["greyhold"]["at"][0])
	assert_lt(places["barrow_below"]["at"][0], places["skarns_pit"]["at"][0])
	assert_lt(places["last_grove"]["at"][0], places["heartroots"]["at"][0])
	assert_eq(atlas["layers"]["deep_underworld"]["future_faction"], "darkelf")
	assert_eq(atlas["expansion_reserves"]["atlantean_shelf"]["future_faction"], "fishmen")
	assert_eq(atlas["status"], "geography_approved_world_scale_revision")


func test_empire_atlas_preserves_regional_geography_and_room_for_many_towns() -> void:
	var atlas := _atlas()
	assert_eq(atlas["empires"].size(), 6)
	var transform: Dictionary = atlas["regional_reference"]["world_transform"]
	for key in atlas["landmarks"]:
		var place: Dictionary = atlas["landmarks"][key]
		var regional: Array = place["regional_reference_at"]
		for axis in 2:
			var expected: float = transform["offset"][axis] + transform["scale"][axis] * regional[axis]
			assert_true(absf(place["at"][axis] - expected) < .00001, key)
	var seen := {}
	for key in atlas["empires"]:
		var empire: Dictionary = atlas["empires"][key]
		assert_true(data.factions.has(empire["faction"]), key)
		assert_true(empire["hinterland_settlements"].size() >= 6, key)
		for settlement in empire["hinterland_settlements"]:
			assert_false(seen.has(settlement["id"]), settlement["id"])
			seen[settlement["id"]] = true
			assert_false(atlas["landmarks"].has(settlement["id"]), "context towns are not chapter destinations")
			assert_between(settlement["at"][0], 0.0, 1.0)
			assert_between(settlement["at"][1], 0.0, 1.0)
	var shelf: Array = atlas["expansion_reserves"]["atlantean_shelf"]["bounds"]
	assert_true((shelf[2] - shelf[0]) * (shelf[3] - shelf[1]) >= .07, "substantial sea reserved for Atlantis")
