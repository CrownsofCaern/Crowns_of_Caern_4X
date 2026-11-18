extends "res://tests/test_case.gd"
## Hamlets, villages and freeholds (data/sites.json kind "hamlet", Hamlets,
## game_rules.json "hamlets"): placement in a game with hamlets, the Classic
## game without, daily gold, the levy and its price, unrest and revolt,
## stationed troops and the fight for a held hamlet.


func _session(seed_value: int = 3, hamlets: bool = false) -> GameSession:
	return GameSession.new_game(data, "twin_marches", seed_value, {"hamlets": true} if hamlets else {})


func _hero(s: GameSession, owner: int = 0) -> Hero:
	return s._heroes_sorted(owner)[0]


## Puts a held hamlet on a free tile next to the hero and returns it.
func _put(s: GameSession, h: Hero, site_id: String = "hamlet_croft", owner: int = 0) -> Dictionary:
	var p := s._free_tile_near(h.pos)
	var pool := MapSites.creature_pool(data.sites[site_id], data)
	var o := {"id": "test_%s" % site_id, "type": "site", "site": site_id, "pos": [p.x, p.y], "owner": owner, "creature": pool[0]}
	s.state.map.add_object(o)
	MapSites.normalize(o, data)
	return o


func _hamlets_of(s: GameSession) -> Array:
	var out := []
	for id in s._sorted_object_ids():
		if MapSites.is_hamlet(s.state.map.objects[id], data):
			out.append(s.state.map.objects[id])
	return out


func _with_radius(radius: int, body: Callable) -> void:
	var before: int = data.rules["hamlets"]["realm_radius"]
	data.rules["hamlets"]["realm_radius"] = radius
	body.call()
	data.rules["hamlets"]["realm_radius"] = before


# ------------------------------------------------------------------- data --

func test_hamlet_data_validates_and_has_three_levels() -> void:
	assert_true(MapSites.validate(data).is_empty(), "\n".join(MapSites.validate(data)))
	var gold := {}
	for sid in data.sites:
		if data.sites[sid]["kind"] == "hamlet":
			gold[int(data.sites[sid]["level"])] = int(data.sites[sid]["gold"])
	assert_eq(gold, {1: 100, 2: 250, 3: 500})


func test_validation_catches_bad_hamlet_rules() -> void:
	var rules: Dictionary = data.rules["hamlets"].duplicate(true)
	data.rules["hamlets"]["revolt_chance"] = 1.5
	data.rules["hamlets"]["per_player"][0]["site"] = "oathstone"
	var text := "\n".join(Hamlets.validate(data))
	data.rules["hamlets"] = rules
	assert_true(text.contains("revolt_chance") and text.contains("oathstone"), text)


# -------------------------------------------------------------- placement --

func test_classic_game_has_no_hamlets() -> void:
	var s := _session(3)
	assert_false(Hamlets.enabled(s.state))
	assert_eq(_hamlets_of(s).size(), 0)


func test_game_with_hamlets_places_them_fairly_and_repeatably() -> void:
	var def := generated_map("random_m_2p_normal_normal", 3)
	var s := GameSession.new_game_from_definition(data, def, 3, {"hamlets": true})
	assert_true(Hamlets.enabled(s.state))
	var found := _hamlets_of(s)
	assert_eq(found.size(), 8, "three a side and two between")
	var levels := {}
	for o in found:
		var p := AdventureMap.object_pos(o)
		assert_eq(int(o["owner"]), -1, "hamlets start neutral")
		assert_false((o["guard"] as Array).is_empty(), "and guarded")
		assert_true(s.state.map.is_passable(p))
		var level := int(data.sites[o["site"]]["level"])
		levels[level] = int(levels.get(level, 0)) + 1
	assert_eq(levels, {1: 4, 2: 3, 3: 1})
	var again := _hamlets_of(GameSession.new_game_from_definition(data, def, 3, {"hamlets": true}))
	assert_eq(_hamlets_of(GameSession.new_game_from_definition(data, def, 3, {})).size(), 0, "the same map, played Classic")
	assert_eq(found.map(func(o): return [o["site"], o["pos"], o["creature"], o["guard"]]),
		again.map(func(o): return [o["site"], o["pos"], o["creature"], o["guard"]]))
	# The home hamlets draw their levy from the player's own folk.
	var faction := String(s.state.player(0)["faction"])
	assert_eq(String(data.creature(found[0]["creature"])["faction"]), faction)


