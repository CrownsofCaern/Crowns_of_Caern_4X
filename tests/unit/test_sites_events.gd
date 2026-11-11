extends "res://tests/test_case.gd"
## Rare map buildings (data/sites.json, MapSites) and random events
## (data/events.json, WorldEvents): rules, saves, map generation and the AI.


func _session(seed_value: int = 3, rules: Dictionary = {}) -> GameSession:
	return GameSession.new_game(data, "twin_marches", seed_value, {}, rules)


## Puts a site on a free tile next to the hero and returns it.
func _put_site(s: GameSession, h: Hero, site_id: String, extra: Dictionary = {}) -> Dictionary:
	var p := s._free_tile_near(h.pos)
	var o := {"id": "test_site_%s" % site_id, "type": "site", "site": site_id, "pos": [p.x, p.y]}
	o.merge(extra, true)
	s.state.map.add_object(o)
	MapSites.normalize(o, data)
	s.state.player(h.owner)["fog"].reveal(p, 2)
	return o


func _pos(o: Dictionary) -> Vector2i:
	return AdventureMap.object_pos(o)


## Ends turns until the given day starts.
func _to_day(s: GameSession, day: int) -> void:
	while s.state.day < day:
		s.end_turn()


# ------------------------------------------------------------------- data --

func test_site_and_event_data_validate() -> void:
	var errors := MapSites.validate(data)
	errors.append_array(WorldEvents.validate(data))
	assert_true(errors.is_empty(), "\n".join(errors))
	assert_true(data.sites.has("spell_crypt"))
	var kinds := {}
	for sid in data.sites:
		kinds[data.sites[sid]["kind"]] = true
	assert_eq(kinds.size(), MapSites.KINDS.size(), "every kind is used")


func test_validation_catches_bad_sites_and_events() -> void:
	var sites: Dictionary = data.sites.duplicate(true)
	var events: Dictionary = data.world_events.duplicate(true)
	data.sites["oathstone"]["attributes"] = {"charisma": 1}
	data.sites["pilgrims_rest"]["mods"] = {"luckiness": 1}
	data.sites["outcast_camp"]["tiers"] = [9, 9]
	data.world_events["weekly"]["ashfall"]["effects"] = [{"type": "earthquake"}]
	data.world_events["fortunes"]["lost_caravan"]["effects"][0]["resource"] = "silver"
	var errors := MapSites.validate(data)
	errors.append_array(WorldEvents.validate(data))
	data.sites = sites
	data.world_events = events
	var text := "\n".join(errors)
	for word in ["charisma", "luckiness", "outcast_camp", "earthquake", "lost_caravan"]:
		assert_true(text.contains(word), "%s reported:\n%s" % [word, text])


func test_every_site_has_its_landmark_sprite() -> void:
	for sid in data.sites:
		assert_true(Art.has_sprite(String(data.sites[sid]["sprite"])), "%s sprite %s" % [sid, data.sites[sid]["sprite"]])


func test_dwelling_pools_never_hold_upgrades() -> void:
	for sid in data.sites:
		if data.sites[sid]["kind"] != "dwelling":
			continue
		var pool := MapSites.creature_pool(data.sites[sid], data)
		assert_gt(pool.size(), 3, sid)
		for c in pool:
			assert_false(data.creature(c).has("upgrade_of"), c)


# ------------------------------------------------------------------ sites --

func test_attribute_site_once_per_hero() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "oathstone")
	var before := h.defense
	var r := s.move_hero(h.id, _pos(o))
	assert_eq(r["site"], o["id"])
	assert_eq(r["visited"].size(), 1)
	assert_eq(h.defense, before + 1)
	assert_ne(MapSites.visit_block(h, o, data), "", "already visited")
	h.pos = s._free_tile_near(_pos(o))
	h.movement_left = 1000
	s.move_hero(h.id, _pos(o))
	assert_eq(h.defense, before + 1, "a second visit gives nothing")


func test_boon_site_lasts_its_days_and_can_be_renewed() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "wardens_causeway")
	var base_move := h.max_movement(data)
	s.move_hero(h.id, _pos(o))
	assert_true(h.has_boon(o["id"]))
	assert_gt(h.max_movement(data), base_move, "the causeway speeds the hero")
	_to_day(s, 1 + 7)
	assert_false(h.has_boon(o["id"]), "gone after seven days")
	assert_eq(MapSites.visit_block(h, o, data), "", "can be taken again")


