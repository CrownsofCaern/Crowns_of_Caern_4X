extends "res://tests/test_case.gd"

var session: GameSession
var hero: Hero


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 7)
	hero = session.hero("hero_wren")


func test_start_state() -> void:
	assert_eq(session.state.day, 1)
	assert_eq(hero.pos, Vector2i(2, 8))
	assert_eq(hero.movement_left, 1500)
	assert_eq(hero.army.stack_count(), 4)
	assert_true(session.current_player()["fog"].is_explored(hero.pos))


func test_move_spends_points_by_terrain() -> void:
	var r := session.move_hero("hero_wren", Vector2i(5, 8))  # 3 road tiles
	assert_eq(r["steps"].size(), 3)
	assert_eq(hero.pos, Vector2i(5, 8))
	assert_eq(hero.movement_left, 1500 - 180)


func test_movement_runs_out() -> void:
	# Far target: the hero walks exactly the affordable prefix of the planned path.
	var plan := session.plan_path("hero_wren", Vector2i(2, 17))
	var reachable: int = plan["reachable"]
	assert_true(reachable > 0 and reachable < plan["path"].size(), "target is beyond one day")
	var r := session.move_hero("hero_wren", Vector2i(2, 17))
	assert_eq(r["steps"].size(), reachable)
	assert_eq(hero.pos, plan["path"][reachable - 1])
	var spent := 0
	for i in reachable:
		spent += plan["costs"][i]
	assert_eq(hero.movement_left, 1500 - spent)
	assert_gt(plan["costs"][reachable], hero.movement_left, "next step unaffordable")


func test_planned_destination_survives_turn_and_save() -> void:
	var target := Vector2i(2, 17)
	hero.planned_destination = target
	session.move_hero(hero.id, target)
	assert_true(hero.pos != target, "route takes more than one day")
	session.end_turn()
	var loaded := GameSession.from_state(data, GameState.from_dict(session.state.to_dict(), data))
	var restored: Hero = loaded.hero(hero.id)
	assert_eq(restored.planned_destination, target)
	var remaining := loaded.plan_path(restored.id, target)
	assert_true(not remaining["path"].is_empty(), "remaining route can be recalculated")
	loaded.move_hero(restored.id, target)
	assert_eq(restored.pos, target)


func test_old_hero_save_has_no_planned_destination() -> void:
	var saved := hero.to_dict()
	saved.erase("planned_destination")
	assert_eq(Hero.from_dict(saved).planned_destination, Vector2i(-1, -1))


func test_collect_resource() -> void:
	var bank: ResourceBank = session.current_player()["resources"]
	var wood_before := bank.get_amount("wood")
	var r := session.move_hero("hero_wren", Vector2i(3, 6))
	assert_eq(r["collected"].size(), 1)
	assert_eq(bank.get_amount("wood"), wood_before + 6)
	assert_false(session.state.map.objects.has("res_2"), "pile removed")


func test_end_turn_advances_day_and_resets_movement() -> void:
	session.move_hero("hero_wren", Vector2i(5, 8))
	session.end_turn()
	assert_eq(session.state.day, 2)
	assert_eq(hero.movement_left, hero.max_movement(data))


func test_week_rollover() -> void:
	for i in 7:
		session.end_turn()
	assert_eq(session.state.day, 8)
	assert_eq(session.state.week(), 2)
	assert_eq(session.state.day_of_week(), 1)


func test_moving_reveals_fog() -> void:
	var fog: FogOfWar = session.current_player()["fog"]
	var before := fog.explored_count()
	session.move_hero("hero_wren", Vector2i(8, 8))
	assert_gt(fog.explored_count(), before)


func test_forest_reduces_vision() -> void:
	# Same hero, vision on grass vs inside the forest.
	assert_eq(session.state.map.vision_mod(Vector2i(3, 5)), -1)
	assert_eq(session.state.map.vision_mod(Vector2i(14, 6)), 1, "rocky highland gives a vantage point")


func test_approach_neutral_offers_battle() -> void:
	var r := session.move_hero("hero_wren", Vector2i(12, 8))
	assert_eq(r["battle"], "neutral_wolves")
	assert_eq(hero.pos, Vector2i(11, 8), "hero stops adjacent")


func test_attack_resolves_and_applies_results() -> void:
	session.move_hero("hero_wren", Vector2i(12, 8))
	var creatures_before := hero.army.total_creatures()
	var r := session.attack("hero_wren", "neutral_wolves")
	assert_true(r.has("summary"))
	assert_true(hero.army.total_creatures() <= creatures_before)
	if r["winner"] == 0:
		assert_false(session.state.map.objects.has("neutral_wolves"))
		assert_eq(hero.pos, Vector2i(12, 8))
		assert_gt(r["xp_gained"], 0)
		assert_eq(hero.xp, r["xp_gained"])


func test_save_load_roundtrip() -> void:
	session.move_hero("hero_wren", Vector2i(3, 6))
	session.end_turn()
	var path := "user://test_save.json"
	assert_eq(session.save_to_file(path), OK)
	var loaded := GameSession.load_from_file(data, path)
	assert_true(loaded != null)
	assert_eq(JSON.stringify(loaded.state.to_dict()), JSON.stringify(session.state.to_dict()))
	# The loaded game continues identically, including battle randomness.
	session.move_hero("hero_wren", Vector2i(12, 8))
	loaded.move_hero("hero_wren", Vector2i(12, 8))
	var a := session.attack("hero_wren", "neutral_wolves")
	var b := loaded.attack("hero_wren", "neutral_wolves")
	assert_eq(a["seed"], b["seed"])
	assert_eq(JSON.stringify(a["sides"]), JSON.stringify(b["sides"]))


func test_rejects_invalid_save() -> void:
	assert_true(GameState.validate_save({}).size() > 0)
	var d := session.state.to_dict()
	d["version"] = 999
	assert_true(GameState.validate_save(d).size() > 0)
