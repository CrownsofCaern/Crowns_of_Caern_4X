class_name Hamlets
extends RefCounted
## Hamlets, villages and freeholds (map sites of kind "hamlet", data/sites.json;
## rules in game_rules.json "hamlets"). A game started with setup.hamlets (the
## new-game default; a Classic game has none) gets them placed on its map here,
## whatever map it is, so the map generator and every other mode stay as they
## were.
##
## A held hamlet pays gold every day and raises a weekly levy of one creature.
## The unhired levy defends the site. A levy of at least one week's growth
## that stands unhired for unrest_weeks full weeks makes the hamlet restless;
## from the week after it may turn neutral, guarded by that same levy. A
## hamlet with a garrison worth garrison_weeks of its levy, or within
## realm_radius of one of its owner's towns, never does. All functions are static, like MapSites.

const SEED_SALT := 0x48414d4c   # a stream of its own: placing hamlets never shifts the game's rolls


static func config(data: GameData) -> Dictionary:
	return data.rules.get("hamlets", {})


static func enabled(state: GameState) -> bool:
	return bool(state.rules.get("hamlets", false))


# -------------------------------------------------------------- placement --

## Adds the hamlets of a new game to the map: each player's own, by movement
## cost from its first town and nearer to it than to any rival's, then the
## contested ones where the two nearest players are about equally far. Sites
## that find no open tile are left out. Returns the placed object ids.
static func place(map: AdventureMap, players: int, seed_value: int, data: GameData) -> Array:
	var cfg := config(data)
	var placed: Array = []
	if cfg.is_empty():
		return placed
	var rng := GameRng.new(seed_value ^ SEED_SALT)
	var move := int(data.progression["base_movement"])
	var towns := {}   # player -> its first town (lowest id)
	var ids := map.objects.keys()
	ids.sort()
	for id in ids:
		var o: Dictionary = map.objects[id]
		var owner := int(o.get("owner", -1))
		if o["type"] == "town" and owner >= 0 and owner < players and not towns.has(owner):
			towns[owner] = o
	if towns.is_empty():
		return placed
	var fields := {}
	for owner in towns:
		fields[owner] = AiDistanceField.build(map, AdventureMap.object_pos(towns[owner]), {})
	var taken := _taken(map)
	var owners := towns.keys()
	owners.sort()
	var index := 0
	for item in cfg.get("per_player", []):
		var days: Array = item.get("days", [1.0, 2.0])
		for owner in owners:
			var tiles := _own_tiles(map, fields, owner, int(float(days[0]) * move), int(float(days[1]) * move), taken)
			if tiles.is_empty():
				continue
			var p: Vector2i = tiles[rng.next_int(0, tiles.size() - 1)]
			placed.append(_add(map, String(item["site"]), p, index, _town_faction(towns[owner], data), rng, data))
			_claim(taken, p)
			index += 1
	if owners.size() >= 2:
		for item in cfg.get("contested", []):
			var copies := maxi(1, owners.size() / maxi(1, int(item.get("per_players", 2))))
			for _i in copies:
				var tiles := _contested_tiles(map, fields, owners, taken)
				if tiles.is_empty():
					break
				var p: Vector2i = tiles[rng.next_int(0, mini(tiles.size(), 12) - 1)]
				placed.append(_add(map, String(item["site"]), p, index, "", rng, data))
				_claim(taken, p)
				index += 1
	return placed


static func _town_faction(town: Dictionary, data: GameData) -> String:
	var tt := String(town.get("town_type", ""))
	return tt if data.town_types.has(tt) else ""


## Tiles next to any object are kept clear, so a hamlet never crowds a mine or blocks a guard's pocket.
static func _taken(map: AdventureMap) -> Dictionary:
	var taken := {}
	for id in map.objects:
		_claim(taken, AdventureMap.object_pos(map.objects[id]), 1)
	return taken


