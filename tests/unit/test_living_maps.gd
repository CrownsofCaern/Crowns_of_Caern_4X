extends "res://tests/test_case.gd"
## Living maps: the faction map mechanics (data/faction_mechanics.json,
## FactionMechanics), the new encounters, site kinds (watchtower, drill,
## mana_well) and map-wide omens (plague, roaming horrors, spoils).


func _session(seed_value: int = 3) -> GameSession:
	return GameSession.new_game(data, "twin_marches", seed_value)


func _mines(s: GameSession) -> Array:
	var out := []
	var ids := s.state.map.objects.keys()
	ids.sort()
	for id in ids:
		if s.state.map.objects[id]["type"] == "mine":
			out.append(s.state.map.objects[id])
	return out


func _set_terrain(s: GameSession, p: Vector2i, terrain: String) -> void:
	s.state.map.terrain[s.state.map.index(p)] = terrain


## Puts a site on a free tile next to the hero and returns it.
func _put_site(s: GameSession, h: Hero, site_id: String) -> Dictionary:
	var p := s._free_tile_near(h.pos)
	var o := {"id": "test_site_%s" % site_id, "type": "site", "site": site_id, "pos": [p.x, p.y]}
	s.state.map.add_object(o)
	MapSites.normalize(o, data)
	return o


func _force_omen(s: GameSession, id: String) -> void:
	s.state.omen = {"id": id, "week": s.state.week()}


# --------------------------------------------------------------- mechanics --

func test_every_town_faction_has_its_own_mechanic() -> void:
	var errors := FactionMechanics.validate(data)
	assert_true(errors.is_empty(), "\n".join(errors))
	var seen := {}
	for fid in data.town_types:
		var m := FactionMechanics.mechanic(fid, data)
		assert_true(FactionMechanics.MECHANICS.has(m), "%s has a mechanic" % fid)
		assert_false(seen.has(m), "%s shares %s" % [fid, m])
		seen[m] = true
		assert_ne(FactionMechanics.describe(fid, data), "")
	assert_eq(seen.size(), FactionMechanics.MECHANICS.size(), "every mechanic is used")


func test_validation_catches_bad_mechanics() -> void:
	var saved: Dictionary = data.faction_mechanics.duplicate(true)
	data.faction_mechanics["hollow"]["creature"] = "pike_militia"
	data.faction_mechanics["forge"]["mechanic"] = "tunnelling"
	data.faction_mechanics["fishmen"]["pct"] = 3.0
	data.faction_mechanics.erase("concord")
	var text := "\n".join(FactionMechanics.validate(data))
	data.faction_mechanics = saved
	for word in ["hollow", "tunnelling", "fishmen", "concord"]:
		assert_true(text.contains(word), "%s reported:\n%s" % [word, text])


func test_wildwalk_makes_forest_nearly_open_ground() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	h.faction = "concord"
	var plain := Pathfinder.adjusted_cost(150, "forest", false, h.move_cost_mods(data))
	h.faction = "thornwood"
	var wild := Pathfinder.adjusted_cost(150, "forest", false, h.move_cost_mods(data))
	assert_lt(wild, plain)
	assert_between(wild, 100, 110, "forest costs about as much as grass")
	assert_lt(Pathfinder.adjusted_cost(175, "swamp", false, h.move_cost_mods(data)), 175)


func test_tidebound_hero_by_the_water_moves_farther() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	h.faction = "fishmen"
	var base := h.max_movement(data)
	_set_terrain(s, h.pos, "grass")
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := h.pos + Vector2i(dx, dy)
			if s.state.map.in_bounds(q) and q != h.pos and s.state.map.terrain_at(q) in ["water", "river", "swamp"]:
				_set_terrain(s, q, "grass")
	FactionMechanics.on_day_start(s.state, data, [h])
	assert_false(h.has_boon(FactionMechanics.TIDE_SOURCE), "dry land: no tide")
	_set_terrain(s, h.pos + Vector2i(1, 0), "water")
	FactionMechanics.on_day_start(s.state, data, [h])
	assert_true(h.has_boon(FactionMechanics.TIDE_SOURCE))
	assert_gt(h.max_movement(data), base)
	h.expire_boons(s.state.day + 1)
	assert_false(h.has_boon(FactionMechanics.TIDE_SOURCE), "lasts one day")
	h.faction = "concord"
	FactionMechanics.on_day_start(s.state, data, [h])
	assert_false(h.has_boon(FactionMechanics.TIDE_SOURCE), "only the Shoal rides the tide")


