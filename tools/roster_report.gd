extends SceneTree
## Roster balance: cost calibration and faction parity.
##
##   godot --headless --path . --script res://tools/roster_report.gd -- report [runs] [out.md]
##   godot --headless --path . --script res://tools/roster_report.gd -- calibrate [iterations] [runs]
##   godot --headless --path . --script res://tools/roster_report.gd -- factions [iterations] [runs] [gain]
##
## calibrate and factions accept a final "only=<faction>,<faction>" argument:
## then only those factions' prices move and every other creature acts as a
## fixed anchor (use it to fit a new faction into a balanced roster).
##
## Every unit is valued in gold (RESOURCE_VALUE converts wood/ore/rare
## resources). "Efficiency" is a unit's average win rate against every other
## unit of its tier band at equal gold value, each side fielding the unit plus
## the shared neutral core army (BalanceScenarios.CORE, scaled to the budget),
## the same yardstick as tests/unit/test_combat_balance.gd, so healers and
## archers are judged doing their job in an army. 50% means fairly priced.
## Tiers 1-7 are anchored by the combat workstream's creatures (ANCHORS), which
## calibrate never reprices; tier 8 keeps its mean price level.
##
## calibrate rescales each unit's gold cost (keeping other resources) towards
## its target efficiency and rewrites data/creatures/*.json in place. Targets
## follow the faction's economy curve: early factions are slightly more
## cost-efficient at tiers 1-3 and slightly less at 6-8; late factions the
## reverse (CURVE_SHIFT).

const RESOURCE_VALUE := {"gold": 1, "wood": 100, "ore": 100, "mercury": 250, "sulfur": 250, "crystal": 250, "gems": 250}
const CURVE_SHIFT := 0.04
const TERRAIN := "desert"   # no faction is native or hostile there
const DATA_FILES := "res://data/creatures"

## Creatures whose stats and prices the combat workstream tunes against
## tests/unit/test_combat_balance.gd: they take part in every comparison as
## fixed anchors, so they also pin each tier's price level, but calibrate never
## changes them.
const ANCHORS := ["pike_militia", "longbowman", "shieldwarden", "lancer", "lightbearer", "sunhawk_rider",
	"bastion_colossus", "cinderling", "scorchhound", "brimstone_hurler", "flayer", "ash_witch", "gorgewing",
	"pyre_titan", "thornwolf", "bog_lurker", "crag_slinger"]

var data: GameData
var sim: CombatSimulator
var runs := 60
## Factions whose prices calibrate and factions may change (empty: all).
var only: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and String(args[-1]).begins_with("only="):
		only = Array(String(args[-1]).trim_prefix("only=").split(","))
		args.remove_at(args.size() - 1)
	var mode: String = args[0] if args.size() > 0 else "report"
	data = GameData.new()
	data.load_all(GameData.DATA_DIR)
	sim = CombatSimulator.new(data)
	if mode == "factions":
		var iterations := int(args[1]) if args.size() > 1 else 6
		runs = int(args[2]) if args.size() > 2 else 40
		_faction_pass(iterations, float(args[3]) if args.size() > 3 else 0.5)
	elif mode == "parity":
		var max_tier := int(args[1]) if args.size() > 1 else 6
		var budget := float(args[2]) if args.size() > 2 else MID_BUDGET
		runs = int(args[3]) if args.size() > 3 else 60
		var terrain: String = args[4] if args.size() > 4 else TERRAIN
		print(_parity_line(parity_matrix(max_tier, budget, terrain)))
	elif mode == "calibrate":
		var iterations := int(args[1]) if args.size() > 1 else 4
		runs = int(args[2]) if args.size() > 2 else 60
		_calibrate(iterations)
	else:
		runs = int(args[1]) if args.size() > 1 else 100
		var out_path: String = args[2] if args.size() > 2 else "res://reports/roster_report.md"
		_report(out_path)
	quit()


# ------------------------------------------------------------------ helpers --

