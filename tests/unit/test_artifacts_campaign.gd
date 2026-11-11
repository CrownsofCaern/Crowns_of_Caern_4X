extends "res://tests/test_case.gd"
## Equipment, hero effects on the economy and after battles, and the campaign
## layer (veterans, level caps, kept artifacts, campaign saves).

var session: GameSession


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 21)


func _add_hero(id: String, cls: String, pos: Vector2i, army: Array) -> Hero:
	var h := Hero.create({"id": id, "name": id, "class": cls, "owner": 0, "pos": [pos.x, pos.y], "army": army}, data)
	session.state.heroes[id] = h
	return h


# -------------------------------------------------------------- equipment --

func test_pick_up_and_wear_artifact() -> void:
	var wren := session.hero("hero_wren")
	var before := wren.total_attr("attack", data)
	wren.pos = Vector2i(8, 3)
	var r := session.move_hero("hero_wren", Vector2i(9, 3))
	assert_eq(r["steps"].size(), 1)
	assert_false(session.state.map.objects.has("art_falchion"), "picked up")
	assert_eq(wren.equipment.get("weapon", ""), "notched_falchion")
	assert_eq(wren.total_attr("attack", data), before + 1)
	assert_eq(int(wren.combat_profile(data)["attack"]), before + 1)


func test_pack_equip_and_swap() -> void:
	var h := session.hero("hero_wren")
	assert_true(h.give_artifact("notched_falchion", data))
	assert_true(h.give_artifact("bleeding_glaive", data))
	assert_eq(h.equipment["weapon"], "notched_falchion")
	assert_eq(h.pack, ["bleeding_glaive"] as Array[String])
	assert_true(session.equip_artifact("hero_wren", "bleeding_glaive")["ok"])
	assert_eq(h.equipment["weapon"], "bleeding_glaive")
	assert_eq(h.pack, ["notched_falchion"] as Array[String])
	assert_true(session.unequip_artifact("hero_wren", "weapon")["ok"])
	assert_false(h.equipment.has("weapon"))
	assert_false(session.equip_artifact("hero_wren", "longwatch_bow")["ok"], "not carried")


func test_pack_has_a_limit() -> void:
	var h := session.hero("hero_wren")
	h.give_artifact("notched_falchion", data)
	for i in int(data.artifact_rules["pack_size"]):
		assert_true(h.give_artifact("cinderbrand_rod", data))
	assert_false(h.give_artifact("cinderbrand_rod", data), "pack full")


func test_give_artifact_between_adjacent_heroes() -> void:
	var wren := session.hero("hero_wren")
	var maelis := session.hero("hero_maelis")
	wren.give_artifact("longwatch_bow", data)
	assert_false(session.give_artifact("hero_wren", "hero_maelis", "longwatch_bow")["ok"], "too far apart")
	maelis.pos = wren.pos + Vector2i(1, 1)
	assert_true(session.give_artifact("hero_wren", "hero_maelis", "longwatch_bow")["ok"])
	assert_eq(maelis.equipment.get("weapon", ""), "longwatch_bow")
	assert_false(wren.all_artifacts(data).has("longwatch_bow"))


func test_encounter_artifact_effect_validates() -> void:
	var errors: Array[String] = []
	data._validate_effect({"type": "artifact", "artifact": "nope"}, "t", {}, errors)
	assert_eq(errors.size(), 1)
	errors.clear()
	data._validate_effect({"type": "artifact", "artifact": "bone_dice"}, "t", {}, errors)
	assert_eq(errors.size(), 0)


func test_save_keeps_equipment_and_migrates_v5() -> void:
	var wren := session.hero("hero_wren")
	wren.give_artifact("scarred_plate", data)
	wren.give_artifact("riveted_hauberk", data)
	var d := session.state.to_dict()
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	var loaded := GameSession.from_state(data, GameState.from_dict(JSON.parse_string(JSON.stringify(d)), data))
	assert_eq(loaded.hero("hero_wren").equipment["armor"], "scarred_plate")
	assert_eq(loaded.hero("hero_wren").pack, ["riveted_hauberk"] as Array[String])
	# A version 5 save: no equipment fields and no artifact objects.
	var old: Dictionary = JSON.parse_string(JSON.stringify(d))
	old["version"] = 5
	for id in old["heroes"]:
		old["heroes"][id].erase("equipment")
		old["heroes"][id].erase("pack")
		old["heroes"][id].erase("level_cap")
	for id in ["art_falchion", "art_lantern", "art_quill"]:
		old["objects"].erase(id)
	var migrated := GameState.from_dict(old, data)
	assert_true(migrated.map.objects.has("art_quill"), "map artifacts added")
	assert_true(migrated.heroes["hero_wren"].equipment.is_empty())


