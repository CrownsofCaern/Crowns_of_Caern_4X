extends SceneTree
## Renders each faction's town view (starting, developing and complete) for art review.
## xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/town_scene_review.gd -- /tmp/towns

var main: Node
var out := "/tmp/towns/"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames(15)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("TOWN_SCREEN ", name)


func _run() -> void:
	await _frames(5)
	for faction in ["concord", "thornwood", "hollow", "ashen", "forge", "frostmarch"]:
		main.start_new_game("ember_ford", 11, {"players": [{"type": "human", "faction": faction}]})
		main._open_town()
		var town: Dictionary = main.session.town(main.town_screen.town_id)
		await _shot(faction + "-start")
		var all: Array = main.data.town_types[faction]["buildings"].keys()
		town["built"] = all.slice(0, all.size() / 2)
		main.town_screen.refresh()
		await _shot(faction + "-half")
		town["built"] = all
		main.town_screen.refresh()
		await _shot(faction + "-complete")
		main.town_screen.close_screen()
		main._set_busy(false)
	quit()
