class_name Economy
extends RefCounted
## Player-level economy rules: daily income from towns and mines, ownership
## queries, market trading, and validation of data/buildings.json.

const CATEGORIES := ["civic", "defense", "dwelling", "upgrade", "growth", "special", "ultimate"]
const EFFECT_TYPES := ["income", "dwelling", "growth", "growth_pct", "defense", "tavern", "market", "build_discount", "battle_spoils", "dwelling_upgrade", "army_upgrade"]
## Numeric bonuses an army_upgrade effect may carry (whole numbers for the stats, fractions for the rest).
const ARMY_UPGRADE_STATS := ["attack", "defense", "initiative", "morale"]
const ARMY_UPGRADE_PCTS := ["hp_pct", "damage_pct", "ranged_damage_pct", "shot_resist_pct"]
## The tier an army_upgrade building counts as for a campaign chapter's max_tier.
const ARMY_UPGRADE_TIER := 8


static func towns_of(map: AdventureMap, player_idx: int) -> Array:
	var out := []
	for id in map.objects:
		var o: Dictionary = map.objects[id]
		if o["type"] == "town" and int(o["owner"]) == player_idx:
			out.append(o)
	return out


static func mines_of(map: AdventureMap, player_idx: int) -> Array:
	var out := []
	for id in map.objects:
		var o: Dictionary = map.objects[id]
		if o["type"] == "mine" and int(o.get("owner", -1)) == player_idx:
			out.append(o)
	return out


static func mine_income(mine: Dictionary, data: GameData) -> int:
	if mine.has("amount"):
		return int(mine["amount"])
	return int(data.economy["mines"][mine["resource"]]["amount"])


static func mine_name(mine: Dictionary, data: GameData) -> String:
	return String(mine.get("name", data.economy["mines"][mine["resource"]]["name"]))


static func daily_income(map: AdventureMap, player_idx: int, data: GameData) -> Dictionary:
	var out := {}
	for t in towns_of(map, player_idx):
		var inc := Town.daily_income(t, data)
		for res in inc:
			out[res] = int(out.get(res, 0)) + int(inc[res])
	for m in mines_of(map, player_idx):
		out[m["resource"]] = int(out.get(m["resource"], 0)) + mine_income(m, data)
	return out


static func count_effect(map: AdventureMap, player_idx: int, effect_type: String, data: GameData) -> int:
	var n := 0
	for t in towns_of(map, player_idx):
		for e in Town.effects(t, data):
			if e["type"] == effect_type:
				n += 1
	return n


## Gold per XP from the best battle_spoils building the player owns (they do not stack).
static func battle_spoils_rate(map: AdventureMap, player_idx: int, data: GameData) -> float:
	var best := 0.0
	for t in towns_of(map, player_idx):
		for e in Town.effects(t, data):
			if e["type"] == "battle_spoils":
				best = maxf(best, float(e["gold_per_xp"]))
	return best


## The faction-wide ultimate upgrades a player owns: {faction id: army_upgrade
## effect}. A town's army_upgrade empowers the creatures of that town's faction
## (a captured foreign town's ultimate works for its own faction's creatures).
## Owning two of the same does not stack. Towns whose tier cap keeps tier 8
## locked do not count. Keys are sorted, so iteration order is stable.
static func army_upgrades(map: AdventureMap, player_idx: int, data: GameData) -> Dictionary:
	var out := {}
	if map == null or player_idx < 0:
		return out
	for t in towns_of(map, player_idx):
		var cap := int(t.get("tier_cap", 0))
		if cap > 0 and cap < ARMY_UPGRADE_TIER:
			continue
		for e in Town.effects(t, data):
			if e["type"] == "army_upgrade":
				out[String(t["town_type"])] = e
	var sorted := {}
	var keys := out.keys()
	keys.sort()
	for k in keys:
		sorted[k] = out[k]
	return sorted


## Exchange rate for a player owning `markets` markets (0 = cannot trade).
static func market_rate(markets: int, data: GameData) -> float:
	if markets <= 0:
		return 0.0
	var m: Dictionary = data.economy["market"]
	return minf(float(m["max_rate"]), float(m["base_rate"]) + float(m["rate_per_extra_market"]) * (markets - 1))


