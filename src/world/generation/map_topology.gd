class_name MapTopology
extends RefCounted
## Chooses a strategic graph from borders that can actually hold a pass.
## Paired edges preserve rotational fairness; Adventure graphs need no symmetry.


static func select(layout: ZoneLayout, template: Dictionary, rng: GameRng) -> Array:
	var adjacent := {}
	for i in layout.wall.size():
		if layout.wall[i] == 0:
			continue
		var own := int(layout.zone_of[i])
		var touches := []
		for n in GridSearch.neighbors4(layout.width, layout.height, i):
			if layout.wall[n] == 0 and not touches.has(int(layout.zone_of[n])):
				touches.append(int(layout.zone_of[n]))
		if not touches.has(own):
			continue
		for other in touches:
			if other != own:
				adjacent[_key(own, other)] = [mini(own, other), maxi(own, other)]
	var keys := adjacent.keys()
	keys.sort()
	var symmetric: bool = template.get("symmetry", "none") == "rotate180"
	var mirrors := {}
	for z in template["zones"]:
		var index := int(layout.zone_index[z["id"]])
		var partner := String(z.get("mirror", ""))
		if partner == "self":
			mirrors[index] = index
		elif partner != "":
			var other := int(layout.zone_index[partner])
			mirrors[index] = other
			mirrors[other] = index
	var groups := []
	var used := {}
	for key in keys:
		if used.has(key):
			continue
		var pair: Array = adjacent[key]
		var edges := [pair]
		used[key] = true
		if symmetric:
			if not mirrors.has(pair[0]) or not mirrors.has(pair[1]):
				continue
			var mirrored := _key(int(mirrors[pair[0]]), int(mirrors[pair[1]]))
			if not adjacent.has(mirrored):
				continue
			if mirrored != key:
				edges.append(adjacent[mirrored])
				used[mirrored] = true
		groups.append({"edges": edges, "weight": rng.next_float(), "key": key})
	groups.sort_custom(func(a, b): return a["weight"] < b["weight"] or (a["weight"] == b["weight"] and a["key"] < b["key"]))
	var parent := []
	for i in layout.zone_ids.size():
		parent.append(i)
	var selected := []
	var family := String(template.get("layout_family", "frontiers"))
	for group in groups:
		var needed := false
		for pair in group["edges"]:
			if _root(parent, pair[0]) != _root(parent, pair[1]):
				needed = true
		var ring_edge := false
		if family == "ringlands":
			var order: Array = template["ring_order"]
			var p: Array = group["edges"][0]
			var a := order.find(layout.zone_ids[p[0]])
			var b := order.find(layout.zone_ids[p[1]])
			ring_edge = absi(a - b) == 1 or absi(a - b) == order.size() - 1
		var take: bool = ring_edge or rng.chance(float(template.get("loop_chance", 0.25))) if family == "ringlands" else needed or rng.chance(float(template.get("loop_chance", 0.25)))
		if not take:
			continue
		var guard := "medium" if rng.chance(0.65) else "weak"
		for pair in group["edges"]:
			parent[_root(parent, pair[0])] = _root(parent, pair[1])
			selected.append({"a": layout.zone_ids[pair[0]], "b": layout.zone_ids[pair[1]],
				"width": 1, "guard": guard, "road": true, "group": "edge_" + String(group["key"])})
	for i in parent.size():
		if _root(parent, i) != _root(parent, 0):
			layout.errors.append("recipe graph is disconnected")
			return []
	return selected


static func _key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func _root(parent: Array, i: int) -> int:
	while int(parent[i]) != i:
		i = int(parent[i])
	return i
