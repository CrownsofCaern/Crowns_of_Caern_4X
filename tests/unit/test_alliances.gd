extends "res://tests/test_case.gd"
## Teams and alliances: setup, who may fight whom, shared vision, sending
## resources, victory of an alliance, saves, campaign data and the AI.


## Mournfield (4 slots): players 0 and 3 against 1 and 2 by default.
func _game(teams: Array = [1, 2, 2, 1], seed_value: int = 7) -> GameSession:
	var entry := GameSetup.map_entry(data, "mournfield")
	var setup := GameSetup.default_setup(entry)
	for i in teams.size():
		setup["players"][i]["team"] = teams[i]
	return GameSession.new_game(data, "mournfield", seed_value, setup)


func _hero_of(s: GameSession, owner: int) -> Hero:
	return s.state.heroes_of(owner)[0]


func _town_of(s: GameSession, owner: int) -> Dictionary:
	return s.towns_of(owner)[0]


func test_setup_assigns_teams() -> void:
	var s := _game()
	assert_eq(s.state.team_of(0), 1)
	assert_eq(s.state.team_of(3), 1)
	assert_eq(s.state.team_of(1), 2)
	assert_true(s.allied(0, 3))
	assert_true(s.allied(1, 2))
	assert_true(s.allied(2, 2))
	assert_false(s.allied(0, 1))
	assert_false(s.allied(0, -1), "neutral is nobody's ally")
	assert_eq(s.state.allies_of(0), [0, 3] as Array[int])
	assert_eq(s.living_allies(0), [3] as Array[int])


func test_no_teams_means_everyone_alone() -> void:
	var s := GameSession.new_game(data, "mournfield", 3)
	for i in s.state.players.size():
		assert_eq(s.state.team_of(i), 0)
		for j in s.state.players.size():
			assert_eq(s.allied(i, j), i == j)
	assert_true(s.living_allies(0).is_empty())


func test_setup_validation_of_teams() -> void:
	var def := data.load_map("mournfield")
	var all_one := {"players": [{"team": 1}, {"team": 1}, {"team": 1}, {"team": 1}]}
	var text := "\n".join(GameSetup.validate(def, all_one, data))
	assert_true(text.contains("same team"), text)
	var bad := {"players": [{"team": GameSetup.MAX_TEAMS + 1}]}
	text = "\n".join(GameSetup.validate(def, bad, data))
	assert_true(text.contains("team must be"), text)
	# One team plus a closed slot and a player alone is fine.
	var ok := {"players": [{"team": 1}, {"type": "closed"}, {"team": 0}, {"team": 1}]}
	assert_true(GameSetup.validate(def, ok, data).is_empty())
	# Closing a slot keeps the other players' teams on their new indices.
	var applied := GameSetup.apply(def, ok, data)
	assert_eq(int(applied["players"][2]["team"]), 1)
	assert_eq(int(applied["players"][1]["team"]), 0)


func test_send_resources_to_an_ally() -> void:
	var s := _game()
	var mine: ResourceBank = s.state.player(0)["resources"]
	var theirs: ResourceBank = s.state.player(3)["resources"]
	var gold0 := mine.get_amount("gold")
	var gold3 := theirs.get_amount("gold")
	var wood3 := theirs.get_amount("wood")
	var r := s.send_resources(3, {"gold": 700, "wood": 2})
	assert_true(r["ok"], r.get("reason", ""))
	assert_eq(r["sent"], {"gold": 700, "wood": 2})
	assert_eq(mine.get_amount("gold"), gold0 - 700)
	assert_eq(theirs.get_amount("gold"), gold3 + 700)
	assert_eq(theirs.get_amount("wood"), wood3 + 2)


func test_send_resources_refusals_change_nothing() -> void:
	var s := _game()
	var mine: ResourceBank = s.state.player(0)["resources"]
	var before := mine.to_dict()
	assert_eq(s.send_resources(1, {"gold": 10})["reason"], "not an ally")
	assert_eq(s.send_resources(0, {"gold": 10})["reason"], "not an ally")
	assert_eq(s.send_resources(3, {"gold": mine.get_amount("gold") + 1})["reason"], "not enough Gold")
	assert_eq(s.send_resources(3, {"gold": 0})["reason"], "nothing to send")
	assert_eq(s.send_resources(3, {"gold": -5})["reason"], "invalid amount")
	assert_eq(s.send_resources(3, {"stardust": 5})["reason"], "unknown resource stardust")
	assert_eq(s.send_resources(9, {"gold": 5})["reason"], "not an ally")
	VictoryRules.eliminate(s, 3, "test")
	assert_eq(s.send_resources(3, {"gold": 5})["reason"], "that ally is out of the game")
	assert_eq(mine.to_dict(), before)


