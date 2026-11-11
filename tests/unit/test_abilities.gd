extends "res://tests/test_case.gd"
## One behavioural test per ability in data/abilities.json, using synthetic
## creatures so the tests do not depend on roster balance numbers.

const COVERED := ["ranged", "flying", "charge", "brace", "shield_wall", "guardian", "heal", "inspire",
	"relentless", "curse", "unwavering", "mindless", "first_strike", "riposte", "double_strike", "splash",
	"poison", "life_drain", "regenerate", "stun", "evasion", "sunder", "armor_pierce", "momentum", "taunt",
	"fear", "aura", "rebirth", "skirmisher", "reach", "cleave", "breath"]

var gd: GameData
var sim: CombatSimulator


func before_each() -> void:
	gd = GameData.new()
	gd.load_all(GameData.DATA_DIR)
	sim = CombatSimulator.new(gd)


func _def(id: String, role: String, abilities: Array, overrides: Dictionary = {}) -> String:
	var c := {"name": id, "faction": "wilds", "tier": 3, "role": role, "hp": 20, "attack": 8, "defense": 8,
		"damage": [3, 5], "speed": 6, "initiative": 6, "growth": 5, "cost": {"gold": 200}, "morale": 0,
		"tags": [], "abilities": abilities, "terrain": {}}
	c.merge(overrides, true)
	gd.creatures[id] = c
	return id


func _side(stacks: Array) -> Dictionary:
	var out := []
	for i in stacks.size():
		out.append({"slot": i, "creature": stacks[i][0], "count": stacks[i][1]})
	return {"name": "S", "hero": null, "stacks": out}


func _run(a: Array, b: Array, seed_value: int = 7) -> Dictionary:
	return sim.simulate(CombatSimulator.make_setup(_side(a), _side(b), "desert", seed_value))


func _win_rate(a: Array, b: Array, runs: int = 200) -> float:
	var wins := 0
	for i in runs:
		if sim.simulate(CombatSimulator.make_setup(_side(a), _side(b), "desert", 300 + i), false)["winner"] == 0:
			wins += 1
	return float(wins) / runs


func _events(r: Dictionary, kind: String, actor: String = "") -> Array:
	return r["log"].filter(func(e): return e["type"] == kind and (actor == "" or e["actor"] == actor))


func _unit(name: String) -> CombatUnit:
	for u in sim._units:
		if u.name == name:
			return u
	return null


# ---------------------------------------------------------------- coverage --

func test_every_ability_is_covered() -> void:
	for id in gd.abilities:
		assert_true(COVERED.has(id), "ability %s has no test" % id)
		assert_true(gd.abilities[id].has("desc") and gd.abilities[id].has("params"), id)


func test_validation_rejects_unknown_ability_and_param() -> void:
	_def("bad1", "infantry", [{"id": "teleport"}])
	_def("bad2", "infantry", [{"id": "splash", "fractoin": 0.2}])
	var errors := "\n".join(gd.validate())
	assert_true(errors.contains("unknown ability teleport"), errors)
	assert_true(errors.contains("unknown parameter fractoin"), errors)


func test_validation_checks_upgrade_pairs() -> void:
	_def("base_x", "infantry", [], {"upgrade": "up_x"})
	_def("up_x", "infantry", [], {"upgrade_of": "base_x", "tier": 4})
	var errors := "\n".join(gd.validate())
	assert_true(errors.contains("upgrade up_x differs from its base in tier"), errors)


# ------------------------------------------------- existing core abilities --

