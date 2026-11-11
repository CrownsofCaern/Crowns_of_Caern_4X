extends "res://tests/test_case.gd"
## Armor progression: the helm/armor/shield/boots slots, armor sets, armor
## drops on generated and hand-made maps, the AI picking up and wearing
## gear, and campaign veterans keeping what they wear.

const SEEDS := [1, 2, 3, 17, 404]


func _hero(cls: String = "knight") -> Hero:
	return Hero.create({"id": "h", "name": "h", "class": cls, "pos": [0, 0], "army": [["pike_militia", 10]]}, data)


func _drop_pool() -> Array:
	var slots: Array = data.artifact_rules["drop_slots"]
	var out := []
	for aid in data.artifacts:
		if slots.has(data.artifacts[aid]["slot"]):
			out.append(aid)
	return out


# ------------------------------------------------------------------ data --

func test_armor_slots_have_pieces_of_every_rarity() -> void:
	var slots: Array = data.artifact_rules["drop_slots"]
	assert_eq(slots, ["helm", "armor", "shield", "boots"])
	assert_true(_drop_pool().size() >= 20, "about twenty armor pieces: %d" % _drop_pool().size())
	for slot in slots:
		var rar := {}
		for aid in _drop_pool():
			if data.artifacts[aid]["slot"] == slot:
				rar[data.artifacts[aid]["rarity"]] = true
		assert_true(rar.has("minor") and (rar.has("major") or rar.has("relic")), "%s pieces span rarities: %s" % [slot, rar.keys()])


func test_each_slot_is_worn_separately() -> void:
	var h := _hero()
	var base := h.total_attr("defense", data)
	for a in ["dented_sallet", "riveted_hauberk", "splintered_buckler", "outriders_greaves"]:
		assert_true(h.give_artifact(a, data))
	assert_true(h.pack.is_empty(), "every piece found a free slot")
	assert_eq(h.equipment["helm"], "dented_sallet")
	assert_eq(h.equipment["shield"], "splintered_buckler")
	assert_eq(h.equipment["boots"], "outriders_greaves")
	assert_eq(h.total_attr("defense", data), base + 4)
	assert_eq(h.max_movement(data), int(round(int(data.progression["base_movement"]) * 1.1)))


func test_set_bonus_grows_with_pieces_worn() -> void:
	var h := _hero()
	h.give_artifact("gravewatch_visor", data)
	assert_eq(h.active_set_bonuses(data).size(), 0, "one piece earns nothing")
	assert_eq(int(h.modifiers(data).get("morale_floor", 0)), 0)
	h.give_artifact("hobnailed_boots", data)
	assert_eq(h.worn_set_pieces("gravewatch", data), 2)
	assert_eq(h.active_set_bonuses(data).size(), 1)
	assert_eq(int(h.modifiers(data).get("morale_floor", 0)), 1, "two pieces: morale floor")
	var def_two := h.total_attr("defense", data)
	h.give_artifact("ossuary_brigandine", data)
	assert_eq(h.active_set_bonuses(data).size(), 2)
	assert_eq(h.total_attr("defense", data), def_two + 2 + 1, "brigandine +2 and the full-set +1")
	assert_between(float(h.modifiers(data)["recover_pct"]), 0.089, 0.091, "4% brigandine + 5% set")
	# A set piece in the pack does not count.
	assert_true(h.unequip("helm", data))
	assert_eq(h.worn_set_pieces("gravewatch", data), 2)
	assert_eq(h.active_set_bonuses(data).size(), 1)


func test_set_bonus_reaches_combat() -> void:
	var h := _hero()
	for a in ["greathelm_of_dread", "emberforged_cuirass", "aegis_of_cinders"]:
		h.give_artifact(a, data)
	var mods: Dictionary = h.combat_profile(data)["mods"]
	assert_eq(int(mods.get("enemy_morale", 0)), 2, "greathelm +1, full Ashwall +1")
	assert_eq(int(mods.get("morale", 0)), 1 + 1, "Knight's starting Leadership +1, full Ashwall +1")