static func _claim(taken: Dictionary, p: Vector2i, radius: int = 3) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			taken[p + Vector2i(dx, dy)] = true


static func _open(map: AdventureMap, p: Vector2i, taken: Dictionary) -> bool:
	if taken.has(p) or not map.is_passable(p) or map.has_road(p):
		return false
	var open := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := p + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and map.in_bounds(n) and map.is_passable(n):
				open += 1
	return open >= 7


## Open tiles lo..hi movement from the owner's town and clearly nearer to it than to any rival's.
static func _own_tiles(map: AdventureMap, fields: Dictionary, owner: int, lo: int, hi: int, taken: Dictionary) -> Array:
	var out := []
	var own: AiDistanceField = fields[owner]
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var c := own.cost_to(p)
			if c < lo or c > hi or not _open(map, p, taken):
				continue
			var mine := true
			for other in fields:
				if other != owner:
					var oc: int = (fields[other] as AiDistanceField).cost_to(p)
					if oc >= 0 and oc * 2 < c * 3:
						mine = false
			if mine:
				out.append(p)
	return out


## Open tiles the two nearest players reach at about the same cost (within a
## tenth), best balanced first; ties by position.
static func _contested_tiles(map: AdventureMap, fields: Dictionary, owners: Array, taken: Dictionary) -> Array:
	var scored := []
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if not _open(map, p, taken):
				continue
			var best := -1
			var second := -1
			for owner in owners:
				var c: int = (fields[owner] as AiDistanceField).cost_to(p)
				if c < 0:
					continue
				if best < 0 or c < best:
					second = best
					best = c
				elif second < 0 or c < second:
					second = c
			if best <= 0 or second < 0 or (second - best) * 10 > second:
				continue
			scored.append([second - best, p])
	scored.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1].y < b[1].y or (a[1].y == b[1].y and a[1].x < b[1].x))))
	return scored.map(func(e): return e[1])


## faction: the folk the levy is drawn from ("" = any town faction).
static func _add(map: AdventureMap, site: String, p: Vector2i, index: int, faction: String, rng: GameRng, data: GameData) -> String:
	var def: Dictionary = data.sites[site]
	var pool := MapSites.creature_pool(def, data)
	var folk := pool.filter(func(c): return String(data.creature(c)["faction"]) == faction)
	if folk.is_empty():
		folk = pool
	var budget := int(data.map_templates["guard_levels"][String(def.get("guard", "light"))])
	var obj := {"id": "hamlet_%d" % index, "type": "site", "site": site, "pos": [p.x, p.y], "owner": -1,
		"creature": String(folk[rng.next_int(0, folk.size() - 1)]), "guard": ScenarioGenerator._guard(data, rng, budget)}
	MapSites.normalize(obj, data)
	map.add_object(obj)
	return String(obj["id"])


# ------------------------------------------------------------ the weekly turn --

## Gold worth (town prices) of the troops stationed in a hamlet.
static func garrison_worth(obj: Dictionary, data: GameData) -> int:
	var worth := 0
	for pair in obj.get("garrison", []):
		worth += int(pair[1]) * int(data.creature(String(pair[0])).get("cost", {}).get("gold", 0))
	return worth


## Gold worth of stationed troops that keeps a hamlet loyal: garrison_weeks
## weeks of its levy at town prices.
static func garrison_needed(obj: Dictionary, data: GameData) -> int:
	var c := String(obj.get("creature", ""))
	var week := maxi(1, MapSites.weekly_growth(obj, data)) * int(data.creature(c).get("cost", {}).get("gold", 0))
	return int(ceil(float(week) * float(config(data).get("garrison_weeks", 1.0))))


