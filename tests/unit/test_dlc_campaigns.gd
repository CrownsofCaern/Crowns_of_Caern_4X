extends "res://tests/test_case.gd"
## The two expansion campaigns: The Six Eyes (Umbral Court) and The Drowned Oath
## (Abyssal Shoal). Ten chapters each on the shared tier schedule, the story's
## enemies and allies in every chapter, the Eyes collected and then taken at the
## hero-only finale, and the ancient dragon standing in the Nightgate.

const TIERS := [2, 3, 3, 4, 5, 5, 6, 7, 8, 8]
const EYES := ["eye_of_the_anvil", "eye_of_the_saint", "eye_of_the_root", "eye_of_the_regent", "eye_of_embers", "eye_of_winter"]
## id -> faction, hand-made maps, per chapter the other players as [faction, allied with the player],
## and for each veteran the chapters (0-based) it is on the map on the player's side. A survival
## chapter's invasion player (the waves) is listed too; it holds no town.
const CAMPAIGNS := {
	"six_eyes": {
		"faction": "darkelf",
		"maps": ["below_the_sky", "the_nightgate"],
		"others": [
			[["darkelf", false]], [["forge", false]], [["forge", false]], [["concord", false]],
			[["thornwood", false], ["concord", true]], [["ashen", false], ["hollow", true], ["ashen", false]],
			[["ashen", false]], [["frostmarch", false]],
			[["concord", false], ["forge", false], ["frostmarch", false]], [["darkelf", false]],
		],
		"veterans": {"hero_serane": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_rhuvel": [1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_ulmarra": [0]},
	},
	"drowned_oath": {
		"faction": "fishmen",
		"maps": ["tablets_of_sarranth", "who_was_cold_first"],
		"others": [
			[["fishmen", false]], [["fishmen", false]], [["ashen", false]],
			[["ashen", false], ["concord", true], ["ashen", false]], [["forge", false]], [["forge", false], ["forge", false]],
			[["frostmarch", false]], [["frostmarch", false], ["concord", true]], [["frostmarch", false]],
			[["frostmarch", false], ["concord", false]],
		],
		"veterans": {"hero_ilo": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_thunn": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "hero_sael": [1, 2, 3, 4, 5, 6, 7, 8, 9]},
	},
}


func _chapters(cid: String) -> Array:
	return data.campaigns[cid]["chapters"]


func test_ten_chapters_with_the_tier_schedule_and_story_text() -> void:
	for cid in CAMPAIGNS:
		assert_true(data.campaigns.has(cid), "%s exists" % cid)
		assert_eq(String(data.campaigns[cid]["faction"]), CAMPAIGNS[cid]["faction"])
		assert_eq(_chapters(cid).size(), 10, "%s has ten chapters" % cid)
		var tiers := []
		for ch in _chapters(cid):
			tiers.append(int(ch.get("max_tier", 0)))
			assert_false(String(ch.get("intro", "")).is_empty(), "%s has a story intro" % ch["id"])
			assert_false(String(ch.get("outro", "")).is_empty(), "%s has a story outro" % ch["id"])
		assert_eq(tiers, TIERS, "%s follows the tier schedule" % cid)
	assert_eq(Campaign.validate(data), [] as Array[String], "the campaigns validate")


func test_hand_made_maps_validate() -> void:
	for cid in CAMPAIGNS:
		for mid in CAMPAIGNS[cid]["maps"]:
			var def := data.load_map(mid)
			assert_false(def.is_empty(), "%s loads" % mid)
			assert_eq(MapValidator.validate(def, data), [] as Array[String], "%s validates" % mid)


func test_every_chapter_begins_with_its_story_enemies_and_allies() -> void:
	for cid in CAMPAIGNS:
		var spec: Dictionary = CAMPAIGNS[cid]
		var c := Campaign.start(data, cid, 4)
		for i in _chapters(cid).size():
			c.chapter = i
			var s := c.begin_chapter(data)
			var chid: String = _chapters(cid)[i]["id"]
			assert_true(s != null, "%s starts" % chid)
			var others: Array = spec["others"][i]
			assert_eq(s.state.players.size(), 1 + others.size(), "%s player count" % chid)
			assert_eq(s.state.player(0)["faction"], spec["faction"])
			assert_true(bool(s.state.player(0)["is_human"]))
			for o in others.size():
				var p: int = o + 1
				assert_eq(s.state.player(p)["faction"], others[o][0], "%s player %d" % [chid, p])
				assert_false(bool(s.state.player(p)["is_human"]))
				assert_eq(s.allied(0, p), bool(others[o][1]), "%s player %d allied with the player" % [chid, p])
				if not WaveDirector.reserved_player(s.state, p):
					assert_gt(float(s.towns_of(p).size()), 0.0, "%s player %d holds a town" % [chid, p])
			assert_eq(s.tier_cap(), TIERS[i])
			for hid in spec["veterans"]:
				var h := s.hero(hid)
				var present: bool = (spec["veterans"][hid] as Array).has(i)
				if present:
					assert_true(h != null and h.owner == 0, "%s: %s fights for the player" % [chid, hid])
				else:
					assert_true(h == null or h.owner != 0, "%s: %s is not on the player's side" % [chid, hid])
				if h != null:
					assert_true(s.state.map.is_passable(h.pos), "%s %s stands on open ground" % [chid, hid])
			for id in s.state.heroes:
				var h: Hero = s.state.heroes[id]
				if h.owner != 0:
					continue
				assert_true((spec["veterans"] as Dictionary).has(id), "%s: %s is a veteran, not a leftover generated hero" % [chid, id])
				for st in h.army.slots:
					if not st.is_empty():
						assert_true(int(data.creature(st["creature"])["tier"]) <= TIERS[i], "%s %s starts within the cap" % [chid, id])


func test_the_eyes_are_collected_and_then_set_in_the_gate() -> void:
	var c := Campaign.start(data, "six_eyes", 7)
	var found: Array[String] = []
	for i in range(2, 8):
		c.chapter = i
		var s := c.begin_chapter(data)
		c.complete_chapter(data, s, true)
		for r in _chapters("six_eyes")[i].get("rewards", []):
			if String(r.get("type", "")) == "artifact":
				found.append(String(r["artifact"]))
	assert_eq(found, EYES, "one Eye per surface people, in story order")
	c.chapter = 9
	var finale := c.begin_chapter(data)
	assert_eq(_chapters("six_eyes")[9].get("take_artifacts", []), EYES)
	var serane := finale.hero("hero_serane")
	assert_true(serane != null)
	for eye in EYES:
		assert_false(serane.all_artifacts(data).has(eye), "%s has been set in the Nightgate" % eye)


func test_the_nightgate_is_hero_only_with_the_dragon_in_the_gate() -> void:
	var c := Campaign.start(data, "six_eyes", 5)
	c.chapter = 9
	var s := c.begin_chapter(data)
	assert_eq(s.towns_of(0).size(), 0, "the Wardens hold no town")
	assert_true(s.hero("hero_ulmarra") != null and s.hero("hero_ulmarra").owner == 1, "Ulmarra is Vexmire")
	assert_true(s.state.rules.has("scenario"), "the finale has scenario objectives")
	var dragons := 0
	for oid in s.state.map.objects:
		var obj: Dictionary = s.state.map.objects[oid]
		if String(obj.get("type", "")) == "neutral_army":
			for st in obj.get("stacks", []):
				if String(st[0]) == "ancient_dragon":
					dragons += int(st[1])
	assert_eq(dragons, 1, "one Karzhaloth")
	var dragon := data.creature("ancient_dragon")
	assert_eq(int(dragon["tier"]), 8)
	assert_true((dragon.get("tags", []) as Array).has("boss"))
	assert_gt(float(dragon["hp"]), 1000.0, "a boss, not a stack")


func test_the_forgewarm_harness_is_the_survival_reward() -> void:
	var c := Campaign.start(data, "drowned_oath", 2)
	c.chapter = 5
	var s := c.begin_chapter(data)
	c.complete_chapter(data, s, true)
	c.chapter = 6
	s = c.begin_chapter(data)
	var ilo := s.hero("hero_ilo")
	assert_true(ilo != null)
	var worn := ilo.all_artifacts(data)
	for piece in ["emberglass_visor", "furnace_mail", "hearthstride_greaves"]:
		assert_true(worn.has(piece), "%s carried into the cold" % piece)
	assert_eq(data.factions["fishmen"].get("hostile_terrain", []), ["snow"], "the Shoal cannot bear the cold")


func test_finales_run_against_several_enemies() -> void:
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
	var c2 := Campaign.start(data, "drowned_oath", 5)
	c2.chapter = 9
	var s2 := c2.begin_chapter(data)
	assert_eq(s2.state.players.size(), 3)
	for p in range(1, 3):
		assert_eq(s2.difficulty_of(p), "easy", "one against two is gentler")
	assert_true(s2.state.allied(1, 2), "the clans and the Concord fight together")


## Chapters 2-9 are frozen, hand-tuned map files (tools/maps/build_*_chapters.py), each playing the
## scenario of the map overhaul schedule: L layout, C conquest, T townless, A 2v2, S survival, B betrayal.
const SCHEDULE := {
	"six_eyes": ["L", "T", "C", "B", "A", "C", "C", "S"],
	"drowned_oath": ["L", "C", "A", "C", "S", "C", "B", "T"],
}


func test_middle_chapters_are_map_files_playing_their_scenario() -> void:
	for cid in SCHEDULE:
		for k in SCHEDULE[cid].size():
			var i: int = k + 1
			var chapter: Dictionary = _chapters(cid)[i]
			var key: String = SCHEDULE[cid][k]
			var chid: String = chapter["id"]
			assert_true(FileAccess.file_exists("res://data/maps/%s.json" % chapter["map"]), "%s plays a map file" % chid)
			var c := Campaign.start(data, cid, 11)
			c.chapter = i
			var s := c.begin_chapter(data)
			var sc: Dictionary = s.state.rules.get("scenario", {})
			var types := []
			for obj in sc.get("objectives", []):
				types.append(String(obj["type"]))
			match key:
				"L", "C":
					assert_false(sc.has("betrayal") or sc.has("townless_players"), "%s is a plain chapter" % chid)
				"T":
					var townless: Array = sc.get("townless_players", [])
					assert_true(townless.size() == 1 and int(townless[0]) == 0, "%s starts without a town" % chid)
					assert_eq(s.towns_of(0).size(), 0, "%s: no town at the start" % chid)
					var villages := 0
					for oid in s.state.map.objects:
						var o: Dictionary = s.state.map.objects[oid]
						if String(o.get("type", "")) == "site" and not (o.get("stock", []) as Array).is_empty():
							villages += 1
					assert_true(villages >= 4, "%s has villages to recruit from" % chid)
				"A":
					assert_true(types.has("ally_survives"), "%s keeps an ally alive" % chid)
					assert_true(s.allied(0, 2), "%s: slot 2 is the ally" % chid)
				"S":
					assert_true(types.has("survive"), "%s is survived to a day" % chid)
				"B":
					assert_true(sc.has("betrayal"), "%s has a betrayal" % chid)
					assert_eq(int(sc["betrayal"]["player"]), 2, "%s: the ally turns" % chid)
					assert_true(s.allied(0, 2), "%s: the ally starts on the player's side" % chid)


func test_the_shoal_stays_off_the_snow_until_the_harness() -> void:
	# The Forgewarm Harness is the chapter 6 reward; before it the Shoal's start and towns are never on snow,
	# and from chapter 7 on the Shoal still starts and finds its first town off the snow.
	for i in range(1, 9):
		var c := Campaign.start(data, "drowned_oath", 4)
		c.chapter = i
		var s := c.begin_chapter(data)
		var chid: String = _chapters("drowned_oath")[i]["id"]
		var ilo := s.hero("hero_ilo")
		assert_true(s.state.map.terrain_at(ilo.pos) != "snow", "%s: Ilo starts off the snow" % chid)
		for t in s.towns_of(0):
			assert_true(s.state.map.terrain_at(Vector2i(int(t["pos"][0]), int(t["pos"][1]))) != "snow", "%s: %s is off the snow" % [chid, t["name"]])
		if i <= 5:
			var snow := 0
			var tiles: int = s.state.map.width * s.state.map.height
			for y in s.state.map.height:
				for x in s.state.map.width:
					if s.state.map.terrain_at(Vector2i(x, y)) == "snow":
						snow += 1
			assert_true(snow * 10 < tiles, "%s: at most a snowy edge before the Harness" % chid)