func test_whisper_web_watches_mines_and_enemy_heroes() -> void:
	var s := _session()
	s.state.player(0)["faction"] = "darkelf"
	var fog: FogOfWar = s.state.player(0)["fog"]
	var far := {}
	for m in _mines(s):
		if not fog.is_explored(AdventureMap.object_pos(m)):
			far = m
			break
	assert_false(far.is_empty(), "an unseen mine")
	far["owner"] = 0
	var enemy: Hero = s.hero("hero_east")
	s.state.day = 8   # first day of week 2
	assert_eq(s.state.day_of_week(), 1)
	var seen := FactionMechanics.on_day_vision(s.state, data, s.allied)
	assert_gt(float(seen.get(0, 0)), 0.0)
	assert_true(fog.is_explored(AdventureMap.object_pos(far)), "the mine watches its land")
	assert_true(fog.is_explored(enemy.pos), "informants report the enemy hero")


func test_levy_of_the_shires_musters_recruits_per_mine() -> void:
	var s := _session()
	s.state.player(0)["faction"] = "concord"
	var t: Dictionary = s.towns_of(0)[0]
	var c := FactionMechanics.levy_creature(t, data)
	assert_ne(c, "", "the town has a tier-1 dwelling")
	for m in _mines(s):
		if int(m["owner"]) == 0:
			m["owner"] = -1
	var mines := _mines(s).slice(0, 3)
	for m in mines:
		m["owner"] = 0
	var before := int(t.get("available", {}).get(c, 0))
	var added := FactionMechanics.on_week_growth(s.state, data)
	var per := int(data.faction_mechanics["concord"]["per_mine"])
	assert_eq(int(added[t["id"]]), mini(per * 3, int(data.faction_mechanics["concord"]["max_per_town"])))
	assert_eq(int(t["available"][c]), before + int(added[t["id"]]))
	s.state.player(0)["faction"] = "ashen"
	assert_true(FactionMechanics.on_week_growth(s.state, data).is_empty(), "only the Concord levies")


func test_brand_and_plunder_pays_on_capture() -> void:
	var s := _session()
	s.state.player(0)["faction"] = "ashen"
	var m: Dictionary = {}
	for o in _mines(s):
		if int(o["owner"]) < 0:
			m = o
			break
	var res := String(m["resource"])
	var bank: ResourceBank = s.state.player(0)["resources"]
	var before := bank.get_amount(res)
	s._capture(m, 0)
	assert_eq(bank.get_amount(res) - before, Economy.mine_income(m, data) * int(data.faction_mechanics["ashen"]["mine_days"]))
	before = bank.get_amount(res)
	s._capture(m, 0)
	assert_eq(bank.get_amount(res), before, "taking your own mine pays nothing")
	s.state.player(1)["faction"] = "concord"
	var other: ResourceBank = s.state.player(1)["resources"]
	before = other.get_amount(res)
	s._capture(m, 1)
	assert_eq(other.get_amount(res), before, "only the Ashen Host plunders")


func test_grave_harvest_raises_the_living_slain() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	h.faction = "hollow"
	var cid := String(data.faction_mechanics["hollow"]["creature"])
	var pct := float(data.faction_mechanics["hollow"]["pct"])
	var slain := [{"creature": "pike_militia", "lost": 90}, {"creature": "shambler", "lost": 50}]
	var expected := int(floor(90.0 * float(data.creature("pike_militia")["hp"]) * pct / float(data.creature(cid)["hp"])))
	assert_gt(float(expected), 0.0)
	assert_eq(FactionMechanics.harvest_count(slain, "hollow", data), expected, "the undead do not rise twice")
	h.army = Army.new()
	h.army.add("marrow_archer", 5)
	var lines := FactionMechanics.after_victory(h, slain, s.state, data)
	assert_eq(lines.size(), 1)
	var raised := 0
	for st in h.army.slots:
		if not st.is_empty() and st["creature"] == cid:
			raised += int(st["count"])
	assert_eq(raised, expected)
	assert_eq(FactionMechanics.harvest_count(slain, "concord", data), 0)


