class_name RoamingThreats
extends RefCounted
## Map-wide threats from the weekly omens (data/events.json, effect "roamer"):
## a roaming horror rises somewhere in the wilds, far from every town, and
## walks toward the nearest town that someone holds. If it reaches the walls
## while no hero of the owner stands in the town, it ravages it (the owner
## loses gold and part of the town's recruits) and slinks back into the wild.
## Beating it pays its bounty. A roamer is an ordinary neutral army map object
## (so it saves with the map) with the extra keys:
##   roamer: true, steps (tiles a day), bounty {resource: n},
##   ravage {gold, pool_pct}, target (town id it is walking to)
## All randomness uses the game RNG; tiles and objects are visited in sorted order.

const MIN_TOWN_DISTANCE := 10
const MIN_HERO_DISTANCE := 5


## Spawns the roamers of this week's omen. Returns the spawned objects.
static func on_week(session: GameSession) -> Array:
	var out := []
	var def := WorldEvents.omen_def(session.state, session.data)
	for e in def.get("effects", []):
		if String(e["type"]) != "roamer":
			continue
		var packs: Array = e["packs"]
		var pack: Dictionary = packs[session.state.rng.next_int(0, packs.size() - 1)]
		var at := spawn_tile(session)
		if at == Vector2i(-1, -1):
			continue
		var stacks := []
		for st in pack["stacks"]:
			stacks.append([String(st["creature"]), int(st["count"]) + int(st.get("per_week", 0)) * (session.state.week() - 1)])
		var o := {"id": "roamer_w%d_%d" % [session.state.week(), out.size()], "type": "neutral_army", "pos": [at.x, at.y],
			"name": String(pack["name"]), "stacks": stacks, "roamer": true, "steps": int(e.get("steps", 6)),
			"bounty": (e.get("bounty", {}) as Dictionary).duplicate(), "ravage": (e.get("ravage", {}) as Dictionary).duplicate()}
		session.state.map.add_object(o)
		out.append(o)
	return out


## A free tile far from every town and hero ((-1, -1) if there is none).
static func spawn_tile(session: GameSession) -> Vector2i:
	var map := session.state.map
	var occupied := {}
	var towns: Array[Vector2i] = []
	for id in _sorted_ids(map):
		var o: Dictionary = map.objects[id]
		occupied[AdventureMap.object_pos(o)] = true
		if o["type"] == "town":
			towns.append(AdventureMap.object_pos(o))
	var heroes: Array[Vector2i] = []
	for id in session.state.heroes:
		var h: Hero = session.state.heroes[id]
		if h.alive:
			heroes.append(h.pos)
			occupied[h.pos] = true
	var candidates: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if occupied.has(p) or not map.is_passable(p) or map.has_road(p):
				continue
			if towns.any(func(t): return _dist(t, p) < MIN_TOWN_DISTANCE):
				continue
			if heroes.any(func(hp): return _dist(hp, p) < MIN_HERO_DISTANCE):
				continue
			candidates.append(p)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[session.state.rng.next_int(0, candidates.size() - 1)]


## Every roamer walks toward its town. Returns news lines per player index.
static func on_day(session: GameSession) -> Dictionary:
	var news := {}
	var map := session.state.map
	for id in _sorted_ids(map):
		if not map.objects.has(id):
			continue
		var o: Dictionary = map.objects[id]
		if not bool(o.get("roamer", false)):
			continue
		var t := target_town(session, o)
		if t.is_empty():
			continue
		o["target"] = t["id"]
		var tp := AdventureMap.object_pos(t)
		_walk(session, o, tp)
		if _dist(AdventureMap.object_pos(o), tp) <= 1 and not _defended(session, t):
			var owner := int(t["owner"])
			var lines: Array = news.get(owner, [])
			lines.append(ravage(session, o, t))
			news[owner] = lines
			map.remove_object(id)
	return news


