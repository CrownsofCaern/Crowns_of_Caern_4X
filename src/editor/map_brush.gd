class_name MapBrush
extends RefCounted
## Grid geometry shared by pointer tools and their headless tests.

static func line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var point := from
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var error := dx + dy
	while true:
		cells.append(point)
		if point == to:
			break
		var twice := 2 * error
		if twice >= dy:
			error += dy
			point.x += sx
		if twice <= dx:
			error += dx
			point.y += sy
	return cells


static func square(centre: Vector2i, side: int, bounds: Vector2i) -> Array[Vector2i]:
	var offset := Vector2i.ONE * (clampi(side, 1, 15) / 2)
	return rectangle(centre - offset, centre - offset + Vector2i.ONE * (clampi(side, 1, 15) - 1), bounds)


static func rectangle(from: Vector2i, to: Vector2i, bounds: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var minimum := from.min(to).max(Vector2i.ZERO)
	var maximum := from.max(to).min(bounds - Vector2i.ONE)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			cells.append(Vector2i(x, y))
	return cells
