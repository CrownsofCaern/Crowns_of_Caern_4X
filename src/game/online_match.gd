class_name OnlineMatch
extends RefCounted
## Rules of an online game played turn by turn on several computers. Headless:
## the network itself lives in NetSession (src/net), which only moves saves.
##
## The save is the turn token. The computer of the player to move holds the
## game and plays the turn; at End Turn it sends the save to the host, which
## checks it (check_handoff), plays the computer players (play_computers) and
## sends the result to everyone. A "seat" is the name of the person who plays
## a human player; one person may hold several seats. Seats and the match id
## live in the save (GameState.online, player "seat"), so a saved online game
## resumes with the same people, and anyone can join a game in progress by
## taking a free seat.

## Longest accepted seat name, in characters.
const NAME_MAX := 24


## Marks the game as hosted online (keeps an existing match id: a resumed game
## stays the same match).
static func begin(state: GameState, match_id: String) -> void:
	if String(state.online.get("match_id", "")) == "":
		state.online = {"match_id": match_id}


static func is_online(state: GameState) -> bool:
	return String(state.online.get("match_id", "")) != ""


static func match_id(state: GameState) -> String:
	return String(state.online.get("match_id", ""))


## A trimmed seat name, or "" if it is not usable.
static func clean_name(person: String) -> String:
	var n := person.strip_edges().replace("\n", " ").replace("\t", " ")
	return n.substr(0, NAME_MAX)


## Indices of the players people can play: humans still in the game.
static func human_players(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for i in state.players.size():
		var p := state.player(i)
		if bool(p["is_human"]) and not bool(p["defeated"]):
			out.append(i)
	return out


static func seat_of(state: GameState, player_idx: int) -> String:
	if player_idx < 0 or player_idx >= state.players.size():
		return ""
	return String(state.player(player_idx).get("seat", ""))


## Players this person plays, in index order.
static func seats_held(state: GameState, person: String) -> Array[int]:
	var out: Array[int] = []
	if person == "":
		return out
	for i in human_players(state):
		if seat_of(state, i) == person:
			out.append(i)
	return out


## Takes a free human player for a person. Returns "" or why not.
static func claim(state: GameState, player_idx: int, person: String) -> String:
	var who := clean_name(person)
	if who == "":
		return "Enter a name first."
	if not human_players(state).has(player_idx):
		return "That player is not played by a person."
	var held := seat_of(state, player_idx)
	if held != "" and held != who:
		return "%s already plays %s." % [held, state.player(player_idx)["name"]]
	state.player(player_idx)["seat"] = who
	return ""


## Frees a player again (only its holder, or the host, may do so).
static func release(state: GameState, player_idx: int) -> void:
	if player_idx >= 0 and player_idx < state.players.size():
		state.player(player_idx)["seat"] = ""


## Copies the seat table of one state onto another (the host's table wins over
## whatever a handed-over save carries).
static func copy_seats(from: GameState, to: GameState) -> void:
	for i in mini(from.players.size(), to.players.size()):
		to.player(i)["seat"] = seat_of(from, i)
	to.online = from.online.duplicate(true)


## The person whose turn it is ("" if nobody has taken that player yet, or the
## game is over or a computer player is to move).
static func person_to_move(state: GameState) -> String:
	if state.game_over or not bool(state.player(state.current_player)["is_human"]):
		return ""
	return seat_of(state, state.current_player)


## {player, name, faction, color, seat} for every human player still in the game.
static func seat_rows(state: GameState) -> Array:
	var out := []
	for i in human_players(state):
		var p := state.player(i)
		out.append({"player": i, "name": String(p["name"]), "faction": String(p["faction"]),
			"color": String(p["color"]), "seat": seat_of(state, i)})
	return out


## Checks a save handed over at the end of a turn against the host's game.
## Returns "" if it may replace the host's game, else why not.
static func check_handoff(current: GameState, incoming: Dictionary, sender: String) -> String:
	var errors := GameState.validate_save(incoming)
	if not errors.is_empty():
		return "The game sent is damaged (%s)." % ", ".join(errors)
	if int(incoming["version"]) != GameState.SAVE_VERSION:
		return "The game sent comes from another version of the game."
	var online: Variant = incoming.get("online", {})
	if typeof(online) != TYPE_DICTIONARY or String(online.get("match_id", "")) != match_id(current):
		return "The game sent belongs to another match."
	if (incoming["players"] as Array).size() != current.players.size():
		return "The game sent has other players."
	if current.game_over:
		return "This game is already over."
	var mover := current.current_player
	if not bool(current.player(mover)["is_human"]) or seat_of(current, mover) != sender or sender == "":
		return "It is not %s's turn." % (sender if sender != "" else "your")
	var day := int(incoming["day"])
	var next := int(incoming["current_player"])
	var finished := bool(incoming.get("game_over", false))
	if not finished and (day < current.day or (day == current.day and next == mover)):
		return "The turn was not finished."
	if day > current.day + 1:
		return "The game sent skipped days."
	return ""


## Plays every computer player until a human is to move or the game ends (on
## the host). Returns how many computer turns were played.
static func play_computers(session: GameSession, max_turns: int = 64) -> int:
	return StrategicAI.play_ai_turns(session, max_turns)


## The save that travels between computers: {bytes: compressed JSON, size:
## its uncompressed length, which unpack() needs}.
static func pack(state: GameState) -> Dictionary:
	var raw := JSON.stringify(state.to_dict()).to_utf8_buffer()
	return {"bytes": raw.compress(FileAccess.COMPRESSION_ZSTD), "size": raw.size()}


## Unpacks a save from pack(); {} if it is not one.
static func unpack(bytes: PackedByteArray, raw_size: int) -> Dictionary:
	if raw_size <= 0 or raw_size > 256 * 1024 * 1024:
		return {}
	var raw := bytes.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return {}
	var d: Variant = JSON.parse_string(raw.get_string_from_utf8())
	return d if typeof(d) == TYPE_DICTIONARY else {}


## Save slot an online game is kept in on every computer ("online_<match>").
static func save_slot(state: GameState) -> String:
	return "online_" + match_id(state).validate_filename()


## A short fingerprint of the game's data files: two computers with different
## data would play different games from the same save.
static func data_fingerprint() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var files := Array(DirAccess.get_files_at(GameData.DATA_DIR))
	files.sort()
	for f in files:
		var fname := String(f)
		if not fname.ends_with(".json"):
			continue
		ctx.update(fname.to_utf8_buffer())
		# Line endings differ between checkouts on different systems.
		ctx.update(FileAccess.get_file_as_string(GameData.DATA_DIR.path_join(fname)).replace("\r", "").to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 12)
