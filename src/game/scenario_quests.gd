class_name ScenarioQuests
extends RefCounted
## Persistent mission sites and dedicated quest inventory, separate from equipment.


static func quest(st: GameState, id: String) -> Dictionary:
	for q in ScenarioRules.definition(st).get("quests", []):
		if q["id"] == id:
			return q
	return {}


static func status(st: GameState, id: String) -> String:
	return String(st.scenario_runtime.get("quests", {}).get(id, "available"))


static func items(st: GameState, hero_id: String) -> Array:
	return st.scenario_runtime.get("items", {}).get(hero_id, [])


static func collect(session: GameSession, h: Hero, obj: Dictionary) -> bool:
	var sc := ScenarioRules.definition(session.state)
	if sc.is_empty() or h.owner != int(sc.get("player", 0)):
		return false
	var guard := String(obj.get("guarded_by", ""))
	if guard != "" and session.state.map.objects.has(guard):
		return false
	WaveDirector.initialize(session.state)
	var pack: Array = items(session.state, h.id).duplicate()
	var id := String(obj["item"])
	if not pack.has(id):
		pack.append(id)
	session.state.scenario_runtime["items"][h.id] = pack
	session.state.map.remove_object(String(obj["id"]))
	session.message.emit("%s recovers %s. Return it to the quest giver." % [h.name, obj.get("name", id)])
	return true


static func transfer(session: GameSession, from_id: String, to_id: String, item: String) -> Dictionary:
	var a := session.hero(from_id)
	var b := session.hero(to_id)
	if session.state.game_over or a == null or b == null or not a.alive or not b.alive or a == b or a.owner != session.state.current_player or b.owner != a.owner:
		return {"ok": false, "reason": "choose two of your living heroes"}
	if maxi(absi(a.pos.x - b.pos.x), absi(a.pos.y - b.pos.y)) > 1 or not items(session.state, a.id).has(item):
		return {"ok": false, "reason": "the carrier must stand next to the recipient"}
	var source: Array = items(session.state, a.id).duplicate()
	var destination: Array = items(session.state, b.id).duplicate()
	source.erase(item)
	destination.append(item)
	session.state.scenario_runtime["items"][a.id] = source
	session.state.scenario_runtime["items"][b.id] = destination
	return {"ok": true, "reason": ""}


static func on_fall(session: GameSession, h: Hero) -> void:
	var pack := items(session.state, h.id).duplicate()
	for item in pack.duplicate():
		var placed := false
		for radius in range(0, 7):
			for y in range(h.pos.y - radius, h.pos.y + radius + 1):
				for x in range(h.pos.x - radius, h.pos.x + radius + 1):
					var p := Vector2i(x, y)
					if not session.state.map.in_bounds(p) or not session.state.map.is_passable(p) or not session.state.map.object_at(p).is_empty():
						continue
					session.state.map.add_object({"id": "dropped_quest_" + String(item), "type": "quest_item", "item": item, "name": "Recovered relic", "pos": [x, y], "sprite": "object_chest"})
					pack.erase(item)
					placed = true
					break
				if placed:
					break
			if placed:
				break
	if session.state.scenario_runtime.has("items"):
		session.state.scenario_runtime["items"][h.id] = pack