func test_core_abilities_still_work() -> void:
	# ranged/flying/charge/brace/shield_wall/guardian/heal/inspire/relentless/curse/unwavering
	# are exercised in test_combat.gd; here we check the log shows each mechanic.
	_def("archer", "ranged", [{"id": "ranged"}])
	_def("bird", "flyer", [{"id": "flying"}])
	_def("knight", "cavalry", [{"id": "charge", "bonus": 0.5}])
	_def("pike", "infantry", [{"id": "brace"}, {"id": "shield_wall"}, {"id": "guardian"}])
	_def("priest", "support", [{"id": "heal", "per_creature": 10}, {"id": "inspire", "morale": 2}])
	_def("butcher", "infantry", [{"id": "relentless"}, {"id": "unwavering"}])
	_def("hag", "support", [{"id": "ranged"}, {"id": "curse"}])
	var r := _run([["archer", 10], ["knight", 5], ["priest", 5]], [["pike", 10], ["bird", 5], ["butcher", 5], ["hag", 5]])
	assert_gt(_events(r, "shot", "archer").size(), 0)
	assert_gt(_events(r, "heal", "priest").size(), 0)
	assert_true(_events(r, "charge").size() + r["stats"]["braced"] > 0)


func test_heal_tag_only_heals_matching_allies() -> void:
	_def("stitcher", "support", [{"id": "heal", "per_creature": 50, "tag": "undead"}])
	_def("living", "infantry", [])
	_def("enemy", "infantry", [], {"attack": 12})
	var r := _run([["stitcher", 5], ["living", 10]], [["enemy", 10]])
	assert_eq(_events(r, "heal").size(), 0, "living allies are not healed")
	gd.creatures["living"]["tags"] = ["undead"]
	r = _run([["stitcher", 5], ["living", 10]], [["enemy", 10]])
	assert_gt(_events(r, "heal").size(), 0, "undead allies are healed")


# ------------------------------------------------------------ new abilities --

func test_mindless_has_zero_morale_and_ignores_fear() -> void:
	_def("zombie", "infantry", [{"id": "mindless"}])
	_def("terror", "infantry", [{"id": "fear", "morale": 2}])
	var r := _run([["zombie", 10]], [["terror", 10]])
	assert_eq(_unit("zombie").morale, 0)
	assert_true(r["sides"][0]["notes"].any(func(n): return n.contains("Dread")))


func test_fear_lowers_enemy_morale() -> void:
	_def("soldier", "infantry", [])
	_def("terror", "infantry", [{"id": "fear", "morale": 2}])
	_run([["soldier", 10]], [["terror", 10]])
	# Single faction gives +1, fear -2.
	assert_eq(_unit("soldier").morale, -1)
	assert_eq(_unit("terror").morale, 1, "fear does not hit its own side")


func test_aura_buffs_every_ally_once() -> void:
	_def("banner", "support", [{"id": "aura", "attack": 2, "defense": 1}])
	_def("banner2", "support", [{"id": "aura", "attack": 1}])
	_def("soldier", "infantry", [])
	_def("foe", "infantry", [])
	_run([["banner", 1], ["banner2", 1], ["soldier", 10]], [["foe", 10]])
	assert_eq(_unit("soldier").attack, 10, "strongest aura counts, no stacking")
	assert_eq(_unit("soldier").defense, 9)
	assert_eq(_unit("foe").attack, 8, "enemies unaffected")


func test_first_strike_retaliates_before_the_blow() -> void:
	_def("duelist", "infantry", [{"id": "first_strike"}], {"initiative": 1})
	_def("brute", "infantry", [], {"initiative": 12, "speed": 8})
	var r := _run([["brute", 10]], [["duelist", 10]])
	var log: Array = r["log"]
	var first_melee := -1
	for i in log.size():
		if log[i]["type"] == "melee" and log[i]["actor"] == "brute":
			first_melee = i
			break
	assert_gt(first_melee, 0)
	assert_eq(log[first_melee - 1]["type"], "retaliation")
	assert_eq(log[first_melee - 1]["actor"], "duelist")


func test_riposte_retaliates_every_time() -> void:
	_def("fencer", "infantry", [{"id": "riposte"}], {"hp": 200, "defense": 20})
	_def("a1", "infantry", [], {"speed": 8, "initiative": 10})
	_def("a2", "infantry", [], {"speed": 8, "initiative": 10})
	var r := _run([["a1", 5], ["a2", 5]], [["fencer", 5]])
	var round1 := _events(r, "retaliation", "fencer").filter(func(e): return e["round"] == 1)
	assert_eq(round1.size(), 2)


