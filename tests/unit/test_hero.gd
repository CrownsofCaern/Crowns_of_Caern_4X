extends "res://tests/test_case.gd"

func _knight() -> Hero:
	return Hero.create({"id": "h", "name": "Test", "class": "knight", "pos": [0, 0], "army": [["pike_militia", 5]]}, data)


func test_class_stats_and_starting_skill() -> void:
	var h := _knight()
	assert_eq(h.level, 1)
	assert_eq(h.defense, 2)
	assert_eq(h.skill_level("leadership"), 1)


func test_slow_progression_thresholds() -> void:
	var h := _knight()
	assert_eq(h.add_xp(999, data), 0)
	assert_eq(h.add_xp(1, data), 1)
	assert_eq(h.level, 2)
	# A big single-map haul still only yields a couple of levels.
	assert_eq(h.add_xp(3500, data), 2)
	assert_eq(h.level, 4)
	assert_eq(h.skill_points, 3)


func test_level_up_grants_primary_stat() -> void:
	var h := _knight()
	var total_before := h.attack + h.defense + h.power + h.knowledge
	h.add_xp(2500, data)
	assert_eq(h.attack + h.defense + h.power + h.knowledge, total_before + 2)


func test_learn_skill_respects_points_and_cap() -> void:
	var h := _knight()
	assert_false(h.learn_skill("logistics", data), "no points")
	h.add_xp(16500, data)
	assert_true(h.learn_skill("logistics", data))
	assert_eq(h.max_movement(data), 1650)
	assert_true(h.learn_skill("leadership", data))
	assert_true(h.learn_skill("leadership", data))
	assert_false(h.learn_skill("leadership", data), "max level")
	assert_false(h.learn_skill("no_such_skill", data))


func test_skill_offers_follow_class() -> void:
	var h := _knight()
	assert_eq(h.skill_offers(data), ["class_knight", "leadership"])   # weight 5 each, ties by id


func test_scouting_extends_vision() -> void:
	var h := _knight()
	var base := h.vision_radius(data)
	h.skills["scouting"] = 2
	assert_eq(h.vision_radius(data), base + 2)


func test_serialization_roundtrip() -> void:
	var h := _knight()
	h.add_xp(1200, data)
	var h2 := Hero.from_dict(JSON.parse_string(JSON.stringify(h.to_dict())))
	assert_eq(JSON.stringify(h2.to_dict()), JSON.stringify(h.to_dict()))


func test_resource_bank() -> void:
	var b := ResourceBank.new({"gold": 100, "wood": 2})
	assert_true(b.can_afford({"gold": 100}))
	assert_false(b.spend({"gold": 50, "wood": 3}), "all or nothing")
	assert_eq(b.get_amount("gold"), 100)
	assert_true(b.spend({"gold": 60, "wood": 2}))
	assert_eq(b.get_amount("gold"), 40)
	assert_eq(b.get_amount("wood"), 0)


func test_army_merge_and_slots() -> void:
	var a := Army.from_pairs([["pike_militia", 5], ["longbowman", 3], ["pike_militia", 2]])
	assert_eq(a.stack_count(), 2)
	assert_eq(a.total_creatures(), 10)
	a.set_survivors({0: 0, 1: 2})
	assert_eq(a.stack_count(), 1)
	assert_eq(a.total_creatures(), 2)