func test_lore_site_grants_experience() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "elder_rings")
	var before := h.xp
	s.move_hero(h.id, _pos(o))
	assert_eq(h.xp - before, h.xp_with_bonus(int(data.sites["elder_rings"]["xp"]), data))
	assert_gt(h.skill_points, 0, "1200 XP is a level")


func test_dwelling_site_capture_recruit_and_growth() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "outcast_camp", {"creature": "cinderling", "owner": -1})
	assert_eq(int(o["available"]), MapSites.weekly_growth(o, data))
	assert_ne(s.site_recruit_error(o["id"], h.id, 1), "", "not held yet")
	var r := s.move_hero(h.id, _pos(o))
	assert_true(r["captured"].has(o["id"]))
	assert_eq(int(o["owner"]), 0)
	var gold := s._bank(0).get_amount("gold")
	var n := int(o["available"])
	var res := s.site_recruit(o["id"], h.id, n)
	assert_true(res["ok"], str(res))
	assert_eq(int(o["available"]), 0)
	assert_eq(s._bank(0).get_amount("gold"), gold - n * int(data.creature("cinderling")["cost"]["gold"]))
	var found := false
	for slot in h.army.slots:
		if not slot.is_empty() and slot["creature"] == "cinderling":
			found = true
	assert_true(found, "a foreign creature joins the hero")
	_to_day(s, 8)
	assert_eq(int(o["available"]), MapSites.weekly_growth(o, data), "the pool refills each week (no omen in week 1 decides)")


func test_dwelling_site_respects_a_chapter_tier_cap() -> void:
	var s := _session(3, {"max_tier": 2})
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "pyre_citadel", {"creature": "ash_witch", "owner": -1})
	s.move_hero(h.id, _pos(o))
	s._bank(0).add("gold", 20000)
	s._bank(0).add("mercury", 20)
	assert_true(s.site_recruit_error(o["id"], h.id, 1).contains("tier"))
	assert_eq(StrategicAI.new(s, 0).site_value(h, o), 0.0)


func test_rotating_dwelling_draws_a_new_company() -> void:
	var s := _session(5, {"random_events": false})
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "sellsword_gate", {"creature": "cinderling", "owner": 0, "available": 99})
	var seen := {}
	for week in 4:
		_to_day(s, 8 + week * 7)
		seen[o["creature"]] = true
		assert_eq(int(o["available"]), MapSites.weekly_growth(o, data), "old pool is lost")
		var t := int(data.creature(o["creature"])["tier"])
		assert_between(t, 2, 4)
	assert_gt(seen.size(), 1, "the company changes")


func test_guarded_site_is_fought_then_visited() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	h.army = Army.from_pairs([["sunhawk_rider", 30], ["lightbearer", 30]])
	var o := _put_site(s, h, "bleeding_rift", {"guard": [["cinderling", 3]]})
	assert_true(s.is_guarded(o, 0))
	var r := s.move_hero(h.id, _pos(o))
	assert_eq(r["battle"], o["id"])
	var atk := h.attack
	var result := s.attack(h.id, o["id"])
	assert_eq(result["winner"], 0)
	assert_false(o.has("guard"))
	assert_eq(h.pos, _pos(o))
	assert_eq(h.attack, atk + 1, "the rift's gift after the battle")
	assert_false(s.is_guarded(o, 1), "open for everyone now")


# ----------------------------------------------------------------- events --

func test_no_events_in_the_first_week_then_an_omen_each_week() -> void:
	var s := _session(11)
	_to_day(s, 7)
	assert_true(s.state.omen.is_empty())
	_to_day(s, 8)
	assert_false(s.state.omen.is_empty())
	assert_eq(int(s.state.omen["week"]), 2)
	assert_true(data.world_events["weekly"].has(s.state.omen["id"]))
	var news := s.take_news(0)
	assert_true(news.size() >= 1 and String(news[0]).begins_with("Omen of week 2"), str(news))
	assert_true(s.take_news(0).is_empty(), "news is cleared once taken")
	assert_true(s.state.player(1)["news"].is_empty(), "computer players keep no news")


func test_events_can_be_turned_off() -> void:
	var s := _session(11, {"random_events": false})
	_to_day(s, 16)
	assert_true(s.state.omen.is_empty())


func test_the_tutorial_chapter_has_no_events() -> void:
	var ch: Dictionary = data.campaigns["last_light"]["chapters"][0]
	assert_eq(Campaign.chapter_rules(ch)["random_events"], false)
	assert_false(Campaign.chapter_rules(data.campaigns["last_light"]["chapters"][1]).has("random_events"))