# ---------------------------------------------------------- gold and levy --

func test_held_hamlet_pays_gold_every_day() -> void:
	var s := _session()
	var before := int(s.daily_income(0).get("gold", 0))
	_put(s, _hero(s), "hamlet_village")
	assert_eq(int(s.daily_income(0).get("gold", 0)), before + 250)
	var lines: Array = s.income_breakdown(0)["gold"]["sources"]
	assert_true(lines.any(func(l): return l[0] == "Village" and l[1] == "+250"), str(lines))


func test_levy_grows_at_half_rate_costs_half_more_and_stops_at_its_cap() -> void:
	var s := _session()
	var h := _hero(s)
	var o := _put(s, h)
	var c := String(o["creature"])
	var week := int(floor(float(data.creature(c)["growth"]) * 0.5))
	assert_eq(int(o["available"]), week, "one week's levy waits")
	for _i in 6:
		s._hamlet_week(o)
	assert_eq(int(o["available"]), week * 4, "the levy stops growing at four weeks")
	h.pos = AdventureMap.object_pos(o)
	var info := s.site_info(o["id"], h.id)
	var town_gold := int(data.creature(c)["cost"]["gold"])
	assert_eq(int(info["cost"]["gold"]), int(ceil(town_gold * 1.5)))
	assert_eq(int(info["gold"]), 100)
	s._bank(0).add("gold", 100000)
	var had := int(s._bank(0).get_amount("gold"))
	var r := s.site_recruit(o["id"], h.id, 2)
	assert_true(r["ok"], str(r))
	assert_eq(int(s._bank(0).get_amount("gold")), had - 2 * int(ceil(town_gold * 1.5)))


# ------------------------------------------------------ unrest and revolt --

func test_unhired_levy_brings_unrest_then_revolt() -> void:
	var s := _session()
	var o := _put(s, _hero(s))
	var rng := GameRng.new(11)
	_with_radius(0, func():
		assert_eq(Hamlets.on_week(o, s.state.map, rng, data), "")
		assert_eq(Hamlets.on_week(o, s.state.map, rng, data), "")
		assert_eq(Hamlets.mood(o, data), "restless")
		assert_eq(Hamlets.on_week(o, s.state.map, rng, data), "unrest")
		assert_eq(Hamlets.mood(o, data), "on the brink of revolt")
		var levy := int(o["available"])
		var weeks := 0
		while int(o["owner"]) == 0 and weeks < 40:
			Hamlets.on_week(o, s.state.map, rng, data)
			weeks += 1
		assert_lt(weeks, 40, "it rises sooner or later")
		assert_eq(int(o["owner"]), -1)
		assert_eq(o["guard"], [[o["creature"], levy]], "its own levy guards it")
		assert_eq(int(o["available"]), 0))


func test_revolt_odds_follow_the_rule() -> void:
	var s := _session()
	var o := _put(s, _hero(s))
	var rng := GameRng.new(5)
	var risen := [0]
	_with_radius(0, func():
		for _i in 400:
			o["owner"] = 0
			o["available"] = 10
			o["idle_weeks"] = 3
			o.erase("guard")
			if Hamlets.on_week(o, s.state.map, rng, data) == "revolt":
				risen[0] += 1)
	assert_between(risen[0], 160, 240, "about half of 400")


