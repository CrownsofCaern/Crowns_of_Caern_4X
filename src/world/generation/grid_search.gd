class_name GridSearch
extends RefCounted
## Small headless grid searches used by the map generator and its validator.
##
## Tiles are flat indices (y * width + x). Movement is 4-connected: with the
## adventure map's "no corner cutting" diagonal rule, 4-connected reachability
## is exactly the reachability heroes have, and it keeps every search here
## deterministic and cheap.

const DIRS4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func neighbors4(width: int, height: int, idx: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := idx % width
	var y := idx / width
	if y > 0:
		out.append(idx - width)
	if x < width - 1:
		out.append(idx + 1)
	if y < height - 1:
		out.append(idx + width)
	if x > 0:
		out.append(idx - 1)
	return out


## Breadth-first flood fill over tiles where open[i] != 0.
## Returns a mask (1 = reached). Sources that are not open are still expanded from.
static func flood(width: int, height: int, open: PackedByteArray, sources: PackedInt32Array) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(width * height)
	var queue := PackedInt32Array()
	for s in sources:
		if s >= 0 and seen[s] == 0:
			seen[s] = 1
			queue.append(s)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for n in neighbors4(width, height, cur):
			if seen[n] == 0 and open[n] != 0:
				seen[n] = 1
				queue.append(n)
	return seen


static func count(mask: PackedByteArray) -> int:
	var c := 0
	for v in mask:
		if v != 0:
			c += 1
	return c


## Dijkstra over per-tile entry costs (cost <= 0 means blocked). Returns the
## cheapest total cost to enter every tile from the sources, -1 if unreachable.
## Ties are broken by tile index, so results never depend on memory layout.
static func distances(width: int, height: int, cost: PackedInt32Array, sources: PackedInt32Array, max_cost: int = -1) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	var heap := _Heap.new()
	for s in sources:
		if s >= 0 and dist[s] != 0:
			dist[s] = 0
			heap.push(0, s)
	while not heap.is_empty():
		var top := heap.pop()
		var d: int = top[0]
		var cur: int = top[1]
		if d > dist[cur]:
			continue
		for n in neighbors4(width, height, cur):
			var c := cost[n]
			if c <= 0:
				continue
			var nd := d + c
			if max_cost >= 0 and nd > max_cost:
				continue
			if dist[n] < 0 or nd < dist[n]:
				dist[n] = nd
				heap.push(nd, n)
	return dist


## Cheapest 4-connected path from `from` to `to` (both included). Empty if none.
static func path(width: int, height: int, cost: PackedInt32Array, from: int, to: int) -> PackedInt32Array:
	var dist := distances(width, height, cost, PackedInt32Array([to]))
	var out := PackedInt32Array()
	if dist[from] < 0:
		return out
	# Walk downhill from `from` towards `to`; costs are entry costs, so the
	# step from a to b is valid when dist[a] == dist[b] + cost[a].
	var cur := from
	out.append(cur)
	var guard := width * height
	while cur != to and guard > 0:
		guard -= 1
		var best := -1
		for n in neighbors4(width, height, cur):
			if dist[n] >= 0 and dist[n] + cost[cur] == dist[cur]:
				if best < 0 or dist[n] < dist[best] or (dist[n] == dist[best] and n < best):
					best = n
		if best < 0:
			return PackedInt32Array()
		cur = best
		out.append(cur)
	return out


## Binary min-heap of [priority, index] pairs ordered by (priority, index).
class _Heap:
	var keys := PackedInt64Array()

	func is_empty() -> bool:
		return keys.is_empty()

	func push(priority: int, idx: int) -> void:
		keys.append((priority << 20) | idx)
		var i := keys.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if keys[parent] <= keys[i]:
				break
			var t := keys[parent]
			keys[parent] = keys[i]
			keys[i] = t
			i = parent

	func pop() -> Array:
		var top := keys[0]
		var last := keys[keys.size() - 1]
		keys.resize(keys.size() - 1)
		if not keys.is_empty():
			keys[0] = last
			var i := 0
			var n := keys.size()
			while true:
				var l := 2 * i + 1
				var r := l + 1
				var m := i
				if l < n and keys[l] < keys[m]:
					m = l
				if r < n and keys[r] < keys[m]:
					m = r
				if m == i:
					break
				var t := keys[m]
				keys[m] = keys[i]
				keys[i] = t
				i = m
		return [top >> 20, top & 0xFFFFF]
