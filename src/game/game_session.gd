class_name GameSession
extends RefCounted
## Rules and command layer between GameState and the UI (or tests/AI).
## The UI never mutates GameState directly: it calls commands here and reacts
## to the signals. Every command works headless.

signal message(text: String)
signal state_changed
signal day_started(day: int)
signal battle_resolved(result: Dictionary)
signal encounter_resolved(result: Dictionary)

var data: GameData
var state: GameState
var pathfinder: Pathfinder
var encounters: EncounterSystem


## setup: optional player configuration from GameSetup (factions, human or
## computer, closed slots); an empty dictionary plays the map as defined.
## setup.standard_start (a skirmish from the new-game menu): every player
## starts with its faction's number of heroes (GameData.starting_heroes()),
## see _standard_start_heroes(). Without it the map's heroes are kept as they are.
## setup.cast places extra named heroes (a campaign's veterans on a generated
## map): [{id, name, class, owner, army, replaces?}], see _place_cast().
## setup.hide_odds: true starts a hard-mode game in which battle odds are never
## shown (stored as rules.hide_odds, see odds_hidden()).
## rules: rule overrides kept for the whole game (GameState.rules), such as a
## campaign chapter's max_tier and computer-player settings.
static func new_game(game_data: GameData, map_id: String, seed_value: int, setup: Dictionary = {},
		rules: Dictionary = {}) -> GameSession:
	return new_game_from_definition(game_data, game_data.load_map(map_id), seed_value, setup, rules)


## Starts from an independent authored snapshot; used by unsaved editor playtests.
## Callers validate untrusted definitions before this shared initialization path.
static func new_game_from_definition(game_data: GameData, definition: Dictionary, seed_value: int,
		setup: Dictionary = {}, rules: Dictionary = {}) -> GameSession:
	if definition.is_empty():
		return null
	if not setup.is_empty() and not GameSetup.validate(definition, setup, game_data).is_empty():
		return null
	var s := GameSession.new()
	s.data = game_data
	var def := definition.duplicate(true)
	# Where each map hero starts: a setup that changes a slot's faction swaps its
	# heroes for the new faction's, and a cast hero's "replaces" still names the map's.
	var map_hero_pos := {}
	for hd in def.get("heroes", []):
		map_hero_pos[String(hd["id"])] = Vector2i(int(hd["pos"][0]), int(hd["pos"][1]))
	if not setup.is_empty():
		def = GameSetup.apply(def, setup, game_data)
	var st := GameState.new()
	st.game_seed = seed_value
	st.rng = GameRng.new(seed_value)
	st.rules = rules.duplicate(true)
	if def.has("scenario") and not st.rules.has("scenario"):
		st.rules["scenario"] = def["scenario"].duplicate(true)
	if ScenarioRules.active(st) and not st.rules.has("random_events"):
		st.rules["random_events"] = bool(ScenarioRules.definition(st).get("random_events", false))
	if bool(setup.get("hide_odds", false)):
		st.rules["hide_odds"] = true
	st.map = AdventureMap.from_definition(def, game_data)
	for p in def["players"]:
		st.players.append({"id": int(p["id"]), "name": p["name"], "faction": p["faction"], "color": p["color"],
			"is_human": bool(p["is_human"]), "difficulty": String(p.get("difficulty", game_data.default_difficulty())),
			"team": maxi(0, int(p.get("team", 0))), "defeated": false, "days_without_town": 0, "eliminated_day": 0, "scouted": {},
			"resources": ResourceBank.new(game_data.starting_resources),
			"fog": FogOfWar.new(st.map.width, st.map.height), "news": []})
	for hd in def["heroes"]:
		var h := Hero.create(hd, game_data)
		st.heroes[h.id] = h
	s._attach(st)
	if bool(setup.get("standard_start", false)) and not ScenarioRules.active(st):
		s._standard_start_heroes(def["players"])
	s._place_cast(setup.get("cast", []), map_hero_pos)
	MapTraders.populate_authored(st, game_data)
	MapCobolts.populate_authored(st, game_data)
	s._man_starting_garrisons(def, String(def["id"]).begins_with("custom:") or bool(setup.get("preserve_authored", false)))
	for id in st.heroes:
		var h: Hero = st.heroes[id]
		h.home_town = GameState.initial_home(st.map, h)
		s._reveal_around(h)
	if ScenarioRules.active(st):
		var scenario_map := {"width": st.map.width, "height": st.map.height, "players": st.players,
			"heroes": st.heroes.values().map(func(h): return h.to_dict()), "objects": st.map.objects.values()}
		var scenario_errors := ScenarioRules.validate(ScenarioRules.definition(st), scenario_map, game_data)
		if scenario_errors.is_empty():
			for obj in ScenarioRules.definition(st)["objectives"]:
				if obj["type"] == "reach" and not st.map.is_passable(Vector2i(int(obj["pos"][0]), int(obj["pos"][1]))):
					scenario_errors.append("reach target must be passable")
		assert(scenario_errors.is_empty(), "invalid scenario: " + ", ".join(scenario_errors))
		for h in st.heroes.values():
			ScenarioRules.on_visit(st, h)
		for town in st.map.objects.values():
			if town["type"] == "town" and int(town["owner"]) >= 0:
				(st.player(int(town["owner"]))["fog"] as FogOfWar).reveal(AdventureMap.object_pos(town), 3)
		WaveDirector.on_day(s)
		VictoryRules.update(s)
	return s


## Puts the cast's heroes on the map. A hero with "replaces" takes the place of
## that hero (a generated map's starting hero), which leaves the game; any other
## stands on the free tile nearest its owner's first hero (or first town).
func _place_cast(cast: Array, map_hero_pos: Dictionary = {}) -> void:
	for cd in cast:
		var d: Dictionary = cd.duplicate(true)
		var owner := int(d.get("owner", 0))
		d["owner"] = owner
		var rep := String(d.get("replaces", ""))
		var pos := Vector2i(-1, -1)
		var replaced: Hero = null
		if rep != "" and state.heroes.has(rep):
			replaced = state.heroes[rep]
		elif rep != "" and map_hero_pos.has(rep):
			# The setup gave that slot another faction, so its hero has a new id.
			replaced = state.hero_at(map_hero_pos[rep])
		if replaced != null:
			pos = replaced.pos
			state.heroes.erase(replaced.id)
		else:
			pos = _free_tile_near(_home_of(owner))
		d["pos"] = [pos.x, pos.y]
		var h := Hero.create(d, data)
		state.heroes[h.id] = h


## Gives every player its faction's number of starting heroes: the map's first
## heroes of that player are kept (a map lists its lead hero first), the rest
## leave; a player short of heroes gets the next of its faction's tavern heroes,
## with the tavern's army, on the free tile nearest its first hero or town.
## Every starting hero then keeps only its stacks of tier starting_army_max_tier
## or lower (game_rules); a hero left with nothing gets its tavern's army.
func _standard_start_heroes(player_defs: Array = []) -> void:
	for p in state.players:
		var owner := int(p["id"])
		var want := data.starting_heroes(String(p["faction"]))
		var kept := 0
		for id in state.heroes.keys():
			var h: Hero = state.heroes[id]
			if h.owner != owner:
				continue
			if kept < want:
				kept += 1
			else:
				state.heroes.erase(id)
		var faction := String(p["faction"])
		if not data.town_types.has(faction):
			continue
		while kept < want:
			var offer := _next_hire({"town_type": faction})
			if offer.is_empty():
				break
			var pos := _free_tile_near(_home_of(owner))
			var chosen := String(player_defs[owner].get("hero_class", "")) if kept == 0 and owner < player_defs.size() else ""
			var h := Hero.create({"id": offer["id"], "name": offer["name"], "class": chosen if chosen != "" else offer["class"], "owner": owner,
				"pos": [pos.x, pos.y], "army": data.town_types[faction]["hire"]["army"]}, data)
			state.heroes[h.id] = h
			kept += 1
	var max_tier := int(data.rules.get("starting_army_max_tier", 2))
	for id in state.heroes:
		var h: Hero = state.heroes[id]
		for i in h.army.slots.size():
			var st: Dictionary = h.army.slots[i]
			if not st.is_empty() and int(data.creature(String(st["creature"]))["tier"]) > max_tier:
				h.army.slots[i] = {}
		if h.army.is_empty() and data.town_types.has(h.faction):
			h.army = Army.from_pairs(data.town_types[h.faction]["hire"]["army"])
		h.army.initialize_veterans(data)


## Where a player's forces gather: its first hero, else its first town.
func _home_of(owner: int) -> Vector2i:
	var ids := state.heroes.keys()
	ids.sort()
	for id in ids:
		var h: Hero = state.heroes[id]
		if h.owner == owner and h.alive:
			return h.pos
	for t in towns_of(owner):
		return AdventureMap.object_pos(t)
	return Vector2i.ZERO


## The nearest passable tile to p with no object and no hero, scanning rings
## outward in a fixed order; p itself if none is free within 8 tiles.
func _free_tile_near(p: Vector2i) -> Vector2i:
	for r in range(1, 9):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if state.map.is_passable(q) and state.map.object_at(q).is_empty() and state.hero_at(q) == null:
					return q
	return p


## A new game's player towns that start without a garrison get a small one:
## their built dwellings' creatures of the tiers in game_rules
## starting_garrison_weeks, as that many weeks of growth. Maps that define a
## garrison keep it.
## Custom maps also keep an explicitly empty authored garrison.
func _man_starting_garrisons(definition: Dictionary = {}, preserve_explicit: bool = false) -> void:
	var weeks: Dictionary = data.rules.get("starting_garrison_weeks", {})
	if weeks.is_empty():
		return
	for id in state.map.objects:
		var t: Dictionary = state.map.objects[id]
		if t["type"] != "town" or int(t["owner"]) < 0 or not Town.garrison(t).is_empty():
			continue
		if preserve_explicit and definition.get("objects", []).any(func(object): return object["id"] == id and object.has("garrison")):
			continue
		var g := Army.new()
		for c in Town.dwellings(t, data):
			var w := float(weeks.get(str(int(data.creature(c)["tier"])), 0.0))
			var n := int(round(Town.weekly_growth(t, c, data) * w))
			if n > 0:
				g.add(c, n)
		Town.set_garrison(t, g)


static func from_state(game_data: GameData, st: GameState) -> GameSession:
	var s := GameSession.new()
	s.data = game_data
	s._attach(st)
	return s


func _attach(st: GameState) -> void:
	state = st
	state.map.set_data(data)
	if ScenarioRules.active(state):
		WaveDirector.initialize(state)
	pathfinder = Pathfinder.new(state.map)
	encounters = EncounterSystem.new(data, state)
	for id in state.map.objects:
		var o: Dictionary = state.map.objects[id]
		if o["type"] == "town":
			Town.set_tier_cap(o, tier_cap())
			Town.normalize(o, data)
		elif o["type"] == "mine":
			o["owner"] = int(o.get("owner", -1))
		elif o["type"] == "site":
			MapSites.normalize(o, data)


## The highest creature tier towns may build and recruit in this game (0 = no limit).
func tier_cap() -> int:
	return int(state.rules.get("max_tier", 0))


func hero(hero_id: String) -> Hero:
	return state.heroes.get(hero_id, null)


func current_player() -> Dictionary:
	return state.player(state.current_player)


## True if the players are the same or allies (see GameState.allied).
func allied(a: int, b: int) -> bool:
	return state.allied(a, b)


# --------------------------------------------------------------- movement --

## Path preview: tiles, per-step cost, and how many steps are affordable today.
func plan_path(hero_id: String, target: Vector2i) -> Dictionary:
	var h := hero(hero_id)
	var blocked := _guarded_positions(h.owner)
	var others := _other_hero_positions(h)
	blocked.append_array(others)
	var path: Array[Vector2i] = []
	# Other heroes block the way; an enemy hero can still be the destination (a battle).
	if not others.has(target) or _enemy_hero_at(target, h.owner) != null:
		path = pathfinder.find_path(h.pos, target, blocked)
	var costs := pathfinder.step_costs(h.pos, path, h.move_cost_mods(data))
	var total := 0
	for c in costs:
		total += c
	var spent := 0
	var reachable := 0
	for c in costs:
		if spent + c > h.movement_left:
			break
		spent += c
		reachable += 1
	return {"path": path, "costs": costs, "reachable": reachable, "total_cost": total}


