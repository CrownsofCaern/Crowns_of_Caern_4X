extends "res://tests/test_case.gd"
## Online play by turn handoff (OnlineMatch), seats in saves (v24) and online
## save slots. The network itself is covered by tests/integration/online_loopback.gd.

const SAVE_DIR := "user://test_online_saves"


## Mournfield: Ana plays slot 0, a computer slot 1, Ben slot 2.
func _match() -> GameSession:
	var s := GameSession.new_game(data, "mournfield", 5, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "ashen"},
		{"type": "human", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
	OnlineMatch.begin(s.state, "m1")
	assert_eq(OnlineMatch.claim(s.state, 0, "Ana"), "")
	assert_eq(OnlineMatch.claim(s.state, 2, "Ben"), "")
	return s


## The game as it arrives on another computer.
func _copy(s: GameSession) -> GameSession:
	var packed := OnlineMatch.pack(s.state)
	var d := OnlineMatch.unpack(packed["bytes"], int(packed["size"]))
	return GameSession.from_state(data, GameState.from_dict(d, data))


func _dict_of(s: GameSession) -> Dictionary:
	return JSON.parse_string(JSON.stringify(s.state.to_dict()))


func test_seats_and_match_survive_a_save() -> void:
	var s := _match()
	var back := _copy(s)
	assert_eq(OnlineMatch.match_id(back.state), "m1")
	assert_eq(OnlineMatch.seat_of(back.state, 0), "Ana")
	assert_eq(OnlineMatch.seat_of(back.state, 1), "")
	assert_eq(OnlineMatch.seat_of(back.state, 2), "Ben")
	assert_eq(OnlineMatch.person_to_move(back.state), "Ana")


func test_older_saves_are_offline_with_free_seats() -> void:
	var s := GameSession.new_game(data, "mournfield", 5)
	var d := _dict_of(s)
	d["version"] = 23
	d.erase("online")
	for p in d["players"]:
		p.erase("seat")
	var st := GameState.from_dict(d, data)
	assert_false(OnlineMatch.is_online(st))
	for i in st.players.size():
		assert_eq(OnlineMatch.seat_of(st, i), "")
	assert_eq(int(st.to_dict()["version"]), GameState.SAVE_VERSION)


func test_begin_keeps_the_match_of_a_resumed_game() -> void:
	var s := _match()
	OnlineMatch.begin(s.state, "other")
	assert_eq(OnlineMatch.match_id(s.state), "m1")


func test_claiming_and_freeing_seats() -> void:
	var s := _match()
	assert_ne(OnlineMatch.claim(s.state, 0, "Cara"), "", "Ana already plays it")
	assert_ne(OnlineMatch.claim(s.state, 1, "Cara"), "", "a computer player is no seat")
	assert_ne(OnlineMatch.claim(s.state, 2, "   "), "", "a name is needed")
	assert_eq(OnlineMatch.claim(s.state, 0, " Ana "), "", "taking your own seat again is fine")
	OnlineMatch.release(s.state, 2)
	assert_eq(OnlineMatch.claim(s.state, 2, "Ana"), "", "one person may play several players")
	assert_eq(OnlineMatch.seats_held(s.state, "Ana"), [0, 2] as Array[int])
	assert_eq(OnlineMatch.seat_rows(s.state).size(), 2)
	VictoryRules.eliminate(s, 2, "test")
	assert_eq(OnlineMatch.seats_held(s.state, "Ana"), [0] as Array[int], "players out of the game are no seats")


func test_a_turn_hands_over_through_the_host() -> void:
	var host := _match()
	var ana := _copy(host)
	ana.end_turn()
	assert_eq(OnlineMatch.check_handoff(host.state, _dict_of(ana), "Ana"), "")
	var next := GameSession.from_state(data, GameState.from_dict(_dict_of(ana), data))
	OnlineMatch.copy_seats(host.state, next.state)
	assert_gt(OnlineMatch.play_computers(next), 0, "the computer player moved on the host")
	assert_eq(next.state.current_player, 2)
	assert_eq(OnlineMatch.person_to_move(next.state), "Ben")
	# Ben's turn ends the day; Ana moves again on day 2.
	var ben := _copy(next)
	ben.end_turn()
	assert_eq(OnlineMatch.check_handoff(next.state, _dict_of(ben), "Ben"), "")
	assert_eq(ben.state.day, 2)
	assert_eq(OnlineMatch.person_to_move(ben.state), "Ana")


func test_handoffs_that_are_refused() -> void:
	var host := _match()
	var ana := _copy(host)
	assert_ne(OnlineMatch.check_handoff(host.state, _dict_of(ana), "Ana"), "", "the turn was not ended")
	ana.end_turn()
	var d := _dict_of(ana)
	assert_ne(OnlineMatch.check_handoff(host.state, d, "Ben"), "", "not Ben's turn")
	assert_ne(OnlineMatch.check_handoff(host.state, d, ""), "", "nobody's turn")
	var other := d.duplicate(true)
	other["online"] = {"match_id": "m2"}
	assert_ne(OnlineMatch.check_handoff(host.state, other, "Ana"), "", "another match")
	var old := d.duplicate(true)
	old["version"] = 23
	assert_ne(OnlineMatch.check_handoff(host.state, old, "Ana"), "", "another game version")
	var broken := d.duplicate(true)
	broken.erase("heroes")
	assert_ne(OnlineMatch.check_handoff(host.state, broken, "Ana"), "", "a damaged save")
	var skipped := d.duplicate(true)
	skipped["day"] = 5
	assert_ne(OnlineMatch.check_handoff(host.state, skipped, "Ana"), "", "days skipped")


func test_pack_rejects_garbage() -> void:
	var packed := OnlineMatch.pack(_match().state)
	assert_lt(float((packed["bytes"] as PackedByteArray).size()), float(int(packed["size"])), "the save is compressed")
	assert_eq(OnlineMatch.unpack(packed["bytes"], int(packed["size"]) + 1), {})
	assert_eq(OnlineMatch.unpack(PackedByteArray([1, 2, 3]), 3), {})
	assert_eq(OnlineMatch.unpack(packed["bytes"], 0), {})


func test_defender_hears_of_the_battle_online_only() -> void:
	for online in [false, true]:
		var s := GameSession.new_game(data, "mournfield", 5, {"players": [
			{"type": "human", "faction": "concord"}, {"type": "human", "faction": "ashen"},
			{"type": "closed", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
		if online:
			OnlineMatch.begin(s.state, "m1")
		var attacker: Hero = s.state.heroes_of(0)[0]
		var defender: Hero = s.state.heroes_of(1)[0]
		defender.pos = attacker.pos + Vector2i(1, 0)
		attacker.army = Army.from_pairs([["bastion_colossus", 30], ["lancer", 60]])
		defender.army = Army.from_pairs([["pike_militia", 2]])
		s.take_news(1)
		var r := s.attack(attacker.id, defender.id)
		assert_eq(int(r["winner"]), 0)
		var news := s.take_news(1)
		if online:
			assert_eq(news.size(), 1)
			assert_true(String(news[0]).contains(attacker.name) and String(news[0]).contains("lost"), str(news))
		else:
			assert_eq(news.size(), 0, "offline the defender watched it")


func test_online_games_have_their_own_slot() -> void:
	var s := _match()
	var slot := OnlineMatch.save_slot(s.state)
	assert_true(SaveSlots.is_online_slot(slot))
	assert_eq(SaveSlots.save(s, slot, SAVE_DIR), OK)
	var rows := SaveSlots.list(data, SAVE_DIR)
	var row: Dictionary = rows[rows.size() - 1]
	assert_eq(String(row["slot"]), slot)
	assert_eq(String(row["label"]), "Online")
	assert_true(bool(row["valid"]))
	var back := SaveSlots.load_slot(data, slot, SAVE_DIR)
	assert_eq(OnlineMatch.seat_of(back.state, 2), "Ben")
	SaveSlots.delete(slot, SAVE_DIR)


func test_data_fingerprint_is_stable() -> void:
	var a := OnlineMatch.data_fingerprint()
	assert_eq(a.length(), 12)
	assert_eq(OnlineMatch.data_fingerprint(), a)