## The nearest town anyone holds (straight distance, ties by id); {} if none.
static func target_town(session: GameSession, o: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 1 << 30
	var at := AdventureMap.object_pos(o)
	for id in _sorted_ids(session.state.map):
		var t: Dictionary = session.state.map.objects[id]
		if t["type"] != "town" or int(t.get("owner", -1)) < 0:
			continue
		var d := _dist(at, AdventureMap.object_pos(t))
		if d < best_d:
			best_d = d
			best = t
	return best


## A hero of the town's owner inside keeps the horror at bay.
static func _defended(session: GameSession, t: Dictionary) -> bool:
	var h := session.state.hero_at(AdventureMap.object_pos(t))
	return h != null and h.owner == int(t["owner"])


static func _walk(session: GameSession, o: Dictionary, goal: Vector2i) -> void:
	var map := session.state.map
	var extra: Array[Vector2i] = []
	for hid in session.state.heroes:
		var h: Hero = session.state.heroes[hid]
		if h.alive:
			extra.append(h.pos)
	var path := session.pathfinder.find_path(AdventureMap.object_pos(o), goal, extra)
	var steps := int(o.get("steps", 6))
	var dest := AdventureMap.object_pos(o)
	for i in mini(steps, path.size()):
		var p: Vector2i = path[i]
		if p == goal or not map.object_at(p).is_empty():
			break
		dest = p
	if dest != AdventureMap.object_pos(o):
		map.remove_object(String(o["id"]))
		o["pos"] = [dest.x, dest.y]
		map.add_object(o)


## The horror ravages the town: its owner loses gold and a share of the
## town's recruits. Returns the news line.
static func ravage(session: GameSession, o: Dictionary, t: Dictionary) -> String:
	var r: Dictionary = o.get("ravage", {})
	var bank: ResourceBank = session.state.player(int(t["owner"]))["resources"]
	var gold := mini(int(r.get("gold", 0)), bank.get_amount("gold"))
	if gold > 0:
		bank.spend({"gold": gold})
	var lost := 0
	var avail: Dictionary = t.get("available", {})
	var keys := avail.keys()
	keys.sort()
	for c in keys:
		var n := int(floor(int(avail[c]) * float(r.get("pool_pct", 0.0))))
		avail[c] = int(avail[c]) - n
		lost += n
	return "%s ravages %s: -%d gold, %d recruits lost. It slinks back into the wild." % [o.get("name", "A roaming horror"), t["name"], gold, lost]


## The bounty paid for beating a roamer ({} for other armies).
static func bounty(o: Dictionary) -> Dictionary:
	return o.get("bounty", {}) if bool(o.get("roamer", false)) else {}


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _sorted_ids(map: AdventureMap) -> Array:
	var ids := map.objects.keys()
	ids.sort()
	return ids


static func validate_effect(e: Dictionary, where: String, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var packs: Array = e.get("packs", [])
	if packs.is_empty():
		errors.append("%s roamer needs packs" % where)
	for pack in packs:
		if String(pack.get("name", "")) == "":
			errors.append("%s roamer pack needs a name" % where)
		var stacks: Array = pack.get("stacks", [])
		if stacks.is_empty() or stacks.size() > Army.MAX_SLOTS:
			errors.append("%s roamer pack needs 1-%d stacks" % [where, Army.MAX_SLOTS])
		for st in stacks:
			if data.creature(String(st.get("creature", ""))).is_empty() or int(st.get("count", 0)) <= 0:
				errors.append("%s roamer pack has an invalid stack" % where)
	if int(e.get("steps", 0)) <= 0:
		errors.append("%s roamer needs steps > 0" % where)
	for res in e.get("bounty", {}):
		if not data.resources.has(res):
			errors.append("%s roamer bounty has unknown resource %s" % [where, res])
	var r: Dictionary = e.get("ravage", {})
	if float(r.get("pool_pct", 0.0)) < 0.0 or float(r.get("pool_pct", 0.0)) > 1.0 or int(r.get("gold", 0)) < 0:
		errors.append("%s roamer ravage needs gold >= 0 and pool_pct in [0, 1]" % where)
	return errors