func test_set_validation() -> void:
	assert_eq(data._validate_artifact_sets().size(), 0)
	var original: Dictionary = data.artifact_sets.duplicate(true)
	data.artifact_sets["broken"] = {"name": "Broken", "pieces": ["dented_sallet", "gravewatch_visor", "nope"],
		"bonuses": [{"pieces": 4, "mods": {"defense": 1}, "text": "x"}, {"pieces": 2, "mods": {"bogus": 1}, "text": "y"}]}
	var errors := data._validate_artifact_sets()
	data.artifact_sets = original
	var text := "\n".join(errors)
	assert_true(text.contains("unknown piece nope"), text)
	assert_true(text.contains("two helm pieces"), text)
	assert_true(text.contains("piece count"), text)
	assert_true(text.contains("unknown modifier bogus"), text)
	assert_true(text.contains("already belongs"), "gravewatch_visor is in two sets: " + text)


func test_armor_drop_config_validates() -> void:
	assert_eq(MapGenerator.validate_templates(data).size(), 0)
	var cfg: Dictionary = data.map_templates["armor_drops"]
	var original := cfg.duplicate(true)
	cfg["per_player"]["rarity"] = "mythic"
	cfg["extras"]["max"] = 0
	cfg["extras"]["guards"].erase("relic")
	var errors := MapGenerator.validate_templates(data)
	data.map_templates["armor_drops"] = original
	assert_eq(errors.size(), 3, "\n".join(errors))


# ---------------------------------------------------------------- drops --

func test_generated_maps_drop_one_piece_per_player_and_extras() -> void:
	var cfg: Dictionary = data.map_templates["armor_drops"]
	var pool := _drop_pool()
	var extra_counts := {}
	for tpl in ["twin_marches", "crossing"]:
		for s in SEEDS:
			var def := MapGenerator.generate(data, tpl, s)
			assert_false(def.is_empty(), "%s %d generated" % [tpl, s])
			var starts := {}
			for z in def["generator"]["zones"]:
				if z.has("player"):
					starts[String(z["id"])] = true
			var by_zone := {}
			var extras := []
			var guards := {}
			for o in def["objects"]:
				if o["type"] == "neutral_army" and o.has("guards"):
					guards[String(o["guards"])] = o
			for o in def["objects"]:
				if o["type"] != "artifact" or o.get("hoard", false):
					continue   # hoards (density fill) are covered by test_mapgen
				assert_true(pool.has(o["artifact"]), "%s is an armor piece" % o["artifact"])
				assert_true(guards.has(String(o["id"])) and o.has("guarded_by"), "%s %d: %s is guarded" % [tpl, s, o["id"]])
				if starts.has(String(o["zone"])):
					by_zone[String(o["zone"])] = String(o["artifact"])
				else:
					extras.append(String(o["artifact"]))
			assert_eq(by_zone.size(), starts.size(), "%s %d: a piece in every start zone" % [tpl, s])
			var ids := {}
			for z in by_zone:
				ids[by_zone[z]] = true
			assert_eq(ids.size(), 1, "every player finds the same piece")
			for a in by_zone.values():
				assert_eq(data.artifacts[a]["rarity"], cfg["per_player"]["rarity"])
			assert_between(extras.size(), int(cfg["extras"]["min"]), int(cfg["extras"]["max"]), "%s %d extras" % [tpl, s])
			var seen := {}
			for a in extras:
				assert_false(seen.has(a) or ids.has(a), "%s %d: %s appears once" % [tpl, s, a])
				seen[a] = true
			extra_counts[extras.size()] = true
	assert_true(extra_counts.size() >= 2, "the number of extras varies: %s" % [extra_counts.keys()])


func test_armor_drops_are_deterministic() -> void:
	var a := MapGenerator.generate(data, "twin_marches", 31)
	var b := MapGenerator.generate(data, "twin_marches", 31)
	assert_eq(JSON.stringify(a["objects"]), JSON.stringify(b["objects"]))


func test_hand_made_maps_drop_armor() -> void:
	var pool := _drop_pool()
	for map_id in ["twin_marches", "mournfield", "burning_ford", "ashes_return", "into_the_embers"]:
		var def := data.load_map(map_id)
		var n := 0
		for o in def["objects"]:
			if o["type"] == "artifact" and pool.has(o["artifact"]):
				n += 1
		assert_true(n >= (def["players"] as Array).size() + 1, "%s holds %d armor pieces" % [map_id, n])
		var errors := MapValidator.validate(def, data)
		assert_eq(errors.size(), 0, "%s: %s" % [map_id, ", ".join(errors)])


func test_campaign_can_complete_the_long_road_harness() -> void:
	var found := {}
	for map_id in ["burning_ford", "ashes_return", "into_the_embers"]:
		for o in data.load_map(map_id)["objects"]:
			if o["type"] == "artifact":
				found[String(o["artifact"])] = true
	for piece in data.artifact_sets["long_road"]["pieces"]:
		assert_true(found.has(piece), "%s lies somewhere in the Ember Chronicle" % piece)


