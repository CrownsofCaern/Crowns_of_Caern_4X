class_name ScenarioTownless
extends RefCounted
## Townless start (map overhaul scenario "T"): the scenario player begins with
## a single hero and no town. Its old start town becomes a garrisoned neutral
## town at a medium distance that the starting army alone usually loses to;
## 3-5 guarded villages (data/sites.json kind "village") nearby sell a one-off
## stock of the player's own folk. The starting gold buys about stock_share of
## all village stock, and that is enough to take the town.
##
## Builds on any generator template: ScenarioGenerator calls build() for a
## recipe with mode "townless" (data/scenario_recipes.json):
##   template: generator template id; villages: [min, max]; stock_share: the
##   share of all village stock the starting gold buys; village_days and
##   town_days: [min, max] days of the hero's movement from the start to the
##   villages and to the town; town_win: [min, max] chance of the starting army
##   against the town garrison (the build aims below max, then keeps the best
##   affordable army at a sure win); tiers: [min, max] creature tiers sold.
## The build records its own measurements in scenario.townless, which the
## probe (tools/scenario_probe.gd) re-checks with more fights.

const PLAYER := 0
const TUNE_SIMULATIONS := 32
const VERIFY_SIMULATIONS := 64


static func build(data: GameData, recipe: Dictionary, seed_value: int) -> Dictionary:
	var def := MapGenerator.generate(data, String(recipe.get("template", "twin_marches")), seed_value)
	if def.is_empty():
		return {}
	var rng := GameRng.new(GameRng.mix(seed_value, 5813))
	var faction := String(def["players"][PLAYER]["faction"])
	# One hero: the first the map gives the player.
	var lead: Dictionary = {}
	var heroes := []
	for hd in def["heroes"]:
		if int(hd["owner"]) != PLAYER:
			heroes.append(hd)
		elif lead.is_empty():
			lead = hd
			heroes.append(hd)
	def["heroes"] = heroes
	if lead.is_empty():
		return {}
	# The start town turns neutral; the player's mines go back to the wild.
	var town: Dictionary = {}
	var hero_pos := Vector2i(int(lead["pos"][0]), int(lead["pos"][1]))
	for o in def["objects"]:
		if o["type"] in ["town", "mine", "site"] and int(o.get("owner", -1)) == PLAYER:
			o["owner"] = -1
			if o["type"] == "town":
				var d := Vector2i(int(o["pos"][0]), int(o["pos"][1])) - hero_pos
				if town.is_empty() or absi(d.x) + absi(d.y) < _manhattan(town, hero_pos):
					town = o
	if town.is_empty():
		return {}
	town["town_type"] = faction if data.town_types.has(faction) else String(town["town_type"])
	# The start safety and fairness checks compare equal starts; this one is
	# lopsided on purpose, so the generator record moves aside.
	if def.has("generator"):
		def["source_generator"] = def["generator"]
		def.erase("generator")
	var hero := Hero.create(lead, data)
	var move := hero.max_movement(data)
	var map := AdventureMap.from_definition(def, data)
	var town_pos := AdventureMap.object_pos(town)
	var guards := {}
	for o in def["objects"]:
		if MapGenerator.blocks_path(o):
			guards[AdventureMap.object_pos(o)] = true
	var enemy_field := _enemy_field(map, def, guards)
	# The hero walks off to a spot town_days from the town, as far from the enemy as possible.
	var from_town := AiDistanceField.build(map, town_pos, guards)
	var town_days: Array = recipe.get("town_days", [1.0, 1.6])
	var spot := _pick_spot(map, from_town, int(float(town_days[0]) * move), int(float(town_days[1]) * move), enemy_field, def, rng)
	if spot.x < 0:
		return {}
	lead["pos"] = [spot.x, spot.y]
	# Villages around the hero, nearer to it than to the enemy.
	var from_hero := AiDistanceField.build(map, spot, guards)
	var village_days: Array = recipe.get("village_days", [0.3, 1.4])
	var counts: Array = recipe.get("villages", [3, 5])
	var wanted := rng.next_int(int(counts[0]), int(counts[1]))
	var village_ids := _village_sites(data)
	var placed := []
	var lo := int(float(village_days[0]) * move)
	var hi := int(float(village_days[1]) * move)
	var candidates := _open_tiles(map, def, from_hero, lo, hi, enemy_field, [spot, town_pos])
	while placed.size() < wanted and not candidates.is_empty():
		var p: Vector2i = candidates[rng.next_int(0, candidates.size() - 1)]
		candidates = candidates.filter(func(q): return maxi(absi(q.x - p.x), absi(q.y - p.y)) > 4)
		var sid: String = village_ids[placed.size() % village_ids.size()]
		var level := String(data.sites[sid].get("guard", "light"))
		var budget := int(data.map_templates["guard_levels"][level])
		var obj := {"id": "village_%d" % placed.size(), "type": "site", "site": sid, "pos": [p.x, p.y],
			"owner": -1, "zone": "townless", "guard": ScenarioGenerator._guard(data, rng, budget), "stock": []}
		def["objects"].append(obj)
		placed.append(obj)
	if placed.size() < int(counts[0]):
		return {}
	var tiers: Array = recipe.get("tiers", [1, 3])
	var folk := _folk(data, faction, int(tiers[0]), int(tiers[1]))
	if folk.is_empty():
		return {}
	_fill_stock(data, placed, folk, rng)
	var gold := int(data.starting_resources.get("gold", 0))
	_scale_stock(data, placed, gold, float(recipe.get("stock_share", 0.65)))
	var scenario := {
		"name": String(recipe.get("name", "Townless start")),
		"player": PLAYER,
		"townless_players": [PLAYER],
		"objectives": [
			{"id": "take_town", "type": "control_towns", "towns": [town["id"]], "text": "Take and hold %s" % town.get("name", town["id"])},
			{"id": "conquer", "type": "conquer", "text": "Defeat every rival"},
		],
	}
	def["scenario"] = scenario
	var report := _tune_town(data, def, town, lead, folk, gold, recipe, seed_value)
	report["town"] = town["id"]
	report["villages"] = placed.map(func(o): return o["id"])
	scenario["townless"] = report
	return def