## True if the hamlet cannot revolt now: a garrison worth garrison_needed is
## stationed, or one of the owner's towns stands within realm_radius.
static func is_secure(obj: Dictionary, map: AdventureMap, data: GameData) -> bool:
	if not (obj.get("garrison", []) as Array).is_empty() and garrison_worth(obj, data) >= garrison_needed(obj, data):
		return true
	var r := int(config(data).get("realm_radius", 0))
	var pos := AdventureMap.object_pos(obj)
	for id in map.objects:
		var o: Dictionary = map.objects[id]
		if o["type"] == "town" and int(o.get("owner", -1)) == int(obj.get("owner", -1)):
			var d := AdventureMap.object_pos(o) - pos
			if d.x * d.x + d.y * d.y <= r * r:
				return true
	return false


## "" while calm, else a short note for tooltips ("restless", "on the brink of revolt").
static func mood(obj: Dictionary, data: GameData) -> String:
	if int(obj.get("owner", -1)) < 0:
		return ""
	var weeks := int(obj.get("idle_weeks", 0))
	var limit := int(config(data).get("unrest_weeks", 3))
	if weeks >= limit:
		return "on the brink of revolt"
	if weeks == limit - 1 and limit > 1:
		return "restless"
	return ""


## The start of a week for one held hamlet, before its levy grows: counts the
## idle week and may turn it neutral. Returns "" (calm), "unrest" or "revolt".
static func on_week(obj: Dictionary, map: AdventureMap, rng: GameRng, data: GameData) -> String:
	if int(obj.get("owner", -1)) < 0:
		return ""
	var cfg := config(data)
	var standing := int(obj.get("available", 0))
	var week := maxi(1, MapSites.weekly_growth(obj, data))
	if standing < week or is_secure(obj, map, data):
		obj["idle_weeks"] = 0
		return ""
	obj["idle_weeks"] = int(obj.get("idle_weeks", 0)) + 1
	var limit := int(cfg.get("unrest_weeks", 3))
	if int(obj["idle_weeks"]) == limit:
		return "unrest"
	if int(obj["idle_weeks"]) > limit and rng.next_float() < float(cfg.get("revolt_chance", 0.5)):
		obj["guard"] = [[String(obj["creature"]), standing]]
		obj["available"] = 0
		obj["owner"] = -1
		obj["idle_weeks"] = 0
		return "revolt"
	return ""


# ------------------------------------------------------------- validation --

static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var cfg := config(data)
	if cfg.is_empty():
		return errors
	for key in ["per_player", "contested"]:
		for item in cfg.get(key, []):
			var sid := String(item.get("site", ""))
			if not data.sites.has(sid) or String(data.sites[sid].get("kind", "")) != "hamlet":
				errors.append("game_rules hamlets.%s: %s is not a hamlet site" % [key, sid])
			if key == "per_player":
				var days: Variant = item.get("days", null)
				if typeof(days) != TYPE_ARRAY or days.size() != 2 or float(days[0]) < 0.0 or float(days[0]) > float(days[1]):
					errors.append("game_rules hamlets.per_player: %s needs days [min, max]" % sid)
			elif int(item.get("per_players", 0)) < 1:
				errors.append("game_rules hamlets.contested: %s needs per_players >= 1" % sid)
	if int(cfg.get("unrest_weeks", 0)) < 1:
		errors.append("game_rules hamlets.unrest_weeks must be >= 1")
	if float(cfg.get("revolt_chance", -1.0)) < 0.0 or float(cfg.get("revolt_chance", 2.0)) > 1.0:
		errors.append("game_rules hamlets.revolt_chance must be 0..1")
	if float(cfg.get("garrison_weeks", 0.0)) <= 0.0:
		errors.append("game_rules hamlets.garrison_weeks must be > 0")
	if int(cfg.get("realm_radius", -1)) < 0 or int(cfg.get("garrison_slots", 0)) < 1 or int(cfg.get("levy_cap_weeks", 0)) < 1:
		errors.append("game_rules hamlets needs realm_radius >= 0, garrison_slots >= 1 and levy_cap_weeks >= 1")
	return errors
