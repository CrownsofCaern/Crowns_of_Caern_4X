extends "res://tests/test_case.gd"


func test_unit_browser_hides_locked_stats_and_unlocks_with_dwelling() -> void:
	var session := GameSession.new_game(data, "ember_ford", 11)
	var screen := TownScreen.new()
	screen.build_ui(data)
	screen.session = session
	screen.town_id = "town_greyhold"
	screen.refresh()
	var town := session.town(screen.town_id)
	var units := screen._town_units(town)
	var index := units.find("longbowman")
	assert_true(index >= 0)
	screen._unit_index = index
	screen._fill_units(town)
	assert_eq(screen._unit_building(town, "longbowman"), "c_dw2")
	assert_eq(screen._unit_content.get_child_count(), 3, "locked unit hides statistics and abilities")
	town["built"].append("c_dw2")
	screen._fill_units(town)
	assert_true(screen._unit_content.get_child_count() > 3, "built dwelling reveals unit details")
	screen.free()


func test_touch_town_places_recruitment_in_a_tab() -> void:
	TouchGestures.force_touch_ui = true
	var session := GameSession.new_game(data, "ember_ford", 11)
	var screen := TownScreen.new()
	screen.build_ui(data)
	screen.session = session
	screen.town_id = "town_greyhold"
	screen.refresh()
	assert_eq(String(screen._right.get_parent().name), "Recruit & town")
	assert_true(screen._next_btn.custom_minimum_size.y >= 44)
	screen.free()
	TouchGestures.force_touch_ui = false


func test_touch_hero_and_hud_use_scrollable_layouts() -> void:
	TouchGestures.force_touch_ui = true
	var session := GameSession.new_game(data, "ember_ford", 11)
	var hero_screen := HeroScreen.new()
	hero_screen.build(data, 760)
	hero_screen.session = session
	hero_screen.hero_id = "hero_wren"
	hero_screen.refresh()
	assert_true(hero_screen._body.get_parent() is ScrollContainer)
	assert_eq(hero_screen.exchange.columns, 5)
	var hud := Hud.new()
	hud.build(data)
	hud.refresh(session, session.hero("hero_wren"))
	assert_true(hud._roster.get_parent().get_parent() is ScrollContainer)
	assert_true(hud._end_turn.custom_minimum_size.y >= 44)
	hud.free()
	hero_screen.free()
	TouchGestures.force_touch_ui = false
