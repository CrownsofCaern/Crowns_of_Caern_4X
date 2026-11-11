extends SceneTree
## Render setup, survival, quest dialogue and the generated expedition for QA.
var main: Node
var directory := "/tmp/reignem-gameplay-variety"


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int = 12) -> void:
	for i in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames()
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	root.show()
	root.grab_focus()
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	await _frames()
	main.menu.open(false)
	main.menu._show_setup()
	main.menu.select_mode("survival")
	main.menu._seed_edit.text = "7"
	main.menu._refresh_preview()
	await _shot("01_adventure_setup")
	main.start_new_game("last_watch", 7, {})
	await _shot("02_survival")
	main._open_objectives()
	await _shot("03_objectives")
	main.scenario_dialog.hide()
	main._set_busy(false)
	main.session.hero("hero_watch").pos = Vector2i(8, 6)
	main._refresh()
	main._open_objectives("site_pact")
	await _shot("04_pact")
	main.scenario_dialog.hide()
	main._set_busy(false)
	main.start_new_game("scenario:labyrinth_v1:7", 7, {})
	main.look_at_tile(Vector2i(13, 13))
	await _shot("05_labyrinth")
	AudioManager.stop_all()
	main.queue_free()
	await _frames(2)
	GameData._default = null
	quit()
