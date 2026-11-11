class_name GameSetup
extends RefCounted
## New-game configuration, headless: which maps exist, which player slots a map
## has, and how a chosen configuration (human / computer / closed per slot,
## faction per slot) turns a map definition into the one the game starts from.
##
## A setup dictionary: {"players": [{"type": "human"|"computer"|"closed",
## "faction": faction_id, "hero_class": optional starting hero class from that faction,
## "name": optional, "difficulty": optional level of a
## computer player (data/ai_difficulty.json), "team": optional int, 0 = no team,
## 1..MAX_TEAMS = allied with every player of the same team}], one entry per map player slot}.
## Missing entries keep the map's own slot settings. "standard_start": true (set
## by the new-game menu) gives every player its faction's number of starting
## heroes, see GameSession._standard_start_heroes().

const GENERATED_PREFIX := "gen:"
const MAX_TEAMS := 4
const PLAYER_COLORS := ["#c94040", "#4488d0", "#49a85a", "#d9b33f", "#a267c4", "#db873c", "#44b6b4", "#db79a8"]
const COLOR_NAMES := ["Red", "Blue", "Green", "Gold", "Purple", "Orange", "Teal", "Pink"]


## Factions a player can lead: those with a town type.
static func playable_factions(data: GameData) -> Array:
	var out := []
	var ids := data.factions.keys()
	ids.sort()
	for f in ids:
		if data.town_types.has(f) and not bool(data.factions[f].get("neutral", false)):
			out.append(f)
	return out


static func classes_for_faction(data: GameData, faction: String) -> Array:
	var out := []
	for id in data.hero_classes:
		if String(data.hero_classes[id]["faction"]) == faction:
			out.append(id)
	out.sort()
	return out


## Game modes of the new-game screen, in menu order. Every mode but conquest
## is a generated scenario (ScenarioGenerator.MODES).
const MODES := ["conquest", "townless", "survival", "defence", "endless", "labyrinth"]
const MODE_NAMES := {"conquest": "Conquest", "townless": "Townless start", "survival": "Survival",
	"defence": "Three strongholds", "endless": "Endless survival", "labyrinth": "Expedition"}
const MODE_TEXT := {
	"conquest": "Last player or team standing wins. A player who loses every town has a few days to take one back.",
	"townless": "You begin with a lone hero and no town. Win over the guarded villages nearby, raise their folk and take the neutral town before your rivals grow strong.",
	"survival": "Hold your stronghold through the appointed weeks while invasion hosts march on it. A neighbour may join you if you win its trust.",
	"defence": "Keep three strongholds standing against the invasions. Losing any one of them loses the mission.",
	"endless": "The invasions never stop and every wave comes back stronger. Hold out as long as you can.",
	"labyrinth": "A lone expedition into a walled maze. Find the way to its heart before the deadline runs out."}
## Scenario modes on a random template take 2-4 player zones.
const SCENARIO_MAX_PLAYERS := 4
const RANDOM_ID := GENERATED_PREFIX + "random"
const CURATED_PREFIX := "curated:"


## The maps the new-game menu offers for a mode ("all" = every mode, in MODES
## order). Conquest: the random map, the curated seeds of random_maps.curated
## and the player's own editor maps. A scenario mode: its random entry and its
## curated seeds. Story and campaign maps (data/maps), the hand-written
## generator templates and legacy recipes are not listed, but their ids stay
## loadable (map_entry builds an entry for any map id).
## [{id, name, slots: [{faction, is_human, name, difficulty, team}], generated, template, mode, random?, curated?, recipe?}]
static func available_maps(data: GameData, mode: String = "conquest") -> Array:
	var out := []
	if mode == "all":
		for m in MODES:
			out.append_array(available_maps(data, m))
		return out
	var random := random_entry(data, default_random_options(data, mode))
	if not random.is_empty():
		out.append(random)
	out.append_array(curated_entries(data, mode))
	if mode == "conquest":
		for definition in MapRepository.new(data).playable_maps():
			out.append({"id": definition["id"], "name": definition.get("name", definition["id"]),
				"slots": _slots_from(definition["players"]), "generated": false, "custom": true,
				"template": "", "scenario": false, "mode": "conquest",
				"layout_family": "custom", "size": "%dx%d" % [int(definition["width"]), int(definition["height"])]})
	return out


