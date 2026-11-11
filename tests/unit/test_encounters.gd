extends "res://tests/test_case.gd"

var session: GameSession
var hero: Hero


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 11)
	hero = session.hero("hero_wren")


## Places an encounter next to the given hero and returns its object id.
func _place(encounter_id: String, h: Hero = null, offset := Vector2i(1, 0)) -> String:
	if h == null:
		h = hero
	var p := h.pos + offset
	var existing := session.state.map.object_at(p)
	if not existing.is_empty():
		session.state.map.remove_object(existing["id"])
	var id := "test_" + encounter_id
	session.state.map.add_object({"id": id, "type": "encounter", "pos": [p.x, p.y], "encounter": encounter_id})
	return id


func _choice(opts: Dictionary, text: String) -> Dictionary:
	for c in opts["choices"]:
		if c["text"] == text:
			return c
	_fail("no choice '%s'" % text)
	return {}


func _add_hero(id: String, cls: String, pos: Vector2i, army: Array = [["cinderling", 20]]) -> Hero:
	var h := Hero.create({"id": id, "name": id, "class": cls, "owner": 0, "pos": [pos.x, pos.y], "army": army}, data)
	session.state.heroes[id] = h
	return h


func _bank() -> ResourceBank:
	return session.current_player()["resources"]


# ------------------------------------------------------------------ data --

func test_encounter_data_is_valid_and_rich() -> void:
	assert_eq(data.validate_encounters(), [] as Array[String])
	assert_true(data.encounters.size() >= 10, "at least ten encounter types")
	for eid in data.encounters:
		var has_leave_or_force := false
		for c in data.encounters[eid]["choices"]:
			if not bool(c.get("leave", false)):
				has_leave_or_force = true
		assert_true(has_leave_or_force, "%s offers a real choice" % eid)


func _marks_read(cond: Dictionary, out: Dictionary) -> void:
	for k in ["mark", "no_mark"]:
		if cond.has(k):
			out[cond[k]] = true
	for sub in cond.get("any", []):
		_marks_read(sub, out)


func test_every_mark_has_a_consequence() -> void:
	# A mark is only meaningful if some condition or chance modifier reads it.
	var read := {}
	for eid in data.encounters:
		for c in data.encounters[eid]["choices"]:
			_marks_read(c.get("requires", {}), read)
			for m in c.get("check", {}).get("mods", []):
				_marks_read(m["when"], read)
	for mark in data.encounter_rules["marks"]:
		assert_true(read.has(mark), "mark %s is read by a condition" % mark)


func test_validation_catches_bad_encounters() -> void:
	var d := GameData.new()
	d.load_all(GameData.DATA_DIR)
	d.encounters = {"bad": {"name": "x", "text": "y", "choices": [
		{"text": "a", "requires": {"klass": ["knight"]}, "success": {"effects": [{"type": "teleport"}]}},
		{"text": "b", "check": {"chance": 2.0}, "success": {"effects": [{"type": "mark", "mark": "nope"}]}}]}}
	var errors := d.validate_encounters()
	assert_true(errors.size() >= 4, str(errors))


func test_map_encounters_reference_valid_types_on_free_tiles() -> void:
	var seen := {}
	var count := 0
	for id in session.state.map.objects:
		var o: Dictionary = session.state.map.objects[id]
		var p := AdventureMap.object_pos(o)
		assert_false(seen.has(p), "one object per tile at %s" % p)
		seen[p] = true
		if o["type"] == "encounter":
			count += 1
			assert_true(data.encounters.has(o["encounter"]), "known encounter %s" % o["encounter"])
			assert_true(session.state.map.is_passable(p), "%s on passable tile" % id)
	assert_true(count >= 10)


# --------------------------------------------------------------- flow ---

func test_walking_into_encounter_stops_adjacent() -> void:
	var r := session.move_hero("hero_wren", Vector2i(6, 5))  # brigand toll on the north road
	assert_eq(r["encounter"], "enc_toll")
	var d: Vector2i = hero.pos - Vector2i(6, 5)
	assert_true(maxi(absi(d.x), absi(d.y)) == 1, "hero adjacent to encounter")
	assert_eq(r["battle"], "")


func test_encounters_block_paths_through_them() -> void:
	var path: Array = session.plan_path("hero_wren", Vector2i(6, 3))["path"]
	assert_false(path.has(Vector2i(6, 5)), "route goes around the toll")


func test_must_be_adjacent_to_resolve() -> void:
	var r := session.resolve_encounter("hero_wren", "enc_hall", 1)
	assert_false(r["ok"])
	assert_true(session.state.map.objects.has("enc_hall"))