## Moves the hero toward target as far as movement allows. Steps onto resource
## piles collect them; unguarded mines and towns are captured by stepping on
## them. If the destination is guarded (neutral army, guarded mine, garrisoned
## or hero-defended foreign town, enemy hero) and the hero gets adjacent with
## enough points to engage, returns battle = the target id (an object id, or an
## enemy hero's id for a battle in the open; see battle_target()); the caller
## then shows the forecast and calls attack(). Ending the move on an own town
## returns town = its id. Map sites take effect when a hero steps on them
## (visited: [{id, lines}]); ending the move on one returns site = its id.
func move_hero(hero_id: String, target: Vector2i) -> Dictionary:
	var h := hero(hero_id)
	var out := {"steps": [], "collected": [], "captured": [], "battle": "", "town": "", "encounter": "",
		"site": "", "scenario": "", "visited": []}
	if h == null or not h.alive or h.owner != state.current_player or state.game_over:
		return out
	var plan := plan_path(hero_id, target)
	var path: Array = plan["path"]
	var costs: Array = plan["costs"]
	for i in path.size():
		var p: Vector2i = path[i]
		var obj := state.map.object_at(p)
		var foe := _enemy_hero_at(p, h.owner)
		if foe != null or is_guarded(obj, h.owner):
			if h.movement_left >= int(costs[i]):
				out["battle"] = obj["id"] if not obj.is_empty() and obj["type"] == "town" else (foe.id if foe != null else obj["id"])
			break
		if is_allied_town(obj, h.owner):
			break
		if not obj.is_empty() and obj["type"] == "encounter":
			if h.movement_left >= int(costs[i]):
				out["encounter"] = obj["id"]
			break
		if h.movement_left < int(costs[i]):
			break
		h.movement_left -= int(costs[i])
		h.pos = p
		record_enemy_sightings()
		ScenarioRules.on_visit(state, h)
		out["steps"].append(p)
		if obj.is_empty():
			continue
		match obj["type"]:
			"resource":
				_collect(obj)
				out["collected"].append(obj)
			"quest_item":
				if ScenarioQuests.collect(self, h, obj):
					out["collected"].append(obj)
			"scenario_site":
				out["scenario"] = obj["id"]
				break
			"artifact":
				if _pick_up_artifact(h, obj):
					out["collected"].append(obj)
			"mine", "town":
				if obj.has("requires_quest") and ScenarioQuests.status(state, String(obj["requires_quest"])) != "complete":
					continue
				if not allied(int(obj["owner"]), h.owner):
					_capture(obj, h.owner)
					out["captured"].append(obj["id"])
				if obj["type"] == "town" and i == path.size() - 1:
					out["town"] = obj["id"]
			"site":
				_enter_site(h, obj, out)
				if i == path.size() - 1:
					out["site"] = obj["id"]
	if not out["steps"].is_empty():
		_reveal_around(h)
		VictoryRules.update(self)
		state_changed.emit()
	return out


## Tiles of the other living heroes; a hero cannot walk through them.
func _other_hero_positions(h: Hero) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in state.heroes:
		var o: Hero = state.heroes[id]
		if o != h and o.alive:
			out.append(o.pos)
	return out


## A living hero of a player not allied with player_idx standing on p, or null.
func _enemy_hero_at(p: Vector2i, player_idx: int) -> Hero:
	var o := state.hero_at(p)
	return o if o != null and not allied(o.owner, player_idx) else null


## True for a town of an ally (not the player's own): its gates stay shut to
## the player's heroes, who can neither capture nor pass through it.
func is_allied_town(obj: Dictionary, player_idx: int) -> bool:
	return not obj.is_empty() and obj["type"] == "town" and int(obj["owner"]) != player_idx \
		and allied(int(obj["owner"]), player_idx)


func _collect(obj: Dictionary) -> void:
	var bank: ResourceBank = current_player()["resources"]
	bank.add(obj["resource"], int(obj["amount"]))
	state.map.remove_object(obj["id"])
	message.emit("Collected %d %s." % [int(obj["amount"]), data.resources[obj["resource"]]["name"]])


## The winner of a guard fight takes the prize it stood over.
func _claim_prize(h: Hero, obj: Dictionary, result: Dictionary) -> void:
	match String(obj["type"]):
		"resource":
			_bank(h.owner).add(obj["resource"], int(obj["amount"]))
			state.map.remove_object(obj["id"])
			result["summary"].append("Claimed %d %s." % [int(obj["amount"]), data.resources[obj["resource"]]["name"]])
		"artifact":
			if _pick_up_artifact(h, obj):
				result["summary"].append("Claimed the %s." % data.artifacts[String(obj["artifact"])]["name"])
		"mine":
			if not allied(int(obj["owner"]), h.owner):
				_capture(obj, h.owner)
				result["summary"].append("Claimed the %s." % Economy.mine_name(obj, data))
	result["claimed"] = String(obj["id"])


func _pick_up_artifact(h: Hero, obj: Dictionary) -> bool:
	var aid := String(obj["artifact"])
	if not h.give_artifact(aid, data):
		message.emit("%s's pack is full; the %s stays where it lies." % [h.name, data.artifacts[aid]["name"]])
		return false
	state.map.remove_object(obj["id"])
	message.emit("%s takes the %s." % [h.name, data.artifacts[aid]["name"]])
	return true


## Record the first sighting for each human, including sightings during AI movement.
func record_enemy_sightings() -> void:
	var ids := state.heroes.keys()
	ids.sort()
	for i in state.players.size():
		var p := state.player(i)
		if not p["is_human"] or p["defeated"]:
			continue
		var known: Dictionary = p.get("known_enemy_heroes", {})
		var fog: FogOfWar = p["fog"]
		for id in ids:
			var h: Hero = state.heroes[id]
			if h.alive and h.owner >= 0 and not allied(i, h.owner) and fog.is_explored(h.pos) and not known.has(id):
				known[id] = true
				_add_news(p, "Enemy hero sighted: %s." % h.name)
		p["known_enemy_heroes"] = known


## Reveals what the hero sees for its owner and every ally still in the game.
func _reveal_around(h: Hero) -> void:
	var radius := maxi(1, h.vision_radius(data) + state.map.vision_mod(h.pos))
	for i in state.allies_of(h.owner):
		if i == h.owner or not state.player(i)["defeated"]:
			(state.player(i)["fog"] as FogOfWar).reveal(h.pos, radius)
	record_enemy_sightings()


# ----------------------------------------------------------------- combat --

## True if entering this object means a fight for the given player.
func is_guarded(obj: Dictionary, player_idx: int) -> bool:
	if obj.is_empty():
		return false
	# Cobolt guards defend only against an explicit robbery, never a visit.
	if MapCobolts.is_post(obj, data):
		return false
	match obj["type"]:
		"neutral_army":
			return true
		"mine":
			if allied(int(obj["owner"]), player_idx):
				return false
			return not (obj.get("guard", []) as Array).is_empty() or not claim_guard(obj, player_idx).is_empty()
		"resource", "artifact":
			return not claim_guard(obj, player_idx).is_empty()
		"site", "scenario_site":
			return not (obj.get("guard", []) as Array).is_empty()
		"town":
			if allied(int(obj["owner"]), player_idx):
				return false
			return not Town.garrison(obj).is_empty() or town_defender(obj) != null
	return false


## Map objects a neutral army can stand guard over: they cannot be claimed
## while a neutral army stands on a neighbouring tile (or the army named by the
## object's guarded_by is alive). Stepping onto them starts that fight instead.
const GUARDABLE_TYPES := ["resource", "artifact", "mine"]


## The neutral army that keeps player_idx from claiming obj, or {}. A mine
## held by the player or an ally, or still holding its own guard (fought
## first), has none. guarded_by wins over neighbours; among several
## neighbouring armies the lowest id stands guard first.
func claim_guard(obj: Dictionary, player_idx: int) -> Dictionary:
	if obj.is_empty() or not GUARDABLE_TYPES.has(String(obj.get("type", ""))):
		return {}
	if obj["type"] == "mine" and (allied(int(obj["owner"]), player_idx) or not (obj.get("guard", []) as Array).is_empty()):
		return {}
	var named: Dictionary = state.map.objects.get(String(obj.get("guarded_by", "")), {})
	if named.get("type", "") == "neutral_army":
		return named
	for id in state.map.armies_around(AdventureMap.object_pos(obj)):
		return state.map.objects[id]
	return {}


## The owner's hero standing in a town (it defends the town together with the garrison), or null.
func town_defender(t: Dictionary) -> Hero:
	var h := state.hero_at(AdventureMap.object_pos(t))
	return h if h != null and h.owner == int(t["owner"]) and int(t["owner"]) >= 0 else null


