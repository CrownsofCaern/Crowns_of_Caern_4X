extends "res://tests/test_case.gd"
## Adventure map zoom: three levels (twice as far, default, twice as close),
## and the camera math behind them (MapCamera). Picking, hover and scrolling
## on the real screen are checked by tools/zoom_check.gd (needs a scene tree).


func test_levels_and_steps() -> void:
	assert_eq(MapCamera.LEVELS.size(), 3)
	assert_eq(MapCamera.zoom_of(MapCamera.DEFAULT_LEVEL), 1.0)
	assert_eq(MapCamera.zoom_of(0), 0.5, "farthest level shows twice as much")
	assert_eq(MapCamera.zoom_of(2), 2.0, "closest level is twice as close")
	assert_eq(MapCamera.stepped(1, 1), 2)
	assert_eq(MapCamera.stepped(2, 1), 2, "no level past the closest")
	assert_eq(MapCamera.stepped(0, -1), 0, "no level past the farthest")
	assert_eq(MapCamera.zoom_of(99), 2.0)


func test_map_origin_centres_focus_and_fills_edges() -> void:
	var view := Vector2(800, 600)
	var map_px := Vector2(4000, 4000)
	# Focus in the middle of a big map: the focus lands on the view centre.
	var o := MapCamera.map_origin(view, map_px, Vector2(2000, 2000), 2.0)
	assert_eq(o + Vector2(2000, 2000) * 2.0, view * 0.5)
	assert_eq(MapCamera.focus_of(view, o, 2.0), Vector2(2000, 2000))
	# Near the top-left corner the map stays flush with the view edge.
	assert_eq(MapCamera.map_origin(view, map_px, Vector2(10, 10), 1.0), Vector2.ZERO)
	# Near the far corner, likewise.
	assert_eq(MapCamera.map_origin(view, map_px, map_px, 0.5), view - map_px * 0.5)
	# A map smaller than the view is centred.
	assert_eq(MapCamera.map_origin(view, Vector2(400, 1000), Vector2.ZERO, 1.0), Vector2(200, -0.0))


func test_anchor_keeps_point_under_pointer() -> void:
	var view := Vector2(800, 600)
	var map_px := Vector2(8000, 8000)
	var point := Vector2(3000, 2500)
	var anchor := Vector2(120, 450)
	for zoom in MapCamera.LEVELS:
		var focus := MapCamera.focus_for_anchor(point, anchor, view, zoom)
		var o := MapCamera.map_origin(view, map_px, focus, zoom)
		var on_screen := o + point * zoom
		assert_true(on_screen.distance_to(anchor) <= 1.0, "zoom %s: %s vs %s" % [zoom, on_screen, anchor])


func test_clamp_focus_and_visible_cells() -> void:
	var view := Vector2(800, 600)
	var map_px := Vector2(40, 30) * MapView.TILE
	var f := MapCamera.clamp_focus(Vector2(-500, 99999), view, map_px, 1.0)
	assert_eq(f, Vector2(400, map_px.y - 300))
	# Zoomed out the whole 1600x1200 map fits: the focus is pinned to its middle.
	assert_eq(MapCamera.clamp_focus(Vector2(0, 0), view, map_px, 0.5), map_px * 0.5)
	var r := MapCamera.visible_cells(view, Vector2i(40, 30), Vector2(-400, -80), 1.0)
	assert_eq(r, Rect2i(10, 2, 20, 15))
	var whole := MapCamera.visible_cells(view, Vector2i(40, 30), Vector2.ZERO, 0.5)
	assert_eq(whole, Rect2i(0, 0, 40, 30))
	var close := MapCamera.visible_cells(view, Vector2i(40, 30), Vector2(-400, -80), 2.0)
	assert_eq(close.size, Vector2i(10, 8), "twice as close shows half the cells")
