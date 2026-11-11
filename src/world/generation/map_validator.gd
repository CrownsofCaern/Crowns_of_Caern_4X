class_name MapValidator
extends RefCounted
## Checks a map definition (hand-made or generated) for structural validity,
## connectivity and, for generated maps, start fairness.
##
## Reachability is 4-connected over passable tiles (see GridSearch). "Open"
## means blockers (MapGenerator.blocks_path) count as beatable; "safe" means they block.

const KNOWN_TYPES := ["resource", "neutral_army", "mine", "town", "encounter", "artifact", "site", "scenario_site", "quest_item", "gate"]
## Value of one unit of each resource in gold, for comparing pickups.
const RESOURCE_VALUE := {"gold": 1, "wood": 100, "ore": 100}
const RARE_VALUE := 250
## Start-to-own-mine cost ceilings and fairness tolerances.
const MAX_BASIC_MINE_COST := 1500
const MINE_COST_TOLERANCE := 450
const ENEMY_COST_RATIO := 1.35


static func validate(def: Dictionary, data: GameData) -> Array[String]:
	var errors := _structure(def, data)
	if not errors.is_empty():
		return errors
	errors.append_array(ScenarioRules.validate(def.get("scenario", {}), def, data))
	if not errors.is_empty():
		return errors
	var g := _Grid.new(def, data)
	for obj in def.get("scenario", {}).get("objectives", []):
		if obj["type"] == "reach":
			var p := Vector2i(int(obj["pos"][0]), int(obj["pos"][1]))
			if not g.map.is_passable(p):
				errors.append("scenario reach target is impassable")
	errors.append_array(_objects(def, data, g))
	if not errors.is_empty():
		return errors
	errors.append_array(_connectivity(def, g))
	if def.has("generator"):
		errors.append_array(_start_safety(def, g))
		var policy := String(def["generator"].get("policy", "fair"))
		if policy == "fair":
			errors.append_array(_fairness_errors(fairness(def, data)))
		elif policy == "adventure":
			for metrics in fairness(def, data):
				for resource in ["wood", "ore"]:
					var cost := int(metrics["mine_cost"].get(resource, -1))
					if cost < 0 or cost > 2500:
						errors.append("Adventure start lacks usable %s income" % resource)
		else:
			errors.append("unknown generation policy %s" % policy)
	return errors


