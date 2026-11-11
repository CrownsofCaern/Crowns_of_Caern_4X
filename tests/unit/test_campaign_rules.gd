extends "res://tests/test_case.gd"
## Per-game rules a campaign chapter sets: the creature tier cap on every town
## and computer-player settings (a passive tutorial opponent).

const TOWN := "town_greyhold"


func _capped(cap: int) -> GameSession:
	return GameSession.new_game(data, "ember_ford", 11, {}, {"max_tier": cap})


func _rich(s: GameSession) -> void:
	for res in data.resource_order:
		s.current_player()["resources"].add(res, 100000)


func test_tier_cap_blocks_higher_dwellings() -> void:
	var s := _capped(3)
	_rich(s)
	assert_eq(s.tier_cap(), 3)
	var t := s.town(TOWN)
	assert_eq(int(t["tier_cap"]), 3, "every town carries the chapter's cap")
	for b in ["c_dw1", "c_dw2", "c_dw3"]:
		if not Town.has_building(t, b):
			t["built"].append(b)
	assert_eq(s.can_build(TOWN, "c_dw4"), "unlocks in a later chapter")
	assert_eq(s.can_build(TOWN, "c_up4"), "unlocks in a later chapter", "upgrades of locked tiers stay locked")
	assert_eq(s.can_build(TOWN, "c_remount"), "unlocks in a later chapter", "growth of locked tiers stays locked")
	assert_eq(s.can_build(TOWN, "c_up3"), "", "tier 3 upgrade is open")


func test_tier_cap_idles_prebuilt_dwellings() -> void:
	var s := _capped(2)
	var t := s.town(TOWN)
	t["built"].append_array(["c_dw2", "c_dw3", "c_dw4"])
	assert_eq(Town.dwellings(t, data), ["pike_militia", "longbowman"])
	t["available"]["lancer"] = 5
	_rich(s)
	assert_false(s.recruit(TOWN, "lancer", 1, true)["ok"], "a dwelling above the cap does not recruit")
	assert_eq(s.max_recruitable(TOWN, "lancer"), 0)
	var before := int(t["available"].get("shieldwarden", 0))
	Town.apply_weekly_growth(t, data)
	assert_eq(int(t["available"].get("shieldwarden", 0)), before, "and does not grow")


func test_no_cap_by_default() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	assert_eq(s.tier_cap(), 0)
	assert_false(s.town(TOWN).has("tier_cap"))
	var t := s.town(TOWN)
	t["built"].append_array(["c_dw2", "c_dw3", "c_dw4"])
	assert_true(Town.dwellings(t, data).has("lancer"))


func test_rules_survive_save_and_load() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11, {}, {"max_tier": 4, "ai": {"passive": true}})
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	var back := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_eq(back.tier_cap(), 4)
	assert_eq(int(back.town(TOWN)["tier_cap"]), 4)
	assert_true(bool(back.state.rules["ai"]["passive"]))


func test_v7_save_plays_by_standard_rules() -> void:
	var s := _capped(3)
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	d["version"] = 7
	d.erase("rules")
	for id in d["objects"]:
		d["objects"][id].erase("tier_cap")
	var back := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_eq(back.tier_cap(), 0)
	assert_false(back.town(TOWN).has("tier_cap"))


func test_passive_ai_ignores_rival_heroes_and_towns() -> void:
	var rules := {"ai": {"passive": true}}
	var passive := GameSession.new_game(data, "burning_ford", 3, {}, rules)
	var normal := GameSession.new_game(data, "burning_ford", 3)
	for s in [passive, normal]:
		# Wren stands right in front of the Ashen hero, in plain sight.
		var skarn: Hero = s.hero("hero_skarn")
		s.hero("hero_wren").pos = skarn.pos + Vector2i(-2, 0)
		s.state.player(1)["fog"].reveal(skarn.pos, 30)
	var kinds := []
	for s in [passive, normal]:
		var ai := StrategicAI.new(s, 1, {"strength_prefilter": 0.0})
		var h: Hero = s.hero("hero_skarn")
		var field := AiDistanceField.build(s.state.map, h.pos, ai._blocked_for(h))
		var rival := 0
		for c in ai.candidate_targets(h, field):
			if c["kind"] == "hero":
				rival += 1
			elif c["kind"] in ["town", "mine"] and int(s.state.map.objects[c["id"]].get("owner", -1)) == 0:
				rival += 1
		kinds.append(rival)
	assert_eq(kinds[0], 0, "the passive AI never targets the player")
	assert_gt(kinds[1], 0, "the normal AI does")


func test_passive_ai_leaves_the_player_alone() -> void:
	var s := GameSession.new_game(data, "burning_ford", 5, {}, {"ai": {"passive": true}})
	var greyhold := ""
	for t in s.towns_of(0):
		greyhold = t["id"]
	for _day in 14:
		s.end_turn()
		StrategicAI.play_ai_turns(s, 4)
	assert_false(s.state.game_over)
	assert_eq(int(s.town(greyhold)["owner"]), 0, "the player's town was never taken")
	assert_true(s.hero("hero_wren").alive)
	assert_true(s.hero("hero_maelis").alive)


func test_ai_can_be_kept_from_building_and_recruiting() -> void:
	var s := GameSession.new_game(data, "burning_ford", 5, {}, {"ai": {"builds": false, "recruits": false}})
	s.end_turn()
	var rep := StrategicAI.new(s, 1).play_turn()
	assert_eq(int(rep["builds"]), 0)
	assert_eq(int(rep["recruits"]), 0)


