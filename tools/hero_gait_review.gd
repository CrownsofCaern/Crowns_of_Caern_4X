extends SceneTree
## Verify actual route playback uses gait frames, fixed scale and stable banner placement.

var main: Node


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for frame in 5:
		await process_frame
	main.start_new_game("ember_ford",11,{"players":[{"type":"human","faction":"concord"}]})
	var view: MapView = main.map_view
	var hero: Hero = main.session.hero("hero_wren")
	var from := hero.pos
	var steps := [Vector2i(2,8),Vector2i(3,8),Vector2i(4,8),Vector2i(5,8)]
	hero.pos = steps[-1]
	view.animate_hero(hero.id,from,steps)
	DirAccess.make_dir_recursive_absolute("/tmp/crowns-hero-frames")
	var checked := false
	for frame in 32:
		await process_frame
		await RenderingServer.frame_post_draw
		var sprite: Sprite2D = view._hero_sprites[hero.id]
		if view._animating.has(hero.id):
			var rest: Vector2 = sprite.get_meta("rest_scale")
			if sprite.scale != rest or sprite.offset != Vector2(-160,-207) or (sprite.get_child(0) as Sprite2D).position.y != 0.0:
				push_error("Hero pose/flag shifted while gait was playing")
				quit(1)
				return
			checked = true
		root.get_texture().get_image().save_png("/tmp/crowns-hero-frames/%02d.png" % frame)
	if not checked:
		push_error("Gait review did not observe any moving frames")
		quit(1)
		return
	for frame in 3:
		await process_frame
	var sprite: Sprite2D = view._hero_sprites[hero.id]
	if sprite.texture != Art.sprite("hero_knight") or sprite.offset != -Art.anchor("hero_knight"):
		push_error("Hero did not restore approved idle art after route")
		quit(1)
		return
	print("HERO_GAIT_REVIEW_OK")
	AudioManager.stop_all()
	main.queue_free()
	await process_frame
	quit(0)
