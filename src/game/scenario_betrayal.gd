class_name ScenarioBetrayal
extends RefCounted
## A scripted change of sides (scenario "betrayal"): an ally of the scenario
## player leaves the alliance and joins another player's team once a trigger
## fires. Definition, in rules.scenario:
##   betrayal: {
##     player: the traitor (must start allied with the scenario player),
##     joins: the player whose side it takes (usually the common enemy),
##     trigger: {day?: N (from the start of day N),
##               towns_lost?: P (player P holds no town any more),
##               reach?: {pos: [x, y], radius?: r} (a hero of the scenario
##                       player within r tiles of pos),
##               towns_taken?: {towns: [town ids], count?: n, by?: P} (player P,
##                       default the scenario player, and its allies hold at
##                       least n of these towns, default all of them; with
##                       by = the common enemy and the player's own towns it
##                       fires when the player loses a town)} - the first one met fires,
##     text?: the news line shown to the scenario player,
##     reinforcements?: [[creature, count]] added to the traitor's first town
##                      (by id) when it turns, so a weak ally becomes a threat,
##   }
## Objectives may carry after_betrayal: true (they cannot be completed, and are
## not listed, before the betrayal). The betrayal is saved in
## scenario_runtime.betrayal = {day} (save version 20).


static func definition(st: GameState) -> Dictionary:
	return ScenarioRules.definition(st).get("betrayal", {})


static func happened(st: GameState) -> bool:
	return st.scenario_runtime.has("betrayal")


static func day(st: GameState) -> int:
	return int(st.scenario_runtime.get("betrayal", {}).get("day", 0))


## Fires the betrayal if its trigger is met. Safe to call any time; runs from
## VictoryRules.update (after moves, battles and captures) and at every new day.
static func check(session: GameSession) -> bool:
	var st := session.state
	var b := definition(st)
	if b.is_empty() or happened(st) or st.game_over:
		return false
	if not triggered(session):
		return false
	fire(session)
	return true


static func triggered(session: GameSession) -> bool:
	var st := session.state
	var b := definition(st)
	var trigger: Dictionary = b.get("trigger", {})
	if trigger.has("day") and st.day >= int(trigger["day"]):
		return true
	if trigger.has("towns_lost"):
		var p := int(trigger["towns_lost"])
		if session.towns_of(p).is_empty():
			return true
	if trigger.has("towns_taken"):
		var taken: Dictionary = trigger["towns_taken"]
		var player_idx := int(taken.get("by", ScenarioRules.definition(st).get("player", 0)))
		var held := 0
		for id in taken["towns"]:
			var town := session.town(String(id))
			if not town.is_empty() and int(town["owner"]) >= 0 and st.allied(int(town["owner"]), player_idx):
				held += 1
		if held >= int(taken.get("count", (taken["towns"] as Array).size())):
			return true
	if trigger.has("reach"):
		var reach: Dictionary = trigger["reach"]
		var at := Vector2i(int(reach["pos"][0]), int(reach["pos"][1]))
		var r := int(reach.get("radius", 0))
		for h in st.heroes_of(int(ScenarioRules.definition(st).get("player", 0))):
			if maxi(absi(h.pos.x - at.x), absi(h.pos.y - at.y)) <= r:
				return true
	return false


## The traitor takes the joined player's team (a free team is opened for the
## two if that player has none). Allied vision ends by itself because it is
## derived from teams.
static func fire(session: GameSession) -> void:
	var st := session.state
	var b := definition(st)
	var traitor := int(b["player"])
	var joins := int(b["joins"])
	var team := st.team_of(joins)
	if team <= 0:
		team = _free_team(st)
		st.player(joins)["team"] = team
	st.player(traitor)["team"] = team
	st.scenario_runtime["betrayal"] = {"day": st.day}
	var reinforcements: Array = b.get("reinforcements", [])
	var towns := session.towns_of(traitor)
	if not reinforcements.is_empty() and not towns.is_empty():
		var town: Dictionary = towns[0]
		for t in towns:
			if String(t["id"]) < String(town["id"]):
				town = t
		var garrison := Town.garrison(town)
		for pair in reinforcements:
			garrison.add(String(pair[0]), int(pair[1]))
		Town.set_garrison(town, garrison)
	var text := String(b.get("text", ""))
	if text == "":
		text = "%s breaks the alliance and marches with %s!" % [st.player(traitor)["name"], st.player(joins)["name"]]
	var player_idx := int(ScenarioRules.definition(st).get("player", 0))
	session._add_news(st.player(player_idx), text)
	session.message.emit(text)


static func _free_team(st: GameState) -> int:
	for team in range(1, GameSetup.MAX_TEAMS + 1):
		var used := false
		for p in st.players:
			if int(p.get("team", 0)) == team:
				used = true
		if not used:
			return team
	return GameSetup.MAX_TEAMS + 1