static func _manhattan(o: Dictionary, p: Vector2i) -> int:
	var d := Vector2i(int(o["pos"][0]), int(o["pos"][1])) - p
	return absi(d.x) + absi(d.y)


## Movement cost from the nearest rival town or hero (rivals' start), for
## keeping the hero and its villages on the player's side of the map.
static func _enemy_field(map: AdventureMap, def: Dictionary, guards: Dictionary) -> AiDistanceField:
	for o in def["objects"]:
		if o["type"] == "town" and int(o.get("owner", -1)) > PLAYER:
			return AiDistanceField.build(map, AdventureMap.object_pos(o), guards)
	for hd in def["heroes"]:
		if int(hd["owner"]) != PLAYER:
			return AiDistanceField.build(map, Vector2i(int(hd["pos"][0]), int(hd["pos"][1])), guards)
	return null


## Free, open tiles (no object, no hero, at least six passable neighbours, so
## nothing blocks a corridor) at a movement cost in [lo, hi], sorted by index.
## With an enemy field, only tiles nearer to us than to the enemy.
static func _open_tiles(map: AdventureMap, def: Dictionary, field: AiDistanceField, lo: int, hi: int,
		enemy: AiDistanceField, keep_clear: Array) -> Array:
	var taken := {}
	for o in def["objects"]:
		var p := AdventureMap.object_pos(o)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				taken[p + Vector2i(dx, dy)] = true
	for hd in def["heroes"]:
		taken[Vector2i(int(hd["pos"][0]), int(hd["pos"][1]))] = true
	for p in keep_clear:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				taken[p + Vector2i(dx, dy)] = true
	var out := []
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var c := field.cost_to(p)
			if c < lo or c > hi or taken.has(p) or not map.is_passable(p):
				continue
			if enemy != null and enemy.cost_to(p) >= 0 and enemy.cost_to(p) <= c:
				continue
			var open := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if (dx != 0 or dy != 0) and map.in_bounds(p + Vector2i(dx, dy)) and map.is_passable(p + Vector2i(dx, dy)):
						open += 1
			if open >= 6:
				out.append(p)
	return out