func test_hired_levy_stationed_troops_or_a_near_town_keep_the_peace() -> void:
	var s := _session()
	var h := _hero(s)
	var o := _put(s, h)
	var rng := GameRng.new(2)
	# Next to the capital: inside the realm.
	o["idle_weeks"] = 5
	assert_true(Hamlets.is_secure(o, s.state.map, data))
	assert_eq(Hamlets.on_week(o, s.state.map, rng, data), "")
	assert_eq(int(o["idle_weeks"]), 0)
	_with_radius(0, func():
		assert_false(Hamlets.is_secure(o, s.state.map, data))
		# Hired below a week's growth.
		o["idle_weeks"] = 5
		var levy := int(o["available"])
		o["available"] = 0
		assert_eq(Hamlets.on_week(o, s.state.map, rng, data), "")
		assert_eq(int(o["idle_weeks"]), 0)
		o["available"] = levy
		# Stationed troops.
		h.pos = AdventureMap.object_pos(o)
		var slot := 0
		while h.army.slots[slot].is_empty():
			slot += 1
		h.army.slots[slot]["count"] = 200
		var r := s.hamlet_station(o["id"], h.id, slot, 1)
		assert_true(r["ok"], str(r))
		o["garrison"] = [[o["creature"], 1]]
		assert_false(Hamlets.is_secure(o, s.state.map, data), "one soldier is no garrison")
		o["garrison"] = [[o["creature"], int(o["available"])]]
		assert_eq(Hamlets.garrison_worth(o, data), Hamlets.garrison_needed(o, data))
		o["idle_weeks"] = 5
		assert_eq(Hamlets.on_week(o, s.state.map, rng, data), "")
		assert_eq(int(o["idle_weeks"]), 0))


func test_station_and_withdraw_move_troops() -> void:
	var s := _session()
	var h := _hero(s)
	var o := _put(s, h)
	h.pos = AdventureMap.object_pos(o)
	var slot := 0
	while h.army.slots[slot].is_empty():
		slot += 1
	var c := String(h.army.slots[slot]["creature"])
	var total := h.army.total_creatures()
	assert_false(s.hamlet_station(o["id"], h.id, slot, 0)["ok"] and h.army.is_empty(), "a hero keeps a creature")
	if h.army.slots[slot].is_empty():
		return
	var have := int(h.army.slots[slot]["count"])
	assert_true(s.hamlet_station(o["id"], h.id, slot, 1)["ok"])
	assert_eq(o["garrison"], [[c, 1]])
	assert_eq(h.army.total_creatures(), total - 1)
	assert_eq(s.site_info(o["id"], h.id)["garrison"], [[c, 1]])
	assert_true(s.hamlet_withdraw(o["id"], h.id, 0)["ok"])
	assert_eq(o["garrison"], [])
	assert_eq(h.army.total_creatures(), total)
	assert_eq(int(h.army.slots[slot]["count"]), have)


# ----------------------------------------------------------------- battle --

func test_rival_must_beat_levy_and_stationed_troops() -> void:
	var s := _session()
	var h := _hero(s)
	var o := _put(s, h, "hamlet_croft", 1)
	var c := String(o["creature"])
	o["garrison"] = [[c, 3]]
	assert_true(s.is_guarded(o, 0), "a rival's levy defends")
	assert_false(s.is_guarded(o, 1), "never against its owner")
	assert_eq(MapSites.defenders(o, data), [[c, 3 + int(o["available"])]])
	# A failed attack leaves the survivors: stationed troops first, then the levy.
	var levy := int(o["available"])
	MapSites.set_survivors(o, [[c, 4]])
	assert_eq(o["garrison"], [[c, 3]])
	assert_eq(int(o["available"]), mini(levy, 1))
	# Beating them takes the hamlet, with nothing left to hire this week.
	o["available"] = levy
	o["idle_weeks"] = 2
	h.army = Army.from_pairs([[c, 400]])
	var r := s.attack(h.id, String(o["id"]))
	assert_eq(r["winner"], 0, str(r.get("outcome", "")))
	assert_eq([int(o["owner"]), o["garrison"], int(o["available"]), int(o["idle_weeks"])], [0, [], 0, 0])
	assert_eq(h.pos, AdventureMap.object_pos(o))
	# A hamlet without defenders is simply taken.
	o["owner"] = 1
	assert_false(s.is_guarded(o, 0))
	var visit := {"visited": [], "captured": []}
	s._enter_site(h, o, visit)
	assert_eq(int(o["owner"]), 0)
	assert_eq(visit["captured"], [o["id"]])


