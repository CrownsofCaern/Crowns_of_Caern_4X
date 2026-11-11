extends SceneTree
## Headless pacing checks using normal commands, not injected army/resources.
## godot --headless --path . --script res://tools/scenario_playtest.gd -- [map] [seed] [passive|expeditions]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id := String(args[0]) if args.size() > 0 else "last_watch"
	var seed_value := int(args[1]) if args.size() > 1 else 7
	var policy := String(args[2]) if args.size() > 2 else "expeditions"
	var data := GameData.get_default()
	var faction := String(args[3]) if args.size() > 3 else "concord"
	var setup := {}
	if faction != "concord":
		var def := data.load_map(map_id)
		setup = GameSetup.default_setup({"slots": GameSetup._slots_from(def["players"])})
		setup["players"][0]["faction"] = faction
	var s := GameSession.new_game(data, map_id, seed_value, setup, {"random_events": false})
	var turns := 0
	while not s.state.game_over and s.state.day <= 70 and turns < 250:
		if s.state.current_player == 0:
			if policy in ["expeditions", "prepared"]:
				if ScenarioRules.definition(s.state).get("mode", "") == "labyrinth":
					_labyrinth_player(s)
				else:
					_player(s, policy == "expeditions")
		else:
			StrategicAI.new(s, s.state.current_player).play_turn()
		s.end_turn()
		turns += 1
	var result := s.game_result()
	print(JSON.stringify({"map": map_id, "seed": seed_value, "policy": policy, "faction": faction, "day": s.state.day, "over": s.state.game_over,
		"reason": result["reason"], "human_won": result["human_won"], "battles": s.state.battles_fought,
		"quests": s.state.scenario_runtime.get("quests", {}), "support": s.state.scenario_runtime.get("flags", {}),
		"waves_spawned": s.state.scenario_runtime.get("spawned", []).size(), "living_invaders": s.state.heroes_of(1).size(), "suppressed": s.state.scenario_runtime.get("suppressed", []), "sealed": s.state.map.objects.get("tunnel_north", {}).get("closed", false)}))
	GameData._default = null
	quit()


func _player(s: GameSession, expeditions: bool = true) -> void:
	var ai := StrategicAI.new(s, 0)
	ai._compute_threats()
	for town in s.towns_of(0):
		ai._build_best(town)
		ai._recruit_all(town, true)
	var h := s.hero("hero_watch")
	if h != null and h.alive:
		if s.state.day >= 30:
			var castle := AdventureMap.object_pos(s.town("town_last_watch"))
			var blocker := s.state.hero_at(castle)
			if blocker != null and blocker.id != h.id and blocker.owner == 0:
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var p: Vector2i = castle + offset
					if s.state.map.is_passable(p) and s.state.hero_at(p) == null:
						s.move_hero(blocker.id, p)
						break
		ai._spend_skill_points(h)
		ai.equip_best(h)
		var here := s.state.map.object_at(h.pos)
		if not here.is_empty() and here["type"] == "town" and int(here["owner"]) == 0:
			ai._consolidate(here, h)
		var objective := _expedition_goal(s, h) if expeditions and s.state.day < 30 else "town_last_watch"
		# Intercept nearby invaders, rather than walking away from a siege.
		for enemy in (s.state.heroes_of(1) if expeditions and s.state.day < 30 else []):
			var route := s.plan_path(h.id, enemy.pos)
			if not route["path"].is_empty() and int(route["total_cost"]) <= h.max_movement(s.data) * 2:
				objective = enemy.id
				break
		_march(s, h, objective)
	for scout in s.state.heroes_of(0):
		if (h == null or scout.id != h.id) and s.state.day < 30:
			ai._run_hero(scout, {"hires": 0, "builds": 0, "recruits": 0, "battles": 0})


func _expedition_goal(s: GameSession, h: Hero) -> String:
	var qstate := ScenarioQuests.status(s.state, "reedhaven_pact")
	if qstate == "available":
		if h.pos == AdventureMap.object_pos(s.state.map.objects["site_pact"]):
			s.scenario_act(h.id, "site_pact", "accept")
		else:
			return "site_pact"
	if ScenarioQuests.status(s.state, "reedhaven_pact") == "active":
		if s.state.map.objects.has("guardian_oath"):
			return "guardian_oath"
		if not ScenarioQuests.items(s.state, h.id).has("reed_oathstone"):
			return "relic_oath"
		if h.pos == AdventureMap.object_pos(s.state.map.objects["site_pact"]):
			s.scenario_act(h.id, "site_pact", "deliver")
		else:
			return "site_pact"
	for id in ["site_forge", "site_nest", "site_camp", "site_watch"]:
		var site: Dictionary = s.state.map.objects[id]
		if bool(site.get("claimed", false)):
			continue
		if h.pos == AdventureMap.object_pos(site) and not s.is_guarded(site, 0):
			s.scenario_act(h.id, id, "seal" if site["kind"] == "nest" else "claim")
		else:
			return id
	return "town_last_watch"


func _march(s: GameSession, h: Hero, target_id: String) -> void:
	for _i in 12:
		if h.movement_left <= 0 or not h.alive or s.state.game_over:
			return
		var enemy := s.hero(target_id)
		var obj: Dictionary = s.state.map.objects.get(target_id, {})
		if enemy == null and obj.is_empty():
			return
		var target: Vector2i = enemy.pos if enemy != null else AdventureMap.object_pos(obj)
		var result := s.move_hero(h.id, target)
		if result["battle"] != "":
			var battle := s.attack(h.id, String(result["battle"]))
			if int(battle["winner"]) != 0:
				return
		elif result["steps"].is_empty() or h.pos == target:
			return


func _labyrinth_player(s: GameSession) -> void:
	var h := s.hero("hero_watch")
	if h == null or not h.alive:
		return
	var ai := StrategicAI.new(s, 0)
	ai._spend_skill_points(h)
	var goal: Dictionary = s.state.map.objects["stone_heart"]
	var plan := s.plan_path(h.id, AdventureMap.object_pos(goal))
	if not plan["path"].is_empty():
		_march(s, h, "stone_heart")
		return
	var target := ""
	var cost := 2147483647
	for id in s.state.map.objects:
		if not String(id).begins_with("maze_guard_"):
			continue
		var route := s.plan_path(h.id, AdventureMap.object_pos(s.state.map.objects[id]))
		if not route["path"].is_empty() and int(route["total_cost"]) < cost:
			target = id
			cost = int(route["total_cost"])
	if target != "":
		_march(s, h, target)
