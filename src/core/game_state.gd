class_name GameState
extends RefCounted
## The complete, serializable state of one game. Contains no rules; those live
## in GameSession and the subsystem classes. Saves are versioned JSON.

## 2: towns and mines (map objects with owners, buildings, recruitment pools).
## 3: heroes carry persistent "marks"; maps hold "encounter" objects.
## 4: saves of generated maps ("gen:" ids) carry their terrain and roads under
##    "map", so a later generator change cannot alter a saved game. v3 saves
##    of generated maps regenerate the terrain from the id.
## 5: game flow: winner, end_reason, per-player town-loss timer and elimination day.
## 6: heroes carry equipment, a pack and a campaign level cap; maps hold
##    "artifact" objects.
## 7: a campaign chapter carries its campaign record ("campaign": Campaign
##    progress without the game in progress), so a chapter saved to any slot
##    still advances the campaign when it is won. Older saves have none.
## 8: "rules": per-game rule overrides (a campaign chapter's max_tier and
##    computer-player settings, see GameSession.new_game). Older saves have none.
## 9: players carry a "difficulty" (data/ai_difficulty.json level). Older saves
##    play at the default level.
## 10: random events and rare map buildings: "omen" (this week's event, see
##    WorldEvents), players carry "news" (event lines not yet shown), heroes
##    carry "boons", maps may hold "site" objects. Older saves have no omen,
##    no news and no boons.
## 11: players carry a "team" (0 = no team; players sharing a team > 0 are
##    allies). Older saves have no alliances.
## 12: players carry "scouted" (target id -> day of today's scouting reports,
##    see GameSession.scout). Older saves have none.
## 13: heroes carry standing battle orders (older saves use defaults).
## 14: heroes carry mana, home town, and known spells.
## 15: each player remembers enemy heroes already sighted.
## Older saves migrate step by step in from_dict().
## 16: trader sites carry finite artifact and map stock. Older saves keep their
## existing map objects; traders are never retroactively spawned or restocked.
## 17: scenario progress, wave schedule, orders, quest inventory and support state.
## 18: creature stacks carry veteran XP; old improved forms start at level 3.
## 19: the saved "map" may carry "decor": "painted" and decorations a "variant"
##    (TerrainPainter). Older saves have neither and keep the view's own scenery.
## 20: scenario_runtime may hold "betrayal" {day} once a scripted betrayal
##     fired (ScenarioBetrayal); map "site" objects may be villages with a
##     one-off "stock". Older saves have neither, so nothing migrates.
## 21: the saved "map" may carry "scenery" (map scenery pieces and landmarks)
##     and "surface" (ground-variant patches), see TerrainPainter. Older saves
##     have neither; their landmark-free terrain needs nothing.
## 22: heroes' standing battle orders also carry "formation", "art" (when the
##     battle art is loosed) and "retreat" (BattleOrders). Older saves have only
##     stance and focus; the rest read as the defaults (battle line, at once,
##     fight to the last), which play exactly as before.
## 23: cobolt posts carry stock, local hostility, fixed loot and plundered state.
## Older saves have no cobolt posts; none are inserted on load.
const SAVE_VERSION := 23

var map: AdventureMap
var day: int = 1
var current_player: int = 0
var players: Array = []        # [{id, name, faction, color, is_human, difficulty, team, resources: ResourceBank, fog: FogOfWar,
                               #   defeated, days_without_town, eliminated_day, news: [String], scouted}]; difficulty: a data/ai_difficulty.json level;
                               #   team: 0 = alone, players sharing a team > 0 are allies (see allied())
