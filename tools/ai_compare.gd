extends SceneTree
## Head-to-head test of the strategic AI against its older self: the "old" AI is
## the current one with spells, stack upgrades, road traders and ally gifts
## switched off (exactly the AI before those were added). Every seed is played
## twice with the sides swapped.
##   godot --headless --path . --script res://tools/ai_compare.gd -- [map] [seeds] [days] [new_overrides_json]
## map: a map id (default twin_marches), "random:<size>:<players>" for a fresh
## random map per seed, or "random:<size>:4:teams" for two alliances of two.

const OLD := {"casts_spells": false, "upgrades": false, "trades_at_sites": false, "ally_gifts": false}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var map_arg: String = args[0] if args.size() > 0 else "twin_marches"
	var seeds := int(args[1]) if args.size() > 1 else 10
	var days := int(args[2]) if args.size() > 2 else 42
	var new_ai: Dictionary = JSON.parse_string(args[3]) if args.size() > 3 else {}
	var data := GameData.get_default()
	var tally := {"new": 0, "old": 0, "open": 0}
	var stats := {"new": {"towns": 0.0, "army": 0.0, "spells": 0, "upgrades": 0, "purchases": 0, "gifts": 0},
		"old": {"towns": 0.0, "army": 0.0, "spells": 0, "upgrades": 0, "purchases": 0, "gifts": 0}}
	var t0 := Time.get_ticks_msec()
	for seed_value in range(1, seeds + 1):
		for new_side in 2:
			var s := _session(data, map_arg, seed_value)
			var side_of := func(i: int) -> String:
				return "new" if i % 2 == new_side else "old"   # teams are also split by parity
			while s.state.day <= days and not s.state.game_over:
				var idx := s.state.current_player
				var who: String = side_of.call(idx)
				var rep := StrategicAI.new(s, idx, new_ai if who == "new" else OLD).play_turn()
				for k in ["spells", "upgrades", "purchases", "gifts"]:
					stats[who][k] += int(rep[k])
				s.end_turn()
			var result := "open"
			if s.state.game_over:
				var winners: Array = s.game_result().get("winners", [])
				if not winners.is_empty():
					result = side_of.call(int(winners[0]))
			tally[result] += 1
			var ai := StrategicAI.new(s, 0)
			for i in s.state.players.size():
				var who: String = side_of.call(i)
				stats[who]["towns"] += s.towns_of(i).size()
				for h in s.state.heroes_of(i):
					stats[who]["army"] += ai.army_value(h.army)
				for t in s.towns_of(i):
					stats[who]["army"] += ai.army_value(Town.garrison(t))
			print("seed %2d new=%s: %s on day %d" % [seed_value, "even" if new_side == 0 else "odd", result, s.state.day])
	var games := seeds * 2
	print("\n%s, %d games, %d days max, %.0fs" % [map_arg, games, days, (Time.get_ticks_msec() - t0) / 1000.0])
	print("wins: new AI %d, old AI %d, undecided %d" % [tally["new"], tally["old"], tally["open"]])
	for who in ["new", "old"]:
		var st: Dictionary = stats[who]
		print("%s AI: towns at end %.2f, army value at end %d (per game); spells %d, upgrades %d, purchases %d, gifts %d" % [
			who, st["towns"] / games, int(st["army"] / games), st["spells"], st["upgrades"], st["purchases"], st["gifts"]])
	quit(0)


func _session(data: GameData, map_arg: String, seed_value: int) -> GameSession:
	var s: GameSession
	if map_arg.begins_with("random:"):
		var parts := map_arg.split(":")
		var entry := GameSetup.random_entry(data, {"size": parts[1], "players": int(parts[2]), "monsters": "normal", "treasure": "normal"})
		var setup := GameSetup.default_setup(entry)
		for i in setup["players"].size():
			setup["players"][i]["type"] = "computer"
			if parts.size() > 3 and parts[3] == "teams":
				setup["players"][i]["team"] = 1 + i % 2
		s = GameSession.new_game(data, GameSetup.map_id_for(entry, seed_value), seed_value, setup)
	else:
		s = GameSession.new_game(data, map_arg, seed_value)
	for p in s.state.players:
		p["is_human"] = false
	return s
