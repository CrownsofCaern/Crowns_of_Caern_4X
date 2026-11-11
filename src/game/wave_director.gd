class_name WaveDirector
extends RefCounted
## Saved invasion schedules and explicit orders. All armies use normal commands.

const VERY_HARD_WAVE_FACTOR := 1.2


static func initialize(st: GameState) -> void:
	for key in ["spawned", "warned", "activated", "suppressed"]:
		if not st.scenario_runtime.has(key):
			st.scenario_runtime[key] = []
	for key in ["orders", "quests", "items", "flags"]:
		if not st.scenario_runtime.has(key):
			st.scenario_runtime[key] = {}


static func invasion_player(st: GameState, player_idx: int) -> bool:
	return ScenarioRules.definition(st).get("invasion_players", []).any(func(idx): return int(idx) == player_idx)


static func reserved_player(st: GameState, player_idx: int) -> bool:
	return invasion_player(st, player_idx) or (ScenarioRules.definition(st).get("dormant_players", []).any(func(idx): return int(idx) == player_idx) and not st.scenario_runtime.get("activated", []).any(func(idx): return int(idx) == player_idx))


static func waves(st: GameState) -> Array:
	var out: Array = ScenarioRules.definition(st).get("waves", []).duplicate(true)
	var endless: Dictionary = ScenarioRules.definition(st).get("endless", {})
	if not endless.is_empty():
		var first := int(endless["first_day"])
		var interval := int(endless["interval"])
		# Only materialize waves within the warning horizon; IDs make reloads stable.
		var through := maxi(0, (st.day + 7 - first) / interval + 1)
		for i in through:
			var wave: Dictionary = endless["wave"].duplicate(true)
			wave["id"] = "endless_%d" % i
			wave["day"] = first + i * interval
			wave["hero"]["id"] = "endless_commander_%d" % i
			wave["hero"]["name"] = "%s %d" % [wave["hero"]["name"], i + 1]
			for stack in wave["hero"]["army"]:
				stack[1] = maxi(1, int(round(float(stack[1]) * (1.0 + i * float(endless.get("growth", 0.2))))))
			out.append(wave)
	return out


static func cleared(st: GameState) -> bool:
	if not ScenarioRules.definition(st).get("endless", {}).is_empty():
		return false
	for wave in waves(st):
		if not st.scenario_runtime.get("spawned", []).has(wave["id"]):
			return false
		var h: Hero = st.heroes.get(String(wave["hero"]["id"]), null)
		if h != null and h.alive:
			return false
	for h in st.heroes.values():
		if h.alive and invasion_player(st, h.owner):
			return false
	return true


static func on_day(session: GameSession) -> void:
	var st := session.state
	if not ScenarioRules.active(st) or st.game_over:
		return
	initialize(st)
	ScenarioBetrayal.check(session)
	var sc := ScenarioRules.definition(st)
	var player_idx := int(sc.get("player", 0))
	var active := 0
	for h in st.heroes.values():
		if h.alive and invasion_player(st, h.owner):
			active += 1
	for wave in waves(st):
		var id := String(wave["id"])
		if st.scenario_runtime["spawned"].has(id):
			continue
		var warning := int(wave.get("warning_days", 3)) + (2 if st.scenario_runtime["flags"].get("watchtower", false) else 0)
		if st.day >= int(wave["day"]) - warning and not st.scenario_runtime["warned"].has(id):
			st.scenario_runtime["warned"].append(id)
			(st.player(player_idx)["fog"] as FogOfWar).reveal(Vector2i(int(wave["spawn"][0]), int(wave["spawn"][1])), 2)
			var target: Dictionary = st.map.objects.get(String(wave["target"]), {})
			var composition := []
			for pair in scaled_army(session, wave):
				composition.append("%d %s" % [int(pair[1]), session.data.creature(String(pair[0]))["name"]])
			session._add_news(st.player(player_idx), "%s approaches %s. Entry on day %d at %s: %s." % [wave["hero"]["name"], target.get("name", wave["target"]), wave["day"], wave.get("entry_name", "the marked invasion entry"), ", ".join(composition)])
		if st.day < int(wave["day"]) or active >= int(sc.get("max_active_invaders", 6)):
			continue
		var target: Dictionary = st.map.objects.get(String(wave["target"]), {})
		if target.is_empty():
			continue
		var field := AiDistanceField.build(st.map, AdventureMap.object_pos(target), {})
		var spawn := Vector2i(-1, -1)
		for pos in wave.get("entry_tiles", [wave["spawn"]]):
			var candidate := Vector2i(int(pos[0]), int(pos[1]))
			if st.map.in_bounds(candidate) and st.map.is_passable(candidate) and st.hero_at(candidate) == null and st.map.object_at(candidate).is_empty() and field.cost_to(candidate) >= 0:
				spawn = candidate
				break
		if spawn.x < 0:
			continue # Every declared entry tile is blocked: keep this wave queued.
		var hd: Dictionary = wave["hero"].duplicate(true)
		hd["owner"] = int(wave["owner"])
		hd["pos"] = [spawn.x, spawn.y]
		hd["army"] = scaled_army(session, wave)
		var h := Hero.create(hd, session.data)
		st.heroes[h.id] = h
		st.player(h.owner)["defeated"] = false
		st.player(h.owner)["days_without_town"] = 0
		st.scenario_runtime["orders"][h.id] = {"kind": wave.get("order", "assault"), "target": wave["target"], "targets": wave.get("targets", [wave["target"]])}
		st.scenario_runtime["spawned"].append(id)
		session._reveal_around(h)
		session._add_news(st.player(player_idx), "%s has entered through %s." % [h.name, wave.get("entry_name", "an invasion entry")])
		active += 1
	ScenarioQuests.on_day(session)