## How much of `buy_res` you get for `sell_amount` of `sell_res`.
static func trade_quote(sell_res: String, buy_res: String, sell_amount: int, markets: int, data: GameData) -> int:
	if sell_res == buy_res or sell_amount <= 0:
		return 0
	var values: Dictionary = data.economy["market"]["values"]
	var rate := market_rate(markets, data)
	# Selling into gold and buying out of gold each lose (1 - rate); a direct
	# resource swap goes through gold once in each direction.
	var gold := float(sell_amount) * float(values[sell_res]) * (rate if sell_res != "gold" else 1.0)
	var got := gold * (rate if buy_res != "gold" else 1.0) / float(values[buy_res])
	return int(floor(got + 0.000001))


## Smallest sell amount that yields at least `buy_amount` (or -1 if impossible).
static func trade_price(sell_res: String, buy_res: String, buy_amount: int, markets: int, data: GameData) -> int:
	if trade_quote(sell_res, buy_res, 1000000, markets, data) < buy_amount:
		return -1
	var lo := 1
	var hi := 1000000
	while lo < hi:
		var mid := (lo + hi) / 2
		if trade_quote(sell_res, buy_res, mid, markets, data) >= buy_amount:
			hi = mid
		else:
			lo = mid + 1
	return lo


static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var eco: Dictionary = data.economy
	for key in ["builds_per_day", "max_heroes_per_player", "market", "mines", "conversion_cost"]:
		if not eco.has(key):
			errors.append("economy missing %s" % key)
	var conversion: Variant = eco.get("conversion_cost", null)
	if not conversion is Dictionary or conversion.is_empty():
		errors.append("economy conversion_cost must be a nonempty resource bundle")
	else:
		for res in conversion:
			if not data.resources.has(res) or not (conversion[res] is int or conversion[res] is float) or float(conversion[res]) <= 0 or float(conversion[res]) != floor(float(conversion[res])):
				errors.append("economy conversion_cost has invalid amount or resource %s" % res)
	for res in data.resources:
		if not eco.get("market", {}).get("values", {}).has(res):
			errors.append("market has no value for %s" % res)
		if not eco.get("mines", {}).has(res):
			errors.append("no mine definition for %s" % res)
	for tt_id in data.town_types:
		var tt: Dictionary = data.town_types[tt_id]
		var where := "town %s" % tt_id
		if not data.factions.has(tt_id):
			errors.append("%s is not a faction" % where)
		var bs: Dictionary = tt.get("buildings", {})
		if bs.size() < 15:
			errors.append("%s has only %d buildings" % [where, bs.size()])
		for b in tt.get("starting_buildings", []):
			if not bs.has(b):
				errors.append("%s starts with unknown building %s" % [where, b])
		var tiers := {}
		var upgrades := {}   # building id -> base creature
		var dwelling_of := {}  # base creature -> building id
		var ultimates := 0
		for b_id in bs:
			var b: Dictionary = bs[b_id]
			for key in ["name", "category", "cost", "requires", "effects", "description"]:
				if not b.has(key):
					errors.append("%s building %s missing %s" % [where, b_id, key])
			if not CATEGORIES.has(b.get("category", "")):
				errors.append("%s building %s has unknown category %s" % [where, b_id, b.get("category", "")])
			for res in b.get("cost", {}):
				if not data.resources.has(res):
					errors.append("%s building %s costs unknown resource %s" % [where, b_id, res])
			for r in b.get("requires", []):
				if not bs.has(r):
					errors.append("%s building %s requires unknown %s" % [where, b_id, r])
			for e in b.get("effects", []):
				var et: String = e.get("type", "")
				if not EFFECT_TYPES.has(et):
					errors.append("%s building %s has unknown effect %s" % [where, b_id, et])
				if et in ["dwelling", "growth"]:
					var c := data.creature(String(e.get("creature", "")))
					if c.is_empty():
						errors.append("%s building %s references unknown creature" % [where, b_id])
					elif c["faction"] != tt_id:
						errors.append("%s building %s houses foreign creature %s" % [where, b_id, e["creature"]])
					elif et == "dwelling":
						tiers[int(c["tier"])] = true
						dwelling_of[e["creature"]] = b_id
				if et == "dwelling_upgrade":
					var base := data.creature(String(e.get("creature", "")))
					var up := data.creature(String(base.get("upgrade", "")))
					if base.is_empty() or up.is_empty():
						errors.append("%s building %s upgrades a creature without an upgrade" % [where, b_id])
					elif String(up.get("upgrade_of", "")) != e["creature"] or up["faction"] != base["faction"] or int(up["tier"]) != int(base["tier"]):
						errors.append("%s building %s: upgrade pair %s/%s is inconsistent" % [where, b_id, e["creature"], base["upgrade"]])
					elif base["faction"] != tt_id:
						errors.append("%s building %s upgrades foreign creature %s" % [where, b_id, e["creature"]])
					else:
						upgrades[b_id] = e["creature"]
				if et == "army_upgrade":
					errors.append_array(_validate_army_upgrade(e, "%s building %s" % [where, b_id], data))
					ultimates += 1
					if String(b.get("category", "")) != "ultimate":
						errors.append("%s building %s: army_upgrade belongs in the ultimate category" % [where, b_id])
				if et in ["income", "build_discount"]:
					for res in e.get("resources", {}):
						if not data.resources.has(res):
							errors.append("%s building %s: unknown resource %s" % [where, b_id, res])
		if ultimates > 1:
			errors.append("%s has %d army_upgrade effects (at most one per faction)" % [where, ultimates])
		for b_id in upgrades:
			var dw: String = dwelling_of.get(upgrades[b_id], "")
			if dw == "" or not (bs[b_id].get("requires", []) as Array).has(dw):
				errors.append("%s building %s must require the dwelling of %s" % [where, b_id, upgrades[b_id]])
		for c_id in data.creatures:
			if data.creatures[c_id].has("upgrade_of"):
				continue
			if data.creatures[c_id]["faction"] == tt_id and data.creatures[c_id].has("upgrade") and not upgrades.values().has(c_id):
				errors.append("%s has no upgrade building for %s" % [where, c_id])
			if data.creatures[c_id]["faction"] == tt_id and not tiers.has(int(data.creatures[c_id]["tier"])):
				errors.append("%s has no dwelling for tier %d" % [where, int(data.creatures[c_id]["tier"])])
		# Requirements must form a tree/DAG so everything is buildable.
		var reachable := {}
		var changed := true
		while changed:
			changed = false
			for b_id in bs:
				if reachable.has(b_id):
					continue
				var ok := true
				for r in bs[b_id].get("requires", []):
					if not reachable.has(r):
						ok = false
				if ok:
					reachable[b_id] = true
					changed = true
		for b_id in bs:
			if not reachable.has(b_id):
				errors.append("%s building %s can never be built (cyclic requirements)" % [where, b_id])
		var hire: Dictionary = tt.get("hire", {})
		for h in hire.get("heroes", []):
			if not data.hero_classes.has(h.get("class", "")):
				errors.append("%s hires unknown class %s" % [where, h.get("class", "")])
			elif data.hero_classes[h["class"]]["faction"] != tt_id:
				errors.append("%s hires %s of another faction's class %s" % [where, h.get("name", "?"), h["class"]])
		for p in hire.get("army", []):
			if data.creature(String(p[0])).is_empty():
				errors.append("%s hire army has unknown creature %s" % [where, p[0]])
	return errors


