class_name ScenarioSiege
extends RefCounted
## Siege missions (survival, defence, endless; recipe version 2+) built on the
## map generator, so every seed brings a new, wide map with regions to
## explore, neutral towns and mines to take.
##
## The generated map's first start becomes the defender's castle (a developed
## town with a garrison, two heroes and its start mines). Every other start
## town turns neutral; the nearest one becomes the potential ally's town,
## pledged through a relic quest. Invasions enter from the two zones farthest
## from the protected towns (within a few days' march) on the recipe's wave
## schedule ([day, strength]; strength is the wave's value as a multiple of the
## defender's starting heroes). Defence protects the castle and the two
## nearest other towns; endless repeats a growing last wave every week.
##
## Mission sites are gated so the starting army cannot take them in the first
## week (ScenarioGating.week_one_problems): the forge and the ally's envoy open
## on day 8 or later, and the watchtower, the siege camp and the relic's keeper
## carry guards that the combined starting army (both heroes and the castle
## garrison) beats less than GUARD_WIN of the time. The build records the
## tuned guards in scenario.siege.

const DEFENDER := 0
const INVADER := 1
const ALLY := 2
const GUARD_WIN := 0.4
const TUNE_SIMULATIONS := 24
const MAX_ENTRY_DAYS := 5.0
## Which entry each scheduled wave uses (cycled), as on the original Last Watch.
const ENTRY_PATTERN := [0, 1, 0, 0, 1, 0, 1]
const COMPASS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]


## The three fixed roles: the defender, the invasion host and a potential ally.
static func scenario_players(data: GameData) -> Array:
	var factions: Array = data.map_templates.get("random_maps", {}).get("factions", ["concord"])
	var own := String(factions[0]) if not factions.is_empty() else "concord"
	return [
		{"id": DEFENDER, "name": "The Watch", "faction": own, "color": "#4488d0", "is_human": true},
		{"id": INVADER, "name": "The Encircling Host", "faction": "ashen", "color": "#c94040", "is_human": false},
		{"id": ALLY, "name": "The Hill Folk", "faction": own, "color": "#49a85a", "is_human": false},
	]


