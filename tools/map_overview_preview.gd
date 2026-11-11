extends SceneTree
## Render the shared overview in setup and in the HUD, at the normal window size.
## godot --path . --script res://tools/map_overview_preview.gd

func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/" + name + ".png")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.menu.open(false)
	main.menu._show_setup()
	main.menu._seed_edit.text = "12345"
	main.menu._map_pick.select(0)
	main.menu.set_random_options({"players": 4})
	await _shot("map_overview_setup")
	main.start_new_game("twin_marches", 11, {})
	await _shot("map_overview_hud")
	AudioManager.stop_all()
	quit()
