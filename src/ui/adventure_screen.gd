extends Node2D
signal playtest_return_requested
## Adventure map controller: owns the GameSession, wires the MapView, HUD and
## battle panels together, and translates player intent into session commands.
## Also runs the game flow around the map: main menu, new-game setup, save and
## load slots, computer turns, the hot-seat hand-over and the end screen.

const MAP_ID := "ember_ford"

var data: GameData
var session: GameSession
var initial_session: GameSession
var editor_playtest := false
var save_directory := SaveSlots.DEFAULT_DIR
var selected_hero_id := ""
var map_view: MapView
var adventure_cursor: AdventureCursor
var hud: Hud
var panels: BattlePanels
var battle_viewer: BattleViewer
var encounter_dialog: EncounterDialog
var site_dialog: SiteDialog
var scenario_dialog: ScenarioDialog
var level_up: LevelUpDialog
var town_screen: TownScreen
var hero_screen: HeroScreen
var menu: MainMenu
var map_editor: MapEditorScreen
var _editor_previous_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var save_dialog: SaveLoadDialog
var game_over_dialog: GameOverDialog
var curtain: TurnCurtain
var sound_dialog: SoundDialog
var chapter_dialog: ChapterDialog
## Online play (host or join by address); idle unless a game is online.
var net: NetSession
var online_panel: OnlinePanel
## True while this computer plays its turn of an online game.
var _online_playing := false
var found_dialog: ArtifactFoundDialog
## Artifacts the hero gained in an encounter, shown once its result closes.
var _found_in_encounter: Array[String] = []
## The campaign being played, or null in a skirmish or a game loaded from a slot.
var campaign: Campaign = null
## Set to false before adding the node to skip the title screen (tools, tests).
var show_menu_on_start := true
var _game_over_shown := false
var _last_human := -1
var _pending_battle := ""
var _pending_encounter := ""
var _points_before := 0
var _busy := false
## Map pixel the camera looks at when the player scrolled away from the hero
## (minimap click, arrow keys); x < 0 follows the selected hero.
var _look_at := Vector2(-1, -1)
## Adventure map zoom: an index into MapCamera.LEVELS (kept for the session).
var zoom_level := MapCamera.DEFAULT_LEVEL
var _zoom_bar: HBoxContainer
var _zoom_label: Label
## The move being animated, for pickup and capture sounds as the hero arrives.
var _move_result: Dictionary = {}
## Floating card over a hostile army under the pointer, and the intel it shows
## (cached per hero, target and state revision: the quick forecast is not free).
var intel_tip: MapTip
var _intel: Dictionary = {}
var _intel_cache_key := ""
var _intel_rev := 0
var _forecast_title := ""
## True while computer players move: their own bookkeeping stays out of the log.
var _ai_playing := false
## What the players held when the last turn was handed on (see _turn_snapshot),
## so the next human hears what happened in between.
var _before_turns: Dictionary = {}