static func gold_value(cost: Dictionary) -> float:
	var v := 0.0
	for r in cost:
		v += float(cost[r]) * float(RESOURCE_VALUE.get(r, 250))
	return v


func _value(id: String) -> float:
	return gold_value(data.creature(id)["cost"])


const ESCORT_PRICE := [0, 75, 140, 230, 350, 520, 800, 1300, 2800]


func _army(id: String, t: int) -> Dictionary:
	var budget := _unit_budget(t)
	var n := maxi(1, int(round(budget / _value(id))))
	var stacks := []
	var scale := budget / float(BalanceScenarios.TIER_SWAP_GOLD)
	for p in BalanceScenarios.CORE:
		stacks.append({"slot": stacks.size(), "creature": p[0], "count": maxi(1, int(round(int(p[1]) * scale)))})
	stacks.append({"slot": stacks.size(), "creature": id, "count": n})
	return {"name": id, "hero": null, "stacks": stacks}


## Gold of the tested creature per side: the shared balance yardstick
## (BalanceScenarios.TIER_SWAP_GOLD), raised for big tiers so stacks stay >= 2.
func _unit_budget(t: int) -> float:
	return maxf(float(BalanceScenarios.TIER_SWAP_GOLD), 2.0 * ESCORT_PRICE[t])


func _count_exact(id: String, t: int) -> float:
	return _unit_budget(t) / _value(id)


## Win rate of a vs b (both directions, half the runs each).
func _duel(a: String, b: String, t: int) -> float:
	var wins := 0.0
	var A := _army(a, t)
	var B := _army(b, t)
	var fa := _count_exact(a, t)
	var fb := _count_exact(b, t)
	for i in runs:
		var sa: Dictionary = A.duplicate(true)
		var sb: Dictionary = B.duplicate(true)
		sa["stacks"][-1]["count"] = _stochastic_round(fa, i, 17)
		sb["stacks"][-1]["count"] = _stochastic_round(fb, i, 31)
		# Half the fights inside the neutral core, half as bare stacks, so a
		# price is fair both in a real army and in a head-on clash.
		if (i / 2) % 2 == 1:
			sa["stacks"] = [sa["stacks"][-1]]
			sb["stacks"] = [sb["stacks"][-1]]
			sa["stacks"][0]["slot"] = 0
			sb["stacks"][0]["slot"] = 0
		if i % 2 == 0:
			var r := sim.simulate(CombatSimulator.make_setup(sa, sb, TERRAIN, 70000 + i), false)
			wins += 1.0 if r["winner"] == 0 else 0.0
		else:
			var r := sim.simulate(CombatSimulator.make_setup(sb, sa, TERRAIN, 70000 + i), false)
			wins += 1.0 if r["winner"] == 1 else 0.0
	return wins / runs


## Deterministic dithering of a fractional count across runs.
static func _stochastic_round(x: float, i: int, salt: int) -> int:
	var base := floori(x)
	var frac := x - base
	var h := float(((i + 1) * 2654435761 + salt * 40503) % 1000) / 1000.0
	return maxi(1, base + (1 if h < frac else 0))


func _groups() -> Dictionary:
	# tier -> {"base": [...], "upgraded": [...]}; wild creatures join "base".
	var g := {}
	for t in range(1, 9):
		g[t] = {"base": [], "upgraded": []}
	var ids := data.creatures.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = data.creatures[id]
		g[int(c["tier"])]["upgraded" if c.has("upgrade_of") else "base"].append(id)
	return g


func _target(id: String) -> float:
	var c := data.creature(id)
	var curve: String = data.factions.get(c["faction"], {}).get("economy", {}).get("curve", "steady")
	var t := int(c["tier"])
	var sign := 0.0
	if t <= 3:
		sign = 1.0
	elif t >= 6:
		sign = -1.0
	if curve == "early":
		return 0.5 + CURVE_SHIFT * sign
	if curve == "late":
		return 0.5 - CURVE_SHIFT * sign
	return 0.5