func test_hamlet_state_survives_a_save() -> void:
	var s := _session(3, true)
	var o: Dictionary = _hamlets_of(s)[0]
	o["owner"] = 0
	o["garrison"] = [[o["creature"], 2]]
	o["idle_weeks"] = 2
	var back := GameState.from_dict(s.state.to_dict(), data)
	var b: Dictionary = back.map.objects[o["id"]]
	assert_eq([b["owner"], b["garrison"], b["idle_weeks"], b["available"]], [0, o["garrison"], 2, o["available"]])
	assert_true(bool(back.rules.get("hamlets", false)))


# --------------------------------------------------------- interface and AI --

func test_new_game_setup_offers_hamlets_by_default_and_classic() -> void:
	var menu := MainMenu.new()
	menu.build(data)
	menu._show_setup()
	for i in menu._maps.size():
		if menu._maps[i]["generated"] and not menu._maps[i].get("scenario", false):
			menu._map_pick.select(i)
			break
	menu._fill_slots()
	assert_true(bool(menu.current_setup().get("hamlets", false)), "hamlets are the default")
	menu._hamlets_check.button_pressed = false
	assert_false(menu.current_setup().has("hamlets"), "unticked: a Classic game")
	assert_false(MainMenu._hamlets_offered({"id": "x", "scenario": true}))
	assert_false(MainMenu._hamlets_offered({"id": "custom:x", "custom": true}))
	menu.free()


func test_site_dialog_shows_a_held_hamlet() -> void:
	var s := _session()
	var h := _hero(s)
	var o := _put(s, h)
	h.pos = AdventureMap.object_pos(o)
	o["garrison"] = [[o["creature"], 2]]
	var dialog := SiteDialog.new()
	dialog.build(data, 620)
	dialog.open(s, String(o["id"]), h.id)
	assert_true(dialog.visible)
	var buttons := dialog.find_children("", "Button", true, false).map(func(b): return b.text)
	for word in ["Recruit", "Take back", "Station"]:
		assert_true(buttons.has(word), "%s in %s" % [word, buttons])
	dialog.free()


func test_ai_wants_hamlets_and_hires_a_restless_levy() -> void:
	var s := _session()
	var h := _hero(s)
	var o := _put(s, h)
	var ai := StrategicAI.new(s, 0)
	o["owner"] = -1
	var free_value := ai.site_value(h, o)
	assert_gt(free_value, 100.0 * 10.0, "worth at least its gold")
	o["owner"] = 1
	assert_between(ai.site_value(h, o), 1.0, free_value, "a rival's changes hands too easily to be worth as much")
	assert_gt(ai.defender_value(o), 0.0, "and its levy counts as its defence")
	# Our own, far from home and poor: only the levy that breeds unrest is hired.
	o["owner"] = 0
	o["available"] = 12
	var week := MapSites.weekly_growth(o, data)
	var bank: ResourceBank = s.state.player(0)["resources"]
	bank.spend({"gold": bank.get_amount("gold")})
	bank.add("gold", 3000)
	assert_eq(ai._hamlet_hire(h, o), 0, "inside the realm the purse is kept for the towns")
	_with_radius(0, func():
		assert_eq(ai._hamlet_hire(h, o), 12 - week + 1)
		h.pos = AdventureMap.object_pos(o)
		ai._recruit_at_site(h, String(o["id"]))
		assert_eq(int(o["available"]), week - 1))