func _ready() -> void:
	TouchLayout.configure(get_window())
	if TouchGestures.touch_ui():
		get_tree().node_added.connect(_prepare_touch_control)
	data = initial_session.data if initial_session != null else GameData.get_default()
	RenderingServer.set_default_clear_color(Color("#0b0a09"))
	add_child(TouchTooltips.new())
	map_view = MapView.new()
	map_view.position = _view_origin()
	add_child(map_view)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.build(data)
	_build_zoom_bar(layer)
	panels = BattlePanels.new()
	layer.add_child(panels)
	panels.build(data)
	encounter_dialog = EncounterDialog.new()
	layer.add_child(encounter_dialog)
	encounter_dialog.build(data, 620)
	site_dialog = SiteDialog.new()
	layer.add_child(site_dialog)
	site_dialog.build(data, 620)
	site_dialog.rob_requested.connect(func(site_id: String):
		site_dialog.hide()
		_pending_battle = site_id
		_show_forecast())
	site_dialog.closed.connect(func():
		_refresh()
		_after_event())
	scenario_dialog = ScenarioDialog.new()
	layer.add_child(scenario_dialog)
	scenario_dialog.build(data, 620)
	scenario_dialog.closed.connect(func():
		_refresh()
		_after_event())
	scenario_dialog.focus_tile.connect(look_at_tile)
	found_dialog = ArtifactFoundDialog.new()
	layer.add_child(found_dialog)
	found_dialog.build(data, 600)
	level_up = LevelUpDialog.new()
	layer.add_child(level_up)
	level_up.build(data, 560)
	town_screen = TownScreen.new()
	layer.add_child(town_screen)
	town_screen.build_ui(data)
	town_screen.closed.connect(func():
		_set_busy(false)
		_refresh())
	town_screen.changed.connect(_refresh)
	hero_screen = HeroScreen.new()
	layer.add_child(hero_screen)
	hero_screen.build(data, 760)
	hero_screen.closed.connect(func():
		_set_busy(false)
		_refresh())
	hero_screen.changed.connect(_refresh)
	hero_screen.learn_pressed.connect(func():
		_set_busy(false)
		_open_level_up())

	map_view.tile_clicked.connect(_on_tile_clicked)
	map_view.tile_hovered.connect(_on_tile_hovered)
	intel_tip = MapTip.new()
	layer.add_child(intel_tip)
	battle_viewer = BattleViewer.new()
	layer.add_child(battle_viewer)
	battle_viewer.build()
	map_view.cancel_requested.connect(_cancel_route)
	map_view.hero_stepped.connect(_on_hero_stepped)
	map_view.zoom_requested.connect(func(steps: int, at: Vector2): zoom_by(steps, at))
	map_view.pan_requested.connect(_pan)
	hud.end_turn_pressed.connect(_end_turn)
	hud.save_pressed.connect(func(): _open_saves("save"))
	hud.load_pressed.connect(func(): _open_saves("load"))
	hud.menu_pressed.connect(_open_menu)
	hud.town_pressed.connect(_open_town)
	hud.next_hero_pressed.connect(_next_hero)
	hud.hero_screen_pressed.connect(_open_hero_screen)
	hud.objectives_pressed.connect(_open_objectives)
	hud.minimap.tile_picked.connect(look_at_tile)
	panels.attack_confirmed.connect(_on_attack_confirmed)
	panels.attack_cancelled.connect(func(): _set_busy(false))
	panels.scout_requested.connect(_on_forecast_scout)
	panels.orders_changed.connect(_on_forecast_orders)
	panels.report_closed.connect(func():
		if not _ai_playing:
			_after_event())
	panels.watch_requested.connect(_watch_again)
	hud.hero_selected.connect(_select_hero)
	hud.skills_pressed.connect(_open_level_up)
	encounter_dialog.choice_made.connect(_on_encounter_choice)
	encounter_dialog.result_closed.connect(_on_encounter_result_closed)
	level_up.skill_chosen.connect(_on_skill_chosen)
	level_up.closed.connect(func(): _set_busy(false))

	var flow_layer := CanvasLayer.new()
	flow_layer.layer = 5
	add_child(flow_layer)
	var dialog_layer := CanvasLayer.new()
	dialog_layer.layer = 11   # above the main menu, which opens it for loading
	add_child(dialog_layer)
	save_dialog = SaveLoadDialog.new()
	dialog_layer.add_child(save_dialog)
	save_dialog.build(data, 760)
	save_dialog.slot_chosen.connect(_on_slot_chosen)
	save_dialog.closed.connect(func(): _set_busy(false))
	net = NetSession.new(data)
	add_child(net)
	online_panel = OnlinePanel.new()
	dialog_layer.add_child(online_panel)
	online_panel.build(data, 620)
	online_panel.net = net
	online_panel.host_requested.connect(_host_online)
	online_panel.join_requested.connect(_join_online)
	online_panel.take_requested.connect(func(i: int): net.take_seat(i))
	online_panel.free_requested.connect(func(i: int): net.free_seat(i))
	online_panel.leave_requested.connect(_leave_online)
	online_panel.closed.connect(func():
		map_view.visible = true
		menu.open(session != null and not session.state.game_over, editor_playtest))
	net.game_received.connect(_on_online_game)
	net.people_changed.connect(online_panel.refresh)
	net.notice.connect(func(t: String):
		online_panel.add_note(t)
		hud.log_message("[color=#e0b450]%s[/color]" % t))
	net.closed.connect(_on_online_closed)
	sound_dialog = SoundDialog.new()
	dialog_layer.add_child(sound_dialog)
	sound_dialog.build(data, 520)
	sound_dialog.closed.connect(func():
		if not menu.visible:
			_set_busy(false))
	game_over_dialog = GameOverDialog.new()
	flow_layer.add_child(game_over_dialog)
	game_over_dialog.build(data, 640)
	game_over_dialog.main_menu_pressed.connect(_open_menu)
	game_over_dialog.view_map_pressed.connect(func(): _set_busy(false))
	game_over_dialog.campaign_pressed.connect(_campaign_journey_or_retry)
	chapter_dialog = ChapterDialog.new()
	flow_layer.add_child(chapter_dialog)
	chapter_dialog.build(data, 560)
	chapter_dialog.begin_pressed.connect(func():
		_set_busy(false)
		_on_turn_changed())
	curtain = TurnCurtain.new()
	flow_layer.add_child(curtain)
	curtain.build(data, 460)
	curtain.begin_pressed.connect(_begin_human_turn)
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menu = MainMenu.new()
	menu_layer.add_child(menu)
	menu.build(data)
	menu.start_requested.connect(start_new_game)
	menu.load_requested.connect(func(): _open_saves("load"))
	menu.online_requested.connect(_open_online)
	menu.resume_requested.connect(func():
		menu.hide()
		AudioManager.set_music("map")
		_set_busy(false))
	menu.campaign_requested.connect(start_campaign)
	menu.quit_requested.connect(_quit)
	menu.sound_requested.connect(func():
		_set_busy(true)
		sound_dialog.open())
	menu.editor_requested.connect(_open_editor)
	menu.editor_return_requested.connect(func(): playtest_return_requested.emit())
	if editor_playtest:
		var test_layer := CanvasLayer.new()
		test_layer.layer = 14
		add_child(test_layer)
		var return_button := Button.new()
		return_button.text = "Return to Editor"
		return_button.position = Vector2(12, Hud.TOP_H + 8)
		return_button.custom_minimum_size = Vector2(170, 38)
		return_button.theme = UiStyle.make_theme()
		return_button.tooltip_text = "Discard playtest progress and return to the current draft"
		return_button.pressed.connect(func(): playtest_return_requested.emit())
		test_layer.add_child(return_button)
	UiStyle._restyle(self)
	adventure_cursor = AdventureCursor.new()
	adventure_cursor.map_view = map_view
	add_child(adventure_cursor)

	# Command line: --map=<id> and/or --seed=<n> start a game directly.
	var seed_value := int(Time.get_unix_time_from_system())
	var map_id := MAP_ID
	var direct := not show_menu_on_start
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
			direct = true
		elif arg.begins_with("--map="):
			map_id = arg.trim_prefix("--map=")
			direct = true
	if initial_session != null:
		_start(initial_session)
		initial_session = null
		_on_turn_changed()
		hud.log_message("Playtest: saves are temporary. Return to Editor keeps your draft.")
	elif direct:
		start_new_game(map_id, seed_value, {"standard_start": true})
	else:
		menu.open(false)


func _quit() -> void:
	if editor_playtest:
		playtest_return_requested.emit()
		return
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()


func start_new_game(map_id: String, seed_value: int, setup: Dictionary) -> void:
	if editor_playtest:
		return
	_leave_online(false)
	var candidate := GameSession.new_game(data, map_id, seed_value, setup)
	if candidate == null:
		menu.show_launch_error("This map could not be started. Reopen setup or check the map in the editor.")
		return
	campaign = null
	_start(candidate)
	hud.log_message("[color=#c9a24a]%s.[/color] %s" % [session.state.map.name, TouchGestures.controls_hint()])
	_on_turn_changed()


func _start(s: GameSession) -> void:
	town_screen.hide()
	hero_screen.hide()
	menu.hide()
	game_over_dialog.hide()
	curtain.hide()
	save_dialog.hide()
	_set_busy(false)
	session = s
	AudioManager.set_faction(String(session.current_player().get("faction", "")))
	AudioManager.set_music("map")
	hud.clear_log()
	_game_over_shown = false
	_last_human = -1
	_before_turns = {}
	# Computer players' own bookkeeping stays out of the humans' log; what
	# matters to the next human is reported by _report_turn_events().
	session.message.connect(func(t):
		if not _ai_playing and session.current_player()["is_human"]:
			hud.log_message(t))
	map_view.bind(session)
	hud.minimap.bind(session)
	_look_at = Vector2(-1, -1)
	selected_hero_id = ""
	_ensure_selection()
	_refresh()


func _human_count() -> int:
	var n := 0
	for p in session.state.players:
		if p["is_human"] and not p["defeated"]:
			n += 1
	return n


