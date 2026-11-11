class_name VictoryRules
extends RefCounted
## Victory and defeat. Pure rules on top of a GameSession, run after every
## battle, capture and turn change.
##
## - A player with neither living heroes nor towns is eliminated at once.
## - A player who holds no town but still has heroes must retake one within
##   game_rules.town_loss_grace_days new days, or is eliminated (heroes and all).
## - With two or more players, the last one standing wins ("conquest"); allies
##   (GameState.allied) win together once no rival of theirs is left. The
##   winner is then the first surviving player of that alliance.
## - When every human player is out while computer players remain, the game is
##   over and lost ("defeat"); computer-only games play on to the last player.
## - On a map with a single player, holding every town wins ("domination").
## The outcome is stored in GameState (game_over, winner, end_reason) and saved.


## Re-evaluates eliminations and the end of the game. Safe to call any time.
static func update(session: GameSession) -> void:
	var st := session.state
	if st.game_over:
		return
	ScenarioBetrayal.check(session)
	for i in st.players.size():
		var p := st.player(i)
		if p["defeated"]:
			continue
		if WaveDirector.reserved_player(st, i):
			continue
		if st.heroes_of(i).is_empty() and session.towns_of(i).is_empty():
			eliminate(session, i, "has neither heroes nor towns left")
	_check_end(session)


## Daily town-loss timer; called once at the start of every new day.
static func on_new_day(session: GameSession) -> void:
	var st := session.state
	if st.game_over:
		return
	var grace := int(session.data.rules["town_loss_grace_days"])
	for i in st.players.size():
		var p := st.player(i)
		if p["defeated"]:
			continue
		if ScenarioRules.townless_allowed(st, i) or WaveDirector.reserved_player(st, i):
			p["days_without_town"] = 0
			continue
		if not session.towns_of(i).is_empty():
			p["days_without_town"] = 0
			continue
		p["days_without_town"] = int(p.get("days_without_town", 0)) + 1
		var left := grace - int(p["days_without_town"])
		if left <= 0:
			eliminate(session, i, "held no town for %d days" % grace)
		else:
			session.message.emit("%s holds no town: %d day%s left to take one, or the realm is lost." % [
				p["name"], left, "" if left == 1 else "s"])
	_check_end(session)


## Days a townless player has left (or -1 if the player holds a town / is out).
static func days_left(session: GameSession, player_idx: int) -> int:
	var p := session.state.player(player_idx)
	if ScenarioRules.townless_allowed(session.state, player_idx) or WaveDirector.reserved_player(session.state, player_idx) or p["defeated"] or not session.towns_of(player_idx).is_empty():
		return -1
	return int(session.data.rules["town_loss_grace_days"]) - int(p.get("days_without_town", 0))


## Removes a player from the game: heroes fall, mines go back to the wild.
static func eliminate(session: GameSession, player_idx: int, why: String) -> void:
	var st := session.state
	var p := st.player(player_idx)
	if p["defeated"]:
		return
	p["defeated"] = true
	p["eliminated_day"] = st.day
	for h in st.heroes_of(player_idx):
		h.alive = false
		h.army = Army.new()
	for m in session.mines_of(player_idx):
		m["owner"] = -1
	for t in session.towns_of(player_idx):
		t["owner"] = -1
	session.message.emit("%s %s and is out of the game." % [p["name"], why])


