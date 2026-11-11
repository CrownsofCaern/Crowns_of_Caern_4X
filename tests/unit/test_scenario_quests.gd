extends "res://tests/test_case.gd"


func _game() -> GameSession:
	return GameSession.new_game(data, "last_watch", 7, {}, {"random_events": false})


func test_quest_is_persistent_requires_carried_relic_and_rewards_once() -> void:
	var s := _game()
	var h := s.hero("hero_watch")
	h.pos = Vector2i(8, 6)
	assert_false(s.scenario_act(h.id, "site_pact", "accept")["ok"], "the envoy arrives in the second week")
	s.state.day = 9
	assert_true(s.scenario_act(h.id, "site_pact", "accept")["ok"])
	assert_eq(ScenarioQuests.status(s.state, "reedhaven_pact"), "active")
	assert_true(s.state.map.objects.has("site_pact"))
	assert_false(s.scenario_act(h.id, "site_pact", "deliver")["ok"])
	var item: Dictionary = s.state.map.objects["relic_oath"]
	assert_false(ScenarioQuests.collect(s, h, item), "the guardian must be defeated")
	s.state.map.remove_object("guardian_oath")
	assert_true(ScenarioQuests.collect(s, h, item))
	assert_true(s.scenario_act(h.id, "site_pact", "deliver")["ok"])
	assert_eq(ScenarioQuests.status(s.state, "reedhaven_pact"), "complete")
	assert_true(s.allied(0, 2))
	assert_eq(int(s.town("town_reedhaven")["owner"]), 2)
	assert_true(s.hero("hero_reedwarden") != null)
	assert_true(WaveDirector.has_order(s.state, "hero_reedwarden"))
	assert_false(s.scenario_act(h.id, "site_pact", "deliver")["ok"])
	assert_true(ScenarioQuests.items(s.state, h.id).is_empty())


func test_relic_can_be_transferred_and_saved_without_pack_space() -> void:
	var s := _game()
	var a := s.hero("hero_watch")
	var b := s.hero("hero_scout")
	s.state.map.remove_object("guardian_oath")
	ScenarioQuests.collect(s, a, s.state.map.objects["relic_oath"])
	assert_true(s.transfer_quest_item(a.id, b.id, "reed_oathstone")["ok"])
	assert_true(ScenarioQuests.items(s.state, a.id).is_empty())
	var back := GameSession.from_state(data, GameState.from_dict(JSON.parse_string(JSON.stringify(s.state.to_dict())), data))
	assert_eq(ScenarioQuests.items(back.state, b.id), ["reed_oathstone"])
	assert_false(back.transfer_quest_item(a.id, b.id, "reed_oathstone")["ok"])
	b = back.hero(b.id)
	b.pos = Vector2i(30, 30)
	assert_false(back.transfer_quest_item(b.id, a.id, "reed_oathstone")["ok"])


func test_fallen_hero_drops_relic_for_recovery() -> void:
	var s := _game()
	var h := s.hero("hero_watch")
	s.state.map.remove_object("guardian_oath")
	ScenarioQuests.collect(s, h, s.state.map.objects["relic_oath"])
	s._fall(h, null)
	assert_true(ScenarioQuests.items(s.state, h.id).is_empty())
	var drops: Array = s.state.map.objects.values().filter(func(o): return o["type"] == "quest_item")
	assert_eq(drops.size(), 1)
	assert_eq(drops[0]["item"], "reed_oathstone")
	assert_true(s.state.map.is_passable(AdventureMap.object_pos(drops[0])))


