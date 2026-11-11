class_name ScenarioMaze
extends RefCounted
## Expedition maze (labyrinth recipe version 2+): a townless race to the
## centre before the deadline.
##
## The maze is a grid of `cells` x `cells` rooms on a pitch of three tiles, so
## corridors are two tiles wide; a few 2x2 blocks of cells open into halls.
## The only one-tile openings are guarded chokepoints: the sentinels that hold
## doorways along the safe route, and the keeper of a shortcut through a
## wall. Floors change biome by ring around the centre, walls mix stone and
## dark water. Dead ends hold the prizes: a survey chamber that reveals the
## centre and the shortcut, stranded volunteers, guarded armour caches and
## loose supplies. The survey chamber and the volunteers open in the second
## week unless they lie beyond a week's march anyway (ScenarioGating).

const PITCH := 3
const FLOORS := [".", "r", "d", "i"]
const HALLS := 3


static func build(data: GameData, recipe: Dictionary, seed_value: int) -> Dictionary:
	var n := int(recipe["cells"])
	var side := n * PITCH + 1
	var start_cell := Vector2i.ZERO
	var centre_cell := Vector2i(n / 2, n / 2)
	var start := _tile(start_cell)
	var centre := _tile(centre_cell) + Vector2i(1, 1) / 2
	var result := {"id": "maze", "name": recipe["name"], "width": side, "height": side, "roads": [],
		"players": [{"id": 0, "name": "The Expedition", "faction": "concord", "color": "#4488d0", "is_human": true}],
		"heroes": [{"id": "hero_watch", "name": "Aldous Wren", "class": "knight", "owner": 0, "pos": [start.x, start.y], "army": recipe["army"].duplicate(true)}],
		"objects": []}
	var rng := GameRng.new(seed_value)
	var map: AdventureMap
	var path: Array[Vector2i] = []
	var travel := 0
	var links := {}
	var halls := []
	var fitted := false
	for attempt in 128:
		rng = GameRng.new(GameRng.mix(seed_value, attempt + 4099))
		links = _carve(n, rng)
		halls = _halls(n, rng, [start_cell, centre_cell])
		result["terrain"] = _rows(n, side, links, halls, centre_cell, rng)
		map = AdventureMap.from_definition(result, data)
		var finder := Pathfinder.new(map)
		path = finder.find_path(start, centre)
		travel = 0
		for cost in finder.step_costs(start, path):
			travel += cost
		if travel >= int(recipe["min_travel_cost"]) and travel <= int(recipe["max_travel_cost"]):
			fitted = true
			break
	if not fitted:
		return {}
	var from_start := AiDistanceField.build(map, start, {})
	var from_goal := AiDistanceField.build(map, centre, {})
	# Sentinels narrow doorways on the safe route to one tile and hold them.
	var occupied := {start: true, centre: true}
	var guard_budget := int(recipe["road_guard_budget"])
	var doors := _route_doors(n, links, path, start_cell, centre_cell, from_start, map)
	var step := maxi(1, doors.size() / 4)
	var placed := 0
	for i in range(step, doors.size() - 1, step):
		if placed >= 3:
			break
		var door: Array = doors[i]
		var keep: Vector2i = door[0]
		var fill: Vector2i = door[1]
		_set_tile(result, fill, "^")
		result["objects"].append({"id": "maze_guard_%d" % placed, "type": "neutral_army", "pos": [keep.x, keep.y], "name": "Labyrinth sentinels",
			"stacks": ScenarioGenerator._guard(data, rng, guard_budget)})
		occupied[keep] = true
		placed += 1
	map = AdventureMap.from_definition(result, data)
	from_start = AiDistanceField.build(map, start, {})
	from_goal = AiDistanceField.build(map, centre, {})
	travel = from_start.cost_to(centre)
	# The shortcut: one wall tile between two corridors, held by a keeper.
	var special := []
	var shortcut := _shortcut(map, from_start, from_goal, travel, side, rng)
	if shortcut.x >= 0:
		_set_tile(result, shortcut, ".")
		result["objects"].append({"id": "labyrinth_shortcut_guard", "type": "neutral_army", "pos": [shortcut.x, shortcut.y], "name": "The Shortcut Keeper",
			"stacks": ScenarioGenerator._guard(data, rng, int(recipe["shortcut_budget"]))})
		occupied[shortcut] = true
		special.append([shortcut.x, shortcut.y])
	map = AdventureMap.from_definition(result, data)
	from_start = AiDistanceField.build(map, start, {})
	result["objects"].append({"id": "stone_heart", "type": "scenario_site", "kind": "goal", "name": "The Stone Heart", "pos": [centre.x, centre.y],
		"sprite": "place_lockstone", "text": "Reach this chamber by the end of day %d." % int(recipe["deadline_day"])})
	# Dead ends hold the prizes, spread from near to deep: the survey chamber
	# about a third of the way in, the rest shuffled over the other ends.
	var ends := _dead_ends(n, links, halls, [start_cell, centre_cell]).map(func(c): return _tile(c) + Vector2i(rng.next_int(0, 1), rng.next_int(0, 1)))
	ends = ends.filter(func(p): return not occupied.has(p) and from_start.cost_to(p) >= 1200 and from_goal.cost_to(p) >= 900)
	ends.sort_custom(func(a, b): return from_start.cost_to(a) < from_start.cost_to(b) or (from_start.cost_to(a) == from_start.cost_to(b) and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	var week := 1500 * ScenarioGating.WINDOW_DAYS
	var prizes := ["supplies", "supplies", "armour", "armour", "cache", "cache", "cache"]
	for i in range(prizes.size() - 1, 0, -1):
		var j := rng.next_int(0, i)
		var swap: String = prizes[i]
		prizes[i] = prizes[j]
		prizes[j] = swap
	prizes.insert(mini(2, prizes.size()), "observatory")
	var gen := MapGenerator.new(data)
	gen.rng = rng
	var used_armour := {}
	var count := mini(prizes.size(), ends.size())
	for i in count:
		var p: Vector2i = ends[mini(ends.size() - 1, int(float(i) * ends.size() / count))]
		if occupied.has(p):
			continue
		occupied[p] = true
		match String(prizes[i]):
			"observatory", "supplies":
				var observatory: bool = prizes[i] == "observatory"
				var site := {"id": "maze_support_%d" % i, "type": "scenario_site", "kind": prizes[i], "pos": [p.x, p.y],
					"name": "The Survey Chamber" if observatory else "Stranded Volunteers",
					"sprite": "encounter_blind_cartographer" if observatory else "encounter_free_company_camp",
					"text": "Survey the maze to reveal the centre and a shortcut." if observatory else "These survivors will join your expedition if you reach them.",
					"reveal": special + [[centre.x, centre.y]], "radius": 5,
					"recruits": [["pike_militia", 10 + rng.next_int(0, 4)], ["longbowman", 6 + rng.next_int(0, 3)]]}
				if from_start.cost_to(p) <= week:
					site["unlock_day"] = ScenarioGating.WINDOW_DAYS + 1 + rng.next_int(0, 2)
					site["text"] += " They are expected on day %d." % int(site["unlock_day"]) if not observatory else " Its lamps are lit on day %d." % int(site["unlock_day"])
				result["objects"].append(site)
			"armour":
				var aid := gen._pick_armor("minor", used_armour)
				if aid == "":
					continue
				used_armour[aid] = true
				result["objects"].append({"id": "maze_cache_%d" % i, "type": "artifact", "artifact": aid, "pos": [p.x, p.y]})
				var guard_at := _guard_spot(map, p, occupied, from_start)
				if guard_at.x >= 0:
					occupied[guard_at] = true
					result["objects"].append({"id": "maze_cache_guard_%d" % i, "type": "neutral_army", "pos": [guard_at.x, guard_at.y], "name": "Cache wardens",
						"stacks": ScenarioGenerator._guard(data, rng, guard_budget)})
			"cache":
				var res: String = ["gold", "wood", "ore"][rng.next_int(0, 2)]
				result["objects"].append({"id": "maze_supply_%d" % i, "type": "resource", "resource": res, "pos": [p.x, p.y],
					"amount": 500 + 100 * rng.next_int(0, 5) if res == "gold" else 4 + rng.next_int(0, 4)})
	var deadline := int(recipe["deadline_day"])
	result["scenario"] = {"name": recipe["name"], "mode": "labyrinth", "player": 0, "deadline_day": deadline, "required_heroes": ["hero_watch"], "townless_players": [0],
		"briefing": "Reach the Stone Heart before the end of day %d. A safe winding route leads inward past sentinels at its doorways; a stronger guardian holds a shorter crossing. Survey chambers reveal the land, stranded volunteers can reinforce your army, and dead ends hide armour caches." % deadline,
		"travel_budget": {"safe_cost": travel, "minimum_daily_movement": 1500, "buffer_days": deadline - ceili(travel / 1500.0)},
		"objectives": [{"id": "heart", "type": "reach", "hero": "hero_watch", "pos": [centre.x, centre.y], "text": "Reach the Stone Heart by the end of day %d." % deadline}]}
	return result


## Top-left floor tile of a cell.
static func _tile(c: Vector2i) -> Vector2i:
	return Vector2i(1 + c.x * PITCH, 1 + c.y * PITCH)


static func _key(a: Vector2i, b: Vector2i) -> String:
	var lo := a if (a.y < b.y or (a.y == b.y and a.x < b.x)) else b
	var hi := b if lo == a else a
	return "%d,%d-%d,%d" % [lo.x, lo.y, hi.x, hi.y]


## A depth-first maze over the cells: {link key: true} for each open wall.
static func _carve(n: int, rng: GameRng) -> Dictionary:
	var links := {}
	var visited := {Vector2i.ZERO: true}
	var stack := [Vector2i.ZERO]
	while not stack.is_empty():
		var p: Vector2i = stack[-1]
		var options := []
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var q: Vector2i = p + d
			if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and not visited.has(q):
				options.append(q)
		if options.is_empty():
			stack.pop_back()
			continue
		var q: Vector2i = options[rng.next_int(0, options.size() - 1)]
		visited[q] = true
		links[_key(p, q)] = true
		stack.append(q)
	return links


## A few 2x2 cell blocks (top-left cells) that open into halls, away from
## the start and the centre.
static func _halls(n: int, rng: GameRng, avoid: Array) -> Array:
	var out := []
	for _i in 40:
		if out.size() >= HALLS:
			break
		var c := Vector2i(rng.next_int(0, n - 2), rng.next_int(0, n - 2))
		var ok := true
		for a in avoid:
			if absi((a as Vector2i).x - c.x) <= 2 and absi((a as Vector2i).y - c.y) <= 2:
				ok = false
		for h in out:
			if absi((h as Vector2i).x - c.x) <= 3 and absi((h as Vector2i).y - c.y) <= 3:
				ok = false
		if ok:
			out.append(c)
	return out


static func _rows(n: int, side: int, links: Dictionary, halls: Array, centre_cell: Vector2i, rng: GameRng) -> Array:
	var grid := []
	for y in side:
		var row := []
		for x in side:
			row.append("^")
		grid.append(row)
	var walls := ["^", "^", "#"]
	for y in side:
		for x in side:
			# Walls in long runs of stone with pools of dark water.
			if rng.next_int(0, 9) == 0:
				grid[y][x] = walls[rng.next_int(0, walls.size() - 1)]
	var floor_at := func(c: Vector2i) -> String:
		var ring := maxi(absi(c.x - centre_cell.x), absi(c.y - centre_cell.y))
		var band := clampi(FLOORS.size() - 1 - ring * FLOORS.size() / maxi(1, centre_cell.x + 1), 0, FLOORS.size() - 1)
		return FLOORS[band]
	for cy in n:
		for cx in n:
			var c := Vector2i(cx, cy)
			var t := _tile(c)
			var f: String = floor_at.call(c)
			for dy in 2:
				for dx in 2:
					grid[t.y + dy][t.x + dx] = f
			if links.has(_key(c, c + Vector2i.RIGHT)):
				for dy in 2:
					grid[t.y + dy][t.x + 2] = f
			if links.has(_key(c, c + Vector2i.DOWN)):
				for dx in 2:
					grid[t.y + 2][t.x + dx] = f
	for h in halls:
		var t := _tile(h)
		var f: String = floor_at.call(h)
		for dy in 5:
			for dx in 5:
				grid[t.y + dy][t.x + dx] = f
	var out := []
	for y in side:
		out.append("".join(grid[y]))
	return out


static func _set_tile(def: Dictionary, p: Vector2i, ch: String) -> void:
	var row := String(def["terrain"][p.y])
	row[p.x] = ch
	def["terrain"][p.y] = row


## Doorways the safe route passes between cells, in route order:
## [[tile the guard holds, tile that is walled up]]. Only doors of plain
## corridor links (not inside halls) count.
static func _route_doors(n: int, links: Dictionary, path: Array[Vector2i], start_cell: Vector2i, centre_cell: Vector2i,
		from_start: AiDistanceField, map: AdventureMap) -> Array:
	var cells := []
	for p in path:
		var c := Vector2i((p.x - 1) / PITCH, (p.y - 1) / PITCH)
		if (p.x - 1) % PITCH < 2 and (p.y - 1) % PITCH < 2 and (cells.is_empty() or cells[-1] != c):
			cells.append(c)
	var out := []
	for i in range(1, cells.size()):
		var a: Vector2i = cells[i - 1]
		var b: Vector2i = cells[i]
		if a == start_cell or b == centre_cell or not links.has(_key(a, b)):
			continue
		var t := _tile(a)
		var door := []
		if b == a + Vector2i.RIGHT:
			door = [t + Vector2i(2, 0), t + Vector2i(2, 1)]
		elif b == a + Vector2i.LEFT:
			door = [t + Vector2i(-1, 0), t + Vector2i(-1, 1)]
		elif b == a + Vector2i.DOWN:
			door = [t + Vector2i(0, 2), t + Vector2i(1, 2)]
		elif b == a + Vector2i.UP:
			door = [t + Vector2i(0, -1), t + Vector2i(1, -1)]
		# Both door tiles must be plain doorway (walls on their outer sides), not a hall.
		var plain := true
		for p in door:
			var open := 0
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if map.in_bounds(p + d) and map.is_passable(p + d):
					open += 1
			if open > 3:
				plain = false
		if plain and door.size() == 2:
			out.append(door)
	return out


static func _shortcut(map: AdventureMap, from_start: AiDistanceField, from_goal: AiDistanceField, travel: int, side: int, rng: GameRng) -> Vector2i:
	var options := []
	for y in range(1, side - 1):
		for x in range(1, side - 1):
			var p := Vector2i(x, y)
			if map.is_passable(p):
				continue
			for d in [Vector2i.RIGHT, Vector2i.DOWN]:
				var a: Vector2i = p - d
				var b: Vector2i = p + d
				if not map.is_passable(a) or not map.is_passable(b) or from_start.cost_to(a) < 0 or from_start.cost_to(b) < 0:
					continue
				var cost := mini(from_start.cost_to(a) + 200 + from_goal.cost_to(b), from_start.cost_to(b) + 200 + from_goal.cost_to(a))
				if travel - cost >= 2000 and travel - cost <= 7000:
					options.append({"pos": p, "saved": travel - cost})
	if options.is_empty():
		return Vector2i(-1, -1)
	options.sort_custom(func(a, b): return a["saved"] > b["saved"] or (a["saved"] == b["saved"] and a["pos"].y * side + a["pos"].x < b["pos"].y * side + b["pos"].x))
	return options[rng.next_int(0, mini(4, options.size() - 1))]["pos"]


## Cells with exactly one open link that are not part of a hall.
static func _dead_ends(n: int, links: Dictionary, halls: Array, avoid: Array) -> Array:
	var in_hall := {}
	for h in halls:
		for dy in 2:
			for dx in 2:
				in_hall[(h as Vector2i) + Vector2i(dx, dy)] = true
	var out := []
	for cy in n:
		for cx in n:
			var c := Vector2i(cx, cy)
			if in_hall.has(c) or avoid.has(c):
				continue
			var open := 0
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if links.has(_key(c, c + d)):
					open += 1
			if open == 1:
				out.append(c)
	return out


## The free passable neighbour of `p` nearest the start: where a cache's guard stands.
static func _guard_spot(map: AdventureMap, p: Vector2i, occupied: Dictionary, from_start: AiDistanceField) -> Vector2i:
	var best := Vector2i(-1, -1)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := p + Vector2i(dx, dy)
			if q == p or not map.in_bounds(q) or not map.is_passable(q) or occupied.has(q) or from_start.cost_to(q) < 0:
				continue
			if best.x < 0 or from_start.cost_to(q) < from_start.cost_to(best):
				best = q
	return best