## Average win rate of each unit against the rest of its group.
func _efficiency(group: Array, t: int) -> Dictionary:
	var wr := {}
	for id in group:
		wr[id] = 0.0
	for i in group.size():
		for j in range(i + 1, group.size()):
			var w := _duel(group[i], group[j], t)
			wr[group[i]] += w
			wr[group[j]] += 1.0 - w
	for id in group:
		wr[id] /= maxf(1.0, group.size() - 1)
	return wr


# -------------------------------------------------------------- calibrate --

## Prices calibrate and factions never change: the anchors, and with only=...
## every creature outside those factions.
func _fixed(id: String) -> bool:
	return ANCHORS.has(id) or (not only.is_empty() and not only.has(data.creature(id)["faction"]))


func _calibrate(iterations: int) -> void:
	var groups := _groups()
	for it in iterations:
		var worst := 0.0
		var worst_id := ""
		var gain := 0.6 / (1.0 + it * 0.5)
		for t in range(1, 9):
			for kind in ["base", "upgraded"]:
				var group: Array = groups[t][kind]
				var eff := _efficiency(group, t)
				var log_before := 0.0
				for id in group:
					log_before += log(_value(id))
				for id in group:
					var c := data.creature(id)
					if _fixed(id):
						continue
					var err: float = eff[id] - _target(id)
					if absf(err) > worst:
						worst = absf(err)
						worst_id = id
					# Steep combat: small price moves swing win rates a lot, so damp the step over iterations.
					var factor := clampf(1.0 + err * gain, 0.8, 1.25)
					var other := gold_value(c["cost"]) - float(c["cost"]["gold"])
					var new_value := gold_value(c["cost"]) * factor
					c["cost"]["gold"] = maxi(10, int(round(maxf(new_value - other, 10.0) / 5.0)) * 5)
				# Keep the tier's price level: only redistribute value inside the group.
				if not group.is_empty() and not group.any(func(id): return _fixed(id)):
					var log_after := 0.0
					for id in group:
						log_after += log(_value(id))
					var level := exp((log_before - log_after) / group.size())
					for id in group:
						var c := data.creature(id)
						var other := gold_value(c["cost"]) - float(c["cost"]["gold"])
						c["cost"]["gold"] = maxi(10, int(round(maxf(_value(id) * level - other, 10.0) / 5.0)) * 5)
		print("iteration %d: largest efficiency error %.3f (%s)" % [it + 1, worst, worst_id])
	_enforce_upgrade_premium()
	_write_files()


## Faction parity: whole armies carry synergies single-creature duels miss
## (an all-ranged line behind taunting trees, a swarm with an aura). Each pass
## plays the early (tiers 1-4) and late (tiers 1-8) parity matrices; a faction
## that wins more than half its matchups pays more for its non-anchor creatures
## of that phase (tiers 1-4 follow the early result, 5-8 the late one).
func _faction_pass(iterations: int, base_gain: float) -> void:
	for it in iterations:
		var early := parity_matrix(4, EARLY_BUDGET)
		var late := parity_matrix(8, LATE_BUDGET)
		var line := []
		for f in PLAYABLE:
			var e := 0.0
			var l := 0.0
			for g in PLAYABLE:
				if g != f:
					e += early[f][g]
					l += late[f][g]
			e /= PLAYABLE.size() - 1
			l /= PLAYABLE.size() - 1
			line.append("%s %d/%d" % [f, roundi(100 * e), roundi(100 * l)])
			var gain := base_gain / (1.0 + it * 0.4)
			for id in data.creatures:
				var c: Dictionary = data.creatures[id]
				if c["faction"] != f or _fixed(id):
					continue
				var err := (e if int(c["tier"]) <= 4 else l) - 0.5
				var factor := clampf(1.0 + err * gain, 0.8, 1.25)
				var other := gold_value(c["cost"]) - float(c["cost"]["gold"])
				c["cost"]["gold"] = maxi(10, int(round(maxf(_value(id) * factor - other, 10.0) / 5.0)) * 5)
		print("faction pass %d (early/late win %%): %s" % [it + 1, ", ".join(line)])
	_enforce_upgrade_premium()
	_write_files()


