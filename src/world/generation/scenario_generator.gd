class_name ScenarioGenerator
extends RefCounted
## Versioned mission recipes (data/scenario_recipes.json). Definitions and
## progress are snapshotted by normal saves.
##
## Map ids: "scenario:<recipe>:<seed>" or "scenario:<recipe>:<template>:<seed>",
## where <template> is a generator template (usually a random-map name such as
## random_l_3p_normal_normal_ring) that replaces the recipe's own template.
## Recipes marked "legacy" (the v1 recipes stretched from the hand-made Last
## Watch map) stay loadable for old saves and ids but are not offered in menus.
##
## Modes: survival, defence and endless build on the map generator
## (ScenarioSiege, recipe version 2+); townless on the generator too
## (ScenarioTownless); labyrinth carves its own maze. Every non-legacy recipe
## gates its optional goals so the starting army cannot take them in week one
## (ScenarioGating.week_one_problems reports nothing).

const PREFIX := "scenario:"
const MODES := ["survival", "defence", "endless", "labyrinth", "townless"]
## Modes whose map comes from a generator template (and so take random-map options).
const TEMPLATE_MODES := ["survival", "defence", "endless", "townless"]


static func is_generated_id(id: String) -> bool:
	return id.begins_with(PREFIX)


## {recipe, seed, template ("" = the recipe's own)} or {} for a bad id.
static func parse_id(id: String) -> Dictionary:
	var parts := id.split(":")
	if parts.size() < 3 or parts.size() > 4 or parts[0] != "scenario" or not String(parts[-1]).is_valid_int():
		return {}
	if parts.size() == 4 and String(parts[2]).is_empty():
		return {}
	return {"recipe": parts[1], "seed": int(parts[-1]), "template": parts[2] if parts.size() == 4 else ""}


## The map id of a recipe on a template ("" keeps the recipe's) and seed.
static func make_id(recipe_id: String, template_name: String, seed_value: int) -> String:
	if template_name == "":
		return "%s%s:%d" % [PREFIX, recipe_id, seed_value]
	return "%s%s:%s:%d" % [PREFIX, recipe_id, template_name, seed_value]


static func generate_from_id(data: GameData, id: String) -> Dictionary:
	var parsed := parse_id(id)
	if parsed.is_empty():
		return {}
	return generate(data, String(parsed["recipe"]), int(parsed["seed"]), String(parsed["template"]))


static func recipe_of(data: GameData, recipe_id: String) -> Dictionary:
	return data.scenario_recipes.get("recipes", {}).get(recipe_id, {})


## The recipe the menus offer for a mode: the newest non-legacy one ("" if none).
static func current_recipe(data: GameData, mode: String) -> String:
	var best := ""
	var ids: Array = data.scenario_recipes.get("recipes", {}).keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = data.scenario_recipes["recipes"][id]
		if String(r.get("mode", "")) != mode or bool(r.get("legacy", false)):
			continue
		if best == "" or int(r.get("version", 1)) > int(recipe_of(data, best).get("version", 1)):
			best = String(id)
	return best


## True when the recipe's map comes from a generator template, so the random
## map options (size, players, layout, monsters, treasure) apply to it.
static func uses_template(data: GameData, recipe_id: String) -> bool:
	var r := recipe_of(data, recipe_id)
	return String(r.get("mode", "")) in TEMPLATE_MODES and r.has("template")


## The template a recipe plays on: `template_name` if given, else its own.
static func template_for(data: GameData, recipe_id: String, template_name: String = "") -> String:
	return template_name if template_name != "" else String(recipe_of(data, recipe_id).get("template", ""))


## A template name is usable if it is a hand-written template or a valid random-map name.
static func known_template(data: GameData, template_name: String) -> bool:
	return data.map_templates.get("templates", {}).has(template_name) \
		or not RandomMapTemplate.parse(data.map_templates, template_name).is_empty()