func test_cost_is_paid_and_effect_applied() -> void:
	var id := _place("blind_cartographer")
	var fog: FogOfWar = session.current_player()["fog"]
	var gold := _bank().get_amount("gold")
	var explored := fog.explored_count()
	var r := session.resolve_encounter("hero_wren", id, 0)
	assert_true(r["ok"] and r["success"])
	assert_eq(_bank().get_amount("gold"), gold - 750)
	assert_gt(fog.explored_count(), explored)
	assert_false(session.state.map.objects.has(id), "one-shot encounter removed")


func test_unaffordable_choice_is_refused() -> void:
	var id := _place("blind_cartographer")
	_bank().spend({"gold": _bank().get_amount("gold") - 100})
	var c := _choice(session.encounter_options("hero_wren", id), "Buy his charts")
	assert_false(c["available"])
	assert_true(c["reason"].contains("Gold"))
	var r := session.resolve_encounter("hero_wren", id, 0)
	assert_false(r["ok"])
	assert_eq(_bank().get_amount("gold"), 100)
	assert_true(session.state.map.objects.has(id))


func test_leave_keeps_encounter() -> void:
	var id := _place("hall_of_echoes")
	var r := session.resolve_encounter("hero_wren", id, 2)
	assert_true(r["ok"] and r["leave"])
	assert_true(session.state.map.objects.has(id))


func test_requirements_depend_on_faction_and_class() -> void:
	var id := _place("dispossessed_column")
	var opts := session.encounter_options("hero_wren", id)
	assert_true(_choice(opts, "Share provisions and offer them service")["available"])
	assert_false(_choice(opts, "Press the able-bodied into service")["available"])
	var warlord := _add_hero("h_ash", "warlord", Vector2i(8, 16))
	var id2 := _place("dispossessed_column", warlord)
	var opts2 := session.encounter_options("h_ash", id2)
	assert_false(_choice(opts2, "Share provisions and offer them service")["available"])
	assert_true(_choice(opts2, "Press the able-bodied into service")["available"])
	# Ranger may trade stories with the cartographer, a knight without scouting may not.
	var cid := _place("blind_cartographer")
	assert_false(_choice(session.encounter_options("hero_wren", cid), "Trade stories of the road")["available"])
	var maelis := session.hero("hero_maelis")
	var cid2 := _place("blind_cartographer", maelis, Vector2i(0, 1))
	assert_true(_choice(session.encounter_options("hero_maelis", cid2), "Trade stories of the road")["available"])


func test_chance_depends_on_skills_class_and_terrain() -> void:
	var maelis := session.hero("hero_maelis")
	var id := _place("thornwolf_den", maelis)
	var tame := "Try to tame the pack"
	var base: float = _choice(session.encounter_options("hero_maelis", id), tame)["chance"]
	maelis.skills["scouting"] = 3
	var skilled: float = _choice(session.encounter_options("hero_maelis", id), tame)["chance"]
	assert_between(skilled - base, 0.19, 0.21, "scouting +0.1 per level")
	# Same den in a forest is easier.
	var forest := _add_hero("h_forest", "ranger", Vector2i(3, 6))
	forest.skills["scouting"] = 3
	var fid := _place("thornwolf_den", forest, Vector2i(-1, 0))  # (2,6) is forest
	assert_eq(session.state.map.terrain_at(Vector2i(2, 6)), "forest")
	var in_forest: float = _choice(session.encounter_options("h_forest", fid), tame)["chance"]
	assert_between(in_forest - skilled, 0.14, 0.16)
	# Seal the rift: the warlock's power helps; on infernal ground it is harder.
	var wl := _add_hero("h_wl", "warlock", Vector2i(12, 16))
	var rid := _place("ember_rift", wl)
	var on_grass: float = _choice(session.encounter_options("h_wl", rid), "Seal the rift")["chance"]
	var wl2 := _add_hero("h_wl2", "warlock", Vector2i(21, 2))
	var rid2 := _place("ember_rift", wl2, Vector2i(1, 0))
	assert_eq(session.state.map.terrain_at(Vector2i(22, 2)), "infernal")
	var on_infernal: float = _choice(session.encounter_options("h_wl2", rid2), "Seal the rift")["chance"]
	assert_between(on_grass - on_infernal, 0.14, 0.16)


func test_ambush_spawns_neutral_army_and_battle() -> void:
	var id := _place("thornwolf_den")
	var r := session.resolve_encounter("hero_wren", id, 1)  # smoke them out: always a fight
	assert_true(r["ok"])
	assert_ne(r["battle"], "")
	var army: Dictionary = session.state.map.objects[r["battle"]]
	assert_eq(army["type"], "neutral_army")
	assert_eq(army["stacks"][0][0], "thornwolf")
	assert_eq(int(army["stacks"][0][1]), 7)
	var b := session.attack("hero_wren", r["battle"])
	assert_true(b.has("winner"))