## After the turn passed: computer players move, then the next human gets the
## map (behind the hot-seat curtain when several humans share the screen).
func _on_turn_changed() -> void:
	if not session.state.game_over and not session.current_player()["is_human"]:
		_ai_playing = true
		_set_busy(true)
		var turns := 0
		while not session.state.game_over and not session.current_player()["is_human"] and turns < 64:
			var ai := StrategicAI.new(session, session.state.current_player)
			ai.battle_handler = _incoming_battle
			await ai.play_turn_interactive()
			if not session.state.game_over:
				session.end_turn()
			turns += 1
		_ai_playing = false
	_report_turn_events()
	if session.state.game_over:
		_refresh()
		_check_game_over()
		return
	map_view.clear_path()
	selected_hero_id = ""
	_look_at = Vector2(-1, -1)
	var cur := session.state.current_player
	var notes := []
	var left := VictoryRules.days_left(session, cur)
	if left > 0:
		notes.append("You hold no town. Take one within %d day%s or your cause is lost." % [left, "" if left == 1 else "s"])
	if _human_count() > 1 and _last_human != cur:
		_set_busy(true)
		map_view.visible = false
		_last_human = cur
		_refresh()
		curtain.open(session, notes)
		return
	_last_human = cur
	for n in notes:
		hud.log_message("[color=#e0b450]%s[/color]" % n)
	_begin_human_turn()


## Pause the computer before it attacks a human, then resume after the report.
func _incoming_battle(attacker_id: String, target_id: String) -> Dictionary:
	var attacker := session.hero(attacker_id)
	var target := session.battle_target(target_id)
	var defender: Hero = target["hero"]
	var setup := session.battle_setup(attacker_id, target_id)
	var can_flee := defender != null and session.flee_destination(defender.id, target["pos"]) != Vector2i(-1, -1)
	AudioManager.play("battle_prepare")
	var forecast := {}
	if not session.odds_hidden():
		forecast = CombatPredictor.new(data).predict(setup)
	panels.show_incoming(setup, can_flee, forecast)
	var flee: bool = await panels.incoming_choice
	AudioManager.play("battle_start")
	var result := session.attack(attacker.id, target_id, flee)
	if BattleViewer.watch_enabled(panels.settings_path) and result.has("log"):
		await battle_viewer.play(result, attacker.name, 1, panels.settings_path)
	AudioManager.play_stinger("battle_victory" if result["winner"] == 1 else "battle_defeat")
	panels.show_report(result, 1)
	await panels.report_closed
	return result


## Day-log warning for each enemy hero that could reach one of the current
## human's towns within game_rules threat_warning_days days.
func _warn_threats() -> void:
	for th in session.town_threats(session.state.current_player):
		hud.log_message("[color=#e0b450]%s could reach %s %s.[/color]" % [th["hero"], th["town"],
			"on its next move" if int(th["days"]) <= 1 else "within %d days" % int(th["days"])])


## What the players hold now: {day, towns: {player: [town ids]}, heroes:
## {player: [hero ids]}, defeated: [bool]}.
func _turn_snapshot() -> Dictionary:
	var towns := {}
	var heroes := {}
	var defeated := []
	for i in session.state.players.size():
		towns[i] = session.towns_of(i).map(func(t): return t["id"])
		heroes[i] = session.state.heroes_of(i).map(func(h): return h.id)
		defeated.append(bool(session.state.player(i)["defeated"]))
	return {"day": session.state.day, "towns": towns, "heroes": heroes, "defeated": defeated}


## Tells the human who is about to move (the last one, if the game ended)
## what happened since the turn was handed on: the new day and week, their
## towns taken and heroes fallen, and rivals driven out of the game. The
## session's own messages from those turns are not shown (they belong to
## whoever was moving).
func _report_turn_events() -> void:
	if _before_turns.is_empty():
		return
	var b := _before_turns
	_before_turns = {}
	var st := session.state
	var me := st.current_player
	if not st.player(me)["is_human"]:
		me = _last_human
	if me < 0:
		return
	if st.day != int(b["day"]):
		hud.log_message("Day %d begins." % st.day)
		if st.day_of_week() == 1:
			hud.log_message("Week %d begins. Creatures in the dwellings have multiplied." % st.week())
	_report_news(me)
	var lost_hero := false
	for id in b["heroes"].get(me, []):
		var h := session.hero(id)
		if h != null and not h.alive:
			lost_hero = true
			hud.log_message("[color=#c0392b]%s has fallen.[/color]" % h.name)
	if lost_hero:
		AudioManager.play("hero_fallen")
	for id in b["towns"].get(me, []):
		var t := session.town(id)
		if int(t["owner"]) != me:
			AudioManager.play("town_lost")
			hud.log_message("[color=#c0392b]%s has fallen to %s.[/color]" % [t["name"],
				st.player(int(t["owner"]))["name"] if int(t["owner"]) >= 0 else "the wilds"])
	for i in st.players.size():
		if i != me and st.player(i)["defeated"] and not b["defeated"][i]:
			hud.log_message("[color=#e0b450]%s is out of the game.[/color]" % st.player(i)["name"])


## The week's omen and this player's fortunes since their last turn.
func _report_news(player_idx: int) -> void:
	for line in session.take_news(player_idx):
		hud.log_message("[color=#e0b450]%s[/color]" % line)


func _begin_human_turn() -> void:
	_report_news(session.state.current_player)
	map_view.visible = true
	AudioManager.set_faction(String(session.current_player().get("faction", "")))
	AudioManager.set_music("map")
	if session.state.day > 1:
		AudioManager.play("week_begin" if session.state.day_of_week() == 1 else "turn_begin")
	_set_busy(false)
	_ensure_selection()
	_warn_threats()
	_refresh()
	SaveSlots.save(session, SaveSlots.AUTOSAVE, save_directory)
	if campaign != null:
		campaign.save_progress(session)


## Shows the end screen once, when the game has just ended.
func _check_game_over() -> bool:
	if session == null or not session.state.game_over:
		return false
	if not _game_over_shown:
		_game_over_shown = true
		map_view.visible = true
		map_view.clear_path()
		_set_busy(true)
		var result := session.game_result()
		AudioManager.play_stinger("game_victory" if result["human_won"] else "game_defeat")
		game_over_dialog.open(result, _finish_campaign_chapter(result["human_won"]))
	return true


# --------------------------------------------------------------- campaign --

