extends SceneTree
## How far a computer player (seat 3) ventures in a 3-player random map where
## the other two seats stand in for humans (they play as `rival_level` AIs):
## the farthest its heroes got from home, the first day one went past 18
## tiles, and how many towns, mines and heroes it took from the others.
##   godot --headless --path . --script res://tools/ai_roam_probe.gd -- [seeds] [days] [level] [rival_level] [size] [verbose] [overrides_json]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 4
	var days := int(args[1]) if args.size() > 1 else 35
	var level := String(args[2]) if args.size() > 2 else "hard"
	var rival := String(args[3]) if args.size() > 3 else "hard"
	var size := String(args[4]) if args.size() > 4 else "m"
	var verbose := args.size() > 5 and args[5] == "1"
	var overrides: Dictionary = JSON.parse_string(args[6]) if args.size() > 6 else {}
	var data := GameData.get_default()
	for seed_value in range(1, seeds + 1):
		var entry := GameSetup.random_entry(data, {"size": size, "players": 3, "monsters": "normal", "treasure": "normal"})
		var setup := GameSetup.default_setup(entry)
		for i in 3:
			setup["players"][i]["type"] = "computer"
			setup["players"][i]["difficulty"] = level if i == 2 else rival
		var s := GameSession.new_game(data, GameSetup.map_id_for(entry, seed_value, setup), seed_value, setup)
		var home: Vector2i = AdventureMap.object_pos(s.towns_of(2)[0])
		var far := 0
		var first_out := -1
		var rival_hits := {}
		while s.state.day <= days and not s.state.game_over:
			var idx := s.state.current_player
			var before := _rival_assets(s, idx)
			var rep := StrategicAI.new(s, idx, overrides if idx == 2 else {}).play_turn()
			if idx == 2:
				for h in s.state.heroes_of(2):
					var d := maxi(absi(h.pos.x - home.x), absi(h.pos.y - home.y))
					far = maxi(far, d)
					if d > 18 and first_out < 0:
						first_out = s.state.day
				for a in rep["actions"]:
					if verbose:
						print("  d%d %s" % [s.state.day, a])
				var after := _rival_assets(s, 2)
				if after < before:
					rival_hits[s.state.day] = before - after
			s.end_turn()
		var hits := 0
		for d in rival_hits: hits += int(rival_hits[d])
		print("seed %d (%s): ai towns %d mines %d heroes %d | farthest %d tiles, left home day %d | rival assets taken %d | game_over %s day %d, defeated %s" % [
			seed_value, String(entry.get("layout_family", "")), s.towns_of(2).size(), s.mines_of(2).size(), s.state.heroes_of(2).size(),
			far, first_out, hits, s.state.game_over, s.state.day, [s.state.player(0)["defeated"], s.state.player(1)["defeated"], s.state.player(2)["defeated"]]])
	quit(0)


## Towns, mines and heroes the two stand-in seats own.
func _rival_assets(s: GameSession, _p: int) -> int:
	var n := 0
	for i in s.state.players.size():
		if i == 2:
			continue
		n += s.towns_of(i).size() + s.mines_of(i).size() + s.state.heroes_of(i).size()
	return n
