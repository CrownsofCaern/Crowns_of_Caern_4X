class_name WorldEvents
extends RefCounted
## Random events (data/events.json): a weekly omen that holds for everyone and
## daily fortunes for single players. Rolled by GameSession at the start of a
## day with the game RNG; the effects are read back from GameState.omen:
##   {id, week, tier?, resource?, amount?}  (tier/resource/amount: rolled parts)
## Messages for a player go to GameState player "news" (shown when that player
## is next to move), so a hot-seat player never reads another's fortune.

const WEEKLY_EFFECTS := ["growth_pct", "growth_tier", "hero_boon", "income_pct", "resources_random", "neutral_growth", "mana_regen",
	"plague", "roamer", "spoils_pct"]
const FORTUNE_EFFECTS := ["resources", "lose_pct", "xp", "hero_boon", "recruit"]
const OMEN_SOURCE := "omen"


static func enabled(state: GameState, data: GameData) -> bool:
	if data.world_events.is_empty():
		return false
	return bool(state.rules.get("random_events", data.rules.get("random_events", true)))


static func start_day(data: GameData) -> int:
	return int(data.world_events.get("start_day", 8))


## The omen in force this week ({} if none).
static func current_omen(state: GameState) -> Dictionary:
	if state.omen.is_empty() or int(state.omen.get("week", 0)) != state.week():
		return {}
	return state.omen


static func omen_def(state: GameState, data: GameData) -> Dictionary:
	var o := current_omen(state)
	if o.is_empty():
		return {}
	return data.world_events.get("weekly", {}).get(String(o["id"]), {})


static func _effects(state: GameState, data: GameData) -> Array:
	return omen_def(state, data).get("effects", [])


## Extra weekly growth for a creature this week (0.25 = +25%).
static func growth_bonus(state: GameState, data: GameData, creature_id: String) -> float:
	var pct := 0.0
	var tier := int(data.creature(creature_id).get("tier", 0))
	for e in _effects(state, data):
		match String(e["type"]):
			"growth_pct":
				pct += float(e["pct"])
			"growth_tier":
				if tier == int(state.omen.get("tier", 0)):
					pct += float(e["pct"])
	return pct


## This week's change to a resource's daily income (0.5 = +50%).
static func income_pct(state: GameState, data: GameData, res: String) -> float:
	var pct := 0.0
	for e in _effects(state, data):
		if String(e["type"]) == "income_pct" and (e["resources"] as Array).has(res):
			pct += float(e["pct"])
	return pct


## Extra spoils (gold per experience point) for beating neutral armies this week.
static func spoils_bonus(state: GameState, data: GameData) -> float:
	var v := 0.0
	for e in _effects(state, data):
		if String(e["type"]) == "spoils_pct":
			v += float(e["pct"])
	return v


## The week's plague: each day every hero army loses pct of each stack of
## living creatures (rounded down, so the smallest stacks are spared, and never
## the army's last creature). Returns {player index: [lines]}.
static func apply_plague(state: GameState, data: GameData, heroes_sorted: Array) -> Dictionary:
	var pct := 0.0
	for e in _effects(state, data):
		if String(e["type"]) == "plague":
			pct += float(e["pct"])
	var out := {}
	if pct <= 0.0:
		return out
	for h in heroes_sorted:
		if not h.alive or h.owner < 0:
			continue
		var total := (h.army as Army).total_creatures()
		var lost := []
		for i in Army.MAX_SLOTS:
			var s: Dictionary = h.army.slots[i]
			if s.is_empty() or not FactionMechanics.living(data.creature(s["creature"])):
				continue
			var n := mini(int(floor(int(s["count"]) * pct)), total - 1)
			if n <= 0:
				continue
			total -= n
			h.army.set_survivors({i: int(s["count"]) - n})
			lost.append("%d %s" % [n, data.creature(s["creature"])["name"]])
		if not lost.is_empty():
			var lines: Array = out.get(h.owner, [])
			lines.append("Plague in %s's camp: %s die." % [h.name, ", ".join(lost)])
			out[h.owner] = lines
	return out


static func mana_regen(state: GameState, data: GameData) -> int:
	var amount := 0
	for effect in _effects(state, data):
		if String(effect["type"]) == "mana_regen":
			amount += int(effect["amount"])
	return amount


## One line describing the omen (with its rolled parts) for the log and HUD.
static func omen_text(state: GameState, data: GameData) -> String:
	var def := omen_def(state, data)
	if def.is_empty():
		return ""
	var txt := "%s: %s" % [def["name"], def["text"]]
	if state.omen.has("tier"):
		txt += " (tier %d)" % int(state.omen["tier"])
	if state.omen.has("resource"):
		txt += " (+%d %s)" % [int(state.omen["amount"]), data.resources[state.omen["resource"]]["name"]]
	return txt


