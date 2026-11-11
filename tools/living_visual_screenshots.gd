extends SceneTree
## Real OpenGL review of construction states, terrain and single-image motion.

const OUT := "res://docs/art/production/living-world/"
var main: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
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
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("VISUAL_SCREEN ", name)


func _run() -> void:
	await _frames(5)
	main.start_new_game("ember_ford", 11, {"players": [{"type": "human", "faction": "concord"}]})
	main.session.current_player()["fog"].reveal(Vector2i(12, 8), 50)
	main._refresh()
	await _shot("terrain-map")
	main._open_town("town_greyhold")
	await _shot("concord-starting-town")
	var town: Dictionary = main.session.town("town_greyhold")
	town["built"] = ["c_hall", "c_court", "c_tavern", "c_market", "c_palisade", "c_keep", "c_dw1", "c_dw2", "c_dw3", "c_dw4", "c_dw5"]
	main.town_screen.refresh()
	await _shot("concord-developing-town")
	town["built"] = main.data.town_types["concord"]["buildings"].keys()
	main.town_screen.refresh()
	await _shot("concord-complete-town")
	main.town_screen._inspect_building("c_up8")
	await _shot("concord-building-list")
	main.town_screen.close_screen()
	main._set_busy(false)
	main.start_new_game("ember_ford", 11, {"players": [{"type": "human", "faction": "hollow"}]})
	main._open_town()
	await _shot("hollow-fallback-list")
	main.town_screen.close_screen()
	main._set_busy(false)
	# Isolated enlarged motion study, using the same Sprite2D and update code.
	main.hide()
	for child in main.get_children():
		if child is CanvasLayer:
			child.hide()
	var demo := MapView.new()
	root.add_child(demo)
	var s := GameSession.new_game(main.data, "ember_ford", 11)
	demo.bind(s)
	demo._ground.hide()
	demo._deco.hide()
	demo._fog.hide()
	demo._roads.hide()
	demo._under.hide()
	demo._overlay.hide()
	demo._glow.hide()
	for blend in demo._blends.values():
		blend.hide()
	for c in demo._objects.get_children():
		c.hide()
	var hero := demo._make_sprite(Art.hero_sprite_id("knight"))
	hero.position = Vector2(220, 300)
	hero.set_meta("hero", "review")
	hero.set_meta("motion_kind", "hero")
	hero.scale *= 3.0
	hero.set_meta("rest_scale", hero.scale)
	demo._objects.add_child(hero)
	demo._animating["review"] = true
	var creature := demo._make_sprite("creature_pike_militia")
	creature.position = Vector2(470, 300)
	creature.scale *= 3.0
	creature.set_meta("rest_scale", creature.scale)
	demo._objects.add_child(creature)
	demo.set_process(false)
	for i in 48:
		demo._motion_time = i * TAU / 1.65 / 48.0
		demo._process(0.0)
		await _shot("motion-%02d" % i)
	AudioManager.stop_all()
	quit(0)