static func options(session: GameSession, hero_id: String, site_id: String) -> Dictionary:
	var obj: Dictionary = session.state.map.objects.get(site_id, {})
	var h := session.hero(hero_id)
	if obj.is_empty() or obj.get("type", "") != "scenario_site" or h == null:
		return {}
	var out := {"title": obj.get("name", "Mission site"), "text": obj.get("text", ""), "actions": [], "items": items(session.state, hero_id).duplicate()}
	var available := h.alive and not session.state.game_over and h.owner == session.state.current_player and h.owner == int(ScenarioRules.definition(session.state).get("player", 0)) and h.pos == AdventureMap.object_pos(obj) and not session.is_guarded(obj, h.owner)
	if not available:
		return out
	match String(obj.get("kind", "")):
		"quest":
			var q := quest(session.state, String(obj["quest"]))
			var progress := status(session.state, String(q["id"]))
			out["text"] += "\n" + String(q.get("text", "")) + "\nStatus: " + progress.capitalize()
			if progress == "available":
				out["actions"].append({"id": "accept", "text": "Accept the quest", "reason": ""})
			elif progress == "active":
				out["actions"].append({"id": "deliver", "text": "Return the relic", "reason": "" if items(session.state, h.id).has(q["item"]) else "This hero must carry the relic."})
		"nest":
			if not bool(obj.get("claimed", false)):
				out["actions"].append({"id": "seal", "text": "Seal the tunnel", "reason": seal_reason(session, obj)})
		"goal":
			pass
		_:
			if not bool(obj.get("claimed", false)):
				out["actions"].append({"id": "claim", "text": "Secure this support", "reason": ""})
	# Gated mission sites (unlock_day) cannot be used early, so the starting
	# army cannot sweep every optional goal in the first week.
	var unlock := int(obj.get("unlock_day", 1))
	if session.state.day < unlock:
		for a in out["actions"]:
			if String(a["reason"]) == "":
				a["reason"] = "This opens on day %d." % unlock
	return out


static func act(session: GameSession, hero_id: String, site_id: String, action: String) -> Dictionary:
	var opts := options(session, hero_id, site_id)
	var actions: Array = opts.get("actions", []).filter(func(a): return a["id"] == action)
	if actions.is_empty() or String(actions[0]["reason"]) != "":
		return {"ok": false, "reason": "action is unavailable" if actions.is_empty() else actions[0]["reason"]}
	var st := session.state
	WaveDirector.initialize(st)
	var obj: Dictionary = st.map.objects[site_id]
	var h := session.hero(hero_id)
	var text := ""
	if action == "accept":
		st.scenario_runtime["quests"][String(obj["quest"])] = "active"
		text = "Quest accepted. Defeat the guardian and recover the relic."
	elif action == "deliver":
		var q := quest(st, String(obj["quest"]))
		var reward: Dictionary = q.get("reward", {})
		var ally := int(reward.get("ally_player", -1))
		var team := _alliance_team(st, h.owner)
		if ally >= 0 and team < 0:
			return {"ok": false, "reason": "no team is available for this alliance"}
		var pack := items(st, h.id).duplicate()
		pack.erase(q["item"])
		st.scenario_runtime["items"][h.id] = pack
		st.scenario_runtime["quests"][String(q["id"])] = "complete"
		var town := session.town(String(reward.get("town", "")))
		if not town.is_empty():
			town["owner"] = ally if ally >= 0 else h.owner
			# Capturing a town through a pact is immediate, with no battle.
			town.erase("requires_quest")
		if ally >= 0:
			st.player(h.owner)["team"] = team
			st.player(ally)["team"] = team
			st.player(ally)["defeated"] = false
			st.player(ally)["days_without_town"] = 0
			st.scenario_runtime["activated"].append(ally)
			var joined := PackedByteArray()
			joined.resize(st.map.width * st.map.height)
			for member in st.allies_of(h.owner):
				var fog: FogOfWar = st.player(member)["fog"]
				for i in joined.size():
					joined[i] = maxi(joined[i], fog.explored[i])
			for member in st.allies_of(h.owner):
				(st.player(member)["fog"] as FogOfWar).explored = joined.duplicate()
			if reward.has("hero"):
				var hd: Dictionary = reward["hero"].duplicate(true)
				hd["owner"] = ally
				hd["pos"] = town["pos"].duplicate()
				var ally_hero := Hero.create(hd, session.data)
				st.heroes[ally_hero.id] = ally_hero
				st.scenario_runtime["orders"][ally_hero.id] = {"kind": "defend", "target": reward.get("defend_target", town["id"]), "radius": 10}
				session._reveal_around(ally_hero)
		for res in reward.get("resources", {}):
			(st.player(h.owner)["resources"] as ResourceBank).add(res, int(reward["resources"][res]))
		text = String(q.get("completion_text", "The pact is sealed. Your allies will send reinforcements each week."))
	elif action == "seal":
		var gate: Dictionary = st.map.objects[String(obj["gate"])]
		gate["closed"] = true
		obj["claimed"] = true
		obj["owner"] = h.owner
		session.pathfinder.refresh_terrain()
		text = "The tunnel is sealed. Northern armies must take the long road."
	elif action == "claim":
		var recruits := Army.from_dict(h.army.to_dict())
		if obj["kind"] == "supplies":
			for pair in obj.get("recruits", []):
				if not recruits.add(String(pair[0]), int(pair[1])):
					return {"ok": false, "reason": "make room in your army for the volunteers"}
		obj["claimed"] = true
		obj["owner"] = h.owner
		match String(obj["kind"]):
			"watchtower":
				st.scenario_runtime["flags"]["watchtower"] = true
				for wave in WaveDirector.waves(st):
					(st.player(h.owner)["fog"] as FogOfWar).reveal(Vector2i(int(wave["spawn"][0]), int(wave["spawn"][1])), 6)
				text = "The watch is restored. Invasion warnings arrive two days earlier."
			"siege_camp":
				st.scenario_runtime["suppressed"].append(site_id)
				text = "The siege camp is destroyed. Future invasion armies lose one fifth of their strength."
			"observatory":
				for p in obj.get("reveal", []):
					(st.player(h.owner)["fog"] as FogOfWar).reveal(Vector2i(int(p[0]), int(p[1])), int(obj.get("radius", 5)))
				text = "The survey reveals the centre and a guarded shortcut."
			"supplies":
				h.army = recruits
				text = "The waiting volunteers join your expedition."
			"forge":
				st.scenario_runtime["flags"]["forge"] = true
				text = "The forge is secured. Fresh troops will reinforce the castle every week."
	session.message.emit(text)
	return {"ok": true, "reason": "", "text": text}


