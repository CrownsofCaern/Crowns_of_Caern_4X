extends "res://tests/test_case.gd"

var session: GameSession
var map: AdventureMap


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 1)
	map = session.state.map


func test_map_loads_with_expected_size() -> void:
	assert_eq(map.width, 24)
	assert_eq(map.height, 18)
	assert_eq(map.terrain_at(Vector2i(0, 0)), "snow")
	assert_eq(map.terrain_at(Vector2i(20, 0)), "infernal")


func test_terrain_costs() -> void:
	assert_eq(map.move_cost(Vector2i(0, 3)), 100, "grass")
	assert_eq(map.move_cost(Vector2i(3, 5)), 150, "forest")
	assert_eq(map.move_cost(Vector2i(0, 13)), 175, "swamp")
	assert_eq(map.move_cost(Vector2i(4, 8)), 60, "road")
	assert_eq(map.move_cost(Vector2i(10, 3)), 200, "river ford")


func test_mountains_block_and_roads_bridge() -> void:
	assert_false(map.is_passable(Vector2i(5, 0)), "mountain")
	assert_true(map.is_passable(Vector2i(10, 8)), "bridge over river")


func test_path_avoids_mountains() -> void:
	var pf := session.pathfinder
	var path := pf.find_path(Vector2i(2, 9), Vector2i(2, 13))
	assert_true(path.size() > 0, "a path exists around the mountain ridge")
	for p in path:
		assert_true(map.is_passable(p), "path tile %s passable" % p)


func test_path_prefers_road() -> void:
	# Along the road the 6-tile trip costs 360; the grass row above would cost 600.
	var pf := session.pathfinder
	var from := Vector2i(1, 8)
	var path := pf.find_path(from, Vector2i(7, 8))
	var total := 0
	for c in pf.step_costs(from, path):
		total += c
	assert_eq(total, 360)


func test_swamp_costs_more_than_grass() -> void:
	var pf := session.pathfinder
	var grass := pf.step_costs(Vector2i(8, 13), [Vector2i(9, 13)] as Array[Vector2i])
	var swamp := pf.step_costs(Vector2i(1, 14), [Vector2i(2, 14)] as Array[Vector2i])
	assert_gt(swamp[0], grass[0])


func test_diagonal_costs_more() -> void:
	var c := session.pathfinder.step_costs(Vector2i(14, 15), [Vector2i(15, 16)] as Array[Vector2i])
	assert_eq(c[0], 141)


func test_neutral_army_blocks_unless_destination() -> void:
	var pf := session.pathfinder
	var wolves := Vector2i(12, 8)
	var through := pf.find_path(Vector2i(11, 8), Vector2i(13, 8))
	assert_false(through.has(wolves), "path routes around the wolves")
	var into := pf.find_path(Vector2i(11, 8), wolves)
	assert_eq(into.size(), 1)
	assert_eq(into[0], wolves)


func test_fog_reveal() -> void:
	var fog := FogOfWar.new(10, 10)
	assert_eq(fog.reveal(Vector2i(5, 5), 2), 21)
	assert_eq(fog.reveal(Vector2i(5, 5), 2), 0, "already explored")
	assert_true(fog.is_explored(Vector2i(5, 3)))
	assert_false(fog.is_explored(Vector2i(0, 0)))


func test_no_two_map_objects_share_a_tile() -> void:
	var def := data.load_map("ember_ford")
	var seen := {}
	for o in def["objects"]:
		var p := AdventureMap.object_pos(o)
		assert_false(seen.has(p), "%s and %s share tile %s" % [seen.get(p, ""), o["id"], p])
		seen[p] = o["id"]
	for hd in def["heroes"]:
		var p := Vector2i(int(hd["pos"][0]), int(hd["pos"][1]))
		assert_false(seen.has(p) and def["objects"].filter(func(o): return o["id"] == seen[p] and o["type"] != "town").size() > 0,
			"hero %s starts on object %s" % [hd["id"], seen.get(p, "")])
