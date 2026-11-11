extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _answer(screen: Node) -> void:
	await process_frame
	if not screen.panels.visible:
		push_error("incoming panel did not open")
		quit(1)
		return
	screen.panels.hide()
	screen.panels.incoming_choice.emit(true)
	await process_frame
	if not screen.panels.visible or screen.panels.last_result.is_empty():
		push_error("battle report did not open")
		quit(1)
		return
	screen.panels.hide()
	screen.panels.report_closed.emit()

func _run() -> void:
	var screen = load("res://src/ui/adventure_screen.gd").new()
	screen.show_menu_on_start = false
	root.add_child(screen)
	var s := GameSession.new_game(GameData.get_default(), "mournfield", 5, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "ashen"},
		{"type": "closed", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
	screen._start(s)
	screen._ai_playing = true
	screen.panels.settings_path = "user://enemy_turn_smoke.cfg"
	BattleViewer.set_watch_enabled(false, screen.panels.settings_path)
	var attacker := s.hero("hero_gaul")
	var defender := s.hero("hero_osric")
	defender.pos = attacker.pos + Vector2i(-3, 0)
	defender.army = Army.from_pairs([["pike_militia", 2]])
	(s.state.player(1)["fog"] as FogOfWar).reveal(defender.pos, 2)
	s.state.current_player = 1
	var ai := StrategicAI.new(s, 1)
	ai.battle_handler = screen._incoming_battle
	_answer(screen)
	await ai.play_turn_interactive()
	var result: Dictionary = screen.panels.last_result
	if not result.get("defender_fled", false) or not defender.alive or not defender.army.is_empty():
		push_error("flee was not applied")
		quit(1)
		return
	print("PASS incoming battle pauses for choice and report, then resumes")
	var scenario := GameSession.new_game(GameData.get_default(), "last_watch", 7)
	scenario.state.day = 7
	WaveDirector.on_day(scenario)
	scenario.hero("hero_watch").pos = Vector2i(18, 18)
	var commander := scenario.hero("watch_commander_0")
	commander.pos = Vector2i(23, 18)
	scenario.state.scenario_runtime["orders"][commander.id] = {"kind": "assault", "target": "town_last_watch", "targets": ["town_last_watch"]}
	scenario.state.current_player = 1
	var ordered_ai := StrategicAI.new(scenario, 1)
	ordered_ai.battle_handler = _ordered_attack.bind(scenario)
	await ordered_ai.play_turn_interactive()
	if ordered_calls < 1:
		push_error("ordered invasion did not await the human battle handler")
		quit(1)
		return
	print("PASS ordered invasion awaits the human battle handler")
	screen.queue_free()
	quit(0)


var ordered_calls := 0

func _ordered_attack(attacker_id: String, target_id: String, session: GameSession) -> Dictionary:
	await process_frame
	ordered_calls += 1
	var result := session.attack(attacker_id, target_id)
	session.hero(attacker_id).movement_left = 0
	return result