## The player slots of a recipe's maps (the new-game screen shows these
## without generating a map): [{id, name, faction, color, is_human}].
static func players(data: GameData, recipe_id: String, template_name: String = "") -> Array:
	var r := recipe_of(data, recipe_id)
	match String(r.get("mode", "")):
		"labyrinth":
			return [{"id": 0, "name": "The Expedition", "faction": "concord", "color": "#4488d0", "is_human": true}]
		"townless":
			var tname := template_for(data, recipe_id, template_name)
			if data.map_templates.get("templates", {}).has(tname):
				return data.map_templates["templates"][tname].get("players", [])
			return RandomMapTemplate.build(data.map_templates, tname, 0).get("players", [])
		"survival", "defence", "endless":
			if r.has("base_map"):
				return data.load_map(String(r["base_map"])).get("players", [])
			return ScenarioSiege.scenario_players(data)
	return []


static func generate(data: GameData, recipe_id: String, seed_value: int, template_name: String = "") -> Dictionary:
	var r := recipe_of(data, recipe_id)
	if r.is_empty():
		return {}
	if template_name != "":
		if not uses_template(data, recipe_id) or not known_template(data, template_name):
			return {}
		r = r.duplicate(true)
		r["template"] = template_name
	var result: Dictionary
	match String(r["mode"]):
		"labyrinth":
			result = _labyrinth(data, r, seed_value) if int(r.get("version", 1)) < 2 else ScenarioMaze.build(data, r, seed_value)
		"townless":
			result = ScenarioTownless.build(data, r, seed_value)
		_:
			result = _siege(data, r, seed_value) if r.has("base_map") else ScenarioSiege.build(data, r, seed_value)
	if result.is_empty():
		push_error("Scenario generation failed: %s seed %d has no room for its layout" % [recipe_id, seed_value])
		return {}
	result["id"] = make_id(recipe_id, template_name, seed_value)
	result["name"] = "%s (%d)" % [r["name"], seed_value]
	result["scenario"]["name"] = r["name"]
	result["scenario"]["mode"] = r["mode"]
	result["scenario"]["recipe"] = {"id": recipe_id, "version": int(r["version"]), "seed": seed_value}
	if template_name != "":
		result["scenario"]["recipe"]["template"] = template_name
	var errors := MapValidator.validate(result, data)
	if not errors.is_empty():
		push_error("Scenario generation failed: " + ", ".join(errors))
		return {}
	return result


