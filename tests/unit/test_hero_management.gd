extends "res://tests/test_case.gd"

var session: GameSession


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 5)


func test_player_starts_with_two_heroes() -> void:
	var heroes := session.state.heroes_of(0)
	assert_eq(heroes.size(), 2)
	assert_ne(heroes[0].class_id, heroes[1].class_id, "different classes")


func test_heroes_move_independently() -> void:
	var wren := session.hero("hero_wren")
	var maelis := session.hero("hero_maelis")
	session.move_hero("hero_wren", Vector2i(5, 8))
	assert_eq(maelis.movement_left, maelis.max_movement(data), "other hero keeps its movement")
	assert_lt(wren.movement_left, wren.max_movement(data))


func test_heroes_cannot_share_or_cross_tiles() -> void:
	var maelis := session.hero("hero_maelis")
	assert_true(session.plan_path("hero_wren", maelis.pos)["path"].is_empty(), "cannot stack on a hero")
	# Wall the ranger in a corridor: path from wren around her must not pass her tile.
	var plan := session.plan_path("hero_wren", maelis.pos + Vector2i(1, 1))
	assert_false(plan["path"].has(maelis.pos))


func test_skill_offers_are_stable_distinct_and_class_based() -> void:
	var h := session.hero("hero_wren")
	assert_eq(session.skill_offers("hero_wren"), [], "no offers without points")
	h.add_xp(1000, data)
	var a := session.skill_offers("hero_wren")
	var b := session.skill_offers("hero_wren")
	assert_eq(a, b, "reopening the dialog does not reroll")
	assert_eq(a.size(), 2)
	assert_ne(a[0], a[1])
	for sk in a:
		assert_true(data.hero_classes["knight"]["skill_weights"].has(sk))


func test_learn_skill_only_from_offers() -> void:
	var h := session.hero("hero_wren")
	h.add_xp(2500, data)
	assert_eq(h.skill_points, 2)
	var offers := session.skill_offers("hero_wren")
	var not_offered := ""
	for sk in data.skills:
		if not offers.has(sk):
			not_offered = sk
			break
	assert_false(session.learn_skill("hero_wren", not_offered))
	var pick: String = offers[0]
	var lvl := h.skill_level(pick)
	assert_true(session.learn_skill("hero_wren", pick))
	assert_eq(h.skill_level(pick), lvl + 1)
	assert_eq(h.skill_points, 1)
	assert_eq(session.skill_offers("hero_wren").size(), 2, "second point still has offers")


func test_offers_skip_maxed_skills() -> void:
	var h := session.hero("hero_wren")
	for sk in data.skills:
		h.skills[sk] = data.skill_max_level
	h.skills["archery"] = 2
	h.skill_points = 1
	assert_eq(session.skill_offers("hero_wren"), ["archery"])


func test_offer_distribution_follows_class_weights() -> void:
	# Knight weights: leadership 5 ... scouting 1. Across seeds leadership should be offered far more often.
	var h := session.hero("hero_wren")
	var counts := {}
	for s in 300:
		for sk in h.skill_offers_seeded(data, 77 + s * 13):
			counts[sk] = counts.get(sk, 0) + 1
	assert_gt(counts.get("leadership", 0), counts.get("scouting", 0) * 2)
	assert_gt(counts.get("scouting", 0), 0, "rare skills still appear")


func test_marks_survive_save_and_load() -> void:
	session.hero("hero_maelis").add_mark("friend_of_the_road")
	var path := "user://test_marks_save.json"
	assert_eq(session.save_to_file(path), OK)
	var loaded := GameSession.load_from_file(data, path)
	assert_true(loaded.hero("hero_maelis").has_mark("friend_of_the_road"))
	assert_eq(loaded.state.heroes_of(0).size(), 2)


## Builds an old-format save from the current state: drops what later versions added.
func _old_save(version: int) -> Dictionary:
	var d: Dictionary = JSON.parse_string(JSON.stringify(session.state.to_dict()))
	d["version"] = version
	for id in d["heroes"]:
		d["heroes"][id].erase("marks")
	var keep := {}
	for id in d["objects"]:
		var t: String = d["objects"][id]["type"]
		if t == "encounter" or (version < 2 and t in ["town", "mine"]):
			continue
		keep[id] = d["objects"][id]
	d["objects"] = keep
	return d


func _check_migrated(version: int) -> void:
	session.hero("hero_wren").pos = Vector2i(2, 8)
	var d := _old_save(version)
	assert_eq(GameState.validate_save(d), [] as Array[String])
	var st := GameState.from_dict(d, data)
	assert_eq(st.heroes["hero_wren"].marks.size(), 0, "v%d: marks default to none" % version)
	var enc := 0
	var towns := 0
	for id in st.map.objects:
		var t: String = st.map.objects[id]["type"]
		enc += 1 if t == "encounter" else 0
		towns += 1 if t == "town" else 0
	assert_eq(enc, 13, "v%d: encounters restored from the map" % version)
	assert_gt(towns, 0, "v%d: towns present" % version)
	# Round trip: the migrated state saves as the current version and reloads identically.
	var again := st.to_dict()
	assert_eq(int(again["version"]), GameState.SAVE_VERSION)
	var st2 := GameState.from_dict(JSON.parse_string(JSON.stringify(again)), data)
	assert_eq(JSON.stringify(st2.to_dict()), JSON.stringify(again))
	# And it plays: a session on the migrated state can still meet an encounter.
	var s2 := GameSession.from_state(data, st2)
	assert_eq(s2.move_hero("hero_wren", Vector2i(6, 5))["encounter"], "enc_toll")


func test_version_one_save_migrates_and_round_trips() -> void:
	_check_migrated(1)


func test_version_two_save_migrates_and_round_trips() -> void:
	_check_migrated(2)


func test_migration_skips_encounters_on_occupied_tiles() -> void:
	var d := _old_save(2)
	d["heroes"]["hero_wren"]["pos"] = [6, 5]  # standing where the toll would be
	var st := GameState.from_dict(d, data)
	assert_false(st.map.objects.has("enc_toll"))
	assert_true(st.map.objects.has("enc_hall"))