static func _alliance_team(st: GameState, player_idx: int) -> int:
	if st.team_of(player_idx) > 0:
		return st.team_of(player_idx)
	for team in range(1, GameSetup.MAX_TEAMS + 1):
		var used := false
		for p in st.players:
			if int(p.get("team", 0)) == team:
				used = true
		if not used:
			return team
	return -1


static func seal_reason(session: GameSession, obj: Dictionary) -> String:
	var gate: Dictionary = session.state.map.objects.get(String(obj.get("gate", "")), {})
	if gate.is_empty() or gate.get("type", "") != "gate":
		return "No tunnel gate is connected."
	if bool(gate.get("closed", false)):
		return "The tunnel is already sealed."
	if session.state.hero_at(AdventureMap.object_pos(gate)) != null:
		return "An army is standing in the tunnel."
	var entries := []
	for wave in WaveDirector.waves(session.state):
		entries.append({"from": Vector2i(int(wave["spawn"][0]), int(wave["spawn"][1])), "to": AdventureMap.object_pos(session.town(String(wave["target"])))})
	var before := []
	for entry in entries:
		before.append(AiDistanceField.build(session.state.map, entry["from"], {}).cost_to(entry["to"]))
	gate["closed"] = true
	var delayed := false
	var blocked := false
	for i in entries.size():
		var after := AiDistanceField.build(session.state.map, entries[i]["from"], {}).cost_to(entries[i]["to"])
		if after < 0:
			blocked = true
		elif before[i] >= 0 and after > before[i]:
			delayed = true
	var sc := ScenarioRules.definition(session.state)
	var base := session.town(String(sc.get("castle", "")))
	if not base.is_empty():
		var field := AiDistanceField.build(session.state.map, AdventureMap.object_pos(base), {})
		for target in session.state.map.objects.values():
			if target["type"] in ["scenario_site", "quest_item", "town"] and field.cost_to(AdventureMap.object_pos(target)) < 0:
				blocked = true
	gate["closed"] = false
	if blocked:
		return "Sealing this gate would strand a required route."
	return "" if delayed else "This gate would not delay the invasion."