func test_feast_of_victory_once_a_day() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	h.faction = "frostmarch"
	h.movement_left = 0
	FactionMechanics.after_victory(h, [], s.state, data)
	assert_eq(h.movement_left, int(round(h.max_movement(data) * float(data.faction_mechanics["frostmarch"]["pct"]))))
	var after_first := h.movement_left
	FactionMechanics.after_victory(h, [], s.state, data)
	assert_eq(h.movement_left, after_first, "only the first victory of the day")
	h.expire_boons(s.state.day + 1)
	assert_false(h.has_boon(FactionMechanics.FEAST_SOURCE), "a new day, a new feast")


func test_deep_roads_link_mines_and_towns() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	var mines := _mines(s)
	var a: Dictionary = mines[0]
	var b: Dictionary = mines[mines.size() - 1]
	a["owner"] = 0
	b["owner"] = 0
	h.pos = s._free_tile_near(AdventureMap.object_pos(a))
	h.movement_left = h.max_movement(data)
	h.faction = "concord"
	assert_ne(s.can_deep_road(h.id, b["id"]), "", "only the Forgeborn")
	h.faction = "forge"
	assert_eq(s.can_deep_road(h.id, b["id"]), "")
	var dests := s.deep_road_destinations(h.id)
	assert_true(dests.any(func(d): return d["id"] == b["id"]))
	assert_false(dests.any(func(d): return d["id"] == a["id"]), "not back to where it stands")
	var r := s.deep_road(h.id, b["id"])
	assert_true(r["ok"], str(r))
	var d := h.pos - AdventureMap.object_pos(b)
	assert_true(maxi(absi(d.x), absi(d.y)) <= 1, "comes up at the mine")
	assert_eq(h.movement_left, 0, "spends the day")
	h.movement_left = h.max_movement(data) / 4
	assert_ne(s.can_deep_road(h.id, a["id"]), "", "needs half a day's movement")
	h.movement_left = h.max_movement(data)
	b["owner"] = 1
	h.pos = s._free_tile_near(AdventureMap.object_pos(b))
	assert_ne(s.can_deep_road(h.id, a["id"]), "", "must start by one of your own holdings")


func test_ai_values_its_faction_mechanic() -> void:
	var s := _session()
	var ai := StrategicAI.new(s, 0)
	var m: Dictionary = {}
	for o in _mines(s):
		if int(o["owner"]) < 0:
			m = o
			break
	s.state.player(0)["faction"] = "thornwood"
	assert_eq(ai.faction_capture_bonus(m), 0.0)
	s.state.player(0)["faction"] = "ashen"
	assert_gt(ai.faction_capture_bonus(m), 0.0, "plunder makes mines worth more")
	s.state.player(0)["faction"] = "concord"
	assert_gt(ai.faction_capture_bonus(m), 0.0, "so does the levy")
	var h: Hero = s.hero("hero_west")
	var beasts := {"type": "neutral_army", "stacks": [["thornwolf", 20]]}
	h.faction = "concord"
	assert_eq(ai.harvest_value(h, beasts), 0.0)
	h.faction = "hollow"
	assert_gt(ai.harvest_value(h, beasts), 0.0)


