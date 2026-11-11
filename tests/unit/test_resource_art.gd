extends "res://tests/test_case.gd"


func test_every_resource_has_map_art_with_consistent_footprint() -> void:
	for rid in data.resource_order:
		var sid := "resource_" + String(rid)
		assert_eq(Art.sprite(sid).get_size(), Vector2(96, 96), sid)
		assert_eq(Art.sprite_info(sid)["map_scale"], 0.5, sid)
		assert_eq(Art.sprite_info(sid)["anchor"], [48.0, 95.0], sid)
		assert_eq(Art.sprite_info(sid)["source"], "generated", sid)
	assert_eq(Art.sprite("object_chest").get_size(), Vector2(96, 96))


func test_resource_ui_uses_dedicated_legible_icons() -> void:
	for rid in data.resource_order:
		var texture := Art.resource_icon(rid)
		assert_true(texture != null, rid)
		assert_eq(texture.get_size(), Vector2(48, 48), rid)
		assert_eq(texture, Art.sprite("ui_resource_" + String(rid)), rid)
	assert_true(Art.resource_icon("no_such_resource") == null)


func test_ui_falls_back_to_map_art_when_icon_is_missing() -> void:
	var cached := Art._sprite_cache.duplicate()
	Art._sprite_cache["ui_resource_gold"] = null
	assert_eq(Art.resource_icon("gold"), Art.sprite("resource_gold"))
	Art._sprite_cache = cached
