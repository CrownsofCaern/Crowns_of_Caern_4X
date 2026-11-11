class_name FactionMechanics
extends RefCounted
## One adventure-map mechanic per playable faction (data/faction_mechanics.json).
## Headless rules; GameSession calls the hooks at the right moments:
##   on_day_start   before movement is refilled (Tidebound)
##   on_day_vision  after the new day began (Whisper Web)
##   on_week_growth after the weekly growth (Levy of the Shires)
##   on_capture     a mine or town changed hands (Brand and Plunder)
##   after_victory  a hero won a battle (Grave Harvest, Feast of Victory)
##   deep_road_*    the Sunken Forge's travel command (Deep Roads)
## Wildwalk is plain hero mods, folded in by Hero.modifiers().
## Nothing here is saved: boons used as markers live on the hero (Hero.boons).

const MECHANICS := ["militia_levy", "plunder", "grave_harvest", "wildwalk", "deep_roads", "feast_of_victory",
	"whisper_web", "tidebound"]
const TIDE_SOURCE := "tidebound"
const FEAST_SOURCE := "feast_of_victory"
## Creatures with these tags never rise for the Grave Harvest (they were never alive).
const UNLIVING_TAGS := ["undead", "construct", "spirit"]


## The mechanic definition of a faction ({} if none).
static func of_faction(faction: String, data: GameData) -> Dictionary:
	return data.faction_mechanics.get(faction, {})


## The mechanic id of a faction ("" if none).
static func mechanic(faction: String, data: GameData) -> String:
	return String(of_faction(faction, data).get("mechanic", ""))


static func player_has(state: GameState, player_idx: int, mech: String, data: GameData) -> bool:
	if player_idx < 0 or player_idx >= state.players.size():
		return false
	return mechanic(String(state.player(player_idx).get("faction", "")), data) == mech


static func hero_has(h: Hero, mech: String, data: GameData) -> bool:
	return h != null and mechanic(h.faction, data) == mech


## Hero mods from the hero's faction mechanic (Wildwalk), for Hero.modifiers().
static func hero_mods(faction: String, data: GameData) -> Dictionary:
	var def := of_faction(faction, data)
	if String(def.get("mechanic", "")) != "wildwalk":
		return {}
	return def.get("mods", {})


## One line for menus and tooltips: "Name: text".
static func describe(faction: String, data: GameData) -> String:
	var def := of_faction(faction, data)
	if def.is_empty():
		return ""
	return "%s: %s" % [def["name"], def["text"]]


# ------------------------------------------------------------------- days --

## Tidebound: heroes that start the day by the water get a one-day movement
## boon. Call after boons expired and before movement is refilled.
static func on_day_start(state: GameState, data: GameData, heroes_sorted: Array) -> void:
	for h in heroes_sorted:
		if not h.alive or not hero_has(h, "tidebound", data):
			continue
		if by_the_water(state.map, h.pos):
			var def := of_faction(h.faction, data)
			h.add_boon(TIDE_SOURCE, String(def["name"]), state.day, {"movement_pct": float(def["pct"])})


## True on swamp or a river ford, or next to deep water or a ford.
static func by_the_water(map: AdventureMap, p: Vector2i) -> bool:
	if map.terrain_at(p) in ["swamp", "river"]:
		return true
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := p + Vector2i(dx, dy)
			if q != p and map.in_bounds(q) and map.terrain_at(q) in ["water", "river"]:
				return true
	return false


## Whisper Web: the player's mines and sites watch around them; on the first
## day of a week the land around every enemy hero is revealed too. Returns the
## number of newly seen tiles per player index.
static func on_day_vision(state: GameState, data: GameData, allied: Callable) -> Dictionary:
	var out := {}
	for i in state.players.size():
		var p := state.player(i)
		if p["defeated"] or not player_has(state, i, "whisper_web", data):
			continue
		var def := of_faction(String(p["faction"]), data)
		var fog: FogOfWar = p["fog"]
		var n := 0
		for o in _sorted_objects(state.map):
			if o["type"] in ["mine", "site"] and int(o.get("owner", -1)) == i:
				n += fog.reveal(AdventureMap.object_pos(o), int(def["mine_radius"]))
		if state.day_of_week() == 1:
			var ids := state.heroes.keys()
			ids.sort()
			for id in ids:
				var h: Hero = state.heroes[id]
				if h.alive and h.owner >= 0 and not allied.call(i, h.owner):
					n += fog.reveal(h.pos, int(def["hero_radius"]))
		out[i] = n
	return out


