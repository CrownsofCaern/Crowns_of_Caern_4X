extends "res://tests/test_case.gd"
## Starting heroes: a standard game (a skirmish from the new-game menu) gives
## every player one hero, Frostmarch two (a faction trait), leading tier 1-2
## creatures only; maps played without
## a standard start, and campaigns, keep the heroes the map places.


func _setup(map_id: String, factions: Array = []) -> Dictionary:
	var entry := GameSetup.map_entry(data, map_id)
	var setup := GameSetup.default_setup(entry)
	for i in factions.size():
		setup["players"][i]["faction"] = factions[i]
	setup["standard_start"] = true
	return setup


func _ids(s: GameSession, owner: int) -> Array:
	var out := []
	for h in s.state.heroes_of(owner):
		out.append(h.id)
	return out


func test_rules_default_to_one_hero_and_frostmarch_starts_with_two() -> void:
	assert_eq(int(data.rules["starting_heroes"]), 1)
	assert_eq(data.starting_heroes("concord"), 1)
	assert_eq(data.starting_heroes("ashen"), 1)
	assert_eq(data.starting_heroes("frostmarch"), 2)
	var others := 0
	for f in GameSetup.playable_factions(data):
		if data.starting_heroes(f) > 1:
			others += 1
	assert_eq(others, 1, "only one faction has the extra hero")


func test_standard_start_trims_a_campaign_maps_extra_heroes() -> void:
	# burning_ford places two heroes for player 0 (a campaign map).
	var plain := GameSession.new_game(data, "burning_ford", 3)
	assert_eq(plain.state.heroes_of(0).size(), 2, "without a standard start the map's heroes stay")
	var s := GameSession.new_game(data, "burning_ford", 3, _setup("burning_ford"))
	assert_eq(_ids(s, 0), ["hero_wren"], "the map's lead hero is kept")
	assert_eq(_ids(s, 1), ["hero_skarn"])


func test_frostmarch_gets_a_second_hero_from_its_tavern() -> void:
	var s := GameSession.new_game(data, "twin_marches", 5, _setup("twin_marches", ["frostmarch", "ashen"]))
	var heroes := s.state.heroes_of(0)
	assert_eq(heroes.size(), 2)
	assert_eq(s.state.heroes_of(1).size(), 1)
	var second: Hero = heroes[1]
	assert_eq(second.id, "hire_frostmarch_1", "the map hero took the tavern's first frostmarch hero")
	assert_eq(String(data.hero_classes[second.class_id]["faction"]), "frostmarch")
	assert_true(s.state.map.is_passable(second.pos))
	assert_true(s.state.map.object_at(second.pos).is_empty(), "the second hero stands on a free tile")
	assert_ne(second.pos, heroes[0].pos)
	assert_true(heroes[0].pos.distance_to(second.pos) <= 3.0, "next to the first hero")
	assert_false(second.army.is_empty(), "the second hero brings the tavern's army")
	# The tavern does not offer the second hero again.
	var town_id := ""
	for t in s.towns_of(0):
		town_id = t["id"]
	assert_ne(String(s.hire_offer(town_id).get("id", "")), second.id)


func test_frostmarch_on_both_sides_never_shares_a_hero() -> void:
	var s := GameSession.new_game(data, "twin_marches", 5, _setup("twin_marches", ["frostmarch", "frostmarch"]))
	var seen := {}
	for owner in 2:
		assert_eq(s.state.heroes_of(owner).size(), 2)
		for h in s.state.heroes_of(owner):
			assert_false(seen.has(h.id), "hero %s twice" % h.id)
			seen[h.id] = true


func test_standard_start_on_a_generated_map() -> void:
	var entry := {}
	for m in GameSetup.available_maps(data):
		if bool(m["generated"]):
			entry = m
			break
	var setup := GameSetup.default_setup(entry)
	setup["players"][0]["faction"] = "frostmarch"
	setup["players"][0]["hero_class"] = "reaver"
	setup["standard_start"] = true
	var map_id := GameSetup.map_id_for(entry, 4)
	var s := GameSession.new_game(data, map_id, 4, setup)
	assert_eq(s.state.heroes_of(0).size(), 2)
	assert_eq(s.state.heroes_of(0)[0].class_id, "reaver")
	for i in range(1, s.state.players.size()):
		assert_eq(s.state.heroes_of(i).size(), data.starting_heroes(String(s.state.players[i]["faction"])))


func test_standard_start_is_deterministic() -> void:
	var a := GameSession.new_game(data, "twin_marches", 9, _setup("twin_marches", ["frostmarch", "hollow"]))
	var b := GameSession.new_game(data, "twin_marches", 9, _setup("twin_marches", ["frostmarch", "hollow"]))
	assert_eq(_ids(a, 0), _ids(b, 0))
	assert_eq(a.state.heroes_of(0)[1].pos, b.state.heroes_of(0)[1].pos)


func test_campaign_chapters_keep_their_cast() -> void:
	# Campaigns never ask for a standard start: a chapter's map keeps its heroes.
	for cid in data.campaigns:
		for ch in data.campaigns[cid]["chapters"]:
			assert_false(Campaign.chapter_setup(ch).has("standard_start"), "%s %s" % [cid, ch.get("id", "")])
	# A chapter on a map that gives the player several heroes keeps them all.
	var c := Campaign.start(data, "last_light", 4)
	var chapters: Array = c.definition(data)["chapters"]
	for i in chapters.size():
		var def := data.load_map(String(chapters[i]["map"]))
		var on_map := 0
		for hd in def["heroes"]:
			if int(hd["owner"]) == 0:
				on_map += 1
		if on_map < 2 or not (chapters[i].get("cast", []) as Array).is_empty():
			continue
		c.chapter = i
		var s := c.begin_chapter(data)
		assert_eq(s.state.heroes_of(0).size(), on_map, "chapter %d keeps its heroes" % i)
		return
	_fail("no last_light chapter on a map with several heroes")