static func _validate_army_upgrade(e: Dictionary, where: String, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	if String(e.get("name", "")) == "":
		errors.append("%s: army_upgrade needs a name" % where)
	var known := ["type", "name", "abilities"] + ARMY_UPGRADE_STATS + ARMY_UPGRADE_PCTS
	for k in e:
		if not known.has(k):
			errors.append("%s: army_upgrade has unknown field %s" % [where, k])
	for k in ARMY_UPGRADE_STATS:
		if e.has(k) and (float(e[k]) != floorf(float(e[k])) or int(e[k]) < 0 or int(e[k]) > 10):
			errors.append("%s: army_upgrade %s must be a whole number 0-10" % [where, k])
	for k in ARMY_UPGRADE_PCTS:
		if e.has(k) and (float(e[k]) < 0.0 or float(e[k]) > 1.0):
			errors.append("%s: army_upgrade %s must be a fraction 0-1" % [where, k])
	var effects := 0
	for k in ARMY_UPGRADE_STATS + ARMY_UPGRADE_PCTS:
		if float(e.get(k, 0)) > 0.0:
			effects += 1
	for a in e.get("abilities", []):
		effects += 1
		var aid := String(a.get("id", ""))
		if not data.abilities.has(aid):
			errors.append("%s: army_upgrade grants unknown ability %s" % [where, aid])
			continue
		for k in a:
			if k != "id" and not data.abilities[aid]["params"].has(k):
				errors.append("%s: army_upgrade ability %s has unknown parameter %s" % [where, aid, k])
	if effects == 0:
		errors.append("%s: army_upgrade does nothing" % where)
	return errors
