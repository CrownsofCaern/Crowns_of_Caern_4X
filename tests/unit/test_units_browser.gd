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


func test_upgrade_requires_its_own_building() -> void:
	var session := GameSession.new_game(data, "ember_ford", 11)
	var screen := TownScreen.new()
	screen.build_ui(data)
	screen.session = session
	screen.town_id = "town_greyhold"
	screen.refresh()
	var town := session.town(screen.town_id)
	var upgrade := screen._unit_building(town, "pike_veteran")
	assert_true(upgrade != "")
	screen._unit_index = screen._town_units(town).find("pike_veteran")
	screen._fill_units(town)
	assert_eq(screen._unit_content.get_child_count(), 3)
	town["built"].append(upgrade)
	screen._fill_units(town)
	assert_true(screen._unit_content.get_child_count() > 3)
	screen.free()


func test_dwelling_preview_and_tooltip_identify_recruit() -> void:
	var session := GameSession.new_game(data, "ember_ford", 11)
	var screen := TownScreen.new()
	screen.build_ui(data)
	screen.session = session
	screen.town_id = "town_greyhold"
	screen.refresh()
	assert_true(screen._scene._building_tooltip("c_dw2").contains("Longbowman"))
	screen._inspect_building("c_dw2")
	var art := screen._preview_content.get_child(1)
	assert_true(art is TextureRect)
	assert_eq(art.get_child_count(), 1)
	screen.free()
