extends SceneTree
## Two adventure screens on this computer play an online game over ENet on
## 127.0.0.1: host, join, take seats, hand turns over, keep a turn in progress
## when seats change, refuse a duplicate name, and resume the saved match with
## the roles swapped. Each screen gets its own multiplayer branch.

const PORT := 24791
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if not cond and not failed:
		failed = true
		push_error("online loopback: " + what)


func _until(cond: Callable, what: String, frames: int = 600) -> bool:
	for i in frames:
		if cond.call():
			return true
		await process_frame
	_check(false, "timed out waiting for " + what)
	return false


func _screen(branch: String) -> Node:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath("/root/" + branch))
	var screen = load("res://src/ui/adventure_screen.gd").new()
	screen.name = "Main"
	screen.show_menu_on_start = false
	screen.save_directory = "user://online_loopback_" + branch
	holder.add_child(screen)
	screen.net.save_directory = screen.save_directory
	return screen


func _run() -> void:
	var data := GameData.get_default()
	var a = _screen("A")
	var b = _screen("B")
	var s := GameSession.new_game(data, "mournfield", 5, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "ashen"},
		{"type": "human", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
	a._start(s)
	a._host_online("Ana", PORT)
	_check(a.net.is_host and a.online_panel.is_match_page(), "host waits on the match page")
	a.net.take_seat(0)
	_check(a._online_playing and not a.online_panel.visible and not a._busy, "the host plays its seat")

	b._join_online("127.0.0.1:%d" % PORT, "Ben")
	if not await _until(func(): return b.net.session != null, "the joiner to receive the game"):
		return _finish()
	_check(b.online_panel.is_match_page() and not b.net.my_turn(), "the joiner waits")
	b.net.take_seat(2)
	await _until(func(): return OnlineMatch.seat_of(a.session.state, 2) == "Ben", "Ben's seat on the host")
	_check(a._online_playing and a.session == s, "a seat taken mid-turn keeps the host's turn")

	# A third computer with a name already in the game is turned away.
	var c = _screen("C")
	var refused := [""]
	c.net.closed.connect(func(r: String): refused[0] = r)
	c._join_online("127.0.0.1:%d" % PORT, "Ben")
	await _until(func(): return refused[0] != "", "the duplicate name to be refused")
	_check(String(refused[0]).contains("already"), "refusal says why: " + String(refused[0]))

	# Ana's turn goes to the host's computer players, then to Ben.
	var hero: Hero = a.session.state.heroes_of(0)[0]
	var start_pos := hero.pos
	a._end_turn()
	if not await _until(func(): return b._online_playing, "Ben's turn"):
		return _finish()
	_check(b.session.state.current_player == 2, "Ben plays slot 2")
	_check(a.online_panel.is_match_page() and not a.map_view.visible, "the host's map is hidden while Ben moves")
	_check(b.session.hero(hero.id).pos == start_pos, "Ben sees the same game")

	# Ben ends the day: back to Ana on day 2.
	b._end_turn()
	if not await _until(func(): return a._online_playing, "Ana's second turn"):
		return _finish()
	_check(a.session.state.day == 2, "a new day began")
	await _until(func(): return b.net.session.state.day == 2, "Ben to receive day 2")
	_check(not b._online_playing and b.online_panel.is_match_page(), "Ben waits again")

	# The host leaves; Ben keeps the match and hosts it from his save.
	var dropped := [""]
	b.net.closed.connect(func(r: String): dropped[0] = r)
	a._leave_online()
	await _until(func(): return dropped[0] != "", "Ben to notice the host left")
	var slot := OnlineMatch.save_slot(b.session.state)
	_check(SaveSlots.online_slots(b.save_directory).has(slot), "Ben's computer kept the match")
	b._on_slot_chosen("load", slot)
	_check(not b.net.active(), "loading leaves online play")
	var match_id := OnlineMatch.match_id(b.session.state)
	b._host_online("Ben", PORT + 1)
	_check(OnlineMatch.match_id(b.session.state) == match_id, "a resumed game stays the same match")
	_check(b.online_panel.is_match_page(), "Ana is to move, so Ben waits")
	a._join_online("127.0.0.1:%d" % (PORT + 1), "Ana")
	await _until(func(): return a.net.session != null and a.net.session.state.day == 2, "Ana to rejoin")
	_check(OnlineMatch.seat_of(a.net.session.state, 0) == "Ana", "Ana's seat was kept in the save")
	await _until(func(): return a._online_playing, "Ana to resume her turn in the joined game")
	_finish()


func _finish() -> void:
	for branch in ["A", "B", "C"]:
		var holder := root.get_node_or_null(branch)
		if holder != null:
			var screen = holder.get_node_or_null("Main")
			if screen != null:
				screen.net.leave()
				for slot in SaveSlots.online_slots(screen.save_directory):
					SaveSlots.delete(slot, screen.save_directory)
	if not failed:
		print("PASS online game: host, join, seats, turn handoff, refusal, resume")
	quit(1 if failed else 0)