## An upgrade must always cost more than its base (it is strictly better).
func _enforce_upgrade_premium() -> void:
	for id in data.creatures:
		var c: Dictionary = data.creatures[id]
		if c.has("upgrade_of") and not _fixed(id):
			var b := data.creature(c["upgrade_of"])
			var min_gold := int(ceil(float(b["cost"]["gold"]) * 1.1 / 5.0)) * 5
			if gold_value(c["cost"]) <= gold_value(b["cost"]) * 1.1:
				c["cost"]["gold"] = maxi(int(c["cost"]["gold"]), min_gold)


func _write_files() -> void:
	var dir := DirAccess.open(DATA_FILES)
	var names := Array(dir.get_files()).filter(func(n): return n.ends_with(".json"))
	names.sort()
	for n in names:
		var path: String = DATA_FILES + "/" + n
		var parsed: Dictionary = GameData.read_json(path)
		var defs: Dictionary = parsed["creatures"]
		var lines := PackedStringArray(["{", '  "_doc": %s,' % JSON.stringify(parsed.get("_doc", "")), '  "creatures": {'])
		var ids := defs.keys()
		for i in ids.size():
			var id: String = ids[i]
			var c: Dictionary = defs[id]
			c["cost"] = data.creature(id)["cost"]
			lines.append('    %s: %s%s' % [JSON.stringify(id), _compact(c), "," if i < ids.size() - 1 else ""])
		lines.append_array(["  }", "}", ""])
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string("\n".join(lines))
		print("wrote ", path)


