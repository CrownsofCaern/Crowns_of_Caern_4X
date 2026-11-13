class_name NetSession
extends Node
## Online play over ENet: one computer hosts, the others join by address.
## Only moves saves around; the rules of the match are OnlineMatch's.
##
## The host keeps the game that counts. Whoever is to move plays on their own
## computer and sends the save at End Turn (finish_turn); the host checks it,
## plays the computer players, keeps it in the match's save slot and sends it
## to everyone (game_received). Seats are taken and freed through the host.
## Every computer keeps the latest game in the same slot, so the match can be
## resumed later by any of them (load it, then host it again).
##
## Must sit at the same node path on every computer (RPCs use it).

signal game_received(session: GameSession)
signal people_changed
## Something to tell the local player (a seat taken, a turn refused, ...).
signal notice(text: String)
## The connection ended; reason says why ("" when we left ourselves).
signal closed(reason: String)

const DEFAULT_PORT := 24680
const MAX_CLIENTS := 7

var data: GameData
var save_directory := SaveSlots.DEFAULT_DIR
var is_host := false
## The name this computer plays under.
var my_name := ""
## The game as this computer last knew it (the host's is the one that counts).
var session: GameSession
## Everyone in the match now, host first: [{name, host}].
var people: Array = []
var _peer: ENetMultiplayerPeer
var _connected := false
## Host only: peer id -> name, for peers that have said hello.
var _names: Dictionary = {}


func _init(game_data: GameData = null) -> void:
	data = game_data
	name = "Net"


func active() -> bool:
	return _peer != null


# ------------------------------------------------------------------ hosting --

## Hosts the running game. Returns "" or why it failed.
func host(game: GameSession, person: String, port: int = DEFAULT_PORT) -> String:
	var who := OnlineMatch.clean_name(person)
	if who == "":
		return "Enter your name first."
	if game == null or game.state.game_over:
		return "Start or load a game first."
	if OnlineMatch.human_players(game.state).is_empty():
		return "This game has no human players."
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return "Could not open port %d (%s)." % [port, error_string(err)]
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_wire()
	is_host = true
	my_name = who
	_names = {}
	session = game
	OnlineMatch.begin(game.state, _new_match_id())
	_update_people()
	_keep(session)
	game_received.emit(session)
	return ""


## This computer's addresses others can join, Tailscale ones first:
## [{address, label}].
static func local_addresses() -> Array:
	var tail := []
	var lan := []
	for a in IP.get_local_addresses():
		var s := String(a)
		if not s.is_valid_ip_address() or s.contains(":") or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		var parts := s.split(".")
		var second := int(parts[1]) if parts.size() == 4 else 0
		if s.begins_with("100.") and second >= 64 and second <= 127:
			tail.append({"address": s, "label": "Tailscale"})
		else:
			lan.append({"address": s, "label": "Local network"})
	return tail + lan


# ------------------------------------------------------------------ joining --

## Joins a host. The answer comes later: game_received, or closed(reason).
func join(address: String, person: String, port: int = DEFAULT_PORT) -> String:
	var who := OnlineMatch.clean_name(person)
	if who == "":
		return "Enter your name first."
	var addr := address.strip_edges()
	if addr.contains(":") and not addr.contains("::"):
		var bits := addr.rsplit(":", true, 1)
		addr = bits[0]
		port = int(bits[1])
	if addr == "":
		return "Enter the host's address."
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, port)
	if err != OK:
		return "Could not connect to %s (%s)." % [addr, error_string(err)]
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_wire()
	is_host = false
	my_name = who
	session = null
	people = []
	return ""


## Leaves the match (the host closes it for everyone).
func leave() -> void:
	if _peer == null:
		return
	var p := _peer
	_peer = null
	_connected = false
	_unwire()
	p.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	_names = {}
	people = []
	closed.emit("")