static func _structure(def: Dictionary, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	for key in ["id", "width", "height", "terrain", "players", "heroes", "objects"]:
		if not def.has(key):
			errors.append("map missing %s" % key)
	if not errors.is_empty():
		return errors
	var w := int(def["width"])
	var h := int(def["height"])
	var rows: Array = def["terrain"]
	if rows.size() != h:
		errors.append("expected %d terrain rows, got %d" % [h, rows.size()])
		return errors
	for y in h:
		var row := String(rows[y])
		if row.length() != w:
			errors.append("row %d has width %d, expected %d" % [y, row.length(), w])
			continue
		for x in w:
			if not data.terrain_by_char.has(row[x]):
				errors.append("unknown terrain char '%s' at %d,%d" % [row[x], x, y])
	for seg in def.get("roads", []):
		for key in ["from", "to"]:
			var p := Vector2i(int(seg[key][0]), int(seg[key][1]))
			if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
				errors.append("road endpoint %s out of bounds" % p)
	for pd in def["players"]:
		var level := String(pd.get("difficulty", ""))
		if level != "" and not data.difficulty_levels().has(level):
			errors.append("player %s has unknown difficulty %s" % [pd.get("id", "?"), level])
		var team := int(pd.get("team", 0))
		if team < 0 or team > GameSetup.MAX_TEAMS:
			errors.append("player %s has team %d (0 = none, up to %d)" % [pd.get("id", "?"), team, GameSetup.MAX_TEAMS])
	return errors


static func _objects(def: Dictionary, data: GameData, g: _Grid) -> Array[String]:
	var errors: Array[String] = []
	var ids := {}
	var at := {}
	var town_owner := {}   # town id -> owner
	for o in def["objects"]:
		if String(o.get("type", "")) == "town":
			town_owner[String(o.get("id", ""))] = int(o.get("owner", -1))
	for o in def["objects"] + def["heroes"]:
		var oid := String(o.get("id", ""))
		if oid == "" or ids.has(oid):
			errors.append("missing or duplicate id '%s'" % oid)
		ids[oid] = true
		var p := Vector2i(int(o["pos"][0]), int(o["pos"][1]))
		if not g.in_bounds(p):
			errors.append("%s out of bounds" % oid)
			continue
		if not g.map.is_passable(p):
			errors.append("%s stands on impassable %s" % [oid, g.map.terrain_at(p)])
		# A hero may start inside its own player's town (it stands in the gate).
		var in_own_town: bool = o.has("class") and at.has(p) and int(town_owner.get(at[p], -2)) == int(o.get("owner", -1))
		if at.has(p) and not in_own_town:
			errors.append("%s and %s share tile %s" % [oid, at[p], p])
		at[p] = oid
	for o in def["objects"]:
		var t := String(o.get("type", ""))
		if not KNOWN_TYPES.has(t):
			errors.append("%s has unknown type %s" % [o["id"], t])
		match t:
			"resource", "mine":
				if not data.resources.has(o.get("resource", "")):
					errors.append("%s has unknown resource" % o["id"])
				for s in o.get("guard", []):
					if not data.creatures.has(s[0]) or int(s[1]) < 1:
						errors.append("%s has bad guard stack %s" % [o["id"], s])
			"neutral_army":
				if o.get("stacks", []).is_empty():
					errors.append("%s has no stacks" % o["id"])
				for s in o.get("stacks", []):
					if not data.creatures.has(s[0]) or int(s[1]) < 1:
						errors.append("%s has bad stack %s" % [o["id"], s])
			"town":
				if not data.town_types.has(o.get("town_type", "")):
					errors.append("%s has unknown town_type" % o["id"])
				for s in o.get("garrison", []):
					if not data.creatures.has(s[0]) or int(s[1]) < 1:
						errors.append("%s has bad garrison stack %s" % [o["id"], s])
			"encounter":
				if not data.encounters.has(o.get("encounter", "")):
					errors.append("%s has unknown encounter" % o["id"])
			"artifact":
				if not data.artifacts.has(o.get("artifact", "")):
					errors.append("%s has unknown artifact" % o["id"])
			"scenario_site":
				if o.get("kind", "") not in ["quest", "nest", "watchtower", "siege_camp", "forge", "supplies", "observatory", "goal"]:
					errors.append("unknown scenario site kind")
				for stack in o.get("guard", []):
					if not data.creatures.has(stack[0]) or int(stack[1]) < 1:
						errors.append("bad scenario site guard")
			"quest_item":
				if String(o.get("item", "")) == "":
					errors.append("quest item needs an item id")
			"gate":
				if typeof(o.get("closed", false)) != TYPE_BOOL:
					errors.append("gate closed state must be boolean")
			"site":
				if MapCobolts.is_post(o, data):
					errors.append_array(MapCobolts.object_errors(o, data))
				if not data.sites.has(o.get("site", "")):
					errors.append("%s has unknown site" % o["id"])
				elif String(data.sites[o["site"]]["kind"]) == "dwelling" and not data.creatures.has(o.get("creature", "")):
					errors.append("%s has unknown creature" % o["id"])
				elif String(data.sites[o["site"]]["kind"]) == "village":
					var stock: Variant = o.get("stock", [])
					if typeof(stock) != TYPE_ARRAY or stock.size() > 2:
						errors.append("%s village stock must hold at most two stacks" % o["id"])
					else:
						for s in stock:
							if typeof(s) != TYPE_ARRAY or s.size() != 2 or not data.creatures.has(s[0]) or int(s[1]) < 0:
								errors.append("%s has bad village stock %s" % [o["id"], s])
				for s in o.get("guard", []):
					if not data.creatures.has(s[0]) or int(s[1]) < 1:
						errors.append("%s has bad guard stack %s" % [o["id"], s])
	for hd in def["heroes"]:
		if not data.hero_classes.has(hd.get("class", "")):
			errors.append("hero %s has unknown class" % hd["id"])
	return errors


static func _connectivity(def: Dictionary, g: _Grid) -> Array[String]:
	var errors: Array[String] = []
	if def["heroes"].is_empty():
		return errors
	var reach := GridSearch.flood(g.w, g.h, g.open_mask(false), PackedInt32Array([g.idx_of(def["heroes"][0])]))
	for o in def["objects"] + def["heroes"]:
		if reach[g.idx_of(o)] == 0:
			errors.append("%s is unreachable" % o["id"])
	var stranded := 0
	var open := g.open_mask(false)
	for i in open.size():
		if open[i] != 0 and reach[i] == 0:
			stranded += 1
	if stranded > 0:
		errors.append("%d passable tiles are unreachable" % stranded)
	return errors


## Each player can reach their own town and unguarded start-zone content
## without a fight, and cannot reach another player's hero without one.
static func _start_safety(def: Dictionary, g: _Grid) -> Array[String]:
	var errors: Array[String] = []
	var safe := g.open_mask(true)
	for hd in def["heroes"]:
		var pl := int(hd["owner"])
		var zone := _start_zone(def, pl)
		var reach := GridSearch.flood(g.w, g.h, safe, PackedInt32Array([g.idx_of(hd)]))
		for o in def["objects"]:
			if o.get("zone", "") != zone or MapGenerator.blocks_path(o) or o.has("guarded_by"):
				continue
			if reach[g.idx_of(o)] == 0:
				errors.append("player %d cannot reach own %s without a fight" % [pl, o["id"]])
		for other in def["heroes"]:
			if int(other["owner"]) != pl and reach[g.idx_of(other)] != 0:
				errors.append("player %d can reach %s without passing a guard" % [pl, other["id"]])
	return errors


static func _start_zone(def: Dictionary, player: int) -> String:
	for z in def["generator"]["zones"]:
		if int(z.get("player", -1)) == player:
			return String(z["id"])
	return ""


## Per-player start metrics: what the start zone holds and how far things are.
static func fairness(def: Dictionary, data: GameData) -> Array:
	var g := _Grid.new(def, data)
	var out: Array = []
	var safe_cost := g.cost_array(true)
	var open_cost := g.cost_array(false)
	for hd in def["heroes"]:
		var pl := int(hd["owner"])
		var zone := _start_zone(def, pl)
		var src := PackedInt32Array([g.idx_of(hd)])
		var safe_d := GridSearch.distances(g.w, g.h, safe_cost, src)
		var open_d := GridSearch.distances(g.w, g.h, open_cost, src)
		var m := {"player": pl, "zone": zone, "signature": [], "mine_cost": {}, "guard_value": 0,
			"day_one_value": 0, "pile_value": 0, "enemy_town_cost": -1}
		var sig: Array = []
		for o in def["objects"]:
			var i := g.idx_of(o)
			if o.get("zone", "") == zone:
				match String(o["type"]):
					"mine":
						var kind := String(o["resource"]) if RESOURCE_VALUE.has(o["resource"]) else "rare"
						sig.append("mine:%s:%s" % [kind, "guarded" if o.has("guard") else "free"])
						var c := open_d[i]
						if not m["mine_cost"].has(kind) or c < int(m["mine_cost"][kind]):
							m["mine_cost"][kind] = c
					"resource":
						sig.append("treasure" if o.get("treasure", false) else "pile")
						m["pile_value"] += int(o["amount"]) * int(RESOURCE_VALUE.get(o["resource"], RARE_VALUE))
						if not o.has("guarded_by") and safe_d[i] >= 0 and safe_d[i] <= 1500:
							var unit := int(RESOURCE_VALUE.get(o["resource"], RARE_VALUE))
							m["day_one_value"] += int(o["amount"]) * unit
					"neutral_army":
						# Gate guards sit on whichever side of the wall the pass was cut.
						if o.get("role", "") != "gate":
							m["guard_value"] += int(o.get("value", 0))
							sig.append("army:%s" % o.get("role", ""))
					"town":
						sig.append("town")
					"encounter":
						sig.append("encounter")
					"artifact":
						sig.append("artifact:%s" % ("guarded" if o.has("guarded_by") else "free"))
					"site":
						sig.append("site:%s" % o["site"])
			if o["type"] == "town" and int(o.get("owner", -1)) >= 0 and int(o["owner"]) != pl:
				if m["enemy_town_cost"] < 0 or open_d[i] < m["enemy_town_cost"]:
					m["enemy_town_cost"] = open_d[i]
		sig.sort()
		m["signature"] = sig
		out.append(m)
	return out


static func _fairness_errors(metrics: Array) -> Array[String]:
	var errors: Array[String] = []
	if metrics.size() < 2:
		return errors
	var first: Dictionary = metrics[0]
	for m in metrics:
		for kind in ["wood", "ore"]:
			var c := int(m["mine_cost"].get(kind, -1))
			if c < 0 or c > MAX_BASIC_MINE_COST:
				errors.append("player %d: own %s mine costs %d to reach" % [m["player"], kind, c])
		if m["signature"] != first["signature"]:
			errors.append("player %d start content differs from player %d" % [m["player"], first["player"]])
		if m["pile_value"] != first["pile_value"]:
			errors.append("player %d start pickups differ in value" % m["player"])
		if m["guard_value"] != first["guard_value"]:
			errors.append("player %d start guards differ in strength" % m["player"])
		for kind in first["mine_cost"]:
			var a := int(first["mine_cost"][kind])
			var b := int(m["mine_cost"].get(kind, -1))
			if b < 0 or absi(a - b) > maxi(MINE_COST_TOLERANCE, mini(a, b) / 2):
				errors.append("player %d: %s mine distance %d vs %d" % [m["player"], kind, b, a])
	var lo := INF
	var hi := 0.0
	for m in metrics:
		var c := float(m["enemy_town_cost"])
		if c < 0:
			errors.append("player %d cannot reach an enemy town" % m["player"])
			continue
		lo = minf(lo, c)
		hi = maxf(hi, c)
	if lo < INF and hi > lo * ENEMY_COST_RATIO:
		errors.append("distance to the enemy differs too much (%d vs %d)" % [lo, hi])
	return errors


## Static view of a definition: passability and costs, objects as blockers.
class _Grid:
	var w: int
	var h: int
	var map: AdventureMap
	var blocked := PackedByteArray()

	func _init(def: Dictionary, data: GameData) -> void:
		var d := def.duplicate()
		d["objects"] = []
		map = AdventureMap.from_definition(d, data)
		w = map.width
		h = map.height
		blocked.resize(w * h)
		for o in def["objects"]:
			if MapGenerator.blocks_path(o):
				blocked[idx_of(o)] = 1

	func in_bounds(p: Vector2i) -> bool:
		return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

	func idx_of(o: Dictionary) -> int:
		return int(o["pos"][1]) * w + int(o["pos"][0])

	func open_mask(blockers: bool) -> PackedByteArray:
		var m := PackedByteArray()
		m.resize(w * h)
		for i in w * h:
			if map.is_passable(Vector2i(i % w, i / w)) and not (blockers and blocked[i] != 0):
				m[i] = 1
		return m

	func cost_array(blockers: bool) -> PackedInt32Array:
		var c := PackedInt32Array()
		c.resize(w * h)
		for i in w * h:
			var p := Vector2i(i % w, i / w)
			if map.is_passable(p) and not (blockers and blocked[i] != 0):
				c[i] = map.move_cost(p)
		return c
