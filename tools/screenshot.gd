extends SceneTree
## Smoke test + screenshots with a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/screenshot.gd -- <out_dir>
## Launches the main scene, plans a route, marches to the wolves, opens the
## forecast, attacks, opens the town screen and the hero screen (army
## management), and saves a PNG at each stage.

var out_dir := "res://reports/screens"
var main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") else out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(12)   # lets the short panel fade-ins finish
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


func _run() -> void:
	await _frames(5)
	# The tour uses both heroes the map places, so it plays the map as defined
	# (a standard start keeps one hero for most factions).
	main.start_new_game(main.MAP_ID, 7, {})
	await _frames(5)
	main.session.hero("hero_wren").pos  # sanity
	await _shot("01_start")
	# The hover card: a neutral army in sight (rough count and a worded
	# verdict), a mine and an encounter (what they are and do).
	for shot in [["01b_enemy_hover", Vector2i(5, 14)], ["01c_mine_hover", Vector2i(6, 11)], ["01d_encounter_hover", Vector2i(7, 10)]]:
		var tile: Vector2i = shot[1]
		var px: Vector2 = main.map_view.get_global_transform_with_canvas() * (main.map_view.tile_to_px(tile) + Vector2(MapView.TILE, MapView.TILE) * 0.5)
		main.get_viewport().warp_mouse(px)
		await _frames(2)
		main.map_view.hovered = tile
		main._on_tile_hovered(tile)
		await _shot(shot[0])
	main.intel_tip.hide()
	main._on_tile_clicked(Vector2i(12, 8))
	await _shot("02_path_preview")
	await main._on_tile_clicked(Vector2i(12, 8))
	await _frames(10)
	await _shot("03_forecast")
	main._on_forecast_scout()
	await _frames(10)
	await _shot("03b_forecast_scouted")
	main.panels.hide()
	await main._on_attack_confirmed()
	await _frames(5)
	await _shot("04_battle_report")
	main.panels.show_details()
	await _shot("04b_battle_details")
	main.panels.hide()
	# The live battle view, replaying the same result: early, mid-fight, end.
	main.battle_viewer.play(main.panels.last_result, "Wren")
	for at in [["04c_live_battle_start", 40], ["04d_live_battle_melee", 110], ["04e_live_battle_late", 200]]:
		await _frames(at[1])
		await _shot(at[0])
	main.battle_viewer.skip_to_end()
	await _frames(5)
	main._set_busy(false)
	main._end_turn()
	main._on_tile_clicked(Vector2i(15, 3))
	await main._on_tile_clicked(Vector2i(15, 3))
	await _frames(5)
	await _shot("05_day2_explored")
	# Town screen: raise a building, recruit, then show the screen.
	var s: GameSession = main.session
	s.build("town_greyhold", "c_dw2")
	s.recruit("town_greyhold", "pike_militia", 6)
	# Wren visits the town so the garrison exchange shows both armies.
	var wren: Hero = s.hero("hero_wren")
	var wren_was := wren.pos
	wren.pos = Vector2i(1, 8)
	main._refresh()
	main._open_town("town_greyhold")
	main.town_screen.exchange.click("hero_wren", 1)
	await _frames(5)
	await _shot("06_town")
	main.town_screen.close_screen()
	# Hero overview with army management: split some pikes into the garrison.
	for art in ["bleeding_glaive", "scarred_plate", "crowcrest_helm", "vigil_pavise", "outriders_greaves", "lantern_of_the_lost",
			"standard_of_the_hold", "notched_falchion", "sceptre_of_the_pyre", "bone_dice"]:
		if main.data.artifacts.has(art):
			wren.give_artifact(art, main.data)
	main._open_hero_screen()
	main.hero_screen.exchange.click("hero_wren", 0)
	main.hero_screen.exchange.click(GameSession.garrison_ref("town_greyhold"), 3, true)
	main.hero_screen.exchange.click("hero_wren", 2)
	await _frames(5)
	await _shot("19_hero_screen")
	main.hero_screen.close_screen()
	wren.pos = wren_was
	main._refresh()
	await _frames(2)
	await _shot("07_map_towns")
	# Second hero: select, walk into an encounter, choose, then level up.
	main._select_hero("hero_maelis")
	main._on_tile_clicked(Vector2i(7, 10))
	await main._on_tile_clicked(Vector2i(7, 10))
	await _frames(5)
	await _shot("08_encounter")
	main._on_encounter_choice(2)
	await _frames(5)
	await _shot("09_encounter_result")
	main.encounter_dialog.hide()
	main._set_busy(false)
	main.session.hero("hero_maelis").add_xp(1000, main.data)
	main._refresh()
	main._open_level_up()
	await _frames(5)
	await _shot("10_level_up")
	main.level_up.hide()
	main._set_busy(false)
	var wren_pos: Vector2i = main.session.hero("hero_wren").pos
	var slice_day: int = main.session.state.day
	# Duel map against the computer: pass a few days and let the AI play.
	main._start(GameSession.new_game(main.data, "twin_marches", 3))
	for i in 4:
		main._end_turn()
	await _frames(5)
	await _shot("11_duel_vs_ai")
	# Game flow: title screen, new-game setup, save slots, hot-seat, end screen.
	main.menu.open(true)
	await _shot("12_main_menu")
	main.menu.show_campaigns()
	await _shot("12b_campaigns")
	main.menu.open(true)   # back to the title, as the Back button does
	main.menu._show_setup()
	# The random map with its options: a four-player hub in two teams, two humans side by side.
	main.menu._map_pick.select(0)
	main.menu.set_random_options({"size": "m", "players": 4, "family": "hub", "teams": 2, "monsters": "normal", "treasure": "rich"})
	main.menu._slot_rows[1]["type"].select(0)
	main.menu._validate()
	await _shot("13_new_game_setup")
	# A curated seed: a fixed, named map.
	main.menu._map_pick.select(1)
	main.menu._fill_slots()
	await _shot("13b_curated_map_setup")
	# A scenario mode: the random townless start.
	main.menu.select_mode("townless")
	await _shot("13c_scenario_setup")
	main.menu.select_mode("conquest")
	var hotseat := GameSetup.default_setup(GameSetup.map_entry(main.data, "mournfield"))
	hotseat["players"][1]["type"] = "human"
	hotseat["players"][3]["type"] = "closed"
	for i in 3:
		hotseat["players"][i]["team"] = [1, 1, 2][i]
	main.menu.start_requested.emit("mournfield", 11, hotseat)
	await _frames(5)
	await _shot("14_hotseat_curtain")
	main.curtain.hide()
	main._begin_human_turn()
	await _frames(3)
	await _shot("15_mournfield")
	main._open_town("town_lanternholm")
	await _frames(3)
	await _shot("15b_ally_courier")
	main.town_screen.close_screen()
	main._open_saves("save")
	await _shot("16_save_slots")
	main.save_dialog.hide()
	main._set_busy(false)
	# Win: the human hero beats the second player's hero and their town falls.
	var s2: GameSession = main.session
	for i in [1, 2]:
		var town: Dictionary = s2.towns_of(i)[0]
		town["owner"] = 0
		for h in s2.state.heroes_of(i):
			h.alive = false
	VictoryRules.update(s2)
	main._check_game_over()
	await _frames(3)
	await _shot("17_game_over")
	main.sound_dialog.open()
	await _shot("18_sound_settings")
	main.sound_dialog.hide()
	print("SMOKE_OK day=%d hero=%s duel_day=%d" % [slice_day, wren_pos, main.session.state.day])
	AudioManager.stop_all()
	await _frames(3)
	quit(0)