static func _siege(data: GameData, recipe: Dictionary, seed_value: int) -> Dictionary:
	var result: Dictionary = GameData.read_json("%s/maps/%s.json" % [GameData.DATA_DIR, recipe["base_map"]])
	var rng := GameRng.new(GameRng.mix(seed_value, 8143))
	var stretch_x := {15: rng.next_int(1, 5), 28: rng.next_int(1, 5), 38: rng.next_int(1, 4)}
	var stretch_y := {9: rng.next_int(1, 4), 22: rng.next_int(1, 4)}
	var xs := _coordinates(int(result["width"]), stretch_x)
	var ys := _coordinates(int(result["height"]), stretch_y)
	var rows := []
	var last_row := ""
	for y in int(result["height"]):
		var row := ""
		for x in int(result["width"]):
			row += String(result["terrain"][y])[x]
			for _i in int(stretch_x.get(x, 0)):
				# Extend a corridor/room only if it continues on both sides.
				row += String(result["terrain"][y])[x] if x + 1 < int(result["width"]) and String(result["terrain"][y])[x + 1] != "^" else "^"
		rows.append(row)
		for _i in int(stretch_y.get(y, 0)):
			var extra := ""
			for x in row.length():
				# The same column mapping is used for the next source row.
				var source_x := 0
				while source_x + 1 < xs.size() and int(xs[source_x + 1]) <= x:
					source_x += 1
				extra += row[x] if y + 1 < int(result["height"]) and String(result["terrain"][y + 1])[source_x] != "^" else "^"
			rows.append(extra)
		last_row = row
	result["width"] = last_row.length()
	result["height"] = rows.size()
	result["terrain"] = rows
	for road in result["roads"]:
		road["from"] = _map_pos(road["from"], xs, ys)
		road["to"] = _map_pos(road["to"], xs, ys)
	for obj in result["objects"] + result["heroes"]:
		obj["pos"] = _map_pos(obj["pos"], xs, ys)
	var sc: Dictionary = result["scenario"]
	var profiles: Array = data.scenario_recipes["invasion_profiles"]
	var final_day := 0
	for i in sc["waves"].size():
		var wave: Dictionary = sc["waves"][i]
		wave["spawn"] = _map_pos(wave["spawn"], xs, ys)
		if wave.has("entry_tiles"):
			wave["entry_tiles"] = wave["entry_tiles"].map(func(p): return _map_pos(p, xs, ys))
		var budget := 0
		for pair in wave["hero"]["army"]:
			budget += MapGenerator.creature_value(data.creature(String(pair[0]))) * int(pair[1])
		var profile: Dictionary = profiles[rng.next_int(0, profiles.size() - 1)]
		var viable: Array = profile["units"].filter(func(pair): return MapGenerator.creature_value(data.creature(String(pair[0]))) * 4 <= budget)
		var total := 0.0
		for pair in viable:
			total += float(pair[1])
		var army := []
		for pair in viable:
			army.append([pair[0], maxi(1, int(round(budget * float(pair[1]) / total / MapGenerator.creature_value(data.creature(String(pair[0]))))))])
		wave["hero"]["class"] = profile["class"]
		wave["hero"]["name"] = "%s %d" % [profile["name"], i + 1]
		wave["hero"]["army"] = army
		wave["day"] = int(wave["day"]) + rng.next_int(-1, 1)
		final_day = maxi(final_day, int(wave["day"]))
	for objective in sc["objectives"]:
		if objective["type"] == "survive":
			objective["through_day"] = final_day
			objective["text"] = "Hold Last Watch through day %d." % final_day
	if recipe["mode"] == "defence":
		sc["protected_towns"] = ["town_last_watch", "town_northwatch", "town_crossing"]
		sc["briefing"] = "Hold Last Watch, Northwatch, and Crossingstead throughout the siege. Losing any of the three ends the mission. Expeditions can earn allies, reinforcements, and time."
	elif recipe["mode"] == "endless":
		sc["objectives"] = [{"id": "endless", "type": "endless", "text": "Survive as long as possible. Invasions continue every week."}]
		var next: Dictionary = sc["waves"][-1].duplicate(true)
		next.erase("day")
		sc["endless"] = {"first_day": final_day + 7, "interval": 7, "growth": 0.25, "wave": next}
		sc["briefing"] = "Hold Last Watch for as long as you can. After the initial siege, a stronger commander arrives every week. Win support across the map to prolong your defence."
	# Final-tile ecology remains independent of the wave schedule and geometry RNG.
	var ecology := MapGenerator.new(data)
	ecology.w = int(result["width"])
	ecology.h = int(result["height"])
	ecology.terrain = AdventureMap.from_definition(result, data).terrain
	ecology.objects = result["objects"]
	ecology.rng = GameRng.new(seed_value)
	ecology._attempt_seed = GameRng.mix(seed_value, 391)
	var named_guards := {}
	for obj in result["objects"]:
		if obj["type"] == "neutral_army" and obj.has("name"):
			named_guards[String(obj["id"])] = obj["name"]
	ecology._apply_neutral_habitats()
	for obj in result["objects"]:
		if named_guards.has(String(obj["id"])):
			obj["name"] = named_guards[String(obj["id"])]
	return result


static func _coordinates(size: int, stretches: Dictionary) -> Array:
	var out := []
	var offset := 0
	for i in size:
		out.append(i + offset)
		offset += int(stretches.get(i, 0))
	return out


static func _map_pos(p: Array, xs: Array, ys: Array) -> Array:
	return [xs[int(p[0])], ys[int(p[1])]]


