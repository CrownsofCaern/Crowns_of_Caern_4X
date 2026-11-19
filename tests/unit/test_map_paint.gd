extends "res://tests/test_case.gd"
## The painted adventure-map surface (MapPaint): the images it hands to its
## shaders. How the result looks on screen is checked with tools/screenshot.gd.


func _blank(w: int, h: int) -> AdventureMap:
	var map := AdventureMap.new()
	map.width = w
	map.height = h
	map.terrain.resize(w * h)
	map.terrain.fill("grass")
	map.road.resize(w * h)
	return map


func test_atlas_supports_painted_ground() -> void:
	var info := Art.terrain_info()
	assert_true(MapPaint.supported(info), "every ground and the fog have a painted field")
	var bare := info.duplicate(true)
	bare["fog"].erase("field")
	assert_false(MapPaint.supported(bare), "without fields the tile layers stay in charge")


func test_id_image_follows_terrain() -> void:
	var map := _blank(4, 3)
	map.terrain[map.index(Vector2i(2, 1))] = "snow"
	var order: Array = Art.terrain_info()["order"]
	var visual := func(t: Vector2i) -> String: return map.terrain_at(t)
	var ids := MapPaint.id_image(map, order, visual)
	assert_eq(ids.get_size(), Vector2i(4, 3))
	assert_eq(roundi(ids.get_pixel(2, 1).r * 255.0), order.find("snow"))
	assert_eq(roundi(ids.get_pixel(0, 0).r * 255.0), order.find(map.terrain_at(Vector2i.ZERO)))


func test_territory_image_bleeds_colour_without_alpha() -> void:
	var map := _blank(5, 5)
	var blue := Color(0.2, 0.4, 0.8)
	var img := MapPaint.territory_image(map, {Vector2i(2, 2): blue})
	assert_eq(img.get_pixel(2, 2).a, 1.0)
	assert_eq(img.get_pixel(1, 2).a, 0.0, "the neighbour is outside the realm")
	assert_gt(img.get_pixel(1, 2).b, 0.7, "but carries its colour for the filtered rim")
	assert_eq(img.get_pixel(0, 0), Color(0, 0, 0, 0))
