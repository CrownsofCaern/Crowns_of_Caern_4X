extends "res://tests/test_case.gd"
## The guard rule: a resource pile, artifact or mine next to a neutral army
## cannot be claimed until that army is beaten; stepping onto it starts the fight.

var session: GameSession
var hero: Hero


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 5)
	hero = session.hero("hero_wren")
	session.current_player()["fog"].reveal(Vector2i(12, 8), 40)


func _make_strong() -> void:
	hero.army = Army.from_pairs([["shieldwarden", 60], ["longbowman", 80], ["lancer", 30], ["sunhawk_rider", 12]])


func _army(id: String, pos: Vector2i) -> Dictionary:
	var o := {"id": id, "type": "neutral_army", "name": "Test %s" % id, "pos": [pos.x, pos.y], "stacks": [["thornwolf", 4]]}
	session.state.map.add_object(o)
	return o


## res_2 lies at (3, 6) on open ground near Wren's start.
func _pile() -> Dictionary:
	return session.state.map.objects["res_2"]


func test_pile_next_to_army_is_guarded() -> void:
	assert_false(session.is_guarded(_pile(), 0), "a lone pile is free")
	var guard := _army("guard_a", Vector2i(4, 7))   # diagonal neighbours count
	assert_true(session.is_guarded(_pile(), 0))
	assert_eq(session.claim_guard(_pile(), 0)["id"], "guard_a")
	assert_eq(session.hostile_target_at(Vector2i(3, 6), 0), "res_2")
	var tgt := session.battle_target("res_2")
	assert_eq(tgt["kind"], "neutral_army")
	assert_eq(tgt["object"], guard)
	assert_eq(tgt["claim"], _pile())
	assert_eq(tgt["pos"], Vector2i(3, 6), "the fight is on the prize's tile")
	assert_eq(session.battle_setup("hero_wren", "res_2")["sides"][1]["stacks"].size(), 1)


func test_far_army_does_not_guard() -> void:
	_army("guard_far", Vector2i(5, 6))
	assert_false(session.is_guarded(_pile(), 0), "two tiles away is not next to it")


func test_stepping_on_guarded_pile_starts_the_fight_and_winning_claims_it() -> void:
	_army("guard_a", Vector2i(4, 7))
	hero.pos = Vector2i(3, 8)
	hero.movement_left = 2000
	var r := session.move_hero("hero_wren", Vector2i(3, 6))
	assert_eq(r["battle"], "res_2")
	assert_eq(hero.pos, Vector2i(3, 7), "stops next to the pile")
	assert_true(r["collected"].is_empty())
	assert_true(session.state.map.objects.has("res_2"))
	var bank: ResourceBank = session.current_player()["resources"]
	var res := String(_pile()["resource"])
	var before := bank.get_amount(res)
	var amount := int(_pile()["amount"])
	_make_strong()
	var out := session.attack("hero_wren", "res_2")
	assert_eq(out["winner"], 0)
	assert_eq(out["claimed"], "res_2")
	assert_false(session.state.map.objects.has("guard_a"), "the guard is gone")
	assert_false(session.state.map.objects.has("res_2"), "the pile is taken")
	assert_eq(hero.pos, Vector2i(3, 6))
	assert_true(bank.get_amount(res) >= before + amount)


func test_losing_leaves_prize_and_weakened_guard() -> void:
	var guard := _army("guard_a", Vector2i(4, 7))
	guard["stacks"] = [["thornwolf", 400]]
	hero.pos = Vector2i(3, 7)
	hero.army = Army.from_pairs([["shieldwarden", 1]])
	var out := session.attack("hero_wren", "res_2")
	assert_eq(out["winner"], 1)
	assert_true(session.state.map.objects.has("res_2"))
	assert_true(session.state.map.objects.has("guard_a"))
	assert_true(session.is_guarded(_pile(), 0))


func test_second_guard_keeps_the_prize() -> void:
	_army("guard_a", Vector2i(4, 7))
	_army("guard_b", Vector2i(2, 5))
	assert_eq(session.claim_guard(_pile(), 0)["id"], "guard_a", "lowest id fights first")
	hero.pos = Vector2i(3, 7)
	_make_strong()
	var out := session.attack("hero_wren", "res_2")
	assert_eq(out["winner"], 0)
	assert_true(session.state.map.objects.has("res_2"), "still guarded by the second army")
	assert_eq(hero.pos, Vector2i(3, 7), "the hero holds its ground")
	assert_eq(session.claim_guard(_pile(), 0)["id"], "guard_b")
	out = session.attack("hero_wren", "res_2")
	assert_eq(out["winner"], 0)
	assert_false(session.state.map.objects.has("res_2"))


func test_guarded_pile_blocks_paths_through_it() -> void:
	_army("guard_a", Vector2i(4, 7))
	hero.pos = Vector2i(3, 7)
	var plan := session.plan_path("hero_wren", Vector2i(3, 5))
	assert_false(plan["path"].is_empty())
	assert_false(plan["path"].has(Vector2i(3, 6)), "walk around the guarded pile")


func test_guarded_by_names_a_guard_further_away() -> void:
	_army("warden", Vector2i(8, 8))
	_pile()["guarded_by"] = "warden"
	assert_eq(session.claim_guard(_pile(), 0)["id"], "warden")
	session.state.map.remove_object("warden")
	assert_false(session.is_guarded(_pile(), 0))


