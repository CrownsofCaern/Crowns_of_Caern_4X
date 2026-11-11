extends SceneTree
## Headless balance probes for the map-overhaul scenarios (docs/DESIGN.md 5a).
##
##   godot --headless --path . --script res://tools/scenario_probe.gd -- townless [recipe] [seeds] [fights] [out.md]
##     Builds the recipe (default townless_v1) for seeds 1..N and checks the
##     townless targets with `fights` seeded battles each (default 200):
##     the starting army alone beats the town < 50%, the starting gold buys
##     about 60-70% of all village stock, and the best affordable army wins
##     every fight with moderate losses.
##
##   godot --headless --path . --script res://tools/scenario_probe.gd -- match <game> [runs] [days] [passive_player] [out.md]
##     AI-only runs of a map id, scenario id or campaign chapter
##     ("campaign:<id>:<chapter index>"), every player a computer. Reports the
##     end, each player's elimination day and the betrayal day. passive_player
##     (an index, -1 = none) plays passively: "the ally lasts 3 weeks without
##     help" / "without help the ally falls by week 3" checks.
##
##   godot --headless --path . --script res://tools/scenario_probe.gd -- townless_chapter <game> <town_id> [fights] [out.md]
##     The townless targets on an authored map or campaign chapter
##     ("campaign:<id>:<chapter index>"): the scenario player's strongest
##     starting hero against town_id, alone and with the best army the
##     starting gold buys from every village (sites of kind "village").
##
##   godot --headless --path . --script res://tools/scenario_probe.gd -- gating <game> [out.md]
##     The week-one rule (ScenarioGating): optional goals the starting army
##     can reach and win in the first week.
##
##   godot --headless --path . --script res://tools/scenario_probe.gd -- recipes [seeds] [out.md] [recipe,...]
##     The week-one rule over seeds 1..N (default 20) of every recipe the menus
##     offer (or the listed ones), plus when each optional goal opens: its
##     unlock day, or for held sites whether the starting army (should lose)
##     and the army after three weeks of castle growth (should win) beat the
##     guard. Target: no goal before day 8, most by day 30.
##
## Every number comes from fixed seeds, so a report is reproducible.

var data: GameData


func _init() -> void:
	data = GameData.get_default()
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "townless"
	var lines: Array[String] = []
	match mode:
		"townless":
			var recipe: String = args[1] if args.size() > 1 else "townless_v1"
			var seeds := int(args[2]) if args.size() > 2 else 10
			var fights := int(args[3]) if args.size() > 3 else 200
			lines = townless(recipe, seeds, fights)
			_write(lines, args[4] if args.size() > 4 else "")
		"match":
			var game: String = args[1] if args.size() > 1 else "twin_marches"
			var runs := int(args[2]) if args.size() > 2 else 20
			var days := int(args[3]) if args.size() > 3 else 28
			var passive := int(args[4]) if args.size() > 4 else -1
			lines = matches(game, runs, days, passive)
			_write(lines, args[5] if args.size() > 5 else "")
		"townless_chapter":
			var fights := int(args[3]) if args.size() > 3 else 200
			lines = townless_chapter(args[1], args[2], fights)
			_write(lines, args[4] if args.size() > 4 else "")
		"gating":
			var game: String = args[1] if args.size() > 1 else "scenario:survival_v1:1"
			lines = gating(game)
			_write(lines, args[2] if args.size() > 2 else "")
		"recipes":
			var seeds := int(args[1]) if args.size() > 1 else 20
			var only: Array = Array(String(args[3]).split(",")) if args.size() > 3 else []
			lines = recipes(seeds, only)
			_write(lines, args[2] if args.size() > 2 else "")
		_:
			print("unknown mode %s" % mode)
	quit(0)


func _write(lines: Array[String], path: String) -> void:
	var text := "\n".join(lines)
	print(text)
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text + "\n")


# ---------------------------------------------------------------- townless --

func townless(recipe: String, seeds: int, fights: int) -> Array[String]:
	var out: Array[String] = ["# Townless start probe: %s, %d seeds, %d fights each" % [recipe, seeds, fights], "",
		"| seed | villages | stock gold | buys | start army vs town | best army vs town | best army losses |",
		"|---:|---:|---:|---:|---:|---:|---:|"]
	var fails := 0
	for seed_value in range(1, seeds + 1):
		var def := ScenarioGenerator.generate(data, recipe, seed_value)
		if def.is_empty():
			out.append("| %d | build failed | | | | | |" % seed_value)
			fails += 1
			continue
		var r := measure_townless(def, fights)
		var ok: bool = r["start_win"] < 0.5 and r["share"] >= 0.6 and r["share"] <= 0.7 and r["best_win"] >= 1.0 and r["best_loss"] <= 0.4
		if not ok:
			fails += 1
		out.append("| %d | %d | %d | %d%% | %d%% | %d%% | %d%% %s|" % [seed_value, r["villages"], r["stock_gold"], roundi(r["share"] * 100),
			roundi(r["start_win"] * 100), roundi(r["best_win"] * 100), roundi(r["best_loss"] * 100), "" if ok else "**miss** "])
	out.append("")
	out.append("Targets: start army < 50%%, starting gold buys 60-70%% of the stock, best army 100%% with losses at most 40%%. Seeds missing a target: %d of %d." % [fails, seeds])
	return out


