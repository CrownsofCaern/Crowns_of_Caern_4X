extends SceneTree
## Diagnostics for AI formation choices (not a test):
##   godot --headless --path . --script res://tools/formation_probe.gd -- [duel|battles|all]
## duel: the hard-vs-easy Ashen mirror duel on twin_marches seed 9 (as in
##   test_ai_difficulty) with the war-council orders switched off one at a time.
## battles: win rate and attacker losses per formation for typical early
##   fights against neutral packs.

const NEUTRALS := [
	[["thornwolf", 22]], [["bog_lurker", 14]], [["crag_slinger", 12], ["thornwolf", 10], ["bog_lurker", 6]],
	[["thornwolf", 40]], [["bog_lurker", 25]],
]
const ARMIES := [
	[["cinderling", 30], ["scorchhound", 10], ["brimstone_hurler", 8], ["flayer", 3]],
	[["cinderling", 45], ["scorchhound", 14], ["brimstone_hurler", 12], ["flayer", 6], ["ash_witch", 2]],
	[["pike_militia", 24], ["longbowman", 14], ["shieldwarden", 6], ["lancer", 3]],
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var what := String(args[0]) if args.size() > 0 else "all"
	if what in ["battles", "all"]:
		_battles()
	if what in ["duel", "all"]:
		_duel()
	quit()


func _fresh(variant: String) -> GameData:
	var d := GameData.new()
	d.load_all(GameData.DATA_DIR)
	if variant in ["line_only", "plain"]:
		for id in d.tactics["formations"].keys():
			if id != "line":
				d.tactics["formations"].erase(id)
	if variant in ["art_now", "plain"]:
		for id in d.tactics["art_timing"].keys():
			if id != "at_once":
				d.tactics["art_timing"].erase(id)
	return d


func _worth(s: GameSession, p: int) -> float:
	var ai := StrategicAI.new(s, p)
	var v := 0.0
	for h in s.state.heroes_of(p):
		v += ai.army_value(h.army)
	for t in s.towns_of(p):
		v += ai.army_value(Town.garrison(t))
		for b in t["built"]:
			v += ai.bundle_value(Town.build_cost(t, b, s.data))
	var bank: ResourceBank = s.state.player(p)["resources"]
	for res in s.data.resource_order:
		v += float(bank.get_amount(res)) * ai.resource_value(res)
	return v


func _duel() -> void:
	for variant in ["full", "line_only", "art_now", "plain"]:
		for hard_seat in 2:
			var d := _fresh(variant)
			var ps := []
			for seat in 2:
				ps.append({"type": "computer", "faction": "ashen", "difficulty": "hard" if seat == hard_seat else "easy"})
			var s := GameSession.new_game(d, "twin_marches", 9, {"players": ps})
			var forms := {}
			while s.state.day < 15 and not s.state.game_over:
				StrategicAI.new(s, s.state.current_player).play_turn()
				for h in s.state.heroes_of(hard_seat):
					var f := String(h.orders.get("formation", "line")) + "/" + String(h.orders.get("art", "at_once"))
					forms[f] = int(forms.get(f, 0)) + 1
				s.end_turn()
			print("duel %-9s hard seat %d: day %d over %s winner %d  hard %.0f  easy %.0f  orders %s" % [variant, hard_seat,
				s.state.day, s.state.game_over, s.state.winner, _worth(s, hard_seat), _worth(s, 1 - hard_seat), str(forms)])


func _battles() -> void:
	var data := GameData.get_default()
	var sim := CombatSimulator.new(data)
	for a in ARMIES:
		for n in NEUTRALS:
			var own := []
			for st in a:
				own.append({"creature": st[0], "count": st[1]})
			var foe := []
			for st in n:
				foe.append({"creature": st[0], "count": st[1]})
			var pick := BattleOrders.choose(data, 8, 0, own, foe)
			var line := "%s vs %s (AI picks %s):" % [str(a), str(n), pick["formation"]]
			for f in BattleOrders.ids(data, "formation"):
				var wins := 0
				var lost := 0.0
				var runs := 200
				for i in runs:
					var hero := {"name": "H", "attack": 2, "defense": 2, "power": 1, "knowledge": 1, "skills": {},
						"orders": {"stance": "balanced", "focus": "any", "formation": f, "art": "at_once", "retreat": "never"}}
					var r := sim.simulate(CombatSimulator.make_setup(BalanceScenarios.side(a, hero), BalanceScenarios.side(n, null), "grass", 4000 + i), false)
					if r["winner"] == 0:
						wins += 1
					lost += 1.0 - float(r["sides"][0]["hp_end"]) / float(r["sides"][0]["hp_start"])
				line += "  %s %d%%/%.0f%%" % [f, wins * 100 / runs, lost * 100.0 / runs]
			print(line)
