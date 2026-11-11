class_name Pathfinder
extends RefCounted
## Terrain-weighted A* on the adventure map, built on Godot's AStarGrid2D.
## Diagonal steps cost sqrt(2) x the entered tile's cost and are only allowed
## when they do not cut a blocked corner.

const DIAGONAL_FACTOR := 1.41421356

var _astar := AStarGrid2D.new()
var _map: AdventureMap


func _init(map: AdventureMap) -> void:
	_map = map
	_astar.region = Rect2i(0, 0, map.width, map.height)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	refresh_terrain()


func refresh_terrain() -> void:
	for y in _map.height:
		for x in _map.width:
			var p := Vector2i(x, y)
			var passable := _map.is_passable(p)
			_astar.set_point_solid(p, not passable)
			if passable:
				# Weight is relative to grassland (100 points).
				_astar.set_point_weight_scale(p, _map.move_cost(p) / 100.0)


## Returns the tile path from `from` to `to`, excluding `from`. Empty if unreachable.
## Map objects that block movement (neutral armies) are only enterable as the
## final destination.
func find_path(from: Vector2i, to: Vector2i, extra_blocked: Array[Vector2i] = []) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _map.in_bounds(to) or not _map.is_passable(to) or from == to:
		return result
	var blocked := _map.blocking_positions()
	blocked.append_array(extra_blocked)
	var toggled: Array[Vector2i] = []
	for b in blocked:
		if b != to and b != from and not _astar.is_point_solid(b):
			_astar.set_point_solid(b, true)
			toggled.append(b)
	var ids := _astar.get_id_path(from, to)
	for b in toggled:
		_astar.set_point_solid(b, false)
	for i in range(1, ids.size()):
		result.append(ids[i])
	return result


const MAX_COST_CUT := 0.9


## Movement cost of each step along `path`, starting at `from`. cost_mods (from
## Hero.move_cost_mods) removes part of the cost above open ground (100):
## {"rough": share on every terrain, "terrain": {terrain_id: share}}. Roads and
## open ground are unaffected.
func step_costs(from: Vector2i, path: Array[Vector2i], cost_mods: Dictionary = {}) -> Array[int]:
	var costs: Array[int] = []
	var prev := from
	for p in path:
		var c := float(adjusted_cost(_map.move_cost(p), _map.terrain_at(p), _map.has_road(p), cost_mods))
		if p.x != prev.x and p.y != prev.y:
			c *= DIAGONAL_FACTOR
		costs.append(int(round(c)))
		prev = p
	return costs


static func adjusted_cost(base_cost: int, terrain_id: String, on_road: bool, cost_mods: Dictionary) -> int:
	var extra := base_cost - 100
	if on_road or extra <= 0 or cost_mods.is_empty():
		return base_cost
	var cut := float(cost_mods.get("rough", 0.0)) + float(cost_mods.get("terrain", {}).get(terrain_id, 0.0))
	cut = clampf(cut, 0.0, MAX_COST_CUT)
	return int(round(100 + extra * (1.0 - cut)))
