class_name Town
extends RefCounted
## Rules for one town. A town is a map object dictionary (so it saves with the
## map) with these fields:
##   id, type = "town", pos, name, town_type (faction id), owner (-1 = neutral),
##   built: [building ids], last_build_day: int,
##   available: {creature id: count}  (recruitment pool, refilled weekly),
##   garrison: Army.to_dict() slots,
##   tier_cap: int (optional): creatures above this tier cannot be built for or
##     recruited here (a campaign chapter's max_tier; absent or 0 = no limit).
##   available is keyed by the BASE creature: an upgraded creature (creature def
##   with "upgrade_of") is recruited from its base's pool once the town has a
##   dwelling_upgrade building for that base.
## All functions are static and take the dictionary, so the session, the AI and
## tests share one implementation and nothing keeps a second copy of the state.


## Fills in defaults and converts map-definition shorthand (garrison as
## [creature, count] pairs) into the runtime layout. Idempotent.
static func normalize(t: Dictionary, data: GameData) -> void:
	var tt: Dictionary = data.town_types[t["town_type"]]
	if not t.has("name"):
		t["name"] = tt["name"]
	t["owner"] = int(t.get("owner", -1))
	if not t.has("built"):
		t["built"] = (tt["starting_buildings"] as Array).duplicate()
	t["last_build_day"] = int(t.get("last_build_day", 0))
	# Coerce everything to ints: JSON loads numbers as floats.
	var g: Array = t.get("garrison", [])
	if not g.is_empty() and typeof(g[0]) == TYPE_ARRAY:
		t["garrison"] = Army.from_pairs(g).to_dict()
	else:
		t["garrison"] = Army.from_dict(g).to_dict()
	var veteran_garrison := Army.from_dict(t["garrison"])
	veteran_garrison.initialize_veterans(data)
	t["garrison"] = veteran_garrison.to_dict()
	if t.has("available"):
		var avail := {}
		for c in t["available"]:
			avail[c] = int(t["available"][c])
		t["available"] = avail
	else:
		t["available"] = {}
		for c in dwellings(t, data):
			t["available"][c] = weekly_growth(t, c, data)


## Sets the highest tier this town may build and recruit (0 removes the limit).
static func set_tier_cap(t: Dictionary, cap: int) -> void:
	if cap > 0:
		t["tier_cap"] = cap
	else:
		t.erase("tier_cap")


static func tier_allowed(t: Dictionary, creature_id: String, data: GameData) -> bool:
	var cap := int(t.get("tier_cap", 0))
	return cap <= 0 or int(data.creature(creature_id)["tier"]) <= cap


## True if the building houses or improves a creature above the town's tier cap.
static func locked_by_tier(t: Dictionary, building_id: String, data: GameData) -> bool:
	for e in building(t, building_id, data).get("effects", []):
		if e["type"] in ["dwelling", "dwelling_upgrade", "growth"] and not tier_allowed(t, String(e["creature"]), data):
			return true
		if e["type"] == "army_upgrade":
			var cap := int(t.get("tier_cap", 0))
			if cap > 0 and cap < Economy.ARMY_UPGRADE_TIER:
				return true
	return false


static func building(t: Dictionary, building_id: String, data: GameData) -> Dictionary:
	return data.town_types[t["town_type"]]["buildings"].get(building_id, {})


static func building_ids(t: Dictionary, data: GameData) -> Array:
	return data.town_types[t["town_type"]]["buildings"].keys()


static func has_building(t: Dictionary, building_id: String) -> bool:
	return (t["built"] as Array).has(building_id)


## All effects of every building in the town, in build order.
static func effects(t: Dictionary, data: GameData) -> Array:
	var out := []
	for b in t["built"]:
		out.append_array(building(t, b, data).get("effects", []))
	return out


static func has_effect(t: Dictionary, effect_type: String, data: GameData) -> bool:
	for e in effects(t, data):
		if e["type"] == effect_type:
			return true
	return false


static func missing_requirements(t: Dictionary, building_id: String, data: GameData) -> Array:
	var out := []
	for r in building(t, building_id, data).get("requires", []):
		if not has_building(t, r):
			out.append(r)
	return out


## Building cost after this town's build discounts.
static func build_cost(t: Dictionary, building_id: String, data: GameData) -> Dictionary:
	var base: Dictionary = building(t, building_id, data).get("cost", {})
	var discount := {}
	for e in effects(t, data):
		if e["type"] == "build_discount":
			for res in e["resources"]:
				discount[res] = minf(0.9, float(discount.get(res, 0.0)) + float(e["resources"][res]))
	var out := {}
	for res in base:
		var amount := int(round(int(base[res]) * (1.0 - float(discount.get(res, 0.0)))))
		if amount > 0:
			out[res] = amount
	return out


## Why the building cannot be built right now, or "" if it can.
static func build_error(t: Dictionary, building_id: String, bank: ResourceBank, day: int, data: GameData) -> String:
	if building(t, building_id, data).is_empty():
		return "unknown building"
	if has_building(t, building_id):
		return "already built"
	if locked_by_tier(t, building_id, data):
		return "unlocks in a later chapter"
	if int(t["last_build_day"]) == day:
		return "already built today"
	var missing := missing_requirements(t, building_id, data)
	if not missing.is_empty():
		var names := []
		for m in missing:
			names.append(building(t, m, data)["name"])
		return "requires " + ", ".join(names)
	if not bank.can_afford(build_cost(t, building_id, data)):
		return "not enough resources"
	return ""