func test_events_are_deterministic() -> void:
	var omens := []
	for _k in 2:
		var s := _session(21)
		var ids := []
		for week in range(2, 7):
			_to_day(s, (week - 1) * 7 + 1)
			ids.append(s.state.omen["id"])
		omens.append(ids)
	assert_eq(omens[0], omens[1])


func _force_omen(s: GameSession, id: String, extra: Dictionary = {}) -> void:
	s.state.omen = {"id": id, "week": s.state.week()}
	s.state.omen.merge(extra, true)


func test_growth_omens_add_to_weekly_growth() -> void:
	var s := _session()
	var t: Dictionary = s.town("town_greywatch")
	var c: String = Town.dwellings(t, data)[0]
	var tier := int(data.creature(c)["tier"])
	_force_omen(s, "teeming_moon")
	assert_eq(WorldEvents.growth_bonus(s.state, data, c), 0.5)
	_force_omen(s, "levy_week", {"tier": tier})
	assert_eq(WorldEvents.growth_bonus(s.state, data, c), 1.0)
	_force_omen(s, "levy_week", {"tier": tier + 1})
	assert_eq(WorldEvents.growth_bonus(s.state, data, c), 0.0)
	var plain := Town.weekly_growth(t, c, data)
	assert_eq(Town.weekly_growth(t, c, data, 1.0), plain * 2)
	assert_eq(Town.weekly_growth(t, c, data, -0.25), int(floor(plain * 0.75)))


func test_income_omens_change_daily_income() -> void:
	var s := _session()
	var plain := s.daily_income(0)
	_force_omen(s, "tithe_riots")
	assert_eq(int(s.daily_income(0)["gold"]), int(round(int(plain["gold"]) * 0.75)))
	_force_omen(s, "rich_veins")
	assert_eq(int(s.daily_income(0)["gold"]), int(plain["gold"]))
	_force_omen(s, "tithe_riots")
	s.state.omen["week"] = s.state.week() - 1
	assert_eq(s.daily_income(0), plain, "last week's omen is over")


func test_hero_omen_reaches_every_hero_and_ends_with_the_week() -> void:
	var s := _session(3)
	_to_day(s, 7)
	s.state.day = 7
	# Roll the omen by hand on the first day of week 2.
	s.state.day = 8
	var heroes := s._all_heroes_sorted()
	var omen := {}
	var seed_value := 1
	while omen.get("id", "") != "blood_sky":
		s.state.rng = GameRng.new(seed_value)
		omen = WorldEvents.roll_omen(s.state, data, heroes)
		seed_value += 1
	for h in heroes:
		assert_true((h as Hero).has_boon(WorldEvents.OMEN_SOURCE))
		assert_eq(int((h as Hero).combat_profile(data)["attack"]), (h as Hero).attack + HeroModifiers.whole((h as Hero).modifiers(data), "attack"))
	var h0: Hero = heroes[0]
	h0.expire_boons(14)
	assert_true(h0.has_boon(WorldEvents.OMEN_SOURCE), "lasts through day 14")
	h0.expire_boons(15)
	assert_false(h0.has_boon(WorldEvents.OMEN_SOURCE))


func test_gathering_dark_grows_neutral_armies() -> void:
	var s := _session(3)
	var counts := {}
	for id in s.state.map.objects:
		var o: Dictionary = s.state.map.objects[id]
		if o["type"] == "neutral_army":
			counts[id] = int(o["stacks"][0][1])
	assert_false(counts.is_empty())
	s.state.day = 8
	var omen := {}
	var seed_value := 1
	while omen.get("id", "") != "gathering_dark":
		for id in counts:
			s.state.map.objects[id]["stacks"][0][1] = counts[id]
		s.state.rng = GameRng.new(seed_value)
		omen = WorldEvents.roll_omen(s.state, data, [])
		seed_value += 1
	for id in counts:
		assert_gt(int(s.state.map.objects[id]["stacks"][0][1]), counts[id], id)


func test_fortunes_reach_only_their_player() -> void:
	var s := _session(3)
	var ev: Dictionary = data.world_events.duplicate(true)
	data.world_events["fortune_chance"] = 1.0
	data.world_events["fortunes"] = {"lost_caravan": ev["fortunes"]["lost_caravan"]}
	s.state.day = 8
	var gold := s._bank(0).get_amount("gold")
	var line := WorldEvents.roll_fortune(s.state, data, 0, s._heroes_sorted(0))
	data.world_events = ev
	assert_true(line.begins_with("Lost Caravan"), line)
	assert_between(s._bank(0).get_amount("gold") - gold, 400, 900)