## JSON with "key": value spacing and integral floats printed as ints.
static func _compact(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var parts := []
			for k in v:
				parts.append("%s: %s" % [JSON.stringify(k), _compact(v[k])])
			return "{" + ", ".join(parts) + "}"
		TYPE_ARRAY:
			return "[" + ", ".join(v.map(func(x): return _compact(x))) + "]"
		TYPE_FLOAT:
			if v == floorf(v) and absf(v) < 1e9:
				return str(int(v))
			return str(v)
	return JSON.stringify(v)


# ----------------------------------------------------------------- report --

func _report(out_path: String) -> void:
	var md := PackedStringArray()
	md.append("# Crowns of Caern roster report\n")
	md.append("%d simulations per pairing, terrain %s. Values in gold (wood/ore 100, rare resources 250).\n" % [runs, TERRAIN])
	md.append("## Cost efficiency per tier\n")
	md.append("Average win rate against every other unit of the same tier and kind at equal value (with an identical escort). Target 50% (±4 by economy curve).\n")
	md.append("| Tier | Unit | Faction | Value | Efficiency | Target |")
	md.append("|---|---|---|---|---|---|")
	var groups := _groups()
	var worst := 0.0
	for t in range(1, 9):
		for kind in ["base", "upgraded"]:
			var eff := _efficiency(groups[t][kind], t)
			for id in groups[t][kind]:
				var c := data.creature(id)
				worst = maxf(worst, absf(eff[id] - _target(id)))
				md.append("| %d | %s | %s | %d | %d%% | %d%% |" % [t, c["name"], c["faction"], int(_value(id)), roundi(100 * eff[id]), roundi(100 * _target(id))])
	md.append("\nLargest deviation from target: %d points.\n" % roundi(100 * worst))
	md.append("## Faction parity (full armies, equal value)\n")
	md.append(_parity_table("Early game (tiers 1-4, budget %d)" % EARLY_BUDGET, 4, EARLY_BUDGET))
	md.append(_parity_table("Mid game (tiers 1-6, budget %d)" % MID_BUDGET, 6, MID_BUDGET))
	md.append(_parity_table("Late game (tiers 1-8, budget %d)" % LATE_BUDGET, 8, LATE_BUDGET))
	md.append("## Upgrade value\n")
	md.append("Upgraded stack vs base stack of the same unit at equal value (50% = upgrade fairly priced).\n")
	md.append("| Unit | Upgrade | Upgrade win % |")
	md.append("|---|---|---|")
	for t in range(1, 9):
		for id in groups[t]["upgraded"]:
			var b: String = data.creature(id)["upgrade_of"]
			md.append("| %s | %s | %d |" % [data.creature(b)["name"], data.creature(id)["name"], roundi(100 * _duel(id, b, t))])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
		f = FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n".join(md) + "\n")
	print("\n".join(md))


## The three phases the faction pass and the report measure: early (tiers 1-4),
## mid (tiers 1-6, where the top tiers cannot hide weak low tiers) and late (tiers 1-8).
const EARLY_BUDGET := 12000.0
const MID_BUDGET := 10000.0
const LATE_BUDGET := 90000.0


## Average win rate of each faction against the other five, as "faction NN%".
func _parity_line(m: Dictionary) -> String:
	var parts := []
	for f in PLAYABLE:
		parts.append("%s %d%%" % [f, roundi(100 * _parity_avg(m, f))])
	return ", ".join(parts)


static func _parity_avg(m: Dictionary, f: String) -> float:
	var total := 0.0
	for g in PLAYABLE:
		if g != f:
			total += m[f][g]
	return total / (PLAYABLE.size() - 1)


const PLAYABLE := ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch", "darkelf", "fishmen"]


## A faction's standard army: equal value split across its base units of tier <= max_tier,
## weighted towards low tiers like a real recruitment week, at most 7 stacks.
func faction_army(fid: String, max_tier: int, budget: float, upgraded: bool = false) -> Dictionary:
	var picks := []
	for t in range(1, max_tier + 1):
		for id in data.creatures:
			var c: Dictionary = data.creatures[id]
			if c["faction"] == fid and int(c["tier"]) == t and c.has("upgrade_of") == upgraded:
				picks.append(id)
	# Keep the 7 highest tiers if there are more than 7.
	while picks.size() > 7:
		picks.pop_front()
	var stacks := []
	var share := budget / picks.size()
	for i in picks.size():
		stacks.append({"slot": i, "creature": picks[i], "count": maxi(1, int(round(share / _value(picks[i]))))})
	return {"name": fid, "hero": null, "stacks": stacks}


func parity_matrix(max_tier: int, budget: float, terrain: String = TERRAIN) -> Dictionary:
	var m := {}
	for a in PLAYABLE:
		m[a] = {}
	for i in PLAYABLE.size():
		for j in range(i + 1, PLAYABLE.size()):
			var a: String = PLAYABLE[i]
			var b: String = PLAYABLE[j]
			var A := faction_army(a, max_tier, budget)
			var B := faction_army(b, max_tier, budget)
			var wins := 0.0
			for k in runs:
				if k % 2 == 0:
					wins += 1.0 if sim.simulate(CombatSimulator.make_setup(A, B, terrain, 80000 + k), false)["winner"] == 0 else 0.0
				else:
					wins += 1.0 if sim.simulate(CombatSimulator.make_setup(B, A, terrain, 80000 + k), false)["winner"] == 1 else 0.0
			m[a][b] = wins / runs
			m[b][a] = 1.0 - wins / runs
	return m


func _parity_table(title: String, max_tier: int, budget: float) -> String:
	var m := parity_matrix(max_tier, budget)
	var lines := PackedStringArray(["### " + title + "\n", "| vs | " + " | ".join(PLAYABLE) + " | avg |", "|---|" + "---|".repeat(PLAYABLE.size() + 1)])
	for a in PLAYABLE:
		var row := []
		var total := 0.0
		for b in PLAYABLE:
			if a == b:
				row.append("-")
			else:
				row.append("%d" % roundi(100 * m[a][b]))
				total += m[a][b]
		lines.append("| %s | %s | %d |" % [a, " | ".join(row), roundi(100 * total / (PLAYABLE.size() - 1))])
	return "\n".join(lines) + "\n"