## A new-game entry for any loadable map id (hand-made, "gen:...",
## "scenario:..." or "custom:..."); {} if the map does not load. Story maps are
## not listed in the menu, but tools and tests still start them this way. For
## a generated id, map_id_for(entry, seed) gives the same id with that seed.
static func map_entry(data: GameData, map_id: String) -> Dictionary:
	var def := data.load_map(map_id)
	if def.is_empty() or not def.has("players"):
		return {}
	var sc: Dictionary = def.get("scenario", {})
	var entry := {"id": map_id, "name": def.get("name", map_id), "slots": _slots_from(def["players"]), "generated": false,
		"template": "", "scenario": def.has("scenario"), "mode": sc.get("mode", "conquest"),
		"invasion_strength": sc.get("wave_strength", {}), "custom": map_id.begins_with("custom:"),
		"size": "%dx%d" % [int(def["width"]), int(def["height"])]}
	# Generated ids keep their template (and recipe), so map_id_for(entry, seed) varies only the seed.
	if ScenarioGenerator.is_generated_id(map_id):
		var parsed := ScenarioGenerator.parse_id(map_id)
		entry.merge({"generated": true, "recipe": parsed["recipe"], "template": parsed["template"]}, true)
	elif MapGenerator.is_generated_id(map_id):
		var parsed := MapGenerator.parse_id(map_id)
		entry.merge({"generated": true, "template": parsed["template"], "factions": parsed["factions"]}, true)
	return entry


## Team counts the teams picker offers for a player count: 0 (no teams), 2
## for an even count of four or more, 3 for six players.
static func team_choices(players: int) -> Array:
	var out := [0]
	if players >= 4 and players % 2 == 0:
		out.append(2)
	if players == 6:
		out.append(3)
	return out


## The team of slot i when `players` slots split into `teams` contiguous
## blocks (0 without teams).
static func team_of(slot: int, players: int, teams: int) -> int:
	if teams < 2 or players <= 0:
		return 0
	return slot * teams / players + 1


## The random_maps.curated entries of a mode as new-game entries. A curated
## entry always plays its own seed (map_seed); the seed box then only seeds
## the game.
static func curated_entries(data: GameData, mode: String) -> Array:
	var out := []
	var cfg := data.map_templates
	for c in RandomMapTemplate.settings(cfg).get("curated", []):
		var recipe := String(c.get("recipe", ""))
		var c_mode := "conquest" if recipe == "" else String(ScenarioGenerator.recipe_of(data, recipe).get("mode", ""))
		if c_mode != mode:
			continue
		var tname := String(c.get("template", ""))
		var o := RandomMapTemplate.parse(cfg, tname)
		var entry := {"id": CURATED_PREFIX + String(c["id"]), "name": String(c["name"]), "text": String(c.get("text", "")),
			"curated": true, "generated": true, "template": tname, "map_seed": int(c["seed"]), "mode": mode,
			"layout_family": String(o.get("family", "")), "scenario": recipe != ""}
		if recipe != "":
			entry["recipe"] = recipe
			entry["slots"] = _slots_from(ScenarioGenerator.players(data, recipe, tname))
			entry["invasion_strength"] = ScenarioGenerator.recipe_of(data, recipe).get("wave_strength", {})
		else:
			entry["slots"] = _slots_from(RandomMapTemplate.build(cfg, tname, int(c["seed"])).get("players", []))
		entry["size"] = _random_size_text(data, recipe, o)
		out.append(entry)
	return out


