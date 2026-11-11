class_name BalanceScenarios
extends RefCounted
## Gold-matched army builders and win-rate measurement shared by the balance
## report (tools/balance_report.gd), the fair-cost tool and the statistical
## balance tests, so all three measure exactly the same matchups.
## Armies are Arrays of [creature_id, count] pairs.

## Gold for "balanced army vs doom stack" and faction parity matchups.
const ARMY_GOLD := 9000
## Gold of the tier creature added to the neutral core in same-tier checks.
const TIER_SWAP_GOLD := 3000
## Neutral core army for same-tier parity checks: both sides field it, so role
## counters between the two tier creatures mostly cancel out.
const CORE := [["bog_lurker", 5], ["crag_slinger", 12], ["thornwolf", 4]]
## Gold worth of one unit of each resource, so creatures that also cost wood,
## ore or rare resources are matched at their full price (same table as
## tools/roster_report.gd and tests/unit/test_roster_balance.gd).
const RESOURCE_VALUE := {"gold": 1, "wood": 100, "ore": 100, "mercury": 250, "sulfur": 250, "crystal": 250, "gems": 250}

var data: GameData
var sim: CombatSimulator


func _init(game_data: GameData) -> void:
	data = game_data
	sim = CombatSimulator.new(game_data)


## A creature's price in gold, counting other resources at RESOURCE_VALUE.
func cost_of(id: String) -> int:
	var cost: Dictionary = data.creature(id)["cost"]
	var total := 0
	for r in cost:
		total += int(cost[r]) * int(RESOURCE_VALUE.get(r, 250))
	return total


func army_gold(army: Array) -> int:
	var total := 0
	for p in army:
		total += int(p[1]) * cost_of(p[0])
	return total


## The faction's creature of a tier, or "" (first by sorted id if several).
func creature_at(tier: int, faction: String) -> String:
	var ids: Array = data.creatures.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = data.creatures[id]
		if int(c["tier"]) == tier and c["faction"] == faction and not c.has("upgrade_of"):
			return id
	return ""


func count_for(id: String, gold: int) -> int:
	return maxi(1, roundi(float(gold) / cost_of(id)))


## A single stack of one creature worth about `gold`.
func doom_stack(id: String, gold: int = ARMY_GOLD) -> Array:
	return [[id, count_for(id, gold)]]


## Splits `gold` by [id, share] pairs, then spends or refunds the remainder on
## the first creature so the army costs (almost exactly) `gold`.
func gold_army(shares: Array, gold: int) -> Array:
	var out: Array = []
	for p in shares:
		out.append([p[0], count_for(p[0], int(gold * float(p[1])))])
	out[0][1] = maxi(1, out[0][1] + roundi(float(gold - army_gold(out)) / cost_of(out[0][0])))
	return out


## Equal gold in every tier 1-6 creature of the faction.
func balanced_army(faction: String, gold: int = ARMY_GOLD) -> Array:
	var shares := []
	for tier in range(1, 7):
		var id := creature_at(tier, faction)
		if id != "":
			shares.append([id, 1.0])
	for p in shares:
		p[1] = 1.0 / shares.size()
	return gold_army(shares, gold)


## Counts of two creatures whose total gold is as equal as possible, near `gold`.
func matched_counts(a: String, b: String, gold: int) -> Array:
	var ca := float(cost_of(a))
	var cb := float(cost_of(b))
	var best := [1, 1]
	var best_err := INF
	for na in range(1, int(gold * 1.5 / ca) + 2):
		var nb := maxi(1, roundi(na * ca / cb))
		var err := absf(na * ca - nb * cb) / (na * ca) + 0.3 * absf(na * ca - gold) / gold
		if err < best_err:
			best_err = err
			best = [na, nb]
	return best


## Two armies: the shared neutral core plus equal gold of each tier creature.
func tier_swap(tier: int, faction_a: String, faction_b: String) -> Array:
	var a := creature_at(tier, faction_a)
	var b := creature_at(tier, faction_b)
	var n := matched_counts(a, b, TIER_SWAP_GOLD)
	return [CORE + [[a, n[0]]], CORE + [[b, n[1]]]]


## A late-game army: equal gold in the upgraded creature of every tier 1-8.
func late_army(faction: String, gold: int) -> Array:
	var shares := []
	for tier in range(1, 9):
		var id := creature_at(tier, faction)
		if id == "":
			continue
		var up := String(data.creature(id).get("upgrade", ""))
		shares.append([up if up != "" else id, 1.0])
	for p in shares:
		p[1] = 1.0 / shares.size()
	return gold_army(shares, gold)


## The faction's ultimate army upgrade (its town's army_upgrade effect), or {}.
func ultimate_of(faction: String) -> Dictionary:
	var bs: Dictionary = data.town_types.get(faction, {}).get("buildings", {})
	var ids := bs.keys()
	ids.sort()
	for b in ids:
		for e in bs[b].get("effects", []):
			if e["type"] == "army_upgrade":
				return e
	return {}


## Win rate of a late army WITH its faction's ultimate against the same faction
## army WITHOUT it, worth `rival_gold` (defaults to the same gold), averaged
## over both attack directions on neutral ground.
func ultimate_edge(faction: String, gold: int, runs: int, rival_gold: int = -1, seed_base: int = 70000) -> float:
	var up := ultimate_of(faction)
	var a := side(late_army(faction, gold))
	a["upgrades"] = {faction: up}
	var b := side(late_army(faction, gold if rival_gold < 0 else rival_gold))
	var wins := 0
	for i in runs:
		var r := sim.simulate(CombatSimulator.make_setup(a, b, "desert", seed_base + i), false)
		wins += 1 if r["winner"] == 0 else 0
		r = sim.simulate(CombatSimulator.make_setup(b, a, "desert", seed_base + runs + i), false)
		wins += 1 if r["winner"] == 1 else 0
	return float(wins) / (2 * runs)


static func side(army: Array, hero: Variant = null, name: String = "") -> Dictionary:
	var stacks := []
	for i in army.size():
		stacks.append({"slot": i, "creature": army[i][0], "count": int(army[i][1])})
	return {"name": name, "hero": hero, "stacks": stacks}


## Returns {win_rate, loss} for army `a` (attacker) over `runs` fixed seeds.
func measure(a: Array, b: Array, terrain: String, runs: int, seed_base: int = 90000) -> Dictionary:
	var wins := 0
	var loss := 0.0
	var sa := side(a)
	var sb := side(b)
	for i in runs:
		var r := sim.simulate(CombatSimulator.make_setup(sa, sb, terrain, seed_base + i), false)
		if r["winner"] == 0:
			wins += 1
		loss += 1.0 - float(r["sides"][0]["hp_end"]) / maxf(1.0, float(r["sides"][0]["hp_start"]))
	return {"win_rate": float(wins) / runs, "loss": loss / runs}


func win_rate(a: Array, b: Array, terrain: String, runs: int, seed_base: int = 90000) -> float:
	return measure(a, b, terrain, runs, seed_base)["win_rate"]


func describe(army: Array) -> String:
	return " + ".join(army.map(func(p): return "%d %s" % [p[1], data.creature(p[0])["name"]]))