static func _labyrinth(data: GameData, recipe: Dictionary, seed_value: int) -> Dictionary:
	var n := int(recipe["cells"])
	var width := n * 2 + 1
	var start := Vector2i(1, 1)
	var centre := Vector2i((n / 2) * 2 + 1, (n / 2) * 2 + 1)
	var result := {"id": "maze", "name": recipe["name"], "width": width, "height": width, "roads": [],
		"players": [{"id": 0, "name": "The Expedition", "faction": "concord", "color": "#4488d0", "is_human": true}],
		"heroes": [{"id": "hero_watch", "name": "Aldous Wren", "class": "knight", "owner": 0, "pos": [1, 1], "army": recipe["army"].duplicate(true)}], "objects": []}
	var rng := GameRng.new(seed_value)
	var map: AdventureMap
	var path: Array[Vector2i] = []
	var travel := 0
	for attempt in 128:
		rng = GameRng.new(GameRng.mix(seed_value, attempt + 239))
		var tiles := PackedStringArray()
		tiles.resize(width * width)
		tiles.fill("^")
		var visited := {Vector2i.ZERO: true}
		var stack := [Vector2i.ZERO]
		tiles[width + 1] = "."
		while not stack.is_empty():
			var p: Vector2i = stack[-1]
			var neighbours := []
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q: Vector2i = p + step
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and not visited.has(q):
					neighbours.append(q)
			if neighbours.is_empty():
				stack.pop_back()
				continue
			var q: Vector2i = neighbours[rng.next_int(0, neighbours.size() - 1)]
			visited[q] = true
			var a := p * 2 + Vector2i.ONE
			var b := q * 2 + Vector2i.ONE
			var mid := (a + b) / 2
			tiles[b.y * width + b.x] = "."
			tiles[mid.y * width + mid.x] = "."
			stack.append(q)
		var rows := []
		for y in width:
			var row := ""
			for x in width:
				row += tiles[y * width + x]
			rows.append(row)
		result["terrain"] = rows
		map = AdventureMap.from_definition(result, data)
		var finder := Pathfinder.new(map)
		path = finder.find_path(start, centre)
		travel = 0
		for cost in finder.step_costs(start, path):
			travel += cost
		if travel >= int(recipe["min_travel_cost"]) and travel <= int(recipe["max_travel_cost"]):
			break
	assert(travel >= int(recipe["min_travel_cost"]) and travel <= int(recipe["max_travel_cost"]), "maze must fit its travel budget")
	var original_path := path.duplicate()
	var from_start := AiDistanceField.build(map, start, {})
	var from_goal := AiDistanceField.build(map, centre, {})
	var shortcuts := []
	for y in range(1, width - 1):
		for x in range(1, width - 1):
			var p := Vector2i(x, y)
			if map.is_passable(p):
				continue
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var a: Vector2i = p - direction
				var b: Vector2i = p + direction
				if not map.is_passable(a) or not map.is_passable(b):
					continue
				var cost := mini(from_start.cost_to(a) + 200 + from_goal.cost_to(b), from_start.cost_to(b) + 200 + from_goal.cost_to(a))
				if travel - cost >= 2000 and travel - cost <= 7000:
					shortcuts.append({"pos": p, "saved": travel - cost})
	shortcuts.sort_custom(func(a, b): return a["saved"] > b["saved"] or (a["saved"] == b["saved"] and a["pos"].y * width + a["pos"].x < b["pos"].y * width + b["pos"].x))
	var special := []
	if not shortcuts.is_empty():
		var shortcut: Vector2i = shortcuts[rng.next_int(0, mini(4, shortcuts.size() - 1))]["pos"]
		var row := String(result["terrain"][shortcut.y])
		row[shortcut.x] = "."
		result["terrain"][shortcut.y] = row
		result["objects"].append({"id": "labyrinth_shortcut_guard", "type": "neutral_army", "pos": [shortcut.x, shortcut.y], "name": "The Shortcut Keeper", "stacks": _guard(data, rng, int(recipe["shortcut_budget"]))})
		special.append([shortcut.x, shortcut.y])
	result["objects"].append({"id": "stone_heart", "type": "scenario_site", "kind": "goal", "name": "The Stone Heart", "pos": [centre.x, centre.y], "sprite": "place_lockstone", "text": "Reach this chamber by the end of day 21."})
	for i in range(35, original_path.size() - 5, 45):
		var p: Vector2i = original_path[i]
		result["objects"].append({"id": "maze_guard_%d" % i, "type": "neutral_army", "pos": [p.x, p.y], "name": "Labyrinth sentinels", "stacks": _guard(data, rng, int(recipe["road_guard_budget"]))})
	var occupied := {}
	for obj in result["objects"]:
		occupied[Vector2i(int(obj["pos"][0]), int(obj["pos"][1]))] = true
	var side_branches := []
	for y in range(1, width - 1, 2):
		for x in range(1, width - 1, 2):
			var p := Vector2i(x, y)
			if not occupied.has(p) and not original_path.has(p) and from_start.cost_to(p) >= 1500:
				side_branches.append(p)
	for i in mini(3, side_branches.size()):
		var index := rng.next_int(0, side_branches.size() - 1)
		var p: Vector2i = side_branches.pop_at(index)
		var observatory := i == 0
		result["objects"].append({"id": "maze_support_%d" % i, "type": "scenario_site", "kind": "observatory" if observatory else "supplies", "pos": [p.x, p.y],
			"name": "The Survey Chamber" if observatory else "Stranded Volunteers", "sprite": "encounter_blind_cartographer" if observatory else "encounter_free_company_camp",
			"text": "Survey the maze to reveal the centre and a shortcut." if observatory else "These survivors will join your expedition if you reach them.",
			"reveal": special + [[centre.x, centre.y]], "radius": 5, "recruits": [["pike_militia", 10], ["longbowman", 6]]})
	result["scenario"] = {"name": recipe["name"], "mode": "labyrinth", "player": 0, "deadline_day": int(recipe["deadline_day"]), "required_heroes": ["hero_watch"], "townless_players": [0],
		"briefing": "Reach the Stone Heart before the end of day 21. A safe winding route leads inward; a stronger guardian holds a shorter crossing. Survey chambers reveal the land, and stranded volunteers can reinforce your army.",
		"travel_budget": {"safe_cost": travel, "minimum_daily_movement": 1500, "buffer_days": int(recipe["deadline_day"]) - ceili(travel / 1500.0)},
		"objectives": [{"id": "heart", "type": "reach", "hero": "hero_watch", "pos": [centre.x, centre.y], "text": "Reach the Stone Heart by the end of day 21."}]}
	return result


