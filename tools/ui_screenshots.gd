extends SceneTree
## Real renderer review: DISPLAY=:91 godot --path . --script res://tools/ui_screenshots.gd

var main: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/art/production/ui")
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/art/production/ui/" + name + ".png")
	print("UI_SCREEN ", name)


func _run() -> void:
	await _frames(5)
	for faction in ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch"]:
		main.start_new_game("ember_ford", 11, {"players": [{"type": "human", "faction": faction}]})
		await _shot(faction + "-hud")
		main._open_hero_screen()
		await _shot(faction + "-hero")
		main.hero_screen.hide()
		main._set_busy(false)
	main.start_new_game("twin_marches", 11, {"players": [
		{"type": "human", "faction": "hollow"}, {"type": "human", "faction": "ashen"}]})
	main.curtain.hide()
	main._begin_human_turn()
	main._end_turn()
	if UiStyle.faction != "ashen" or not main.curtain.visible or main.map_view.visible:
		push_error("Hot-seat faction or privacy curtain failed")
		quit(1)
		return
	await _shot("hotseat-ashen-curtain")
	main.curtain.hide()
	main._begin_human_turn()
	await _shot("hotseat-ashen-hud")
	print("UI_SCREENSHOTS_OK")
	AudioManager.stop_all()
	await _frames(3)
	quit(0)