static func on_day(session: GameSession) -> void:
	var st := session.state
	if st.day_of_week() != 1:
		return
	for q in ScenarioRules.definition(st).get("quests", []):
		var reward: Dictionary = q.get("reward", {})
		var source := session.town(String(reward.get("town", "")))
		var expected_owner := int(reward.get("ally_player", ScenarioRules.definition(st).get("player", 0)))
		if status(st, String(q["id"])) == "complete" and not source.is_empty() and int(source["owner"]) == expected_owner and not st.player(expected_owner)["defeated"]:
			_reinforce(session, q.get("reward", {}).get("weekly", {}), String(q["id"]))
	if st.scenario_runtime.get("flags", {}).get("forge", false):
		_reinforce(session, ScenarioRules.definition(st).get("forge_support", {}), "forge")


static func _reinforce(session: GameSession, support: Dictionary, source: String) -> void:
	if support.is_empty():
		return
	var token := "reinforced_%s_%d" % [source, session.state.week()]
	if session.state.scenario_runtime["flags"].get(token, false):
		return
	var town := session.town(String(support["town"]))
	var player_idx := int(ScenarioRules.definition(session.state).get("player", 0))
	if town.is_empty() or int(town["owner"]) != player_idx:
		return
	var garrison := Town.garrison(town)
	if garrison.add(String(support["creature"]), int(support["count"])):
		Town.set_garrison(town, garrison)
		session.state.scenario_runtime["flags"][token] = true
		session._add_news(session.state.player(player_idx), "%d %s reinforce %s." % [support["count"], session.data.creature(String(support["creature"]))["name"], town["name"]])


