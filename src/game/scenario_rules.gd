class_name ScenarioRules
extends RefCounted
## Explicit, headless objectives shared by campaigns and free-play scenarios.
## Definitions live in rules.scenario; visit progress is saved separately.
##
## Objective types: reach, control_towns, defeat_hero, clear_waves, endless,
## survive, conquer (every rival of the scenario player is out; invasion and
## still-dormant players excepted) and ally_survives {player, until_betrayal?}
## (counts as done while that ally is in the game; losing it loses the
## scenario, unless until_betrayal and the ally has turned, see ScenarioBetrayal).
## Any objective may carry:
##   unlock_day: it cannot be completed (a reach is not even recorded) before
##               this day, so a goal cannot be rushed with the starting army;
##   optional: true - listed, but not needed for victory;
##   after_betrayal: true - hidden and incomplete until the betrayal happened.


static func definition(st: GameState) -> Dictionary:
	return st.rules.get("scenario", {})


static func active(st: GameState) -> bool:
	return not definition(st).is_empty()


static func townless_allowed(st: GameState, player_idx: int) -> bool:
	return definition(st).get("townless_players", []).any(func(idx): return int(idx) == player_idx)


## Called for each visited tile, including intermediate steps of a march.
static func on_visit(st: GameState, h: Hero) -> void:
	var sc := definition(st)
	if sc.is_empty() or h.owner != int(sc.get("player", 0)):
		return
	if int(sc.get("deadline_day", 0)) > 0 and st.day > int(sc["deadline_day"]):
		return
	for obj in sc["objectives"]:
		if obj["type"] == "reach" and obj["hero"] == h.id and st.day >= int(obj.get("unlock_day", 1)):
			var p: Array = obj["pos"]
			if h.pos == Vector2i(int(p[0]), int(p[1])):
				st.scenario_progress[String(obj["id"])] = true


static func completed(session: GameSession, obj: Dictionary) -> bool:
	var st := session.state
	var player_idx := int(definition(st).get("player", 0))
	if st.day < int(obj.get("unlock_day", 1)):
		return false
	if bool(obj.get("after_betrayal", false)) and not ScenarioBetrayal.happened(st):
		return false
	match String(obj["type"]):
		"reach":
			return bool(st.scenario_progress.get(String(obj["id"]), false))
		"control_towns":
			for id in obj["towns"]:
				var town := session.town(String(id))
				if town.is_empty() or int(town["owner"]) != player_idx:
					return false
			return true
		"defeat_hero":
			var h := session.hero(String(obj["hero"]))
			return h != null and not h.alive
		"clear_waves":
			return WaveDirector.cleared(st)
		"endless":
			return false
		"survive":
			return st.day > int(obj["through_day"])
		"conquer":
			for i in st.players.size():
				if st.allied(i, player_idx) or WaveDirector.reserved_player(st, i):
					continue
				if not bool(st.player(i)["defeated"]):
					return false
			return true
		"ally_survives":
			return not bool(st.player(int(obj["player"]))["defeated"]) or _ally_turned(st, obj)
	return false


## An ally_survives objective with until_betrayal stops mattering once that ally turned.
static func _ally_turned(st: GameState, obj: Dictionary) -> bool:
	return bool(obj.get("until_betrayal", false)) and ScenarioBetrayal.happened(st) \
		and int(ScenarioBetrayal.definition(st).get("player", -1)) == int(obj["player"])


## Returns {winner, reason, text} when resolved; {} while still in progress.
## Losses take precedence over success. Ownership is checked live, not latched.
static func outcome(session: GameSession) -> Dictionary:
	var st := session.state
	var sc := definition(st)
	if sc.is_empty():
		return {}
	var player_idx := int(sc.get("player", 0))
	if bool(st.player(player_idx)["defeated"]):
		return _loss("Your realm has fallen.")
	for id in sc.get("required_heroes", []):
		var h := session.hero(String(id))
		if h == null or not h.alive:
			return _loss("A required hero has fallen: %s." % (h.name if h != null else id))
	for id in sc.get("protected_towns", []):
		var town := session.town(String(id))
		if town.is_empty() or int(town["owner"]) != player_idx:
			return _loss("A protected stronghold has been lost: %s." % town.get("name", id))
	for obj in sc["objectives"]:
		if obj["type"] == "ally_survives" and bool(st.player(int(obj["player"]))["defeated"]) and not _ally_turned(st, obj):
			return _loss("Your ally has fallen: %s." % st.player(int(obj["player"]))["name"])
	var all_done := true
	for obj in sc["objectives"]:
		if not bool(obj.get("optional", false)) and not completed(session, obj):
			all_done = false
	if all_done:
		return {"winner": player_idx, "reason": "scenario_victory", "text": "%s: all objectives completed." % sc["name"]}
	var deadline := int(sc.get("deadline_day", 0))
	if deadline > 0 and st.day > deadline:
		return _loss("%s: the deadline at the end of day %d has passed." % [sc["name"], deadline])
	return {}