func test_ai_plays_with_two_starting_heroes() -> void:
	var setup := _setup("twin_marches", ["frostmarch", "concord"])
	setup["players"][0]["type"] = "computer"
	var s := GameSession.new_game(data, "twin_marches", 23, setup)
	for p in s.state.players:
		p["is_human"] = false
	var moved := {}
	for _turn in 8:
		var idx := s.state.current_player
		var before := {}
		for h in s.state.heroes_of(idx):
			before[h.id] = h.pos
		StrategicAI.new(s, idx).play_turn()
		for h in s.state.heroes_of(idx):
			if before.has(h.id) and before[h.id] != h.pos:
				moved[h.id] = true
		s.end_turn()
	assert_true(moved.has("hire_frostmarch_1"), "the AI uses its second starting hero")


func test_standard_start_armies_hold_tier_one_and_two_only() -> void:
	var plain := GameSession.new_game(data, "twin_marches", 3)
	var top := 0
	for st in plain.state.heroes_of(0)[0].army.slots:
		if not st.is_empty():
			top = maxi(top, int(data.creature(st["creature"])["tier"]))
	assert_gt(top, 2, "the map's own army has higher tiers")
	var s := GameSession.new_game(data, "twin_marches", 3, _setup("twin_marches", ["concord", "frostmarch"]))
	for h in s.state.heroes.values():
		assert_false(h.army.is_empty(), "%s keeps an army" % h.id)
		for st in h.army.slots:
			if not st.is_empty():
				assert_true(int(data.creature(st["creature"])["tier"]) <= 2, "%s leads %s" % [h.id, st["creature"]])
	var west: Hero = s.state.heroes_of(0)[0]
	assert_eq(west.army.total_creatures(), 24 + 14, "the tier 1 and 2 stacks stay whole")


func test_campaign_armies_are_untouched() -> void:
	# A chapter whose map gives the player's lead hero tier 3+ creatures keeps them.
	var c := Campaign.start(data, "last_light", 4)
	var chapters: Array = c.definition(data)["chapters"]
	for i in chapters.size():
		var def := data.load_map(String(chapters[i]["map"]))
		var lead := String(c.definition(data)["heroes"][0])
		var top := 0
		for hd in def["heroes"]:
			if String(hd["id"]) == lead:
				for pair in hd["army"]:
					top = maxi(top, int(data.creature(String(pair[0]))["tier"]))
		if top <= 2:
			continue
		c.chapter = i
		var s := c.begin_chapter(data)
		var got := 0
		for st in s.hero(lead).army.slots:
			if not st.is_empty():
				got = maxi(got, int(data.creature(st["creature"])["tier"]))
		assert_eq(got, top, "chapter %d keeps its lead hero's army" % i)
		return
	_fail("no last_light chapter gives the lead hero tier 3+ creatures")


func test_validation_rejects_bad_starting_heroes() -> void:
	var d := GameData.new()
	d.load_all(GameData.DATA_DIR)
	d.rules["starting_heroes"] = 0
	d.factions["frostmarch"]["starting_heroes"] = 99
	d.rules["starting_army_max_tier"] = 0
	var joined := "\n".join(d.validate())
	assert_true(joined.contains("game_rules starting_heroes"), joined)
	assert_true(joined.contains("faction frostmarch starting_heroes"), joined)
	assert_true(joined.contains("starting_army_max_tier"), joined)


func test_selected_class_sets_the_lead_hero_and_starting_skills() -> void:
	var setup := _setup("twin_marches", ["frostmarch", "ashen"])
	setup["players"][0]["hero_class"] = "frostcaller"
	var s := GameSession.new_game(data, "twin_marches", 5, setup)
	var heroes := s.state.heroes_of(0)
	assert_eq(heroes.size(), 2)
	assert_eq(heroes[0].class_id, "frostcaller")
	assert_eq(heroes[0].skill_level("fieldcraft"), 1)
	assert_eq(heroes[0].power, int(data.hero_classes["frostcaller"]["power"]))
	assert_eq(String(data.hero_classes[heroes[1].class_id]["faction"]), "frostmarch")


func test_setup_rejects_a_class_from_another_faction() -> void:
	var setup := _setup("twin_marches", ["concord", "ashen"])
	setup["players"][0]["hero_class"] = "warlock"
	assert_false(GameSetup.validate(data.load_map("twin_marches"), setup, data).is_empty())


func test_every_class_has_exclusive_and_faction_specialties() -> void:
	for id in data.hero_classes:
		var cls: Dictionary = data.hero_classes[id]
		var own := "class_" + String(id)
		var faction := "faction_" + String(cls["faction"])
		assert_true(data.skills.has(own), own)
		assert_true(data.skills.has(faction), faction)
		assert_gt(int(cls["skill_weights"].get(own, 0)), 0)
		assert_gt(int(cls["skill_weights"].get(faction, 0)), 0)
		for other in data.hero_classes:
			if other != id:
				assert_false(data.hero_classes[other]["skill_weights"].has(own), own)