static func strength_scale(session: GameSession, wave: Dictionary) -> float:
	var presets: Dictionary = ScenarioRules.definition(session.state).get("wave_strength", {})
	var level := session.difficulty_of(int(wave["owner"]))
	if presets.has(level):
		return float(presets[level])
	# Very hard is newer than most scenarios: a third more than their hard waves.
	if level == "very_hard" and presets.has("hard"):
		return float(presets["hard"]) * VERY_HARD_WAVE_FACTOR
	return 1.0


## The army a wave brings, as [creature, count] pairs: its declared troops
## scaled by the invader's difficulty and weakened 20% per suppressed entry.
## The warning news shows exactly this army, so the defender may plan with it.
static func scaled_army(session: GameSession, wave: Dictionary) -> Array:
	var factor := strength_scale(session, wave) * pow(0.8, session.state.scenario_runtime.get("suppressed", []).size())
	var out := []
	for pair in wave["hero"]["army"]:
		out.append([String(pair[0]), maxi(1, int(round(int(pair[1]) * factor)))])
	return out


static func next_wave(st: GameState) -> Dictionary:
	var pending := waves(st).filter(func(w): return not st.scenario_runtime.get("spawned", []).has(w["id"]))
	pending.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]) or (int(a["day"]) == int(b["day"]) and a["id"] < b["id"]))
	return pending[0] if not pending.is_empty() else {}


static func has_order(st: GameState, hero_id: String) -> bool:
	return st.scenario_runtime.get("orders", {}).has(hero_id)


static func play_order(session: GameSession, h: Hero) -> int:
	var order: Dictionary = session.state.scenario_runtime["orders"][h.id]
	var battles := 0
	for _i in 16:
		if not h.alive or h.movement_left <= 0 or session.state.game_over:
			break
		var target := _order_target(session, h, order)
		if target == Vector2i(-1, -1) or target == h.pos:
			break
		var result := session.move_hero(h.id, target)
		if result["battle"] != "":
			var battle := session.attack(h.id, String(result["battle"]))
			battles += 1
			if int(battle["winner"]) != 0:
				break
		elif result["steps"].is_empty() or result["encounter"] != "":
			# A neutral guard on a necessary route may be reached as a destination.
			var obstacle := _route_guard(session, h, target)
			if obstacle == "":
				break
			var approach := session.move_hero(h.id, session.battle_target(obstacle)["pos"])
			if approach["battle"] == obstacle:
				var battle := session.attack(h.id, obstacle)
				battles += 1
				if int(battle["winner"]) != 0:
					break
			elif approach["encounter"] != "":
				if not StrategicAI.new(session, h.owner)._handle_encounter(h, String(approach["encounter"])):
					break
			else:
				break
	return battles


