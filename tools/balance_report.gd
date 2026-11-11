extends SceneTree
## Headless balance diagnostics. Writes a Markdown report:
##   godot --headless --path . --script res://tools/balance_report.gd -- [runs] [out.md]
## Matchups are gold-matched so results speak to cost efficiency. The "Goals"
## section uses the same scenarios (BalanceScenarios) as the statistical tests
## in tests/unit/test_combat_balance.gd.

const FACTIONS := ["concord", "ashen"]
const RANGED_VS_CAVALRY := [["longbowman", "scorchhound"], ["longbowman", "thornwolf"], ["brimstone_hurler", "lancer"], ["crag_slinger", "scorchhound"]]
const RANGED_VS_CAVALRY_GOLD := 6000

var data: GameData
var bs: BalanceScenarios
var runs := 500


func _init() -> void:
	data = GameData.get_default()
	bs = BalanceScenarios.new(data)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		runs = int(args[0])
	var out_path := args[1] if args.size() > 1 else "res://reports/balance_report.md"
	var md := PackedStringArray()
	md.append("# Crowns of Caern balance report\n\n%d simulations per row. Win rate is for the first army. Gold is matched as closely as whole creatures allow.\n" % runs)

	md.append("## Goals\n")
	md.append("| Goal | Matchup | Terrain | A win % | Target |")
	md.append("|---|---|---|---|---|")
	for faction in FACTIONS:
		var bal := bs.balanced_army(faction)
		for tier in range(1, 8):
			var c := bs.creature_at(tier, faction)
			if c == "":
				continue
			md.append(_goal("Balanced beats doom stack", bal, bs.doom_stack(c), "rough", "> 55"))
	var cb := bs.balanced_army("concord")
	var ab := bs.balanced_army("ashen")
	for terrain in ["rough", "grass", "infernal"]:
		md.append(_goal("Faction parity (balanced)", cb, ab, terrain, "35-65 on neutral"))
	for tier in range(1, 8):
		var pair := bs.tier_swap(tier, "concord", "ashen")
		md.append(_goal("Same-tier parity (tier %d in core army)" % tier, pair[0], pair[1], "rough", "25-75"))
	for pair in RANGED_VS_CAVALRY:
		var n := bs.matched_counts(pair[0], pair[1], RANGED_VS_CAVALRY_GOLD)
		md.append(_goal("Mass ranged vs cavalry", [[pair[0], n[0]]], [[pair[1], n[1]]], "rough", "loses, not hopeless"))

	md.append("\n## Gold efficiency: each creature vs. same-tier rival, alone (about 12000 gold each)\n")
	md.append("Role counters dominate these pure matchups (ranged vs cavalry, etc.); the goals above measure parity.\n")
	md.append("| Tier | A | B | Terrain | A win % | A avg loss % |")
	md.append("|---|---|---|---|---|---|")
	for tier in range(1, 8):
		var c := bs.creature_at(tier, "concord")
		var a := bs.creature_at(tier, "ashen")
		var n := bs.matched_counts(c, a, 12000)
		for terrain in ["rough", "grass", "infernal"]:
			md.append("| %d %s" % [tier, _row([[c, n[0]]], [[a, n[1]]], terrain)])

	md.append("\n## Composition and counterplay\n")
	md.append("| A | B | Terrain | A win % | A avg loss % |")
	md.append("|---|---|---|---|---|")
	md.append(_row([["longbowman", 35]], [["shieldwarden", 16]], "rough"))
	md.append(_row([["lancer", 6]], [["pike_militia", 27]], "rough"))
	md.append(_row([["lancer", 6]], [["cinderling", 35]], "rough"))
	md.append(_row([["pike_militia", 18], ["pike_militia", 18], ["pike_militia", 17], ["pike_militia", 17]], [["pike_militia", 70]], "rough"))
	md.append(_row([["pike_militia", 35], ["pike_militia", 35]], [["pike_militia", 70]], "rough"))
	md.append(_row([["pike_militia", 30], ["longbowman", 20]], [["pike_militia", 61]], "rough"))
	md.append(_row(cb, cb, "rough"))

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
		f = FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n".join(md) + "\n")
	print("\n".join(md))
	quit()


func _goal(goal: String, a: Array, b: Array, terrain: String, target: String) -> String:
	var r := bs.measure(a, b, terrain, runs)
	return "| %s | %s vs %s | %s | %d | %s |" % [goal, bs.describe(a), bs.describe(b), terrain, roundi(100.0 * r["win_rate"]), target]


func _row(a: Array, b: Array, terrain: String) -> String:
	var r := bs.measure(a, b, terrain, runs)
	return "| %s | %s | %s | %d | %d |" % [bs.describe(a), bs.describe(b), terrain, roundi(100.0 * r["win_rate"]), roundi(100.0 * r["loss"])]
