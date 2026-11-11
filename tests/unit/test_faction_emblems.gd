extends "res://tests/test_case.gd"


func test_emblems_are_distinct_and_picker_shows_them() -> void:
	var factions := GameSetup.playable_factions(data)
	assert_eq(factions.size(), 8)
	var seen := {}
	var menu := MainMenu.new()
	menu.build(data)
	menu._show_setup()
	var picker: OptionButton = menu._slot_rows[0]["faction"]
	for i in factions.size():
		var faction: String = factions[i]
		var emblem := Art.faction_emblem(faction)
		assert_true(emblem != null, faction)
		if emblem != null:
			assert_false(seen.has(emblem.resource_path), faction)
			seen[emblem.resource_path] = true
		assert_true(picker.get_item_icon(i) != null, faction)
		assert_eq(picker.get_item_icon(i).get_size(), Vector2(28, 28))
	assert_true(Art.faction_emblem("wilds") == null)
	menu.free()


func test_hud_and_town_emblems_follow_faction() -> void:
	var session := GameSession.new_game(data, "twin_marches", 5, {"players": [
		{"type": "human", "faction": "darkelf"}, {"type": "computer", "faction": "fishmen"}]})
	var hud := Hud.new()
	hud.build(data)
	hud.minimap.bind(session)
	hud.refresh(session, session.state.heroes_of(0)[0])
	assert_eq(hud._faction_emblem.texture, Art.faction_emblem("darkelf"))
	session.state.current_player = 1
	hud.refresh(session, session.state.heroes_of(1)[0])
	assert_eq(hud._faction_emblem.texture, Art.faction_emblem("fishmen"))
	var hero_screen := HeroScreen.new()
	hero_screen.build(data)
	hero_screen.session = session
	hero_screen.hero_id = session.state.heroes_of(1)[0].id
	hero_screen.refresh()
	var hero_emblem := hero_screen.find_child("FactionEmblem", true, false) as TextureRect
	assert_true(hero_emblem != null)
	if hero_emblem != null:
		assert_eq(hero_emblem.texture, Art.faction_emblem("fishmen"))
	hero_screen.free()
	var town := TownScreen.new()
	town.build_ui(data)
	town.session = session
	town.town_id = session.towns_of(1)[0]["id"]
	town.refresh()
	assert_eq(town._faction_emblem.texture, Art.faction_emblem("fishmen"))
	town.town_id = session.towns_of(0)[0]["id"]
	town.refresh()
	assert_eq(town._faction_emblem.texture, Art.faction_emblem("darkelf"))
	town.free()
	hud.free()