static func active_players(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for i in st.players.size():
		if not st.player(i)["defeated"]:
			out.append(i)
	return out


static func _check_end(session: GameSession) -> void:
	var st := session.state
	if st.game_over:
		return
	if ScenarioRules.active(st):
		var outcome := ScenarioRules.outcome(session)
		if not outcome.is_empty():
			_finish(session, int(outcome["winner"]), String(outcome["reason"]))
		return
	var alive := active_players(st)
	if st.players.size() >= 2:
		if alive.size() <= 1 or _one_alliance(st, alive):
			_finish(session, alive[0] if alive.size() >= 1 else -1, "conquest")
			return
		var had_human := false
		var human_left := false
		for p in st.players:
			if p["is_human"]:
				had_human = true
				if not p["defeated"]:
					human_left = true
		if had_human and not human_left:
			_finish(session, -1, "defeat")
		return
	# Single-player map.
	if alive.is_empty():
		_finish(session, -1, "defeat")
		return
	var towns := 0
	var held := 0
	for id in st.map.objects:
		var o: Dictionary = st.map.objects[id]
		if o["type"] == "town":
			towns += 1
			if int(o["owner"]) == alive[0]:
				held += 1
	if towns > 0 and held == towns:
		_finish(session, alive[0], "domination")


## True if every player still in the game is allied with every other.
static func _one_alliance(st: GameState, alive: Array[int]) -> bool:
	for a in alive:
		for b in alive:
			if not st.allied(a, b):
				return false
	return true


## The winner and its allies who were in the game (fallen allies share the win), in index order.
static func winners(st: GameState) -> Array[int]:
	var out: Array[int] = []
	if st.winner < 0:
		return out
	return st.allies_of(st.winner)


static func _finish(session: GameSession, winner: int, reason: String) -> void:
	var st := session.state
	st.game_over = true
	st.winner = winner
	st.end_reason = reason
	_turn_to_human(st, winner)
	match reason:
		"scenario_victory", "scenario_defeat":
			session.message.emit(String(ScenarioRules.outcome(session).get("text", "")))
		"conquest":
			if winner < 0:
				session.message.emit("No one is left standing.")
			elif st.allies_of(winner).size() > 1:
				session.message.emit("%s and their allies hold the field. The war is over." % st.player(winner)["name"])
			else:
				session.message.emit("%s stands alone. The war is over." % st.player(winner)["name"])
		"domination":
			session.message.emit("Every town flies %s's banner. The land is won." % st.player(winner)["name"])
		_:
			session.message.emit("All heroes have fallen. The game is lost.")


## The game often ends during a computer's turn (it takes the last human town).
## The finished game then belongs to a human player, so the end screen and the
## map left behind it show that player's fog, resources and heroes rather than
## the computer's: the human winner, else the human who moved last before the
## current player. Computer-only games keep their current player.
static func _turn_to_human(st: GameState, winner: int) -> void:
	if bool(st.player(st.current_player)["is_human"]):
		return
	if winner >= 0:
		for i in st.allies_of(winner):
			if bool(st.player(i)["is_human"]):
				st.current_player = i
				return
	var n := st.players.size()
	for k in range(1, n + 1):
		var i := posmod(st.current_player - k, n)
		if bool(st.player(i)["is_human"]):
			st.current_player = i
			return


## Summary for the end-of-game screen and the AI:
## {over, winner, winners, winner_name, human_won, reason, title, text, day, standings[{player, name, faction,
##  is_human, team, won, defeated, eliminated_day, towns, heroes, mines, army}]}. winners: the winner and its allies.
## Standings: winners first, then by elimination day (latest first).
static func result(session: GameSession) -> Dictionary:
	var st := session.state
	var won_by := winners(st)
	var rows := []
	for i in st.players.size():
		var p := st.player(i)
		var army := 0
		for h in st.heroes_of(i):
			army += h.army.total_creatures()
		rows.append({"player": i, "name": p["name"], "faction": p["faction"], "is_human": p["is_human"],
			"difficulty": String(p.get("difficulty", "")), "team": st.team_of(i), "won": won_by.has(i),
			"defeated": p["defeated"], "eliminated_day": int(p.get("eliminated_day", 0)),
			"towns": session.towns_of(i).size(), "heroes": st.heroes_of(i).size(),
			"mines": session.mines_of(i).size(), "army": army})
	rows.sort_custom(func(a, b):
		if a["won"] != b["won"]:
			return a["won"]
		if a["defeated"] != b["defeated"]:
			return not a["defeated"]
		if a["eliminated_day"] != b["eliminated_day"]:
			return a["eliminated_day"] > b["eliminated_day"]
		return a["player"] < b["player"])
	var title := ""
	var text := ""
	var human_won := false
	for i in won_by:
		if bool(st.player(i)["is_human"]):
			human_won = true
	var humans := 0
	for p in st.players:
		if p["is_human"]:
			humans += 1
	if st.game_over:
		if st.winner >= 0:
			var wname: String = st.player(st.winner)["name"]
			if won_by.size() > 1:
				var names: Array[String] = []
				for i in won_by:
					names.append(String(st.player(i)["name"]))
				wname = "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[-1]]
			title = "Victory" if human_won or humans == 0 else "Defeat"
			if humans > 1 and human_won:
				title = ("%s are victorious" if won_by.size() > 1 else "%s is victorious") % wname
			match st.end_reason:
				"domination":
					text = "%s holds every town on the map after %s." % [wname, _days(st.day)]
				_:
					text = ("%s have driven every rival from the land after %s." if won_by.size() > 1
						else "%s has driven every rival from the land after %s.") % [wname, _days(st.day)]
		else:
			title = "Defeat"
			text = "Your heroes are dead and your towns are lost. The realm passes to others on day %d." % st.day
	if st.game_over and st.end_reason in ["scenario_victory", "scenario_defeat"]:
		text = String(ScenarioRules.outcome(session).get("text", ""))
		if not ScenarioRules.definition(st).get("endless", {}).is_empty():
			var defeated_waves := 0
			for wave in WaveDirector.waves(st):
				var commander := session.hero(String(wave["hero"]["id"]))
				if commander != null and not commander.alive:
					defeated_waves += 1
			text += " Survived %d days and defeated %d invasion commanders." % [st.day, defeated_waves]
	return {"over": st.game_over, "winner": st.winner,
		"winner_name": st.player(st.winner)["name"] if st.winner >= 0 else "",
		"winners": won_by, "human_won": human_won, "reason": st.end_reason, "title": title, "text": text, "day": st.day,
		"standings": rows}


static func _days(n: int) -> String:
	return "%d day%s" % [n, "" if n == 1 else "s"]