## From the main menu: continue a campaign's saved progress (the chapter in
## progress, or the next one), or begin it afresh.
func start_campaign(campaign_id: String, fresh: bool) -> void:
	if editor_playtest:
		return
	campaign = null if fresh else Campaign.load_progress(data, campaign_id)
	if campaign == null:
		campaign = Campaign.start(data, campaign_id, int(Time.get_unix_time_from_system()) & 0x7FFFFFFF)
		campaign.save_progress()
	var resumed := campaign.resume(data)
	if resumed != null:
		_start(resumed)
		_last_human = resumed.state.current_player
		hud.log_message("[color=#c9a24a]%s[/color], chapter %d resumed: day %d." % [
			campaign.definition(data)["name"], campaign.chapter + 1, resumed.state.day])
		# The briefing (and its illustration) again, so a resumed chapter opens
		# the same way a fresh one does.
		_open_chapter_briefing(resumed, "Resume on day %d" % resumed.state.day)
		return
	_play_campaign_chapter()


## A victory returns through the journey painting so the hero travels to the next stop.
## A loss retains the existing retry path and its unchanged campaign progress.
func _campaign_journey_or_retry() -> void:
	if campaign != null and session != null and session.state.game_over and session.game_result()["human_won"]:
		_open_menu()
		menu.show_campaign_journey(campaign.campaign_id, campaign)
	else:
		_play_campaign_chapter()


## Starts the campaign's current chapter behind its briefing.
func _play_campaign_chapter() -> void:
	if campaign == null or campaign.is_finished(data):
		_open_menu()
		return
	var s := campaign.begin_chapter(data)
	campaign.save_progress(s)
	_start(s)
	var ch := campaign.current_chapter(data)
	hud.log_message("[color=#c9a24a]%s.[/color] %s" % [ch["name"], ch.get("text", "")])
	_open_chapter_briefing(s, "Take the field")


## The current chapter's briefing over the map, with its illustration when it
## has one; closing it starts (or resumes) play.
func _open_chapter_briefing(s: GameSession, button: String) -> void:
	var def := campaign.definition(data)
	var ch := campaign.current_chapter(data)
	var lines := []
	for para in String(ch.get("intro", ch.get("text", ""))).split("\n\n", false):
		lines.append(para)
	lines.append("Win by holding every town on the map." if s.state.players.size() == 1 else
		"Win by driving every rival from the land.")
	if s.tier_cap() > 0:
		lines.append("Towns can raise creatures up to tier %d in this chapter; higher dwellings open in later chapters." % s.tier_cap())
	var heroes := []
	for hid in def["heroes"]:
		var h := s.hero(hid)
		if h != null:
			heroes.append("%s (level %d)" % [h.name, h.level])
	if not heroes.is_empty():
		var carry: Dictionary = def.get("carry", {})
		var gear: String = ("everything they wear and up to %d packed artifacts" if bool(carry.get("keep_worn", false)) else "up to %d artifacts") \
			% int(carry.get("max_artifacts", 4))
		lines.append("Veterans: %s. Their levels, skills and %s carry over; armies do not. Heroes cannot rise above level %d here." % [
			", ".join(heroes), gear, int(ch.get("level_cap", 0))])
	_set_busy(true)
	chapter_dialog.open(ch["name"], "%s  ·  chapter %d of %d" % [def["name"], campaign.chapter + 1, def["chapters"].size()], lines,
		button, CampaignArt.texture(campaign.campaign_id, String(ch["id"])))


## Records the finished chapter in the campaign and describes it for the end
## screen ({} outside a campaign).
func _finish_campaign_chapter(won: bool) -> Dictionary:
	if campaign == null:
		return {}
	var name: String = campaign.current_chapter(data).get("name", "")
	var art := CampaignArt.texture(campaign.campaign_id, String(campaign.current_chapter(data).get("id", "")))
	var outro: String = campaign.current_chapter(data).get("outro", "")
	var res := campaign.complete_chapter(data, session, won)
	campaign.save_progress()
	if not res["ok"]:
		return {}
	if not won:
		return {"title": "%s is lost" % name, "lines": ["Your veterans keep what they had before this chapter."],
			"action": "Retry chapter"}
	var lines := []
	for para in outro.split("\n\n", false):
		lines.append(para)
	for hid in campaign.definition(data)["heroes"]:
		if not campaign.roster.has(hid):
			continue
		var rec: Dictionary = campaign.roster[hid]
		var line := "%s: level %d" % [rec["name"], int(rec["level"])]
		var kept: Array = res["kept"].get(hid, [])
		if not kept.is_empty():
			line += ", carries %s" % ", ".join(kept.map(func(a): return data.artifacts[a]["name"]))
		var dropped: Array = res["dropped"].get(hid, [])
		if not dropped.is_empty():
			line += "; leaves behind %s" % ", ".join(dropped.map(func(a): return data.artifacts[a]["name"]))
		lines.append(line + ".")
	if res["finished"]:
		lines.append("The campaign is complete.")
		return {"title": "%s is won" % name, "lines": lines, "action": "", "art": art}
	lines.append("Next: %s." % campaign.current_chapter(data)["name"])
	return {"title": "%s is won" % name, "lines": lines, "action": "Next chapter", "art": art}


func _open_menu() -> void:
	if session != null and not menu.visible:
		_set_busy(true)
	menu.open(session != null and not session.state.game_over, editor_playtest)


func _open_editor() -> void:
	if editor_playtest:
		playtest_return_requested.emit()
		return
	if map_editor != null and map_editor.visible:
		return
	_editor_previous_process_mode = process_mode
	# Suspend game input, presentation and bound tweens. The editor explicitly
	# processes independently; autoload audio remains available.
	process_mode = Node.PROCESS_MODE_DISABLED
	_set_busy(true)
	menu.hide()
	map_view.hide()
	hud.hide()
	_zoom_bar.hide()
	if map_editor == null:
		var editor_layer := CanvasLayer.new()
		editor_layer.layer = 12
		add_child(editor_layer)
		map_editor = MapEditorScreen.new()
		map_editor.process_mode = Node.PROCESS_MODE_ALWAYS
		editor_layer.add_child(map_editor)
		map_editor.build(data)
		map_editor.quit_requested.connect(_quit)
		map_editor.closed.connect(func():
			process_mode = _editor_previous_process_mode
			map_view.show()
			hud.show()
			_zoom_bar.visible = session != null
			menu.open(session != null and not session.state.game_over))
	map_editor.open()


func _open_saves(mode: String) -> void:
	if session == null and mode == "save":
		return
	if _busy and not menu.visible:
		return
	_set_busy(true)
	save_dialog.open(data, mode, session != null, save_directory, editor_playtest)