func test_fortune_effects_apply() -> void:
	var s := _session(3)
	var ev: Dictionary = data.world_events.duplicate(true)
	data.world_events["fortune_chance"] = 1.0
	var h: Hero = s.hero("hero_west")
	var lines := {}
	for fid in ev["fortunes"]:
		data.world_events["fortunes"] = {fid: ev["fortunes"][fid]}
		lines[fid] = WorldEvents.roll_fortune(s.state, data, 0, [h])
	data.world_events = ev
	for fid in lines:
		assert_ne(lines[fid], "", "%s applies to a hero with room and a full purse" % fid)
	assert_true(h.has_boon("fortune_pilgrims_blessing"))


# ------------------------------------------------------------------ saves --

func test_sites_events_and_boons_survive_a_save() -> void:
	var s := _session(3)
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "pilgrims_rest")
	s.move_hero(h.id, _pos(o))
	_force_omen(s, "teeming_moon")
	s._add_news(s.state.player(0), "A test line")
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	var back := GameSession.from_state(data, GameState.from_dict(d, data))
	var bh: Hero = back.hero("hero_west")
	assert_true(bh.has_boon(o["id"]))
	assert_eq(HeroModifiers.whole(bh.modifiers(data), "morale"), HeroModifiers.whole(h.modifiers(data), "morale"))
	assert_eq(back.state.omen["id"], "teeming_moon")
	assert_eq(back.take_news(0), ["A test line"])
	assert_eq(back.state.map.objects[o["id"]]["site"], "pilgrims_rest")


func test_version_9_save_loads_without_events() -> void:
	var s := _session(3)
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	d["version"] = 9
	d.erase("omen")
	for p in d["players"]:
		p.erase("news")
	for id in d["heroes"]:
		d["heroes"][id].erase("boons")
	assert_true(GameState.validate_save(d).is_empty())
	var back := GameSession.from_state(data, GameState.from_dict(d, data))
	assert_true(back.state.omen.is_empty())
	assert_true(back.take_news(0).is_empty())
	assert_true(back.hero("hero_west").boons.is_empty())


# --------------------------------------------------------- map generation --

func test_generated_maps_place_fair_sites() -> void:
	for seed_value in [1, 17]:
		var def := generated_map("twin_marches", seed_value)
		assert_true(MapValidator.validate(def, data).is_empty(), "seed %d validates" % seed_value)
		var by_zone := {}
		for o in def["objects"]:
			if o["type"] == "site":
				var z := String(o["zone"])
				if not by_zone.has(z):
					by_zone[z] = []
				by_zone[z].append(o["site"])
				if data.sites[o["site"]]["kind"] == "dwelling":
					assert_true(data.creatures.has(o.get("creature", "")))
		assert_true(by_zone.has("start_0") and by_zone.has("start_1"), "seed %d: a site at every start" % seed_value)
		assert_eq(by_zone["start_0"], by_zone["start_1"], "the same site at both starts")
		var total := 0
		for z in by_zone:
			total += by_zone[z].size()
		assert_gt(total, 3, "seed %d: extra sites in the open zones" % seed_value)


func test_crossing_maps_get_sites_too() -> void:
	var def := generated_map("crossing", 1)
	assert_true(MapValidator.validate(def, data).is_empty())
	assert_gt(def["objects"].filter(func(o): return o["type"] == "site").size(), 2)


# --------------------------------------------------------------------- AI --

func test_ai_values_sites_it_can_use() -> void:
	var s := _session(3)
	s.end_turn()
	var h: Hero = s.hero("hero_east")
	var ai := StrategicAI.new(s, 1)
	var stone := _put_site(s, h, "oathstone")
	assert_gt(ai.site_value(h, stone), 0.0)
	stone["visitors"] = [h.id]
	assert_eq(ai.site_value(h, stone), 0.0, "nothing left to gain")
	var camp := _put_site(s, h, "outcast_camp", {"creature": "pike_militia", "owner": -1})
	assert_gt(ai.site_value(h, camp), 0.0, "worth taking")


func test_ai_takes_a_nearby_dwelling_and_recruits() -> void:
	var s := _session(3)
	s.end_turn()
	var h: Hero = s.hero("hero_east")
	var o := _put_site(s, h, "outcast_camp", {"creature": "pike_militia", "owner": -1})
	s._bank(1).add("gold", 5000)
	# Next to the mines at home the camp is worth less; weigh it up so it comes first.
	StrategicAI.new(s, 1, {"site_capture_weeks": 12.0}).play_turn()
	assert_eq(int(o["owner"]), 1, "captured")
	assert_lt(float(o["available"]), float(MapSites.weekly_growth(o, data)), "recruited from the pool")