static func build(data: GameData, recipe: Dictionary, seed_value: int) -> Dictionary:
	var def := MapGenerator.generate(data, String(recipe.get("template", "")), seed_value)
	if def.is_empty() or not def.has("generator"):
		return {}
	var mode := String(recipe["mode"])
	var rng := GameRng.new(GameRng.mix(seed_value, 7717))
	# The start checks compare equal starts; a siege is lopsided on purpose.
	var gen: Dictionary = def["generator"]
	def["source_generator"] = gen
	def.erase("generator")
	var players := scenario_players(data)
	var faction := String(def["players"][0]["faction"])
	players[DEFENDER]["faction"] = faction
	players[ALLY]["faction"] = faction
	def["players"] = players
	var folk := ScenarioTownless._folk(data, faction, 1, 7)
	if folk.size() < 3:
		return {}
	# Heroes: the defender's lead becomes hero_watch, a scout joins it.
	var lead: Dictionary = {}
	for hd in def["heroes"]:
		if int(hd["owner"]) == 0 and lead.is_empty():
			lead = hd
	if lead.is_empty():
		return {}
	lead["id"] = "hero_watch"
	var castle: Dictionary = {}
	var towns := []
	for o in def["objects"]:
		if o["type"] == "town":
			towns.append(o)
			if int(o.get("owner", -1)) == 0 and castle.is_empty():
				castle = o
		if o["type"] in ["town", "mine", "site"] and int(o.get("owner", -1)) > 0:
			o["owner"] = -1
			if o["type"] == "town" and (o.get("garrison", []) as Array).is_empty():
				o["garrison"] = _garrison(data, String(o["town_type"]), _army_value(data, lead["army"]) * 1.2)
	if castle.is_empty():
		return {}
	_unique_town_names(data, towns)
	var map := AdventureMap.from_definition(def, data)
	var castle_pos := AdventureMap.object_pos(castle)
	var scout := _scout(data, def, lead, castle_pos, map, rng)
	if scout.is_empty():
		return {}
	def["heroes"] = [lead, scout]
	_develop(data, castle, 3, 1, true)
	castle["garrison"] = _garrison(data, faction, _army_value(data, lead["army"]) * 0.35, 2)
	# The castle's own start mines work for it from day one.
	for o in def["objects"]:
		if o["type"] == "mine" and String(o.get("zone", "")) == String(castle.get("zone", "")) and (o.get("guard", []) as Array).is_empty():
			o["owner"] = DEFENDER
	var from_castle := AiDistanceField.build(map, castle_pos, {})
	var others := towns.filter(func(t): return t != castle and from_castle.cost_to(AdventureMap.object_pos(t)) >= 0)
	others.sort_custom(func(a, b): return _closer(from_castle, a, b))
	var protected := [castle]
	if mode == "defence":
		for t in others.slice(0, 2):
			t["owner"] = DEFENDER
			t["town_type"] = faction if data.town_types.has(faction) else String(t["town_type"])
			t.erase("built")
			_develop(data, t, 1, 0, false)
			t["garrison"] = _garrison(data, faction, _army_value(data, lead["army"]) * 0.25, 1)
			protected.append(t)
		if protected.size() < 3:
			return {}
	var ally_town: Dictionary = {}
	for t in others:
		if not protected.has(t):
			ally_town = t
			break
	var move := Hero.create(lead, data).max_movement(data)
	var entries := _entries(def, map, from_castle, protected + ([ally_town] if not ally_town.is_empty() else []), move)
	if entries.size() < 2:
		return {}
	# Waves
	var defender_value := _army_value(data, lead["army"]) + _army_value(data, scout["army"])
	var waves := []
	var final_day := 0
	var profiles: Array = data.scenario_recipes.get("invasion_profiles", [])
	var schedule: Array = recipe.get("waves", [])
	for i in schedule.size():
		var day := int(schedule[i][0])
		var budget := int(float(schedule[i][1]) * defender_value)
		var entry: Dictionary = entries[int(ENTRY_PATTERN[i % ENTRY_PATTERN.size()]) % entries.size()]
		var target: Dictionary = protected[i % protected.size()] if mode == "defence" else castle
		var profile: Dictionary = profiles[rng.next_int(0, profiles.size() - 1)]
		var targets := [target["id"]]
		for t in protected:
			targets.append(t["id"])
		if i > 0 and i < schedule.size() - 1:
			day += rng.next_int(-1, 1)
		final_day = maxi(final_day, day)
		waves.append({"id": "watch_wave_%d" % i, "day": day, "warning_days": 3, "owner": INVADER,
			"spawn": entry["tiles"][0], "entry_tiles": entry["tiles"], "entry_name": entry["name"],
			"target": target["id"], "targets": targets, "order": "assault",
			"hero": {"id": "watch_commander_%d" % i, "name": "%s %d" % [profile["name"], i + 1], "class": profile["class"],
				"army": _invasion_army(data, profile, budget)}})
	# Mission sites
	var sc := {
		"name": String(recipe.get("name", "Siege")), "mode": mode, "player": DEFENDER, "castle": castle["id"],
		"protected_towns": protected.map(func(t): return t["id"]), "invasion_players": [INVADER], "dormant_players": [],
		"max_active_invaders": 6, "random_events": false, "wave_strength": {"easy": 0.75, "normal": 1.0, "hard": 1.25},
		"waves": waves, "quests": [],
		"objectives": [
			{"id": "hold", "type": "survive", "through_day": final_day, "text": "Hold %s through day %d." % [castle.get("name", "the castle"), final_day]},
			{"id": "siege", "type": "clear_waves", "text": "Defeat every invasion commander, including the final siege."},
		],
	}
	def["scenario"] = sc
	var probe := _probe_session(data, def, seed_value)
	var army := _combined_army(data, lead, scout, castle)
	var later := _later_army(data, army, castle, 3)
	var tuned := {}
	var guards := {}
	for o in def["objects"]:
		if MapGenerator.blocks_path(o):
			guards[AdventureMap.object_pos(o)] = true
	var day_lo := func(days: float) -> int: return int(days * move)
	var site_names := _site_names(rng)
	# Forge: near the castle, opens in the second week.
	var forge_tile := _pick(map, def, from_castle, day_lo.call(1.0), day_lo.call(2.5), [castle_pos], rng)
	if forge_tile.x >= 0:
		var forge := _site(def, "site_forge", forge_tile, site_names["forge"], "forge", "mine_ore",
			"Secure the workshops to send fresh %s to %s every week." % [data.creature(String(folk[0]))["name"], castle.get("name", "the castle")])
		forge["unlock_day"] = 8 + rng.next_int(0, 2)
		forge["text"] += " The smiths return on day %d." % int(forge["unlock_day"])
		forge["guard"] = ScenarioGenerator._guard(data, rng, int(data.map_templates["guard_levels"].get("light", 700)))
		sc["forge_support"] = {"town": castle["id"], "creature": folk[0], "count": maxi(1, int(data.creature(String(folk[0]))["growth"]) * 2 / 3)}
	# Watchtower: on the way to an entry, strongly held.
	var from_entry := AiDistanceField.build(map, Vector2i(int(entries[0]["tiles"][0][0]), int(entries[0]["tiles"][0][1])), {})
	var from_entry2 := AiDistanceField.build(map, Vector2i(int(entries[1]["tiles"][0][0]), int(entries[1]["tiles"][0][1])), {})
	var watch_tile := _pick_towards(map, def, from_castle, from_entry2, day_lo.call(2.0), day_lo.call(4.0), [castle_pos])
	if watch_tile.x >= 0:
		var watch := _site(def, "site_watch", watch_tile, site_names["watch"], "watchtower", "place_fenwick_dike",
			"Restore this watch for earlier invasion warnings and a view of the entry roads.")
		tuned["site_watch"] = _tune(probe, data, watch, "guard", army, later, rng)
	# Siege camp: close to the main entry.
	var camp_tile := Vector2i(-1, -1)
	for reach in [[1.5, 3.0], [2.5, 2.5], [3.5, 2.0]]:
		camp_tile = _pick_towards(map, def, from_entry, from_castle, 0, day_lo.call(reach[0]), [castle_pos], day_lo.call(reach[1]))
		if camp_tile.x >= 0:
			break
	if camp_tile.x >= 0:
		var camp := _site(def, "site_camp", camp_tile, site_names["camp"], "siege_camp", "encounter_ash_pit_champion",
			"Destroy the supplies to reduce every future invasion army by one fifth.")
		tuned["site_camp"] = _tune(probe, data, camp, "guard", army, later, rng)
	# The ally: an envoy by its town, and a relic in a far, optional valley.
	if not ally_town.is_empty():
		var ally_pos := AdventureMap.object_pos(ally_town)
		var from_ally := AiDistanceField.build(map, ally_pos, guards)
		var envoy_tile := _pick(map, def, from_ally, 100, day_lo.call(0.6), [], rng)
		var relic := _relic_spot(map, def, gen, from_castle, move, rng)
		if envoy_tile.x >= 0 and relic.size() == 2:
			ally_town["owner"] = -1
			ally_town["garrison"] = []
			ally_town["requires_quest"] = "ally_pact"
			ally_town["town_type"] = faction if data.town_types.has(faction) else String(ally_town["town_type"])
			ally_town.erase("built")
			_develop(data, ally_town, 1, 0, false)
			var envoy := _site(def, "site_pact", envoy_tile, "%s Envoy" % ally_town.get("name", "Hill"), "quest", "encounter_free_company_camp",
				"The people of %s will stand with you if you return their stolen oath relic." % ally_town.get("name", "the hill town"))
			envoy["quest"] = "ally_pact"
			envoy["unlock_day"] = 8 + rng.next_int(0, 1)
			envoy["text"] += " Their envoy will hear you from day %d." % int(envoy["unlock_day"])
			var keeper := {"id": "guardian_oath", "type": "neutral_army", "pos": [relic[1].x, relic[1].y], "name": site_names["keeper"], "stacks": []}
			def["objects"].append(keeper)
			def["objects"].append({"id": "relic_oath", "type": "quest_item", "pos": [relic[0].x, relic[0].y], "name": site_names["relic"],
				"item": "oath_relic", "guarded_by": "guardian_oath", "sprite": "object_chest"})
			tuned["guardian_oath"] = _tune(probe, data, keeper, "stacks", army, later, rng)
			players[ALLY]["name"] = String(ally_town.get("name", "The Hill Folk"))
			sc["dormant_players"] = [ALLY]
			var tier2 := String(folk[1])
			sc["quests"].append({"id": "ally_pact", "giver": "site_pact", "item": "oath_relic",
				"text": "Defeat %s, recover %s from beside it, and return it here." % [site_names["keeper"], site_names["relic"]],
				"reward": {"town": ally_town["id"], "ally_player": ALLY, "defend_target": protected[-1]["id"] if mode == "defence" else castle["id"],
					"resources": {"gold": 1200},
					"hero": {"id": "hero_ally", "name": "%s Warden" % ally_town.get("name", "Hill"), "class": _other_class(data, faction, ""),
						"army": _garrison(data, faction, _army_value(data, lead["army"]) * 0.5, 2)},
					"weekly": {"town": castle["id"], "creature": tier2, "count": maxi(1, int(data.creature(tier2)["growth"]))}},
				"completion_text": "%s joins your cause. Its warden takes the field, and fresh %s reinforce %s each week." % [ally_town.get("name", "The town"), data.creature(tier2)["name"], castle.get("name", "the castle")]})
	if mode == "endless":
		sc["objectives"] = [{"id": "endless", "type": "endless", "text": "Survive as long as possible. Invasions continue every week."}]
		var next: Dictionary = waves[-1].duplicate(true)
		next.erase("day")
		sc["endless"] = {"first_day": final_day + 7, "interval": 7, "growth": float(recipe.get("endless_growth", 0.25)), "wave": next}
	sc["briefing"] = _briefing(mode, castle, protected, entries, final_day, not sc["quests"].is_empty(), String(ally_town.get("name", "")))
	sc["siege"] = {"guards": tuned, "defender_value": defender_value, "entries": entries.map(func(e): return e["name"])}
	return def