func _on_slot_chosen(mode: String, slot: String) -> void:
	if mode == "save":
		var err := SaveSlots.save(session, slot, save_directory)
		hud.log_message("Game saved to slot %s." % slot if err == OK else "Save failed (%s)." % error_string(err))
		save_dialog.open(data, "save", true, save_directory, editor_playtest)
		return
	var s := SaveSlots.load_slot(data, slot, save_directory)
	if s == null:
		hud.log_message("That save could not be read.")
		return
	_leave_online(false)
	# A campaign chapter keeps its campaign, whichever slot it was saved to.
	campaign = null if editor_playtest else Campaign.of_session(data, s)
	_start(s)
	_last_human = s.state.current_player
	hud.log_message("Game loaded: %s, day %d." % [s.state.map.name, s.state.day])
	if s.state.game_over:
		_game_over_shown = true
	elif not s.current_player()["is_human"]:
		_on_turn_changed()


func _ensure_selection() -> void:
	var h := _hero()
	if h != null and h.alive and h.owner == session.state.current_player:
		return
	var heroes := session.state.heroes_of(session.state.current_player)
	selected_hero_id = heroes[0].id if not heroes.is_empty() else ""


func _select_hero(hero_id: String) -> void:
	if _busy:
		return
	selected_hero_id = hero_id
	_look_at = Vector2(-1, -1)
	map_view.clear_path()
	_refresh()


func _hero() -> Hero:
	return session.hero(selected_hero_id) if selected_hero_id != "" else null


func _refresh() -> void:
	if not _ai_playing and session.current_player()["is_human"]:
		_report_news(session.state.current_player)
	_intel_rev += 1
	if session.current_player()["is_human"]:
		UiStyle.apply_faction(self, String(session.current_player()["faction"]))
	_ensure_selection()
	map_view.selected_hero_id = selected_hero_id
	_show_planned_route()
	map_view.threatened = []
	if session.current_player()["is_human"] and not session.state.game_over:
		for th in session.town_threats(session.state.current_player):
			map_view.threatened.append(AdventureMap.object_pos(session.town(th["town_id"])))
	hud.refresh(session, _hero())
	_keep_hero_in_view()
	map_view.refresh()


## Maps larger than the window scroll so that the selected hero stays centred
## where possible, unless the player looked elsewhere (minimap, arrow keys).
func _keep_hero_in_view() -> void:
	var view := _view_size()
	var map_px := _map_px()
	var zoom := MapCamera.zoom_of(zoom_level)
	var h := _hero()
	var focus := map_px * 0.5
	if _look_at.x >= 0.0:
		focus = _look_at
	elif h != null:
		focus = map_view.center_px(h.pos)
	var origin := MapCamera.map_origin(view, map_px, focus, zoom)
	map_view.position = origin + _view_origin()
	hud.minimap.view_rect = MapCamera.visible_cells(view, Vector2i(session.state.map.width, session.state.map.height), origin, zoom)
	hud.minimap.queue_redraw()
	# The map moved under a still pointer: hover info, tips and cursor follow.
	var mouse := get_viewport().get_mouse_position()
	if map_view.input_enabled and _view_rect().has_point(mouse):
		map_view.hover_at(mouse)


func _view_size() -> Vector2:
	var m := Hud.map_margins()
	return get_viewport_rect().size - Vector2(m.x + m.z, m.y + m.w)


## Top-left corner of the map's view area (below the top bar, right of a notch).
func _view_origin() -> Vector2:
	var m := Hud.map_margins()
	return Vector2(m.x, m.y)


## The map's view area on screen (between the top bar, side panel and log).
func _view_rect() -> Rect2:
	return Rect2(_view_origin(), _view_size())


func _map_px() -> Vector2:
	return Vector2(session.state.map.width, session.state.map.height) * MapView.TILE


## Map pixel at the middle of the view right now.
func _current_focus() -> Vector2:
	return MapCamera.focus_of(_view_size(), map_view.position - _view_origin(), MapCamera.zoom_of(zoom_level))


## Scrolls the map to a cell without changing the selection (minimap clicks).
func look_at_tile(t: Vector2i) -> void:
	if session == null:
		return
	_look_at = map_view.center_px(t)
	_keep_hero_in_view()


## Arrow keys scroll the map by a few cells (more cells when zoomed out, so a
## key press moves the picture by the same amount at every zoom).
func _scroll(dir: Vector2) -> void:
	_pan(dir * MapView.TILE * 3)


## Scrolls the map by `delta` screen pixels (arrow keys, trackpad swipes).
func _pan(delta: Vector2) -> void:
	if session == null or _busy:
		return
	intel_tip.hide()
	var zoom := MapCamera.zoom_of(zoom_level)
	_look_at = MapCamera.clamp_focus(_current_focus() + delta / zoom, _view_size(), _map_px(), zoom)
	_keep_hero_in_view()


## Zooms `steps` levels closer (negative: farther). With a screen point (the
## pointer), the map spot under it stays put; otherwise the view centre does,
## and a map that follows the hero keeps following it.
func zoom_by(steps: int, at: Variant = null) -> void:
	set_zoom_level(MapCamera.stepped(zoom_level, steps), at)


func set_zoom_level(level: int, at: Variant = null) -> void:
	level = clampi(level, 0, MapCamera.LEVELS.size() - 1)
	if session == null or level == zoom_level:
		_update_zoom_bar()
		return
	var view := _view_size()
	var old_zoom := MapCamera.zoom_of(zoom_level)
	var new_zoom := MapCamera.zoom_of(level)
	var origin := map_view.position - _view_origin()
	if at is Vector2 and _view_rect().has_point(at):
		var anchor: Vector2 = at - _view_origin()
		var point := (anchor - origin) / old_zoom
		_look_at = MapCamera.clamp_focus(MapCamera.focus_for_anchor(point, anchor, view, new_zoom), view, _map_px(), new_zoom)
	elif _look_at.x >= 0.0:
		_look_at = MapCamera.clamp_focus(MapCamera.focus_of(view, origin, old_zoom), view, _map_px(), new_zoom)
	zoom_level = level
	map_view.set_zoom(new_zoom)
	_update_zoom_bar()
	_keep_hero_in_view()