var heroes: Dictionary = {}    # id -> Hero
var rng: GameRng = GameRng.new(1)
var game_seed: int = 1
var battles_fought: int = 0
var game_over: bool = false
var winner: int = -1           # player index once the game is won, else -1 (see VictoryRules)
var end_reason: String = ""    # "", "conquest", "domination" or "defeat"
## The campaign this game is a chapter of (Campaign.record()), or {} for a skirmish.
var campaign: Dictionary = {}
## Rule overrides for this game, {} for the standard rules:
##   max_tier: int, the highest creature tier any town may build or recruit (0 = all);
##   ai: {StrategicAI setting: value}, applied to every computer player.
var rules: Dictionary = {}
## This week's random event (WorldEvents): {id, week, tier?, resource?, amount?}, or {}.
var omen: Dictionary = {}
## Objective id -> completed visit; ordinary games have no scenario progress.
var scenario_progress: Dictionary = {}
var scenario_runtime: Dictionary = {}


## Select the closest town held at the start, with an id tie-breaker.
static func initial_home(map: AdventureMap, h: Hero) -> String:
	var best := ""
	var distance := 2147483647
	for t in Economy.towns_of(map, h.owner):
		var delta := AdventureMap.object_pos(t) - h.pos
		var d := absi(delta.x) + absi(delta.y)
		var id := String(t["id"])
		if d < distance or (d == distance and (best == "" or id < best)):
			distance = d
			best = id
	return best


func week() -> int:
	return (day - 1) / 7 + 1


func day_of_week() -> int:
	return (day - 1) % 7 + 1


func player(idx: int) -> Dictionary:
	return players[idx]


## A player's team: 0 means the player has no allies.
func team_of(player_idx: int) -> int:
	if player_idx < 0 or player_idx >= players.size():
		return 0
	return int(players[player_idx].get("team", 0))


## True if the two players are the same player or share a team. Allies do not
## fight: their heroes, towns and mines are off limits to each other, they see
## what the other's heroes see and they can send each other resources.
## Neutral (owner -1) is nobody's ally.
func allied(a: int, b: int) -> bool:
	if a < 0 or b < 0:
		return false
	if a == b:
		return true
	var t := team_of(a)
	return t > 0 and t == team_of(b)


## The players allied with player_idx, the player included, in index order.
func allies_of(player_idx: int) -> Array[int]:
	var out: Array[int] = []
	for i in players.size():
		if allied(player_idx, i):
			out.append(i)
	return out


func heroes_of(player_idx: int) -> Array:
	var out := []
	for id in heroes:
		var h: Hero = heroes[id]
		if h.owner == player_idx and h.alive:
			out.append(h)
	return out


func hero_at(p: Vector2i) -> Hero:
	for id in heroes:
		var h: Hero = heroes[id]
		if h.alive and h.pos == p:
			return h
	return null


func to_dict() -> Dictionary:
	var ps := []
	for p in players:
		ps.append({"id": p["id"], "name": p["name"], "faction": p["faction"], "color": p["color"],
			"is_human": p["is_human"], "difficulty": String(p.get("difficulty", "normal")), "team": int(p.get("team", 0)), "defeated": p.get("defeated", false),
			"days_without_town": int(p.get("days_without_town", 0)), "eliminated_day": int(p.get("eliminated_day", 0)),
			"scouted": (p.get("scouted", {}) as Dictionary).duplicate(),
			"known_enemy_heroes": (p.get("known_enemy_heroes", {}) as Dictionary).duplicate(),
			"resources": p["resources"].to_dict(), "fog": p["fog"].to_dict(),
			"news": (p.get("news", []) as Array).duplicate()})
	var hs := {}
	for id in heroes:
		hs[id] = heroes[id].to_dict()
	var out := {
		"version": SAVE_VERSION,
		"map_id": map.map_id,
		"day": day,
		"current_player": current_player,
		"seed": game_seed,
		"rng_state": rng.state,
		"battles_fought": battles_fought,
		"game_over": game_over,
		"winner": winner,
		"end_reason": end_reason,
		"players": ps,
		"heroes": hs,
		"objects": map.objects.duplicate(true),
		"campaign": campaign.duplicate(true),
		"rules": rules.duplicate(true),
		"omen": omen.duplicate(true),
		"scenario_progress": scenario_progress.duplicate(true),
		"scenario_runtime": scenario_runtime.duplicate(true),
	}
	out["map"] = map.static_definition()
	return out