## Renames towns that share a name (the generator can repeat one) to unused
## names from the template's name pool, in id order.
static func _unique_town_names(data: GameData, towns: Array) -> void:
	var used := {}
	var dupes := []
	var ordered := towns.duplicate()
	ordered.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	for t in ordered:
		if used.has(String(t.get("name", ""))):
			dupes.append(t)
		used[String(t.get("name", ""))] = true
	for t in dupes:
		for n in data.map_templates.get("town_names", []):
			if not used.has(String(n)):
				t["name"] = String(n)
				used[String(n)] = true
				break


## The value of an army in gold (rare resources at 250), as the generator counts it.
static func _army_value(data: GameData, army: Array) -> int:
	var total := 0
	for pair in army:
		total += MapGenerator.creature_value(data.creature(String(pair[0]))) * int(pair[1])
	return total


## Folk of the faction worth about `value`: lower tiers first (up to max_tier).
static func _garrison(data: GameData, faction: String, value: float, max_tier: int = 3) -> Array:
	var folk := ScenarioTownless._folk(data, faction, 1, max_tier)
	if folk.is_empty():
		return []
	var shares := [0.45, 0.35, 0.2]
	var pairs := []
	for i in mini(folk.size(), shares.size()):
		pairs.append([folk[i], shares[i]])
	var total := 0.0
	for p in pairs:
		total += float(p[1])
	var out := []
	for p in pairs:
		var unit := MapGenerator.creature_value(data.creature(String(p[0])))
		out.append([p[0], maxi(1, int(round(value * float(p[1]) / total / unit)))])
	return out


