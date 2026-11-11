extends SceneTree
## Phone-sized screenshots of the main screens, with touch UI forced on.
## xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 2532x1170 \
##     --script res://tools/phone_screenshots.gd -- /tmp/phone
## The default size is an iPhone 12 Pro held sideways (2532x1170 pixels, 844x390 points).

var main: Node
var out_dir := "/tmp/phone"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	TouchGestures.force_touch_ui = true
	# iPhone 12 Pro held sideways: 390 points tall, notch side 47 pt, home indicator 21 pt.
	TouchLayout.simulated_points_height = 390.0
	TouchLayout.simulated_insets = Vector4(47, 0, 47, 21)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames(14)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("PHONE_SCREEN ", name)


func _run() -> void:
	await _frames(8)
	await _shot("01_main_menu")
	main.menu._show_setup()
	await _shot("02_new_game")
	main.menu.hide()
	main.start_new_game("ember_ford", 11, {"players": [{"type": "human", "faction": "concord"}]})
	await _frames(4)
	for d in [main.chapter_dialog, main.curtain]:
		if d.visible:
			d.hide()
	main._set_busy(false)
	await _shot("03_adventure")
	main._open_hero_screen()
	await _shot("04_hero")
	main.hero_screen.hide()
	main._set_busy(false)
	main._open_town()
	await _shot("05_town")
	main.town_screen.hide()
	main._set_busy(false)
	var target := ""
	for id in main.session.state.map.objects.keys():
		if String(main.session.state.map.objects[id].get("type", "")) == "neutral_army":
			target = String(id)
			break
	if target != "":
		main._pending_battle = target
		main._show_forecast()
		await _shot("06_forecast")
		main.panels.hide()
	main._open_saves("save")
	await _shot("07_save")
	print("PHONE_SCREENSHOTS_OK")
	AudioManager.stop_all()
	await _frames(3)
	quit(0)