## {villages, stock_gold, share, start_win, best_win, best_loss} for a built
## townless map, from `fights` seeded battles in a session on the map.
func measure_townless(def: Dictionary, fights: int) -> Dictionary:
	var sc: Dictionary = def["scenario"]
	var report: Dictionary = sc["townless"]
	var session := GameSession.new_game_from_definition(data, def, 1)
	var player := int(sc["player"])
	var h: Hero = session.state.heroes_of(player)[0]
	var villages: Array = report["villages"].map(func(id): return session.state.map.objects[id])
	var gold := (session.state.player(player)["resources"] as ResourceBank).get_amount("gold")
	var start := h.army.to_combat_stacks().map(func(st): return [st["creature"], int(st["count"])])
	var best := ScenarioTownless.best_purchase(data, start, villages, gold)
	var pred := CombatPredictor.new(data)
	var town := String(report["town"])
	var start_odds := pred.predict(session.battle_setup(h.id, town), fights)
	h.army = Army.from_pairs(best)
	var best_odds := pred.predict(session.battle_setup(h.id, town), fights)
	var stock := ScenarioTownless.stock_gold(data, villages)
	return {"villages": villages.size(), "stock_gold": stock, "share": float(gold) / maxf(1.0, float(stock)),
		"start_win": float(start_odds["win_probability"]), "best_win": float(best_odds["win_probability"]),
		"best_loss": float(best_odds["expected_loss_fraction"])}


## The townless targets on a hand-built map or campaign chapter (see the header).
func townless_chapter(game: String, town: String, fights: int) -> Array[String]:
	var session := start_game(game, 1)
	if session == null or session.town(town).is_empty():
		return ["cannot start %s with town %s" % [game, town]]
	var player := int(ScenarioRules.definition(session.state).get("player", 0))
	var heroes := session.state.heroes_of(player)
	heroes.sort_custom(func(a: Hero, b: Hero) -> bool: return a.id < b.id)
	var h: Hero = heroes[0]
	var best_value := -1.0
	var ai := StrategicAI.new(session, player)
	for cand in heroes:
		var v := ai.army_value(cand.army)
		if v > best_value:
			best_value = v
			h = cand
	var villages: Array = []
	for id in session.state.map.objects:
		var o: Dictionary = session.state.map.objects[id]
		if String(o.get("type", "")) == "site" and data.sites.has(String(o.get("site", ""))) and String(data.sites[String(o["site"])].get("kind", "")) == "village":
			villages.append(o)
	villages.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	var gold := (session.state.player(player)["resources"] as ResourceBank).get_amount("gold")
	var start := h.army.to_combat_stacks().map(func(st): return [st["creature"], int(st["count"])])
	var best := ScenarioTownless.best_purchase(data, start, villages, gold)
	var pred := CombatPredictor.new(data)
	var start_odds := pred.predict(session.battle_setup(h.id, town), fights)
	h.army = Army.from_pairs(best)
	var best_odds := pred.predict(session.battle_setup(h.id, town), fights)
	var stock := ScenarioTownless.stock_gold(data, villages)
	var share := float(gold) / maxf(1.0, float(stock))
	var ok: bool = float(start_odds["win_probability"]) < 0.5 and share >= 0.6 and share <= 0.7 \
		and float(best_odds["win_probability"]) >= 1.0 and float(best_odds["expected_loss_fraction"]) <= 0.4
	return ["# Townless chapter probe: %s against %s, %d fights" % [game, town, fights], "",
		"| hero | villages | gold | stock gold | buys | start army vs town | best army vs town | best army losses |",
		"|---|---:|---:|---:|---:|---:|---:|---:|",
		"| %s | %d | %d | %d | %d%% | %d%% | %d%% | %d%% |" % [h.id, villages.size(), gold, stock, roundi(share * 100),
			roundi(float(start_odds["win_probability"]) * 100), roundi(float(best_odds["win_probability"]) * 100),
			roundi(float(best_odds["expected_loss_fraction"]) * 100)], "",
		"Targets: start army < 50%%, starting gold buys 60-70%% of the stock, best army 100%% with losses at most 40%%: %s." % ("met" if ok else "**missed**"),
		"Best army: %s" % ", ".join(best.map(func(p): return "%d %s" % [p[1], p[0]]))]


# ------------------------------------------------------------------- match --

## A new session for a map id, generated id or "campaign:<id>:<chapter index>".
func start_game(game: String, seed_value: int) -> GameSession:
	if game.begins_with("campaign:"):
		var parts := game.split(":")
		var camp := Campaign.start(data, parts[1], seed_value)
		camp.chapter = int(parts[2])
		return camp.begin_chapter(data)
	return GameSession.new_game(data, game, seed_value)


