extends "res://tests/test_case.gd"
## Sieges: fortified, defended towns hold out one day per fortification.


func _duel() -> GameSession:
	return GameSession.new_game(data, "mournfield", 5, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "ashen"},
		{"type": "closed", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})


## Pyrewatch with two fortifications and a garrison; the attacker next to it.
func _setup(s: GameSession, attacker_pairs: Array) -> Dictionary:
	var a := s.hero("hero_osric")
	var pyre := s.town("town_pyrewatch")
	s.hero("hero_gaul").pos = Vector2i(0, 0)
	for b in ["a_trench"]:
		if not pyre["built"].has(b):
			pyre["built"].append(b)
	Town.set_garrison(pyre, Army.from_pairs([["cinderling", 20]]))
	a.pos = AdventureMap.object_pos(pyre) + Vector2i(-1, 0)
	a.army = Army.from_pairs(attacker_pairs)
	return {"hero": a, "town": pyre}


func test_fortified_town_needs_a_siege() -> void:
	var s := _duel()
	var x := _setup(s, [["pike_militia", 30]])
	var a: Hero = x["hero"]
	var pyre: Dictionary = x["town"]
	var forts := s.fortification_level(pyre)
	assert_gt(forts, 0)
	var st := s.siege_status(a.id, "town_pyrewatch")
	assert_true(st["needed"])
	assert_false(st["ready"])
	var rng_before := s.state.rng.state
	var res := s.attack(a.id, "town_pyrewatch")
	assert_true(res.get("siege", false), "the first attack lays siege")
	assert_false(res.has("winner"))
	assert_eq(s.state.rng.state, rng_before, "the siege never draws from the game RNG")
	assert_eq(a.movement_left, 0)
	assert_eq(s.besiegers(pyre), [0])
	assert_eq(int(s.siege_of(pyre, 0)["ready_day"]), s.state.day + forts)
	assert_true(s.attack(a.id, "town_pyrewatch").get("siege", false), "still waiting")
	s.state.day += forts
	assert_true(s.siege_status(a.id, "town_pyrewatch")["ready"])
	res = s.attack(a.id, "town_pyrewatch")
	assert_true(res.has("winner"), "the walls can be stormed")
	assert_false(pyre.has("sieges"))


func test_siege_breaks_when_the_besieger_leaves() -> void:
	var s := _duel()
	var x := _setup(s, [["pike_militia", 30]])
	var a: Hero = x["hero"]
	s.attack(a.id, "town_pyrewatch")
	assert_eq(s.besiegers(x["town"]).size(), 1)
	a.pos += Vector2i(-3, 0)
	assert_eq(s.besiegers(x["town"]).size(), 0)
	assert_false(s.siege_status(a.id, "town_pyrewatch")["active"])


func test_empty_town_needs_no_siege() -> void:
	var s := _duel()
	var x := _setup(s, [["pike_militia", 30]])
	Town.set_garrison(x["town"], Army.new())
	assert_false(s.siege_status((x["hero"] as Hero).id, "town_pyrewatch")["needed"])


func test_surrender_chance_grows_with_odds() -> void:
	var s := _duel()
	var x := _setup(s, [["pike_militia", 5]])
	var weak := s.surrender_chance(x["hero"], x["town"])
	(x["hero"] as Hero).army = Army.from_pairs([["bastion_colossus", 30], ["lancer", 60]])
	var strong := s.surrender_chance(x["hero"], x["town"])
	assert_eq(weak, 0.0)
	assert_gt(strong, 0.0)
	assert_true(strong <= 0.35)


func test_ai_keeps_its_siege_then_storms() -> void:
	var s := _duel()
	s.state.player(0)["is_human"] = false
	var x := _setup(s, [["bastion_colossus", 2], ["lancer", 30]])
	var pyre: Dictionary = x["town"]
	# The AI besieges player 0's town this time.
	pyre["owner"] = 0
	var ai_hero := s.hero("hero_gaul")
	var mine := s.hero("hero_osric")
	mine.pos = Vector2i(0, 0)
	ai_hero.pos = AdventureMap.object_pos(pyre) + Vector2i(-1, 0)
	ai_hero.army = Army.from_pairs([["cinderling", 200]])
	s.state.player(1)["fog"].reveal(ai_hero.pos, 3)
	s.state.current_player = 1
	var status := s.siege_status(ai_hero.id, "town_pyrewatch")
	assert_true(status["needed"])
	var begun := s.begin_siege(ai_hero.id, "town_pyrewatch")
	assert_true(begun["started"], "no early surrender with this seed")
	var pos := ai_hero.pos
	ai_hero.movement_left = ai_hero.max_movement(data)
	StrategicAI.new(s, 1).play_turn()
	assert_eq(ai_hero.pos, pos, "the besieger holds its ground")
	assert_eq(int(pyre["owner"]), 0)
	s.state.day += s.fortification_level(pyre)
	ai_hero.movement_left = ai_hero.max_movement(data)
	StrategicAI.new(s, 1).play_turn()
	assert_eq(int(pyre["owner"]), 1, "the walls fell and the AI stormed the town")