func test_forge_ai_tunnels_toward_a_far_goal() -> void:
	var s := GameSession.new_game(data, "gen:twin_marches:3", 3)   # big enough for a long walk
	var ai := StrategicAI.new(s, 0)
	var h: Hero = s._heroes_sorted(0)[0]
	h.faction = "forge"
	var mines := _mines(s)
	var near: Dictionary = {}
	var far: Dictionary = {}
	for m in mines:
		var dist := (AdventureMap.object_pos(m) - h.pos).length()
		if near.is_empty() or dist < (AdventureMap.object_pos(near) - h.pos).length():
			near = m
		if far.is_empty() or dist > (AdventureMap.object_pos(far) - h.pos).length():
			far = m
	near["owner"] = 0
	far["owner"] = 0
	h.pos = s._free_tile_near(AdventureMap.object_pos(near))
	h.movement_left = h.max_movement(data)
	var goal := AdventureMap.object_pos(far) + Vector2i(1, 1)
	assert_true(ai._take_deep_road(h, goal), "a long walk becomes a tunnel")
	var d := h.pos - AdventureMap.object_pos(far)
	assert_true(maxi(absi(d.x), absi(d.y)) <= 1)
	h.movement_left = h.max_movement(data)
	assert_false(ai._take_deep_road(h, goal + Vector2i(1, 0)), "no tunnel for a short walk")


# --------------------------------------------------------------- encounters --

func test_encounters_tripled_and_every_faction_has_a_way_in() -> void:
	assert_eq(data.validate_encounters(), [] as Array[String])
	assert_true(data.encounters.size() >= 39, "about three times the first 13: %d" % data.encounters.size())
	var factions := {}
	for eid in data.encounters:
		for c in data.encounters[eid]["choices"]:
			for f in c.get("requires", {}).get("faction", []):
				factions[f] = true
			for sub in c.get("requires", {}).get("any", []):
				for f in sub.get("faction", []):
					factions[f] = true
	for fid in data.town_types:
		assert_true(factions.has(fid), "%s has an encounter choice of its own" % fid)
	var risk: Dictionary = data.map_templates["encounter_risk"]
	for eid in data.encounters:
		assert_true((risk["low"] as Array).has(eid) or (risk["high"] as Array).has(eid), "%s can be generated" % eid)


func test_encounter_sprites_fall_back_to_their_own() -> void:
	assert_eq(EncounterSystem.sprite_id("ember_rift", data), "encounter_ember_rift")
	assert_eq(EncounterSystem.sprite_id("bitter_well", data), "encounter_bitter_well")
	# An encounter may still borrow another sprite by declaring one.
	var def: Dictionary = data.encounters["bitter_well"]
	def["sprite"] = "encounter_ember_rift"
	assert_eq(EncounterSystem.sprite_id("bitter_well", data), "encounter_ember_rift")
	def.erase("sprite")


func test_new_encounter_effects_apply() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	var p := s._free_tile_near(h.pos)
	s.state.map.add_object({"id": "enc_test", "type": "encounter", "pos": [p.x, p.y], "encounter": "weeping_spring"})
	h.mana = 0
	var r := s.resolve_encounter(h.id, "enc_test", 0)
	assert_true(r["ok"])
	assert_eq(h.mana, mini(20, h.max_mana(data)), "drinking restores mana")
	p = s._free_tile_near(h.pos)
	s.state.map.add_object({"id": "enc_drill", "type": "encounter", "pos": [p.x, p.y], "encounter": "old_drillmaster"})
	s.state.player(0)["resources"].add("gold", 5000)
	h.movement_left = h.max_movement(data)
	h.army = Army.new()
	h.army.add("pike_militia", 30)
	h.army.initialize_veterans(data)
	r = s.resolve_encounter(h.id, "enc_drill", 0)
	assert_true(r["ok"], str(r))
	assert_eq(int(h.army.slots[0]["veteran_xp"]), 800)
	p = s._free_tile_near(h.pos)
	s.state.map.add_object({"id": "enc_salt", "type": "encounter", "pos": [p.x, p.y], "encounter": "stranded_salt_caravan"})
	var base := h.max_movement(data)
	r = s.resolve_encounter(h.id, "enc_salt", 0)
	assert_true(r["ok"], str(r))
	assert_true(h.has_boon("encounter_stranded_salt_caravan"))
	assert_gt(h.max_movement(data), base)