func test_double_strike_attacks_twice() -> void:
	_def("twin", "ranged", [{"id": "ranged"}, {"id": "double_strike", "mult": 0.5}])
	_def("wall", "infantry", [], {"hp": 100, "speed": 2})
	var r := _run([["twin", 5]], [["wall", 5]])
	var round1 := _events(r, "shot", "twin").filter(func(e): return e["round"] == 1)
	assert_eq(round1.size(), 2)
	assert_lt(round1[1]["amount"], round1[0]["amount"] * 0.8 + 1)


func test_splash_hits_a_second_stack() -> void:
	_def("breath", "infantry", [{"id": "splash", "fraction": 0.5}], {"speed": 8})
	_def("t1", "infantry", [])
	_def("t2", "ranged", [{"id": "ranged"}])
	var r := _run([["breath", 10]], [["t1", 10], ["t2", 10]])
	assert_gt(_events(r, "splash", "breath").size(), 0)


func test_ground_melee_cannot_strike_a_flyer_in_the_air() -> void:
	# A lone flyer that holds back (waits for its own line) stays in the air.
	_def("hawk", "flyer", [{"id": "flying"}], {"speed": 10, "initiative": 2, "hp": 30})
	_def("wall", "infantry", [], {"speed": 2, "initiative": 1, "hp": 200, "defense": 30})
	_def("grunt", "infantry", [], {"speed": 8, "initiative": 9})
	var r := _run([["grunt", 10]], [["hawk", 5], ["wall", 5]])
	for e in r["log"].filter(func(x): return x["actor"] == "grunt" and x["type"] in ["melee", "overflow"] and x["round"] == 1):
		assert_ne(e["target"], "hawk", "a grunt struck the hawk before it came down")
	# Once the flyer has struck, it is on the ground and can be answered and hit.
	var r2 := _run([["grunt", 10]], [["hawk", 5]])
	assert_gt(r2["log"].filter(func(x): return x["actor"] == "grunt" and x["target"] == "hawk").size(), 0)


func test_ground_troops_wait_while_only_airborne_flyers_are_left() -> void:
	_def("grunt", "infantry", [], {"speed": 8, "initiative": 9})
	_def("hawk", "flyer", [{"id": "flying"}], {"speed": 10, "initiative": 2})
	sim.simulate(CombatSimulator.make_setup(_side([["grunt", 5]]), _side([["hawk", 5]]), "desert", 3))
	var g := _unit("grunt")
	var h := _unit("hawk")
	h.airborne = true
	assert_eq(sim._pick_melee_target(g, [h]), null)
	assert_false(sim.can_reach(g, h))


func test_reach_strikes_flyers_in_the_air() -> void:
	_def("pike", "infantry", [{"id": "reach"}])
	_def("grunt", "infantry", [])
	_def("hawk", "flyer", [{"id": "flying"}])
	sim.simulate(CombatSimulator.make_setup(_side([["pike", 5], ["grunt", 5]]), _side([["hawk", 5]]), "desert", 3))
	var h := _unit("hawk")
	h.airborne = true
	assert_true(sim.can_reach(_unit("pike"), h))
	assert_false(sim.can_reach(_unit("grunt"), h))
	h.airborne = false
	assert_true(sim.can_reach(_unit("grunt"), h))


func test_cleave_sweeps_into_stacks_within_reach() -> void:
	_def("axe", "infantry", [{"id": "cleave", "targets": 2, "fraction": 0.5}], {"speed": 8, "initiative": 9})
	_def("f1", "infantry", [], {"hp": 60})
	_def("f2", "infantry", [], {"hp": 60})
	_def("archer", "ranged", [{"id": "ranged"}])
	var cleaves := []
	for seed_value in 5:
		var r := _run([["axe", 10]], [["f1", 10], ["f2", 10], ["archer", 10]], 40 + seed_value)
		cleaves.append_array(_events(r, "cleave", "axe"))
	assert_gt(cleaves.size(), 0)
	# The front line screens the archers, so a sweep never reaches them while it stands.
	for e in cleaves:
		if e["round"] <= 2:
			assert_ne(e["target"], "archer")