func _wire() -> void:
	var mp := multiplayer
	if not mp.peer_connected.is_connected(_on_peer_connected):
		mp.peer_connected.connect(_on_peer_connected)
		mp.peer_disconnected.connect(_on_peer_disconnected)
		mp.connected_to_server.connect(_on_connected)
		mp.connection_failed.connect(_on_connection_failed)
		mp.server_disconnected.connect(_on_server_gone)


func _unwire() -> void:
	var mp := multiplayer
	if mp.peer_connected.is_connected(_on_peer_connected):
		mp.peer_connected.disconnect(_on_peer_connected)
		mp.peer_disconnected.disconnect(_on_peer_disconnected)
		mp.connected_to_server.disconnect(_on_connected)
		mp.connection_failed.disconnect(_on_connection_failed)
		mp.server_disconnected.disconnect(_on_server_gone)


func _on_connected() -> void:
	_connected = true
	_rpc_hello.rpc_id(1, my_name, compatibility())


func _on_connection_failed() -> void:
	_drop("Could not reach the host. Check the address, and that the host is online (on Tailscale, if you use it).")


func _on_server_gone() -> void:
	_drop("The host closed the game. Your copy of the latest turn is kept under Load Game.")


func _drop(reason: String) -> void:
	if _peer == null:
		return
	var p := _peer
	_peer = null
	_connected = false
	_unwire()
	p.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	people = []
	closed.emit(reason)


func _on_peer_connected(_id: int) -> void:
	pass   # the peer introduces itself with _rpc_hello


func _on_peer_disconnected(id: int) -> void:
	if not is_host or not _names.has(id):
		return
	var who := String(_names[id])
	_names.erase(id)
	_update_people()
	_rpc_people.rpc(people)
	notice.emit("%s left the game." % who)


# ------------------------------------------------------------------- seats --

## Takes a free human player for this computer's person.
func take_seat(player_idx: int) -> void:
	if is_host:
		_host_claim(player_idx, my_name)
	elif _connected:
		_rpc_claim.rpc_id(1, player_idx)


func free_seat(player_idx: int) -> void:
	if is_host:
		_host_release(player_idx, my_name)
	elif _connected:
		_rpc_release.rpc_id(1, player_idx)


## True if this computer plays the player to move now.
func my_turn() -> bool:
	return session != null and active() and OnlineMatch.person_to_move(session.state) == my_name


func _host_claim(player_idx: int, who: String) -> void:
	# A seat whose person is not connected can be taken over.
	var holder := OnlineMatch.seat_of(session.state, player_idx)
	if holder != "" and holder != who and not _present(holder):
		OnlineMatch.release(session.state, player_idx)
	var why := OnlineMatch.claim(session.state, player_idx, who)
	if why != "":
		_tell(who, why)
		return
	_after_seats()


func _host_release(player_idx: int, who: String) -> void:
	if OnlineMatch.seat_of(session.state, player_idx) != who:
		return
	OnlineMatch.release(session.state, player_idx)
	_after_seats()


func _after_seats() -> void:
	_keep(session)
	_send_game()
	game_received.emit(session)


# ------------------------------------------------------------------- turns --

## The local player ended their turn (session.end_turn() already ran): the
## game goes to the host, or, on the host, on to everyone.
func finish_turn(game: GameSession) -> void:
	if is_host:
		_advance(game)
	elif _connected:
		var packed := OnlineMatch.pack(game.state)
		_rpc_handoff.rpc_id(1, packed["bytes"], int(packed["size"]))


## Host: computer players move, the game is kept and sent to everyone.
func _advance(game: GameSession) -> void:
	session = game
	OnlineMatch.play_computers(session)
	_keep(session)
	_send_game()
	game_received.emit(session)