static func _loss(text: String) -> Dictionary:
	return {"winner": -1, "reason": "scenario_defeat", "text": text}


## Read-only summaries for the HUD and future objective journal:
## {id, text, completed, optional, unlock_day}. Objectives that wait for the
## betrayal stay hidden until it happens.
static func objectives(session: GameSession) -> Array:
	var out := []
	for obj in definition(session.state).get("objectives", []):
		if bool(obj.get("after_betrayal", false)) and not ScenarioBetrayal.happened(session.state):
			continue
		var text := String(obj.get("text", obj["id"]))
		if session.state.day < int(obj.get("unlock_day", 1)):
			text += " (from day %d)" % int(obj["unlock_day"])
		if bool(obj.get("optional", false)):
			text = "Optional: " + text
		out.append({"id": obj["id"], "text": text, "completed": completed(session, obj),
			"optional": bool(obj.get("optional", false)), "unlock_day": int(obj.get("unlock_day", 1))})
	return out


## Schema checks also run through Campaign.validate / GameData.validate.
## With a map definition, additionally check references and reach coordinates.
static func validate(value: Variant, map_def: Dictionary = {}, data: GameData = null) -> Array[String]:
	var errors: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		return ["must be a dictionary"]
	var sc: Dictionary = value
	if sc.is_empty():
		return errors
	if typeof(sc.get("name", null)) != TYPE_STRING or String(sc.get("name", "")).is_empty():
		errors.append("needs a name")
	if not _whole(sc.get("player", 0), 0):
		errors.append("player must be a nonnegative integer")
	if sc.has("deadline_day") and not _whole(sc["deadline_day"], 1):
		errors.append("deadline_day must be a positive integer")
	for field in ["required_heroes", "protected_towns", "townless_players"]:
		if typeof(sc.get(field, [])) != TYPE_ARRAY:
			errors.append("%s must be an array" % field)
		else:
			for item in sc.get(field, []):
				if field == "townless_players":
					if not _whole(item, 0):
						errors.append("townless_players must contain player indices")
				elif typeof(item) != TYPE_STRING or String(item).is_empty():
					errors.append("%s must contain nonempty ids" % field)
	var objs: Variant = sc.get("objectives", null)
	if typeof(objs) != TYPE_ARRAY:
		errors.append("objectives must be a nonempty array")
		return errors
	if objs.is_empty():
		errors.append("objectives must be a nonempty array")
	var ids := {}
	for obj in objs:
		if typeof(obj) != TYPE_DICTIONARY:
			errors.append("objective must be a dictionary")
			continue
		var id: Variant = obj.get("id", "")
		if typeof(id) != TYPE_STRING or String(id).is_empty() or ids.has(id):
			errors.append("objective needs a unique nonempty id")
		ids[id] = true
		if obj.has("text") and typeof(obj["text"]) != TYPE_STRING:
			errors.append("objective text must be a string")
		if obj.has("unlock_day") and not _whole(obj["unlock_day"], 1):
			errors.append("%s unlock_day must be a positive integer" % id)
		for flag in ["optional", "after_betrayal", "until_betrayal"]:
			if obj.has(flag) and typeof(obj[flag]) != TYPE_BOOL:
				errors.append("%s %s must be true or false" % [id, flag])
		match String(obj.get("type", "")):
			"reach", "defeat_hero":
				if typeof(obj.get("hero", null)) != TYPE_STRING or String(obj.get("hero", "")).is_empty():
					errors.append("%s needs a hero id" % id)
				if obj["type"] == "reach":
					var pos: Variant = obj.get("pos", null)
					if typeof(pos) != TYPE_ARRAY or pos.size() != 2:
						errors.append("%s needs pos [x, y]" % id)
					elif not _whole(pos[0], 0) or not _whole(pos[1], 0):
						errors.append("%s position must contain nonnegative integers" % id)
			"control_towns":
				var towns: Variant = obj.get("towns", null)
				if typeof(towns) != TYPE_ARRAY or towns.is_empty():
					errors.append("%s needs nonempty towns" % id)
				else:
					for town in towns:
						if typeof(town) != TYPE_STRING or String(town).is_empty():
							errors.append("%s towns must contain ids" % id)
			"clear_waves", "endless", "conquer":
				pass
			"ally_survives":
				if not _whole(obj.get("player", null), 0):
					errors.append("%s needs an ally player index" % id)
				elif int(obj["player"]) == int(sc.get("player", 0)):
					errors.append("%s must name another player" % id)
			"survive":
				if not _whole(obj.get("through_day", null), 1):
					errors.append("%s needs a positive through_day" % id)
				elif int(sc.get("deadline_day", obj["through_day"])) < int(obj["through_day"]):
					errors.append("%s survival extends beyond the deadline" % id)
			_:
				errors.append("%s has unknown objective type" % id)
	if errors.is_empty():
		errors.append_array(WaveDirector.validate(sc, map_def, data))
	if errors.is_empty():
		errors.append_array(ScenarioQuests.validate(sc, map_def, data))
	if errors.is_empty():
		errors.append_array(ScenarioBetrayal.validate(sc, map_def, data))
	if errors.is_empty():
		var required := 0
		for obj in sc["objectives"]:
			if not bool(obj.get("optional", false)):
				required += 1
		if required == 0:
			errors.append("at least one objective must be required")
	if errors.is_empty():
		for obj in sc["objectives"]:
			if obj["type"] == "clear_waves" and sc.get("waves", []).is_empty():
				errors.append("clear_waves needs a wave schedule")
			if obj["type"] == "endless" and sc.get("endless", {}).is_empty():
				errors.append("endless objective needs an endless schedule")
	if errors.is_empty() and not map_def.is_empty():
		errors.append_array(_references(sc, map_def))
	return errors