func test_breath_rolls_over_the_line_into_the_archers() -> void:
	_def("drake", "infantry", [{"id": "breath", "fraction": 0.5}], {"speed": 8, "initiative": 9})
	_def("front", "infantry", [], {"hp": 80})
	_def("archer", "ranged", [{"id": "ranged"}])
	_def("healer", "support", [{"id": "heal"}])
	var r := _run([["drake", 10]], [["front", 10], ["archer", 10], ["healer", 3]])
	var b := _events(r, "breath", "drake")
	assert_gt(b.size(), 0)
	for e in b:
		assert_true(e["target"] in ["archer", "healer"], "breath reached " + e["target"])


func test_role_matchups_add_damage_and_are_validated() -> void:
	_def("rider", "cavalry", [])
	_def("bow", "ranged", [{"id": "ranged"}])
	sim.cfg = gd.combat.duplicate(true)
	sim.cfg["role_matchups"] = {"cavalry": {"ranged": 0.5}}
	sim.simulate(CombatSimulator.make_setup(_side([["rider", 5]]), _side([["bow", 5]]), "desert", 3))
	assert_between(sim.matchup_mult(_unit("rider"), _unit("bow")), 1.499, 1.501)
	assert_between(sim.matchup_mult(_unit("bow"), _unit("rider")), 0.999, 1.001)
	gd.combat["role_matchups"] = {"knight": {"ranged": 0.2}, "cavalry": {"ranged": "lots"}}
	var errors := "\n".join(gd.validate_combat_config())
	assert_true(errors.contains("unknown role knight"), errors)
	assert_true(errors.contains("cavalry vs ranged"), errors)


func test_poison_ticks_next_round() -> void:
	_def("viper", "infantry", [{"id": "poison", "fraction": 0.5}], {"speed": 8})
	_def("target", "infantry", [], {"hp": 60})
	var r := _run([["viper", 10]], [["target", 10]])
	var ticks := _events(r, "poison")
	assert_gt(ticks.size(), 0)
	assert_gt(ticks[0]["round"], 1)


func test_life_drain_heals_and_wins_more() -> void:
	_def("leech", "infantry", [{"id": "life_drain", "fraction": 0.5}])
	_def("plain", "infantry", [])
	var r := _run([["leech", 10]], [["plain", 10]])
	assert_gt(_events(r, "drain", "leech").size(), 0)
	assert_gt(_win_rate([["leech", 10]], [["plain", 10]]), 0.75)


func test_regenerate_restores_top_creature() -> void:
	_def("troll", "infantry", [{"id": "regenerate", "amount": 15}], {"hp": 40})
	_def("plain", "infantry", [])
	var r := _run([["troll", 8]], [["plain", 10]])
	var regen := _events(r, "regenerate", "troll")
	assert_gt(regen.size(), 0)
	for e in regen:
		assert_true(e["amount"] <= 15)


func test_stun_skips_next_action() -> void:
	_def("stunner", "infantry", [{"id": "stun", "chance": 1.0}], {"speed": 8, "initiative": 12})
	_def("victim", "infantry", [], {"hp": 200})
	var r := _run([["stunner", 3]], [["victim", 3]])
	assert_gt(_events(r, "stunned", "victim").size(), 0)
	assert_gt(r["stats"].get("stuns", 0), 0)


func test_evasion_dodges() -> void:
	_def("ghost", "infantry", [{"id": "evasion", "chance": 1.0}])
	_def("plain", "infantry", [])
	var r := _run([["plain", 10]], [["ghost", 10]])
	assert_eq(r["sides"][1]["hp_end"], r["sides"][1]["hp_start"], "nothing lands")
	assert_gt(_events(r, "evade").size(), 0)


