extends SceneTree
## Renders part of a map with the real map view (fog off), for judging terrain
## and decoration by eye:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/terrain_preview.gd -- <map_id> <out.png> [zoom] [tile_x,tile_y]
## [tile_x,tile_y | landmark | scenery]. Without a focus it centres on the first hero. Generated maps use ids like gen:crossing:3.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id: String = args[0] if args.size() > 0 else "gen:crossing:3"
	var out: String = args[1] if args.size() > 1 else "/tmp/terrain_preview.png"
	var zoom: float = float(args[2]) if args.size() > 2 else 0.5
	root.size = Vector2i(1600, 1000)
	var data := GameData.get_default()
	var session := GameSession.new_game(data, map_id, 1)
	var map := session.state.map
	(session.current_player()["fog"] as FogOfWar).reveal(Vector2i(map.width / 2, map.height / 2), maxi(map.width, map.height))
	var view := MapView.new()
	root.add_child(view)
	view.bind(session)
	view._fog.hide()
	view.set_zoom(zoom)
	var focus := Vector2i(session.state.map.width / 2, session.state.map.height / 2)
	if args.size() > 3 and args[3] in ["landmark", "scenery"]:
		# Centre on the first landmark (or single-tile scenery piece).
		for e in session.state.map.scenery:
			if (int(e["footprint"][0]) > 1) == (args[3] == "landmark"):
				focus = Vector2i(int(e["pos"][0]), int(e["pos"][1]))
				break
	elif args.size() > 3:
		var parts := args[3].split(",")
		focus = Vector2i(int(parts[0]), int(parts[1]))
	elif not session.state.heroes.is_empty():
		focus = session.state.heroes.values()[0].pos
	view.position = Vector2(root.size) / 2.0 - view.center_px(focus) * zoom
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
