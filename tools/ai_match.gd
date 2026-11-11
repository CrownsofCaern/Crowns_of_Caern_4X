extends SceneTree
## Headless AI-versus-AI match on a map where every player is a computer:
##   godot --headless --path . --script res://tools/ai_match.gd -- [map_id] [seed] [days] [verbose]
## Prints a per-day summary (and every AI action with verbose=1) and the result.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id: String = args[0] if args.size() > 0 else "twin_marches"
	var seed_value := int(args[1]) if args.size() > 1 else 1
	var days := int(args[2]) if args.size() > 2 else 28
	var verbose := args.size() > 3 and args[3] == "1"
	var data := GameData.get_default()
	var session := GameSession.new_game(data, map_id, seed_value)
	for p in session.state.players:
		p["is_human"] = false
	var t0 := Time.get_ticks_msec()
	while session.state.day <= days and not session.state.game_over:
		var idx := session.state.current_player
		var ai := StrategicAI.new(session, idx)
		var t := Time.get_ticks_msec()
		var rep := ai.play_turn()
		var p := session.current_player()
		var heroes := session.state.heroes_of(idx)
		var army := 0.0
		for h in heroes:
			army += ai.army_value(h.army)
		print("day %2d %-11s %4d ms  towns %d mines %d heroes %d army %6d gold %6d  battles %d builds %d" % [
			session.state.day, p["name"], Time.get_ticks_msec() - t, session.towns_of(idx).size(),
			session.mines_of(idx).size(), heroes.size(), int(army), p["resources"].get_amount("gold"),
			rep["battles"], rep["builds"]])
		if verbose:
			for a in rep["actions"]:
				print("        " + a)
		session.end_turn()
	print("\nday %d, game over: %s, %.1fs" % [session.state.day, session.state.game_over, (Time.get_ticks_msec() - t0) / 1000.0])
	for i in session.state.players.size():
		var p := session.state.player(i)
		print("%s: defeated=%s towns=%d mines=%d heroes=%d ultimates=%s" % [p["name"], p["defeated"], session.towns_of(i).size(),
			session.mines_of(i).size(), session.state.heroes_of(i).size(), ", ".join(session.army_upgrades(i).keys())])
	quit(0)