static func _closer(field: AiDistanceField, a: Dictionary, b: Dictionary) -> bool:
	var ca := field.cost_to(AdventureMap.object_pos(a))
	var cb := field.cost_to(AdventureMap.object_pos(b))
	return ca < cb or (ca == cb and String(a["id"]) < String(b["id"]))


## A second hero of another class with about half the lead's lower tiers,
## standing next to the castle.
static func _scout(data: GameData, def: Dictionary, lead: Dictionary, castle_pos: Vector2i, map: AdventureMap, rng: GameRng) -> Dictionary:
	var faction := String(data.hero_classes[String(lead["class"])]["faction"])
	var army := []
	for pair in lead["army"]:
		if int(data.creature(String(pair[0]))["tier"]) <= 2:
			army.append([pair[0], maxi(1, int(pair[1]) / 2)])
	if army.is_empty():
		army.append([lead["army"][0][0], maxi(1, int(lead["army"][0][1]) / 2)])
	var taken := {}
	for o in def["objects"]:
		taken[AdventureMap.object_pos(o)] = true
	for hd in def["heroes"]:
		taken[Vector2i(int(hd["pos"][0]), int(hd["pos"][1]))] = true
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := castle_pos + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and map.in_bounds(p) and map.is_passable(p) and not taken.has(p):
					var pool: Array = data.town_types.get(faction, {}).get("hire", {}).get("heroes", [])
					var hero_name := "The Scout"
					if not pool.is_empty():
						hero_name = String(pool[rng.next_int(0, pool.size() - 1)]["name"])
					if hero_name == String(lead.get("name", "")):
						hero_name = "%s's Scout" % lead.get("name", "The Watch")
					return {"id": "hero_scout", "name": hero_name, "class": _other_class(data, faction, String(lead["class"])),
						"owner": DEFENDER, "pos": [p.x, p.y], "army": army}
	return {}


