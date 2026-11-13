extends "res://tests/test_case.gd"


func test_faction_changes_existing_ui_without_recolouring_warnings() -> void:
	var root := Control.new()
	UiStyle.apply_faction(root, "concord")
	root.theme = UiStyle.make_theme()
	var shared := root.theme
	var title := UiStyle.label("Faction", 18, UiStyle.BRASS)
	var warning := UiStyle.label("Losses", 15, UiStyle.BAD)
	root.add_child(title)
	root.add_child(warning)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(Color("#15110d")))
	root.add_child(panel)
	UiStyle.apply_faction(root, "hollow")
	assert_eq(UiStyle.accent(), Color("#8aee78"))
	assert_eq(title.get_theme_color("font_color"), UiStyle.accent())
	assert_eq(warning.get_theme_color("font_color"), UiStyle.BAD)
	assert_eq(panel.get_theme_stylebox("panel").bg_color, Color("#191e20"))
	assert_eq(root.theme, shared, "existing controls retain the same live theme")
	UiStyle.apply_faction(root, "ashen")
	assert_eq(title.get_theme_color("font_color"), Color("#e65249"))
	assert_eq(panel.get_theme_stylebox("panel").bg_color, Color("#240a10"))
	UiStyle.apply_faction(root, "unknown")
	assert_eq(UiStyle.faction, "concord", "unknown IDs safely use Concord")
	root.free()


func test_all_six_factions_have_independent_panel_art() -> void:
	for faction in ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch"]:
		assert_true(Art.has_sprite("ui_panel_" + faction), faction)
		assert_true(UiStyle.palette(faction).has("material"), faction)
		var p := UiStyle.palette(faction)
		var foreground := Color(p["accent"]).srgb_to_linear().get_luminance()
		var background := Color(p["panel"]).srgb_to_linear().get_luminance()
		assert_true((foreground + 0.05) / (background + 0.05) >= 4.5, faction + " accent contrast")


func test_cursors_match_towns_pickups_encounters_and_guards() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	s.current_player()["fog"].reveal(Vector2i(12, 8), 40)
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(1, 8)), "town")
	assert_eq(AdventureCursor.action_for(s, "hero_wren", s.hero("hero_maelis").pos), "select")
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(3, 6)), "pickup")
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(12, 8)), "attack")
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(3, 8)), "move")
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(3, 4)), "capture", "unowned mines use the capture flag")
	s.state.map.objects["mine_wood"]["owner"] = s.state.current_player
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(3, 4)), "move", "owned mines are not presented as unclaimed pickups")
	s.state.map.objects["cursor_town_fixture"] = {"id": "cursor_town_fixture", "type": "town", "owner": -1, "pos": [3, 8], "garrison": []}
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(3, 8)), "capture", "unguarded neutral towns use the capture flag")
	s.state.map.objects.erase("cursor_town_fixture")
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(5, 0)), "blocked")
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(-1, 8)), "default")
	for object in s.state.map.objects.values():
		if object.get("type", "") == "encounter":
			var pos := AdventureMap.object_pos(object)
			if not s.plan_path("hero_wren", pos)["path"].is_empty():
				assert_eq(AdventureCursor.action_for(s, "hero_wren", pos), "encounter")
				break
	s.state.map.objects["cursor_site_fixture"] = {"id": "cursor_site_fixture", "type": "site", "pos": [3, 8], "site": "outcast_camp", "guard": []}
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(3, 8)), "capture", "unguarded dwellings use the capture flag")
	s.state.map.objects["cursor_site_fixture"]["owner"] = s.state.current_player
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(3, 8)), "encounter", "owned dwellings remain interactive")
	s.state.map.objects.erase("cursor_site_fixture")
	s.hero("hero_wren").movement_left = 0
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(3, 8)), "blocked")
	s.hero("hero_wren").pos = Vector2i(1, 8)
	assert_eq(AdventureCursor.action_for(s, "hero_wren", Vector2i(1, 8)), "town", "visiting a town needs no movement")


func test_shrouded_targets_never_reveal_their_action() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	s.current_player()["fog"].explored.fill(0)
	for pos in [Vector2i(12, 8), Vector2i(22, 2), Vector2i(3, 6), Vector2i(0, 0)]:
		assert_eq(AdventureCursor.action_for(s, "hero_wren", pos), "move", "no hidden guards, towns, resources or terrain leaks")


func test_every_cursor_has_a_fixed_in_bounds_hotspot() -> void:
	for action in AdventureCursor.ACTIONS:
		var info := Art.sprite_info("cursor_" + action)
		var hotspot: Array = info.get("hotspot", [0, 0])
		assert_eq(Vector2(hotspot[0], hotspot[1]), Vector2(2, 2), action)
		assert_eq(Art.sprite("cursor_" + action).get_size(), Vector2(40, 40), action)
		var image := Art.sprite("cursor_" + action).get_image()
		assert_eq(image.get_pixel(2, 2).a, 1.0, action + " click tip is visible")
		assert_eq(image.get_pixel(0, 0).a, 0.0, action + " outer margin stays transparent")
