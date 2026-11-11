extends SceneTree
## Adventure map zoom on the real screen (the unit tests have no scene tree):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/zoom_check.gd -- [out_dir]
## Checks at each zoom level that clicking picks the tile drawn under the
## pointer, that wheel zoom keeps the tile under the pointer, and that arrow
## scrolling moves the picture the same distance; saves a screenshot per level
## when an out_dir is given. Exits 1 on any failure.

var main: Node
var failures: Array[String] = []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	_run()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		printerr("FAIL ", msg)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var out_dir := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
		DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(5)
	var mv: MapView = main.map_view
	var view_rect: Rect2 = main._view_rect()
	var map := Vector2i(main.session.state.map.width, main.session.state.map.height)
	var start_pos := mv.position
	for level in [2, 0, 1]:
		main.set_zoom_level(level)
		await _frames(2)
		var z := MapCamera.zoom_of(level)
		_check(mv.scale == Vector2(z, z), "scale at level %d" % level)
		# Picking: probe a few tiles in view, at their centres and edges.
		var probes := 0
		for y in range(0, map.y, 3):
			for x in range(0, map.x, 3):
				var t := Vector2i(x, y)
				var px := mv.get_global_transform_with_canvas() * mv.center_px(t)
				if not view_rect.has_point(px):
					continue
				probes += 1
				_check(mv._event_tile(px) == t, "pick %s at zoom %s" % [t, z])
				_check(mv._event_tile(px + Vector2(MapView.TILE * z * 0.45, 0)) == t, "edge of %s at zoom %s" % [t, z])
				_check(mv._event_tile(px + Vector2(MapView.TILE * z * 0.55, 0)) == t + Vector2i(1, 0), "next of %s at zoom %s" % [t, z])
		_check(probes > 0, "some tiles visible at zoom %s" % z)
		# Hover follows a pointer that did not move while the map zoomed.
		var at := view_rect.position + view_rect.size * Vector2(0.4, 0.5)
		Input.warp_mouse(at)
		await _frames(2)
		main._keep_hero_in_view()
		_check(mv.hovered == mv._event_tile(at), "hover at zoom %s" % z)
		# The minimap frame shows as many cells as are on screen.
		var vr: Rect2i = main.hud.minimap.view_rect
		var expect_w := mini(map.x, ceili(view_rect.size.x / (MapView.TILE * z)))
		_check(absi(vr.size.x - expect_w) <= 1, "minimap frame %s at zoom %s" % [vr, z])
		if out_dir != "":
			await _frames(10)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir.path_join("zoom_%d.png" % level))
	_check(mv.position == start_pos, "default zoom puts the camera back (%s vs %s)" % [mv.position, start_pos])
	# Wheel zoom around the pointer keeps the tile under it.
	var at := view_rect.position + view_rect.size * Vector2(0.3, 0.6)
	var before := mv._event_tile(at)
	main.zoom_by(1, at)
	_check(mv._event_tile(at) == before, "wheel in keeps %s under the pointer (got %s)" % [before, mv._event_tile(at)])
	main.zoom_by(-1, at)
	_check(mv._event_tile(at) == before, "wheel out keeps %s under the pointer (got %s)" % [before, mv._event_tile(at)])
	main.zoom_by(-1, at)
	main.zoom_by(-1, at)
	_check(main.zoom_level == 0, "stops at the farthest level")
	# Arrow scrolling moves the picture by three on-screen cells at every zoom.
	for level in [0, 1, 2]:
		main.set_zoom_level(level)
		main.look_at_tile(map / 2)
		var x0: float = mv.position.x
		main._scroll(Vector2.RIGHT)
		var moved: float = x0 - mv.position.x
		_check(moved == 0.0 or absf(moved - MapView.TILE * 3) <= 1.0, "level %d scrolled %s" % [level, moved])
	print("zoom check: %s" % ("ok" if failures.is_empty() else "%d failures" % failures.size()))
	quit(0 if failures.is_empty() else 1)