static func validate(sc: Dictionary, map_def: Dictionary, data: GameData = null) -> Array[String]:
	var errors: Array[String] = []
	var quests: Variant = sc.get("quests", [])
	if typeof(quests) != TYPE_ARRAY:
		return ["quests must be an array"]
	var ids := {}
	var item_ids := {}
	var hero_ids := {}
	if not map_def.is_empty():
		for h in map_def["heroes"]:
			hero_ids[String(h["id"])] = true
	if typeof(sc.get("waves", [])) == TYPE_ARRAY:
		for wave in sc.get("waves", []):
			if typeof(wave) == TYPE_DICTIONARY and typeof(wave.get("hero", {})) == TYPE_DICTIONARY:
				hero_ids[String(wave.get("hero", {}).get("id", ""))] = true
	for q in quests:
		if typeof(q) != TYPE_DICTIONARY:
			errors.append("quest must be a dictionary")
			continue
		for key in ["id", "giver", "item", "text"]:
			if typeof(q.get(key, null)) != TYPE_STRING or String(q.get(key, "")) == "":
				errors.append("quest needs %s" % key)
		if ids.has(q.get("id", "")):
			errors.append("quest ids must be unique")
		ids[q.get("id", "")] = true
		if item_ids.has(q.get("item", "")):
			errors.append("each quest needs a distinct relic")
		item_ids[q.get("item", "")] = true
		var reward: Variant = q.get("reward", {})
		if typeof(reward) != TYPE_DICTIONARY:
			errors.append("quest reward must be a dictionary")
			continue
		if reward.has("ally_player") and not sc.get("dormant_players", []).has(reward["ally_player"]):
			errors.append("quest ally must be a reserved dormant player")
		if typeof(reward.get("resources", {})) != TYPE_DICTIONARY:
			errors.append("quest resources must be a dictionary")
			continue
		if reward.has("hero") and typeof(reward["hero"]) != TYPE_DICTIONARY:
			errors.append("ally hero must be a dictionary")
			continue
		if reward.has("hero"):
			var ally_hero: Dictionary = reward["hero"]
			if not reward.has("ally_player") or not reward.has("town"):
				errors.append("an ally hero needs an ally player and a home town")
			if typeof(ally_hero.get("id", null)) != TYPE_STRING or String(ally_hero.get("id", "")).is_empty() or hero_ids.has(ally_hero.get("id", "")):
				errors.append("ally hero needs a unique nonempty id")
			hero_ids[String(ally_hero.get("id", ""))] = true
			if typeof(ally_hero.get("name", null)) != TYPE_STRING or String(ally_hero.get("name", "")).is_empty():
				errors.append("ally hero needs a name")
			var army: Variant = ally_hero.get("army", null)
			if typeof(army) != TYPE_ARRAY or army.is_empty():
				errors.append("ally hero needs an army")
			else:
				for pair in army:
					if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
						errors.append("invalid ally stack")
					elif not ScenarioRules._whole(pair[1], 1) or (data != null and not data.creatures.has(pair[0])):
						errors.append("invalid ally creature or count")
		if data != null:
			for res in reward.get("resources", {}):
				if not data.resources.has(res) or not ScenarioRules._whole(reward["resources"][res], 0):
					errors.append("unknown quest resource or invalid amount")
			if reward.has("hero") and not data.hero_classes.has(reward["hero"].get("class", "")):
				errors.append("unknown ally hero class")
		var weekly: Variant = reward.get("weekly", {})
		if typeof(weekly) != TYPE_DICTIONARY:
			errors.append("weekly support must be a dictionary")
		elif not weekly.is_empty():
			if not ScenarioRules._whole(weekly.get("count", null), 1) or (data != null and not data.creatures.has(weekly.get("creature", ""))):
				errors.append("invalid weekly support")
		if not map_def.is_empty():
			var giver: Array = map_def["objects"].filter(func(o): return o["id"] == q.get("giver", "") and o.get("kind", "") == "quest" and o.get("quest", "") == q.get("id", ""))
			if giver.is_empty():
				errors.append("quest giver must exist")
			if reward.has("defend_target") and map_def["objects"].filter(func(o): return o["id"] == reward["defend_target"] and o["type"] == "town").is_empty():
				errors.append("ally defence target must be a known town")
			if reward.has("town") and map_def["objects"].filter(func(o): return o["id"] == reward["town"] and o["type"] == "town").is_empty():
				errors.append("quest reward town must exist")
	var supports := [sc.get("forge_support", {})]
	for q in quests:
		if typeof(q) == TYPE_DICTIONARY and typeof(q.get("reward", {})) == TYPE_DICTIONARY:
			supports.append(q.get("reward", {}).get("weekly", {}))
	for support in supports:
		if typeof(support) != TYPE_DICTIONARY:
			errors.append("support must be a dictionary")
		elif not support.is_empty():
			if not ScenarioRules._whole(support.get("count", null), 1) or typeof(support.get("town", null)) != TYPE_STRING or (data != null and not data.creatures.has(support.get("creature", ""))):
				errors.append("invalid support town, creature or count")
	if not map_def.is_empty():
		var objects := {}
		for obj in map_def["objects"]:
			objects[String(obj["id"])] = obj
		for obj in map_def["objects"]:
			if obj["type"] == "quest_item":
				var guardian := String(obj.get("guarded_by", ""))
				if guardian != "" and objects.get(guardian, {}).get("type", "") != "neutral_army":
					errors.append("quest relic has an unknown guardian")
			elif obj["type"] == "scenario_site":
				if obj.has("unlock_day") and not ScenarioRules._whole(obj["unlock_day"], 1):
					errors.append("mission site unlock_day must be a positive integer")
				if obj.get("kind", "") == "nest" and objects.get(String(obj.get("gate", "")), {}).get("type", "") != "gate":
					errors.append("nest needs a known gate")
				if obj.get("kind", "") == "quest" and not ids.has(obj.get("quest", "")):
					errors.append("site needs a known quest")
				for pair in obj.get("recruits", []):
					if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
						errors.append("bad support recruit stack")
					elif not ScenarioRules._whole(pair[1], 1) or (data != null and not data.creatures.has(pair[0])):
						errors.append("unknown support recruit")
		for support in supports:
			if typeof(support) == TYPE_DICTIONARY and not support.is_empty() and objects.get(String(support.get("town", "")), {}).get("type", "") != "town":
				errors.append("support needs a known target town")
		for q in quests:
			if typeof(q) == TYPE_DICTIONARY:
				var relics: Array = map_def["objects"].filter(func(o): return o["type"] == "quest_item" and o.get("item", "") == q.get("item", ""))
				if relics.size() != 1:
					errors.append("quest needs exactly one recoverable relic")
	return errors