## Small zoom buttons in the bottom-right corner of the map view.
func _build_zoom_bar(layer: CanvasLayer) -> void:
	_zoom_bar = HBoxContainer.new()
	_zoom_bar.theme = UiStyle.make_theme()
	_zoom_bar.add_theme_constant_override("separation", 2)
	_zoom_bar.anchor_left = 1.0
	_zoom_bar.anchor_right = 1.0
	_zoom_bar.anchor_top = 1.0
	_zoom_bar.anchor_bottom = 1.0
	_zoom_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_zoom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_zoom_bar.offset_right = -Hud.map_margins().z - 8
	_zoom_bar.offset_bottom = -Hud.map_margins().w - 8
	layer.add_child(_zoom_bar)
	var out := Button.new()
	out.text = "−"
	out.tooltip_text = "Zoom out (- or mouse wheel)"
	out.focus_mode = Control.FOCUS_NONE
	out.custom_minimum_size = Vector2(TouchLayout.MIN_TARGET, TouchLayout.MIN_TARGET) if TouchGestures.touch_ui() else Vector2(30, 30)
	out.pressed.connect(func(): zoom_by(-1))
	_zoom_bar.add_child(out)
	_zoom_label = UiStyle.label("", 13)
	_zoom_label.custom_minimum_size = Vector2(40, 30)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zoom_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_zoom_label.tooltip_text = "Map zoom. Wheel or +/- to change, 0 to reset."
	_zoom_bar.add_child(_zoom_label)
	var closer := Button.new()
	closer.text = "+"
	closer.tooltip_text = "Zoom in (+ or mouse wheel)"
	closer.focus_mode = Control.FOCUS_NONE
	closer.custom_minimum_size = Vector2(TouchLayout.MIN_TARGET, TouchLayout.MIN_TARGET) if TouchGestures.touch_ui() else Vector2(30, 30)
	closer.pressed.connect(func(): zoom_by(1))
	_zoom_bar.add_child(closer)
	_zoom_bar.set_meta("out", out)
	_zoom_bar.set_meta("in", closer)
	_update_zoom_bar()


func _update_zoom_bar() -> void:
	if _zoom_bar == null:
		return
	var z := MapCamera.zoom_of(zoom_level)
	_zoom_label.text = ("%dx" % int(z)) if z >= 1.0 else ("1/%dx" % int(roundf(1.0 / z)))
	(_zoom_bar.get_meta("out") as Button).disabled = zoom_level <= 0
	(_zoom_bar.get_meta("in") as Button).disabled = zoom_level >= MapCamera.LEVELS.size() - 1


func _set_busy(b: bool) -> void:
	_busy = b
	map_view.input_enabled = not b
	if b and intel_tip != null:
		intel_tip.hide()


# ------------------------------------------------ hover intel and scouting --

func _on_tile_hovered(t: Vector2i) -> void:
	hud.show_tile(session, t)
	_update_intel_tip(t)


## The hostile target under the pointer that the current human can see, or "".
func _hovered_target(t: Vector2i) -> String:
	if session == null or session.state.game_over or not session.current_player()["is_human"]:
		return ""
	if not session.state.map.in_bounds(t) or not (session.current_player()["fog"] as FogOfWar).is_explored(t):
		return ""
	return session.hostile_target_at(t, session.state.current_player)


## The hover card: what is on the tile (any structure or hero) and, for a
## hostile army, its troops and the odds for the selected hero.
func _update_intel_tip(t: Vector2i) -> void:
	if session == null or _busy or session.state.game_over or not session.current_player()["is_human"]:
		intel_tip.hide()
		return
	var h := _hero()
	var info := MapTipInfo.describe(session, t, h)
	var target := _hovered_target(t)
	var intel := {}
	if target != "" and h != null and h.alive:
		var key := "%s|%s|%d" % [h.id, target, _intel_rev]
		if key != _intel_cache_key:
			_intel = session.intel(h.id, target)
			_intel_cache_key = key
		intel = _intel
	var bounds := _view_rect()
	intel_tip.show_card(info, intel, get_viewport().get_mouse_position(), bounds)


## S: the selected hero sends a scout to the hostile army under the pointer.
func _scout_hovered() -> void:
	var h := _hero()
	var target := _hovered_target(map_view.hovered)
	if h == null or target == "":
		hud.log_message("Point at an enemy army, then press S to send a scout.")
		return
	_send_scout(h, target)
	_update_intel_tip(map_view.hovered)


func _send_scout(h: Hero, target: String) -> bool:
	var r := session.scout(h.id, target)
	if not r["ok"]:
		hud.log_message("[color=#d96a52]No scout:[/color] %s" % r["reason"])
		return false
	AudioManager.play("ui_click")
	_refresh()
	return true


## The forecast's Send scout button: scout the pending target and show the
## forecast again with what the scouts found.
func _on_forecast_scout() -> void:
	var h := _hero()
	if h == null or _pending_battle == "" or not _send_scout(h, _pending_battle):
		return
	_show_forecast(_forecast_title)


## The forecast's order pickers: give the orders and forecast again.
func _on_forecast_orders(orders: Dictionary) -> void:
	var h := _hero()
	if h == null or _pending_battle == "" or not session.set_battle_orders(h.id, orders):
		return
	_show_forecast(_forecast_title)


