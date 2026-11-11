extends "res://tests/test_case.gd"
## Game flow: new-game setup, hero battles, sieges with defending heroes,
## victory and defeat, save slots.

## Long-running tests (whole AI games, balance sweeps, many generated maps):
## they run only with ./run_tests.sh --slow.
const SLOW := ["test_computer_duel_reaches_an_end"]

const SAVE_DIR := "user://test_saves"
## Upper bound for a computer-only duel on twin_marches. The test guards
## against stand-offs, not pace: the slowest seed ends near day 52, and
## balance changes routinely shift that by a week or two.
const DUEL_DAY_LIMIT := 90


func _duel(seed_value: int = 5) -> GameSession:
	# Mournfield with two players: slot 0 (Concord, human) and slot 1 (Ashen, computer).
	return GameSession.new_game(data, "mournfield", seed_value, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "ashen"},
		{"type": "closed", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})


func _strong(h: Hero) -> void:
	h.army = Army.from_pairs([["bastion_colossus", 30], ["lancer", 60], ["longbowman", 120]])


func _weak(h: Hero) -> void:
	h.army = Army.from_pairs([["pike_militia", 2]])


# ------------------------------------------------------------------ setup --

func test_rules_data_is_valid() -> void:
	assert_eq(data._validate_rules(), [] as Array[String])
	assert_gt(int(data.rules["town_loss_grace_days"]), 0)


func test_map_entries_for_story_maps_keep_their_slots() -> void:
	var mournfield := GameSetup.map_entry(data, "mournfield")
	var ember_ford := GameSetup.map_entry(data, "ember_ford")
	assert_eq(mournfield["slots"].size(), 4)
	assert_eq(ember_ford["slots"].size(), 1)
	assert_eq(GameSetup.map_id_for(mournfield, 9), "mournfield")
	assert_eq(GameSetup.map_id_for({"generated": true, "template": "crossing"}, 9), "gen:crossing:9")
	assert_eq(GameSetup.map_id_for(GameSetup.map_entry(data, "gen:crossing:3"), 9), "gen:crossing:9")
	var maps := GameSetup.available_maps(data)
	assert_true(GameSetup.playable_factions(data).has("ashen"))
	assert_true(GameSetup.playable_factions(data).has("concord"))
	assert_false(GameSetup.playable_factions(data).has("wilds"))
	var generated := maps.filter(func(m): return m["generated"])
	assert_false(generated.is_empty(), "procedural templates are offered")
	assert_true(String(generated[0]["id"]).begins_with("gen:"))
	# A generated map starts from the menu's id format.
	var s := GameSession.new_game(data, GameSetup.map_id_for(generated[0], 5), 5, GameSetup.default_setup(generated[0]))
	assert_eq(s.state.players.size(), generated[0]["slots"].size())


func test_setup_validation() -> void:
	var def := data.load_map("mournfield")
	var closed := []
	for i in 4:
		closed.append({"type": "closed", "faction": "concord"})
	assert_false(GameSetup.validate(def, {"players": closed}, data).is_empty(), "nobody plays")
	assert_false(GameSetup.validate(def, {"players": [{"type": "human", "faction": "wilds"}]}, data).is_empty(), "neutral faction")
	assert_false(GameSetup.validate(def, {"players": [{"type": "robot", "faction": "ashen"}]}, data).is_empty())
	assert_true(GameSetup.validate(def, GameSetup.default_setup(GameSetup.map_entry(data, "mournfield")), data).is_empty())


func test_setup_player_colors_survive_closed_slots() -> void:
	var setup := {"players": [
		{"type": "closed"}, {"type": "human", "color": "#4488d0"},
		{"type": "computer", "color": "#49a85a"}, {"type": "closed"}]}
	var s := GameSession.new_game(data, "mournfield", 3, setup)
	assert_eq(s.state.player(0)["color"], "#4488d0")
	assert_eq(s.state.player(1)["color"], "#49a85a")
	assert_false(GameSetup.validate(data.load_map("mournfield"), {"players": [{"color": "invalid"}]}, data).is_empty())


