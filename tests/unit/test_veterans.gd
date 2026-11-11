extends "res://tests/test_case.gd"

func test_progression_and_upgrade() -> void:
	var h := Hero.create({"id": "h", "name": "Test", "class": "knight", "pos": [0, 0], "army": [["pike_militia", 5]]}, data)
	h.add_xp(1500, data)
	assert_eq(Army.veteran_level(h.army.slots[0]), 2)
	h.add_xp(3500, data)
	assert_eq(Army.veteran_level(h.army.slots[0]), 3)
	assert_eq(h.army.slots[0]["creature"], "pike_veteran")
	h.add_xp(30000, data)
	assert_eq(Army.veteran_level(h.army.slots[0]), 5)

func test_merge_weighted_and_different_levels() -> void:
	var a := Army.new()
	a.add("pike_militia", 3, 200)
	a.add("pike_militia", 1, 1000)
	assert_eq(int(a.slots[0]["veteran_xp"]), 400)
	a.add("pike_militia", 1, 1500)
	assert_eq(a.stack_count(), 2)
	assert_eq(Army.from_dict(a.to_dict()).slots, a.slots)

func test_training_skill_and_legacy_upgrade() -> void:
	var h := Hero.create({"id": "h", "name": "Test", "class": "knight", "pos": [0, 0], "army": [["pike_veteran", 5]]}, data)
	assert_eq(Army.veteran_level(h.army.slots[0]), 3)
	h.skills["veteran_training"] = 2
	h.add_xp(1000, data)
	assert_eq(int(h.army.slots[0]["veteran_xp"]), 6200)
