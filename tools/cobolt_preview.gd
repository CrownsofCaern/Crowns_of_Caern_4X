extends SceneTree
## Real-renderer QA of peaceful visits, stock, uncertain scouts and robbery.
var main: Node
var out_dir := "/tmp/cobolt-preview"

func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	_run()

func _frames() -> void:
	for i in 16:
		await process_frame

func _shot(name: String) -> void:
	await _frames()
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))

func _button(text: String) -> Button:
	for b in main.site_dialog.find_children("*", "Button", true, false):
		if b.text.begins_with(text):
			return b
	return null

func _run() -> void:
	await _frames()
	main.start_new_game("twin_marches", 3, {})
	var s: GameSession = main.session
	var h := s.hero("hero_west")
	var p := s._free_tile_near(h.pos)
	var obj := {"id": "preview_cobolt", "type": "site", "site": "cobolt_exchange", "pos": [p.x, p.y]}
	MapSites.normalize(obj, s.data)
	s.state.map.add_object(obj)
	for res in s.data.resource_order:
		s._bank(0).add(res, 100000)
	h.movement_left = 1000
	s.state.player(0)["fog"].reveal(p, 7)
	main._select_hero(h.id)
	main._refresh()
	await main._on_tile_clicked(p)
	await main._on_tile_clicked(p)
	assert(h.pos == p and main.site_dialog.visible)
	await _shot("01_shop")
	_button("Trade").pressed.emit()
	await _frames()
	assert(obj["stock"][2]["remaining"] == obj["stock"][2]["cap"] - 1)
	_button("Scout").pressed.emit()
	await _shot("02_scouted")
	_button("Rob").pressed.emit()
	await _shot("03_robbery")
	assert(main.panels.visible)
	main.panels._cancel()
	assert(not obj["plundered"] and obj["hostile_players"].is_empty())
	main.site_dialog.open(s, "preview_cobolt", h.id)
	h.army = Army.from_pairs([["cobolt_vault_warden", 100]])
	obj["guard"] = [["cobolt_pack_runner", 1]]
	s.attack(h.id, "preview_cobolt")
	main.site_dialog.open(s, "preview_cobolt", h.id)
	await _shot("04_plundered")
	print("Cobolt preview saved to ", out_dir)
	quit()