## Levy of the Shires: extra tier-1 recruits in every town of a player per mine
## held. Call once a week, after the regular growth. Returns {town id: added}.
static func on_week_growth(state: GameState, data: GameData) -> Dictionary:
	var out := {}
	for i in state.players.size():
		var p := state.player(i)
		if p["defeated"] or not player_has(state, i, "militia_levy", data):
			continue
		var def := of_faction(String(p["faction"]), data)
		var n := mini(int(def["max_per_town"]), int(def["per_mine"]) * Economy.mines_of(state.map, i).size())
		if n <= 0:
			continue
		for t in Economy.towns_of(state.map, i):
			var c := levy_creature(t, data)
			if c == "":
				continue
			var avail: Dictionary = t.get("available", {})
			avail[c] = int(avail.get(c, 0)) + n
			t["available"] = avail
			out[String(t["id"])] = n
	return out


## The town's tier-1 dwelling creature ("" if it has none).
static func levy_creature(t: Dictionary, data: GameData) -> String:
	for c in Town.dwellings(t, data):
		if int(data.creature(c).get("tier", 0)) == 1:
			return String(c)
	return ""


## Expected levy for a player holding one more mine (for the AI): recruits per town.
static func levy_per_mine(faction: String, data: GameData) -> int:
	var def := of_faction(faction, data)
	return int(def.get("per_mine", 0)) if String(def.get("mechanic", "")) == "militia_levy" else 0


# ---------------------------------------------------------------- capture --

## Brand and Plunder: the spoils of a capture as a resource bundle (empty if
## the capturing player has no plunder, or nothing was taken from anyone).
static func plunder(obj: Dictionary, previous_owner: int, player_idx: int, state: GameState, data: GameData) -> Dictionary:
	if previous_owner == player_idx or not player_has(state, player_idx, "plunder", data):
		return {}
	var def := of_faction(String(state.player(player_idx)["faction"]), data)
	var out := {}
	match String(obj.get("type", "")):
		"mine":
			var n := Economy.mine_income(obj, data) * int(def["mine_days"])
			if n > 0:
				out[String(obj["resource"])] = n
		"town":
			if previous_owner < 0:
				return {}
			var inc := Town.daily_income(obj, data)
			for res in data.resource_order:
				if int(inc.get(res, 0)) > 0:
					out[res] = int(inc[res]) * int(def["town_days"])
	return out


# ---------------------------------------------------------------- battles --

## After a won battle. Applies the Grave Harvest and the Feast of Victory and
## returns summary lines. enemy_stacks: the defender side's result stacks
## ({creature, lost, ...}).
static func after_victory(h: Hero, enemy_stacks: Array, state: GameState, data: GameData) -> Array:
	var lines := []
	if hero_has(h, "grave_harvest", data):
		var raised := harvest_count(enemy_stacks, h.faction, data)
		if raised > 0:
			var cid := String(of_faction(h.faction, data)["creature"])
			if h.army.add(cid, raised):
				lines.append("Grave Harvest: %d %s rise from the slain." % [raised, data.creature(cid)["name"]])
			else:
				lines.append("Grave Harvest: no room in the army for the %d risen." % raised)
	if hero_has(h, "feast_of_victory", data) and not h.has_boon(FEAST_SOURCE):
		var def := of_faction(h.faction, data)
		var before := h.movement_left
		h.movement_left = mini(h.max_movement(data), h.movement_left + int(round(h.max_movement(data) * float(def["pct"]))))
		h.add_boon(FEAST_SOURCE, String(def["name"]), state.day, {})
		if h.movement_left > before:
			lines.append("%s: +%d movement today." % [def["name"], h.movement_left - before])
	return lines


## Shamblers raised from these slain enemies.
static func harvest_count(enemy_stacks: Array, faction: String, data: GameData) -> int:
	var def := of_faction(faction, data)
	if String(def.get("mechanic", "")) != "grave_harvest":
		return 0
	var hp := 0.0
	for st in enemy_stacks:
		var c := data.creature(String(st.get("creature", "")))
		if c.is_empty() or not living(c):
			continue
		hp += float(int(st.get("lost", 0))) * float(c.get("hp", 0))
	var raised_hp := float(data.creature(String(def["creature"])).get("hp", 1))
	return int(floor(hp * float(def["pct"]) / maxf(1.0, raised_hp)))


static func living(c: Dictionary) -> bool:
	for t in c.get("tags", []):
		if UNLIVING_TAGS.has(t):
			return false
	for a in c.get("abilities", []):
		if String(a.get("id", "") if a is Dictionary else a) == "mindless":
			return false
	return true


# ------------------------------------------------------------- deep roads --

## The player's holdings a Forgeborn hero can travel between: mines and towns,
## sorted by id.
static func deep_road_nodes(state: GameState, player_idx: int) -> Array:
	var out := []
	for o in _sorted_objects(state.map):
		if o["type"] in ["mine", "town"] and int(o.get("owner", -1)) == player_idx:
			out.append(o)
	return out