static func _pick(table: Dictionary, rng: GameRng) -> String:
	var ids := table.keys()
	ids.sort()
	var weights := ids.map(func(id): return float(table[id].get("weight", 1)))
	return String(ids[rng.weighted_index(weights)])


## Draws this week's omen and applies its one-off effects (hero boons,
## resources, neutral growth). Returns the omen. Call before weekly growth.
static func roll_omen(state: GameState, data: GameData, heroes_sorted: Array) -> Dictionary:
	var table: Dictionary = data.world_events.get("weekly", {})
	if table.is_empty():
		return {}
	var id := _pick(table, state.rng)
	var omen := {"id": id, "week": state.week()}
	for e in table[id].get("effects", []):
		match String(e["type"]):
			"growth_tier":
				omen["tier"] = state.rng.next_int(int(e["tiers"][0]), int(e["tiers"][1]))
			"resources_random":
				var pool: Array = e["pool"]
				omen["resource"] = String(pool[state.rng.next_int(0, pool.size() - 1)])
				omen["amount"] = state.rng.next_int(int(e["amount"][0]), int(e["amount"][1]))
	state.omen = omen
	for e in table[id].get("effects", []):
		match String(e["type"]):
			"hero_boon":
				for h in heroes_sorted:
					grant_omen_boon(state, data, h)
			"resources_random":
				for p in state.players:
					if not p["defeated"]:
						(p["resources"] as ResourceBank).add(omen["resource"], int(omen["amount"]))
			"neutral_growth":
				var ids := state.map.objects.keys()
				ids.sort()
				for oid in ids:
					var o: Dictionary = state.map.objects[oid]
					if o["type"] != "neutral_army":
						continue
					for st in o["stacks"]:
						st[1] = int(st[1]) + maxi(1, int(round(int(st[1]) * float(e["pct"]))))
	return omen


## The omen's hero boon (if any) for a hero, lasting to the end of the week.
static func grant_omen_boon(state: GameState, data: GameData, h: Hero) -> void:
	var def := omen_def(state, data)
	for e in def.get("effects", []):
		if String(e["type"]) == "hero_boon" and h.alive:
			var end_of_week := state.day + (7 - state.day_of_week())
			h.add_boon(OMEN_SOURCE, String(def["name"]), end_of_week, e["mods"])


## Maybe a fortune for one player this day. Returns the news line, or "".
## heroes: the player's living heroes, sorted by id.
static func roll_fortune(state: GameState, data: GameData, player_idx: int, heroes: Array) -> String:
	var table: Dictionary = data.world_events.get("fortunes", {})
	if table.is_empty() or not state.rng.chance(float(data.world_events.get("fortune_chance", 0.0))):
		return ""
	var id := _pick(table, state.rng)
	var def: Dictionary = table[id]
	var lines := []
	var p: Dictionary = state.player(player_idx)
	var bank: ResourceBank = p["resources"]
	for e in def.get("effects", []):
		match String(e["type"]):
			"resources":
				var n := state.rng.next_int(int(e["amount"][0]), int(e["amount"][1]))
				bank.add(String(e["resource"]), n)
				lines.append("+%d %s" % [n, data.resources[e["resource"]]["name"]])
			"lose_pct":
				var have := bank.get_amount(String(e["resource"]))
				var n := mini(int(e.get("max", have)), int(floor(have * float(e["pct"]))))
				if n > 0:
					bank.spend({String(e["resource"]): n})
					lines.append("-%d %s" % [n, data.resources[e["resource"]]["name"]])
			"xp":
				if heroes.is_empty():
					continue
				var h: Hero = heroes[state.rng.next_int(0, heroes.size() - 1)]
				var gained := h.xp_with_bonus(int(e["amount"]), data)
				h.add_xp(gained, data)
				lines.append("%s gains %d experience" % [h.name, gained])
			"hero_boon":
				if heroes.is_empty():
					continue
				var h: Hero = heroes[state.rng.next_int(0, heroes.size() - 1)]
				var days := int(e.get("days", 3))
				h.add_boon("fortune_" + id, String(def["name"]), state.day + days - 1, e["mods"])
				lines.append("%s: %s for %d days" % [h.name, MapSites.describe_mods(e["mods"]), days])
			"recruit":
				var line := _fortune_recruit(state, data, String(p["faction"]), heroes, e)
				if line != "":
					lines.append(line)
	if lines.is_empty():
		return ""
	return "%s. %s (%s)" % [def["name"], def["text"], ", ".join(lines)]