## UI turns preserve the incoming battle choice/report handshake for ordered armies.
static func play_order_interactive(session: GameSession, h: Hero, battle_handler: Callable) -> int:
	var order: Dictionary = session.state.scenario_runtime["orders"][h.id]
	var battles := 0
	for _i in 16:
		if not h.alive or h.movement_left <= 0 or session.state.game_over:
			break
		var target := _order_target(session, h, order)
		if target == Vector2i(-1, -1) or target == h.pos:
			break
		var result := session.move_hero(h.id, target)
		if result["battle"] != "":
			var battle := await _ordered_battle(session, h, String(result["battle"]), battle_handler)
			battles += 1
			if int(battle["winner"]) != 0:
				break
		elif result["steps"].is_empty() or result["encounter"] != "":
			# A neutral guard on a necessary route may be reached as a destination.
			var obstacle := _route_guard(session, h, target)
			if obstacle == "":
				break
			var approach := session.move_hero(h.id, session.battle_target(obstacle)["pos"])
			if approach["battle"] == obstacle:
				var battle := await _ordered_battle(session, h, obstacle, battle_handler)
				battles += 1
				if int(battle["winner"]) != 0:
					break
			elif approach["encounter"] != "":
				if not StrategicAI.new(session, h.owner)._handle_encounter(h, String(approach["encounter"])):
					break
			else:
				break
	return battles


static func _ordered_battle(session: GameSession, h: Hero, target_id: String, handler: Callable) -> Dictionary:
	var ai := StrategicAI.new(session, h.owner)
	var target := session.battle_target(target_id)
	ai._give_orders(h, session.battle_setup(h.id, target_id)["sides"][1]["stacks"])
	var defender: Hero = target["hero"]
	var owner := defender.owner if defender != null else int(target["object"].get("owner", -1))
	if handler.is_valid() and owner >= 0 and session.state.player(owner)["is_human"]:
		return await handler.call(h.id, target_id)
	return session.attack(h.id, target_id)


static func _order_target(session: GameSession, h: Hero, order: Dictionary) -> Vector2i:
	var kind := String(order.get("kind", "assault"))
	if kind in ["defend", "escort"]:
		var anchor := h.pos
		var target_hero := session.hero(String(order.get("target", "")))
		var town := session.town(String(order.get("target", "")))
		if target_hero != null and target_hero.alive:
			anchor = target_hero.pos
		elif not town.is_empty():
			anchor = AdventureMap.object_pos(town)
		var ids := session.state.heroes.keys()
		ids.sort()
		for id in ids:
			var enemy: Hero = session.state.heroes[id]
			if enemy.alive and not session.allied(enemy.owner, h.owner) and enemy.pos.distance_to(anchor) <= float(order.get("radius", 10)) and (session.state.player(h.owner)["fog"] as FogOfWar).is_explored(enemy.pos):
				return enemy.pos
		if target_hero != null:
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var p: Vector2i = anchor + offset
				if session.state.map.in_bounds(p) and session.state.map.is_passable(p) and session.state.hero_at(p) == null:
					return p
		if not town.is_empty() and int(town["owner"]) != h.owner and session.allied(int(town["owner"]), h.owner):
			# Allied town gates belong to their owner; defend from an adjacent tile.
			var best := Vector2i(-1, -1)
			var cost := 2147483647
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var candidate: Vector2i = anchor + offset
				if not session.state.map.in_bounds(candidate) or not session.state.map.is_passable(candidate):
					continue
				if candidate == h.pos:
					return h.pos
				if session.state.hero_at(candidate) != null:
					continue
				var route := session.plan_path(h.id, candidate)
				if not route["path"].is_empty() and int(route["total_cost"]) < cost:
					best = candidate
					cost = int(route["total_cost"])
			if best.x >= 0:
				return best
		return anchor
	var targets: Array = order.get("targets", [order.get("target", "")]).duplicate()
	var ids := session.state.map.objects.keys()
	ids.sort()
	if kind == "raid":
		for id in ids:
			var obj: Dictionary = session.state.map.objects[id]
			if obj["type"] == "mine" and int(obj.get("owner", -1)) >= 0 and not session.allied(int(obj["owner"]), h.owner):
				targets.push_front(id)
	for id in ids:
		var obj: Dictionary = session.state.map.objects[id]
		if obj["type"] == "town" and not targets.has(id):
			targets.append(id)
	for id in targets:
		var obj: Dictionary = session.state.map.objects.get(String(id), {})
		if not obj.is_empty() and int(obj.get("owner", -1)) >= 0 and not session.allied(int(obj["owner"]), h.owner):
			return AdventureMap.object_pos(obj)
	return Vector2i(-1, -1)


