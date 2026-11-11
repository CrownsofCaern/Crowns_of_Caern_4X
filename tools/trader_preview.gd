extends SceneTree
## Real-renderer QA: godot --path . --rendering-method gl_compatibility
## --script res://tools/trader_preview.gd -- /tmp/trader-preview

var main: Node
var out_dir := "/tmp/trader-preview"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	_run()


func _frames(n: int = 12) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func _run() -> void:
	await _frames()
	main.start_new_game("twin_marches", 3, {})
	var s: GameSession = main.session
	var h := s.hero("hero_west")
	var p := s._free_tile_near(h.pos)
	var obj := {"id": "preview_trader", "type": "site", "site": MapTraders.SITE_ID,
		"pos": [p.x, p.y], "stock": MapTraders.make_stock(s.data, GameRng.new(42))}
	s.state.map.add_object(obj)
	MapSites.normalize(obj, s.data)
	s._bank(0).add("gold", 25000)
	s.state.player(0)["fog"].reveal(p, 7)
	main._select_hero(h.id)
	main._refresh()
	await _shot("01_trader_on_map")
	await main._on_tile_clicked(p) # plan the route
	await main._on_tile_clicked(p) # walk there and open the integrated shop
	assert(h.pos == p and main.site_dialog.visible, "map arrival opens the shop")
	await _shot("02_trader_shop")
	var artifacts_before := h.all_artifacts(s.data).size()
	var fog: FogOfWar = s.state.player(0)["fog"]
	var tiles_before := fog.explored_count()
	var buttons: Array[Node] = main.site_dialog.find_children("*", "Button", true, false)
	buttons[1].pressed.emit() # first artifact, through the actual Buy button
	assert(h.all_artifacts(s.data).size() == artifacts_before + 1)
	buttons = main.site_dialog.find_children("*", "Button", true, false)
	assert(buttons[1].disabled, "purchased artifact is now sold out")
	buttons[0].pressed.emit() # chart remains visible above the artifact list
	assert(fog.explored_count() == tiles_before + 40)
	main.site_dialog._lines = ["Chart purchased. Uncovered 40 tiles."]
	main.site_dialog._render()
	await _shot("03_after_purchase")
	main.site_dialog._close()
	await _shot("04_chart_revealed")
	await main._on_tile_clicked(p)
	assert(main.site_dialog.visible, "standing hero can reopen the trader")
	print("Trader preview saved to ", out_dir)
	quit()