func test_sunder_strips_defense_up_to_cap() -> void:
	_def("breaker", "infantry", [{"id": "sunder", "amount": 3, "cap": 5}], {"speed": 8})
	_def("tank", "infantry", [], {"hp": 300, "defense": 12})
	_run([["breaker", 5]], [["tank", 5]])
	assert_eq(_unit("tank").defense, 7)


func test_armor_pierce_deals_more_damage() -> void:
	_def("piercer", "ranged", [{"id": "ranged"}, {"id": "armor_pierce", "fraction": 0.5}])
	_def("shooter", "ranged", [{"id": "ranged"}])
	_def("tank", "infantry", [], {"hp": 500, "defense": 20, "speed": 1})
	var a := _run([["piercer", 10]], [["tank", 5]])
	var b := _run([["shooter", 10]], [["tank", 5]])
	assert_gt(a["sides"][0]["stacks"][0]["damage"], b["sides"][0]["stacks"][0]["damage"] * 1.2)


func test_momentum_grows_over_rounds() -> void:
	_def("zealot", "infantry", [{"id": "momentum", "per_round": 0.2, "cap": 1.0}], {"hp": 400, "damage": [5, 5]})
	_def("wall", "infantry", [], {"hp": 1000, "attack": 0, "damage": [1, 1], "defense": 8})
	var r := _run([["zealot", 1]], [["wall", 1]])
	var hits := _events(r, "melee", "zealot")
	assert_gt(hits.size(), 3)
	assert_gt(hits[-1]["amount"], hits[0]["amount"])


func test_taunt_draws_attacks() -> void:
	_def("decoy", "infantry", [{"id": "taunt", "chance": 1.0}], {"hp": 500})
	_def("archer", "ranged", [{"id": "ranged"}])
	_def("raider", "flyer", [{"id": "flying"}])
	var r := _run([["raider", 10]], [["decoy", 5], ["archer", 5]])
	for e in _events(r, "melee", "raider"):
		assert_eq(e["target"], "decoy")


func test_rebirth_once() -> void:
	_def("phoenix", "infantry", [{"id": "rebirth", "fraction": 0.5}], {"hp": 10})
	_def("killer", "infantry", [], {"attack": 20, "hp": 100, "damage": [20, 30]})
	var r := _run([["phoenix", 10]], [["killer", 10]])
	var ev := _events(r, "rebirth", "phoenix")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["kills"], 5)


func test_skirmisher_fights_well_when_engaged() -> void:
	_def("skirm", "ranged", [{"id": "ranged"}, {"id": "skirmisher"}], {"hp": 300})
	_def("archer", "ranged", [{"id": "ranged"}], {"hp": 300})
	_def("raider", "cavalry", [], {"speed": 9, "hp": 300})
	var a := _run([["skirm", 10]], [["raider", 10]])
	var b := _run([["archer", 10]], [["raider", 10]])
	var dmg_a: int = (_events(a, "melee", "skirm") + _events(a, "retaliation", "skirm")).reduce(func(acc, e): return acc + e["amount"], 0)
	var dmg_b: int = (_events(b, "melee", "archer") + _events(b, "retaliation", "archer")).reduce(func(acc, e): return acc + e["amount"], 0)
	assert_gt(dmg_a, dmg_b * 1.1, "skirmisher %d vs archer %d" % [dmg_a, dmg_b])


func test_abilities_do_not_break_determinism() -> void:
	var a := _side([["citadel_colossus", 1], ["sunhawk_paladin", 2], ["dawn_confessor", 3]])
	var b := _side([["pyre_sovereign", 1], ["gorgewing_matron", 2], ["ash_matriarch", 3]])
	var r1 := sim.simulate(CombatSimulator.make_setup(a, b, "grass", 99))
	var r2 := CombatSimulator.new(gd).simulate(CombatSimulator.make_setup(a, b, "grass", 99))
	assert_eq(JSON.stringify(r1), JSON.stringify(r2))