func test_counts_scale_with_week() -> void:
	for i in 14:
		session.end_turn()
	assert_eq(session.state.week(), 3)
	var id := _place("dispossessed_column")
	var before := hero.army.total_creatures()
	var r := session.resolve_encounter("hero_wren", id, 0)
	assert_true(r["success"])
	assert_eq(hero.army.total_creatures(), before + 8 + 2 * 2)
	assert_true(hero.has_mark("shelter_giver"))


func test_recruit_needs_army_room() -> void:
	hero.army = Army.from_pairs([["lancer", 1], ["longbowman", 1], ["shieldwarden", 1], ["lightbearer", 1],
		["sunhawk_rider", 1], ["bastion_colossus", 1], ["flayer", 1], ["cinderling", 1], ["scorchhound", 1], ["pike_militia", 1]])
	var id := _place("free_company_camp")
	var c := _choice(session.encounter_options("hero_wren", id), "Hire the slingers")
	assert_false(c["available"])
	assert_true(c["reason"].contains("slot"))


func test_casualties_never_destroy_the_army() -> void:
	hero.army = Army.from_pairs([["pike_militia", 1]])
	var sys := session.encounters
	var out := {"lines": []}
	sys._apply({"type": "casualties", "fraction": 0.5}, hero, {"pos": [0, 0]}, out)
	assert_eq(hero.army.total_creatures(), 1)
	hero.army = Army.from_pairs([["pike_militia", 20], ["lancer", 4]])
	sys._apply({"type": "casualties", "fraction": 0.15, "role": "infantry"}, hero, {"pos": [0, 0]}, out)
	assert_eq(hero.army.total_creatures(), 17 + 4, "only infantry hurt")


func test_marks_gate_later_encounters_and_persist() -> void:
	var id := _place("free_company_camp")
	var negotiate := "Negotiate as a friend of the road"
	assert_false(_choice(session.encounter_options("hero_wren", id), negotiate)["available"])
	var cid := _place("dying_courier", hero, Vector2i(0, 1))
	var r := session.resolve_encounter("hero_wren", cid, 0)
	assert_true(r["ok"])
	assert_true(hero.has_mark("friend_of_the_road"))
	assert_true(_choice(session.encounter_options("hero_wren", id), negotiate)["available"])
	# Marks are campaign state: they survive save/load.
	var h2 := Hero.from_dict(JSON.parse_string(JSON.stringify(hero.to_dict())))
	assert_true(h2.has_mark("friend_of_the_road"))
	# Robbing a courier closes the friendly price for good.
	hero.add_mark("oathbreaker")
	assert_false(_choice(session.encounter_options("hero_wren", id), negotiate)["available"])


func test_skill_point_encounter_requires_level() -> void:
	var id := _place("hall_of_echoes")
	_bank().add("crystal", 5)
	var study := "Study the inscriptions"
	assert_false(_choice(session.encounter_options("hero_wren", id), study)["available"])
	hero.add_xp(1000, data)
	var points := hero.skill_points
	assert_true(_choice(session.encounter_options("hero_wren", id), study)["available"])
	var r := session.resolve_encounter("hero_wren", id, 0)
	assert_true(r["ok"])
	assert_eq(hero.skill_points, points + 1)


func test_resolution_is_deterministic_under_seed() -> void:
	var outcomes := []
	for run in 2:
		before_each()
		var id := _place("overturned_wagon")
		outcomes.append(session.resolve_encounter("hero_wren", id, 0)["success"])
	assert_eq(outcomes[0], outcomes[1])


func test_success_rate_matches_shown_chance() -> void:
	# Statistical: 400 rolls of a 55% check with a fixed seed.
	var wins := 0
	for i in 400:
		session = GameSession.new_game(data, "ember_ford", 1000 + i)
		hero = session.hero("hero_wren")
		var id := _place("overturned_wagon")
		var chance: float = session.encounter_options("hero_wren", id)["choices"][0]["chance"]
		assert_between(chance, 0.549, 0.551)
		if session.resolve_encounter("hero_wren", id, 0)["success"]:
			wins += 1
	assert_between(wins / 400.0, 0.45, 0.65)


func test_encounter_xp_stays_modest() -> void:
	# Slow progression: no single encounter grants a level from scratch.
	for eid in data.encounters:
		for c in data.encounters[eid]["choices"]:
			for key in ["success", "failure"]:
				for e in c.get(key, {}).get("effects", []):
					if e["type"] == "xp":
						assert_true(int(e["amount"]) <= 500, "%s xp %d" % [eid, int(e["amount"])])