static func _other_class(data: GameData, faction: String, not_this: String) -> String:
	var ids := GameSetup.classes_for_faction(data, faction)
	for id in ids:
		if id != not_this:
			return id
	return not_this if not_this != "" else String(ids[0])


## Builds a town up to dwellings of max_tier, `forts` fortifications and maybe a market.
static func _develop(data: GameData, town: Dictionary, max_tier: int, forts: int, market: bool) -> void:
	var definition: Dictionary = data.town_types[String(town["town_type"])]
	var buildings: Dictionary = definition["buildings"]
	var built: Array = definition["starting_buildings"].duplicate()
	var fortifications := []
	var ids := buildings.keys()
	ids.sort()
	for id in ids:
		for effect in buildings[id].get("effects", []):
			if effect["type"] == "dwelling" and int(data.creature(String(effect["creature"]))["tier"]) <= max_tier \
					and not data.creature(String(effect["creature"])).has("upgrade_of"):
				_add_building(built, buildings, id)
			elif effect["type"] == "market" and market:
				_add_building(built, buildings, id)
			elif effect["type"] == "defense":
				fortifications.append(id)
	fortifications.sort_custom(func(a, b): return buildings[a].get("requires", []).size() < buildings[b].get("requires", []).size() \
		or (buildings[a].get("requires", []).size() == buildings[b].get("requires", []).size() and a < b))
	for i in mini(forts, fortifications.size()):
		_add_building(built, buildings, fortifications[i])
	town["built"] = built
	town.erase("available")


static func _add_building(built: Array, buildings: Dictionary, id: String) -> void:
	if built.has(id) or not buildings.has(id):
		return
	for prerequisite in buildings[id].get("requires", []):
		_add_building(built, buildings, String(prerequisite))
	built.append(id)


