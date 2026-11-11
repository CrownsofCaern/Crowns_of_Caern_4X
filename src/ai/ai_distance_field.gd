class_name AiDistanceField
extends RefCounted
## Movement cost from one tile to every tile of the adventure map (Dijkstra),
## using the same step costs as Pathfinder: the entered tile's cost, x sqrt(2)
## for diagonals, no diagonal past a blocked corner. Blocked tiles (neutral
## armies, guarded objects, other heroes) can be reached as a destination but
## never walked through. One field answers "how far is everything" for a hero,
## where running A* per candidate target would not scale to large maps.
##
## Ties are broken by tile index, so the result never depends on hashing.

const UNREACHABLE := -1

var width: int = 0
var height: int = 0
var origin: Vector2i
var _cost: PackedInt32Array = PackedInt32Array()


static func build(map: AdventureMap, from: Vector2i, blocked: Dictionary, max_cost: int = -1) -> AiDistanceField:
	var f := AiDistanceField.new()
	f.width = map.width
	f.height = map.height
	f.origin = from
	var n := map.width * map.height
	f._cost.resize(n)
	f._cost.fill(UNREACHABLE)
	var solid := PackedByteArray()
	solid.resize(n)
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if not map.is_passable(p):
				solid[y * map.width + x] = 2
			elif blocked.has(p) and p != from:
				solid[y * map.width + x] = 1
	var start := from.y * map.width + from.x
	f._cost[start] = 0
	var heap := []   # packed keys: cost * n + index (deterministic tie-break)
	_push(heap, start)
	var done := PackedByteArray()
	done.resize(n)
	while not heap.is_empty():
		var key: int = _pop(heap)
		var idx := key % n
		var c := key / n
		if done[idx] == 1 or c != f._cost[idx]:
			continue
		done[idx] = 1
		if solid[idx] == 1 or (max_cost >= 0 and c > max_cost):
			continue   # destination only, or beyond the horizon
		var px := idx % map.width
		var py := idx / map.width
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var qx: int = px + dx
				var qy: int = py + dy
				if qx < 0 or qy < 0 or qx >= map.width or qy >= map.height:
					continue
				var q := qy * map.width + qx
				if solid[q] == 2 or done[q] == 1:
					continue
				var step := float(map.move_cost(Vector2i(qx, qy)))
				if dx != 0 and dy != 0:
					if solid[py * map.width + qx] != 0 or solid[qy * map.width + px] != 0:
						continue
					step *= Pathfinder.DIAGONAL_FACTOR
				var nc := c + int(round(step))
				if f._cost[q] == UNREACHABLE or nc < f._cost[q]:
					f._cost[q] = nc
					_push(heap, nc * n + q)
	return f


## Movement points to reach p, or UNREACHABLE.
func cost_to(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= width or p.y >= height:
		return UNREACHABLE
	return _cost[p.y * width + p.x]


static func _push(heap: Array, key: int) -> void:
	heap.append(key)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent] <= heap[i]:
			break
		var tmp: int = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


static func _pop(heap: Array) -> int:
	var top: int = heap[0]
	var last: int = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var size := heap.size()
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < size and heap[l] < heap[m]:
			m = l
		if r < size and heap[r] < heap[m]:
			m = r
		if m == i:
			break
		var tmp: int = heap[m]
		heap[m] = heap[i]
		heap[i] = tmp
		i = m
	return top