# ------------------------------------------------- economy and aftermath --

func test_stewardship_income_and_quartermaster_discount() -> void:
	var wren := session.hero("hero_wren")
	var base := int(session.daily_income(0).get("gold", 0))
	wren.skills["stewardship"] = 2
	assert_eq(int(session.daily_income(0).get("gold", 0)), base + 300)
	wren.pos = Vector2i(1, 8)  # in Greyhold
	var full := int(Town.recruit_cost("pike_militia", 10, data)["gold"])
	assert_eq(int(session.recruit_price("town_greyhold", "pike_militia", 10)["gold"]), full)
	wren.skills["quartermaster"] = 3
	assert_eq(int(session.recruit_price("town_greyhold", "pike_militia", 10)["gold"]), int(round(full * 0.85)))
	var gold_before: int = session.current_player()["resources"].get_amount("gold")
	var r := session.recruit("town_greyhold", "pike_militia", 10)
	assert_true(r["ok"], r.get("reason", ""))
	assert_eq(session.current_player()["resources"].get_amount("gold"), gold_before - int(round(full * 0.85)))
	# Hero income arrives at the start of the next day.
	var g: int = session.current_player()["resources"].get_amount("gold")
	session.end_turn()
	assert_eq(session.current_player()["resources"].get_amount("gold"), g + int(session.daily_income(0)["gold"]))


func test_reaver_spoils() -> void:
	var army := [["pike_militia", 80], ["longbowman", 40], ["shieldwarden", 10]]
	_add_hero("h_reaver", "reaver", Vector2i(11, 8), army)
	var r := session.attack("h_reaver", "neutral_wolves")
	assert_eq(r["winner"], 0)
	assert_eq(r["gold_gained"], int(round(r["xp_gained"] * 0.2)))
	assert_gt(r["gold_gained"], 0)


func test_necromancer_raises_the_fallen() -> void:
	var army := [["pike_militia", 70], ["longbowman", 20]]
	var h := _add_hero("h_necro", "necromancer", Vector2i(11, 8), army)
	var pct := HeroModifiers.num(h.modifiers(data), "recover_pct")
	assert_between(pct, 0.149, 0.151, "Ossuary Bond 5% + Gravecalling 10%")
	var r := session.attack("h_necro", "neutral_wolves")
	assert_eq(r["winner"], 0)
	var expected := 0
	var lost := 0
	for st in r["sides"][0]["stacks"]:
		expected += int(floor(int(st["lost"]) * pct))
		lost += int(st["lost"])
	assert_gt(lost, 0, "the wolves bite")
	assert_eq(r["recovered"], expected)
	# The Hollow's Grave Harvest also raises Shamblers from the slain wolves.
	var raised := FactionMechanics.harvest_count(r["sides"][1]["stacks"], h.faction, data)
	assert_eq(h.army.total_creatures(), 90 - lost + expected + raised)


func test_xp_curve_paces_one_to_three_levels_per_map() -> void:
	# Clearing every guard on the slice map is worth roughly 1600 XP.
	var hp := 0
	for id in session.state.map.objects:
		var o: Dictionary = session.state.map.objects[id]
		for key in ["stacks", "guard", "garrison"]:
			var stacks: Variant = o.get(key, [])
			if typeof(stacks) != TYPE_ARRAY:
				continue   # town garrisons are stored as an army record
			for pair: Variant in stacks:
				if typeof(pair) == TYPE_ARRAY:
					hp += int(data.creature(pair[0])["hp"]) * int(pair[1])
				elif typeof(pair) == TYPE_DICTIONARY and not pair.is_empty():   # army slot; empty slots are {}
					hp += int(data.creature(pair["creature"])["hp"]) * int(pair["count"])
	var xp := int(hp * float(data.combat["xp_per_enemy_hp_killed"]))
	var h := Hero.create({"id": "x", "name": "x", "class": "knight", "pos": [0, 0], "army": []}, data)
	var levels := h.add_xp(xp, data)
	assert_between(levels, 1, 3, "levels from one full map: %d (xp %d)" % [levels, xp])
	# A veteran at level 6 gains at most one level from the same map.
	var vet := Hero.create({"id": "v", "name": "v", "class": "knight", "pos": [0, 0], "army": []}, data)
	vet.add_xp(11500, data)
	assert_eq(vet.level, 6)
	assert_true(vet.add_xp(xp, data) <= 1)