## The two invasion entries: [{tiles: [[x, y] x3], name}], the zone anchors
## farthest from the castle within MAX_ENTRY_DAYS of march (away from every
## kept town), the second well apart from the first.
static func _entries(def: Dictionary, map: AdventureMap, from_castle: AiDistanceField, keep_away: Array, move: int) -> Array:
	var zones: Array = def["source_generator"].get("zones", [])
	var cands := []
	var side := maxi(map.width, map.height)
	for z in zones:
		var anchor := Vector2i(int(z["anchor"][0]), int(z["anchor"][1]))
		var tiles := _entry_tiles(def, map, from_castle, anchor)
		if tiles.is_empty():
			continue
		var p := Vector2i(int(tiles[0][0]), int(tiles[0][1]))
		var cost := from_castle.cost_to(p)
		var near_town := false
		for t in keep_away:
			if AdventureMap.object_pos(t).distance_to(p) < side * 0.2:
				near_town = true
		if near_town or cost < 0:
			continue
		cands.append({"zone": String(z["id"]), "cost": cost, "pos": p, "tiles": tiles})
	if cands.is_empty():
		return []
	var limit := int(MAX_ENTRY_DAYS * move)
	cands.sort_custom(func(a, b):
		var ka := mini(int(a["cost"]), limit)
		var kb := mini(int(b["cost"]), limit)
		return ka > kb or (ka == kb and (int(a["cost"]) < int(b["cost"]) or (a["cost"] == b["cost"] and String(a["zone"]) < String(b["zone"])))))
	var first: Dictionary = cands[0]
	var second: Dictionary = {}
	for c in cands.slice(1):
		if (c["pos"] as Vector2i).distance_to(first["pos"]) >= side / 3.0:
			second = c
			break
	if second.is_empty() and cands.size() > 1:
		second = cands[1]
	var castle_pos := Vector2i.ZERO
	for o in def["objects"]:
		if o["type"] == "town" and int(o.get("owner", -1)) == DEFENDER:
			castle_pos = AdventureMap.object_pos(o)
			break
	var out := []
	for c in [first, second]:
		if c.is_empty():
			continue
		var d: Vector2i = c["pos"] - castle_pos
		var octant := posmod(int(round(atan2(float(d.y), float(d.x)) / (PI / 4.0))), 8)
		c["name"] = "the %s road" % COMPASS[octant]
		if out.size() == 1 and String(out[0]["name"]) == String(c["name"]):
			c["name"] = "the far %s road" % COMPASS[octant]
		out.append({"tiles": c["tiles"], "name": c["name"]})
	return out


## Up to three free, reachable tiles nearest a zone anchor.
static func _entry_tiles(def: Dictionary, map: AdventureMap, from_castle: AiDistanceField, anchor: Vector2i) -> Array:
	var taken := {}
	for o in def["objects"]:
		var p := AdventureMap.object_pos(o)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				taken[p + Vector2i(dx, dy)] = true
	var out := []
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := anchor + Vector2i(dx, dy)
				if map.in_bounds(p) and map.is_passable(p) and not taken.has(p) and from_castle.cost_to(p) >= 0:
					out.append([p.x, p.y])
					if out.size() == 3:
						return out
	return out


## A free open tile at a cost in [lo, hi] from the field, seeded.
static func _pick(map: AdventureMap, def: Dictionary, field: AiDistanceField, lo: int, hi: int, keep_clear: Array, rng: GameRng) -> Vector2i:
	var tiles := ScenarioTownless._open_tiles(map, def, field, lo, hi, null, keep_clear)
	if tiles.is_empty():
		return Vector2i(-1, -1)
	return tiles[rng.next_int(0, tiles.size() - 1)]


## A free open tile at [lo, hi] from `field` (and at least `min_other` from
## `other`) that is nearest to `towards` (ties by position).
static func _pick_towards(map: AdventureMap, def: Dictionary, field: AiDistanceField, towards: AiDistanceField, lo: int, hi: int,
		keep_clear: Array, min_other: int = 0) -> Vector2i:
	var tiles := ScenarioTownless._open_tiles(map, def, field, lo, hi, null, keep_clear)
	var best := Vector2i(-1, -1)
	var best_cost := 2147483647
	for p in tiles:
		var c := towards.cost_to(p)
		if c < 0 or (min_other > 0 and c < min_other):
			continue
		if c < best_cost:
			best = p
			best_cost = c
	return best