# ------------------------------------------------------------------- AI --

func test_ai_values_armor_it_can_use() -> void:
	var s := GameSession.new_game(data, "twin_marches", 5)
	var ai := StrategicAI.new(s, 1)
	var h := _hero()
	assert_gt(ai.artifact_value(h, "dented_sallet"), 1000.0, "empty slot: worth the piece")
	h.give_artifact("crowcrest_helm", data)
	assert_between(ai.artifact_value(h, "dented_sallet"), 1.0, 500.0, "a weaker helm is only spare")
	assert_gt(ai.artifact_value(h, "greathelm_of_dread"), 5000.0, "an upgrade is worth the difference")
	for i in int(data.artifact_rules["pack_size"]):
		h.give_artifact("dented_sallet", data)
	assert_eq(ai.artifact_value(h, "greathelm_of_dread"), 0.0, "nowhere to put it")


func test_ai_wears_its_best_gear() -> void:
	var s := GameSession.new_game(data, "twin_marches", 5)
	s.end_turn()   # player 1 (the computer) is now current
	var h: Hero = s.state.heroes_of(1)[0]
	h.give_artifact("dented_sallet", data)
	h.pack.append("greathelm_of_dread")
	h.pack.append("marsh_waders")
	var ai := StrategicAI.new(s, 1)
	assert_eq(ai.equip_best(h), 2)
	assert_eq(h.equipment["helm"], "greathelm_of_dread")
	assert_eq(h.equipment["boots"], "marsh_waders")
	assert_eq(h.pack, ["dented_sallet"] as Array[String])


func test_ai_picks_up_nearby_armor() -> void:
	var s := GameSession.new_game(data, "twin_marches", 5)
	s.end_turn()
	var h: Hero = s.state.heroes_of(1)[0]
	var o: Dictionary = s.state.map.objects["art_sallet_e"]
	h.pos = Vector2i(int(o["pos"][0]) + 1, int(o["pos"][1]))
	s.state.player(1)["fog"].reveal(h.pos, 4)
	var ai := StrategicAI.new(s, 1)
	var field := AiDistanceField.build(s.state.map, h.pos, {})
	var cands: Array = ai.candidate_targets(h, field).filter(func(c): return c["id"] == "art_sallet_e")
	assert_eq(cands.size(), 1, "the piece is a target")
	ai.play_turn()
	assert_false(s.state.map.objects.has("art_sallet_e"), "picked up")
	var owned := []
	for hh in s.state.heroes_of(1):
		owned.append_array((hh as Hero).all_artifacts(data))
	assert_true(owned.has("dented_sallet"))


# ------------------------------------------------------------- campaign --

func test_campaign_veterans_keep_everything_they_wear() -> void:
	var c := Campaign.start(data, "last_light", 9)
	var s := c.begin_chapter(data)
	var wren := s.hero("hero_wren")
	var worn := ["notched_falchion", "dented_sallet", "riveted_hauberk", "splintered_buckler", "hobnailed_boots", "bone_dice", "tattered_pennant"]
	for a in worn:
		assert_true(wren.give_artifact(a, data))
	for a in ["wardstone_mail", "headsmans_maul", "vigil_pavise", "gravewatch_visor", "marsh_waders", "flayed_banner"]:
		assert_true(wren.give_artifact(a, data))
	var res := c.complete_chapter(data, s, true, {"hero_wren": ["marsh_waders"]})
	var kept: Array = res["kept"]["hero_wren"]
	var max_pack := int(data.campaigns["last_light"]["carry"]["max_artifacts"])
	assert_eq(kept.size(), worn.size() + max_pack)
	for a in worn:
		assert_true(kept.has(a), "%s was worn and carries over" % a)
	assert_true(kept.has("marsh_waders"), "preferred pack piece")
	assert_true(kept.has("wardstone_mail") and kept.has("headsmans_maul"), "most valuable pack pieces")
	assert_eq(res["dropped"]["hero_wren"].size(), 6 - max_pack)
	var s2 := c.begin_chapter(data)
	var w2 := s2.hero("hero_wren")
	for slot in ["helm", "armor", "shield", "boots"]:
		assert_eq(String(w2.equipment.get(slot, "")), String(wren.equipment[slot]), "%s still worn in chapter 2" % slot)
