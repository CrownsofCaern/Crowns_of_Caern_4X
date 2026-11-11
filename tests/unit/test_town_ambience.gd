extends "res://tests/test_case.gd"


func test_every_town_has_a_loop_profile_with_valid_art_anchors() -> void:
	var data := GameData.get_default()
	for faction in data.town_types:
		var profile := TownScene.ambience_for(faction)
		assert_false(profile.is_empty(), "%s has ambient animation" % faction)
		assert_true(profile.get("particles", "") in ["motes", "snow", "bubbles"])
		var scene := TownScene.scene_for(faction)
		var source_ids := []
		for path in scene["assets"].values():
			source_ids.append(String(path).get_file().get_basename())
		for id in profile.get("buildings", {}):
			assert_true(id in source_ids, "%s emitter attaches to existing artwork" % id)
			var features: Dictionary = profile["buildings"][id]
			for kind in ["smoke", "motes"]:
				for point in features.get(kind, []):
					assert_eq(point.size(), 2)
					assert_between(float(point[0]), 0.0, 1.0)
					assert_between(float(point[1]), 0.0, 1.0)
			var banner: Array = features.get("banner", [])
			if not banner.is_empty():
				assert_eq(banner.size(), 4)
				assert_between(float(banner[0]) + float(banner[2]), 0.0, 1.0)
				assert_between(float(banner[1]) + float(banner[3]), 0.0, 1.0)


func test_cosmetic_clock_wraps_at_the_exact_loop_boundary() -> void:
	for time in [0.0, 0.25, 1.0, 3.75, 7.9]:
		assert_lt(absf(TownScene.animation_phase(time) - TownScene.animation_phase(time + 8.0)), 0.00001)
	assert_eq(TownScene.animation_phase(8.0), 0.0)
	assert_eq(TownScene.animation_phase(-2.0), 0.75)


func test_town_loops_do_not_capture_building_clicks() -> void:
	var layer = load("res://src/ui/town_building_loop.gd").new()
	var tex := PlaceholderTexture2D.new()
	layer.configure(tex, TownScene.ambience_for("concord"), {}, 0)
	assert_eq(layer.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(layer.get_child(0).mouse_filter, Control.MOUSE_FILTER_IGNORE)
	layer.free()