func test_allies_cannot_fight_or_capture() -> void:
	var s := _game()
	var h := _hero_of(s, 0)
	var ally := _hero_of(s, 3)
	var ally_town := _town_of(s, 3)
	# Next to the allied hero: it blocks the way and is no battle target.
	h.pos = ally.pos + Vector2i(1, 0)
	h.movement_left = 2000
	var mv := s.move_hero(h.id, ally.pos)
	assert_eq(mv["battle"], "")
	assert_eq(h.pos, ally.pos + Vector2i(1, 0))
	var r := s.attack(h.id, ally.id)
	assert_false(r.get("ok", true))
	assert_true(ally.alive)
	# The allied town is not guarded against us, but we can neither enter nor take it.
	var tp := AdventureMap.object_pos(ally_town)
	assert_false(s.is_guarded(ally_town, 0))
	assert_true(s.is_allied_town(ally_town, 0))
	assert_false(s.is_allied_town(ally_town, 3), "a player's own town is not an allied town")
	ally.pos = tp + Vector2i(0, 3)   # out of the way
	h.pos = tp + Vector2i(1, 0)
	mv = s.move_hero(h.id, tp)
	assert_eq(mv["battle"], "")
	assert_true(mv["captured"].is_empty())
	assert_eq(int(ally_town["owner"]), 3)
	assert_ne(h.pos, tp)
	assert_false(s.attack(h.id, ally_town["id"]).get("ok", true))
	assert_eq(int(ally_town["owner"]), 3)
	# An enemy town is still a fight (or a capture).
	assert_false(s.allied(0, 1))
	assert_true(s.can_fight(0, s.battle_target(_town_of(s, 1)["id"])))


func test_allied_heroes_are_no_threat() -> void:
	var s := _game()
	var t := _town_of(s, 0)
	var ally := _hero_of(s, 3)
	var foe := _hero_of(s, 1)
	ally.pos = AdventureMap.object_pos(t) + Vector2i(2, 0)
	foe.pos = AdventureMap.object_pos(t) + Vector2i(0, 2)
	var fog: FogOfWar = s.state.player(0)["fog"]
	fog.reveal(AdventureMap.object_pos(t), 6)
	var ids := []
	for th in s.town_threats(0):
		ids.append(th["hero_id"])
	assert_false(ids.has(ally.id), str(ids))
	assert_true(ids.has(foe.id), str(ids))


func test_allies_share_vision() -> void:
	var s := _game()
	var h := _hero_of(s, 0)
	var ally_fog: FogOfWar = s.state.player(3)["fog"]
	var foe_fog: FogOfWar = s.state.player(1)["fog"]
	assert_true(ally_fog.is_explored(h.pos), "starting heroes reveal for allies too")
	var target := Vector2i(14, 6)
	assert_false(foe_fog.is_explored(h.pos))
	h.pos = target
	s._reveal_around(h)
	assert_true(ally_fog.is_explored(target))
	assert_false(foe_fog.is_explored(target))


func test_alliance_wins_together() -> void:
	var s := _game()
	VictoryRules.eliminate(s, 1, "test")
	VictoryRules.update(s)
	assert_false(s.state.game_over, "player 2 still fights on")
	VictoryRules.eliminate(s, 2, "test")
	VictoryRules.update(s)
	assert_true(s.state.game_over)
	assert_eq(s.state.end_reason, "conquest")
	assert_eq(s.state.winner, 0)
	var res := s.game_result()
	assert_eq(res["winners"], [0, 3] as Array[int])
	assert_true(res["human_won"])
	assert_eq(res["title"], "Victory")
	assert_true(String(res["text"]).contains(" and "), res["text"])
	var won := 0
	for row in res["standings"]:
		if row["won"]:
			won += 1
	assert_eq(won, 2)
	assert_true(res["standings"][0]["won"] and res["standings"][1]["won"], "winners are listed first")


