extends SceneTree
## Head-to-head test of two computer difficulty levels (data/ai_difficulty.json),
## income bonus included. Both sides play the same faction and every seed is
## played twice with the seats swapped, so neither the map nor the faction can
## decide the tally.
##   godot --headless --path . --script res://tools/ai_ladder.gd -- [map] [seeds] [days] [level_a] [level_b] [a_overrides_json] [b_overrides_json] [first_seed]
## map: a map id or "random:<size>:<players>" for a fresh random map per seed.
## Defaults: twin_marches, 10 seeds, 42 days, very_hard against hard. The
## overrides go on top of each level's settings (e.g. to try a tuning).
## An undecided game goes to the side with more worth (troops, buildings and
## resources in gold) if it leads by 25% or more.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id: String = args[0] if args.size() > 0 else "twin_marches"
	var seeds := int(args[1]) if args.size() > 1 else 10
	var days := int(args[2]) if args.size() > 2 else 42
	var level := [String(args[3]) if args.size() > 3 else "very_hard", String(args[4]) if args.size() > 4 else "hard"]
	var overrides := [JSON.parse_string(args[5]) if args.size() > 5 else {}, JSON.parse_string(args[6]) if args.size() > 6 else {}]
	var first := int(args[7]) if args.size() > 7 else 1
	var data := GameData.get_default()
	var tally := {"a": 0, "b": 0, "a_ahead": 0, "b_ahead": 0, "open": 0}
	var t0 := Time.get_ticks_msec()
	for seed_value in range(first, first + seeds):
		for a_seat in 2:
			var entry := _entry(data, map_id)
			var setup := GameSetup.default_setup(entry)
			var faction := String(setup["players"][0].get("faction", "concord"))
			for i in setup["players"].size():
				setup["players"][i]["type"] = "computer"
				setup["players"][i]["faction"] = faction
				setup["players"][i]["difficulty"] = level[0] if i % 2 == a_seat else level[1]
			var game_id := GameSetup.map_id_for(entry, seed_value) if map_id.begins_with("random:") else map_id
			var s := GameSession.new_game(data, game_id, seed_value, setup)
			var side := func(i: int) -> int:
				return 0 if i % 2 == a_seat else 1
			while s.state.day <= days and not s.state.game_over:
				var idx := s.state.current_player
				StrategicAI.new(s, idx, overrides[side.call(idx)]).play_turn()
				s.end_turn()
			var result := "open"
			var worth := [0.0, 0.0]
			for i in s.state.players.size():
				worth[side.call(i)] += _worth(s, i)
			if s.state.game_over:
				var winners: Array = s.game_result().get("winners", [])
				if not winners.is_empty():
					result = "a" if side.call(int(winners[0])) == 0 else "b"
			elif worth[0] >= worth[1] * 1.25:
				result = "a_ahead"
			elif worth[1] >= worth[0] * 1.25:
				result = "b_ahead"
			tally[result] += 1
			print("seed %2d %s in seat %d: %s on day %d (worth %d vs %d)" % [seed_value, level[0], a_seat, result, s.state.day, int(worth[0]), int(worth[1])])
	print("\n%s, %d games, %d days max, %.0fs" % [map_id, seeds * 2, days, (Time.get_ticks_msec() - t0) / 1000.0])
	print("%s (a) against %s (b): a wins %d, b wins %d; undecided: a ahead %d, b ahead %d, even %d" % [
		level[0], level[1], tally["a"], tally["b"], tally["a_ahead"], tally["b_ahead"], tally["open"]])
	quit(0)


func _entry(data: GameData, map_id: String) -> Dictionary:
	if map_id.begins_with("random:"):
		var parts := map_id.split(":")
		return GameSetup.random_entry(data, {"size": parts[1], "players": int(parts[2]), "monsters": "normal", "treasure": "normal"})
	return GameSetup.map_entry(data, map_id)


## Troops (heroes and garrisons), invested buildings and resources, in gold.
func _worth(s: GameSession, player_idx: int) -> float:
	var ai := StrategicAI.new(s, player_idx)
	var v := 0.0
	for h in s.state.heroes_of(player_idx):
		v += ai.army_value(h.army)
	for t in s.towns_of(player_idx):
		v += ai.army_value(Town.garrison(t))
		for building_id in t["built"]:
			v += ai.bundle_value(Town.build_cost(t, building_id, s.data))
	var bank: ResourceBank = s.state.player(player_idx)["resources"]
	for res in s.data.resource_order:
		v += float(bank.get_amount(res)) * ai.resource_value(res)
	return v