# --------------------------------------------------------------- campaign --

func test_campaign_carries_veterans_between_chapters() -> void:
	var c := Campaign.start(data, "last_light", 9)
	var s := c.begin_chapter(data)
	var wren := s.hero("hero_wren")
	assert_eq(wren.level_cap, 3)
	wren.add_xp(9000, data)
	assert_eq(wren.level, 3, "chapter cap")
	wren.learn_skill("tactics", data)
	wren.give_artifact("tattered_pennant", data)
	wren.add_mark("pit_champion")
	var res := c.complete_chapter(data, s, true)
	assert_true(res["ok"] and res["won"])
	assert_false(res["finished"])
	assert_eq(c.chapter, 1)
	assert_eq(c.completed, ["ll_harvest"] as Array[String])
	assert_eq(int(c.roster["hero_wren"]["xp"]), 9300, "XP reward banked")
	var s2 := c.begin_chapter(data)
	var w2 := s2.hero("hero_wren")
	assert_eq(w2.level, 4, "the higher cap pays out banked XP (9300 XP) up to the new cap")
	assert_eq(w2.skill_points, 2, "one point spent on tactics, one more from level 4")
	assert_eq(w2.skill_level("tactics"), 1)
	assert_eq(w2.equipment.get("banner", ""), "tattered_pennant")
	assert_true(w2.has_mark("pit_champion"))
	assert_eq(w2.army.total_creatures(), 40, "armies come from the chapter, not the last one")
	assert_eq(w2.movement_left, w2.max_movement(data))
	# Chapter 2 starts with bonus gold.
	assert_eq(s2.current_player()["resources"].get_amount("gold"), int(data.starting_resources["gold"]) + 1000)


func test_lost_chapter_changes_nothing() -> void:
	var c := Campaign.start(data, "last_light", 9)
	var s := c.begin_chapter(data)
	s.hero("hero_wren").add_xp(3000, data)
	var res := c.complete_chapter(data, s, false)
	assert_false(res["won"])
	assert_eq(c.chapter, 0)
	assert_true(c.roster.is_empty())


## Without carry.keep_worn the limit counts every artifact (The Last Light
## keeps everything worn; see test_armor.gd).
func test_artifacts_trimmed_to_carry_limit() -> void:
	var carry: Dictionary = data.campaigns["last_light"]["carry"]
	carry["keep_worn"] = false
	var c := Campaign.start(data, "last_light", 9)
	var s := c.begin_chapter(data)
	var wren := s.hero("hero_wren")
	for a in ["notched_falchion", "riveted_hauberk", "bone_dice", "tattered_pennant", "wardstone_mail", "headsmans_maul"]:
		assert_true(wren.give_artifact(a, data))
	var res := c.complete_chapter(data, s, true, {"hero_wren": ["bone_dice"]})
	carry["keep_worn"] = true
	var kept: Array = res["kept"]["hero_wren"]
	assert_eq(kept.size(), 4)
	assert_true(kept.has("bone_dice"), "preferred")
	assert_true(kept.has("wardstone_mail") and kept.has("headsmans_maul"), "most valuable")
	assert_eq(res["dropped"]["hero_wren"].size(), 2)
	assert_eq(c.roster["hero_wren"]["equipment"]["armor"], "wardstone_mail", "kept pack items fill freed slots")


func test_reward_artifact_goes_to_lead_hero() -> void:
	var c := Campaign.start(data, "last_light", 9)
	for _i in 4:   # chapter 4 rewards the standard
		c.complete_chapter(data, c.begin_chapter(data), true)
	var rec: Dictionary = c.roster["hero_wren"]
	assert_true(rec["equipment"].values().has("standard_of_the_hold") or rec["pack"].has("standard_of_the_hold"))
	var last := {}
	while not c.is_finished(data):
		last = c.complete_chapter(data, c.begin_chapter(data), true)
	assert_true(last["finished"])
	assert_true(c.is_finished(data))
	assert_eq(c.begin_chapter(data), null)


func test_campaign_save_round_trip_with_game_in_progress() -> void:
	var c := Campaign.start(data, "last_light", 4)
	c.complete_chapter(data, c.begin_chapter(data), true)
	var s := c.begin_chapter(data)
	s.hero("hero_maelis").add_xp(700, data)
	var path := "user://test_campaign.json"
	assert_eq(c.save_to_file(path, s), OK)
	var loaded := Campaign.load_from_file(data, path)
	assert_true(loaded != null)
	assert_eq(loaded.chapter, 1)
	assert_eq(str(loaded.roster), str(JSON.parse_string(JSON.stringify(c.roster))))
	var resumed := loaded.resume(data)
	assert_eq(resumed.hero("hero_maelis").xp, s.hero("hero_maelis").xp)
	assert_eq(resumed.hero("hero_maelis").level_cap, 4)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(Campaign.validate_save({"campaign_version": 99, "campaign": "last_light", "chapter": 0, "seed": 1, "roster": {}}, data).size() > 0)