# ---------------------------------------------------------------- messages --

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(person: String, compat: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	var who := OnlineMatch.clean_name(person)
	var why := ""
	if compat != compatibility():
		why = "The host runs a different version of the game. Both computers need the same build."
	elif who == "":
		why = "Enter a name first."
	elif who == my_name or _names.values().has(who):
		why = "Someone called %s is already in this game. Pick another name." % who
	if why != "":
		_rpc_refuse.rpc_id(id, why)
		get_tree().create_timer(0.5).timeout.connect(func():
			if _peer != null and multiplayer.get_peers().has(id):
				_peer.disconnect_peer(id))
		return
	_names[id] = who
	_update_people()
	_rpc_people.rpc(people)
	_send_game(id)
	notice.emit("%s joined the game." % who)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_claim(player_idx: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host and _names.has(id):
		_host_claim(player_idx, String(_names[id]))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_release(player_idx: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host and _names.has(id):
		_host_release(player_idx, String(_names[id]))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_handoff(bytes: PackedByteArray, raw_size: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host or not _names.has(id):
		return
	var who := String(_names[id])
	var d := OnlineMatch.unpack(bytes, raw_size)
	var why := "The game sent could not be read." if d.is_empty() else OnlineMatch.check_handoff(session.state, d, who)
	if why != "":
		_rpc_notice.rpc_id(id, why)
		_send_game(id)   # back to the host's game
		return
	var next := GameSession.from_state(data, GameState.from_dict(d, data))
	OnlineMatch.copy_seats(session.state, next.state)
	_advance(next)


@rpc("authority", "call_remote", "reliable")
func _rpc_game(bytes: PackedByteArray, raw_size: int) -> void:
	var d := OnlineMatch.unpack(bytes, raw_size)
	if d.is_empty() or not GameState.validate_save(d).is_empty():
		notice.emit("The host sent a game this computer could not read.")
		return
	var incoming := GameState.from_dict(d, data)
	if my_turn() and _same_turn(session.state, incoming):
		# Only the seats changed (someone joined): keep the turn being played.
		OnlineMatch.copy_seats(incoming, session.state)
		if my_turn():
			people_changed.emit()
			return
	session = GameSession.from_state(data, incoming)
	_keep(session)
	game_received.emit(session)


static func _same_turn(a: GameState, b: GameState) -> bool:
	return OnlineMatch.match_id(a) == OnlineMatch.match_id(b) and a.day == b.day and a.current_player == b.current_player


@rpc("authority", "call_remote", "reliable")
func _rpc_people(list: Array) -> void:
	people = list
	people_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_notice(text: String) -> void:
	notice.emit(text)


@rpc("authority", "call_remote", "reliable")
func _rpc_refuse(reason: String) -> void:
	_drop(reason)


# ----------------------------------------------------------------- helpers --

func _send_game(to_peer: int = 0) -> void:
	if not is_host or _peer == null:
		return
	var packed := OnlineMatch.pack(session.state)
	if to_peer != 0:
		_rpc_game.rpc_id(to_peer, packed["bytes"], int(packed["size"]))
		return
	for id in _sorted_peers():
		_rpc_game.rpc_id(id, packed["bytes"], int(packed["size"]))


func _tell(who: String, text: String) -> void:
	if who == my_name:
		notice.emit(text)
		return
	for id in _sorted_peers():
		if String(_names[id]) == who:
			_rpc_notice.rpc_id(id, text)


func _present(who: String) -> bool:
	return who == my_name or _names.values().has(who)


func _sorted_peers() -> Array:
	var ids := _names.keys()
	ids.sort()
	return ids


func _update_people() -> void:
	people = [{"name": my_name, "host": true}]
	for id in _sorted_peers():
		people.append({"name": String(_names[id]), "host": false})
	people_changed.emit()


func _keep(game: GameSession) -> void:
	if game != null and OnlineMatch.is_online(game.state):
		SaveSlots.save(game, OnlineMatch.save_slot(game.state), save_directory)


## Not gameplay randomness (never reaches the rules), so not GameRng.
static func _new_match_id() -> String:
	return Crypto.new().generate_random_bytes(6).hex_encode()


## Computers can play together only with the same game version and data.
func compatibility() -> String:
	return "%s/%d/%s" % [String(ProjectSettings.get_setting("application/config/version", "")),
		GameState.SAVE_VERSION, OnlineMatch.data_fingerprint()]