## The holding the hero can enter the deep roads from ({} if none): a town it
## stands in, or a mine it stands on or next to.
static func deep_road_origin(state: GameState, h: Hero) -> Dictionary:
	for o in deep_road_nodes(state, h.owner):
		var p := AdventureMap.object_pos(o)
		var d := p - h.pos
		if p == h.pos or (o["type"] == "mine" and maxi(absi(d.x), absi(d.y)) <= 1):
			return o
	return {}


## Why the hero cannot take the deep road to destination_id ("" if it can).
static func deep_road_error(state: GameState, data: GameData, h: Hero, destination_id: String) -> String:
	if not hero_has(h, "deep_roads", data):
		return "only Forgeborn heroes know the deep roads"
	var origin := deep_road_origin(state, h)
	if origin.is_empty():
		return "must stand in one of your towns or by one of your mines"
	var dest: Dictionary = state.map.objects.get(destination_id, {})
	if dest.is_empty() or not dest["type"] in ["mine", "town"] or int(dest.get("owner", -1)) != h.owner:
		return "destination is not one of your mines or towns"
	if dest["id"] == origin["id"]:
		return "already there"
	var def := of_faction(h.faction, data)
	if h.movement_left < int(ceil(h.max_movement(data) * float(def["min_movement_pct"]))):
		return "needs half a day's movement"
	if arrival_tile(state, dest) == Vector2i(-1, -1):
		return "no free ground at the destination"
	return ""


## Where a hero comes up at a destination: on it, or the first free passable
## tile next to it (row by row), or (-1, -1).
static func arrival_tile(state: GameState, dest: Dictionary) -> Vector2i:
	var p := AdventureMap.object_pos(dest)
	if state.hero_at(p) == null:
		return p
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := p + Vector2i(dx, dy)
			if q == p or not state.map.in_bounds(q) or not state.map.is_passable(q):
				continue
			if state.hero_at(q) == null and state.map.object_at(q).is_empty():
				return q
	return Vector2i(-1, -1)


# --------------------------------------------------------------- helpers --

static func _sorted_objects(map: AdventureMap) -> Array:
	var ids := map.objects.keys()
	ids.sort()
	var out := []
	for id in ids:
		out.append(map.objects[id])
	return out


# ------------------------------------------------------------- validation --

static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = []
	if data.faction_mechanics.is_empty():
		return errors
	for fid in data.town_types:
		if not data.faction_mechanics.has(fid):
			errors.append("faction %s has no map mechanic" % fid)
	var used := {}
	for fid in data.faction_mechanics:
		var d: Dictionary = data.faction_mechanics[fid]
		var where := "faction mechanic %s" % fid
		if not data.factions.has(fid):
			errors.append("%s: unknown faction" % where)
		for key in ["mechanic", "name", "text"]:
			if String(d.get(key, "")) == "":
				errors.append("%s missing %s" % [where, key])
		var m := String(d.get("mechanic", ""))
		if not MECHANICS.has(m):
			errors.append("%s has unknown mechanic %s" % [where, m])
			continue
		if used.has(m):
			errors.append("%s repeats mechanic %s of %s" % [where, m, used[m]])
		used[m] = fid
		var pos := func(key: String) -> void:
			if float(d.get(key, 0)) <= 0.0:
				errors.append("%s needs a positive %s" % [where, key])
		match m:
			"militia_levy":
				pos.call("per_mine")
				pos.call("max_per_town")
			"plunder":
				pos.call("mine_days")
				pos.call("town_days")
			"grave_harvest":
				pos.call("pct")
				if float(d.get("pct", 0)) > 0.5:
					errors.append("%s pct must be at most 0.5" % where)
				var c := data.creature(String(d.get("creature", "")))
				if c.is_empty() or String(c.get("faction", "")) != fid:
					errors.append("%s raises an unknown creature or one of another faction" % where)
			"wildwalk":
				if (d.get("mods", {}) as Dictionary).is_empty():
					errors.append("%s grants no mods" % where)
				errors.append_array(HeroModifiers.validate(d.get("mods", {}), where, data))
			"deep_roads":
				pos.call("min_movement_pct")
				if float(d.get("min_movement_pct", 0)) > 1.0:
					errors.append("%s min_movement_pct must be at most 1" % where)
			"feast_of_victory", "tidebound":
				pos.call("pct")
				if float(d.get("pct", 0)) > 1.0:
					errors.append("%s pct must be at most 1" % where)
			"whisper_web":
				pos.call("mine_radius")
				pos.call("hero_radius")
	return errors