func test_unguarded_mine_next_to_army_needs_the_fight() -> void:
	var mine: Dictionary = session.state.map.objects["mine_wood"]   # (3, 4)
	_army("guard_m", Vector2i(2, 3))
	assert_true(session.is_guarded(mine, 0))
	hero.pos = Vector2i(3, 5)
	hero.movement_left = 2000
	var r := session.move_hero("hero_wren", Vector2i(3, 4))
	assert_eq(r["battle"], "mine_wood")
	assert_true(r["captured"].is_empty())
	_make_strong()
	var out := session.attack("hero_wren", "mine_wood")
	assert_eq(out["winner"], 0)
	assert_eq(int(mine["owner"]), 0, "captured after the fight")
	assert_eq(hero.pos, Vector2i(3, 4))
	# Once held, a mine next to an army is ours to walk on.
	_army("guard_m2", Vector2i(2, 3))
	assert_false(session.is_guarded(mine, 0))


func test_mine_with_its_own_guard_fights_that_first() -> void:
	var mine: Dictionary = session.state.map.objects["mine_mercury"]   # (6, 16), own guard
	_army("guard_n", Vector2i(7, 17))
	assert_eq(session.battle_target("mine_mercury")["kind"], "mine")
	hero.pos = Vector2i(6, 15)
	_make_strong()
	var out := session.attack("hero_wren", "mine_mercury")
	assert_eq(out["winner"], 0)
	assert_eq(int(mine["owner"]), -1, "the neighbouring army still keeps it")
	assert_eq(hero.pos, Vector2i(6, 15))
	assert_eq(session.battle_target("mine_mercury")["kind"], "neutral_army")
	out = session.attack("hero_wren", "mine_mercury")
	assert_eq(out["winner"], 0)
	assert_eq(int(mine["owner"]), 0)


func test_guarded_artifact_goes_to_the_pack() -> void:
	var art: Dictionary = session.state.map.objects["art_falchion"]   # (9, 3)
	var aid := String(art["artifact"])
	_army("guard_art", Vector2i(10, 3))
	hero.pos = Vector2i(8, 3)
	_make_strong()
	var out := session.attack("hero_wren", "art_falchion")
	assert_eq(out["winner"], 0)
	assert_false(session.state.map.objects.has("art_falchion"))
	assert_true(hero.equipment.values().has(aid) or hero.pack.has(aid), "taken into the pack")


func test_cursor_and_hover_card_show_the_fight() -> void:
	assert_eq(AdventureCursor.action_for(session, "hero_wren", Vector2i(3, 6)), "pickup")
	_army("guard_a", Vector2i(4, 7))
	assert_eq(AdventureCursor.action_for(session, "hero_wren", Vector2i(3, 6)), "attack")
	var info := MapTipInfo.describe(session, Vector2i(3, 6), hero)
	var text := ""
	for line in info["lines"]:
		text += String(line[0]) + "\n"
	assert_true(text.contains("Guarded by Test guard_a"), text)
	assert_false(text.contains("Walk over it"), text)
	var intel := session.intel("hero_wren", "res_2")
	assert_eq(intel["target"], "guard_a", "scouting the pile scouts its guard")


func test_ai_values_guarded_prize_by_its_guard() -> void:
	var ai := StrategicAI.new(session, 0)
	assert_eq(ai.defender_value(_pile()), 0.0)
	var guard := _army("guard_a", Vector2i(4, 7))
	assert_gt(ai.defender_value(_pile()), 0.0)
	assert_eq(ai.defender_value(_pile()), ai.defender_value(guard))


func test_random_maps_leave_guarded_prizes_in_the_open() -> void:
	var tpl := MapGenerator.find_template(data.map_templates, "random_m_2p_normal_normal", 3)
	assert_eq(String(tpl.get("guard_pockets", "")), "open")
	var def := generated_map("random_m_2p_normal_normal", 3)
	assert_false(def.is_empty())
	var by_id := {}
	for o in def["objects"]:
		by_id[o["id"]] = o
	var guarded := 0
	var open := 0
	var rock := String(data.terrain("mountain")["char"])
	for o in def["objects"]:
		if not o.has("guarded_by"):
			continue
		guarded += 1
		var g: Dictionary = by_id[o["guarded_by"]]
		var d := Vector2i(int(g["pos"][0]), int(g["pos"][1])) - Vector2i(int(o["pos"][0]), int(o["pos"][1]))
		assert_eq(absi(d.x) + absi(d.y), 1, "guard stands next to its prize")
		var p := Vector2i(int(o["pos"][0]), int(o["pos"][1]))
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + n
			if q != p + d and q.x >= 0 and q.y >= 0 and q.x < int(def["width"]) and q.y < int(def["height"]):
				if String(def["terrain"][q.y][q.x]) != rock:
					open += 1
					break
	assert_gt(guarded, 3, "the map has guarded treasure")
	assert_gt(float(open), guarded * 0.8, "almost every prize is open on another side")
	var s := GameSession.new_game(data, "gen:random_m_2p_normal_normal:3", 1)
	for id in s.state.map.objects:
		var o: Dictionary = s.state.map.objects[id]
		if o.has("guarded_by") and o["type"] in GameSession.GUARDABLE_TYPES:
			assert_true(s.is_guarded(o, 0), "%s is out of reach until its guard falls" % id)


func test_named_templates_use_open_pockets_and_validation_checks_the_key() -> void:
	# Every named template lays out guarded treasure in the open (generator VERSION 10).
	for tid in data.map_templates["templates"]:
		assert_eq(String(data.map_templates["templates"][tid].get("guard_pockets", "sealed")), "open", tid)
	var d := GameData.new()
	d.load_all(GameData.DATA_DIR)
	d.map_templates["templates"]["twin_marches"]["guard_pockets"] = "walled"
	d.map_templates["random_maps"]["guard_pockets"] = "nope"
	var errors := " | ".join(MapGenerator.validate_templates(d))
	assert_true(errors.contains("twin_marches: guard_pockets"), errors)
	assert_true(errors.contains("random_maps: guard_pockets"), errors)