func test_human_ally_of_a_computer_winner_wins() -> void:
	# Human (0) and computer (3) are allied; the computer ally finishes the last
	# enemy on its own turn: the human wins and the end screen is theirs.
	var s := _game()
	VictoryRules.eliminate(s, 2, "test")
	s.state.current_player = 3
	VictoryRules.eliminate(s, 1, "test")
	VictoryRules.update(s)
	assert_true(s.state.game_over)
	assert_eq(s.state.current_player, 0, "the end screen belongs to the human winner")
	assert_true(s.game_result()["human_won"])


func test_teams_survive_save_and_load() -> void:
	var s := _game([2, 0, 0, 2])
	var d := s.state.to_dict()
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	assert_eq(int(d["players"][3]["team"]), 2)
	var back := GameSession.from_state(data, GameState.from_dict(JSON.parse_string(JSON.stringify(d)), data))
	assert_true(back.allied(0, 3))
	assert_false(back.allied(1, 2), "team 0 players stand alone")
	# Saves from before teams have no alliances.
	for p in d["players"]:
		p.erase("team")
	d["version"] = 9
	var old := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_false(old.allied(0, 3))
	assert_eq(old.state.team_of(0), 0)


func test_campaign_setup_validates_teams() -> void:
	var ch := {"setup": {"players": [{"type": "human", "team": 1}, {"type": "computer", "team": 9}, {"team": "x"}]}}
	var text := "\n".join(Campaign._validate_setup(ch, data))
	assert_true(text.contains("invalid team 9"), text)
	assert_true(text.contains("invalid team x"), text)
	ch = {"setup": {"players": [{"type": "human", "team": 0}, {"type": "computer", "team": 1}, {"team": 1}]}}
	assert_true(Campaign._validate_setup(ch, data).is_empty())
	var errors := Campaign.validate(data)
	assert_true(errors.is_empty(), "\n".join(errors))


## Computer allies never attack each other or each other's towns and mines.
func test_ai_respects_alliances() -> void:
	for seed_value in [1, 2]:
		var s := _game([1, 2, 2, 1], seed_value)
		for p in s.state.players:
			p["is_human"] = false
		var owners := {}
		for id in s.state.map.objects:
			var o: Dictionary = s.state.map.objects[id]
			if o["type"] in ["town", "mine"]:
				owners[id] = int(o["owner"])
		var fights := []
		s.battle_resolved.connect(func(r):
			var attacker: int = s.hero(r["hero_id"]).owner
			var defender_hero: String = r["defender_hero_id"]
			if defender_hero != "":
				fights.append([attacker, s.hero(defender_hero).owner]))
		var last_day := 15
		while s.state.day < last_day and not s.state.game_over:
			var me := s.state.current_player
			StrategicAI.new(s, me).play_turn()
			for id in owners:
				var o: Dictionary = s.state.map.objects.get(id, {})
				if o.is_empty():
					continue
				var before := int(owners[id])
				var now := int(o["owner"])
				if now != before and before >= 0:
					assert_false(s.allied(now, before), "seed %d day %d: %s passed between allies %d -> %d" % [seed_value, s.state.day, id, before, now])
				owners[id] = now
			s.end_turn()
		for f in fights:
			assert_false(s.allied(f[0], f[1]), "seed %d: allies %d and %d fought" % [seed_value, f[0], f[1]])


## Stepping onto an ally's dwelling site leaves it theirs; the AI does not want it.
func test_allied_dwelling_site_is_not_taken() -> void:
	var s := _game()
	var h := _hero_of(s, 0)
	var sid := ""
	var ids: Array = data.sites.keys()
	ids.sort()
	for k in ids:
		if data.sites[k]["kind"] == "dwelling":
			sid = k
			break
	assert_ne(sid, "")
	var p := s._free_tile_near(h.pos)
	var o := {"id": "ally_site", "type": "site", "site": sid, "pos": [p.x, p.y], "owner": 3}
	s.state.map.add_object(o)
	MapSites.normalize(o, data)
	h.movement_left = 2000
	var mv := s.move_hero(h.id, p)
	assert_true(mv["captured"].is_empty(), str(mv))
	assert_eq(int(o["owner"]), 3)
	assert_eq(StrategicAI.new(s, 0).site_value(h, o), 0.0)
	o["owner"] = 1
	assert_gt(StrategicAI.new(s, 0).site_value(h, o), 0.0, "an enemy's dwelling is worth taking")