static func _guard(data: GameData, rng: GameRng, budget: int) -> Array:
	var generator := MapGenerator.new(data)
	generator.rng = rng
	return generator._roll_army(budget, "grass", 1, true)["stacks"]


static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = []
	for id in data.scenario_recipes.get("recipes", {}):
		var recipe: Dictionary = data.scenario_recipes["recipes"][id]
		if typeof(recipe.get("name", null)) != TYPE_STRING or String(recipe.get("name", "")).is_empty():
			errors.append("scenario recipe needs a name")
		if recipe.get("mode", "") not in ["survival", "defence", "endless", "labyrinth", "townless"] or not ScenarioRules._whole(recipe.get("version", null), 1):
			errors.append("invalid scenario recipe %s" % id)
		if recipe.get("mode", "") == "townless":
			if not known_template(data, String(recipe.get("template", ""))):
				errors.append("townless recipe %s needs a known generator template" % id)
			for field in ["villages", "village_days", "town_days", "town_win", "tiers"]:
				var pair: Variant = recipe.get(field, null)
				if typeof(pair) != TYPE_ARRAY or pair.size() != 2 or typeof(pair[0]) not in [TYPE_INT, TYPE_FLOAT] \
						or typeof(pair[1]) not in [TYPE_INT, TYPE_FLOAT] or float(pair[0]) < 0 or float(pair[0]) > float(pair[1]):
					errors.append("townless recipe %s needs %s [min, max]" % [id, field])
			if typeof(recipe.get("villages", null)) == TYPE_ARRAY and recipe["villages"].size() == 2 and (int(recipe["villages"][0]) < 1 or int(recipe["villages"][1]) > 8):
				errors.append("townless recipe %s needs 1 to 8 villages" % id)
			if typeof(recipe.get("stock_share", null)) not in [TYPE_INT, TYPE_FLOAT] or float(recipe.get("stock_share", 0)) <= 0.0 or float(recipe.get("stock_share", 0)) > 1.0:
				errors.append("townless recipe %s needs a stock_share in (0, 1]" % id)
		elif recipe.get("mode", "") == "labyrinth":
			if not ScenarioRules._whole(recipe.get("cells", null), 5) or int(recipe.get("cells", 0)) % 2 == 0:
				errors.append("labyrinth needs an odd number of cells >= 5")
			var army: Variant = recipe.get("army", null)
			if typeof(army) != TYPE_ARRAY or army.is_empty():
				errors.append("expedition needs an army")
			else:
				for pair in army:
					if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
						errors.append("invalid expedition stack")
					elif not data.creatures.has(pair[0]) or not ScenarioRules._whole(pair[1], 1):
						errors.append("invalid expedition army")
			for field in ["shortcut_budget", "road_guard_budget", "min_travel_cost", "max_travel_cost", "deadline_day"]:
				if not ScenarioRules._whole(recipe.get(field, null), 1):
					errors.append("invalid expedition %s" % field)
			if int(recipe.get("max_travel_cost", 0)) > maxi(0, int(recipe.get("deadline_day", 0)) - 5) * 1500:
				errors.append("expedition must reserve at least five days for battles and detours")
			if int(recipe.get("deadline_day", 0)) < 1 or int(recipe.get("max_travel_cost", 0)) <= int(recipe.get("min_travel_cost", 0)):
				errors.append("invalid labyrinth travel budget")
		elif recipe.has("base_map"):
			if not FileAccess.file_exists("%s/maps/%s.json" % [GameData.DATA_DIR, recipe.get("base_map", "")]):
				errors.append("scenario recipe needs a known base map")
		else:
			if not known_template(data, String(recipe.get("template", ""))):
				errors.append("siege recipe %s needs a base map or a known generator template" % id)
			var schedule: Variant = recipe.get("waves", null)
			if typeof(schedule) != TYPE_ARRAY or schedule.is_empty():
				errors.append("siege recipe %s needs waves [[day, strength], ...]" % id)
			else:
				for wave in schedule:
					if typeof(wave) != TYPE_ARRAY or wave.size() != 2 or not ScenarioRules._whole(wave[0], 1) \
							or typeof(wave[1]) not in [TYPE_INT, TYPE_FLOAT] or float(wave[1]) <= 0.0:
						errors.append("siege recipe %s has an invalid wave (day >= 1, strength > 0)" % id)
			if recipe.has("endless_growth") and (typeof(recipe["endless_growth"]) not in [TYPE_INT, TYPE_FLOAT] or float(recipe["endless_growth"]) <= 0.0):
				errors.append("siege recipe %s needs a positive endless_growth" % id)
		if recipe.has("legacy") and typeof(recipe["legacy"]) != TYPE_BOOL:
			errors.append("scenario recipe %s legacy must be true or false" % id)
	for profile in data.scenario_recipes.get("invasion_profiles", []):
		if not data.hero_classes.has(profile.get("class", "")):
			errors.append("invasion profile has unknown class")
		for pair in profile.get("units", []):
			if not data.creatures.has(pair[0]) or float(pair[1]) <= 0:
				errors.append("invalid invasion profile unit")
	return errors
