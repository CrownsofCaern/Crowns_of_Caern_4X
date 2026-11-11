class_name TurnCurtain
extends ModalPanel
## Hot-seat hand-over: hides the map until the next human player is ready, so
## nobody sees another player's fog of war.

signal begin_pressed


func build(game_data: GameData, width: float = 460.0) -> void:
	super.build(game_data, width)
	# Opaque: the map behind belongs to the previous player.
	(get_child(0) as ColorRect).color = Color("#0b0a09")


func open(session: GameSession, notes: Array = []) -> void:
	_clear()
	var p := session.current_player()
	var swatch := ColorRect.new()
	swatch.color = Color(p["color"])
	swatch.custom_minimum_size = Vector2(0, 6)
	_body.add_child(swatch)
	_body.add_child(UiStyle.label(p["name"], 26, UiStyle.BRASS))
	_body.add_child(UiStyle.label("%s  ·  Week %d, Day %d" % [_data.factions[p["faction"]]["name"],
		session.state.week(), session.state.day_of_week()], 14, UiStyle.TEXT_DIM))
	for n in notes:
		_body.add_child(_wrapped(n, 14, UiStyle.WARN))
	_body.add_child(_wrapped("Hand over the controls. The map stays hidden until you begin.", 13, UiStyle.TEXT_DIM))
	_buttons([["Begin turn", func():
		hide()
		begin_pressed.emit()]])
	show()
	UiStyle.fade_in(self)