func matches(game: String, runs: int, days: int, passive: int) -> Array[String]:
	var out: Array[String] = ["# AI-only probe: %s, %d runs, up to day %d%s" % [game, runs, days,
		", player %d passive" % passive if passive >= 0 else ""], ""]
	var first := start_game(game, 1)
	if first == null:
		return ["cannot start %s" % game]
	var header := "| run | end | day | betrayal |"
	var rule := "|---:|---|---:|---:|"
	for p in first.state.players:
		header += " %s out |" % p["name"]
		rule += "---:|"
	out.append(header)
	out.append(rule)
	var early_end := 0
	var out_days := {}
	for run in range(1, runs + 1):
		var session := start_game(game, run)
		for p in session.state.players:
			p["is_human"] = false
		if passive >= 0:
			session.state.player(passive)["difficulty"] = "passive"
		while session.state.day <= days and not session.state.game_over:
			StrategicAI.new(session, session.state.current_player).play_turn()
			session.end_turn()
		var st := session.state
		if st.game_over and st.day <= 7:
			early_end += 1
		var row := "| %d | %s | %d | %s |" % [run, (st.end_reason if st.game_over else "open") + ("" if st.winner < 0 else " (%s)" % st.player(st.winner)["name"]),
			st.day, str(ScenarioBetrayal.day(st)) if ScenarioBetrayal.happened(st) else "-"]
		for i in st.players.size():
			var d := int(st.player(i)["eliminated_day"])
			row += " %s |" % (str(d) if bool(st.player(i)["defeated"]) else "-")
			if bool(st.player(i)["defeated"]):
				if not out_days.has(i):
					out_days[i] = []
				out_days[i].append(d)
		out.append(row)
	out.append("")
	out.append("Games decided in week 1: %d of %d." % [early_end, runs])
	for i in first.state.players.size():
		var arr: Array = out_days.get(i, [])
		arr.sort()
		out.append("%s eliminated in %d of %d runs%s." % [first.state.player(i)["name"], arr.size(), runs,
			"" if arr.is_empty() else ", earliest day %d, median day %d" % [arr[0], arr[arr.size() / 2]]])
	return out


# ------------------------------------------------------------------ gating --

func gating(game: String) -> Array[String]:
	var session := start_game(game, 1)
	if session == null:
		return ["cannot start %s" % game]
	var problems := ScenarioGating.week_one_problems(session)
	var out: Array[String] = ["# Week-one gating: %s" % game, ""]
	if problems.is_empty():
		out.append("Every optional goal is gated.")
	for p in problems:
		out.append("- " + p)
	return out


# ----------------------------------------------------------------- recipes --

func recipes(seeds: int, only: Array) -> Array[String]:
	var ids: Array = only.duplicate()
	if ids.is_empty():
		for mode in ScenarioGenerator.MODES:
			var r := ScenarioGenerator.current_recipe(data, mode)
			if r != "":
				ids.append(r)
	var out: Array[String] = ["# Mission recipes: week-one gating over seeds 1..%d" % seeds, "",
		"Held sites: starting army (both heroes and the castle garrison) vs the guard, and the same army plus three weeks of castle growth (about day 22). Gated sites open on their unlock day.", "",
		"| recipe | seeds built | week-one problems | optional goals | gated by day | held: start wins (max) | held: day-22 army wins | earliest open day |",
		"|---|---:|---:|---:|---:|---:|---:|---:|"]
	var details: Array[String] = []
	for rid in ids:
		var built := 0
		var problems := 0
		var goals := 0
		var by_day := 0
		var held := 0
		var later_ok := 0
		var start_max := 0.0
		var earliest := 999
		for seed_value in range(1, seeds + 1):
			var id := ScenarioGenerator.make_id(String(rid), "", seed_value)
			var def := data.load_map(id)
			if def.is_empty():
				details.append("- %s: build failed" % id)
				continue
			built += 1
			var session := GameSession.new_game(data, id, seed_value, {}, {"random_events": false})
			var found := ScenarioGating.week_one_problems(session)
			problems += found.size()
			for f in found:
				details.append("- %s: %s" % [id, f])
			var guards: Dictionary = def["scenario"].get("siege", {}).get("guards", {})
			for g in ScenarioGating.optional_goals(session):
				goals += 1
				if int(g["unlock_day"]) > ScenarioGating.WINDOW_DAYS:
					by_day += 1
					earliest = mini(earliest, int(g["unlock_day"]))
			for gid in guards:
				held += 1
				start_max = maxf(start_max, float(guards[gid]["start_win"]))
				if float(guards[gid]["later_win"]) >= 0.5:
					later_ok += 1
		out.append("| %s | %d/%d | %d | %d | %d | %s | %s | %s |" % [rid, built, seeds, problems, goals, by_day,
			"%.2f" % start_max if held > 0 else "-", "%d/%d" % [later_ok, held] if held > 0 else "-", str(earliest) if earliest < 999 else "-"])
	out.append("")
	if details.is_empty():
		out.append("No problems.")
	else:
		out.append("## Problems")
		out.append_array(details)
	return out