## [relic tile, keeper tile] in the nearest optional zone at least two days
## from the castle (any zone 3-6 days away if no optional zone fits). The
## keeper stands on the relic's neighbour nearest the castle.
static func _relic_spot(map: AdventureMap, def: Dictionary, gen: Dictionary, from_castle: AiDistanceField, move: int, rng: GameRng) -> Array:
	var optional := {}
	for z in gen.get("zones", []):
		if bool(z.get("optional", false)):
			optional[String(z["id"])] = Vector2i(int(z["anchor"][0]), int(z["anchor"][1]))
	var tiles := ScenarioTownless._open_tiles(map, def, from_castle, 2 * move, 6 * move, null, [])
	var in_optional := tiles.filter(func(p):
		for zid in optional:
			if (optional[zid] as Vector2i).distance_to(p) <= 6.0:
				return true
		return false)
	var pool: Array = in_optional if not in_optional.is_empty() else tiles.filter(func(p): return from_castle.cost_to(p) >= 3 * move)
	if pool.is_empty():
		return []
	pool.sort_custom(func(a, b): return from_castle.cost_to(a) < from_castle.cost_to(b) or (from_castle.cost_to(a) == from_castle.cost_to(b) and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	var relic: Vector2i = pool[rng.next_int(0, maxi(0, mini(pool.size(), 8) - 1))]
	var keeper := Vector2i(-1, -1)
	for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var q: Vector2i = relic + step
		if map.in_bounds(q) and map.is_passable(q) and from_castle.cost_to(q) >= 0 and (keeper.x < 0 or from_castle.cost_to(q) < from_castle.cost_to(keeper)):
			keeper = q
	if keeper.x < 0:
		return []
	return [relic, keeper]


static func _site(def: Dictionary, id: String, p: Vector2i, site_name: String, kind: String, sprite: String, text: String) -> Dictionary:
	var o := {"id": id, "type": "scenario_site", "pos": [p.x, p.y], "name": site_name, "kind": kind, "owner": -1, "sprite": sprite, "text": text}
	def["objects"].append(o)
	return o


static func _site_names(rng: GameRng) -> Dictionary:
	var pick := func(options: Array) -> String: return String(options[rng.next_int(0, options.size() - 1)])
	return {
		"forge": pick.call(["The Abandoned Forge", "The Cold Smithy", "The Ashfall Works"]),
		"watch": pick.call(["The Broken Watch", "The Hollow Beacon", "The Leaning Tower"]),
		"camp": pick.call(["The Ashen Supply Camp", "The Siege Depot", "The Smoke Camp"]),
		"keeper": pick.call(["The Keeper of the Drowned Oath", "The Oathbreaker's Warden", "The Barrow Keeper"]),
		"relic": pick.call(["The Oathstone", "The Bell of Vows", "The Sworn Banner"]),
	}


## Every starting army of the defender in one: both heroes and the castle garrison.
static func _combined_army(data: GameData, lead: Dictionary, scout: Dictionary, castle: Dictionary) -> Array:
	var merged := {}
	var order := []
	for pair in lead["army"] + scout["army"] + castle.get("garrison", []):
		var id := String(pair[0])
		if not merged.has(id):
			order.append(id)
			merged[id] = 0
		merged[id] += int(pair[1])
	order.sort_custom(func(a, b): return int(data.creature(a)["tier"]) > int(data.creature(b)["tier"]) or (data.creature(a)["tier"] == data.creature(b)["tier"] and a < b))
	return order.slice(0, 7).map(func(id): return [id, merged[id]])


static func _invasion_army(data: GameData, profile: Dictionary, budget: int) -> Array:
	var viable: Array = profile["units"].filter(func(pair): return MapGenerator.creature_value(data.creature(String(pair[0]))) * 4 <= budget)
	if viable.is_empty():
		viable = [profile["units"][0]]
	var total := 0.0
	for pair in viable:
		total += float(pair[1])
	var army := []
	for pair in viable:
		army.append([pair[0], maxi(1, int(round(budget * float(pair[1]) / total / MapGenerator.creature_value(data.creature(String(pair[0]))))))])
	return army


## A throwaway session on the map as built so far (no scenario), for battle setups.
static func _probe_session(data: GameData, def: Dictionary, seed_value: int) -> GameSession:
	var bare := def.duplicate(true)
	bare.erase("scenario")
	return GameSession.new_game_from_definition(data, bare, seed_value)


## The combined army plus `weeks` of the castle's dwelling growth: roughly
## what a defender who stays home and recruits fields by day 7 * weeks + 1.
static func _later_army(data: GameData, army: Array, castle: Dictionary, weeks: int) -> Array:
	var merged := {}
	var order := []
	var growth := []
	var buildings: Dictionary = data.town_types[String(castle["town_type"])]["buildings"]
	for id in castle.get("built", []):
		for effect in buildings.get(id, {}).get("effects", []):
			if effect["type"] == "dwelling":
				var c := String(effect["creature"])
				growth.append([c, int(data.creature(c).get("growth", 0)) * weeks])
	for pair in army + growth:
		var id := String(pair[0])
		if not merged.has(id):
			order.append(id)
			merged[id] = 0
		merged[id] += int(pair[1])
	order.sort_custom(func(a, b): return int(data.creature(a)["tier"]) > int(data.creature(b)["tier"]) or (data.creature(a)["tier"] == data.creature(b)["tier"] and a < b))
	return order.slice(0, 7).map(func(id): return [id, merged[id]])


## Rolls a neutral guard for `obj` (field "guard" or "stacks"), growing from
## half the combined starting army's value until that army beats it less than
## GUARD_WIN of the time. Returns {value, start_win, later_win}: later_win is
## the forecast for the army three weeks of castle growth later.
static func _tune(probe: GameSession, data: GameData, obj: Dictionary, field: String, army: Array, later: Array, rng: GameRng) -> Dictionary:
	var h := probe.hero("hero_watch")
	var live: Dictionary = probe.state.map.objects.get(String(obj["id"]), {})
	if live.is_empty():
		probe.state.map.add_object(obj.duplicate(true))
		live = probe.state.map.objects[String(obj["id"])]
	var value := float(_army_value(data, army)) * 0.5
	var win := 1.0
	var stacks := []
	h.army = Army.from_pairs(army)
	for _i in 32:
		stacks = ScenarioGenerator._guard(data, rng, int(value))
		live[field] = stacks.duplicate(true)
		win = _forecast(probe, data, h, String(obj["id"]))
		if win < GUARD_WIN:
			break
		value *= 1.1
	obj[field] = stacks
	h.army = Army.from_pairs(later)
	var later_win := _forecast(probe, data, h, String(obj["id"]))
	return {"value": int(value), "start_win": snappedf(win, 0.01), "later_win": snappedf(later_win, 0.01)}


static func _forecast(probe: GameSession, data: GameData, h: Hero, target_id: String) -> float:
	return float(CombatPredictor.new(data).predict(probe.battle_setup(h.id, target_id), TUNE_SIMULATIONS)["win_probability"])


static func _briefing(mode: String, castle: Dictionary, protected: Array, entries: Array, final_day: int, has_ally: bool, ally_name: String) -> String:
	var roads := " and ".join(entries.map(func(e): return String(e["name"])))
	var ally := " Return a lost relic to %s and it will fight beside you." % ally_name if has_ally else ""
	match mode:
		"defence":
			var names := ", ".join(protected.slice(0, -1).map(func(t): return String(t.get("name", t["id"])))) + " and " + String(protected[-1].get("name", protected[-1]["id"]))
			return "Hold %s throughout the siege. Losing any of them ends the mission. Invaders come by %s. Expeditions into the wilds can earn allies, reinforcements and time.%s" % [names, roads, ally]
		"endless":
			return "Hold %s for as long as you can. After the siege of day %d, a stronger commander arrives every week by %s. Win support across the map to prolong your defence.%s" % [castle.get("name", "the castle"), final_day, roads, ally]
	return "Hold %s through day %d. Invasion armies march in by %s. Leave the walls to take mines and towns, restore the watch, or burn the siege supplies.%s" % [castle.get("name", "the castle"), final_day, roads, ally]