## Guarded mines and towns block paths through them (neutral armies are
## already blocked by the map); they can still be the destination. Allies'
## towns block paths too.
func _guarded_positions(player_idx: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in state.map.objects:
		var o: Dictionary = state.map.objects[id]
		if (o["type"] != "neutral_army" and is_guarded(o, player_idx)) or is_allied_town(o, player_idx):
			out.append(AdventureMap.object_pos(o))
	return out


static func _pairs_to_stacks(pairs: Array) -> Array:
	var stacks := []
	for i in pairs.size():
		stacks.append({"slot": i, "creature": pairs[i][0], "count": int(pairs[i][1])})
	return stacks


## Garrison stacks fight next to a defending hero; their slots are offset so
## the battle result can be split back into hero army and garrison.
const GARRISON_SLOT_OFFSET := 7


## What attacking target_id means: {kind, pos, object, hero}. kind is "hero"
## (an enemy hero in the open), "town" (garrison and/or the owner's hero in the
## town), "mine", "neutral_army" or another object type; hero is the defending
## hero or null; object is the map object or {}. {} if there is no such target.
func battle_target(target_id: String) -> Dictionary:
	var foe: Hero = state.heroes.get(target_id, null)
	if foe != null and foe.alive:
		var here := state.map.object_at(foe.pos)
		if not here.is_empty() and here["type"] == "town" and int(here["owner"]) == foe.owner:
			return {"kind": "town", "pos": foe.pos, "object": here, "hero": foe}
		return {"kind": "hero", "pos": foe.pos, "object": {}, "hero": foe}
	if not state.map.objects.has(target_id):
		return {}
	var obj: Dictionary = state.map.objects[target_id]
	# A guarded pickup or mine: the fight is with its guard, on the prize's tile;
	# "claim" is the prize, taken by the winner (see attack()).
	var guard := claim_guard(obj, state.current_player)
	if not guard.is_empty():
		return {"kind": "neutral_army", "pos": AdventureMap.object_pos(obj), "object": guard, "hero": null, "claim": obj}
	var defender: Hero = town_defender(obj) if obj["type"] == "town" else null
	return {"kind": obj["type"], "pos": AdventureMap.object_pos(obj), "object": obj, "hero": defender}


## False if the target belongs to the player or an ally (neutral targets are always fair game).
func can_fight(player_idx: int, tgt: Dictionary) -> bool:
	if tgt["hero"] != null and allied((tgt["hero"] as Hero).owner, player_idx):
		return false
	var obj: Dictionary = tgt["object"]
	if obj.has("requires_quest") and ScenarioQuests.status(state, String(obj["requires_quest"])) != "complete":
		return false
	if not obj.is_empty() and obj["type"] in ["town", "mine"] and allied(int(obj["owner"]), player_idx):
		return false
	return true


## The ultimate army upgrades a player's creatures fight with ({faction: effect};
## empty for neutrals). Battle sides carry them as "upgrades".
func army_upgrades(player_idx: int) -> Dictionary:
	return Economy.army_upgrades(state.map, player_idx, data)


## The defending side of a battle.
func _defender_side(tgt: Dictionary) -> Dictionary:
	var obj: Dictionary = tgt["object"]
	var foe: Hero = tgt["hero"]
	match tgt["kind"]:
		"hero":
			return {"name": foe.name, "hero": foe.combat_profile(data), "stacks": foe.army.to_combat_stacks(), "upgrades": army_upgrades(foe.owner)}
		"town":
			var walls := Town.defense_bonus(obj, data)
			var garrison := Town.garrison(obj).to_combat_stacks()
			if foe == null:
				var fort: Variant = null
				if walls > 0:
					fort = {"name": "%s walls" % obj["name"], "attack": 0, "defense": walls, "power": 0, "skills": {}}
				return {"name": "%s garrison" % obj["name"], "hero": fort, "stacks": garrison, "upgrades": army_upgrades(int(obj["owner"]))}
			var profile := foe.combat_profile(data)
			profile["defense"] = int(profile["defense"]) + walls
			var stacks := foe.army.to_combat_stacks()
			for st in garrison:
				st["slot"] = int(st["slot"]) + GARRISON_SLOT_OFFSET
				stacks.append(st)
			return {"name": "%s in %s" % [foe.name, obj["name"]], "hero": profile, "stacks": stacks, "upgrades": army_upgrades(foe.owner)}
		"mine":
			return {"name": "%s guards" % Economy.mine_name(obj, data), "hero": null, "stacks": _pairs_to_stacks(obj.get("guard", []))}
		"scenario_site":
			return {"name": "%s guards" % obj["name"], "hero": null, "stacks": _pairs_to_stacks(obj.get("guard", []))}
		"site":
			return {"name": "%s guards" % MapSites.site_name(obj, data), "hero": null, "stacks": _pairs_to_stacks(obj.get("guard", []))}
	return {"name": obj.get("name", "Neutral army"), "hero": null, "stacks": _pairs_to_stacks(obj["stacks"])}


func battle_setup(hero_id: String, target_id: String) -> Dictionary:
	var h := hero(hero_id)
	var tgt := battle_target(target_id)
	var terrain := state.map.combat_terrain(tgt["pos"])
	var defender := _defender_side(tgt)
	# A hero in the open may fall back (retreat order) if a town of its own
	# can take it in; a hero defending a town holds it to the last.
	defender["can_withdraw"] = tgt["kind"] == "hero" and flee_destination((tgt["hero"] as Hero).id, tgt["pos"]) != Vector2i(-1, -1)
	var setup := CombatSimulator.make_setup(
		{"name": h.name, "hero": h.combat_profile(data), "stacks": h.army.to_combat_stacks(), "upgrades": army_upgrades(h.owner), "can_withdraw": true},
		defender, terrain, 0)
	# Presentation-only location context; combat rules continue to use `terrain`.
	setup["visual_terrain"] = state.map.terrain_at(tgt["pos"])
	setup["visual_seed"] = ("%s:%s" % [state.map.map_id,tgt["pos"]]).hash()
	setup["prediction_key"] = state.battles_fought
	return setup


func preview_battle(hero_id: String, target_id: String) -> Dictionary:
	if is_cobolt_target(target_id):
		var info := intel(hero_id, target_id)
		return {"concealed": true, "enemy": {"name": info["name"], "stacks": []}, "stacks": [],
			"odds": "none", "scouted": info["scouted"], "label": "", "win_probability": -1.0, "report": info["report"],
			"scout_cost": info["scout_cost"], "scout_reason": info["scout_reason"]}
	var setup := battle_setup(hero_id, target_id)
	var pred := CombatPredictor.new(data).predict(setup)
	pred["terrain"] = setup["terrain"]
	pred["visual_terrain"] = setup["visual_terrain"]
	pred["visual_seed"] = setup["visual_seed"]
	pred["enemy"] = setup["sides"][1]
	pred["defending_hero"] = battle_target(target_id)["hero"] != null
	pred["scouted"] = is_scouted(target_id)
	pred["odds"] = odds_shown(target_id)
	return pred


# ---------------------------------------------------- scouting and intel --
# What a player knows about a hostile army before a fight. Without a scout the
# player sees rough troop counts and a worded verdict ("Favorable"); a scout
# costs movement and reveals exact counts and the exact odds for the rest of
# the day. In a hard-mode game (rules.hide_odds) the odds are never shown, a
# scout then reveals only the counts.

## True in a hard-mode game: battle odds and encounter chances stay hidden.
func odds_hidden() -> bool:
	return bool(state.rules.get("hide_odds", false))


## The hostile target on tile t for a player: a guarded town's id (also when a
## hero defends it), an enemy hero's id, or the id of a neutral army or guarded
## mine. "" if a step onto t would not start a battle.
func hostile_target_at(t: Vector2i, player_idx: int) -> String:
	var obj := state.map.object_at(t)
	if MapCobolts.is_post(obj, data) and not obj.get("plundered", false) and _enemy_hero_at(t, player_idx) == null:
		return String(obj["id"])
	if is_guarded(obj, player_idx):
		return String(obj["id"])
	var foe := _enemy_hero_at(t, player_idx)
	return foe.id if foe != null else ""


## The id scouting reports are kept under: a hero defending a town is scouted
## as the town.
func _intel_key(target_id: String) -> String:
	var tgt := battle_target(target_id)
	if tgt.is_empty():
		return ""
	if tgt["kind"] == "town":
		return String(tgt["object"]["id"])
	return target_id if tgt["kind"] == "hero" else String(tgt["object"]["id"])


## Movement a hero spends to send a scout (game_rules scout_movement, cut by
## the Scouting skill's scout_cost_pct).
func scout_cost(hero_id: String) -> int:
	var h := hero(hero_id)
	var base := int(data.rules["scout_movement"])
	if h == null:
		return base
	return maxi(0, int(round(base * (1.0 - HeroModifiers.num(h.modifiers(data), "scout_cost_pct")))))


## How far (tiles, in any direction) a hero's scouts reach: vision radius plus
## game_rules scout_range_bonus.
func scout_range(hero_id: String) -> int:
	var h := hero(hero_id)
	return (h.vision_radius(data) if h != null else 0) + int(data.rules["scout_range_bonus"])


## True if the current player scouted this target today.
func is_scouted(target_id: String, player_idx: int = -1) -> bool:
	if player_idx < 0:
		player_idx = state.current_player
	var key := _intel_key(target_id)
	var seen: Dictionary = state.player(player_idx).get("scouted", {})
	return key != "" and int(seen.get(key, -1)) == state.day


## How the current player sees the odds of fighting target_id: "none" (hard
## mode), "label" (a worded verdict only) or "exact" (scouted: the percentage).
func odds_shown(target_id: String) -> String:
	if odds_hidden() or is_cobolt_target(target_id):
		return "none"
	return "exact" if is_scouted(target_id) else "label"


## Why the hero cannot send a scout to target_id now, or "" if it can.
func can_scout(hero_id: String, target_id: String) -> String:
	var h := hero(hero_id)
	if h == null or not h.alive or h.owner != state.current_player or state.game_over:
		return "No hero of yours is ready."
	var tgt := battle_target(target_id)
	if tgt.is_empty() or hostile_target_at(tgt["pos"], h.owner) == "":
		return "Nothing hostile to scout there."
	if not (state.player(h.owner)["fog"] as FogOfWar).is_explored(tgt["pos"]):
		return "That ground is unexplored."
	if is_scouted(target_id):
		return "Already scouted today."
	var d: Vector2i = tgt["pos"] - h.pos
	var reach := scout_range(hero_id)
	if maxi(absi(d.x), absi(d.y)) > reach:
		return "Too far: %s's scouts reach %d tiles." % [h.name, reach]
	var cost := scout_cost(hero_id)
	if h.movement_left < cost:
		return "Not enough movement left (a scout costs %d)." % cost
	return ""


## Sends a scout: spends scout_cost() movement and reveals the target's exact
## troops (and the exact odds unless odds_hidden()) for the rest of the day.
## Returns {ok, reason, cost}.
func scout(hero_id: String, target_id: String) -> Dictionary:
	var why := can_scout(hero_id, target_id)
	if why != "":
		return _fail(why)
	var h := hero(hero_id)
	var cost := scout_cost(hero_id)
	h.movement_left -= cost
	var p := state.player(h.owner)
	var seen: Dictionary = p.get("scouted", {})
	seen[_intel_key(target_id)] = state.day
	p["scouted"] = seen
	if is_cobolt_target(target_id):
		message.emit("%s's scouts observe concealed cobolt patrols; reserves remain unknown (-%d movement)." % [h.name, cost])
	else:
		message.emit("%s's scouts count the %s (-%d movement)." % [h.name, _defender_side(battle_target(target_id))["name"], cost])
	state_changed.emit()
	return {"ok": true, "reason": "", "cost": cost}


## What the current player knows about fighting target_id with hero_id:
## {target, name, defending_hero, scouted, odds ("none", "label", "exact"),
##  stacks: [{creature, name, count, known}] (known: the exact count was
##  scouted; otherwise show only a rough size), label, win_probability (-1
##  unless odds is "exact"), scout_cost, scout_reason ("" if a scout can go)}.
## The verdict of an unscouted army comes from a quicker forecast
## (combat_config hover_simulations); hard mode runs none.
func intel(hero_id: String, target_id: String) -> Dictionary:
	var tgt := battle_target(target_id)
	if tgt.is_empty():
		return {}
	if is_cobolt_target(target_id):
		var h := hero(hero_id)
		var seen := is_scouted(target_id)
		return {"target": target_id, "name": MapSites.site_name(tgt["object"], data), "defending_hero": false,
			"concealed": true, "scouted": seen, "stacks": [], "odds": "none", "label": "", "win_probability": -1.0,
			"report": MapCobolts.report(tgt["object"], data, seen, int(h.skills.get("scouting", 0)) if h != null else 0),
			"scout_cost": scout_cost(hero_id), "scout_reason": can_scout(hero_id, target_id)}
	var side := _defender_side(tgt)
	var scouted := is_scouted(target_id)
	var stacks := []
	for st in side["stacks"]:
		stacks.append({"creature": st["creature"], "name": data.creature(st["creature"])["name"],
			"count": int(st["count"]), "known": scouted})
	var out := {"target": _intel_key(target_id), "name": side["name"], "defending_hero": tgt["hero"] != null,
		"scouted": scouted, "odds": odds_shown(target_id), "stacks": stacks, "label": "", "win_probability": -1.0,
		"scout_cost": scout_cost(hero_id), "scout_reason": can_scout(hero_id, target_id)}
	var h := hero(hero_id)
	if out["odds"] == "none" or h == null or not h.alive or h.army.is_empty():
		return out
	var sims := int(data.combat["prediction_simulations"]) if scouted else int(data.combat["hover_simulations"])
	var pred := CombatPredictor.new(data).predict(battle_setup(hero_id, target_id), sims)
	out["label"] = pred["label"]
	if scouted:
		out["win_probability"] = pred["win_probability"]
	return out


## The home town if still held, otherwise another owned town. A free nearby
## tile is required because heroes cannot share a tile.
func flee_destination(hero_id: String, threatened_pos: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var h := hero(hero_id)
	if h == null or not h.alive:
		return Vector2i(-1, -1)
	var towns := towns_of(h.owner)
	towns.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	var home := town(h.home_town)
	if not home.is_empty() and int(home["owner"]) == h.owner:
		towns.erase(home)
		towns.push_front(home)
	for t in towns:
		var pos := AdventureMap.object_pos(t)
		if pos == threatened_pos:
			continue
		if state.hero_at(pos) == null and pos != h.pos:
			return pos
		var nearby := _free_tile_near(pos)
		if nearby != pos and nearby != h.pos:
			return nearby
	return Vector2i(-1, -1)


## Resolves the battle with a fresh seed from the game RNG, applies casualties,
## experience and the outcome to the map. A hero whose army is destroyed falls
## (attacker or defender); the winner of a hero battle takes the field.
func attack(hero_id: String, target_id: String, defender_flees: bool = false) -> Dictionary:
	var h := hero(hero_id)
	var tgt := battle_target(target_id)
	if h == null or tgt.is_empty() or not can_fight(h.owner, tgt):
		return {"ok": false, "reason": "allies do not fight each other"}
	var obj: Dictionary = tgt["object"]
	if MapCobolts.is_post(obj, data):
		var why := cobolt_rob_error(target_id, hero_id)
		if why != "":
			return _fail(why)
		var hostile: Array = obj.get("hostile_players", [])
		if not hostile.has(h.owner):
			hostile.append(h.owner)
		obj["hostile_players"] = hostile
	var foe: Hero = tgt["hero"]
	var pos: Vector2i = tgt["pos"]
	var escape := flee_destination(foe.id, pos) if foe != null and (defender_flees or tgt["kind"] == "hero") else Vector2i(-1, -1)
	if defender_flees and escape == Vector2i(-1, -1):
		return {"ok": false, "reason": "No safe town is available to flee to."}
	var setup := battle_setup(hero_id, target_id)
	if defender_flees:
		var walls := Town.defense_bonus(obj, data) if tgt["kind"] == "town" else 0
		setup["sides"][1]["hero"] = {"name": "Abandoned army", "attack": 0, "defense": walls, "power": 0, "skills": {}, "mods": {"melee_damage_pct": -0.5, "ranged_damage_pct": -0.5}}
	setup["seed"] = state.rng.next_u32()
	var result := CombatSimulator.new(data).simulate(setup, true)
	result["visual_terrain"] = setup["visual_terrain"]
	result["visual_seed"] = setup["visual_seed"]
	h.battle_spell_damage = 0.0
	if foe != null and not defender_flees:
		foe.battle_spell_damage = 0.0
	state.battles_fought += 1

	var survivors := {}
	for st in result["sides"][0]["stacks"]:
		survivors[st["slot"]] = st["end"]
	h.army.set_survivors(survivors)
	# Defender casualties: hero army slots, then garrison slots (offset) in a siege.
	var foe_surv := {}
	var garrison_surv := {}
	for st in result["sides"][1]["stacks"]:
		var slot := int(st["slot"])
		if foe != null and slot < GARRISON_SLOT_OFFSET:
			foe_surv[slot] = int(st["end"])
		else:
			garrison_surv[slot - (GARRISON_SLOT_OFFSET if foe != null else 0)] = int(st["end"])
	if foe != null:
		foe.army.set_survivors(foe_surv)

	var xp_rate := float(data.combat["xp_per_enemy_hp_killed"])
	var xp_gained := 0
	var levels := 0
	var gold_gained := 0
	var defender_xp := 0
	var recovered := 0
	var mods := h.modifiers(data)
	var foe_retreated := foe != null and not defender_flees and int(result.get("withdrew", -1)) == 1 and escape != Vector2i(-1, -1)
	if result["winner"] == 0:
		xp_gained = int(round(result["hp_killed"][0] * xp_rate))
		if foe_retreated:
			# Standing retreat order: the hero escapes with the survivors.
			defender_xp = foe.xp_with_bonus(int(round(result["hp_killed"][1] * xp_rate)), data)
			result["defender_levels_gained"] = foe.add_xp(defender_xp, data)
			foe.pos = escape
			foe.movement_left = 0
			_reveal_around(foe)
			if foe.army.is_empty():
				_fall(foe, h)
			else:
				result["summary"].append("%s fell back to safety with the survivors." % foe.name)
		elif foe != null and not defender_flees:
			xp_gained += int(round(xp_gained * float(data.rules["hero_defeat_xp_bonus"])))
			_fall(foe, h)
		xp_gained = h.xp_with_bonus(xp_gained, data)
		recovered = _recover_casualties(h, result, mods, setup)
		levels = h.add_xp(xp_gained, data)
		match tgt["kind"]:
			"town":
				Town.set_garrison(obj, Army.new())
				_capture(obj, h.owner)
			"mine":
				obj.erase("guard")
				if claim_guard(obj, h.owner).is_empty():
					_capture(obj, h.owner)
			"scenario_site":
				obj.erase("guard")
				obj["owner"] = h.owner
			"site":
				obj.erase("guard")
				if MapCobolts.is_post(obj, data):
					_plunder_cobolt(h, obj, result)
			"hero":
				# The field is taken: an enemy mine under the fallen hero changes hands.
				var under := state.map.object_at(pos)
				if not under.is_empty() and under["type"] == "mine" and int(under["owner"]) != h.owner:
					_capture(under, h.owner)
			_:
				var reward := RoamingThreats.bounty(obj)
				for res in data.resource_order:
					if int(reward.get(res, 0)) > 0:
						_bank(h.owner).add(res, int(reward[res]))
						result["summary"].append("Bounty for %s: +%d %s." % [obj.get("name", "the beast"), int(reward[res]), data.resources[res]["name"]])
				state.map.remove_object(obj["id"])
		for line in FactionMechanics.after_victory(h, result["sides"][1]["stacks"], state, data):
			result["summary"].append(line)
		var spoils_rate := Economy.battle_spoils_rate(state.map, h.owner, data) + HeroModifiers.num(mods, "spoils_pct")
		if tgt["kind"] == "neutral_army":
			spoils_rate += WorldEvents.spoils_bonus(state, data)
		gold_gained = int(round(xp_gained * spoils_rate))
		if gold_gained > 0:
			_bank(h.owner).add("gold", gold_gained)
			result["summary"].append("Trophies of war: +%d gold." % gold_gained)
		# A prize with another guard next to it stays out of reach: the hero holds its ground.
		var claim: Dictionary = tgt.get("claim", {})
		var next_guard := claim_guard(claim if not claim.is_empty() else obj, h.owner) if tgt["kind"] in ["neutral_army", "mine"] else {}
		if not next_guard.is_empty():
			result["summary"].append("Another guard still watches over it: %s." % String(next_guard.get("name", "a neutral army")))
		else:
			var step := pathfinder.step_costs(h.pos, [pos] as Array[Vector2i], h.move_cost_mods(data))
			h.movement_left = maxi(0, h.movement_left - step[0])
			h.pos = pos
			ScenarioRules.on_visit(state, h)
			_reveal_around(h)
			if not claim.is_empty():
				_claim_prize(h, claim, result)
		if tgt["kind"] == "site":
			var visit := {"visited": [], "captured": []}
			_enter_site(h, obj, visit)
			result["site_visit"] = visit["visited"]
			if not visit["visited"].is_empty():
				for line in visit["visited"][0]["lines"]:
					result["summary"].append("%s: %s." % [MapSites.site_name(obj, data), line])
	else:
		# Surviving defenders stay on the map, weakened.
		match tgt["kind"]:
			"hero":
				pass
			"town":
				var g := Town.garrison(obj)
				g.set_survivors(garrison_surv)
				Town.set_garrison(obj, g)
			_:
				var remaining := []
				for st in result["sides"][1]["stacks"]:
					if st["end"] > 0:
						remaining.append([st["creature"], st["end"]])
				obj["guard" if obj["type"] in ["mine", "site", "scenario_site"] else "stacks"] = remaining
		if foe != null and not defender_flees:
			defender_xp = foe.xp_with_bonus(int(round(result["hp_killed"][1] * xp_rate)), data)
			result["defender_levels_gained"] = foe.add_xp(defender_xp, data)
		if h.army.is_empty():
			_fall(h, foe)
		elif int(result.get("withdrew", -1)) == 0:
			# Standing retreat order: the attacker falls back where it stood.
			h.movement_left = 0
			result["summary"].append("%s fell back with the survivors." % h.name)
	if defender_flees:
		foe.army = Army.new()
		foe.pos = escape
		foe.movement_left = 0
		_reveal_around(foe)
		result["summary"].append("%s fled; the abandoned army dealt 50%% less damage." % foe.name)
	result["defender_fled"] = defender_flees
	result["defender_retreated"] = foe_retreated
	result["xp_gained"] = xp_gained
	result["levels_gained"] = levels
	result["gold_gained"] = gold_gained
	result["recovered"] = recovered
	result["defender_xp"] = defender_xp
	result["defender_hero_id"] = foe.id if foe != null else ""
	result["target_kind"] = tgt["kind"]
	result["hero_id"] = hero_id
	VictoryRules.update(self)
	battle_resolved.emit(result)
	state_changed.emit()
	return result


## After a victory, a share of the hero's fallen creatures rise again
## (recover_pct: Gravecalling, Ossuary Bond, artifacts). Returns how many.
func _recover_casualties(h: Hero, result: Dictionary, mods: Dictionary, setup: Dictionary) -> int:
	var total := 0
	for st in result["sides"][0]["stacks"]:
		var back := HeroBattleEffects.recovered(int(st["lost"]), mods)
		if back <= 0:
			continue
		var slot := int(st["slot"])
		if h.army.slots[slot].is_empty():
			for original in setup["sides"][0]["stacks"]:
				if int(original["slot"]) == slot:
					h.army.slots[slot] = original.duplicate(true)
					h.army.slots[slot].erase("slot")
					h.army.slots[slot]["count"] = back
					break
		else:
			h.army.slots[slot]["count"] = int(h.army.slots[slot]["count"]) + back
		total += back
	if total > 0 and result.has("summary"):
		result["summary"].append("%d of the fallen rise to fight again." % total)
	return total


## A hero whose army was destroyed leaves the game.
func _fall(h: Hero, victor: Hero) -> void:
	h.alive = false
	ScenarioQuests.on_fall(self, h)
	h.army = Army.new()
	h.movement_left = 0
	if victor != null:
		message.emit("%s has fallen to %s." % [h.name, victor.name])
	else:
		message.emit("%s has fallen." % h.name)


## Victory and defeat (see VictoryRules): the game result for the end screen.
func game_result() -> Dictionary:
	return VictoryRules.result(self)


func scenario_objectives() -> Array:
	return ScenarioRules.objectives(self)


func scenario_options(hero_id: String, site_id: String) -> Dictionary:
	return ScenarioQuests.options(self, hero_id, site_id)


func scenario_act(hero_id: String, site_id: String, action: String) -> Dictionary:
	var result := ScenarioQuests.act(self, hero_id, site_id, action)
	if result["ok"]:
		VictoryRules.update(self)
		state_changed.emit()
	return result


func transfer_quest_item(from_id: String, to_id: String, item: String) -> Dictionary:
	var result := ScenarioQuests.transfer(self, from_id, to_id, item)
	if result["ok"]:
		state_changed.emit()
	return result


# ------------------------------------------------------ sites and events --

## A hero steps onto a map site: an unowned (or rival) dwelling is captured
## (an ally's stays theirs), any other site applies its effect if this hero can still benefit.
## Appends {id, lines} to into["visited"] and captured ids to into["captured"].
func _enter_site(h: Hero, obj: Dictionary, into: Dictionary) -> void:
	if MapSites.kind(obj, data) == "dwelling":
		if not allied(int(obj.get("owner", -1)), h.owner):
			_capture(obj, h.owner)
			into["captured"].append(obj["id"])
		return
	if MapSites.kind(obj, data) == "village":
		# A village pledges itself once, to whoever frees it first.
		if int(obj.get("owner", -1)) < 0:
			_capture(obj, h.owner)
			into["captured"].append(obj["id"])
		return
	if MapCobolts.is_post(obj, data):
		return
	var r := MapSites.visit(h, obj, state.day, data)
	if not r["applied"]:
		return
	into["visited"].append({"id": obj["id"], "lines": r["lines"], "levels": r["levels"]})
	if int(r.get("reveal", 0)) > 0:
		for i in state.allies_of(h.owner):
			(state.player(i)["fog"] as FogOfWar).reveal(AdventureMap.object_pos(obj), int(r["reveal"]))
	_reveal_around(h)
	message.emit("%s visits the %s: %s." % [h.name, MapSites.site_name(obj, data), ", ".join(r["lines"])])


## Everything the UI shows about a site for a hero (hero_id may be ""):
## {id, site, name, kind, text, summary, owner, block, creature?, available?,
## cost?, max?, can_recruit?, reason?}.
func site_info(site_id: String, hero_id: String = "") -> Dictionary:
	var obj: Dictionary = state.map.objects.get(site_id, {})
	if obj.get("type", "") != "site":
		return {}
	var def := MapSites.definition(obj, data)
	var out := {"id": site_id, "site": obj["site"], "name": MapSites.site_name(obj, data), "kind": def.get("kind", ""),
		"text": def.get("text", ""), "summary": MapSites.summary(obj, data), "owner": int(obj.get("owner", -1)),
		"sprite": def.get("sprite", ""), "block": ""}
	if MapCobolts.is_post(obj, data) and obj.get("plundered", false):
		out["text"] = "The shutters are broken and the counting house stands empty. Its bargains and recruitment are gone for good."
	var h := hero(hero_id)
	if h != null:
		out["block"] = MapSites.visit_block(h, obj, data, state.day)
	if MapSites.RECRUIT_KINDS.has(out["kind"]):
		# offers: one entry per creature ({creature, available, cost, max, reason,
		# can_recruit}); the top-level fields repeat the first offer with stock left.
		var offers := []
		for pair in MapSites.offers(obj, data):
			var c := String(pair[0])
			var mx := max_site_recruitable(site_id, hero_id, c)
			var reason := site_recruit_error(site_id, hero_id, maxi(1, mx), c)
			offers.append({"creature": c, "available": int(pair[1]), "cost": data.creature(c).get("cost", {}),
				"max": mx, "reason": reason, "can_recruit": reason == ""})
		out["offers"] = offers
		var first: Dictionary = offers[0] if not offers.is_empty() else {"creature": "", "available": 0, "cost": {}, "max": 0, "reason": "nothing to recruit", "can_recruit": false}
		for o in offers:
			if int(o["available"]) > 0:
				first = o
				break
		for key in ["creature", "available", "cost", "max", "reason", "can_recruit"]:
			out[key] = first[key]
	return out


## Shop offers are copies with command-level validation reasons for the UI.
func trader_info(site_id: String, hero_id: String) -> Array:
	var obj: Dictionary = state.map.objects.get(site_id, {})
	if obj.get("type", "") != "site" or MapSites.kind(obj, data) != "trader":
		return []
	var offers: Array = []
	for i in (obj.get("stock", []) as Array).size():
		var offer: Dictionary = obj["stock"][i].duplicate(true)
		offer["index"] = i
		offer["reason"] = trader_buy_error(site_id, hero_id, i)
		if offer["kind"] == "artifact":
			var art: Dictionary = data.artifacts[offer["artifact"]]
			offer["name"] = art["name"]
			offer["text"] = art["text"]
		else:
			offer["name"] = "Wayfarer's Chart"
			offer["text"] = "Uncover %d random unexplored tiles." % int(offer["tiles"])
		offers.append(offer)
	return offers


func trader_buy_error(site_id: String, hero_id: String, offer_index: int) -> String:
	var obj: Dictionary = state.map.objects.get(site_id, {})
	if obj.get("type", "") != "site" or MapSites.kind(obj, data) != "trader":
		return "not a trader"
	var h := hero(hero_id)
	if h == null or not h.alive or h.owner != state.current_player or state.game_over:
		return "not your hero"
	if h.pos != AdventureMap.object_pos(obj):
		return "visit the trader with this hero"
	if not (obj.get("guard", []) as Array).is_empty():
		return "defeat the guards first"
	var stock: Array = obj.get("stock", [])
	if offer_index < 0 or offer_index >= stock.size():
		return "unknown offer"
	var offer: Dictionary = stock[offer_index]
	if int(offer.get("remaining", 0)) <= 0:
		return "sold out"
	if offer.get("kind", "") == "artifact":
		var aid := String(offer.get("artifact", ""))
		if not data.artifacts.has(aid):
			return "unknown artifact"
		# give_artifact auto-equips an empty slot; otherwise it needs pack space.
		var slot := String(data.artifacts[aid]["slot"])
		if String(h.equipment.get(slot, "")) != "" and h.pack.size() >= int(data.artifact_rules["pack_size"]):
			return "hero's pack is full"
	elif offer.get("kind", "") == "map":
		var fog: FogOfWar = state.player(h.owner)["fog"]
		if fog.explored_count() >= state.map.width * state.map.height:
			return "the entire map is already explored"
	else:
		return "unknown offer"
	if int(offer.get("price", 0)) <= 0 or not _bank(h.owner).can_afford({"gold": int(offer["price"])}):
		return "not enough gold"
	return ""


## Failure never changes gold, stock, fog or RNG state.
func trader_buy(site_id: String, hero_id: String, offer_index: int) -> Dictionary:
	var err := trader_buy_error(site_id, hero_id, offer_index)
	if err != "":
		return _fail(err)
	var h := hero(hero_id)
	var offer: Dictionary = state.map.objects[site_id]["stock"][offer_index]
	var revealed := 0
	var item_name := "Wayfarer's Chart"
	if offer["kind"] == "artifact":
		var aid := String(offer["artifact"])
		if not h.give_artifact(aid, data):
			return _fail("hero's pack is full")
		item_name = String(data.artifacts[aid]["name"])
	else:
		var fog: FogOfWar = state.player(h.owner)["fog"]
		var hidden: Array[int] = []
		for i in fog.explored.size():
			if fog.explored[i] == 0:
				hidden.append(i)
		# Partial Fisher-Yates: no duplicates and every chart reveals fresh tiles.
		revealed = mini(int(offer["tiles"]), hidden.size())
		for k in revealed:
			var j := state.rng.next_int(k, hidden.size() - 1)
			var at := hidden[j]
			hidden[j] = hidden[k]
			hidden[k] = at
			for ally in state.allies_of(h.owner):
				(state.player(ally)["fog"] as FogOfWar).explored[at] = 1
	_bank(h.owner).spend({"gold": int(offer["price"])})
	offer["remaining"] = int(offer["remaining"]) - 1
	if offer["kind"] == "artifact":
		h.movement_left = mini(h.movement_left, h.max_movement(data))
		_reveal_around(h)
	message.emit("%s buys %s for %d gold.%s" % [h.name, item_name, int(offer["price"]),
		" Uncovered %d tiles." % revealed if revealed > 0 else ""])
	state_changed.emit()
	return {"ok": true, "reason": "", "revealed": revealed, "name": item_name}


## How many creatures the hero could recruit at a dwelling or village site now
## (pool, purse). creature: which of a village's offers ("" = the first).
func max_site_recruitable(site_id: String, hero_id: String, creature: String = "") -> int:
	var obj: Dictionary = state.map.objects.get(site_id, {})
	var h := hero(hero_id)
	if obj.get("type", "") != "site" or h == null or not MapSites.RECRUIT_KINDS.has(MapSites.kind(obj, data)):
		return 0
	var c := _site_creature(obj, creature)
	var n := MapSites.available(obj, c, data)
	var unit: Dictionary = data.creature(c).get("cost", {})
	for res in unit:
		if int(unit[res]) > 0:
			n = mini(n, _bank(h.owner).get_amount(res) / int(unit[res]))
	return maxi(0, n)


## The creature a recruit command means: the named one, or the site's first offer.
func _site_creature(obj: Dictionary, creature: String) -> String:
	if creature != "":
		return creature
	var offers := MapSites.offers(obj, data)
	return String(offers[0][0]) if not offers.is_empty() else ""


## Why the hero cannot recruit count creatures at the site, or "".
func site_recruit_error(site_id: String, hero_id: String, count: int, creature: String = "") -> String:
	var obj: Dictionary = state.map.objects.get(site_id, {})
	var h := hero(hero_id)
	if obj.get("type", "") != "site" or not MapSites.RECRUIT_KINDS.has(MapSites.kind(obj, data)):
		return "not a dwelling"
	if h == null or not h.alive or h.owner != state.current_player or state.game_over:
		return "not your hero"
	if h.pos != AdventureMap.object_pos(obj):
		return "a hero must stand at the %s" % MapSites.site_name(obj, data)
	if int(obj.get("owner", -1)) != h.owner:
		return "you do not hold the %s" % MapSites.site_name(obj, data)
	var c := _site_creature(obj, creature)
	if c == "" or MapSites.offers(obj, data).filter(func(p): return String(p[0]) == c).is_empty():
		return "nobody here offers that creature"
	var cap := tier_cap()
	if cap > 0 and int(data.creature(c)["tier"]) > cap:
		return "beyond this chapter's ranks (tier %d)" % cap
	if count <= 0:
		return "nothing to recruit"
	if MapSites.available(obj, c, data) < count:
		return "only %d available" % MapSites.available(obj, c, data)
	if not _bank(h.owner).can_afford(Town.recruit_cost(c, count, data)):
		return "not enough resources"
	if not _has_room(h.army, c):
		return "no free army slot"
	return ""


## Recruits from a dwelling or village site into the hero standing on it.
## creature: which of a village's offers ("" = the first).
func site_recruit(site_id: String, hero_id: String, count: int, creature: String = "") -> Dictionary:
	var err := site_recruit_error(site_id, hero_id, count, creature)
	if err != "":
		return _fail(err)
	var obj: Dictionary = state.map.objects[site_id]
	var h := hero(hero_id)
	var c := _site_creature(obj, creature)
	var cost := Town.recruit_cost(c, count, data)
	_bank(h.owner).spend(cost)
	MapSites.take(obj, c, count, data)
	h.army.add(c, count)
	message.emit("Recruited %d %s at the %s." % [count, data.creature(c)["name"], MapSites.site_name(obj, data)])
	state_changed.emit()
	return {"ok": true, "reason": "", "count": count, "cost": cost}


## Dwelling sites a player holds.
func sites_of(player_idx: int) -> Array:
	var out := []
	for id in _sorted_object_ids():
		var o: Dictionary = state.map.objects[id]
		if o["type"] == "site" and int(o.get("owner", -1)) == player_idx:
			out.append(o)
	return out


func _sorted_object_ids() -> Array:
	var ids := state.map.objects.keys()
	ids.sort()
	return ids


## Weekly growth in towns and dwelling sites, with the omen's bonus; a rotating
## dwelling site (Sellsword Gate) draws a new company and loses the old pool.
func _weekly_growth() -> void:
	for id in _sorted_object_ids():
		var o: Dictionary = state.map.objects[id]
		if o["type"] == "town":
			var bonus := {}
			for c in Town.dwellings(o, data):
				var b := WorldEvents.growth_bonus(state, data, c)
				if b != 0.0:
					bonus[c] = b
			Town.apply_weekly_growth(o, data, bonus)
		elif MapCobolts.is_post(o, data):
			MapCobolts.restock(o)
		elif o["type"] == "site" and MapSites.kind(o, data) == "dwelling":
			var def := MapSites.definition(o, data)
			if bool(def.get("rotate", false)):
				var pool := MapSites.creature_pool(def, data)
				o["creature"] = pool[state.rng.next_int(0, pool.size() - 1)]
				o["available"] = MapSites.weekly_growth(o, data, WorldEvents.growth_bonus(state, data, o["creature"]))
			else:
				o["available"] = int(o["available"]) + MapSites.weekly_growth(o, data, WorldEvents.growth_bonus(state, data, o["creature"]))
	var levy := FactionMechanics.on_week_growth(state, data)
	for tid in levy:
		var t: Dictionary = state.map.objects[tid]
		_add_news(state.player(int(t["owner"])), "%s: %d recruits muster at %s." % [FactionMechanics.of_faction(String(state.player(int(t["owner"]))["faction"]), data)["name"], int(levy[tid]), t["name"]])


func _all_heroes_sorted() -> Array:
	var ids := state.heroes.keys()
	ids.sort()
	var out := []
	for id in ids:
		if (state.heroes[id] as Hero).alive:
			out.append(state.heroes[id])
	return out


func _add_news(p: Dictionary, line: String) -> void:
	if not p["is_human"]:
		return   # nobody would read it
	var news: Array = p.get("news", [])
	news.append(line)
	p["news"] = news


## The event lines waiting for a player (the week's omen, fortunes), oldest
## first; they are cleared once taken. The UI shows them when the player moves.
func take_news(player_idx: int) -> Array:
	var p := state.player(player_idx)
	var out: Array = p.get("news", [])
	p["news"] = []
	return out


## The week's omen for the HUD: {name, text} or {} on a quiet start.
func current_omen() -> Dictionary:
	var def := WorldEvents.omen_def(state, data)
	if def.is_empty():
		return {}
	return {"id": state.omen["id"], "name": def["name"], "text": WorldEvents.omen_text(state, data)}


# ------------------------------------------------------------- encounters --

## Choice list for the encounter dialog (see EncounterSystem.options).
func encounter_options(hero_id: String, object_id: String) -> Dictionary:
	var h := hero(hero_id)
	if h == null or not state.map.objects.has(object_id):
		return {}
	var opts := encounters.options(h, state.map.objects[object_id])
	# Hard mode hides success chances as it hides battle odds.
	opts["hide_chances"] = odds_hidden()
	return opts


## Applies the chosen option. If the result has a non-empty "battle", an ambush
## army now stands on the encounter tile: show the forecast and call attack().
func resolve_encounter(hero_id: String, object_id: String, choice_idx: int) -> Dictionary:
	var h := hero(hero_id)
	if h == null or not h.alive or h.owner != state.current_player or state.game_over or not state.map.objects.has(object_id):
		return {"ok": false}
	var obj: Dictionary = state.map.objects[object_id]
	var d := AdventureMap.object_pos(obj) - h.pos
	if obj.get("type", "") != "encounter" or maxi(absi(d.x), absi(d.y)) > 1:
		return {"ok": false}
	var result := encounters.resolve(h, obj, choice_idx)
	result["hero_id"] = hero_id
	if result["ok"] and not result["leave"]:
		_reveal_around(h)
		encounter_resolved.emit(result)
		state_changed.emit()
	return result


# ------------------------------------------------------------ progression --

## The skill choices for a hero's next unspent skill point. Stable until a skill
## is learned (seeded from the game seed, hero, level and skills known).
func skill_offers(hero_id: String) -> Array:
	var h := hero(hero_id)
	if h == null or h.skill_points <= 0:
		return []
	var known := 0
	for sk in h.skills:
		known += int(h.skills[sk])
	return h.skill_offers_seeded(data, GameRng.mix(state.game_seed ^ (h.id.hash() & GameRng.MASK32), h.level * 64 + known))


## Spends one skill point on one of the current offers.
func learn_skill(hero_id: String, skill_id: String) -> bool:
	var h := hero(hero_id)
	if h == null or h.owner != state.current_player or not skill_offers(hero_id).has(skill_id):
		return false
	var ok := h.learn_skill(skill_id, data)
	if ok:
		_reveal_around(h)
		message.emit("%s learns %s %d." % [h.name, data.skills[skill_id]["name"], h.skill_level(skill_id)])
		state_changed.emit()
	return ok


# ---------------------------------------------------------- battle orders --

## The hero's orders and every option, for the forecast's pickers:
## {stance, focus, formation, art, retreat, drill?, options: {kind: [{id, name,
## desc, open, level, drilled}]}} (drilled: the formation's benefits grow by
## this share for this hero, from its class, skill or specialty).
func order_choices(hero_id: String) -> Dictionary:
	var h := hero(hero_id)
	if h == null:
		return {}
	var out := h.battle_orders(data)
	var cmd := h.commander(data)
	var opts := {}
	for kind in BattleOrders.KINDS:
		opts[kind] = []
		for id in BattleOrders.ids(data, kind):
			var o: Dictionary = BattleOrders.table(data, kind)[id]
			opts[kind].append({"id": id, "name": o["name"], "desc": o["desc"], "open": h.can_order(kind, id, data),
				"level": BattleOrders.level_needed(data, kind, id, h.skill_level("tactics"), cmd),
				"drilled": BattleOrders.drill_pct(data, id, cmd) if kind == BattleOrders.FORMATION else 0.0})
	out["options"] = opts
	return out


## Sets a hero's standing stance and focus (data/tactics.json), keeping the
## other orders. Both options must be open to the hero. Returns false otherwise.
func set_hero_orders(hero_id: String, stance: String, focus: String) -> bool:
	return set_battle_orders(hero_id, {BattleOrders.STANCE: stance, BattleOrders.FOCUS: focus})


## Sets any of a hero's standing battle orders ({stance, focus, formation, art,
## retreat}; kinds left out stay as they are). Every given option must be open
## to the hero (level, Tactics and the option's skill, class or specialty).
func set_battle_orders(hero_id: String, changes: Dictionary) -> bool:
	var h := hero(hero_id)
	if h == null or h.owner != state.current_player:
		return false
	var next := h.orders.duplicate()
	for kind in BattleOrders.KINDS:
		if not changes.has(kind):
			continue
		var id := String(changes[kind])
		if not h.can_order(kind, id, data):
			return false
		next[kind] = id
	if next == h.orders:
		return true
	h.orders = next
	state_changed.emit()
	return true


# -------------------------------------------------------------- equipment --

## Wears an artifact from the hero's pack (the previous one goes to the pack).
func equip_artifact(hero_id: String, artifact_id: String) -> Dictionary:
	var h := hero(hero_id)
	if h == null or h.owner != state.current_player or state.game_over:
		return _fail("not your hero")
	if not h.equip(artifact_id, data):
		return _fail("not in the pack")
	_after_equipment_change(h)
	return {"ok": true, "reason": ""}


func unequip_artifact(hero_id: String, slot: String) -> Dictionary:
	var h := hero(hero_id)
	if h == null or h.owner != state.current_player or state.game_over:
		return _fail("not your hero")
	if not h.unequip(slot, data):
		return _fail("nothing worn there or the pack is full")
	_after_equipment_change(h)
	return {"ok": true, "reason": ""}


## Hands an artifact from one hero's pack or slots to another hero on the same or an adjacent tile.
func give_artifact(from_id: String, to_id: String, artifact_id: String) -> Dictionary:
	var a := hero(from_id)
	var b := hero(to_id)
	if a == null or b == null or a == b or a.owner != state.current_player or b.owner != a.owner or state.game_over:
		return _fail("not your heroes")
	var d := a.pos - b.pos
	if maxi(absi(d.x), absi(d.y)) > 1:
		return _fail("the heroes must stand next to each other")
	if not a.all_artifacts(data).has(artifact_id):
		return _fail("not carried")
	var slot: String = data.artifacts[artifact_id]["slot"]
	var worn := String(a.equipment.get(slot, "")) == artifact_id
	if worn:
		a.equipment.erase(slot)
	else:
		a.pack.erase(artifact_id)
	if not b.give_artifact(artifact_id, data):
		if worn:
			a.equipment[slot] = artifact_id
		else:
			a.pack.append(artifact_id)
		return _fail("the pack is full")
	_after_equipment_change(a)
	_after_equipment_change(b)
	return {"ok": true, "reason": ""}


## Movement beyond a lowered maximum is not kept; more vision reveals at once.
func _after_equipment_change(h: Hero) -> void:
	h.movement_left = mini(h.movement_left, h.max_movement(data))
	_reveal_around(h)
	state_changed.emit()


# --------------------------------------------------------------- campaign --

## Applies a campaign veteran's record (Hero.campaign_dict(), may be empty for a
## hero's first chapter) and the chapter's level cap to a map hero. Banked XP
## pays out if the cap allows. Movement and vision are refreshed.
func adopt_veteran(hero_id: String, record: Dictionary, level_cap: int) -> void:
	var h := hero(hero_id)
	if h == null:
		return
	if not record.is_empty():
		h.apply_campaign(record)
	h.level_cap = level_cap
	h.add_xp(0, data)
	h.movement_left = h.max_movement(data)
	_reveal_around(h)


# ------------------------------------------------------------------ turns --

func end_turn() -> void:
	if state.game_over:
		return
	var n := state.players.size()
	var next := state.current_player
	for i in n:
		next = (next + 1) % n
		if not state.player(next)["defeated"]:
			break
	if next <= state.current_player:
		_start_new_day()
	state.current_player = next
	VictoryRules.update(self)
	state_changed.emit()


func _start_new_day() -> void:
	state.day += 1
	# Scouting reports hold for one day.
	for p in state.players:
		p["scouted"] = {}
	var events := WorldEvents.enabled(state, data) and state.day >= WorldEvents.start_day(data)
	for id in state.heroes:
		(state.heroes[id] as Hero).expire_boons(state.day)
	if state.day_of_week() == 1:
		if events:
			WorldEvents.roll_omen(state, data, _all_heroes_sorted())
			var line := WorldEvents.omen_text(state, data)
			for p in state.players:
				if not p["defeated"]:
					_add_news(p, "Omen of week %d. %s" % [state.week(), line])
		_weekly_growth()
		if events:
			for r in RoamingThreats.on_week(self):
				for p in state.players:
					if not p["defeated"]:
						_add_news(p, "%s has been seen in the wilds. It hunts for the nearest town." % r["name"])
		message.emit("Week %d begins. Creatures in the dwellings have multiplied." % state.week())
	if events:
		for i in state.players.size():
			if state.player(i)["defeated"]:
				continue
			var news := WorldEvents.roll_fortune(state, data, i, _heroes_sorted(i))
			if news != "":
				_add_news(state.player(i), news)
	FactionMechanics.on_day_start(state, data, _all_heroes_sorted())
	for id in state.heroes:
		var h: Hero = state.heroes[id]
		h.movement_left = h.max_movement(data)
		if h.alive:
			h.restore_mana(int(data.rules["mana_daily_regen"]) + WorldEvents.mana_regen(state, data), data)
	FactionMechanics.on_day_vision(state, data, allied)
	var threat_news := RoamingThreats.on_day(self)
	var plague_news := WorldEvents.apply_plague(state, data, _all_heroes_sorted())
	for i in state.players.size():
		for line in threat_news.get(i, []) + plague_news.get(i, []):
			_add_news(state.player(i), line)
	ColdAttrition.on_day(self)
	WaveDirector.on_day(self)
	VictoryRules.on_new_day(self)
	for i in state.players.size():
		if state.player(i)["defeated"]:
			continue
		var income := daily_income(i)
		for res in data.resource_order:
			if int(income.get(res, 0)) > 0:
				_bank(i).add(res, int(income[res]))
	day_started.emit(state.day)


# ------------------------------------------------- towns, mines, economy --
# Commands for the UI and the strategic AI. Every command checks that the town
# belongs to the current player and returns {ok, reason, ...} (or a reason
# string from the can_* queries, "" meaning allowed); nothing is changed on
# failure.

func _bank(player_idx: int) -> ResourceBank:
	return state.player(player_idx)["resources"]


func _controls(t: Dictionary) -> bool:
	return not t.is_empty() and int(t["owner"]) == state.current_player and not state.game_over


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _capture(obj: Dictionary, player_idx: int) -> void:
	var previous := int(obj["owner"])
	obj["owner"] = player_idx
	var who: String = state.player(player_idx)["name"]
	var spoils := FactionMechanics.plunder(obj, previous, player_idx, state, data)
	if not spoils.is_empty():
		var parts := []
		for res in data.resource_order:
			if spoils.has(res):
				_bank(player_idx).add(res, int(spoils[res]))
				parts.append("+%d %s" % [int(spoils[res]), data.resources[res]["name"]])
		message.emit("%s: %s." % [FactionMechanics.of_faction(String(state.player(player_idx)["faction"]), data)["name"], ", ".join(parts)])
	if obj["type"] == "town":
		message.emit("%s takes the town of %s." % [who, obj["name"]])
		if previous >= 0:
			VictoryRules.update(self)
	elif obj["type"] == "site":
		message.emit("%s claims the %s (%s)." % [who, MapSites.site_name(obj, data), MapSites.summary(obj, data)])
	else:
		message.emit("%s claims the %s (+%d %s a day)." % [who, Economy.mine_name(obj, data),
			Economy.mine_income(obj, data), data.resources[obj["resource"]]["name"]])


func town(town_id: String) -> Dictionary:
	var o: Dictionary = state.map.objects.get(town_id, {})
	return o if o.get("type", "") == "town" else {}


func towns_of(player_idx: int) -> Array:
	return Economy.towns_of(state.map, player_idx)


func mines_of(player_idx: int) -> Array:
	return Economy.mines_of(state.map, player_idx)


## Towns, mines and the player's heroes (Stewardship, class traits, artifacts),
## scaled by a computer player's difficulty (income_percent, rounded).
func daily_income(player_idx: int) -> Dictionary:
	var out := Economy.daily_income(state.map, player_idx, data)
	for h in _heroes_sorted(player_idx):
		var inc: Dictionary = h.modifiers(data).get("income", {})
		for res in inc:
			out[res] = int(out.get(res, 0)) + int(inc[res])
	var pct := income_percent(player_idx)
	if pct != 100:
		for res in out.keys():
			out[res] = int(round(float(out[res]) * float(pct) / 100.0))
	# The week's omen (Tithe Riots, Rich Veins).
	for res in out.keys():
		var omen_pct := WorldEvents.income_pct(state, data, res)
		if omen_pct != 0.0:
			out[res] = maxi(0, int(round(float(out[res]) * (1.0 + omen_pct))))
	return out


## Where a player's daily income comes from, per resource, for the HUD:
## {res: {"total": int (= daily_income), "sources": [[label, text], ...]}}
## with one line per town, per kind of mine ("2 Ore Pit: +4"), per hero with an
## income bonus, and the difficulty and omen percentages. Resources with no
## income have total 0 and no sources.
func income_breakdown(player_idx: int) -> Dictionary:
	var out := {}
	var total := daily_income(player_idx)
	for res in data.resource_order:
		out[res] = {"total": int(total.get(res, 0)), "sources": []}
	for t in towns_of(player_idx):
		var inc := Town.daily_income(t, data)
		for res in data.resource_order:
			if int(inc.get(res, 0)) > 0:
				out[res]["sources"].append([String(t["name"]), "%+d" % int(inc[res])])
	var mines := {}   # res -> {name -> [count, amount]}
	var mine_names := {}
	for m in mines_of(player_idx):
		var res := String(m["resource"])
		var mname := Economy.mine_name(m, data)
		var by_name: Dictionary = mines.get(res, {})
		var e: Array = by_name.get(mname, [0, 0])
		by_name[mname] = [int(e[0]) + 1, int(e[1]) + Economy.mine_income(m, data)]
		mines[res] = by_name
	for res in data.resource_order:
		var by_name: Dictionary = mines.get(res, {})
		var names := by_name.keys()
		names.sort()
		for mname in names:
			var e: Array = by_name[mname]
			out[res]["sources"].append(["%s%s" % ["%d× " % int(e[0]) if int(e[0]) > 1 else "", mname], "%+d" % int(e[1])])
	for h in _heroes_sorted(player_idx):
		var inc: Dictionary = h.modifiers(data).get("income", {})
		for res in data.resource_order:
			if int(inc.get(res, 0)) != 0:
				out[res]["sources"].append([h.name, "%+d" % int(inc[res])])
	var pct := income_percent(player_idx)
	var omen := current_omen()
	for res in data.resource_order:
		if (out[res]["sources"] as Array).is_empty():
			continue
		if pct != 100:
			out[res]["sources"].append(["%s difficulty" % data.difficulty(difficulty_of(player_idx))["name"], "%+d%%" % (pct - 100)])
		var omen_pct := WorldEvents.income_pct(state, data, res)
		if omen_pct != 0.0:
			out[res]["sources"].append([String(omen.get("name", "This week's omen")), "%+d%%" % roundi(omen_pct * 100.0)])
	return out


## A player's difficulty level id (data/ai_difficulty.json); humans play "normal" rules.
func difficulty_of(player_idx: int) -> String:
	return String(state.player(player_idx).get("difficulty", data.default_difficulty()))


## The share of its normal income (percent) a player earns: 100 for humans,
## the difficulty level's income_percent for computer players.
func income_percent(player_idx: int) -> int:
	if bool(state.player(player_idx)["is_human"]):
		return 100
	return int(data.difficulty(difficulty_of(player_idx)).get("income_percent", 100))


## Enemy heroes the player can see (on an explored tile) that could reach one
## of the player's towns within game_rules threat_warning_days days of full
## movement, nearest first: [{hero_id, hero, town_id, town, days}]. One entry
## per enemy hero (its nearest threatened town).
func town_threats(player_idx: int) -> Array:
	var out := []
	var limit := int(data.rules.get("threat_warning_days", 0))
	var towns := towns_of(player_idx)
	if limit <= 0 or towns.is_empty():
		return out
	var fog: FogOfWar = state.player(player_idx)["fog"]
	var ids: Array = state.heroes.keys()
	ids.sort()
	for id in ids:
		var e: Hero = state.heroes[id]
		if not e.alive or allied(e.owner, player_idx) or e.owner < 0 or not fog.is_explored(e.pos):
			continue
		var per_day := maxi(1, e.max_movement(data))
		var blocked := _guarded_positions(e.owner)
		blocked.append_array(_other_hero_positions(e))
		var best := {}
		for t in towns:
			var p := AdventureMap.object_pos(t)
			var path := pathfinder.find_path(e.pos, p, blocked)
			if path.is_empty():
				continue
			var cost := 0
			for c in pathfinder.step_costs(e.pos, path, e.move_cost_mods(data)):
				cost += c
			var days := ceili(float(cost) / per_day)
			if days <= limit and (best.is_empty() or days < int(best["days"])):
				best = {"hero_id": e.id, "hero": e.name, "town_id": t["id"], "town": t["name"], "days": maxi(1, days)}
		if not best.is_empty():
			out.append(best)
	out.sort_custom(func(a, b): return a["days"] < b["days"] or (a["days"] == b["days"] and a["hero_id"] < b["hero_id"]))
	return out


## Living heroes of a player in id order (stable regardless of dictionary history).
func _heroes_sorted(player_idx: int) -> Array:
	var hs := state.heroes_of(player_idx)
	hs.sort_custom(func(a, b): return a.id < b.id)
	return hs


## The town owner's hero standing in the town, if any. Recruits join this hero.
func visiting_hero(town_id: String) -> Hero:
	var t := town(town_id)
	if t.is_empty():
		return null
	var h := state.hero_at(AdventureMap.object_pos(t))
	return h if h != null and h.owner == int(t["owner"]) else null


## Why the hero cannot cast this spell, or an empty string when allowed.
func can_cast_spell(hero_id: String, spell_id: String, destination_id: String = "") -> String:
	var h := hero(hero_id)
	if h == null or not h.alive or h.owner != state.current_player or state.game_over:
		return "not your active hero"
	if not h.known_spells(data).has(spell_id):
		return "spell not known"
	var spell: Dictionary = data.magic["spells"].get(spell_id, {})
	if spell.is_empty():
		return "unknown spell"
	if h.mana < int(spell["cost"]):
		return "not enough mana"
	if spell["effect"] in ["home", "town_gate"]:
		var destination := town(h.home_town if spell["effect"] == "home" else destination_id)
		if destination.is_empty() or int(destination["owner"]) != h.owner:
			return "destination is not one of your towns"
		var pos := AdventureMap.object_pos(destination)
		if pos == h.pos:
			return "already at destination"
		if state.hero_at(pos) != null:
			return "destination is occupied by a hero"
		if spell["effect"] == "town_gate":
			var origin := state.map.object_at(h.pos)
			if origin.is_empty() or origin["type"] != "town" or int(origin["owner"]) != h.owner:
				return "must stand in one of your towns"
	if spell["effect"] == "movement" and h.movement_left >= h.max_movement(data):
		return "movement already full"
	if spell["effect"] == "battle_damage" and h.battle_spell_damage >= float(spell["amount"]):
		return "an equal or stronger battle spell is already active"
	return ""


func cast_spell(hero_id: String, spell_id: String, destination_id: String = "") -> Dictionary:
	var reason := can_cast_spell(hero_id, spell_id, destination_id)
	if reason != "":
		return _fail(reason)
	var h := hero(hero_id)
	var spell: Dictionary = data.magic["spells"][spell_id]
	h.mana -= int(spell["cost"])
	match String(spell["effect"]):
		"movement":
			h.movement_left = mini(h.max_movement(data), h.movement_left + int(round(h.max_movement(data) * float(spell["amount"]))))
		"battle_damage":
			h.battle_spell_damage = float(spell["amount"])
		"home", "town_gate":
			var destination := town(h.home_town if spell["effect"] == "home" else destination_id)
			h.pos = AdventureMap.object_pos(destination)
			_reveal_around(h)
	message.emit("%s casts %s." % [h.name, spell["name"]])
	state_changed.emit()
	return {"ok": true, "reason": ""}


## Deep Roads (Sunken Forge): the holdings this hero can travel to now, as
## [{id, name, kind, pos}] (empty if the hero cannot use the deep roads here).
func deep_road_destinations(hero_id: String) -> Array:
	var h := hero(hero_id)
	var out := []
	if h == null or not h.alive or not FactionMechanics.hero_has(h, "deep_roads", data):
		return out
	for o in FactionMechanics.deep_road_nodes(state, h.owner):
		if FactionMechanics.deep_road_error(state, data, h, String(o["id"])) == "":
			out.append({"id": o["id"], "kind": o["type"], "pos": AdventureMap.object_pos(o),
				"name": String(o["name"]) if o["type"] == "town" else Economy.mine_name(o, data)})
	return out


## Why the hero cannot take the deep road to a holding ("" when it can).
func can_deep_road(hero_id: String, destination_id: String) -> String:
	var h := hero(hero_id)
	if h == null or not h.alive or h.owner != state.current_player or state.game_over:
		return "not your active hero"
	return FactionMechanics.deep_road_error(state, data, h, destination_id)


## Moves the hero through the deep roads to one of its player's mines or towns.
## Spends all of its remaining movement.
func deep_road(hero_id: String, destination_id: String) -> Dictionary:
	var reason := can_deep_road(hero_id, destination_id)
	if reason != "":
		return _fail(reason)
	var h := hero(hero_id)
	var dest: Dictionary = state.map.objects[destination_id]
	h.pos = FactionMechanics.arrival_tile(state, dest)
	h.movement_left = 0
	ScenarioRules.on_visit(state, h)
	_reveal_around(h)
	var where := String(dest["name"]) if dest["type"] == "town" else Economy.mine_name(dest, data)
	message.emit("%s takes the deep roads to %s." % [h.name, where])
	state_changed.emit()
	return {"ok": true, "reason": "", "pos": h.pos}


## Converts an owned foreign town to the current player's faction.
func can_convert_town(town_id: String) -> String:
	var t := town(town_id)
	if not _controls(t):
		return "not your town"
	var faction := String(current_player()["faction"])
	if not data.town_types.has(faction):
		return "no town type for your faction"
	if t["town_type"] == faction:
		return "already your faction"
	if not _bank(int(t["owner"])).can_afford(data.economy["conversion_cost"]):
		return "not enough resources"
	return ""


func convert_town(town_id: String) -> Dictionary:
	var err := can_convert_town(town_id)
	if err != "":
		return _fail(err)
	var t := town(town_id)
	var cost: Dictionary = data.economy["conversion_cost"].duplicate()
	_bank(int(t["owner"])).spend(cost)
	t["town_type"] = String(current_player()["faction"])
	t["built"] = (data.town_types[t["town_type"]]["starting_buildings"] as Array).duplicate()
	t["available"] = {}
	for creature in Town.dwellings(t, data):
		t["available"][creature] = Town.weekly_growth(t, creature, data)
	message.emit("%s converted to %s." % [t["name"], data.town_types[t["town_type"]]["name"]])
	state_changed.emit()
	return {"ok": true, "reason": "", "cost": cost}


func can_build(town_id: String, building_id: String) -> String:
	var t := town(town_id)
	if not _controls(t):
		return "not your town"
	return Town.build_error(t, building_id, _bank(int(t["owner"])), state.day, data)


## One building per town per day.
func build(town_id: String, building_id: String) -> Dictionary:
	var err := can_build(town_id, building_id)
	if err != "":
		return _fail(err)
	var t := town(town_id)
	var cost := Town.build_cost(t, building_id, data)
	_bank(int(t["owner"])).spend(cost)
	Town.construct(t, building_id, state.day, data)
	message.emit("%s: %s completed." % [t["name"], Town.building(t, building_id, data)["name"]])
	state_changed.emit()
	return {"ok": true, "reason": "", "cost": cost}


## Every building of the town with its status, for the building screen and the AI:
## [{id, name, category, description, built, cost, reason}] in data order.
func build_options(town_id: String) -> Array:
	var t := town(town_id)
	var out := []
	if t.is_empty():
		return out
	for b_id in Town.building_ids(t, data):
		var b := Town.building(t, b_id, data)
		out.append({"id": b_id, "name": b["name"], "category": b["category"], "description": b["description"],
			"built": Town.has_building(t, b_id), "cost": Town.build_cost(t, b_id, data),
			"reason": can_build(town_id, b_id)})
	return out


## Recruitment pool: [{creature, pool, available, cost (per creature), growth, max}]
## by tier; an upgraded creature shares its base's pool.
func recruit_options(town_id: String) -> Array:
	var t := town(town_id)
	var out := []
	if t.is_empty():
		return out
	for c in Town.recruitable(t, data):
		var pool := Town.pool_of(c, data)
		out.append({"creature": c, "pool": pool, "available": int(t["available"].get(pool, 0)),
			"cost": data.creature(c)["cost"], "growth": Town.weekly_growth(t, pool, data),
			"max": max_recruitable(town_id, c)})
	return out


func max_recruitable(town_id: String, creature_id: String) -> int:
	var t := town(town_id)
	if t.is_empty():
		return 0
	return Town.max_affordable(t, creature_id, _bank(maxi(0, int(t["owner"]))), data)


static func _has_room(army: Army, creature_id: String, veteran_xp: int = 0) -> bool:
	for s in army.slots:
		if s.is_empty() or (s["creature"] == creature_id and Army.veteran_level(s) == Army.level_for_xp(veteran_xp)):
			return true
	return false


## Recruits into the visiting hero's army, or into the garrison when no hero is
## in town or to_garrison is set.
func recruit(town_id: String, creature_id: String, count: int, to_garrison: bool = false) -> Dictionary:
	var t := town(town_id)
	if not _controls(t):
		return _fail("not your town")
	var bank := _bank(int(t["owner"]))
	var err := Town.recruit_error(t, creature_id, count, bank, data)
	if err != "":
		return _fail(err)
	var h: Hero = null if to_garrison else visiting_hero(town_id)
	var army: Army = h.army if h != null else Town.garrison(t)
	army.initialize_veterans(data)
	var veteran_xp: int = Army.VETERAN_THRESHOLDS[2] if data.creature(creature_id).has("upgrade_of") else 0
	if not _has_room(army, creature_id, veteran_xp):
		return _fail("no free army slot")
	var cost := recruit_price(town_id, creature_id, count)
	bank.spend(cost)
	var pool := Town.pool_of(creature_id, data)
	t["available"][pool] = int(t["available"][pool]) - count
	army.add(creature_id, count, veteran_xp)
	if h == null:
		Town.set_garrison(t, army)
	message.emit("Recruited %d %s." % [count, data.creature(creature_id)["name"]])
	state_changed.emit()
	return {"ok": true, "reason": "", "count": count, "to": h.id if h != null else "garrison", "cost": cost}


## What recruiting costs in this town now: the visiting hero's
## recruit_discount_pct (Quartermaster, Tempered Craft, artifacts) cuts the gold.
func recruit_price(town_id: String, creature_id: String, count: int) -> Dictionary:
	var cost := Town.recruit_cost(creature_id, count, data)
	var h := visiting_hero(town_id)
	if h != null and cost.has("gold"):
		var cut := HeroModifiers.num(h.modifiers(data), "recruit_discount_pct")
		cost["gold"] = int(round(int(cost["gold"]) * (1.0 - cut)))
	return cost


## Moves a whole stack between the garrison and the visiting hero. The hero
## must keep at least one stack.
func move_stack(town_id: String, slot: int, from_garrison: bool) -> Dictionary:
	var t := town(town_id)
	if not _controls(t):
		return _fail("not your town")
	var h := visiting_hero(town_id)
	if h == null:
		return _fail("no hero in town")
	var g := Town.garrison(t)
	var src: Army = g if from_garrison else h.army
	var dst: Army = h.army if from_garrison else g
	src.initialize_veterans(data)
	dst.initialize_veterans(data)
	if slot < 0 or slot >= Army.MAX_SLOTS or src.slots[slot].is_empty():
		return _fail("empty slot")
	if not from_garrison and h.army.stack_count() <= 1:
		return _fail("a hero needs at least one stack")
	var st: Dictionary = src.slots[slot]
	if not dst.add(st["creature"], int(st["count"]), int(st.get("veteran_xp", 0))):
		return _fail("no free army slot")
	src.slots[slot] = {}
	Town.set_garrison(t, g)
	state_changed.emit()
	return {"ok": true, "reason": ""}


## Army reference for transfer_stack: a hero id, or "garrison:<town id>".
static func garrison_ref(town_id: String) -> String:
	return "garrison:" + town_id


## Resolves an army reference the current player may reorganise:
## {army, hero, town} or {} when it is not theirs.
func _owned_army(ref: String) -> Dictionary:
	if state.game_over:
		return {}
	if ref.begins_with("garrison:"):
		var t := town(ref.trim_prefix("garrison:"))
		return {"army": Town.garrison(t), "hero": null, "town": t} if _controls(t) else {}
	var h := hero(ref)
	if h == null or not h.alive or h.owner != state.current_player:
		return {}
	return {"army": h.army, "hero": h, "town": {}}


## Why two armies cannot exchange troops ("" when they can): a hero and the
## garrison of the town the hero stands in, or two heroes on adjacent tiles.
func _exchange_error(a: Dictionary, b: Dictionary) -> String:
	if a["hero"] != null and b["hero"] != null:
		if a["hero"] == b["hero"]:
			return ""
		var d: Vector2i = (a["hero"] as Hero).pos - (b["hero"] as Hero).pos
		return "" if maxi(absi(d.x), absi(d.y)) <= 1 else "too far apart"
	if a["hero"] == null and b["hero"] == null:
		return "" if a["town"]["id"] == b["town"]["id"] else "too far apart"
	var h: Hero = a["hero"] if a["hero"] != null else b["hero"]
	var t: Dictionary = a["town"] if a["hero"] == null else b["town"]
	return "" if visiting_hero(t["id"]) == h else "hero not in town"


## Army management: moves `count` creatures (0 = the whole stack) from one slot
## to another, within an army or between a hero and its town's garrison (or an
## adjacent hero). An empty target slot receives them, a stack of the same
## creature absorbs them, and a different creature swaps places when the whole
## stack moves. A hero always keeps at least one creature.
func transfer_stack(from_ref: String, from_slot: int, to_ref: String, to_slot: int, count: int = 0) -> Dictionary:
	var a := _owned_army(from_ref)
	var b := a if to_ref == from_ref else _owned_army(to_ref)
	if a.is_empty() or b.is_empty():
		return _fail("not your army")
	var err := _exchange_error(a, b)
	if err != "":
		return _fail(err)
	var src: Army = a["army"]
	var dst: Army = b["army"]
	src.initialize_veterans(data)
	dst.initialize_veterans(data)
	if from_slot < 0 or from_slot >= Army.MAX_SLOTS or to_slot < 0 or to_slot >= Army.MAX_SLOTS:
		return _fail("no such slot")
	if src.slots[from_slot].is_empty():
		return _fail("empty slot")
	if from_ref == to_ref and from_slot == to_slot:
		return _fail("same slot")
	var have := int(src.slots[from_slot]["count"])
	var n := have if count <= 0 else count
	if n > have:
		return _fail("not enough creatures")
	var creature: String = src.slots[from_slot]["creature"]
	var target: Dictionary = dst.slots[to_slot]
	var swapped := false
	if target.is_empty() or (target["creature"] == creature and Army.veteran_level(target) == Army.veteran_level(src.slots[from_slot])):
		if a["hero"] != null and from_ref != to_ref and n == src.total_creatures():
			return _fail("a hero needs at least one creature")
		var moved: Dictionary = src.slots[from_slot].duplicate(true)
		moved["count"] = n
		if not target.is_empty():
			moved["veteran_xp"] = int((int(moved.get("veteran_xp", 0)) * n + int(target.get("veteran_xp", 0)) * int(target["count"])) / float(n + int(target["count"])))
			moved["count"] = n + int(target["count"])
		dst.slots[to_slot] = moved
		if n == have:
			src.slots[from_slot] = {}
		else:
			src.slots[from_slot]["count"] = have - n
	elif n == have:
		dst.slots[to_slot] = src.slots[from_slot].duplicate(true)
		src.slots[from_slot] = target.duplicate(true)
		swapped = true
	else:
		return _fail("slot holds another creature")
	if a["hero"] == null:
		Town.set_garrison(a["town"], src)
	if b["hero"] == null and b != a:
		Town.set_garrison(b["town"], dst)
	state_changed.emit()
	return {"ok": true, "reason": "", "moved": n, "swapped": swapped}


## Stacks in this town (garrison and visiting hero) that its upgrade buildings
## can convert: [{slot, in_garrison, creature, upgrade, count, cost, reason}].
func upgrade_options(town_id: String) -> Array:
	var t := town(town_id)
	var out := []
	if t.is_empty():
		return out
	var armies := [[true, Town.garrison(t)]]
	var h := visiting_hero(town_id)
	if h != null:
		armies.append([false, h.army])
	for pair in armies:
		var army: Army = pair[1]
		for i in Army.MAX_SLOTS:
			var st: Dictionary = army.slots[i]
			if st.is_empty():
				continue
			var up := Town.upgrade_for(t, st["creature"], data)
			if up == "":
				continue
			out.append({"slot": i, "in_garrison": pair[0], "creature": st["creature"], "upgrade": up,
				"count": int(st["count"]), "cost": Town.upgrade_cost(st["creature"], int(st["count"]), data),
				"reason": can_upgrade_stack(town_id, i, pair[0])})
	return out


func can_upgrade_stack(town_id: String, slot: int, in_garrison: bool) -> String:
	var t := town(town_id)
	if not _controls(t):
		return "not your town"
	var army: Army
	if in_garrison:
		army = Town.garrison(t)
	else:
		var h := visiting_hero(town_id)
		if h == null:
			return "no hero in town"
		army = h.army
	if slot < 0 or slot >= Army.MAX_SLOTS or army.slots[slot].is_empty():
		return "empty slot"
	var st: Dictionary = army.slots[slot]
	if Town.upgrade_for(t, st["creature"], data) == "":
		return "this town cannot upgrade %s" % data.creature(st["creature"])["name"]
	if not _bank(int(t["owner"])).can_afford(Town.upgrade_cost(st["creature"], int(st["count"]), data)):
		return "not enough resources"
	return ""


## Upgrades a whole stack in place for the difference in recruitment cost.
## If the army already holds the upgraded creature, the stacks merge.
func upgrade_stack(town_id: String, slot: int, in_garrison: bool) -> Dictionary:
	var err := can_upgrade_stack(town_id, slot, in_garrison)
	if err != "":
		return _fail(err)
	var t := town(town_id)
	var h: Hero = null if in_garrison else visiting_hero(town_id)
	var army: Army = Town.garrison(t) if in_garrison else h.army
	var st: Dictionary = army.slots[slot]
	var base: String = st["creature"]
	var up := Town.upgrade_for(t, base, data)
	var count := int(st["count"])
	var cost := Town.upgrade_cost(base, count, data)
	_bank(int(t["owner"])).spend(cost)
	army.slots[slot] = {}
	army.add(up, count, Army.VETERAN_THRESHOLDS[2])
	if in_garrison:
		Town.set_garrison(t, army)
	message.emit("%d %s upgraded to %s." % [count, data.creature(base)["name"], data.creature(up)["name"]])
	state_changed.emit()
	return {"ok": true, "reason": "", "creature": up, "cost": cost}


func _next_hire(t: Dictionary) -> Dictionary:
	var pool: Array = data.town_types[t["town_type"]]["hire"]["heroes"]
	for i in pool.size():
		var hid := "hire_%s_%d" % [t["town_type"], i]
		if not state.heroes.has(hid):
			return {"id": hid, "name": pool[i]["name"], "class": pool[i]["class"]}
	return {}


func hire_cost(town_id: String) -> Dictionary:
	var t := town(town_id)
	return {} if t.is_empty() else data.town_types[t["town_type"]]["hire"]["cost"]


## The hero the town's tavern offers next ({id, name, class}), or {}.
func hire_offer(town_id: String) -> Dictionary:
	var t := town(town_id)
	return {} if t.is_empty() else _next_hire(t)


func can_hire_hero(town_id: String) -> String:
	var t := town(town_id)
	if not _controls(t):
		return "not your town"
	if not Town.has_effect(t, "tavern", data):
		return "no tavern"
	var standing := state.hero_at(AdventureMap.object_pos(t))
	if standing != null:
		return "%s stands in the town: march out to make room for a new hero" % standing.name
	if state.heroes_of(int(t["owner"])).size() >= int(data.economy["max_heroes_per_player"]):
		return "hero limit reached"
	if _next_hire(t).is_empty():
		return "no heroes for hire"
	if not _bank(int(t["owner"])).can_afford(hire_cost(town_id)):
		return "not enough gold"
	return ""


func hire_hero(town_id: String) -> Dictionary:
	var err := can_hire_hero(town_id)
	if err != "":
		return _fail(err)
	var t := town(town_id)
	var offer := _next_hire(t)
	var p := AdventureMap.object_pos(t)
	_bank(int(t["owner"])).spend(hire_cost(town_id))
	var h := Hero.create({"id": offer["id"], "name": offer["name"], "class": offer["class"], "owner": int(t["owner"]),
		"pos": [p.x, p.y], "army": data.town_types[t["town_type"]]["hire"]["army"]}, data)
	h.home_town = town_id
	state.heroes[h.id] = h
	WorldEvents.grant_omen_boon(state, data, h)
	h.movement_left = h.max_movement(data)
	_reveal_around(h)
	message.emit("%s joins your cause at %s." % [h.name, t["name"]])
	state_changed.emit()
	return {"ok": true, "reason": "", "hero_id": h.id}


func market_count(player_idx: int) -> int:
	return Economy.count_effect(state.map, player_idx, "market", data)


func trade_quote(sell_res: String, buy_res: String, sell_amount: int) -> int:
	return Economy.trade_quote(sell_res, buy_res, sell_amount, market_count(state.current_player), data)


## Sells sell_amount of one resource for another at the current player's market rate.
func trade(sell_res: String, buy_res: String, sell_amount: int) -> Dictionary:
	if state.game_over:
		return _fail("game over")
	if market_count(state.current_player) == 0:
		return _fail("you own no market")
	if not data.resources.has(sell_res) or not data.resources.has(buy_res) or sell_res == buy_res:
		return _fail("invalid trade")
	var bank: ResourceBank = current_player()["resources"]
	if sell_amount <= 0 or bank.get_amount(sell_res) < sell_amount:
		return _fail("not enough %s" % data.resources.get(sell_res, {}).get("name", sell_res))
	var got := trade_quote(sell_res, buy_res, sell_amount)
	if got <= 0:
		return _fail("offer too small")
	bank.spend({sell_res: sell_amount})
	bank.add(buy_res, got)
	state_changed.emit()
	return {"ok": true, "reason": "", "received": got}


# ------------------------------------------------------------- alliances --

## Allies of the player (not the player), still in the game, in index order.
func living_allies(player_idx: int) -> Array[int]:
	var out: Array[int] = []
	for i in state.allies_of(player_idx):
		if i != player_idx and not state.player(i)["defeated"]:
			out.append(i)
	return out


## Why the current player cannot send this bundle ({resource: amount}) to
## to_player ("" if they can): only to a living ally, only what they have.
func can_send_resources(to_player: int, bundle: Dictionary) -> String:
	if state.game_over:
		return "the game is over"
	var me := state.current_player
	if to_player < 0 or to_player >= state.players.size() or to_player == me or not allied(me, to_player):
		return "not an ally"
	if state.player(to_player)["defeated"]:
		return "that ally is out of the game"
	var total := 0
	for res in bundle:
		if not data.resources.has(res):
			return "unknown resource %s" % res
		var n := int(bundle[res])
		if n < 0:
			return "invalid amount"
		if _bank(me).get_amount(res) < n:
			return "not enough %s" % data.resources[res]["name"]
		total += n
	if total <= 0:
		return "nothing to send"
	return ""


## Sends resources from the current player's treasury to an ally at once.
func send_resources(to_player: int, bundle: Dictionary) -> Dictionary:
	var err := can_send_resources(to_player, bundle)
	if err != "":
		return _fail(err)
	var me := state.current_player
	var sent := {}
	var parts: Array[String] = []
	for res in data.resource_order:
		var n := int(bundle.get(res, 0))
		if n <= 0:
			continue
		_bank(me).spend({res: n})
		_bank(to_player).add(res, n)
		sent[res] = n
		parts.append("%d %s" % [n, data.resources[res]["name"]])
	message.emit("%s sends %s to %s." % [state.player(me)["name"], ", ".join(parts), state.player(to_player)["name"]])
	state_changed.emit()
	return {"ok": true, "reason": "", "sent": sent}


# ------------------------------------------------------------- save/load --

func save_to_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(state.to_dict(), "\t"))
	return OK


static func load_from_file(game_data: GameData, path: String) -> GameSession:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or not GameState.validate_save(d).is_empty():
		return null
	return from_state(game_data, GameState.from_dict(d, game_data))


# ------------------------------------------------------------- cobolts --

func is_cobolt_target(target_id: String) -> bool:
	return MapCobolts.is_post(state.map.objects.get(target_id, {}), data)


func cobolt_access_error(site_id: String, hero_id: String) -> String:
	var obj: Dictionary = state.map.objects.get(site_id, {})
	if not MapCobolts.is_post(obj, data):
		return "Not a cobolt post."
	var h := hero(hero_id)
	if h == null or not h.alive or h.owner != state.current_player or state.game_over:
		return "No hero of yours is ready."
	if h.pos != AdventureMap.object_pos(obj):
		return "Visit the post with this hero."
	return MapCobolts.access_error(obj, h.owner)


func cobolt_rob_error(site_id: String, hero_id: String) -> String:
	var obj: Dictionary = state.map.objects.get(site_id, {})
	var h := hero(hero_id)
	if not MapCobolts.is_post(obj, data) or obj.get("plundered", false):
		return "This post cannot be robbed."
	if h == null or not h.alive or h.owner != state.current_player or state.game_over or h.army.is_empty():
		return "No army of yours is ready."
	if h.pos != AdventureMap.object_pos(obj):
		return "Visit the post to attempt robbery."
	return ""


func cobolt_offers(site_id: String, hero_id: String) -> Array:
	var obj: Dictionary = state.map.objects.get(site_id, {})
	if not MapCobolts.is_post(obj, data):
		return []
	var out: Array = []
	for i in (obj["stock"] as Array).size():
		var offer: Dictionary = obj["stock"][i].duplicate(true)
		offer["index"] = i
		offer["reason"] = cobolt_buy_error(site_id, hero_id, i, 1)
		out.append(offer)
	return out


func cobolt_buy_error(site_id: String, hero_id: String, offer_index: int, quantity: int = 1) -> String:
	var why := cobolt_access_error(site_id, hero_id)
	if why != "":
		return why
	var stock: Array = state.map.objects[site_id]["stock"]
	if offer_index < 0 or offer_index >= stock.size():
		return "Unknown offer."
	var offer: Dictionary = stock[offer_index]
	if quantity <= 0 or quantity > int(offer["remaining"]):
		return "Not enough stock."
	var h := hero(hero_id)
	var cost: Dictionary = {}
	match String(offer["kind"]):
		"recruit":
			var cid := String(offer["creature"])
			if tier_cap() > 0 and int(data.creature(cid)["tier"]) > tier_cap():
				return "Beyond this chapter's ranks."
			if not _has_room(h.army, cid):
				return "No free army slot."
			cost = Town.recruit_cost(cid, quantity, data)
		"artifact":
			if quantity != 1:
				return "Only one artefact is offered."
			var slot := String(data.artifacts[offer["artifact"]]["slot"])
			if String(h.equipment.get(slot, "")) != "" and h.pack.size() >= int(data.artifact_rules["pack_size"]):
				return "Hero's pack is full."
			cost = {"gold": int(offer["price"])}
		"exchange":
			cost = {String(offer["sell"]): int(offer["input"]) * quantity}
		_:
			return "Unknown offer."
	if not _bank(h.owner).can_afford(cost):
		return "Not enough resources."
	return ""


func cobolt_buy(site_id: String, hero_id: String, offer_index: int, quantity: int = 1) -> Dictionary:
	var why := cobolt_buy_error(site_id, hero_id, offer_index, quantity)
	if why != "":
		return _fail(why)
	var h := hero(hero_id)
	var offer: Dictionary = state.map.objects[site_id]["stock"][offer_index]
	match String(offer["kind"]):
		"recruit":
			_bank(h.owner).spend(Town.recruit_cost(offer["creature"], quantity, data))
			h.army.add(offer["creature"], quantity)
		"artifact":
			if not h.give_artifact(offer["artifact"], data):
				return _fail("Hero's pack is full.")
			_bank(h.owner).spend({"gold": int(offer["price"])})
			h.movement_left = mini(h.movement_left, h.max_movement(data))
			_reveal_around(h)
		"exchange":
			_bank(h.owner).spend({String(offer["sell"]): int(offer["input"]) * quantity})
			_bank(h.owner).add(offer["buy"], int(offer["output"]) * quantity)
	offer["remaining"] = int(offer["remaining"]) - quantity
	message.emit("%s trades at the %s." % [h.name, MapSites.site_name(state.map.objects[site_id], data)])
	state_changed.emit()
	return {"ok": true, "reason": ""}


func _plunder_cobolt(h: Hero, obj: Dictionary, result: Dictionary) -> void:
	var gold := int(obj.get("loot_gold", 0))
	_bank(h.owner).add("gold", gold)
	obj["loot_gold"] = 0
	obj["plundered"] = true
	result["summary"].append("Plunder: +%d gold. This post can never trade again." % gold)
	for offer in obj["stock"]:
		if offer["kind"] == "artifact" and int(offer["remaining"]) > 0:
			var aid := String(offer["artifact"])
			if not h.give_artifact(aid, data):
				# Keep loot claimable when the pack is full; never silently destroy it.
				var p := _free_tile_near(AdventureMap.object_pos(obj))
				if state.map.object_at(p).is_empty():
					state.map.add_object({"id": String(obj["id"]) + "_loot", "type": "artifact", "artifact": aid, "pos": [p.x, p.y]})
				else:
					obj["unclaimed_artifact"] = aid
					obj["loot_owner"] = h.owner
			result["summary"].append("Recovered %s." % data.artifacts[aid]["name"])
			offer["remaining"] = 0
		else:
			offer["remaining"] = 0


func cobolt_claim_loot(site_id: String, hero_id: String) -> Dictionary:
	var obj: Dictionary = state.map.objects.get(site_id, {})
	var h := hero(hero_id)
	if not MapCobolts.is_post(obj, data) or not obj.has("unclaimed_artifact"):
		return _fail("No unclaimed loot.")
	if h == null or not h.alive or h.owner != state.current_player or state.game_over or h.pos != AdventureMap.object_pos(obj) or h.owner != int(obj.get("loot_owner", -1)):
		return _fail("The victorious player's hero must visit the post.")
	if not h.give_artifact(String(obj["unclaimed_artifact"]), data):
		return _fail("Hero's pack is full.")
	obj.erase("unclaimed_artifact")
	obj.erase("loot_owner")
	h.movement_left = mini(h.movement_left, h.max_movement(data))
	_reveal_around(h)
	state_changed.emit()
	return {"ok": true, "reason": ""}
