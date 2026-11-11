extends "res://tests/test_case.gd"


func test_mana_recovers_slowly_and_survives_save() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	var h := s.hero("hero_wren")
	assert_eq(h.mana, h.max_mana(data))
	h.mana = 0
	var loaded := GameSession.from_state(data, GameState.from_dict(s.state.to_dict(), data))
	assert_eq(loaded.hero(h.id).mana, 0)
	loaded._start_new_day()
	assert_eq(loaded.hero(h.id).mana, int(data.rules["mana_daily_regen"]))
	h.restore_mana(10000, data)
	assert_eq(h.mana, h.max_mana(data))


func test_old_save_heroes_start_with_full_mana() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	var saved := s.state.to_dict()
	saved["version"] = 12
	for id in saved["heroes"]:
		saved["heroes"][id].erase("mana")
	var loaded := GameState.from_dict(saved, data)
	var h: Hero = loaded.heroes["hero_wren"]
	assert_eq(h.mana, h.max_mana(data))


func test_class_spell_casting_and_save() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	var h := s.hero("hero_wren")
	assert_true(h.known_spells(data).is_empty())
	h.add_xp(int(data.progression["xp_thresholds"][1]), data)
	var id := h.known_spells(data)[0]
	assert_eq(data.magic["spells"][id]["source"], "class")
	h.movement_left = 0
	var before := h.mana
	assert_true(s.cast_spell(h.id, id)["ok"])
	assert_eq(h.mana, before - int(data.magic["spells"][id]["cost"]))
	var loaded := GameSession.from_state(data, GameState.from_dict(s.state.to_dict(), data))
	assert_eq(loaded.hero(h.id).mana, h.mana)
	assert_eq(loaded.hero(h.id).battle_spell_damage, h.battle_spell_damage)
	h.mana = 0
	assert_eq(s.can_cast_spell(h.id, id), "not enough mana")
	assert_false(s.cast_spell(h.id, id)["ok"])
	assert_eq(h.mana, 0)


func test_crypt_teaches_a_rare_spell_once() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	var h := s.hero("hero_wren")
	var crypt := {"id": "crypt", "type": "site", "site": "spell_crypt", "spell": "swiftwind"}
	MapSites.normalize(crypt, data)
	assert_true(MapSites.visit(h, crypt, 1, data)["applied"])
	assert_true(h.known_spells(data).has("swiftwind"))
	assert_false(MapSites.visit(h, crypt, 1, data)["applied"])
	var restored := Hero.from_dict(h.to_dict())
	assert_true(restored.known_spells(data).has("swiftwind"))


func test_mana_tide_adds_daily_regeneration() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	var h := s.hero("hero_wren")
	h.mana = 0
	s.state.omen = {"id": "mana_tide", "week": 1}
	s._start_new_day()
	assert_eq(h.mana, int(data.rules["mana_daily_regen"]) + 2)


func test_town_teleports_require_owned_unoccupied_destinations() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	var h := s.hero("hero_wren")
	var origin := s.town("town_greyhold")
	var other := s.town("town_cindermaw")
	other["owner"] = h.owner
	h.spells.append_array(["homeward", "town_gate"])
	h.mana = h.max_mana(data)
	h.pos = AdventureMap.object_pos(origin)
	assert_true(s.cast_spell(h.id, "town_gate", "town_cindermaw")["ok"])
	assert_eq(h.pos, AdventureMap.object_pos(other))
	h.mana = h.max_mana(data)
	assert_true(s.cast_spell(h.id, "homeward")["ok"])
	assert_eq(h.pos, AdventureMap.object_pos(origin))
	other["owner"] = 1
	var mana_before := h.mana
	assert_false(s.cast_spell(h.id, "town_gate", "town_cindermaw")["ok"])
	assert_eq(h.mana, mana_before)


func test_guarded_crypt_armies_use_high_tier_creatures() -> void:
	var generator := MapGenerator.new(data)
	generator.rng = GameRng.new(37)
	for i in 20:
		var army := generator._roll_army(10000, "grass", 4)
		for stack in army["stacks"]:
			assert_true(int(data.creature(stack[0])["tier"]) >= 4)


func test_battle_spell_appears_in_forecast_and_is_consumed() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var h := s.hero("hero_wren")
	h.spells.append("warfire")
	h.mana = h.max_mana(data)
	h.army = Army.from_pairs([["shieldwarden", 60], ["longbowman", 80]])
	h.pos = Vector2i(6, 15)
	assert_true(s.cast_spell(h.id, "warfire")["ok"])
	var setup := s.battle_setup(h.id, "mine_mercury")
	var mods: Dictionary = setup["sides"][0]["hero"]["mods"]
	assert_true(float(mods["melee_damage_pct"]) >= 0.2)
	assert_true(h.battle_spell_damage > 0.0, "forecast does not consume spell")
	s.attack(h.id, "mine_mercury")
	assert_eq(h.battle_spell_damage, 0.0)


func test_spell_screen_handles_known_spells() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	var h := s.hero("hero_wren")
	h.spells.append_array(["town_gate", "swiftwind"])
	var screen := HeroScreen.new()
	screen.build(data)
	screen.session = s
	screen.hero_id = h.id
	screen.refresh()
	screen.free()


func test_version_13_save_gets_mana_and_preserves_battle_orders() -> void:
	var s := GameSession.new_game(data, "ember_ford", 11)
	var saved := s.state.to_dict()
	saved["version"] = 13
	for id in saved["heroes"]:
		saved["heroes"][id].erase("mana")
		saved["heroes"][id].erase("home_town")
	var h: Hero = GameState.from_dict(saved, data).heroes["hero_wren"]
	assert_eq(h.mana, h.max_mana(data))
	assert_ne(h.home_town, "")
	assert_eq(h.orders, s.hero("hero_wren").orders)
