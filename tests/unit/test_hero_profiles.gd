extends "res://tests/test_case.gd"


func test_portraits_cover_all_classes_and_campaign_heroes() -> void:
	for id in data.hero_classes:
		var profile := Art.hero_profile("", id)
		assert_true(profile != null, id)
		if profile != null:
			assert_eq(profile.get_size(), Vector2(256, 256), id)
	for campaign in data.campaigns.values():
		for id in campaign["heroes"]:
			assert_true(Art.CAMPAIGN_PORTRAIT_CLASSES.has(id), id)
			var class_id: String = Art.CAMPAIGN_PORTRAIT_CLASSES.get(id, "")
			var profile := Art.hero_profile(id, class_id)
			assert_true(profile != null, id)
			if profile != null:
				assert_true(profile.resource_path.contains("/campaign/"), id)


func test_named_portraits_fall_back_when_class_changes() -> void:
	var named := Art.hero_profile("hero_wren", "knight")
	var generic := Art.hero_profile("hero_wren", "ranger")
	assert_true(named != null and generic != null)
	assert_ne(named, generic)
	assert_eq(generic, Art.hero_profile("", "ranger"))
	assert_true(Art.hero_profile("unknown", "missing_class") == null)
	var widget := HeroPortrait.new()
	widget.set_hero("hero_wren", "knight")
	assert_eq(widget._profile, named)
	widget.set_hero("hero_wren", "ranger")
	assert_eq(widget._profile, generic)
	widget.free()