## Problems in random_maps.curated: unique ids, names, positive seeds, a
## random-map template that names its layout family (conquest and template
## scenario modes), and a known, non-legacy recipe for scenario entries.
static func validate_curated(data: GameData, curated: Variant) -> Array[String]:
	var errors: Array[String] = []
	if curated == null:
		return errors
	if typeof(curated) != TYPE_ARRAY:
		errors.append("random_maps.curated must be a list")
		return errors
	var cfg := data.map_templates
	var seen := {}
	for c in curated:
		if typeof(c) != TYPE_DICTIONARY:
			errors.append("random_maps.curated: every entry must be an object")
			continue
		var id := String(c.get("id", ""))
		var where := "random_maps.curated %s" % id
		if id == "" or id.contains(":"):
			errors.append("random_maps.curated: every entry needs an id without ':'")
		elif seen.has(id):
			errors.append("%s: duplicate id" % where)
		seen[id] = true
		if typeof(c.get("name")) != TYPE_STRING or String(c["name"]).strip_edges() == "":
			errors.append("%s: missing name" % where)
		var seed_v: Variant = c.get("seed")
		if not (typeof(seed_v) in [TYPE_INT, TYPE_FLOAT]) or float(seed_v) != floorf(float(seed_v)) or float(seed_v) < 1.0:
			errors.append("%s: seed must be a positive whole number" % where)
		var tname := String(c.get("template", ""))
		var recipe := String(c.get("recipe", ""))
		var needs_template := true
		if recipe != "":
			var r := ScenarioGenerator.recipe_of(data, recipe)
			if r.is_empty():
				errors.append("%s: unknown recipe %s" % [where, recipe])
				continue
			if bool(r.get("legacy", false)):
				errors.append("%s: recipe %s is legacy" % [where, recipe])
			needs_template = ScenarioGenerator.uses_template(data, recipe)
			if not needs_template and tname != "":
				errors.append("%s: recipe %s takes no template" % [where, recipe])
		if needs_template:
			var o := RandomMapTemplate.parse(cfg, tname)
			if o.is_empty() or not o.has("family"):
				errors.append("%s: template %s must be a random-map name with a layout family" % [where, tname])
			elif recipe != "" and int(o["players"]) > SCENARIO_MAX_PLAYERS:
				errors.append("%s: scenario templates take at most %d players" % [where, SCENARIO_MAX_PLAYERS])
	return errors


## The options a random map starts with: the second size (or the first), two
## players, any layout, no teams, normal monsters and normal treasure (or the
## first of each). A template scenario mode starts from its recipe's template
## when that is a random-map name.
static func default_random_options(data: GameData, mode: String = "conquest") -> Dictionary:
	var cfg := data.map_templates
	var sizes := RandomMapTemplate.option_keys(cfg, "sizes")
	if sizes.is_empty():
		return {"mode": mode}
	var pick := func(table: String, want: String) -> String:
		var keys := RandomMapTemplate.option_keys(cfg, table)
		return want if keys.has(want) else String(keys[0])
	var out := {"size": String(sizes[mini(1, sizes.size() - 1)]), "players": RandomMapTemplate.min_players(cfg),
		"monsters": pick.call("monsters", "normal"), "treasure": pick.call("treasure", "normal"),
		"family": "", "teams": 0, "mode": mode}
	if mode != "conquest":
		var own := RandomMapTemplate.parse(cfg, ScenarioGenerator.template_for(data, ScenarioGenerator.current_recipe(data, mode)))
		for k in own:
			out[k] = own[k]
	return out


