extends "res://tests/test_case.gd"


func test_cross_system_quest_references_are_validated() -> void:
	var map := data.load_map("last_watch")
	var sc: Dictionary = map["scenario"].duplicate(true)
	sc["quests"][0]["reward"]["hero"]["id"] = sc["waves"][0]["hero"]["id"]
	assert_false(ScenarioRules.validate(sc, map, data).is_empty(), "ally cannot replace an invasion commander")
	sc = map["scenario"].duplicate(true)
	sc["quests"][0]["reward"]["hero"]["army"] = [["not_a_creature", 5]]
	assert_false(ScenarioRules.validate(sc, map, data).is_empty())
	sc = map["scenario"].duplicate(true)
	sc["quests"][0]["reward"]["weekly"]["town"] = "missing"
	assert_false(ScenarioRules.validate(sc, map, data).is_empty())
	sc = map["scenario"].duplicate(true)
	sc["quests"][0]["reward"]["hero"] = []
	assert_false(ScenarioRules.validate(sc, map, data).is_empty())


func test_layout_recipe_validation_rejects_missing_ring_order() -> void:
	var original: Dictionary = data.map_templates["templates"]["fair_ringlands_v1"].duplicate(true)
	data.map_templates["templates"]["fair_ringlands_v1"].erase("ring_order")
	var errors := MapGenerator.validate_templates(data)
	data.map_templates["templates"]["fair_ringlands_v1"] = original
	assert_true(errors.any(func(e): return e.contains("ring_order")))


func test_required_relic_cannot_be_claimed_while_its_guardian_stands() -> void:
	# The relic marsh is open (guard rule #135): the guardian blocks the claim, not walls.
	var s := GameSession.new_game(data, "last_watch", 7)
	var h := s.hero("hero_watch")
	var relic: Dictionary = s.state.map.objects["relic_oath"]
	assert_eq(String(relic.get("guarded_by", "")), "guardian_oath")
	var guardian_pos := AdventureMap.object_pos(s.state.map.objects["guardian_oath"])
	var relic_pos := AdventureMap.object_pos(relic)
	assert_lt(maxi(absi(guardian_pos.x - relic_pos.x), absi(guardian_pos.y - relic_pos.y)), 2, "the guardian stands next to the relic")
	assert_false(ScenarioQuests.collect(s, h, relic), "the relic stays while guardian_oath stands")
	assert_true(s.state.map.objects.has("relic_oath"))
	s.state.map.remove_object("guardian_oath")
	assert_true(ScenarioQuests.collect(s, h, relic), "beating the guardian frees the relic")
	assert_true(ScenarioQuests.items(s.state, "hero_watch").has("reed_oathstone"))