static func _whole(value: Variant, minimum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and float(value) >= minimum and float(value) == floor(float(value))


static func _references(sc: Dictionary, map_def: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var heroes := {}
	var towns := {}
	for h in map_def["heroes"]:
		heroes[String(h["id"])] = h
	for obj in map_def["objects"]:
		if obj["type"] == "town":
			towns[String(obj["id"])] = obj
	var player_idx := int(sc.get("player", 0))
	if player_idx >= map_def["players"].size():
		errors.append("player is outside map slots")
	for idx in sc.get("townless_players", []):
		if int(idx) >= map_def["players"].size():
			errors.append("townless player is outside map slots")
	for hid in sc.get("required_heroes", []):
		if not heroes.has(hid) or int(heroes[hid]["owner"]) != player_idx:
			errors.append("required hero %s must belong to scenario player" % hid)
	for tid in sc.get("protected_towns", []):
		if not towns.has(tid) or int(towns[tid]["owner"]) != player_idx:
			errors.append("protected town %s must belong to scenario player" % tid)
	for obj in sc["objectives"]:
		if obj["type"] in ["reach", "defeat_hero"]:
			var h: Dictionary = heroes.get(obj["hero"], {})
			if h.is_empty():
				errors.append("unknown objective hero %s" % obj["hero"])
			elif obj["type"] == "reach" and int(h["owner"]) != player_idx:
				errors.append("reach hero must belong to scenario player")
			elif obj["type"] == "defeat_hero" and int(h["owner"]) == player_idx:
				errors.append("defeat target must be another player's hero")
		if obj["type"] == "reach":
			var p: Array = obj["pos"]
			if int(p[0]) >= int(map_def["width"]) or int(p[1]) >= int(map_def["height"]):
				errors.append("reach position outside map")
		if obj["type"] == "control_towns":
			for tid in obj["towns"]:
				if not towns.has(tid):
					errors.append("unknown objective town %s" % tid)
		if obj["type"] == "ally_survives":
			var ally := int(obj["player"])
			if ally >= map_def["players"].size():
				errors.append("ally_survives player is outside map slots")
			else:
				var team := int(map_def["players"][player_idx].get("team", 0))
				if team <= 0 or int(map_def["players"][ally].get("team", 0)) != team:
					errors.append("ally_survives player must start allied with the scenario player")
	return errors