static func _route_guard(session: GameSession, h: Hero, target: Vector2i) -> String:
	# Distances ignore beatable object blockers, but respect closed gates.
	var field := AiDistanceField.build(session.state.map, target, {})
	var best := ""
	var cost := 2147483647
	var ids := session.state.map.objects.keys()
	ids.sort()
	for id in ids:
		var obj: Dictionary = session.state.map.objects[id]
		if not session.is_guarded(obj, h.owner) and obj["type"] != "encounter":
			continue
		var plan := session.plan_path(h.id, AdventureMap.object_pos(obj))
		var remaining := field.cost_to(AdventureMap.object_pos(obj))
		if not plan["path"].is_empty() and remaining >= 0 and int(plan["total_cost"]) + remaining < cost:
			best = id
			cost = int(plan["total_cost"]) + remaining
	var hero_ids := session.state.heroes.keys()
	hero_ids.sort()
	for id in hero_ids:
		var enemy: Hero = session.state.heroes[id]
		if not enemy.alive or session.allied(enemy.owner, h.owner):
			continue
		var plan := session.plan_path(h.id, enemy.pos)
		var remaining := field.cost_to(enemy.pos)
		if not plan["path"].is_empty() and remaining >= 0 and int(plan["total_cost"]) + remaining < cost:
			best = id
			cost = int(plan["total_cost"]) + remaining
	return best