## The new-game entry of a random map with these options ({size, players,
## monsters, treasure, family ("" = the seed picks), teams (0, 2 or 3), mode
## (default conquest)}). Players is clamped to what the size (and, for a
## scenario, SCENARIO_MAX_PLAYERS) allows; a family that cannot hold the
## players and a team count the players cannot split into fall back to "" and
## 0. Conquest: id "gen:random", slots from the template with the teams filled
## in. A scenario mode: the mode's current recipe, on the random template if
## the recipe takes one, id "scenario:random:<mode>". map_id_for appends the
## seed. {} if the mode has no recipe or there are no random-map settings.
static func random_entry(data: GameData, options: Dictionary) -> Dictionary:
	var cfg := data.map_templates
	var mode := String(options.get("mode", "conquest"))
	var recipe := "" if mode == "conquest" else ScenarioGenerator.current_recipe(data, mode)
	if mode != "conquest" and recipe == "":
		return {}
	var uses_template := mode == "conquest" or ScenarioGenerator.uses_template(data, recipe)
	if uses_template and RandomMapTemplate.settings(cfg).is_empty():
		return {}
	var o := {"mode": mode}
	var tname := ""
	if uses_template:
		var defaults := default_random_options(data, mode)
		for k in ["size", "players", "monsters", "treasure"]:
			o[k] = options.get(k, defaults[k])
		var size := String(o["size"])
		var hi := RandomMapTemplate.max_players(cfg, size)
		if mode != "conquest":
			hi = mini(hi, SCENARIO_MAX_PLAYERS)
		o["players"] = clampi(int(o["players"]), RandomMapTemplate.min_players(cfg), hi)
		var family := String(options.get("family", ""))
		o["family"] = family if LayoutFamilies.supports(cfg, family, int(o["players"])) else ""
		var teams := int(options.get("teams", 0))
		o["teams"] = teams if mode == "conquest" and team_choices(int(o["players"])).has(teams) else 0
		tname = RandomMapTemplate.make_name(size, int(o["players"]), String(o["monsters"]), String(o["treasure"]), String(o["family"]))
	var entry := {"generated": true, "random": true, "mode": mode, "template": tname, "options": o,
		"layout_family": String(o.get("family", ""))}
	if mode == "conquest":
		var tpl := RandomMapTemplate.build(cfg, tname, 0)
		var slots := _slots_from(tpl.get("players", []))
		for i in slots.size():
			slots[i]["team"] = team_of(i, slots.size(), int(o["teams"]))
		entry.merge({"id": RANDOM_ID, "name": "Random map", "slots": slots, "scenario": false})
	else:
		entry.merge({"id": "%srandom:%s" % [ScenarioGenerator.PREFIX, mode], "name": "Random %s" % String(MODE_NAMES[mode]).to_lower(),
			"recipe": recipe, "scenario": true, "slots": _slots_from(ScenarioGenerator.players(data, recipe, tname)),
			"invasion_strength": ScenarioGenerator.recipe_of(data, recipe).get("wave_strength", {})})
	entry["size"] = _random_size_text(data, recipe, RandomMapTemplate.parse(cfg, tname))
	return entry


## "<side>x<side>" of a random-map template's options, or the recipe's own
## size for a scenario without a template.
static func _random_size_text(data: GameData, recipe: String, o: Dictionary) -> String:
	if not o.is_empty():
		var side := RandomMapTemplate.side(data.map_templates, String(o["size"]), int(o["players"]))
		return "%dx%d" % [side, side]
	var r := ScenarioGenerator.recipe_of(data, recipe)
	var width := int(r.get("width", int(r.get("cells", 0)) * 2 + 1))
	return "%dx%d" % [width, int(r.get("height", width))]


static func _slots_from(players: Array) -> Array:
	var out := []
	for p in players:
		out.append({"faction": String(p["faction"]), "is_human": bool(p.get("is_human", false)),
			"name": String(p.get("name", "")), "color": String(p.get("color", "")), "difficulty": String(p.get("difficulty", "")), "team": int(p.get("team", 0))})
	return out


## The map id to start (the one place new-game ids are built): hand-made
## maps keep their id, generated maps get the seed appended
## ("gen:<template>:<seed>[:<factions>]", "scenario:<recipe>[:<template>]:<seed>"). A
## curated entry plays its own seed (map_seed) whatever seed is passed.
static func map_id_for(entry: Dictionary, map_seed: int, setup: Dictionary = {}) -> String:
	var s := int(entry.get("map_seed", map_seed))
	if entry.has("recipe"):
		return ScenarioGenerator.make_id(String(entry["recipe"]), String(entry.get("template", "")), s)
	if bool(entry.get("generated", false)):
		return MapGenerator.make_id(String(entry["template"]), s, setup_factions(entry, setup))
	return entry["id"]