func test_ai_values_new_effects() -> void:
	var s := _session()
	var ai := StrategicAI.new(s, 0)
	var h: Hero = s.hero("hero_west")
	assert_gt(ai._effects_value(h, [{"type": "boon", "mods": {"attack": 1}, "days": 7}]), 0.0)
	assert_gt(ai._effects_value(h, [{"type": "mana", "amount": 10}]), 0.0)
	assert_gt(ai._effects_value(h, [{"type": "veteran_xp", "amount": 800}]), 0.0)


# ------------------------------------------------------------------- sites --

func test_watchtower_reveals_once_per_player() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "watchfire_ruin")
	var fog: FogOfWar = s.state.player(0)["fog"]
	var radius := int(data.sites["watchfire_ruin"]["radius"])
	var edge := AdventureMap.object_pos(o) + Vector2i(radius - 1, 0)
	edge.x = mini(edge.x, s.state.map.width - 1)
	var r := s.move_hero(h.id, AdventureMap.object_pos(o))
	assert_eq(r["visited"].size(), 1)
	assert_true(fog.is_explored(edge), "the land around lies open")
	assert_ne(MapSites.visit_block(h, o, data, s.state.day), "", "once per player")


func test_mana_well_refills_once_a_week() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "wellspring_wound")
	h.mana = 0
	assert_eq(MapSites.visit_block(h, o, data, s.state.day), "")
	var r := MapSites.visit(h, o, s.state.day, data)
	assert_true(r["applied"])
	assert_eq(h.mana, h.max_mana(data))
	h.mana = 0
	assert_ne(MapSites.visit_block(h, o, data, s.state.day), "", "drawn this week")
	assert_eq(MapSites.visit_block(h, o, data, s.state.day + 7), "", "again next week")


func test_drill_ground_trains_the_army_once() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	var o := _put_site(s, h, "muster_field")
	h.army = Army.new()
	h.army.add("pike_militia", 30)
	h.army.initialize_veterans(data)
	var before := int(h.army.slots[0]["veteran_xp"])
	var r := MapSites.visit(h, o, s.state.day, data)
	assert_true(r["applied"])
	assert_eq(int(h.army.slots[0]["veteran_xp"]), mini(Army.VETERAN_THRESHOLDS[4], before + int(data.sites["muster_field"]["veteran_xp"])))
	assert_ne(MapSites.visit_block(h, o, data, s.state.day), "", "once per hero")


func test_generator_places_the_new_site_kinds() -> void:
	var kinds := {}
	for seed_value in range(1, 13):
		var def := MapGenerator.generate(data, "twin_marches", seed_value)
		for o in def["objects"]:
			if o["type"] == "site":
				kinds[String(data.sites[o["site"]]["kind"])] = true
	for k in ["watchtower", "drill", "mana_well"]:
		assert_true(kinds.has(k), "%s placed on some generated map" % k)


func test_generated_maps_carry_more_encounters() -> void:
	var def := MapGenerator.generate(data, "twin_marches", 4)
	var n := 0
	var kinds := {}
	for o in def["objects"]:
		if o["type"] == "encounter":
			n += 1
			kinds[o["encounter"]] = true
	assert_true(n >= 10, "%d encounters" % n)
	assert_true(kinds.size() >= 6, "varied encounters: %d kinds" % kinds.size())


# ------------------------------------------------------------------ omens --

func test_plague_spares_the_unliving_and_the_last_creature() -> void:
	var s := _session()
	var h: Hero = s.hero("hero_west")
	h.army = Army.new()
	h.army.add("pike_militia", 100)
	h.army.add("shambler", 100)
	_force_omen(s, "plague_week")
	var news := WorldEvents.apply_plague(s.state, data, [h])
	assert_eq((news.get(0, []) as Array).size(), 1)
	var counts := {}
	for st in h.army.slots:
		if not st.is_empty():
			counts[st["creature"]] = int(st["count"])
	assert_lt(float(counts["pike_militia"]), 100.0, "the living sicken")
	assert_eq(int(counts["shambler"]), 100, "the dead do not")
	h.army = Army.new()
	h.army.add("pike_militia", 1)
	WorldEvents.apply_plague(s.state, data, [h])
	assert_eq(h.army.total_creatures(), 1)
	s.state.omen = {}
	assert_true(WorldEvents.apply_plague(s.state, data, [h]).is_empty(), "no plague without the omen")


