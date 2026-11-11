extends "res://tests/test_case.gd"


func test_detailed_map_keeps_every_unexplored_pixel_hidden() -> void:
	var session := GameSession.new_game(data, "ember_ford", 11)
	var mm := Minimap.new()
	mm.bind(session)
	var fog: FogOfWar = session.current_player()["fog"]
	fog.explored.fill(0)
	mm.refresh()
	var image := mm.overview_image()
	assert_eq(image.get_size(), Vector2i(session.state.map.width, session.state.map.height) * Minimap.DETAIL)
	for y in image.get_height():
		for x in image.get_width():
			if not image.get_pixel(x, y).is_equal_approx(Minimap.FOG):
				assert_true(false, "hidden tile detail leaked at %d,%d: %s expected %s" % [x, y, image.get_pixel(x, y).to_html(), Minimap.FOG.to_html()])
				mm.free()
				return
	fog.reveal(Vector2i(1, 8), 2)
	mm.refresh()
	assert_ne(mm.overview_image().get_pixel(Minimap.DETAIL, 8 * Minimap.DETAIL), Minimap.FOG)
	mm.free()


func test_preview_preserves_slot_numbers_and_closed_slots_become_neutral() -> void:
	var def := data.load_map("twin_marches")
	var original := JSON.stringify(def)
	var mm := Minimap.new()
	var players := [{"type": "closed", "color": "#c94040"}, {"type": "human", "color": "#4488d0"}]
	mm.bind_preview(def, data, players)
	assert_eq(mm._starts.size(), 2)
	assert_eq(mm._starts[1]["slot"], 1)
	assert_eq(mm._owner_color(int(def["players"][0]["id"])), Minimap.NEUTRAL)
	assert_eq(mm._owner_color(int(def["players"][1]["id"])), Color("#4488d0"))
	players[1]["color"] = "#49a85a"
	mm.update_preview_players(players)
	assert_eq(mm._owner_color(int(def["players"][1]["id"])), Color("#49a85a"))
	assert_eq(mm.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(mm.custom_minimum_size.x <= 320 and mm.custom_minimum_size.y <= 190)
	assert_eq(JSON.stringify(def), original, "preview must not mutate the definition")
	mm.free()


func test_setup_preview_and_begin_use_the_same_generated_map() -> void:
	var menu := MainMenu.new()
	menu.build(data)
	menu._show_setup()
	for i in menu._maps.size():
		if menu._maps[i]["generated"]:
			menu._map_pick.select(i)
			break
	menu._seed_edit.text = "the cinder road"
	menu._fill_slots()
	var seed_value := menu.preview_seed()
	var preview := menu._preview_definition
	var chosen := []
	menu.start_requested.connect(func(id, seed_number, setup): chosen.append([id, seed_number, setup]))
	menu._start()
	assert_eq(chosen.size(), 1)
	if chosen.size() == 1:
		assert_eq(chosen[0][1], seed_value)
		var started := data.load_map(chosen[0][0])
		assert_eq(started["terrain"], preview["terrain"])
		assert_eq(started["roads"], preview["roads"])
		assert_eq(started["objects"], preview["objects"])
	# Empty seed also remains stable between preview and launch.
	menu._seed_edit.text = ""
	menu._refresh_preview()
	var random_seed := menu.preview_seed()
	menu._start()
	assert_eq(chosen.back()[1], random_seed)
	assert_eq(menu._map_preview._players[0]["color"], menu.current_setup()["players"][0]["color"])
	menu._slot_rows[0]["color"].select(2)
	menu._validate()
	assert_eq(menu._map_preview._players[0]["color"], GameSetup.PLAYER_COLORS[2])
	menu.free()


func test_overview_fits_maps_larger_than_the_hud() -> void:
	var def := {"id": "large", "width": 300, "height": 2, "terrain": [".".repeat(300), ".".repeat(300)]}
	var mm := Minimap.new()
	mm.bind_preview(def, data, [], Minimap.MAX_SIZE)
	assert_true(mm.custom_minimum_size.x <= Minimap.MAX_SIZE.x)
	assert_eq(mm.tile_at(Vector2(9999, 9999)), Vector2i(299, 1))
	mm.free()
