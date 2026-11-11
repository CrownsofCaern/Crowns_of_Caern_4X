extends "res://tests/test_case.gd"


func test_fast_drags_have_no_gaps_in_any_direction() -> void:
	for finish in [Vector2i(12, 3), Vector2i(-12, 3), Vector2i(3, 12), Vector2i(3, -12), Vector2i(-12, -12)]:
		var cells := MapBrush.line(Vector2i.ZERO, finish)
		assert_eq(cells.front(), Vector2i.ZERO)
		assert_eq(cells.back(), finish)
		assert_eq(cells.size(), maxi(absi(finish.x), absi(finish.y)) + 1)
		for i in range(1, cells.size()):
			var delta: Vector2i = (cells[i] - cells[i - 1]).abs()
			assert_true(delta.x <= 1 and delta.y <= 1)


func test_single_click_and_horizontal_vertical_lines() -> void:
	assert_eq(MapBrush.line(Vector2i(2, 3), Vector2i(2, 3)), [Vector2i(2, 3)])
	assert_eq(MapBrush.line(Vector2i(2, 1), Vector2i(2, 3)), [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)])
	assert_eq(MapBrush.line(Vector2i(3, 1), Vector2i(1, 1)), [Vector2i(3, 1), Vector2i(2, 1), Vector2i(1, 1)])


func test_square_brush_clips_at_edges_without_shifting() -> void:
	var bounds := Vector2i(10, 10)
	assert_eq(MapBrush.square(Vector2i(5, 5), 3, bounds).size(), 9)
	assert_eq(MapBrush.square(Vector2i.ZERO, 3, bounds), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)])
	assert_eq(MapBrush.square(Vector2i(9, 9), 3, bounds).size(), 4)
	assert_eq(MapBrush.square(Vector2i.ZERO, 1, bounds), [Vector2i.ZERO])


func test_rectangle_fill_is_order_independent_and_in_bounds() -> void:
	var bounds := Vector2i(8, 6)
	var cells := MapBrush.rectangle(Vector2i(2, 3), Vector2i(4, 5), bounds)
	assert_eq(cells.size(), 9)
	assert_eq(cells, MapBrush.rectangle(Vector2i(4, 5), Vector2i(2, 3), bounds))
	assert_eq(MapBrush.rectangle(Vector2i(-2, -2), Vector2i(9, 9), bounds).size(), 48)
	assert_eq(MapBrush.rectangle(Vector2i(-3, -3), Vector2i(-1, -1), bounds).size(), 0)


func test_brush_width_is_bounded() -> void:
	assert_eq(MapBrush.square(Vector2i(20, 20), 1000, Vector2i(50, 50)).size(), 225)
	assert_eq(MapBrush.square(Vector2i(20, 20), 0, Vector2i(50, 50)).size(), 1)
