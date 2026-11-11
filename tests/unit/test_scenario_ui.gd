extends "res://tests/test_case.gd"


func _buttons(node: Node) -> Array:
	var out := []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_buttons(child))
	return out


func test_quest_dialog_routes_acceptance_to_session() -> void:
	var s := GameSession.new_game(data, "last_watch", 7)
	s.state.day = 9
	s.hero("hero_watch").pos = Vector2i(8, 6)
	var dialog := ScenarioDialog.new()
	dialog.build(data, 620)
	dialog.open(s, "hero_watch", "site_pact")
	var accept := _buttons(dialog).filter(func(b): return b.text == "Accept the quest")
	assert_eq(accept.size(), 1)
	accept[0].pressed.emit()
	assert_eq(ScenarioQuests.status(s.state, "reedhaven_pact"), "active")
	assert_true(s.state.map.objects.has("site_pact"))
	var deliver := _buttons(dialog).filter(func(b): return b.text == "Return the relic")
	assert_eq(deliver.size(), 1)
	assert_true(deliver[0].disabled, "the UI explains that this hero must carry the relic")
	dialog.free()


func test_menu_filters_mode_and_preserves_difficulty_metadata() -> void:
	var menu := MainMenu.new()
	menu.build(data)
	menu._seed_edit.text = "7"
	assert_eq(menu.current_mode(), "conquest", "New Game starts on conquest")
	menu.select_mode("defence")
	assert_eq(menu.current_mode(), "defence")
	assert_true(menu._maps.size() >= 1)
	assert_true(menu._maps.all(func(m): return m["mode"] == "defence"))
	assert_true(bool(menu._maps[0].get("random", false)), "the random mission comes first")
	assert_true(menu._random_row.visible, "a template mission takes the random-map options")
	assert_false(menu._random_fields["teams"].visible, "missions have fixed sides")
	assert_eq(menu._random_keys["players"].max(), GameSetup.SCENARIO_MAX_PLAYERS)
	assert_true(menu._slot_rows[1]["type"].disabled)
	assert_true(menu._slot_rows[2]["faction"].disabled)
	var difficulty: OptionButton = menu._slot_rows[1]["difficulty"]
	for i in difficulty.item_count:
		if difficulty.get_item_metadata(i) == "hard":
			difficulty.select(i)
	assert_eq(menu.current_setup()["players"][1]["difficulty"], "hard")
	assert_true(menu._validate())
	var id := GameSetup.map_id_for(menu._maps[0], 7)
	assert_true(id.begins_with("scenario:defence_v2:random_"), id)
	assert_eq(id.split(":").size(), 4)
	menu.set_random_options({"size": "l", "players": 3, "family": "hub"})
	assert_eq(GameSetup.map_id_for(menu._selected_map(), 7), "scenario:defence_v2:random_l_3p_normal_normal_hub:7")
	menu.select_mode("labyrinth")
	assert_true(menu._maps.size() >= 1)
	assert_true(menu._maps.all(func(m): return m["mode"] == "labyrinth"))
	assert_false(menu._random_row.visible, "an expedition carves its own maze")
	assert_eq(GameSetup.map_id_for(menu._maps[0], 7), "scenario:labyrinth_v2:7")
	menu.free()


func test_mission_sprites_resolve_and_hud_exposes_objectives() -> void:
	var s := GameSession.new_game(data, "last_watch", 7)
	for obj in s.state.map.objects.values():
		if obj.has("sprite"):
			assert_true(Art.sprite(String(obj["sprite"])) != null, String(obj["id"]))
	(s.current_player()["fog"] as FogOfWar).reveal(Vector2i(6, 6), 2)
	var tip := MapTipInfo.describe(s, Vector2i(6, 6), s.hero("hero_watch"))
	assert_true(JSON.stringify(tip).contains("pact"), "the neutral town must explain its quest requirement")
	var hud := Hud.new()
	hud.build(data)
	hud.minimap.bind(s)
	hud.refresh(s, s.hero("hero_watch"))
	assert_true(hud._objectives_btn.visible)
	assert_true(hud._objectives_btn.text.contains("0/2"))
	var signalled := {"yes": false}
	hud.objectives_pressed.connect(func(): signalled["yes"] = true)
	hud._objectives_btn.pressed.emit()
	assert_true(signalled["yes"])
	hud.free()