## Schema checks (map_def: the map with its players, for index and team checks).
static func validate(sc: Dictionary, map_def: Dictionary, data: GameData = null) -> Array[String]:
	var errors: Array[String] = []
	var value: Variant = sc.get("betrayal", {})
	if typeof(value) != TYPE_DICTIONARY:
		return ["betrayal must be a dictionary"]
	var b: Dictionary = value
	var uses := false
	for obj in sc.get("objectives", []):
		if typeof(obj) == TYPE_DICTIONARY and bool(obj.get("after_betrayal", false)):
			uses = true
	if b.is_empty():
		if uses:
			errors.append("after_betrayal objectives need a betrayal")
		return errors
	for key in ["player", "joins"]:
		if not ScenarioRules._whole(b.get(key, null), 0):
			errors.append("betrayal needs a %s index" % key)
	if not errors.is_empty():
		return errors
	var player_idx := int(sc.get("player", 0))
	var traitor := int(b["player"])
	var joins := int(b["joins"])
	if traitor == player_idx or joins == player_idx or traitor == joins:
		errors.append("betrayal needs a traitor and a side other than the scenario player")
	if typeof(b.get("text", "")) != TYPE_STRING:
		errors.append("betrayal text must be a string")
	var trigger: Variant = b.get("trigger", null)
	if typeof(trigger) != TYPE_DICTIONARY or trigger.is_empty():
		errors.append("betrayal needs a trigger")
	else:
		for key in trigger:
			if key not in ["day", "towns_lost", "reach", "towns_taken"]:
				errors.append("unknown betrayal trigger %s" % key)
		if trigger.has("day") and not ScenarioRules._whole(trigger["day"], 2):
			errors.append("betrayal day must be 2 or later")
		if trigger.has("towns_lost") and not ScenarioRules._whole(trigger["towns_lost"], 0):
			errors.append("betrayal towns_lost needs a player index")
		if trigger.has("towns_taken"):
			var taken: Variant = trigger["towns_taken"]
			if typeof(taken) != TYPE_DICTIONARY or typeof(taken.get("towns", null)) != TYPE_ARRAY or taken["towns"].is_empty() \
					or not ScenarioRules._whole(taken.get("count", 1), 1) or int(taken.get("count", 1)) > taken["towns"].size():
				errors.append("betrayal towns_taken needs towns [ids] and a count from 1 to their number")
			elif taken.has("by") and (not ScenarioRules._whole(taken["by"], 0) or (not map_def.is_empty() and int(taken["by"]) >= map_def["players"].size())):
				errors.append("betrayal towns_taken by needs a player index")
			elif not map_def.is_empty():
				var town_ids := {}
				for o in map_def.get("objects", []):
					if String(o.get("type", "")) == "town":
						town_ids[String(o["id"])] = true
				for id in taken["towns"]:
					if not town_ids.has(String(id)):
						errors.append("betrayal towns_taken names unknown town %s" % id)
		if trigger.has("reach"):
			var reach: Variant = trigger["reach"]
			if typeof(reach) != TYPE_DICTIONARY or typeof(reach.get("pos", null)) != TYPE_ARRAY or reach["pos"].size() != 2 \
					or not ScenarioRules._whole(reach["pos"][0], 0) or not ScenarioRules._whole(reach["pos"][1], 0) \
					or not ScenarioRules._whole(reach.get("radius", 0), 0):
				errors.append("betrayal reach needs pos [x, y] and an optional radius")
			elif not map_def.is_empty() and (int(reach["pos"][0]) >= int(map_def["width"]) or int(reach["pos"][1]) >= int(map_def["height"])):
				errors.append("betrayal reach position outside map")
	var extra: Variant = b.get("reinforcements", [])
	if typeof(extra) != TYPE_ARRAY:
		errors.append("betrayal reinforcements must be an array")
	else:
		for pair in extra:
			if typeof(pair) != TYPE_ARRAY or pair.size() != 2 or not ScenarioRules._whole(pair[1], 1) \
					or (data != null and not data.creatures.has(pair[0])):
				errors.append("invalid betrayal reinforcement")
	if not map_def.is_empty():
		var players: Array = map_def["players"]
		for idx in [traitor, joins]:
			if idx >= players.size():
				errors.append("betrayal player outside map slots")
		if trigger is Dictionary and trigger.has("towns_lost") and int(trigger["towns_lost"]) >= players.size():
			errors.append("betrayal towns_lost player outside map slots")
		if errors.is_empty():
			var team := int(players[player_idx].get("team", 0))
			if team <= 0 or int(players[traitor].get("team", 0)) != team:
				errors.append("the traitor must start allied with the scenario player")
			if team > 0 and int(players[joins].get("team", 0)) == team:
				errors.append("the betrayal must join a rival of the scenario player")
	return errors


## Runtime record checks for saves.
static func validate_runtime(value: Variant) -> Array[String]:
	if typeof(value) != TYPE_DICTIONARY or not value.has("betrayal"):
		return []
	var rec: Variant = value["betrayal"]
	if typeof(rec) != TYPE_DICTIONARY or not ScenarioRules._whole(rec.get("day", null), 1):
		return ["runtime betrayal must be {day}"]
	return []