## Rebuilds a state from a save dictionary. The static terrain comes from the
## map definition; mutable objects come from the save.
static func from_dict(d: Dictionary, data: GameData) -> GameState:
	var errors := validate_save(d)
	assert(errors.is_empty(), "invalid save: %s" % ", ".join(errors))
	var s := GameState.new()
	# New saves carry their terrain. Older authored-map saves need their original
	# layout when a chapter has since been redrawn.
	var def: Dictionary
	var legacy_path := GameData.DATA_DIR + "/legacy_maps/" + String(d["map_id"]) + ".json"
	if d.has("map"):
		def = d["map"].duplicate(true)
	elif FileAccess.file_exists(legacy_path):
		def = GameData.read_json(legacy_path)
	else:
		def = data.load_map(d["map_id"])
	var def_objects: Array = def.get("objects", [])
	# Snapshots contain terrain only. Legacy migrations still need the original
	# map's objects to restore types that did not exist in earlier save formats.
	if int(d["version"]) < 6 and d.has("map") and def_objects.is_empty():
		def_objects = data.load_map(d["map_id"]).get("objects", [])
	def["objects"] = []
	s.map = AdventureMap.from_definition(def, data)
	for id in d["objects"]:
		s.map.add_object(d["objects"][id])
	var version := int(d["version"])
	if version < 2:
		# v1 -> v2: version 1 predates towns and mines: take them from the map definition.
		for o in def_objects:
			if o["type"] in ["town", "mine"] and not s.map.objects.has(o["id"]):
				s.map.add_object(o.duplicate(true))
	if version < 3:
		# v2 -> v3: encounters come from the map definition unless their tile is
		# already taken (by an object or a hero). Missing hero marks default to
		# none in Hero.from_dict.
		var hero_tiles := {}
		for id in d["heroes"]:
			hero_tiles[Vector2i(int(d["heroes"][id]["pos"][0]), int(d["heroes"][id]["pos"][1]))] = true
		for o in def_objects:
			var p := AdventureMap.object_pos(o)
			if o["type"] == "encounter" and not s.map.objects.has(o["id"]) and s.map.object_at(p).is_empty() and not hero_tiles.has(p):
				s.map.add_object(o.duplicate(true))
	if version < 6:
		# v5 -> v6: artifact pickups come from the map definition on free tiles.
		# Heroes without equipment fields start empty-handed (Hero.from_dict).
		var taken := {}
		for id in d["heroes"]:
			taken[Vector2i(int(d["heroes"][id]["pos"][0]), int(d["heroes"][id]["pos"][1]))] = true
		for o in def_objects:
			var p := AdventureMap.object_pos(o)
			if o["type"] == "artifact" and not s.map.objects.has(o["id"]) and s.map.object_at(p).is_empty() and not taken.has(p):
				s.map.add_object(o.duplicate(true))
	s.day = int(d["day"])
	s.current_player = int(d["current_player"])
	s.game_seed = int(d["seed"])
	s.rng = GameRng.new(1)
	s.rng.state = int(d["rng_state"])
	s.battles_fought = int(d["battles_fought"])
	s.game_over = bool(d.get("game_over", false))
	# v4 -> v5: no winner was recorded and town-loss timers start at zero.
	s.winner = int(d.get("winner", -1))
	s.end_reason = String(d.get("end_reason", "defeat" if s.game_over else ""))
	# v8 -> v9: computer players of older saves play at the default difficulty.
	# v10 -> v11: players of older saves have no team.
	# v11 -> v12: older saves carry no scouting reports.
	for p in d["players"]:
		var scouted := {}
		var sc: Variant = p.get("scouted", {})
		if typeof(sc) == TYPE_DICTIONARY:
			for k in sc:
				scouted[String(k)] = int(sc[k])
		s.players.append({"id": int(p["id"]), "name": p["name"], "faction": p["faction"], "color": p["color"],
			"is_human": bool(p["is_human"]), "difficulty": String(p.get("difficulty", data.default_difficulty())),
			"team": maxi(0, int(p.get("team", 0))),
			"defeated": bool(p.get("defeated", false)),
			"days_without_town": int(p.get("days_without_town", 0)), "eliminated_day": int(p.get("eliminated_day", 0)), "scouted": scouted,
			"known_enemy_heroes": (p.get("known_enemy_heroes", {}) as Dictionary).duplicate(),
			"resources": ResourceBank.from_dict(p["resources"]), "fog": FogOfWar.from_dict(p["fog"]),
			"news": (p.get("news", []) as Array).map(func(n): return String(n))})
	for id in d["heroes"]:
		s.heroes[id] = Hero.from_dict(d["heroes"][id])
		s.heroes[id].army.initialize_veterans(data)
		if version < 14:
			s.heroes[id].mana = s.heroes[id].max_mana(data)
		if version < 14:
			s.heroes[id].home_town = initial_home(s.map, s.heroes[id])
	for obj in s.map.objects.values():
		if obj.get("type", "") == "town" and obj.has("garrison"):
			Town.normalize(obj, data)
			var garrison := Town.garrison(obj)
			garrison.initialize_veterans(data)
			Town.set_garrison(obj, garrison)
	# v6 -> v7: older saves belong to no campaign.
	var camp: Variant = d.get("campaign", {})
	s.campaign = camp.duplicate(true) if typeof(camp) == TYPE_DICTIONARY else {}
	# v7 -> v8: older saves play by the standard rules.
	var rules_in: Variant = d.get("rules", {})
	s.rules = rules_in.duplicate(true) if typeof(rules_in) == TYPE_DICTIONARY else {}
	# v9 -> v10: no omen yet (the next week rolls one), no news, no boons.
	var omen_in: Variant = d.get("omen", {})
	s.omen = omen_in.duplicate(true) if typeof(omen_in) == TYPE_DICTIONARY else {}
	if s.omen.has("week"):
		s.omen["week"] = int(s.omen["week"])
	# v16 -> v17: ordinary older games have no scenario progress.
	var progress: Variant = d.get("scenario_progress", {})
	s.scenario_progress = progress.duplicate(true) if typeof(progress) == TYPE_DICTIONARY else {}
	var runtime: Variant = d.get("scenario_runtime", {})
	s.scenario_runtime = runtime.duplicate(true) if typeof(runtime) == TYPE_DICTIONARY else {}
	return s