## A generated map is built for the chosen factions, so every home zone gets
## its player's native ground. [] when the setup keeps the map's own factions.
static func setup_factions(entry: Dictionary, setup: Dictionary) -> Array:
	var players: Array = setup.get("players", [])
	var slots: Array = entry.get("slots", [])
	if players.size() != slots.size():
		return []
	var out := []
	var changed := not (entry.get("factions", []) as Array).is_empty()
	for i in players.size():
		var f := String(players[i].get("faction", slots[i]["faction"]))
		out.append(f)
		changed = changed or f != String(slots[i]["faction"])
	return out if changed else []


## The map's own configuration as a setup dictionary.
static func default_setup(entry: Dictionary) -> Dictionary:
	var ps := []
	for s in entry["slots"]:
		ps.append({"type": "human" if s["is_human"] else "computer", "faction": s["faction"], "name": "",
			"difficulty": String(s.get("difficulty", "")), "team": int(s.get("team", 0)), "color": String(s.get("color", ""))})
	var setup := {"players": ps}
	if entry.get("custom", false):
		setup["standard_start"] = false
		setup["preserve_authored"] = true
		for i in ps.size():
			ps[i]["name"] = entry["slots"][i].get("name", "")
	return setup


## Problems with a setup for a map definition; empty means it can start.
static func validate(def: Dictionary, setup: Dictionary, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var slots: Array = def.get("players", [])
	var opts: Array = setup.get("players", [])
	if opts.size() > slots.size():
		errors.append("setup has %d players, the map only %d slots" % [opts.size(), slots.size()])
	var active := 0
	var teams := {}   # team of every active player (0 = alone, counted per player)
	for i in slots.size():
		var o := _option(slots, opts, i)
		if not o["type"] in ["human", "computer", "closed"]:
			errors.append("slot %d: unknown type %s" % [i, o["type"]])
		if def.has("scenario") and def["scenario"].get("invasion_players", []).any(func(idx): return int(idx) == i) and o.get("difficulty", "") == "passive":
			errors.append("invasions require Easy, Normal or Hard difficulty")
		if def.has("scenario") and (o["type"] != ("human" if bool(slots[i].get("is_human", false)) else "computer") or (i != int(def["scenario"].get("player", 0)) and o["faction"] != slots[i]["faction"])):
			errors.append("scenario player roles are fixed")
		if o["type"] != "closed":
			active += 1
			if not playable_factions(data).has(o["faction"]):
				errors.append("slot %d: faction %s cannot be played" % [i, o["faction"]])
			var hero_class := String(o.get("hero_class", ""))
			if hero_class != "" and hero_class not in classes_for_faction(data, String(o["faction"])):
				errors.append("slot %d: hero class %s does not belong to faction %s" % [i, hero_class, o["faction"]])
			if String(o.get("difficulty", "")) != "" and not data.difficulty_levels().has(String(o["difficulty"])):
				errors.append("slot %d: unknown difficulty %s" % [i, o["difficulty"]])
			var color := String(o.get("color", ""))
			if color != "" and not Color.html_is_valid(color):
				errors.append("slot %d: invalid color" % i)
			var team := int(o.get("team", 0))
			if team < 0 or team > MAX_TEAMS:
				errors.append("slot %d: team must be 0 (none) to %d" % [i, MAX_TEAMS])
			teams[team if team > 0 else -1 - i] = true
	if active == 0:
		errors.append("at least one player must take part")
	elif active >= 2 and teams.size() == 1:
		errors.append("every player is on the same team: no one is left to fight")
	return errors


static func _option(slots: Array, opts: Array, i: int) -> Dictionary:
	var base: Dictionary = slots[i]
	var o := {"type": "human" if bool(base.get("is_human", false)) else "computer", "faction": String(base["faction"]), "name": "",
		"difficulty": String(base.get("difficulty", "")), "team": int(base.get("team", 0))}
	if i < opts.size():
		o.merge(opts[i], true)
	return o


## Returns a copy of the map definition with the setup applied: closed slots
## are removed (their heroes leave, their towns and mines turn neutral, a
## neutral town gets a garrison) and players are renumbered; a slot that
## changes faction gets that faction's town type and heroes, with armies
## converted creature by creature to the same tier at equal value.
static func apply(def: Dictionary, setup: Dictionary, data: GameData) -> Dictionary:
	var errors := validate(def, setup, data)
	assert(errors.is_empty(), "invalid setup: %s" % ", ".join(errors))
	var out := def.duplicate(true)
	var slots: Array = def["players"]
	var opts: Array = setup.get("players", [])
	var remap := {}           # map player id -> new player index
	var old_faction := {}     # new index -> faction the map gave the slot
	var players := []
	var humans := 0
	for i in slots.size():
		var o := _option(slots, opts, i)
		if o["type"] == "human":
			humans += 1
	for i in slots.size():
		var o := _option(slots, opts, i)
		if o["type"] == "closed":
			continue
		var idx := players.size()
		remap[int(slots[i]["id"])] = idx
		old_faction[idx] = String(slots[i]["faction"])
		var p: Dictionary = slots[i].duplicate(true)
		if String(o.get("color", "")) != "":
			p["color"] = o["color"]
		p["id"] = idx
		p["faction"] = o["faction"]
		p["hero_class"] = String(o.get("hero_class", ""))
		p["is_human"] = o["type"] == "human"
		# "" (or a human slot) plays at the default level.
		var level := String(o.get("difficulty", ""))
		p["difficulty"] = level if level != "" and not p["is_human"] else data.default_difficulty()
		p["team"] = int(o.get("team", 0))
		var fname: String = data.factions[o["faction"]]["name"]
		if String(o.get("name", "")) != "":
			p["name"] = o["name"]
		elif p["is_human"]:
			p["name"] = "Player %d" % (i + 1) if humans > 1 else "Player"
		else:
			p["name"] = fname
		players.append(p)
	out["players"] = players

	var used_hires := {}   # faction -> next index into its tavern pool
	var heroes := []
	var class_assigned := {}
	for hd in def.get("heroes", []):
		var owner := int(hd.get("owner", 0))
		if not remap.has(owner):
			continue
		var h: Dictionary = hd.duplicate(true)
		var idx: int = remap[owner]
		h["owner"] = idx
		var faction: String = players[idx]["faction"]
		if String(data.hero_classes[h["class"]]["faction"]) != faction and (not setup.get("preserve_authored", false) or faction != String(slots[owner]["faction"])):
			_convert_hero(h, faction, used_hires, data)
			if def.has("scenario"):
				h["id"] = hd["id"]
		var chosen := String(players[idx].get("hero_class", ""))
		if chosen != "" and not class_assigned.has(idx):
			h["class"] = chosen
			class_assigned[idx] = true
		heroes.append(h)
	out["heroes"] = heroes

	var objects := []
	for od in def.get("objects", []):
		var o: Dictionary = od.duplicate(true)
		if o["type"] in ["town", "mine"] or (o["type"] == "site" and o.has("owner")):
			var owner := int(o.get("owner", -1))
			if owner >= 0 and remap.has(owner):
				var idx: int = remap[owner]
				o["owner"] = idx
				var faction: String = players[idx]["faction"]
				if o["type"] == "town" and String(o["town_type"]) == old_faction[idx] and faction != old_faction[idx]:
					var previous := o.duplicate(true)
					_convert_town(o, faction, data)
					if def.has("scenario"):
						_preserve_scenario_development(o, previous, data)
			elif owner >= 0:
				o["owner"] = -1
				if o["type"] == "town" and (o.get("garrison", []) as Array).is_empty():
					o["garrison"] = _neutral_garrison(String(o["town_type"]), data)
		objects.append(o)
	out["objects"] = objects
	return out


## Same tier, equal value (rounded, at least one creature).
static func convert_stack(creature_id: String, count: int, faction: String, data: GameData) -> Array:
	var c := data.creature(creature_id)
	if String(c["faction"]) == faction:
		return [creature_id, count]
	var target := ""
	var best_tier := -1
	var ids := data.creatures.keys()
	ids.sort()
	for id in ids:
		var cand: Dictionary = data.creatures[id]
		if String(cand["faction"]) != faction:
			continue
		var t := int(cand["tier"])
		# The same tier, else the highest tier below it, else the lowest above.
		if t == int(c["tier"]):
			target = id
			break
		if t < int(c["tier"]) and t > best_tier:
			best_tier = t
			target = id
	if target == "":
		for id in ids:
			if String(data.creatures[id]["faction"]) == faction:
				target = id
				break
	var ratio := _value(c, data) / maxf(1.0, _value(data.creature(target), data))
	return [target, maxi(1, int(round(count * ratio)))]


static func _value(c: Dictionary, data: GameData) -> float:
	var values: Dictionary = data.economy["market"]["values"]
	var v := 0.0
	for res in c.get("cost", {}):
		v += float(c["cost"][res]) * float(values.get(res, 0))
	return v


static func _convert_army(pairs: Array, faction: String, data: GameData) -> Array:
	var merged := {}
	var order := []
	for pair in pairs:
		var conv := convert_stack(String(pair[0]), int(pair[1]), faction, data)
		if not merged.has(conv[0]):
			order.append(conv[0])
			merged[conv[0]] = 0
		merged[conv[0]] += int(conv[1])
	var out := []
	for id in order:
		out.append([id, merged[id]])
	return out


## Takes the next hero of the faction's tavern pool (so the tavern will not
## offer the same person again) and converts the army.
static func _convert_hero(h: Dictionary, faction: String, used_hires: Dictionary, data: GameData) -> void:
	var pool: Array = data.town_types[faction]["hire"]["heroes"]
	var k := int(used_hires.get(faction, 0))
	used_hires[faction] = k + 1
	if k < pool.size():
		h["id"] = "hire_%s_%d" % [faction, k]
		h["name"] = pool[k]["name"]
		h["class"] = pool[k]["class"]
	else:
		h["class"] = pool[k % pool.size()]["class"]
	h["army"] = _convert_army(h.get("army", []), faction, data)


static func _convert_town(t: Dictionary, faction: String, data: GameData) -> void:
	t["town_type"] = faction
	t.erase("built")        # building ids belong to the old town type
	t.erase("available")
	if t.has("garrison"):
		t["garrison"] = _convert_army(t["garrison"], faction, data)


static func _neutral_garrison(town_type: String, data: GameData) -> Array:
	var out := []
	for pair in data.town_types[town_type]["hire"]["army"]:
		out.append([pair[0], int(pair[1]) * 2])
	return out


## Mission starts retain their development when the player chooses another
## faction: equal creature tiers, the same number of fortifications, and markets.
static func _preserve_scenario_development(town: Dictionary, previous: Dictionary, data: GameData) -> void:
	var old_buildings: Dictionary = data.town_types[previous["town_type"]]["buildings"]
	var tier := 1
	var forts := 0
	var market := false
	for id in previous.get("built", []):
		for effect in old_buildings.get(id, {}).get("effects", []):
			if effect["type"] == "dwelling":
				tier = maxi(tier, int(data.creature(String(effect["creature"]))["tier"]))
			elif effect["type"] == "defense":
				forts += 1
			elif effect["type"] == "market":
				market = true
	var definition: Dictionary = data.town_types[town["town_type"]]
	var buildings: Dictionary = definition["buildings"]
	var built: Array = definition["starting_buildings"].duplicate()
	var fortifications := []
	var ids := buildings.keys()
	ids.sort()
	for id in ids:
		for effect in buildings[id]["effects"]:
			if effect["type"] == "dwelling" and int(data.creature(String(effect["creature"]))["tier"]) <= tier:
				_add_start_building(built, buildings, id)
			elif effect["type"] == "market" and market:
				_add_start_building(built, buildings, id)
			elif effect["type"] == "defense":
				fortifications.append(id)
	fortifications.sort_custom(func(a, b): return buildings[a]["requires"].size() < buildings[b]["requires"].size() or (buildings[a]["requires"].size() == buildings[b]["requires"].size() and a < b))
	for i in mini(forts, fortifications.size()):
		_add_start_building(built, buildings, fortifications[i])
	town["built"] = built


static func _add_start_building(built: Array, buildings: Dictionary, id: String) -> void:
	if built.has(id):
		return
	for prerequisite in buildings[id].get("requires", []):
		_add_start_building(built, buildings, String(prerequisite))
	built.append(id)