static func _fortune_recruit(state: GameState, data: GameData, faction: String, heroes: Array, e: Dictionary) -> String:
	var pool := MapSites.creature_pool({"tiers": e["tiers"], "factions": "any"}, data).filter(
		func(c): return String(data.creature(c)["faction"]) == faction)
	if pool.is_empty():
		return ""
	var c: String = pool[state.rng.next_int(0, pool.size() - 1)]
	var n := maxi(1, int(round(float(data.creature(c)["growth"]) * float(e["weeks"]))))
	for h in heroes:
		if (h as Hero).army.add(c, n):
			return "%d %s join %s" % [n, data.creature(c)["name"], h.name]
	return ""


# ------------------------------------------------------------- validation --

static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var ev: Dictionary = data.world_events
	if ev.is_empty():
		return errors
	if float(ev.get("fortune_chance", 0.0)) < 0.0 or float(ev.get("fortune_chance", 0.0)) > 1.0:
		errors.append("events: fortune_chance must be within [0, 1]")
	for group in ["weekly", "fortunes"]:
		var allowed: Array = WEEKLY_EFFECTS if group == "weekly" else FORTUNE_EFFECTS
		var table: Dictionary = ev.get(group, {})
		if table.is_empty():
			errors.append("events: %s is empty" % group)
		for id in table:
			var d: Dictionary = table[id]
			var where := "event %s.%s" % [group, id]
			if not d.has("name") or not d.has("text"):
				errors.append("%s missing name or text" % where)
			if float(d.get("weight", 1)) <= 0.0:
				errors.append("%s needs a positive weight" % where)
			for e in d.get("effects", []):
				var t := String(e.get("type", ""))
				if not allowed.has(t):
					errors.append("%s has unknown effect %s" % [where, t])
					continue
				errors.append_array(_validate_effect(e, t, where, data))
	return errors


static func _validate_effect(e: Dictionary, t: String, where: String, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var ranged := func(key: String, lo_min: int) -> void:
		var r: Array = e.get(key, [])
		if r.size() != 2 or int(r[0]) < lo_min or int(r[0]) > int(r[1]):
			errors.append("%s %s needs %s [min, max]" % [where, t, key])
	match t:
		"growth_pct", "growth_tier", "neutral_growth", "income_pct", "lose_pct":
			if not e.has("pct") or float(e["pct"]) < -0.9 or float(e["pct"]) > 2.0:
				errors.append("%s %s needs pct within [-0.9, 2]" % [where, t])
	match t:
		"mana_regen":
			if int(e.get("amount", 0)) <= 0:
				errors.append("%s mana_regen needs a positive amount" % where)
		"plague":
			if float(e.get("pct", 0.0)) <= 0.0 or float(e.get("pct", 0.0)) > 0.2:
				errors.append("%s plague needs pct within (0, 0.2]" % where)
		"spoils_pct":
			if float(e.get("pct", 0.0)) <= 0.0 or float(e.get("pct", 0.0)) > 2.0:
				errors.append("%s spoils_pct needs pct within (0, 2]" % where)
		"roamer":
			errors.append_array(RoamingThreats.validate_effect(e, where, data))
		"growth_tier", "recruit":
			ranged.call("tiers", 1)
		"hero_boon":
			if (e.get("mods", {}) as Dictionary).is_empty():
				errors.append("%s hero_boon has no mods" % where)
			errors.append_array(HeroModifiers.validate(e.get("mods", {}), where, data))
		"income_pct":
			for res in e.get("resources", []):
				if not data.resources.has(res):
					errors.append("%s income_pct has unknown resource %s" % [where, res])
		"resources_random":
			for res in e.get("pool", []):
				if not data.resources.has(res):
					errors.append("%s resources_random has unknown resource %s" % [where, res])
			if (e.get("pool", []) as Array).is_empty():
				errors.append("%s resources_random has an empty pool" % where)
			ranged.call("amount", 1)
		"resources", "lose_pct":
			if not data.resources.has(String(e.get("resource", ""))):
				errors.append("%s %s has unknown resource" % [where, t])
			if t == "resources":
				ranged.call("amount", 1)
		"xp":
			if int(e.get("amount", 0)) <= 0:
				errors.append("%s xp needs amount > 0" % where)
		"recruit":
			if float(e.get("weeks", 0)) <= 0.0:
				errors.append("%s recruit needs weeks > 0" % where)
	return errors