static func validate_save(d: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["version", "map_id", "day", "current_player", "seed", "rng_state", "players", "heroes", "objects"]:
		if not d.has(key):
			errors.append("missing '%s'" % key)
	if errors.is_empty():
		if int(d["version"]) > SAVE_VERSION:
			errors.append("save version %d is newer than supported %d" % [int(d["version"]), SAVE_VERSION])
		if int(d["day"]) < 1:
			errors.append("day must be >= 1")
		if int(d["current_player"]) < 0 or int(d["current_player"]) >= d["players"].size():
			errors.append("current_player out of range")
	errors.append_array(WaveDirector.validate_runtime(d.get("scenario_runtime", {})))
	var saved_rules: Variant = d.get("rules", {})
	if typeof(saved_rules) == TYPE_DICTIONARY:
		for err in ScenarioRules.validate(saved_rules.get("scenario", {})):
			errors.append("scenario: " + err)
	var progress: Variant = d.get("scenario_progress", {})
	if typeof(progress) != TYPE_DICTIONARY:
		errors.append("scenario_progress must be a dictionary")
	else:
		for id in progress:
			if typeof(id) != TYPE_STRING or typeof(progress[id]) != TYPE_BOOL:
				errors.append("scenario_progress must map objective ids to booleans")
	return errors