func test_closed_slots_are_removed_and_players_renumbered() -> void:
	var s := GameSession.new_game(data, "mournfield", 3, {"players": [
		{"type": "closed", "faction": "concord"}, {"type": "human", "faction": "ashen"},
		{"type": "computer", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
	assert_eq(s.state.players.size(), 2)
	assert_eq(s.state.player(0)["faction"], "ashen")
	assert_true(s.state.player(0)["is_human"])
	assert_false(s.state.player(1)["is_human"])
	assert_eq(s.hero("hero_gaul").owner, 0)
	assert_eq(s.hero("hero_ishra").owner, 1)
	assert_true(s.hero("hero_osric") == null, "a closed slot's heroes leave")
	var lantern := s.town("town_lanternholm")
	assert_eq(int(lantern["owner"]), -1, "a closed slot's town turns neutral")
	assert_false(Town.garrison(lantern).is_empty(), "and is guarded")
	assert_true(s.is_guarded(lantern, 0))
	assert_eq(s.towns_of(0).size(), 1)
	assert_eq(s.towns_of(1).size(), 1)


func test_faction_change_converts_town_and_heroes() -> void:
	var s := GameSession.new_game(data, "ember_ford", 3, {"players": [{"type": "human", "faction": "ashen"}]})
	var greyhold := s.town("town_greyhold")
	assert_eq(greyhold["town_type"], "ashen")
	assert_true(Town.has_building(greyhold, "a_hall"), "the new town type's starting buildings")
	assert_false(Town.has_building(greyhold, "c_hall"))
	assert_eq(s.state.player(0)["faction"], "ashen")
	var heroes := s.state.heroes_of(0)
	assert_eq(heroes.size(), 2)
	var old_value := 0.0
	var new_value := 0.0
	var def := data.load_map("ember_ford")
	for hd in def["heroes"]:
		for pair in hd["army"]:
			old_value += float(data.creature(pair[0])["cost"]["gold"]) * int(pair[1])
	for h in heroes:
		assert_eq(h.faction, "ashen", h.name)
		assert_true(h.id.begins_with("hire_ashen_"), "taken from the tavern pool: " + h.id)
		for st in h.army.to_combat_stacks():
			assert_eq(data.creature(st["creature"])["faction"], "ashen")
			new_value += float(data.creature(st["creature"])["cost"]["gold"]) * int(st["count"])
	assert_between(new_value / old_value, 0.85, 1.15, "armies keep their value")
	# The tavern does not offer a hero who is already on the map.
	assert_eq(s.hire_offer("town_greyhold")["id"], "hire_ashen_2")


func test_convert_stack_keeps_tier() -> void:
	var conv := GameSetup.convert_stack("lancer", 10, "ashen", data)
	assert_eq(int(data.creature(conv[0])["tier"]), 4)
	assert_eq(GameSetup.convert_stack("lancer", 10, "concord", data), ["lancer", 10])


func test_mournfield_every_start_reaches_every_town() -> void:
	var s := GameSession.new_game(data, "mournfield", 1)
	for id in ["hero_osric", "hero_gaul", "hero_ishra", "hero_hester"]:
		var h := s.hero(id)
		for t_id in ["town_lanternholm", "town_rimecairn", "town_sallowmoor", "town_pyrewatch", "town_mournfield"]:
			var t := s.town(t_id)
			if int(t["owner"]) == h.owner:
				continue
			var path := s.pathfinder.find_path(h.pos, AdventureMap.object_pos(t))
			assert_false(path.is_empty(), "%s -> %s" % [id, t_id])


# ---------------------------------------------------------- hero battles --

func test_hero_battle_in_the_open() -> void:
	var s := _duel()
	var a := s.hero("hero_osric")
	var foe := s.hero("hero_gaul")
	foe.pos = Vector2i(8, 4)
	a.pos = Vector2i(6, 4)
	var plan := s.plan_path(a.id, foe.pos)
	assert_false(plan["path"].is_empty(), "an enemy hero can be the destination")
	var r := s.move_hero(a.id, foe.pos)
	assert_eq(r["battle"], foe.id)
	assert_eq(s.battle_target(foe.id)["kind"], "hero")
	var pred := s.preview_battle(a.id, foe.id)
	assert_true(pred["defending_hero"])
	assert_eq(pred["enemy"]["hero"]["name"], foe.name)
	_strong(a)
	var res := s.attack(a.id, foe.id)
	assert_eq(res["winner"], 0)
	assert_false(foe.alive, "the beaten hero falls")
	assert_eq(a.pos, Vector2i(8, 4), "the victor takes the field")
	var base := int(round(res["hp_killed"][0] * float(data.combat["xp_per_enemy_hp_killed"])))
	assert_eq(res["xp_gained"], base + int(round(base * float(data.rules["hero_defeat_xp_bonus"]))))
	assert_eq(res["target_kind"], "hero")
	assert_false(s.state.game_over, "the Ashen Host still holds Pyrewatch")


func test_own_heroes_still_block() -> void:
	var s := _duel()
	var a := s.hero("hero_osric")
	var b := Hero.create({"id": "h2", "name": "Second", "class": "knight", "owner": 0, "pos": [8, 4],
		"army": [["pike_militia", 3]]}, data)
	s.state.heroes[b.id] = b
	assert_true(s.plan_path(a.id, b.pos)["path"].is_empty())


func test_defending_hero_wins_and_gains_experience() -> void:
	var s := _duel()
	var a := s.hero("hero_osric")
	var foe := s.hero("hero_gaul")
	foe.pos = Vector2i(8, 4)
	a.pos = Vector2i(7, 4)
	_weak(a)
	_strong(foe)
	var res := s.attack(a.id, foe.id)
	assert_eq(res["winner"], 1)
	assert_false(a.alive, "the attacker's army is gone")
	assert_true(foe.alive)
	assert_eq(foe.xp, res["defender_xp"])
	assert_eq(foe.pos, Vector2i(8, 4))


func test_siege_with_defending_hero_and_garrison() -> void:
	var s := _duel()
	var a := s.hero("hero_osric")
	var foe := s.hero("hero_gaul")
	var pyre := s.town("town_pyrewatch")
	var tp := AdventureMap.object_pos(pyre)
	foe.pos = tp
	Town.set_garrison(pyre, Army.from_pairs([["cinderling", 20]]))
	pyre["built"].append("a_trench")
	a.pos = tp + Vector2i(-1, 0)
	assert_true(s.is_guarded(pyre, 0))
	var r := s.move_hero(a.id, tp)
	assert_eq(r["battle"], "town_pyrewatch")
	assert_eq(s.battle_target(foe.id)["kind"], "town", "attacking the hero in a town is a siege")
	var setup := s.battle_setup(a.id, "town_pyrewatch")
	var def_side: Dictionary = setup["sides"][1]
	assert_eq(def_side["hero"]["name"], foe.name)
	assert_eq(int(def_side["hero"]["defense"]), foe.defense + Town.defense_bonus(pyre, data), "walls add to the hero")
	assert_eq(def_side["stacks"].size(), foe.army.stack_count() + 1)
	var garrison_slots: Array = def_side["stacks"].filter(func(st): return int(st["slot"]) >= GameSession.GARRISON_SLOT_OFFSET)
	assert_eq(garrison_slots.size(), 1)
	_strong(a)
	var res := s.attack(a.id, "town_pyrewatch")
	assert_eq(res["winner"], 0)
	assert_false(foe.alive)
	assert_eq(int(pyre["owner"]), 0)
	assert_true(Town.garrison(pyre).is_empty())
	assert_eq(a.pos, tp)


func test_failed_siege_splits_losses_between_hero_and_garrison() -> void:
	var s := _duel()
	var a := s.hero("hero_osric")
	var foe := s.hero("hero_gaul")
	var pyre := s.town("town_pyrewatch")
	foe.pos = AdventureMap.object_pos(pyre)
	Town.set_garrison(pyre, Army.from_pairs([["cinderling", 30]]))
	a.pos = foe.pos + Vector2i(-1, 0)
	a.army = Army.from_pairs([["lancer", 12]])
	var hero_before := foe.army.total_creatures()
	var res := s.attack(a.id, "town_pyrewatch")
	assert_eq(res["winner"], 1)
	assert_true(foe.alive)
	var hero_lost := 0
	var garrison_lost := 0
	for st in res["sides"][1]["stacks"]:
		if int(st["slot"]) >= GameSession.GARRISON_SLOT_OFFSET:
			garrison_lost += int(st["lost"])
		else:
			hero_lost += int(st["lost"])
	assert_eq(foe.army.total_creatures(), hero_before - hero_lost)
	assert_eq(Town.garrison(pyre).total_creatures(), 30 - garrison_lost)
	assert_eq(int(pyre["owner"]), 1)


# ------------------------------------------------------- victory, defeat --

func test_conquest_ends_the_game() -> void:
	var s := _duel()
	var a := s.hero("hero_osric")
	var foe := s.hero("hero_gaul")
	var pyre := s.town("town_pyrewatch")
	foe.pos = AdventureMap.object_pos(pyre)
	a.pos = foe.pos + Vector2i(-1, 0)
	_strong(a)
	var res := s.attack(a.id, "town_pyrewatch")
	assert_eq(res["winner"], 0)
	assert_true(s.state.game_over)
	assert_eq(s.state.winner, 0)
	assert_eq(s.state.end_reason, "conquest")
	assert_true(s.state.player(1)["defeated"])
	var result := s.game_result()
	assert_true(result["human_won"])
	assert_eq(result["title"], "Victory")
	assert_eq(result["standings"][0]["player"], 0)
	assert_eq(result["standings"][1]["eliminated_day"], 1)
	# Nothing moves after the end.
	s.end_turn()
	assert_eq(s.state.current_player, 0)


func test_losing_every_hero_and_town_is_defeat() -> void:
	var s := _duel()
	var mine := s.hero("hero_osric")
	var lantern := s.town("town_lanternholm")
	lantern["owner"] = 1
	_weak(mine)
	var foe := s.hero("hero_gaul")
	foe.pos = mine.pos + Vector2i(1, 0)
	_strong(foe)
	s.attack(mine.id, foe.id)
	assert_true(s.state.game_over)
	assert_eq(s.state.winner, 1)
	var result := s.game_result()
	assert_false(result["human_won"])
	assert_eq(result["title"], "Defeat")


func test_enemy_heroes_near_a_town_are_threats() -> void:
	var s := _duel()
	var lantern := s.town("town_lanternholm")
	var home := AdventureMap.object_pos(lantern)
	var foe := s.hero("hero_gaul")
	var fog: FogOfWar = s.state.player(0)["fog"]
	foe.pos = Vector2i(s.state.map.width - 1, s.state.map.height - 1)
	assert_true(s.town_threats(0).is_empty(), "a far or unseen hero is no threat")
	# Next to the town, in sight.
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		if s.state.map.in_bounds(home + d) and s.state.map.is_passable(home + d) and s.state.map.object_at(home + d).is_empty() \
				and s.state.hero_at(home + d) == null:
			foe.pos = home + d
			break
	fog.reveal(foe.pos, 1)
	var th := s.town_threats(0)
	assert_eq(th.size(), 1, str(th))
	assert_eq(th[0]["town_id"], "town_lanternholm")
	assert_eq(th[0]["hero_id"], "hero_gaul")
	assert_eq(th[0]["days"], 1, "two tiles away: one day")
	assert_true(s.town_threats(1).is_empty() or s.town_threats(1)[0]["hero_id"] != "hero_gaul", "own heroes are never threats")
	data.rules["threat_warning_days"] = 0
	assert_true(s.town_threats(0).is_empty(), "warnings can be switched off in game_rules")
	data.rules["threat_warning_days"] = 3


func test_a_game_lost_in_the_computer_turn_ends_on_the_human_view() -> void:
	var s := _duel()
	s.end_turn()
	assert_eq(s.state.current_player, 1, "the computer is to move")
	var mine := s.hero("hero_osric")
	var lantern := s.town("town_lanternholm")
	var foe := s.hero("hero_gaul")
	_strong(foe)
	_weak(mine)
	mine.pos = AdventureMap.object_pos(lantern)
	foe.pos = mine.pos + Vector2i(1, 0)
	s.attack(foe.id, "town_lanternholm")
	assert_true(s.state.game_over)
	assert_eq(s.state.winner, 1)
	assert_eq(s.state.current_player, 0, "the end screen shows the human's map, fog and resources")


func test_hot_seat_end_goes_to_the_human_winner() -> void:
	var s := GameSession.new_game(data, "mournfield", 2, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "human", "faction": "ashen"},
		{"type": "computer", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
	s.end_turn()
	s.end_turn()
	assert_eq(s.state.current_player, 2)
	VictoryRules.eliminate(s, 0, "test")
	VictoryRules.eliminate(s, 2, "test")
	VictoryRules.update(s)
	assert_true(s.state.game_over)
	assert_eq(s.state.winner, 1)
	assert_eq(s.state.current_player, 1, "the winning human, not the last one to move")


func test_town_loss_timer() -> void:
	var s := _duel()
	var grace := int(data.rules["town_loss_grace_days"])
	s.town("town_pyrewatch")["owner"] = -1
	VictoryRules.update(s)
	assert_false(s.state.player(1)["defeated"], "a hero keeps the player in the game for now")
	var warnings := []
	s.message.connect(func(t): if "holds no town" in t: warnings.append(t))
	for d in grace - 1:
		s.end_turn()
		s.end_turn()
	assert_eq(VictoryRules.days_left(s, 1), 1)
	assert_false(s.state.player(1)["defeated"])
	assert_eq(warnings.size(), grace - 1)
	s.end_turn()
	s.end_turn()
	assert_true(s.state.player(1)["defeated"], "eliminated after %d days" % grace)
	assert_false(s.hero("hero_gaul").alive)
	assert_true(s.state.game_over)
	assert_eq(s.state.winner, 0)


func test_retaking_a_town_resets_the_timer() -> void:
	var s := _duel()
	var pyre := s.town("town_pyrewatch")
	pyre["owner"] = -1
	s.end_turn()
	s.end_turn()
	assert_eq(int(s.state.player(1)["days_without_town"]), 1)
	pyre["owner"] = 1
	s.end_turn()
	s.end_turn()
	assert_eq(int(s.state.player(1)["days_without_town"]), 0)
	assert_eq(VictoryRules.days_left(s, 1), -1)


func test_three_players_play_on_after_one_falls() -> void:
	var s := GameSession.new_game(data, "mournfield", 2, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "human", "faction": "ashen"},
		{"type": "computer", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
	assert_eq(s.state.player(0)["name"], "Player 1", "hot-seat players are numbered")
	assert_eq(s.state.player(1)["name"], "Player 2")
	VictoryRules.eliminate(s, 1, "test")
	VictoryRules.update(s)
	assert_false(s.state.game_over)
	s.end_turn()
	assert_eq(s.state.current_player, 2, "turn order skips the fallen")
	VictoryRules.eliminate(s, 0, "test")
	VictoryRules.update(s)
	assert_true(s.state.game_over, "no human left")
	assert_eq(s.state.end_reason, "conquest", "and the last computer player stands alone")


func test_computer_only_games_play_to_the_last_player() -> void:
	var s := GameSession.new_game(data, "mournfield", 2, {"players": [
		{"type": "computer", "faction": "concord"}, {"type": "computer", "faction": "ashen"},
		{"type": "computer", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
	VictoryRules.eliminate(s, 0, "test")
	VictoryRules.update(s)
	assert_false(s.state.game_over)


# ------------------------------------------------------------- save/load --

func test_save_roundtrip_keeps_flow_state() -> void:
	var s := _duel()
	s.town("town_pyrewatch")["owner"] = -1
	s.end_turn()
	s.end_turn()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	assert_eq(SaveSlots.save(s, "2", SAVE_DIR), OK)
	var loaded := SaveSlots.load_slot(data, "2", SAVE_DIR)
	assert_true(loaded != null)
	assert_eq(JSON.stringify(loaded.state.to_dict()), JSON.stringify(s.state.to_dict()))
	assert_eq(int(loaded.state.player(1)["days_without_town"]), 1)
	assert_eq(loaded.state.players.size(), 2)
	SaveSlots.delete("2", SAVE_DIR)


func test_save_slots_list_and_describe() -> void:
	for slot in SaveSlots.slot_ids(data):
		SaveSlots.delete(slot, SAVE_DIR)
	var s := _duel()
	assert_eq(SaveSlots.save(s, SaveSlots.AUTOSAVE, SAVE_DIR), OK)
	assert_eq(SaveSlots.save(s, "3", SAVE_DIR), OK)
	var rows := SaveSlots.list(data, SAVE_DIR)
	assert_eq(rows.size(), int(data.rules["save_slots"]) + 1)
	assert_eq(rows[0]["slot"], "auto")
	assert_true(rows[0]["valid"])
	assert_true(rows[3]["valid"])
	assert_false(rows[1]["exists"])
	assert_eq(rows[3]["meta"]["map_name"], "Mournfield Crossroads")
	assert_true("Mournfield Crossroads" in SaveSlots.summary(rows[3]))
	assert_eq(SaveSlots.summary(rows[1]), "Empty")
	# A broken file is listed but not loadable.
	var f := FileAccess.open(SaveSlots.path_for("4", SAVE_DIR), FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	var row4: Dictionary = SaveSlots.list(data, SAVE_DIR)[4]
	assert_true(row4["exists"])
	assert_false(row4["valid"])
	assert_true(SaveSlots.load_slot(data, "4", SAVE_DIR) == null)
	for slot in SaveSlots.slot_ids(data):
		SaveSlots.delete(slot, SAVE_DIR)


func test_version_3_save_migrates() -> void:
	var s := GameSession.new_game(data, "ember_ford", 4)
	var d := s.state.to_dict()
	d["version"] = 3
	d.erase("winner")
	d.erase("end_reason")
	for p in d["players"]:
		p.erase("days_without_town")
		p.erase("eliminated_day")
	var st := GameState.from_dict(JSON.parse_string(JSON.stringify(d)), data)
	assert_eq(st.winner, -1)
	assert_eq(st.end_reason, "")
	assert_eq(int(st.player(0)["days_without_town"]), 0)
	assert_eq(st.to_dict()["version"], GameState.SAVE_VERSION)


# --------------------------------------------------------------------- AI --

func _ai_duel() -> GameSession:
	var s := _duel()
	s.state.player(0)["is_human"] = false
	return s


func test_ai_hunts_a_weaker_enemy_hero() -> void:
	var s := _ai_duel()
	var foe := s.hero("hero_osric")
	var ai_hero := s.hero("hero_gaul")
	_weak(foe)
	foe.pos = ai_hero.pos + Vector2i(-3, 0)
	s.state.player(1)["fog"].reveal(foe.pos, 2)
	s.state.current_player = 1
	var ai := StrategicAI.new(s, 1)
	var targets := ai.candidate_targets(ai_hero, AiDistanceField.build(s.state.map, ai_hero.pos, ai._blocked_for(ai_hero)))
	assert_true(targets.any(func(t): return t["kind"] == "hero" and t["id"] == foe.id), "the enemy hero is a target")
	ai.play_turn()
	assert_false(foe.alive, "the computer player fights and beats the hero")


func test_ai_besieges_a_town_defended_by_a_hero() -> void:
	var s := _ai_duel()
	var lantern := s.town("town_lanternholm")
	var foe := s.hero("hero_osric")
	foe.pos = AdventureMap.object_pos(lantern)
	_weak(foe)
	var ai_hero := s.hero("hero_gaul")
	_strong(ai_hero)
	ai_hero.pos = foe.pos + Vector2i(2, 0)
	s.state.player(1)["fog"].reveal(foe.pos, 3)
	s.state.current_player = 1
	var ai := StrategicAI.new(s, 1)
	assert_gt(ai.defender_value(lantern), 0.0, "the defending hero counts")
	ai.play_turn()
	assert_eq(int(lantern["owner"]), 1)
	assert_false(foe.alive)
	assert_true(s.state.game_over, "the last town and hero are gone")
	assert_eq(s.state.winner, 1)


func test_ai_main_hero_swaps_weak_stacks_for_the_garrison() -> void:
	# Full slots used to lock the garrison out: the strongest troops then
	# idled in towns and AI-vs-AI games stalled for months.
	var s := _ai_duel()
	var pyre := s.town("town_pyrewatch")
	var h := s.hero("hero_gaul")
	h.pos = AdventureMap.object_pos(pyre)
	h.army = Army.from_pairs([["pike_militia", 1], ["pike_veteran", 1], ["longbowman", 1], ["warbow_sergeant", 1],
		["shieldwarden", 1], ["bulwark_sworn", 1], ["lancer", 1], ["lightbearer", 1], ["sunhawk_rider", 1], ["cinderling", 1]])
	Town.set_garrison(pyre, Army.from_pairs([["bastion_colossus", 6], ["pike_militia", 40]]))
	s.state.current_player = 1
	var ai := StrategicAI.new(s, 1)
	ai._compute_threats()
	var before := ai.army_value(h.army)
	assert_gt(ai._town_visit_value(pyre, h), 0.0, "a garrison stronger than the hero's stacks is worth a visit")
	ai._manage_town(pyre, h)
	var kinds := {}
	for st in h.army.slots:
		if not st.is_empty():
			kinds[st["creature"]] = int(st["count"])
	assert_eq(int(kinds.get("bastion_colossus", 0)), 6, "the colossi join the hero")
	assert_eq(int(kinds.get("pike_militia", 0)), 41, "the militia merges into the matching stack")
	assert_eq(h.army.stack_count(), Army.MAX_SLOTS)
	assert_gt(ai.army_value(h.army), before * 3.0)
	assert_false(Town.garrison(pyre).is_empty(), "the weakest stack stays behind")
	var again := ai._consolidate(pyre, h)
	assert_eq(again, 0, "nothing left that improves the army: no endless swapping")


func test_computer_duel_reaches_an_end() -> void:
	# Every seed must end in conquest: a stand-off means the AI is missing
	# something (it used to leave its strongest troops idle in garrisons).
	for seed_value in [1, 2, 3, 4, 5]:
		var s := GameSession.new_game(data, "twin_marches", seed_value)
		for p in s.state.players:
			p["is_human"] = false
		while not s.state.game_over and s.state.day <= DUEL_DAY_LIMIT:
			StrategicAI.new(s, s.state.current_player).play_turn()
			s.end_turn()
		assert_true(s.state.game_over, "seed %d: a computer-only duel ends within %d days" % [seed_value, DUEL_DAY_LIMIT])
		assert_true(s.state.winner >= 0, "seed %d has a winner" % seed_value)
		assert_eq(s.game_result()["reason"], "conquest")


func test_sightings_are_recorded_once_and_survive_saving() -> void:
	var s := _duel()
	var enemy := s.hero("hero_gaul")
	var p := s.state.player(0)
	p["known_enemy_heroes"] = {}
	p["news"] = []
	(p["fog"] as FogOfWar).reveal(enemy.pos, 0)
	s.record_enemy_sightings()
	s.record_enemy_sightings()
	assert_eq((p["news"] as Array).size(), 1)
	assert_true(String(p["news"][0]).contains(enemy.name))
	var loaded := GameState.from_dict(s.state.to_dict(), data)
	assert_true(loaded.player(0)["known_enemy_heroes"].has(enemy.id))


func test_flee_preserves_hero_and_abandons_army() -> void:
	var s := _duel()
	var attacker := s.hero("hero_osric")
	var defender := s.hero("hero_gaul")
	attacker.pos = Vector2i(6, 4)
	defender.pos = Vector2i(7, 4)
	_strong(attacker)
	_weak(defender)
	defender.give_artifact("sceptre_of_the_pyre", data)
	var equipment := defender.equipment.duplicate(true)
	var home := s.flee_destination(defender.id, defender.pos)
	assert_ne(home, Vector2i(-1, -1))
	var xp := defender.xp
	var result := s.attack(attacker.id, defender.id, true)
	assert_true(result["defender_fled"])
	assert_true(defender.alive)
	assert_eq(defender.pos, home)
	assert_true(defender.army.is_empty())
	assert_eq(defender.xp, xp)
	assert_eq(defender.equipment, equipment)
	assert_eq(defender.movement_left, 0)
	assert_eq(result["winner"], 0)
	assert_eq(result["xp_gained"], int(round(result["hp_killed"][0] * float(data.combat["xp_per_enemy_hp_killed"]))))


func test_flee_requires_a_held_safe_town() -> void:
	var s := _duel()
	var attacker := s.hero("hero_osric")
	var defender := s.hero("hero_gaul")
	attacker.pos = Vector2i(6, 4)
	defender.pos = Vector2i(7, 4)
	for t in s.towns_of(defender.owner):
		t["owner"] = attacker.owner
	assert_eq(s.flee_destination(defender.id), Vector2i(-1, -1))
	var before := s.state.battles_fought
	assert_false(s.attack(attacker.id, defender.id, true)["ok"])
	assert_eq(s.state.battles_fought, before)
	assert_true(defender.alive)


func test_fleeing_army_can_win_without_returning_to_hero() -> void:
	var s := _duel()
	var attacker := s.hero("hero_osric")
	var defender := s.hero("hero_gaul")
	attacker.pos = Vector2i(6, 4)
	defender.pos = Vector2i(7, 4)
	_weak(attacker)
	_strong(defender)
	var result := s.attack(attacker.id, defender.id, true)
	assert_eq(result["winner"], 1)
	assert_true(defender.alive)
	assert_true(defender.army.is_empty())
	assert_eq(result["defender_xp"], 0)
	assert_true(String(result["summary"][-1]).contains("50% less damage"))


func test_flee_from_siege_preserves_hero_and_resolves_garrison() -> void:
	var s := _duel()
	var attacker := s.hero("hero_osric")
	var defender := s.hero("hero_gaul")
	var town := s.town("town_pyrewatch")
	var refuge := s.town("town_lanternholm")
	refuge["owner"] = defender.owner
	defender.pos = AdventureMap.object_pos(town)
	attacker.pos = defender.pos + Vector2i(-1, 0)
	_strong(attacker)
	_weak(defender)
	Town.set_garrison(town, Army.from_pairs([["cinderling", 3]]))
	var result := s.attack(attacker.id, String(town["id"]), true)
	assert_eq(result["winner"], 0)
	assert_true(defender.alive)
	assert_true(defender.army.is_empty())
	assert_eq(defender.pos, AdventureMap.object_pos(refuge))
	assert_eq(int(town["owner"]), attacker.owner)
	assert_true(Town.garrison(town).is_empty())
