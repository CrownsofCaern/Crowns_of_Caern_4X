class_name OnlinePanel
extends ModalPanel
## Online play: host the running game or join one by address ("connect"
## page), then pick the players you play and wait for your turn ("match"
## page). The match page is opaque: while another person moves, the map
## behind belongs to them.

signal host_requested(person: String, port: int)
signal join_requested(address: String, person: String)
signal take_requested(player_idx: int)
signal free_requested(player_idx: int)
signal leave_requested
signal closed

const SETTINGS := "user://online.cfg"

var net: NetSession
var _dim: ColorRect
var _name_edit: LineEdit
var _address_edit: LineEdit
var _page := ""
var _status := ""
var _notes: Array[String] = []


func build(game_data: GameData, width: float = 560.0) -> void:
	super.build(game_data, width)
	_dim = get_child(0) as ColorRect


## The connect page: host the game in progress (if any) or join one.
func open_connect(can_host: bool, message: String = "") -> void:
	_page = "connect"
	_dim.color = Color(0, 0, 0, 0.55)
	_clear()
	_body.add_child(UiStyle.label("Online Game", 24, UiStyle.BRASS))
	_body.add_child(_wrapped("Players take turns on their own computers. One computer hosts the game; the others join with its address. "
		+ "Over the internet, install Tailscale on every computer and join with the host's Tailscale address (100.x.y.z): no router settings needed.", 13, UiStyle.TEXT_DIM))
	if message != "":
		_body.add_child(_wrapped(message, 14, UiStyle.WARN))
	var cfg := _settings()
	_name_edit = _field("Your name", String(cfg.get_value("online", "name", "")), "The name the other players see")
	_body.add_child(UiStyle.section("Join a game", 16))
	_address_edit = _field("Host address", String(cfg.get_value("online", "address", "")),
		"The host's address, e.g. 100.101.102.103 (port %d unless you add :port)" % NetSession.DEFAULT_PORT)
	_body.add_child(UiStyle.section("Host a game", 16))
	_body.add_child(_wrapped("Hosts the game in progress: start a new game with human players (or load a save, also an online one) first, "
		+ "then host it here. Friends can join at any time, also later in the game.", 13, UiStyle.TEXT_DIM))
	_buttons([
		["Close", func():
			hide()
			closed.emit()],
		["Host this game", func():
			_remember()
			host_requested.emit(_name_edit.text, NetSession.DEFAULT_PORT), "", not can_host],
		["Join", func():
			_remember()
			join_requested.emit(_address_edit.text, _name_edit.text)],
	])
	show()
	UiStyle.fade_in(self)


## The match page: who plays whom, whose turn it is, and the host's address.
func open_match(status: String = "") -> void:
	_page = "match"
	if status != "":
		_status = status
	_dim.color = Color("#0b0a09")
	refresh()
	if not visible:
		show()
		UiStyle.fade_in(self)


func add_note(text: String) -> void:
	_notes.append(text)
	if _notes.size() > 5:
		_notes.remove_at(0)
	if visible and _page == "match":
		refresh()


func is_match_page() -> bool:
	return visible and _page == "match"


func refresh() -> void:
	if _page != "match":
		return
	_clear()
	_body.add_child(UiStyle.label("Online Game", 24, UiStyle.BRASS))
	var s: GameSession = net.session if net != null else null
	if s == null:
		_body.add_child(_wrapped(_status if _status != "" else "Connecting to the host...", 15, UiStyle.TEXT))
		_buttons([["Leave", func(): leave_requested.emit()]])
		return
	var st := s.state
	var mover := OnlineMatch.person_to_move(st)
	var line := ""
	if st.game_over:
		line = "The game is over."
	elif not bool(st.player(st.current_player)["is_human"]):
		line = "The computer players are moving..."
	elif mover == "":
		line = "Waiting for someone to take %s, who is to move." % st.player(st.current_player)["name"]
	elif mover == net.my_name:
		line = "Your turn as %s." % st.player(st.current_player)["name"]
	else:
		line = "Waiting for %s (%s)." % [mover, st.player(st.current_player)["name"]]
	_body.add_child(UiStyle.label("%s  ·  Week %d, Day %d" % [st.map.name, st.week(), st.day_of_week()], 14, UiStyle.TEXT_DIM))
	_body.add_child(_wrapped(line, 16, UiStyle.TEXT))
	if _status != "" and mover != net.my_name:
		_body.add_child(_wrapped(_status, 13, UiStyle.TEXT_DIM))
	_body.add_child(UiStyle.section("Players", 16))
	var here := {}
	for p in net.people:
		here[String(p["name"])] = true
	for row in OnlineMatch.seat_rows(st):
		_body.add_child(_seat_row(row, here))
	if OnlineMatch.seats_held(st, net.my_name).is_empty():
		_body.add_child(_wrapped("Take a player to play.", 13, UiStyle.WARN))
	var names := []
	for p in net.people:
		names.append(String(p["name"]) + (" (host)" if bool(p["host"]) else ""))
	_body.add_child(_wrapped("Connected: " + ", ".join(names), 13, UiStyle.TEXT_DIM))
	if net.is_host:
		var addrs := []
		for a in NetSession.local_addresses():
			addrs.append("%s (%s)" % [a["address"], a["label"]])
		_body.add_child(_wrapped("Others join with: %s, port %d." % [", ".join(addrs) if not addrs.is_empty() else "this computer's address",
			NetSession.DEFAULT_PORT], 13, UiStyle.TEXT_DIM))
	for n in _notes:
		_body.add_child(_wrapped(n, 13, UiStyle.WARN))
	_buttons([["Leave game", func(): leave_requested.emit(),
		"Close the connection. The latest turn stays saved under Load Game."]])


func _seat_row(row: Dictionary, here: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var swatch := ColorRect.new()
	swatch.color = Color(String(row["color"]))
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(swatch)
	var faction := String(_data.factions.get(String(row["faction"]), {}).get("name", row["faction"]))
	var who := String(row["seat"])
	var lbl := UiStyle.label("%s (%s)" % [row["name"], faction], 15, UiStyle.TEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(lbl)
	var held := "free"
	if who != "":
		held = who + ("" if here.has(who) else " (away)")
	line.add_child(UiStyle.label(held, 14, UiStyle.GOOD if here.has(who) else UiStyle.TEXT_DIM))
	var b := Button.new()
	b.custom_minimum_size = Vector2(90, 30)
	var idx := int(row["player"])
	if who == net.my_name:
		b.text = "Free"
		b.pressed.connect(func(): free_requested.emit(idx))
	else:
		b.text = "Take"
		# A seat whose person is away can be taken over (they lost the connection or stay away).
		b.disabled = who != "" and here.has(who)
		b.pressed.connect(func(): take_requested.emit(idx))
	line.add_child(b)
	return line


func _field(caption: String, value: String, tip: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := UiStyle.label(caption, 14, UiStyle.TEXT)
	lbl.custom_minimum_size.x = 130
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = value
	edit.tooltip_text = tip
	edit.max_length = 64
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	_body.add_child(row)
	return edit


func _settings() -> ConfigFile:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(SETTINGS):
		cfg.load(SETTINGS)
	return cfg


func _remember() -> void:
	var cfg := _settings()
	cfg.set_value("online", "name", _name_edit.text.strip_edges())
	cfg.set_value("online", "address", _address_edit.text.strip_edges())
	cfg.save(SETTINGS)
