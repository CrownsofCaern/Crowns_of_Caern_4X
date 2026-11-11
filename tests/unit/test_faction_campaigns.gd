extends "res://tests/test_case.gd"
## The five faction campaigns after The Last Light (which has its own tests):
## each has ten chapters on the shared tier schedule, the story's enemies in
## every chapter, its veterans where the story puts them, and a finale against
## several enemies at once.

## Long-running tests (whole AI games, balance sweeps, many generated maps):
## they run only with ./run_tests.sh --slow.
const SLOW := ["test_multi_enemy_finales_play_out_turns"]

const TIERS := [2, 3, 3, 4, 5, 5, 6, 7, 8, 8]
## id -> faction, the hand-made maps, the enemy factions per chapter, and for
## each veteran the chapters (0-based) it is on the map. Optional: "allies"
## (chapter -> factions of the computer players that start allied with the
## player: 2v2 and betrayal chapters), "townless" (chapters that start without
## a town) and "invaders" (chapter -> enemy slots that only send waves and
## hold no town).
const CAMPAIGNS := {
	"pale_inheritance": {
		"faction": "hollow",
		"maps": ["warm_earth", "twice_dead", "pale_crown", "ph_barrow_lords", "ph_living_shore", "ph_rot", "ph_lantern_siege",
			"ph_deep_barrows", "ph_hungry_fire", "ph_leviathan"],
		"enemies": [["hollow"], ["hollow"], ["concord", "concord"], ["thornwood"], ["concord"], ["concord"], ["ashen"], ["ashen", "ashen"], ["ashen"], ["ashen", "ashen"]],
		"allies": {2: ["hollow"], 5: ["concord"]},
		"townless": [3],
		"invaders": {7: [2]},
		"veterans": {"hero_ysmay": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_orrin": [0, 1, 2, 3, 5, 6, 7, 8, 9], "hero_corvin": [2, 3, 4, 5, 6, 7, 8, 9]},
	},
	"unsealing": {
		"faction": "ashen",
		"maps": ["pit_below", "breaking_the_lockstone", "red_sky_throne"],
		"enemies": [["ashen"], ["ashen"], ["forge"], ["hollow", "hollow"], ["concord"], ["thornwood"], ["concord"], ["frostmarch"], ["concord"], ["concord", "thornwood", "forge"]],
		"allies": {3: ["ashen"], 7: ["ashen"]},
		"townless": [5],
		"veterans": {"hero_skarn": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_ithra": [1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_morvath": [4, 5, 6, 7, 8, 9]},
	},
	"briar_oath": {
		"faction": "thornwood",
		"maps": ["axe_line", "roots_remember", "briar_seal"],
		"enemies": [["concord"], ["concord"], ["concord"], ["frostmarch", "frostmarch"], ["hollow"], ["ashen"], ["ashen", "ashen"], ["ashen"], ["ashen"], ["ashen", "ashen"]],
		"allies": {6: ["frostmarch"], 8: ["thornwood"]},
		"townless": [4],
		"invaders": {3: [2]},
		"veterans": {"hero_cerrid": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_neve": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_brakka": [4, 5, 6, 7, 8, 9]},
	},
	"shuttered_halls": {
		"faction": "forge",
		"maps": ["deep_shift", "fallen_hold", "second_lockstone", "fg_bones", "fg_debtors", "fg_iron_bread", "fg_heat", "fg_wardens_keep", "fg_ore_ember", "fg_engine"],
		"enemies": [["hollow"], ["hollow"], ["concord"], ["frostmarch"], ["ashen", "ashen"], ["ashen"], ["ashen"], ["ashen"], ["ashen", "ashen"], ["ashen", "hollow"]],
		"allies": {3: ["frostmarch"], 8: ["concord"]},
		"townless": [6],
		"invaders": {4: [2]},
		"veterans": {"hero_gunnra": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_dask": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_tobbin": [5, 6, 7, 8, 9]},
	},
	"ashwinter": {
		"faction": "frostmarch",
		"maps": ["sun_goes_out", "granary_of_highmere", "bring_the_winter", "fm_one_hall", "fm_south", "fm_iron_pass", "fm_deer", "fm_cold_bones", "fm_source", "fm_wyrm"],
		"enemies": [["frostmarch"], ["frostmarch"], ["concord"], ["forge"], ["concord"], ["thornwood", "thornwood"], ["hollow"], ["ashen"], ["ashen"], ["ashen", "ashen"]],
		"allies": {2: ["frostmarch"], 5: ["hollow"]},
		"townless": [7],
		"veterans": {"hero_ulvra": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_bjarr": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_iska": [2, 3, 4, 5, 6, 7, 8, 9]},
	},
}


func _chapters(cid: String) -> Array:
	return data.campaigns[cid]["chapters"]


func test_ten_chapters_with_the_tier_schedule() -> void:
	for cid in CAMPAIGNS:
		assert_true(data.campaigns.has(cid), "%s exists" % cid)
		assert_eq(String(data.campaigns[cid]["faction"]), CAMPAIGNS[cid]["faction"])
		assert_eq(_chapters(cid).size(), 10, "%s has ten chapters" % cid)
		var tiers := []
		for ch in _chapters(cid):
			tiers.append(int(ch.get("max_tier", 0)))
			assert_false(String(ch.get("intro", "")).is_empty(), "%s has a story intro" % ch["id"])
			assert_false(String(ch.get("outro", "")).is_empty(), "%s has a story outro" % ch["id"])
		assert_eq(tiers, TIERS, "%s: tier 8 only on the last two maps, tier 7 one map earlier and so on" % cid)


func test_hand_made_maps_validate() -> void:
	for cid in CAMPAIGNS:
		for mid in CAMPAIGNS[cid]["maps"]:
			var def := data.load_map(mid)
			assert_false(def.is_empty(), "%s loads" % mid)
			assert_eq(MapValidator.validate(def, data), [] as Array[String], "%s validates" % mid)


func test_every_chapter_begins_against_its_story_enemies() -> void:
	for cid in CAMPAIGNS:
		var spec: Dictionary = CAMPAIGNS[cid]
		var c := Campaign.start(data, cid, 4)
		for i in _chapters(cid).size():
			c.chapter = i
			var s := c.begin_chapter(data)
			var chid: String = _chapters(cid)[i]["id"]
			assert_true(s != null, "%s starts" % chid)
			var enemies: Array = spec["enemies"][i]
			var allies: Array = spec.get("allies", {}).get(i, [])
			var invaders: Array = spec.get("invaders", {}).get(i, [])
			assert_eq(s.state.players.size(), 1 + enemies.size() + allies.size(), "%s player count" % chid)
			assert_eq(s.state.player(0)["faction"], spec["faction"])
			assert_true(bool(s.state.player(0)["is_human"]))
			if (spec.get("townless", []) as Array).has(i):
				assert_eq(s.towns_of(0).size(), 0, "%s the player starts without a town" % chid)
			else:
				assert_gt(float(s.towns_of(0).size()), 0.0, "%s the player holds a town" % chid)
			var enemy_factions := []
			var ally_factions := []
			for p in range(1, s.state.players.size()):
				assert_false(bool(s.state.player(p)["is_human"]))
				if s.state.allied(0, p):
					ally_factions.append(s.state.player(p)["faction"])
					assert_gt(float(s.towns_of(p).size()), 0.0, "%s ally %d holds a town" % [chid, p])
				else:
					enemy_factions.append(s.state.player(p)["faction"])
					if not invaders.has(p):
						assert_gt(float(s.towns_of(p).size()), 0.0, "%s enemy %d holds a town" % [chid, p])
			assert_eq(enemy_factions, enemies, "%s enemies" % chid)
			assert_eq(ally_factions, allies, "%s allies" % chid)
			assert_eq(s.tier_cap(), TIERS[i])
			for hid in spec["veterans"]:
				var h := s.hero(hid)
				var present: bool = (spec["veterans"][hid] as Array).has(i)
				assert_eq(h != null, present, "%s: %s on the map" % [chid, hid])
				if h != null:
					assert_eq(h.owner, 0, "%s %s is the player's" % [chid, hid])
					assert_true(s.state.map.is_passable(h.pos), "%s %s stands on open ground" % [chid, hid])
			for id in s.state.heroes:
				var h: Hero = s.state.heroes[id]
				if h.owner != 0:
					continue
				assert_true((spec["veterans"] as Dictionary).has(id), "%s: %s is a veteran, not a leftover generated hero" % [chid, id])
				for st in h.army.slots:
					if not st.is_empty():
						assert_true(int(data.creature(st["creature"])["tier"]) <= TIERS[i], "%s %s starts within the cap" % [chid, id])


func test_a_veteran_keeps_his_record_through_a_chapter_he_misses() -> void:
	var c := Campaign.start(data, "pale_inheritance", 9)
	c.chapter = 3
	var s := c.begin_chapter(data)
	s.hero("hero_orrin").add_xp(5000, data)
	c.complete_chapter(data, s, true)
	var level := int(c.roster["hero_orrin"]["level"])
	assert_gt(float(level), 1.0)
	s = c.begin_chapter(data)
	assert_true(s.hero("hero_orrin") == null, "Orrin's body lies in Greyhold in chapter 5")
	c.complete_chapter(data, s, true)
	assert_true(c.roster.has("hero_orrin") and int(c.roster["hero_orrin"]["level"]) >= level, "his record waits while he is absent")
	s = c.begin_chapter(data)
	assert_true(s.hero("hero_orrin") != null and s.hero("hero_orrin").level >= level, "and he comes back at his level")


func test_multi_enemy_finales_play_out_turns() -> void:
	for cid in CAMPAIGNS:
		var c := Campaign.start(data, cid, 3)
		c.chapter = 9
		var s := c.begin_chapter(data)
		for _day in 6:
			if s.state.game_over:
				break
			s.end_turn()
			StrategicAI.play_ai_turns(s, 8)
		assert_gt(float(s.state.day), 5.0, "%s: the finale runs day after day" % cid)
		assert_false(s.state.game_over and s.state.winner != 0, "%s: the enemies do not overrun the player in the first days" % cid)


func test_several_enemies_play_at_the_easy_difficulty() -> void:
	for cid in CAMPAIGNS:
		var c := Campaign.start(data, cid, 5)
		c.chapter = 9
		var s := c.begin_chapter(data)
		assert_gt(float(s.state.players.size()), 2.0, "%s finale has several enemies" % cid)
		for p in range(1, s.state.players.size()):
			assert_eq(s.difficulty_of(p), "easy", "%s enemy %d is gentler, one against several" % [cid, p])
		assert_eq(s.difficulty_of(0), data.default_difficulty())


func test_finale_enemies_are_allied_against_the_player() -> void:
	for cid in CAMPAIGNS:
		var c := Campaign.start(data, cid, 5)
		c.chapter = 9
		var s := c.begin_chapter(data)
		var n := s.state.players.size()
		for a in range(1, n):
			assert_false(s.state.allied(0, a), "%s: enemy %d is no ally of the player" % [cid, a])
			for b in range(a + 1, n):
				assert_true(s.state.allied(a, b), "%s: enemies %d and %d fight together" % [cid, a, b])


func test_map_validator_rejects_an_invalid_team() -> void:
	var def := data.load_map("pale_crown")
	def["players"][1]["team"] = GameSetup.MAX_TEAMS + 1
	var errors := MapValidator.validate(def, data)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("team"))


func test_map_validator_rejects_an_unknown_difficulty() -> void:
	var def := data.load_map("pale_crown")
	def["players"][1]["difficulty"] = "nightmare"
	var errors := MapValidator.validate(def, data)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("nightmare"))


func test_cast_replaces_a_generated_hero_whose_slot_changed_faction() -> void:
	var ch: Dictionary = _chapters("pale_inheritance")[1]
	var plain := GameSession.new_game(data, ch["map"], 11)
	var start: Vector2i = plain.hero("hero_p0").pos
	var s := GameSession.new_game(data, ch["map"], 11, Campaign.chapter_setup(ch), Campaign.chapter_rules(ch))
	var ysmay := s.hero("hero_ysmay")
	assert_true(ysmay != null and ysmay.pos == start, "Ysmay takes the generated hero's tile")
	assert_eq(s.state.heroes_of(0).size(), 2, "the generated hero leaves, whatever faction the setup gave its slot: only Ysmay and Orrin")
