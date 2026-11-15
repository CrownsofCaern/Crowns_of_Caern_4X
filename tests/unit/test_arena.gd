extends "res://tests/test_case.gd"
## The Battle Arena: sandbox setup, fight-equal enemies and a rogue round.

var gd: GameData


func before_each() -> void:
	gd = GameData.get_default()


func test_sandbox_builds_full_towns_and_endless_supply() -> void:
	var a := Arena.create(gd, {"mode": "sandbox", "faction": "concord", "enemy_faction": "ashen", "seed": 7})
	var t := a.session.town(Arena.PLAYER_TOWN)
	assert_false((t["built"] as Array).has("c_ultimate"), "no ultimate unless asked")
	assert_eq(int(t["available"]["pike_militia"]), Arena.SUPPLY)
	var r := a.session.recruit(Arena.PLAYER_TOWN, "pike_militia", 500)
	assert_true(r["ok"], str(r))
	a.refill()
	assert_eq(int(t["available"]["pike_militia"]), Arena.SUPPLY, "troops never run out")
	assert_eq((a.session.state.player(0)["resources"] as ResourceBank).get_amount("gold"), Arena.PLENTY)
	assert_eq(a.player_hero().army.total_creatures(), 500, "recruits join the visiting hero")


func test_enemy_edit_recruits_into_enemy_army() -> void:
	var a := Arena.create(gd, {"mode": "sandbox", "faction": "concord", "enemy_faction": "ashen", "seed": 3})
	a.begin_enemy_edit()
	var t := a.session.town(Arena.ENEMY_TOWN)
	var c := String(Town.dwellings(t, gd)[0])
	assert_true(a.session.recruit(Arena.ENEMY_TOWN, c, 20)["ok"])
	a.end_enemy_edit()
	assert_eq(a.enemy_hero().army.total_creatures(), 20)
	assert_eq(a.enemy_hero().pos, Arena.FIELD)


func test_fight_equal_matches_strength_and_restores() -> void:
	var a := Arena.create(gd, {"mode": "sandbox", "faction": "concord", "enemy_faction": "ashen", "enemy": "equal", "seed": 11})
	a.session.recruit(Arena.PLAYER_TOWN, "pike_militia", 60)
	a.session.recruit(Arena.PLAYER_TOWN, "longbowman", 30)
	a.build_equal_enemy()
	var mine := a.power_of(a.player_hero())
	assert_between(a.power_of(a.enemy_hero()), mine * 0.85, mine * 1.1, "equal worth")
	var before := a.player_hero().army.total_creatures()
	var result := a.fight()
	assert_true(result.has("winner"))
	a.after_fight(result)
	a.restore_armies()
	assert_eq(a.player_hero().army.total_creatures(), before, "sandbox restores the armies")
	assert_true(a.enemy_hero().alive)


func test_rogue_victory_pays_and_brings_a_stronger_foe() -> void:
	var a := Arena.create(gd, {"mode": "rogue", "faction": "concord", "difficulty": "easy", "seed": 5})
	assert_eq((a.session.state.player(0)["resources"] as ResourceBank).get_amount("gold"), 3000)
	assert_true(a.enemy_hero() != null and not a.enemy_hero().army.is_empty())
	# A crushing army so the first fight is won.
	a.player_hero().army.add("pike_militia", 400)
	var first := a.enemy_worth
	var result := a.fight()
	assert_eq(int(result["winner"]), 0)
	var after := a.after_fight(result)
	assert_true(after["victory"])
	assert_eq(a.wins, 1)
	assert_gt(int(after["gold"]), 0)
	assert_gt(a.enemy_worth, first * 0.9, "next foe at least as strong")
	assert_false(a.run_over)


func test_rogue_hard_matches_player_strength() -> void:
	var a := Arena.create(gd, {"mode": "rogue", "faction": "concord", "difficulty": "hard", "seed": 9})
	a.player_hero().army.add("pike_militia", 80)
	var want := a.rogue_enemy_power(0)
	assert_between(want, a.power_of(a.player_hero()) * 0.99, a.power_of(a.player_hero()) * 1.01)