func test_hunters_moon_raises_spoils() -> void:
	var s := _session()
	assert_eq(WorldEvents.spoils_bonus(s.state, data), 0.0)
	_force_omen(s, "hunters_moon")
	assert_gt(WorldEvents.spoils_bonus(s.state, data), 0.0)


func test_roaming_horror_rises_far_away_and_hunts_a_town() -> void:
	var s := _session(5)
	s.state.day = 8
	_force_omen(s, "roaming_horror")
	var spawned := RoamingThreats.on_week(s)
	assert_eq(spawned.size(), 1)
	var o: Dictionary = spawned[0]
	assert_true(bool(o["roamer"]))
	var start := AdventureMap.object_pos(o)
	for t in s.towns_of(0) + s.towns_of(1):
		var d := start - AdventureMap.object_pos(t)
		assert_true(maxi(absi(d.x), absi(d.y)) >= RoamingThreats.MIN_TOWN_DISTANCE, "rises far from towns")
	var target := RoamingThreats.target_town(s, o)
	assert_false(target.is_empty())
	var goal := AdventureMap.object_pos(target)
	var before := s.pathfinder.find_path(start, goal).size()
	assert_gt(float(before), 0.0, "the town can be reached")
	RoamingThreats.on_day(s)
	if s.state.map.objects.has(o["id"]):
		var after := s.pathfinder.find_path(AdventureMap.object_pos(o), goal).size()
		assert_lt(float(after), float(before), "it walks toward the town")


func test_roaming_horror_ravages_an_undefended_town() -> void:
	var s := _session(5)
	var t: Dictionary = s.towns_of(0)[0]
	for id in s.state.heroes:
		var hh: Hero = s.state.heroes[id]
		if hh.pos == AdventureMap.object_pos(t):
			hh.pos = s._free_tile_near(hh.pos + Vector2i(4, 4))
	var p := s._free_tile_near(AdventureMap.object_pos(t))
	var o := {"id": "roamer_test", "type": "neutral_army", "pos": [p.x, p.y], "name": "The Test Beast",
		"stacks": [["hill_giant", 2]], "roamer": true, "steps": 5, "bounty": {"gold": 100},
		"ravage": {"gold": 500, "pool_pct": 0.5}}
	s.state.map.add_object(o)
	var bank: ResourceBank = s.state.player(0)["resources"]
	var gold := bank.get_amount("gold")
	var news := RoamingThreats.on_day(s)
	assert_eq((news.get(0, []) as Array).size(), 1, str(news))
	assert_eq(bank.get_amount("gold"), gold - mini(500, gold))
	assert_false(s.state.map.objects.has("roamer_test"), "it leaves after the raid")


func test_beating_a_roamer_pays_its_bounty() -> void:
	var s := _session(5)
	var h: Hero = s.hero("hero_west")
	h.army = Army.new()
	h.army.add("iron_margrave", 20)
	var p := s._free_tile_near(h.pos)
	s.state.map.add_object({"id": "roamer_weak", "type": "neutral_army", "pos": [p.x, p.y], "name": "A Lame Wolf",
		"stacks": [["thornwolf", 1]], "roamer": true, "steps": 5, "bounty": {"gold": 1234, "gems": 2}, "ravage": {}})
	var bank: ResourceBank = s.state.player(0)["resources"]
	var gems := bank.get_amount("gems")
	var r := s.attack(h.id, "roamer_weak")
	assert_eq(int(r["winner"]), 0)
	assert_eq(bank.get_amount("gems"), gems + 2)
	var ai := StrategicAI.new(s, 0)
	assert_gt(ai.bundle_value(RoamingThreats.bounty({"roamer": true, "bounty": {"gold": 1000}})), 0.0)


func test_new_omens_validate() -> void:
	assert_true(WorldEvents.validate(data).is_empty(), "\n".join(WorldEvents.validate(data)))
	for id in ["plague_week", "roaming_horror", "hunters_moon"]:
		assert_true(data.world_events["weekly"].has(id), id)