static func validate(sc: Dictionary, map_def: Dictionary, data: GameData = null) -> Array[String]:
	var errors: Array[String] = []
	for field in ["invasion_players", "dormant_players"]:
		if typeof(sc.get(field, [])) != TYPE_ARRAY:
			errors.append("%s must be an array" % field)
		else:
			for idx in sc.get(field, []):
				if not ScenarioRules._whole(idx, 0) or (not map_def.is_empty() and int(idx) >= map_def["players"].size()):
					errors.append("invalid reserved player")
	if not ScenarioRules._whole(sc.get("max_active_invaders", 6), 1):
		errors.append("max_active_invaders must be positive")
	if not errors.is_empty():
		return errors
	if sc.get("invasion_players", []).any(func(idx): return int(idx) == int(sc.get("player", 0))):
		errors.append("the scenario player cannot be an invader")
	var presets: Variant = sc.get("wave_strength", {})
	if typeof(presets) != TYPE_DICTIONARY:
		errors.append("wave_strength must be a dictionary")
	else:
		for level in presets:
			if typeof(presets[level]) not in [TYPE_INT, TYPE_FLOAT] or float(presets[level]) <= 0 or (data != null and not data.difficulty_levels().has(level)):
				errors.append("invalid wave strength preset")
	var schedule: Variant = sc.get("waves", [])
	if typeof(schedule) != TYPE_ARRAY:
		return ["waves must be an array"]
	var endless: Variant = sc.get("endless", {})
	if typeof(endless) != TYPE_DICTIONARY:
		errors.append("endless must be a dictionary")
	elif not endless.is_empty():
		if not ScenarioRules._whole(endless.get("first_day", null), 1) or not ScenarioRules._whole(endless.get("interval", null), 1):
			errors.append("endless needs a positive first_day and interval")
		if typeof(endless.get("growth", 0.2)) not in [TYPE_FLOAT, TYPE_INT] or float(endless.get("growth", 0.2)) <= 0:
			errors.append("endless growth must be positive")
		if typeof(endless.get("wave", null)) != TYPE_DICTIONARY:
			errors.append("endless needs a wave template")
		else:
			schedule = schedule.duplicate(true)
			var wave: Dictionary = endless["wave"].duplicate(true)
			wave["id"] = "endless_template"
			wave["hero"]["id"] = "endless_template_commander"
			wave["day"] = 1
			schedule.append(wave)
	var ids := {}
	var hero_ids := {}
	for wave in schedule:
		if typeof(wave) != TYPE_DICTIONARY:
			errors.append("wave must be a dictionary")
			continue
		var id := String(wave.get("id", ""))
		if id == "" or ids.has(id):
			errors.append("wave needs a unique id")
		ids[id] = true
		if not ScenarioRules._whole(wave.get("day", null), 1) or not ScenarioRules._whole(wave.get("warning_days", 3), 0):
			errors.append("wave days must be nonnegative, arrival day positive")
		if not sc.get("invasion_players", []).any(func(idx): return int(idx) == int(wave.get("owner", -1))):
			errors.append("wave owner must be an invasion player")
		if wave.get("order", "assault") not in ["assault", "raid"]:
			errors.append("unknown wave order")
		var pos: Variant = wave.get("spawn", null)
		if typeof(pos) != TYPE_ARRAY or pos.size() != 2:
			errors.append("wave needs spawn [x, y]")
		elif not ScenarioRules._whole(pos[0], 0) or not ScenarioRules._whole(pos[1], 0):
			errors.append("invalid spawn coordinates")
		elif not map_def.is_empty() and (int(pos[0]) >= int(map_def["width"]) or int(pos[1]) >= int(map_def["height"])):
			errors.append("spawn outside map")
		var entries: Variant = wave.get("entry_tiles", [wave.get("spawn", [])])
		if typeof(entries) != TYPE_ARRAY or entries.is_empty():
			errors.append("entry_tiles must be a nonempty array")
		else:
			for entry in entries:
				if typeof(entry) != TYPE_ARRAY or entry.size() != 2:
					errors.append("entry tile needs [x, y]")
				elif not ScenarioRules._whole(entry[0], 0) or not ScenarioRules._whole(entry[1], 0):
					errors.append("invalid entry tile")
				elif not map_def.is_empty() and (int(entry[0]) >= int(map_def["width"]) or int(entry[1]) >= int(map_def["height"])):
					errors.append("entry tile outside map")
		var hd: Variant = wave.get("hero", null)
		if typeof(hd) != TYPE_DICTIONARY:
			errors.append("wave needs a hero definition")
			continue
		if String(hd.get("id", "")) == "" or hero_ids.has(hd.get("id", "")):
			errors.append("wave hero needs a unique id")
		hero_ids[hd.get("id", "")] = true
		if String(hd.get("name", "")) == "" or String(hd.get("class", "")) == "":
			errors.append("wave hero needs name and class")
		if data != null and not data.hero_classes.has(hd.get("class", "")):
			errors.append("unknown wave hero class")
		if typeof(hd.get("army", null)) != TYPE_ARRAY or hd.get("army", []).is_empty():
			errors.append("wave needs an army")
		else:
			for pair in hd["army"]:
				if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
					errors.append("bad wave stack")
				elif not ScenarioRules._whole(pair[1], 1) or (data != null and not data.creatures.has(pair[0])):
					errors.append("invalid wave creature or count")
		if not map_def.is_empty():
			var targets: Array = map_def["objects"].filter(func(o): return o["id"] == wave.get("target", "") and o["type"] == "town")
			if targets.is_empty():
				errors.append("wave needs a known target town")
			for h in map_def["heroes"]:
				if h["id"] == hd.get("id", ""):
					errors.append("wave hero collides with map hero")
	return errors


static func validate_runtime(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		return ["scenario_runtime must be a dictionary"]
	for key in ["spawned", "warned", "activated", "suppressed"]:
		if typeof(value.get(key, [])) != TYPE_ARRAY:
			errors.append("runtime %s must be an array" % key)
	for key in ["orders", "quests", "items", "flags"]:
		if typeof(value.get(key, {})) != TYPE_DICTIONARY:
			errors.append("runtime %s must be a dictionary" % key)
	if not errors.is_empty():
		return errors
	for id in value.get("orders", {}):
		var order: Variant = value["orders"][id]
		if typeof(order) != TYPE_DICTIONARY or order.get("kind", "") not in ["assault", "raid", "defend", "escort"] or typeof(order.get("target", null)) != TYPE_STRING:
			errors.append("invalid saved commander order")
	for id in value.get("items", {}):
		if typeof(value["items"][id]) != TYPE_ARRAY:
			errors.append("quest inventory must be an array")
		else:
			for item in value["items"][id]:
				if typeof(item) != TYPE_STRING:
					errors.append("quest inventory needs item ids")
	for id in value.get("quests", {}):
		if value["quests"][id] not in ["active", "complete"]:
			errors.append("invalid saved quest status")
	errors.append_array(ScenarioBetrayal.validate_runtime(value))
	return errors
