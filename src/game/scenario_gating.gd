class_name ScenarioGating
extends RefCounted
## Validator rule for mission maps: no optional goal may be both reachable and
## winnable by the scenario player's starting army within the first week.
## Optional goals are mission sites that can be secured (scenario_site, except
## the nest gate and the plain "goal" marker), quest relics, and objectives
## marked optional (reach and control_towns). A goal passes if it unlocks
## after the window (unlock_day), if no starting hero can walk there within
## the window's movement, or if its own guard beats the starting army.
## Guards on the way that the starting army would lose to block the road;
## guards it would beat are fought and passed (generously, without losses),
## so the rule errs towards flagging a goal as too easy.
##
## Phase 2 mission recipes and campaign builders call week_one_problems() on a
## fresh session; it is not wired into ScenarioRules.validate because it needs
## combat forecasts.

const WINDOW_DAYS := 7
## The starting army "wins" a guard fight at or above this forecast.
const WIN_THRESHOLD := 0.5
const SIMULATIONS := 24


## Human-readable problems, [] if every optional goal is gated. Read-only.
static func week_one_problems(session: GameSession, days: int = WINDOW_DAYS) -> Array[String]:
	var problems: Array[String] = []
	var st := session.state
	var sc := ScenarioRules.definition(st)
	if sc.is_empty():
		return problems
	var player_idx := int(sc.get("player", 0))
	var heroes := st.heroes_of(player_idx)
	heroes.sort_custom(func(a, b): return a.id < b.id)
	if heroes.is_empty():
		return problems
	var goals := optional_goals(session)
	if goals.is_empty():
		return problems
	var flagged := {}
	for h in heroes:
		var beatable := {}
		var blocked := {}
		for id in _sorted_ids(st):
			var o: Dictionary = st.map.objects[id]
			if _is_guard(session, o, player_idx) and not _wins(session, h, String(id), beatable):
				blocked[AdventureMap.object_pos(o)] = true
		for hh in st.heroes.values():
			if hh.alive and hh != h and not st.allied(hh.owner, player_idx):
				blocked[hh.pos] = true
		var field := AiDistanceField.build(st.map, h.pos, blocked)
		var budget: int = h.max_movement(session.data) * days
		for g in goals:
			if int(g["unlock_day"]) > days or flagged.has(g["label"]):
				continue
			var cost: int = field.cost_to(g["pos"])
			if cost < 0 or cost > budget:
				continue
			var guard := String(g.get("guard", ""))
			if guard != "" and not _wins(session, h, guard, beatable):
				continue
			flagged[g["label"]] = true
			problems.append("%s is reachable (%d of %d movement) and winnable by %s's starting army in week 1" % [g["label"], cost, budget, h.name])
	return problems


## Optional goals: [{label, pos: Vector2i, unlock_day, guard: object id or ""}].
static func optional_goals(session: GameSession) -> Array:
	var st := session.state
	var sc := ScenarioRules.definition(st)
	var out := []
	for id in _sorted_ids(st):
		var o: Dictionary = st.map.objects[id]
		match String(o.get("type", "")):
			"scenario_site":
				if String(o.get("kind", "")) in ["goal", "nest"] or bool(o.get("claimed", false)):
					continue
				var guard := String(id) if not (o.get("guard", []) as Array).is_empty() else String(o.get("guarded_by", ""))
				out.append({"label": "Mission site %s" % o.get("name", id), "pos": AdventureMap.object_pos(o),
					"unlock_day": int(o.get("unlock_day", 1)), "guard": guard if st.map.objects.has(guard) else ""})
			"quest_item":
				var guardian := String(o.get("guarded_by", ""))
				out.append({"label": "Quest relic %s" % o.get("name", id), "pos": AdventureMap.object_pos(o),
					"unlock_day": int(o.get("unlock_day", 1)), "guard": guardian if st.map.objects.has(guardian) else ""})
	for obj in sc.get("objectives", []):
		if not bool(obj.get("optional", false)):
			continue
		match String(obj["type"]):
			"reach":
				out.append({"label": "Optional goal %s" % obj["id"], "pos": Vector2i(int(obj["pos"][0]), int(obj["pos"][1])),
					"unlock_day": int(obj.get("unlock_day", 1)), "guard": ""})
			"control_towns":
				for tid in obj["towns"]:
					var t := session.town(String(tid))
					if not t.is_empty() and int(t["owner"]) != int(sc.get("player", 0)):
						out.append({"label": "Optional goal %s (%s)" % [obj["id"], t.get("name", tid)], "pos": AdventureMap.object_pos(t),
							"unlock_day": int(obj.get("unlock_day", 1)), "guard": String(tid)})
	return out


static func _sorted_ids(st: GameState) -> Array:
	var ids := st.map.objects.keys()
	ids.sort()
	return ids


## Objects a hero must fight to pass or enter.
static func _is_guard(session: GameSession, o: Dictionary, player_idx: int) -> bool:
	match String(o.get("type", "")):
		"neutral_army":
			return true
		"town":
			return not session.allied(int(o["owner"]), player_idx) and not Town.garrison(o).is_empty()
		"mine", "site", "scenario_site":
			return not (o.get("guard", []) as Array).is_empty()
	return false


static func _wins(session: GameSession, h: Hero, target_id: String, cache: Dictionary) -> bool:
	if cache.has(target_id):
		return cache[target_id]
	var won := false
	var tgt := session.battle_target(target_id)
	if not tgt.is_empty() and not h.army.is_empty():
		var setup := session.battle_setup(h.id, target_id)
		if (setup["sides"][1]["stacks"] as Array).is_empty():
			won = true
		else:
			won = float(CombatPredictor.new(session.data).predict(setup, SIMULATIONS)["win_probability"]) >= WIN_THRESHOLD
	cache[target_id] = won
	return won