## The hero's start: among the open tiles in range, the one farthest from the
## enemy (ties by a seeded pick among the best tenth).
static func _pick_spot(map: AdventureMap, field: AiDistanceField, lo: int, hi: int, enemy: AiDistanceField,
		def: Dictionary, rng: GameRng) -> Vector2i:
	var tiles := _open_tiles(map, def, field, lo, hi, enemy, [])
	if tiles.is_empty():
		return Vector2i(-1, -1)
	if enemy != null:
		tiles.sort_custom(func(a, b):
			var ca := enemy.cost_to(a)
			var cb := enemy.cost_to(b)
			return ca > cb or (ca == cb and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	var best := maxi(1, tiles.size() / 10)
	return tiles[rng.next_int(0, best - 1)]


static func _village_sites(data: GameData) -> Array:
	var out := []
	for sid in data.sites:
		if String(data.sites[sid]["kind"]) == "village":
			out.append(String(sid))
	out.sort()
	return out


## Base creatures of the faction within the tiers, lowest tier first.
static func _folk(data: GameData, faction: String, lo: int, hi: int) -> Array:
	var out := []
	for id in data.creatures:
		var c: Dictionary = data.creatures[id]
		if String(c["faction"]) == faction and not c.has("upgrade_of") and int(c["tier"]) >= lo and int(c["tier"]) <= hi and int(c.get("growth", 0)) > 0:
			out.append(String(id))
	out.sort_custom(func(a, b): return int(data.creature(a)["tier"]) < int(data.creature(b)["tier"]) or (data.creature(a)["tier"] == data.creature(b)["tier"] and a < b))
	return out


## Each village sells stock_types of the folk (every folk creature is sold
## somewhere), a week of growth times the site's stock_weeks to begin with.
static func _fill_stock(data: GameData, villages: Array, folk: Array, rng: GameRng) -> void:
	var next := rng.next_int(0, folk.size() - 1)
	for o in villages:
		var def: Dictionary = data.sites[o["site"]]
		var stock := []
		for i in mini(int(def.get("stock_types", 1)), folk.size()):
			var c: String = folk[(next + i) % folk.size()]
			stock.append([c, maxi(1, int(round(float(data.creature(c)["growth"]) * float(def.get("stock_weeks", 1.0)))))])
		next = (next + stock.size()) % folk.size()
		o["stock"] = stock


static func stock_gold(data: GameData, villages: Array) -> int:
	var total := 0
	for o in villages:
		for pair in o["stock"]:
			total += int(pair[1]) * int(data.creature(String(pair[0]))["cost"].get("gold", 0))
	return total


## Scales every stock so the starting gold buys `share` of it (by gold price).
static func _scale_stock(data: GameData, villages: Array, gold: int, share: float) -> void:
	var have := stock_gold(data, villages)
	if have <= 0:
		return
	var factor := float(gold) / share / float(have)
	for o in villages:
		for pair in o["stock"]:
			pair[1] = maxi(1, int(round(int(pair[1]) * factor)))


## The best army the starting gold can buy: the hero's army plus village
## stock, strongest tier first (gold prices; other resources are ignored as
## the starting purse covers them). Returns [[creature, count]].
static func best_purchase(data: GameData, start_army: Array, villages: Array, gold: int) -> Array:
	var offers := []
	for o in villages:
		for pair in o["stock"]:
			offers.append([String(pair[0]), int(pair[1])])
	offers.sort_custom(func(a, b): return int(data.creature(a[0])["tier"]) > int(data.creature(b[0])["tier"]) or (data.creature(a[0])["tier"] == data.creature(b[0])["tier"] and a[0] < b[0]))
	var army := Army.from_pairs(start_army)
	for pair in offers:
		var price := int(data.creature(pair[0])["cost"].get("gold", 0))
		var n: int = pair[1] if price <= 0 else mini(int(pair[1]), gold / price)
		if n > 0 and army.add(pair[0], n):
			gold -= n * price
	return army.to_combat_stacks().map(func(st): return [String(st["creature"]), int(st["count"])])


## Sets the town garrison (folk of the town's tiers, by gold value relative to
## the starting army) to the smallest size the starting army beats at most
## town_win max of the time, then backs off while the best affordable army
## would not win every fight. Returns the measurements.
static func _tune_town(data: GameData, def: Dictionary, town: Dictionary, lead: Dictionary, folk: Array,
		gold: int, recipe: Dictionary, seed_value: int) -> Dictionary:
	var bal := BalanceScenarios.new(data)
	var start_army: Array = lead["army"]
	var start_gold := maxi(1, bal.army_gold(start_army))
	var villages: Array = def["objects"].filter(func(o): return o.get("zone", "") == "townless" and o["type"] == "site")
	var best := best_purchase(data, start_army, villages, gold)
	var win_max := float(recipe.get("town_win", [0.2, 0.45])[1])
	var scale := 0.8
	var start_win := 1.0
	var probe := _probe_session(data, def, seed_value)
	while scale < 4.0:
		town["garrison"] = _garrison(bal, folk, int(start_gold * scale))
		start_win = _odds(probe, data, def, town, lead, start_army, TUNE_SIMULATIONS)["win_probability"]
		if start_win <= win_max:
			break
		scale += 0.1
	var best_odds := _odds(probe, data, def, town, lead, best, VERIFY_SIMULATIONS)
	while float(best_odds["win_probability"]) < 1.0 and scale > 0.5:
		scale -= 0.05
		town["garrison"] = _garrison(bal, folk, int(start_gold * scale))
		best_odds = _odds(probe, data, def, town, lead, best, VERIFY_SIMULATIONS)
	start_win = _odds(probe, data, def, town, lead, start_army, VERIFY_SIMULATIONS)["win_probability"]
	return {"gold": gold, "stock_gold": stock_gold(data, villages), "garrison_scale": snappedf(scale, 0.01),
		"start_win": start_win, "best_win": best_odds["win_probability"],
		"best_loss": snappedf(float(best_odds["expected_loss_fraction"]), 0.01), "best_army": best}


## Creatures of the folk worth about `value` gold: 45% lowest tier, 35% next, 20% the rest.
static func _garrison(bal: BalanceScenarios, folk: Array, value: int) -> Array:
	var shares := [0.45, 0.35, 0.2]
	var pairs := []
	for i in mini(folk.size(), shares.size()):
		pairs.append([folk[i], shares[i]])
	return bal.gold_army(pairs, maxi(value, 1))


## A throwaway session on the map as built so far (no scenario), for battle setups.
static func _probe_session(data: GameData, def: Dictionary, seed_value: int) -> GameSession:
	var bare := def.duplicate(true)
	bare.erase("scenario")
	return GameSession.new_game_from_definition(data, bare, seed_value)


## Forecast of `army` led by the scenario hero against the town as tuned now.
static func _odds(session: GameSession, data: GameData, def: Dictionary, town: Dictionary, lead: Dictionary,
		army: Array, sims: int) -> Dictionary:
	var live := session.town(String(town["id"]))
	live["garrison"] = town["garrison"].duplicate(true)
	Town.normalize(live, data)
	var h := session.hero(String(lead["id"]))
	h.army = Army.from_pairs(army)
	return CombatPredictor.new(data).predict(session.battle_setup(h.id, String(town["id"])), sims)