func test_campaign_validation_catches_bad_level_caps() -> void:
	var original: Dictionary = data.campaigns["last_light"].duplicate(true)
	data.campaigns["last_light"]["chapters"][1]["level_cap"] = 2
	var errors := Campaign.validate(data)
	data.campaigns["last_light"] = original
	assert_eq(errors.size(), 1, "\n".join(errors))
	assert_eq(Campaign.validate(data).size(), 0)


func test_campaign_progress_file_and_chapter_list() -> void:
	var dir := "user://test_campaign_progress"
	assert_eq(Campaign.load_progress(data, "last_light", dir), null, "no progress yet")
	var c := Campaign.start(data, "last_light", 3)
	var chapters := c.chapter_list(data)
	assert_eq(chapters.size(), 10)
	assert_eq(chapters[0]["state"], "current")
	assert_eq(chapters[1]["state"], "locked")
	var s := c.begin_chapter(data)
	s.hero("hero_wren").add_xp(2500, data)
	c.complete_chapter(data, s, true)
	var s2 := c.begin_chapter(data)
	assert_eq(c.save_progress(s2, dir), OK)
	var back := Campaign.load_progress(data, "last_light", dir)
	assert_true(back != null)
	assert_eq(back.chapter, 1)
	assert_false(back.active_game.is_empty(), "the chapter in progress is kept for Continue")
	assert_eq(back.chapter_list(data)[0]["state"], "done")
	assert_eq(back.chapter_list(data)[1]["state"], "current")
	var lines := back.roster_lines(data)
	assert_eq(lines.size(), 1, "only Aldous Wren marched in chapter 1")
	assert_true(lines[0].begins_with("Aldous Wren, level "), lines[0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Campaign.progress_path("last_light", dir)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_chapter_saved_to_any_slot_still_advances_the_campaign() -> void:
	var dir := "user://test_campaign_slots"
	var c := Campaign.start(data, "last_light", 5)
	var s := c.begin_chapter(data)
	assert_eq(s.state.campaign["campaign"], "last_light")
	assert_true(s.state.campaign["active_game"].is_empty(), "the record does not nest the game")
	s.hero("hero_wren").add_xp(2000, data)
	assert_eq(SaveSlots.save(s, "3", dir), OK)
	var row: Dictionary = SaveSlots.list(data, dir)[3]
	assert_true(SaveSlots.summary(row).begins_with("Greyhold Harvest (campaign)"), SaveSlots.summary(row))
	var loaded := SaveSlots.load_slot(data, "3", dir)
	var back := Campaign.of_session(data, loaded)
	assert_true(back != null, "the chapter remembers its campaign")
	assert_eq(back.chapter, 0)
	var res := back.complete_chapter(data, loaded, true)
	assert_true(res["won"])
	assert_eq(back.chapter, 1, "winning the loaded chapter moves the campaign on")
	assert_eq(int(back.roster["hero_wren"]["xp"]), loaded.hero("hero_wren").xp + 300)
	SaveSlots.delete("3", dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_v6_save_migrates_to_no_campaign() -> void:
	var s := GameSession.new_game(data, "ember_ford", 2)
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	d["version"] = 6
	d.erase("campaign")
	var st := GameState.from_dict(d, data)
	assert_true(st.campaign.is_empty())
	assert_eq(Campaign.of_session(data, GameSession.from_state(data, st)), null, "a skirmish")
	assert_eq(int(st.to_dict()["version"]), GameState.SAVE_VERSION)


func test_chapter_resumed_from_v6_progress_keeps_its_campaign() -> void:
	var c := Campaign.start(data, "last_light", 6)
	var s := c.begin_chapter(data)
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict(s)))
	d["active_game"]["version"] = 6
	d["active_game"].erase("campaign")
	var old := Campaign.from_dict(d)
	var resumed := old.resume(data)
	assert_eq(String(resumed.state.campaign.get("campaign", "")), "last_light", "the record is attached on resume")
	assert_true(Campaign.of_session(data, resumed) != null, "a slot save of it still belongs to the campaign")