func test_campaign_chapter_applies_its_rules() -> void:
	var original: Dictionary = data.campaigns["last_light"].duplicate(true)
	data.campaigns["last_light"]["chapters"][0]["max_tier"] = 1
	data.campaigns["last_light"]["chapters"][0]["ai"] = {"passive": true, "max_heroes": 1}
	var c := Campaign.start(data, "last_light", 3)
	var s := c.begin_chapter(data)
	data.campaigns["last_light"] = original
	assert_eq(s.tier_cap(), 1)
	assert_true(bool(s.state.rules["ai"]["passive"]))
	assert_eq(int(s.state.rules["ai"]["max_heroes"]), 1)
	assert_eq(c.chapter_list(data)[0]["max_tier"], 2, "the real chapter caps at tier 2")


func test_campaign_validation_checks_tiers_and_ai() -> void:
	var original: Dictionary = data.campaigns["last_light"].duplicate(true)
	var chs: Array = data.campaigns["last_light"]["chapters"]
	chs[1]["max_tier"] = 1            # falls below chapter 1's tier 2
	chs[9]["max_tier"] = 99           # beyond the roster
	chs[0]["ai"] = {"passive": 1, "no_such_setting": true}
	var errors := Campaign.validate(data)
	data.campaigns["last_light"] = original
	assert_eq(errors.size(), 4, "\n".join(errors))
	assert_eq(Campaign.validate(data).size(), 0)
	assert_eq(data.max_creature_tier(), 8)


func _generated_chapter() -> Dictionary:
	return {"id": "gen_test", "name": "Generated test", "map": "gen:crossing:7", "level_cap": 4, "max_tier": 3,
		"setup": {"players": [{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "hollow"}]},
		"cast": [
			{"id": "hero_wren", "name": "Aldous Wren", "class": "knight", "owner": 0, "replaces": "hero_p0",
				"army": [["pike_militia", 20], ["longbowman", 10]]},
			{"id": "hero_maelis", "name": "Maelis Thorne", "class": "ranger", "owner": 0,
				"army": [["longbowman", 8]]}]}


func test_generated_chapter_places_the_cast() -> void:
	var plain := GameSession.new_game(data, "gen:crossing:7", 1, _generated_chapter()["setup"])
	var start: Vector2i = plain.hero("hero_p0").pos
	var original: Dictionary = data.campaigns["last_light"].duplicate(true)
	data.campaigns["last_light"]["chapters"][0] = _generated_chapter()
	var errors := Campaign.validate(data)
	var c := Campaign.start(data, "last_light", 3)
	var s := c.begin_chapter(data)
	data.campaigns["last_light"] = original
	assert_eq(errors.size(), 0, "\n".join(errors))
	assert_eq(s.hero("hero_p0"), null, "the generated hero made way")
	var wren := s.hero("hero_wren")
	assert_eq(wren.pos, start, "the lead veteran takes its place")
	assert_eq(wren.owner, 0)
	assert_eq(wren.army.total_creatures(), 30)
	var maelis := s.hero("hero_maelis")
	assert_true(maelis != null)
	assert_ne(maelis.pos, wren.pos)
	assert_lt(float(maxi(absi(maelis.pos.x - wren.pos.x), absi(maelis.pos.y - wren.pos.y))), 9.0, "the second veteran stands nearby")
	assert_true(s.state.map.is_passable(maelis.pos))
	assert_true(s.state.map.object_at(maelis.pos).is_empty())
	assert_eq(s.state.player(1)["faction"], "hollow")
	assert_eq(s.tier_cap(), 3)
	# The chapter saves and loads like any generated game.
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	var back := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_eq(back.hero("hero_maelis").pos, maelis.pos)


func test_generated_chapter_validation() -> void:
	var original: Dictionary = data.campaigns["last_light"].duplicate(true)
	var ch := _generated_chapter()
	ch["map"] = "gen:no_such_template:3"
	data.campaigns["last_light"]["chapters"][0] = ch
	var errors := Campaign.validate(data)
	ch = _generated_chapter()
	ch["cast"].pop_front()   # no lead hero
	ch["setup"]["players"][1]["faction"] = "wilds"
	ch["cast"][0]["army"] = [["no_such_creature", 3]]
	data.campaigns["last_light"]["chapters"][0] = ch
	var errors2 := Campaign.validate(data)
	data.campaigns["last_light"] = original
	assert_eq(errors.size(), 1, "\n".join(errors))
	assert_eq(errors2.size(), 3, "\n".join(errors2))


func test_ember_chronicle_progress_loads_as_the_last_light() -> void:
	var dir := "user://test_legacy_campaign"
	DirAccess.make_dir_recursive_absolute(dir)
	var c := Campaign.start(data, "last_light", 5)
	c.chapter = 8
	var s := c.begin_chapter(data)
	var d := c.to_dict(s)
	# Rewrite it as the old Ember Chronicle saved it: chapter 2 of 3, one chapter won.
	d["campaign"] = "ember_chronicle"
	d["chapter"] = 1
	d["completed"] = ["ford_burning"]
	d["active_game"]["campaign"] = {"campaign_version": 1, "campaign": "ember_chronicle", "chapter": 1, "seed": 5,
		"roster": {}, "completed": ["ford_burning"], "active_game": {}}
	var f := FileAccess.open(Campaign.progress_path("ember_chronicle", dir), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var back := Campaign.load_progress(data, "last_light", dir)
	assert_true(back != null, "the old progress file is found")
	assert_eq(back.campaign_id, "last_light")
	assert_eq(back.chapter, 8, "Ashes Return is chapter 9 now")
	assert_eq(back.completed, ["ll_ford"] as Array[String])
	var resumed := back.resume(data)
	var again := Campaign.of_session(data, resumed)
	assert_true(again != null, "the chapter in progress still belongs to the campaign")
	assert_eq(again.campaign_id, "last_light")
	assert_eq(again.chapter, 8)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Campaign.progress_path("ember_chronicle", dir)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