func test_seal_overrides_road_and_delays_but_does_not_stop_invaders() -> void:
	var s := _game()
	var h := s.hero("hero_watch")
	var nest: Dictionary = s.state.map.objects["site_nest"]
	h.pos = AdventureMap.object_pos(nest)
	assert_false(s.scenario_act(h.id, "site_nest", "seal")["ok"], "clear the guard first")
	nest.erase("guard")
	var entry := Vector2i(47, 6)
	var castle := Vector2i(6, 18)
	var before := AiDistanceField.build(s.state.map, entry, {}).cost_to(castle)
	assert_eq(ScenarioQuests.seal_reason(s, nest), "")
	assert_true(s.scenario_act(h.id, "site_nest", "seal")["ok"])
	assert_true(s.state.map.has_road(Vector2i(23, 12)))
	assert_false(s.state.map.is_passable(Vector2i(23, 12)), "a road must not reopen a sealed tunnel")
	var after := AiDistanceField.build(s.state.map, entry, {}).cost_to(castle)
	assert_gt(after, before + 1000, "sealing buys a meaningful travel delay")
	assert_false(s.pathfinder.find_path(entry, castle).is_empty())
	assert_false(s.scenario_act(h.id, "site_nest", "seal")["ok"])
	var back := GameSession.from_state(data, GameState.from_dict(JSON.parse_string(JSON.stringify(s.state.to_dict())), data))
	assert_false(back.state.map.is_passable(Vector2i(23, 12)))
	assert_eq(AiDistanceField.build(back.state.map, entry, {}).cost_to(castle), after)


func test_seal_refuses_to_cut_the_only_route() -> void:
	var s := _game()
	# Close the eastern bypass; sealing the north gate would strand an entry.
	var barrier := {"id": "test_barrier", "type": "gate", "pos": [40, 18], "closed": true}
	s.state.map.add_object(barrier)
	assert_ne(ScenarioQuests.seal_reason(s, s.state.map.objects["site_nest"]), "")
	assert_false(s.state.map.objects["tunnel_north"]["closed"], "validation must not mutate the gate")


func test_support_changes_future_waves_and_weekly_reinforcements() -> void:
	var s := _game()
	var h := s.hero("hero_watch")
	s.state.day = 9 # The forge and the watch open in the second week.
	for id in ["site_camp", "site_forge", "site_watch"]:
		var site: Dictionary = s.state.map.objects[id]
		site.erase("guard")
		h.pos = AdventureMap.object_pos(site)
		assert_true(s.scenario_act(h.id, id, "claim")["ok"])
		assert_false(s.scenario_act(h.id, id, "claim")["ok"])
	s.state.day = 2
	WaveDirector.on_day(s)
	assert_true(s.state.scenario_runtime["warned"].has("watch_wave_0"), "watchtower gives earlier warnings")
	s.state.day = 7
	WaveDirector.on_day(s)
	var wave: Dictionary = ScenarioRules.definition(s.state)["waves"][0]
	var count := s.hero("watch_commander_0").army.total_creatures()
	var original := 0
	for pair in wave["hero"]["army"]:
		original += int(pair[1])
	assert_lt(count, original)
	var before := Town.garrison(s.town("town_last_watch")).total_creatures()
	s.state.day = 8
	WaveDirector.on_day(s)
	assert_eq(Town.garrison(s.town("town_last_watch")).total_creatures(), before + 8)


func test_weekly_support_is_idempotent_and_stops_when_ally_is_lost() -> void:
	var s := _game()
	var h := s.hero("hero_watch")
	h.pos = Vector2i(8, 6)
	s.state.day = 9
	s.scenario_act(h.id, "site_pact", "accept")
	s.state.map.remove_object("guardian_oath")
	ScenarioQuests.collect(s, h, s.state.map.objects["relic_oath"])
	s.scenario_act(h.id, "site_pact", "deliver")
	var save: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict()))
	s = GameSession.from_state(data, GameState.from_dict(save, data))
	assert_false(WaveDirector.reserved_player(s.state, 2), "activated allies stay active after reload")
	s.state.day = 8
	WaveDirector.on_day(s)
	var count := Town.garrison(s.town("town_last_watch")).total_creatures()
	WaveDirector.on_day(s)
	assert_eq(Town.garrison(s.town("town_last_watch")).total_creatures(), count)
	s.town("town_reedhaven")["owner"] = 1
	s.hero("hero_reedwarden").alive = false
	VictoryRules.update(s)
	assert_true(s.state.player(2)["defeated"])
	s.state.day = 15
	WaveDirector.on_day(s)
	assert_eq(Town.garrison(s.town("town_last_watch")).total_creatures(), count)
