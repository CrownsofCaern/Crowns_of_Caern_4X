extends SceneTree
## Suggests the gold cost at which each creature is worth its price inside an
## army. Use it when adding or retuning creatures:
##   godot --headless --path . --script res://tools/fair_cost.gd -- [runs] [gold]
##
## Yardstick: the shared neutral core (BalanceScenarios.CORE) plus `gold` worth
## of the creature fights the same core plus `gold` worth of each faction's
## balanced army (equal gold in its tier 1-6 creatures). The suggested cost is
## the price at which the creature wins half of those fights (bisection).
## Testing inside a core army means support and defensive creatures are judged
## doing their job, and role counters between single stacks mostly cancel out.
## Suggestions are normalised to the current price level (see below).
## The output is a suggestion for a designer, not an automatic rebalance;
## tier 7 creatures may stay a little above par because they grow one per week.

var data: GameData
var bs: BalanceScenarios
var runs := 40
var gold := 3000
var references: Array = []


func _init() -> void:
	data = GameData.get_default()
	bs = BalanceScenarios.new(data)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		runs = int(args[0])
	if args.size() > 1:
		gold = int(args[1])
	var factions := {}
	for id in data.creatures:
		if not data.factions.get(data.creature(id)["faction"], {}).get("neutral", false):
			factions[data.creature(id)["faction"]] = true
	var faction_ids: Array = factions.keys()
	faction_ids.sort()
	for f in faction_ids:
		references.append(BalanceScenarios.CORE + bs.balanced_army(f, gold))
	var ids: Array = data.creatures.keys()
	ids.sort()
	# Gold spread over many roles beats gold concentrated in one creature (that
	# is the doom-stack goal), so raw break-even prices sit below current costs.
	# Normalise by the geometric mean so the suggestions keep the price level
	# and only redistribute value between creatures.
	var raw := {}
	var log_sum := 0.0
	for id in ids:
		raw[id] = _break_even(id)
		log_sum += log(raw[id] / bs.cost_of(id))
	var level := exp(log_sum / ids.size())
	print("| Creature | Tier | Role | Cost now | Raw break-even | Suggested | Change |")
	print("|---|---|---|---|---|---|---|")
	for id in ids:
		var c := data.creature(id)
		var now := bs.cost_of(id)
		var sug := roundi(raw[id] / level / 5.0) * 5
		print("| %s | %d | %s | %d | %d | %d | %+d%% |" % [c["name"], int(c["tier"]), c["role"], now, roundi(raw[id]), sug, roundi(100.0 * (sug - now) / now)])
	quit()


## Bisection on the creature's price: a lower price buys more creatures.
func _break_even(id: String) -> float:
	var lo := bs.cost_of(id) * 0.4
	var hi := bs.cost_of(id) * 2.5
	for step in 8:
		var mid := sqrt(lo * hi)
		var army := BalanceScenarios.CORE + [[id, maxi(1, roundi(gold / mid))]]
		var total := 0.0
		for ref in references:
			total += bs.win_rate(army, ref, "rough", runs, 31000)
		if total / references.size() > 0.5:
			lo = mid
		else:
			hi = mid
	return sqrt(lo * hi)