## Shows the forecast for the pending battle; title "" names the enemy army.
func _show_forecast(title: String = "") -> void:
	var h := _hero()
	var pred := session.preview_battle(h.id, _pending_battle)
	_forecast_title = title
	pred["scout_cost"] = session.scout_cost(h.id)
	pred["scout_reason"] = session.can_scout(h.id, _pending_battle)
	pred["orders"] = session.order_choices(h.id)
	panels.show_forecast(title if title != "" else String(pred["enemy"]["name"]), pred)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	if event.keycode == KEY_ESCAPE and session != null and not menu.visible and not _busy:
		_open_menu()
		return
	if _busy or session == null or menu.visible:
		return
	match event.keycode:
		KEY_M:
			AudioManager.set_muted(not AudioManager.is_muted())
			hud.log_message("Sound %s." % ("muted" if AudioManager.is_muted() else "on"))
		KEY_E:
			_end_turn()
		KEY_F5:
			_open_saves("save")
		KEY_F9:
			_open_saves("load")
		KEY_T:
			_open_town()
		KEY_H:
			_open_hero_screen()
		KEY_LEFT:
			_scroll(Vector2.LEFT)
		KEY_RIGHT:
			_scroll(Vector2.RIGHT)
		KEY_UP:
			_scroll(Vector2.UP)
		KEY_DOWN:
			_scroll(Vector2.DOWN)
		KEY_C:
			_look_at = Vector2(-1, -1)
			_refresh()
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			zoom_by(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_by(-1)
		KEY_0, KEY_KP_0:
			set_zoom_level(MapCamera.DEFAULT_LEVEL)
		KEY_TAB:
			_next_hero()
		KEY_S:
			_scout_hovered()
		KEY_SPACE:
			var h := _hero()
			if h != null and h.planned_destination != Vector2i(-1, -1):
				var plan := session.plan_path(h.id, h.planned_destination)
				if plan["path"].is_empty():
					hud.log_message("The planned destination is currently unreachable.")
				else:
					_execute_move(h.planned_destination)


func _cancel_route() -> void:
	var h := _hero()
	if h != null:
		h.planned_destination = Vector2i(-1, -1)
	map_view.clear_path()


func _show_planned_route() -> void:
	map_view.clear_path()
	var h := _hero()
	if h == null or not h.alive or h.owner != session.state.current_player or h.planned_destination == Vector2i(-1, -1):
		return
	var target := h.planned_destination
	if not session.state.map.in_bounds(target) or h.pos == target:
		h.planned_destination = Vector2i(-1, -1)
		return
	var plan := session.plan_path(h.id, target)
	if plan["path"].is_empty():
		return
	var obj := session.state.map.object_at(target)
	map_view.set_path(plan["path"], plan["reachable"], session.is_guarded(obj, h.owner) or (not obj.is_empty() and obj["type"] == "encounter"))


func _on_tile_clicked(t: Vector2i) -> void:
	if _busy or session.state.game_over:
		return
	# Clicking one of your other heroes selects it.
	var other := session.state.hero_at(t)
	if other != null and other.owner == session.state.current_player and other.id != selected_hero_id:
		selected_hero_id = other.id
		map_view.clear_path()
		_refresh()
		return
	var h := _hero()
	if h == null or not h.alive:
		return
	var here := session.state.map.object_at(t)
	if h.pos == t and here.get("type", "") == "town" and int(here.get("owner", -1)) == h.owner:
		_open_town(String(here["id"]))
		return
	if h.pos == t and here.get("type", "") == "site" and MapSites.kind(here, data) in ["trader", "cobolt"]:
		_set_busy(true)
		site_dialog.open(session, String(here["id"]), h.id)
		return
	if h.pos == t and here.get("type", "") == "scenario_site":
		_open_objectives(String(here["id"]))
		return
	# Second click on the planned destination executes the move.
	if not map_view.path.is_empty() and map_view.path[-1] == t:
		await _execute_move(t)
		return
	var plan := session.plan_path(h.id, t)
	if plan["path"].is_empty():
		_cancel_route()
		return
	h.planned_destination = t
	_show_planned_route()


func _execute_move(t: Vector2i) -> void:
	var h := _hero()
	var from := h.pos
	_set_busy(true)
	_points_before = h.skill_points
	var gear_before := h.all_artifacts(data)
	var r := session.move_hero(h.id, t)
	# Movement-limited routes remain available next turn. Explicit encounters
	# and arrivals complete the order and must never restart it automatically.
	if h.pos == t or r["battle"] != "" or r["encounter"] != "" or r["town"] != "" or r["site"] != "" or r.get("scenario", "") != "":
		h.planned_destination = Vector2i(-1, -1)
	_look_at = Vector2(-1, -1)
	map_view.clear_path()
	if not r["steps"].is_empty():
		_move_result = r
		await map_view.animate_hero(h.id, from, r["steps"])
		_move_result = {}
	_refresh()
	await _show_found(h, ArtifactFoundDialog.gained(gear_before, h.all_artifacts(data)))
	if r["battle"] != "":
		_pending_battle = r["battle"]
		AudioManager.play("battle_prepare")
		_show_forecast()
		return
	if r["encounter"] != "":
		_pending_encounter = r["encounter"]
		AudioManager.play("ui_open")
		encounter_dialog.show_options(session.encounter_options(h.id, _pending_encounter))
		return
	if _check_game_over():
		return
	if r.get("scenario", "") != "":
		scenario_dialog.open(session, h.id, String(r["scenario"]))
		return
	var site_lines := []
	for v in r["visited"]:
		hud.log_message("[color=#7fc06a]%s[/color]: %s" % [MapSites.site_name(session.state.map.objects[v["id"]], data), ", ".join(v["lines"])])
		AudioManager.play("encounter_good")
		if v["id"] == r["site"]:
			site_lines = v["lines"]
	if r["site"] != "":
		AudioManager.play("ui_open")
		site_dialog.open(session, r["site"], h.id, site_lines)
		return
	if h.skill_points > _points_before:
		_after_event()
		return
	_set_busy(false)
	if _check_game_over():
		return
	if r["town"] != "":
		_open_town(r["town"])


## Footsteps by terrain, and the pickup or capture sound on the tile where it happens.
func _on_hero_stepped(_hero_id: String, tile: Vector2i) -> void:
	var m := session.state.map
	AudioManager.play_step(m.terrain_at(tile), m.has_road(tile))
	for obj in _move_result.get("collected", []):
		if Vector2i(int(obj["pos"][0]), int(obj["pos"][1])) == tile:
			AudioManager.play_pickup(String(obj.get("resource", "")))
	for id in _move_result.get("captured", []):
		var obj: Dictionary = m.objects.get(id, {})
		if not obj.is_empty() and Vector2i(int(obj["pos"][0]), int(obj["pos"][1])) == tile:
			AudioManager.play("capture_town" if obj["type"] == "town" else "capture_mine")


func _on_encounter_choice(idx: int) -> void:
	var h := _hero()
	var gear_before := h.all_artifacts(data)
	var result := session.resolve_encounter(h.id, _pending_encounter, idx)
	if not result.get("ok", false):
		return
	_found_in_encounter = ArtifactFoundDialog.gained(gear_before, h.all_artifacts(data))
	if result["leave"]:
		encounter_dialog.hide()
		_pending_encounter = ""
		_set_busy(false)
		return
	_pending_encounter = ""
	var col := "#7fc06a" if result["success"] else "#d96a52"
	hud.log_message("[color=%s]%s[/color]: %s" % [col, result["name"], ", ".join(result["lines"]) if not result["lines"].is_empty() else "done"])
	_refresh()
	AudioManager.play("encounter_good" if result["success"] else "encounter_bad")
	encounter_dialog.show_result(result)
	_pending_battle = result["battle"]


func _on_encounter_result_closed() -> void:
	var found := _found_in_encounter
	_found_in_encounter = []
	await _show_found(_hero(), found)
	if _pending_battle != "":
		var obj: Dictionary = session.state.map.objects[_pending_battle]
		AudioManager.play("battle_prepare")
		_show_forecast(obj.get("name", "ambush"))
		return
	_after_event()


## Shows the artifacts a hero just picked up and waits until the dialog closes.
func _show_found(h: Hero, found: Array[String]) -> void:
	if h == null or found.is_empty():
		return
	found_dialog.open(h, found)
	await found_dialog.closed


## After a battle report or encounter: offer the skill choice if the hero just
## earned a point, otherwise hand control back to the map.
func _after_event() -> void:
	_set_busy(false)
	if _check_game_over():
		return
	var h := _hero()
	if h != null and h.alive and h.skill_points > _points_before:
		_open_level_up()
		return
	_set_busy(false)


func _open_level_up() -> void:
	var h := _hero()
	if h == null or h.skill_points <= 0:
		_set_busy(false)
		return
	_set_busy(true)
	map_view.clear_path()
	AudioManager.play("level_up")
	level_up.show_offers(h, session.skill_offers(h.id))


func _on_skill_chosen(skill_id: String) -> void:
	var h := _hero()
	if not session.learn_skill(h.id, skill_id):
		return
	_points_before = h.skill_points
	_refresh()
	if h.skill_points > 0:
		level_up.show_offers(h, session.skill_offers(h.id))
	else:
		level_up.hide()
		_set_busy(false)


func _on_attack_confirmed() -> void:
	var h := _hero()
	var from := h.pos
	AudioManager.play("battle_start")
	var result := session.attack(h.id, _pending_battle)
	_pending_battle = ""
	if BattleViewer.watch_enabled(panels.settings_path) and result.has("log"):
		await battle_viewer.play(result, h.name, 0, panels.settings_path)
	AudioManager.play_stinger("battle_victory" if result["winner"] == 0 else "battle_defeat")
	if result["winner"] == 0 and h.alive:
		await map_view.animate_hero(h.id, from, [h.pos])
		hud.log_message("[color=#7fc06a]Victory[/color] over %s. +%d XP." % [result["sides"][1]["name"], result["xp_gained"]])
	else:
		hud.log_message("[color=#d96a52]%s[/color] against %s." % ["Withdrew" if result["outcome"] in ["attacker_withdrew", "attacker_retreated"] else "Defeat", result["sides"][1]["name"]])
	_refresh()
	panels.show_report(result)


## Replays the battle from the report, then brings the report back.
func _watch_again(result: Dictionary) -> void:
	panels.hide()
	await battle_viewer.play(result, "", 1 if _ai_playing else 0, panels.settings_path)
	panels.show()


## Opens the given town, else the town the selected hero stands in, else the
## current player's first town.
func _open_town(town_id: String = "") -> void:
	if _busy or session.state.game_over:
		return
	if town_id == "":
		var h := _hero()
		var here := session.state.map.object_at(h.pos) if h != null else {}
		if not here.is_empty() and here["type"] == "town" and int(here["owner"]) == session.state.current_player:
			town_id = here["id"]
		else:
			var towns := session.towns_of(session.state.current_player)
			if towns.is_empty():
				hud.log_message("You hold no town.")
				return
			town_id = towns[0]["id"]
	_set_busy(true)
	town_screen.open(session, town_id)


func _open_objectives(site_id: String = "") -> void:
	if _busy or session == null or not ScenarioRules.active(session.state):
		return
	_set_busy(true)
	scenario_dialog.open(session, selected_hero_id, site_id)


func _open_hero_screen() -> void:
	if _busy or session == null or session.state.game_over:
		return
	var h := _hero()
	if h == null or not h.alive:
		return
	_set_busy(true)
	map_view.clear_path()
	hero_screen.open(session, h.id)


func _next_hero() -> void:
	if _busy:
		return
	var heroes := session.state.heroes_of(session.state.current_player)
	if heroes.is_empty():
		return
	var idx := 0
	for i in heroes.size():
		if heroes[i].id == selected_hero_id:
			idx = (i + 1) % heroes.size()
	_select_hero(heroes[idx].id)


func _end_turn() -> void:
	if _busy or session.state.game_over:
		return
	_last_human = session.state.current_player
	_before_turns = _turn_snapshot()
	if net.active():
		_end_online_turn()
		return
	# The new day's own messages (week, timers, eliminations) are summed up by
	# _report_turn_events() once the next human is to move, in the right order.
	_ai_playing = true
	session.end_turn()
	_ai_playing = false
	map_view.clear_path()
	_on_turn_changed()


## Defer until the builder has assigned its desktop size and font overrides.
func _prepare_touch_control(node: Node) -> void:
	if node is Control:
		_enlarge_added_control.call_deferred(weakref(node))


func _enlarge_added_control(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if is_instance_valid(node):
		UiStyle.enlarge_touch_controls(node)


# ----------------------------------------------------------- online play --

func _open_online() -> void:
	if net.active():
		menu.hide()
		online_panel.open_match()
		return
	var can_host := session != null and not session.state.game_over and not editor_playtest \
		and not OnlineMatch.human_players(session.state).is_empty()
	online_panel.open_connect(can_host)


func _host_online(person: String, port: int) -> void:
	var why := net.host(session, person, port)
	if why != "":
		online_panel.open_connect(true, why)
		return
	campaign = null   # an online game advances no campaign
	hud.log_message("Hosting online as %s." % net.my_name)


func _join_online(address: String, person: String) -> void:
	var why := net.join(address, person)
	if why != "":
		online_panel.open_connect(session != null and not session.state.game_over, why)
		return
	menu.hide()
	online_panel.open_match("Connecting to %s..." % address.strip_edges())


## Ends online play; back_to_menu: show the menu (not when a new game or a
## loaded one takes over the screen).
func _leave_online(back_to_menu: bool = true) -> void:
	_online_playing = false
	if net != null and net.active():
		net.leave()
	if online_panel != null and online_panel.visible:
		online_panel.hide()
		map_view.visible = true
		if back_to_menu and session != null and not menu.visible:
			_open_menu()


## A new state of the online game arrived (or the seats changed).
func _on_online_game(s: GameSession) -> void:
	if s == session and _online_playing and net.my_turn():
		online_panel.refresh()   # seats changed during our turn
		return
	if s != session:
		var before := _before_turns
		_start(s)
		_before_turns = before
		campaign = null
	menu.hide()
	if s.state.game_over:
		online_panel.hide()
		map_view.visible = true
		_report_turn_events()
		_refresh()
		_check_game_over()
		return
	if net.my_turn():
		online_panel.hide()
		_online_playing = true
		_last_human = s.state.current_player
		_report_turn_events()
		map_view.clear_path()
		selected_hero_id = ""
		_look_at = Vector2(-1, -1)
		_begin_human_turn()
		return
	_online_playing = false
	map_view.visible = false
	_set_busy(true)
	online_panel.open_match("")


func _end_online_turn() -> void:
	_online_playing = false
	session.end_turn()
	map_view.clear_path()
	map_view.visible = false
	_set_busy(true)
	online_panel.open_match("Turn sent. The next player is on the move.")
	net.finish_turn(session)


func _on_online_closed(reason: String) -> void:
	_online_playing = false
	if reason == "":
		return
	hud.log_message("[color=#e0b450]%s[/color]" % reason)
	online_panel.open_connect(false, reason)
