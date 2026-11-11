extends "res://tests/test_case.gd"
## The two ascension encounters (ember_crucible, barrow_of_the_last_rank): the
## "ascend" effect raises one random stack below level 5 to the top veteran level.

const ENCOUNTERS := ["ember_crucible", "barrow_of_the_last_rank"]


func _session(seed_value: int = 3) -> GameSession:
	return GameSession.new_game(data, "twin_marches", seed_value)


func _place(s: GameSession, h: Hero, eid: String, oid: String) -> void:
	var p := s._free_tile_near(h.pos)
	s.state.map.add_object({"id": oid, "type": "encounter", "pos": [p.x, p.y], "encounter": eid})


func _paid_choice(eid: String) -> int:
	var choices: Array = data.encounters[eid]["choices"]
	for i in choices.size():
		var c: Dictionary = choices[i]
		if not c.has("check") and not bool(c.get("leave", false)):
			return i
	return -1


func test_encounters_are_valid_and_in_the_high_risk_pool() -> void:
	assert_eq(data.validate_encounters(), [] as Array[String])
	for eid in ENCOUNTERS:
		assert_true(data.encounters.has(eid), eid)
		assert_true(data.map_templates["encounter_risk"]["high"].has(eid), "%s is placed by the generator" % eid)
		var ascends := 0
		for c in data.encounters[eid]["choices"]:
			for e in c.get("success", {}).get("effects", []):
				if e["type"] == "ascend":
					ascends += 1
		assert_eq(ascends, 2, "%s has two ways to ascend" % eid)
		assert_true(Art.sprite(EncounterSystem.sprite_id(eid, data)) != null, "%s has art" % eid)


func test_ascend_raises_one_stack_to_level_five_and_promotes_it() -> void:
	var a := Army.new()
	a.add("pike_militia", 30)
	a.add("longbowman", 12)
	a.initialize_veterans(data)
	var slot := a.ascend_random(GameRng.new(7), data)
	assert_true(slot == 0 or slot == 1, "slot %d" % slot)
	var st: Dictionary = a.slots[slot]
	assert_eq(Army.veteran_level(st), 5)
	assert_true(data.creature(st["creature"]).has("upgrade_of"), "a base creature is promoted on the way")
	assert_true(String(Army.creature_stats(st, data)["name"]).begins_with("Ascendant "))
	var other: Dictionary = a.slots[1 - slot]
	assert_eq(Army.veteran_level(other), 1, "only one stack rises")


func test_ascend_skips_stacks_already_at_level_five() -> void:
	var a := Army.new()
	a.add("pike_militia", 30)
	a.add("longbowman", 12)
	a.initialize_veterans(data)
	Army.ascend_stack(a.slots[0], data)
	assert_eq(a.ascendable_slots(), [1] as Array[int])
	for seed_value in range(1, 11):
		var b := Army.new()
		b.slots[0] = (a.slots[0] as Dictionary).duplicate()
		b.slots[1] = (a.slots[1] as Dictionary).duplicate()
		assert_eq(b.ascend_random(GameRng.new(seed_value), data), 1)
	Army.ascend_stack(a.slots[1], data)
	assert_eq(a.ascend_random(GameRng.new(1), data), -1, "nothing left to raise")


func test_random_pick_covers_every_stack() -> void:
	var seen := {}
	var rng := GameRng.new(11)
	for i in 60:
		var a := Army.new()
		a.add("pike_militia", 10)
		a.add("longbowman", 10)
		a.add("pike_veteran", 10)
		seen[a.ascend_random(rng, data)] = true
	assert_eq(seen.size(), 3, "every stack can be chosen")


func test_paid_choices_ascend_through_the_session() -> void:
	for eid in ENCOUNTERS:
		var s := _session()
		var h: Hero = s.hero("hero_west")
		h.army = Army.new()
		h.army.add("pike_militia", 30)
		h.army.add("longbowman", 12)
		h.army.initialize_veterans(data)
		h.movement_left = h.max_movement(data)
		var bank: ResourceBank = s.state.player(0)["resources"]
		for res in data.resource_order:
			bank.add(res, 10000)
		_place(s, h, eid, "enc_" + eid)
		var r := s.resolve_encounter(h.id, "enc_" + eid, _paid_choice(eid))
		assert_true(r["ok"] and r["success"], "%s: %s" % [eid, str(r)])
		var top := 0
		for st in h.army.slots:
			if not st.is_empty() and Army.veteran_level(st) == 5:
				top += 1
		assert_eq(top, 1, "%s raises exactly one stack" % eid)
		assert_true(String(r["lines"][0]).contains("veteran level 5"), str(r["lines"]))


func test_choice_is_unavailable_when_every_stack_is_at_the_top() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	h.army = Army.new()
	h.army.add("pike_militia", 30)
	Army.ascend_stack(h.army.slots[0], data)
	for res in data.resource_order:
		s.state.player(0)["resources"].add(res, 10000)
	_place(s, h, "barrow_of_the_last_rank", "enc_barrow")
	var opts := s.encounters.options(h, s.state.map.objects["enc_barrow"])
	var c: Dictionary = opts["choices"][_paid_choice("barrow_of_the_last_rank")]
	assert_false(c["available"])
	assert_true(String(c["reason"]).contains("top veteran level"), String(c["reason"]))


func test_ai_values_ascension() -> void:
	var s := _session()
	var ai := StrategicAI.new(s, 0)
	var h: Hero = s.hero("hero_west")
	h.army = Army.new()
	h.army.add("pike_militia", 30)
	h.army.initialize_veterans(data)
	assert_gt(ai._effects_value(h, [{"type": "ascend"}]), 0.0)
	Army.ascend_stack(h.army.slots[0], data)
	assert_eq(ai._effects_value(h, [{"type": "ascend"}]), 0.0)