## Applies a construction (the caller has checked build_error and paid).
## A new dwelling starts with one week of growth, so it pays off immediately.
static func construct(t: Dictionary, building_id: String, day: int, data: GameData) -> void:
	t["built"].append(building_id)
	t["last_build_day"] = day
	for e in building(t, building_id, data).get("effects", []):
		if e["type"] == "dwelling":
			var c: String = e["creature"]
			t["available"][c] = int(t["available"].get(c, 0)) + weekly_growth(t, c, data)


## Creature ids recruitable here, ordered by tier. Dwellings above the tier
## cap stand idle: they neither grow nor recruit.
static func dwellings(t: Dictionary, data: GameData) -> Array:
	var out := []
	for e in effects(t, data):
		if e["type"] == "dwelling" and not out.has(e["creature"]) and tier_allowed(t, e["creature"], data):
			out.append(e["creature"])
	out.sort_custom(func(a, b): return int(data.creature(a)["tier"]) < int(data.creature(b)["tier"]))
	return out


## The pool a creature is recruited from (its base creature for upgrades).
static func pool_of(creature_id: String, data: GameData) -> String:
	return String(data.creature(creature_id).get("upgrade_of", creature_id))


## Base creatures whose upgrade this town can recruit and convert to.
static func upgraded_dwellings(t: Dictionary, data: GameData) -> Array:
	var out := []
	for e in effects(t, data):
		if e["type"] == "dwelling_upgrade" and not out.has(e["creature"]) and tier_allowed(t, e["creature"], data):
			out.append(e["creature"])
	return out


## Upgraded creature id for this base if the town can produce it, else "".
static func upgrade_for(t: Dictionary, base_id: String, data: GameData) -> String:
	var up := String(data.creature(base_id).get("upgrade", ""))
	if up == "" or not upgraded_dwellings(t, data).has(base_id):
		return ""
	return up


## Everything recruitable here: each dwelling's creature, followed by its
## upgrade when the upgrade building stands. Ordered by tier.
static func recruitable(t: Dictionary, data: GameData) -> Array:
	var out := []
	for c in dwellings(t, data):
		out.append(c)
		var up := upgrade_for(t, c, data)
		if up != "":
			out.append(up)
	return out


## Per-resource price to turn `count` base creatures into their upgrade.
static func upgrade_cost(base_id: String, count: int, data: GameData) -> Dictionary:
	var base: Dictionary = data.creature(base_id).get("cost", {})
	var up: Dictionary = data.creature(String(data.creature(base_id).get("upgrade", ""))).get("cost", {})
	var out := {}
	for res in up:
		var diff := (int(up[res]) - int(base.get(res, 0))) * count
		if diff > 0:
			out[res] = diff
	return out


## extra_pct: a bonus on top of the town's own (the week's omen, WorldEvents.growth_bonus).
static func weekly_growth(t: Dictionary, creature_id: String, data: GameData, extra_pct: float = 0.0) -> int:
	var flat := int(data.creature(creature_id).get("growth", 0))
	var pct := extra_pct
	for e in effects(t, data):
		if e["type"] == "growth" and e["creature"] == creature_id:
			flat += int(e["amount"])
		elif e["type"] == "growth_pct":
			pct += float(e["pct"])
	return maxi(0, int(floor(flat * (1.0 + pct))))


## bonus: {creature id: extra growth pct} for this week (absent = none).
static func apply_weekly_growth(t: Dictionary, data: GameData, bonus: Dictionary = {}) -> void:
	for c in dwellings(t, data):
		t["available"][c] = int(t["available"].get(c, 0)) + weekly_growth(t, c, data, float(bonus.get(c, 0.0)))


static func daily_income(t: Dictionary, data: GameData) -> Dictionary:
	var out := {}
	for e in effects(t, data):
		if e["type"] == "income":
			for res in e["resources"]:
				out[res] = int(out.get(res, 0)) + int(e["resources"][res])
	return out


static func defense_bonus(t: Dictionary, data: GameData) -> int:
	var d := 0
	for e in effects(t, data):
		if e["type"] == "defense":
			d += int(e["amount"])
	return d


static func garrison(t: Dictionary) -> Army:
	return Army.from_dict(t["garrison"])


static func set_garrison(t: Dictionary, army: Army) -> void:
	t["garrison"] = army.to_dict()


static func recruit_cost(creature_id: String, count: int, data: GameData) -> Dictionary:
	var out := {}
	var unit: Dictionary = data.creature(creature_id).get("cost", {})
	for res in unit:
		out[res] = int(unit[res]) * count
	return out


## How many creatures of this type the bank can pay for and the pool holds.
static func max_affordable(t: Dictionary, creature_id: String, bank: ResourceBank, data: GameData) -> int:
	if not recruitable(t, data).has(creature_id):
		return 0
	var n := int(t["available"].get(pool_of(creature_id, data), 0))
	var unit: Dictionary = data.creature(creature_id).get("cost", {})
	for res in unit:
		if int(unit[res]) > 0:
			n = mini(n, bank.get_amount(res) / int(unit[res]))
	return maxi(0, n)


static func recruit_error(t: Dictionary, creature_id: String, count: int, bank: ResourceBank, data: GameData) -> String:
	if count <= 0:
		return "nothing to recruit"
	if not recruitable(t, data).has(creature_id):
		return "no dwelling for this creature"
	var pool := int(t["available"].get(pool_of(creature_id, data), 0))
	if pool < count:
		return "only %d available" % pool
	if not bank.can_afford(recruit_cost(creature_id, count, data)):
		return "not enough resources"
	return ""
