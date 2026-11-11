extends "res://tests/test_case.gd"
## Audio: data/audio.json validation, event resolution, settings persistence,
## and the manager both silent (headless default) and playing (forced on).

const SETTINGS := "user://test_audio_settings.cfg"


func _catalog() -> AudioCatalog:
	return AudioCatalog.load_from()


func _cleanup() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func test_audio_data_is_valid() -> void:
	var errors := _catalog().validate(data)
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_validation_catches_broken_entries() -> void:
	var c := _catalog()
	c.sounds.erase("build")
	c.sounds["ghost"] = {"files": ["sfx/nope.ogg"], "bus": "Music"}
	c.terrain_steps["lava_sea"] = "step_grass"
	c.pickups["gold"] = "no_such_sound"
	c.music["town:nobody"] = {"file": "music/map.ogg"}
	c.music.erase("map")
	var text := "\n".join(c.validate(data))
	for needle in ["required event build", "missing file sfx/nope.ogg", "SFX or UI bus", "unknown terrain lava_sea",
			"pickups.gold", "town:nobody", "context map missing"]:
		assert_true(text.contains(needle), "expected an error about %s in:\n%s" % [needle, text])


func test_every_terrain_and_resource_has_a_sound() -> void:
	var c := _catalog()
	for t in data.terrains:
		var ev := c.step_event(t, false)
		assert_true(c.has_event(ev), "terrain %s has no step sound" % t)
	assert_eq(c.step_event("swamp", true), "step_road", "roads sound like roads")
	assert_eq(c.step_event("swamp", false), "step_swamp")
	for r in data.resources:
		assert_true(c.has_event(c.pickup_event(r)), "resource %s has no pickup sound" % r)
	assert_eq(c.pickup_event("gold"), "pickup_gold")
	assert_eq(c.pickup_event("ore"), "pickup_resource")


func test_variants_rotate_and_pitch_is_deterministic() -> void:
	var a := _catalog()
	var b := _catalog()
	var p1 := a.next_play("step_grass")
	var p2 := a.next_play("step_grass")
	var p3 := a.next_play("step_grass")
	assert_ne(p1["path"], p2["path"], "two variants alternate")
	assert_eq(p1["path"], p3["path"])
	assert_ne(p1["pitch"], p2["pitch"])
	var spread := float(a.sounds["step_grass"]["pitch_variation"])
	for p in [p1, p2, p3]:
		assert_between(p["pitch"], 1.0 - spread, 1.0 + spread)
	# Same sequence from a fresh catalog: no hidden randomness.
	assert_eq(b.next_play("step_grass"), p1)
	assert_eq(a.next_play("build")["pitch"], 1.0, "no variation unless the data asks for it")
	assert_true(a.next_play("no_such_event").is_empty())


func test_town_music_by_faction_with_fallback() -> void:
	var c := _catalog()
	assert_eq(c.music_entry("town", "concord")["file"], "music/town_concord.ogg")
	assert_eq(c.music_entry("town", "ashen")["file"], "music/town_ashen.ogg")
	assert_eq(c.music_entry("town", "wilds")["file"], "music/town_default.ogg", "factions without a theme use the default")
	assert_eq(AudioCatalog.music_path(c.music_entry("map", "concord")), "res://assets/audio/music/map.ogg")
	assert_true(c.music_entry("nowhere").is_empty())
	for f in data.factions:
		assert_false(c.music_entry("town", f).is_empty(), "faction %s has town music" % f)


func test_faction_sounds_and_victory_by_faction() -> void:
	var c := _catalog()
	assert_eq(c.next_play("build", "ashen")["path"], "res://assets/audio/sfx/faction/build_ashen.ogg")
	assert_eq(c.next_play("turn_begin", "fishmen")["path"], "res://assets/audio/sfx/faction/turn_begin_fishmen.ogg")
	assert_eq(c.next_play("turn_begin", "")["path"], "res://assets/audio/sfx/turn_begin.ogg", "no faction: shared sound")
	assert_eq(c.next_play("turn_begin", "wilds")["path"], "res://assets/audio/sfx/turn_begin.ogg", "uncoloured faction")
	assert_eq(c.next_play("ui_error", "ashen")["path"], "res://assets/audio/sfx/ui_error.ogg", "event without colour")
	assert_eq(c.next_play("build", "ashen")["bus"], "SFX", "the colour keeps the event's bus")
	for f in GameSetup.playable_factions(data):
		assert_true(c.has_faction_sound("build", f), "playable faction %s has its own build sound" % f)
		assert_eq(AudioCatalog.music_path(c.music_entry("battle_victory", f)),
			"res://assets/audio/music/battle_victory_%s.ogg" % f)
	var broken := _catalog()
	broken.faction_sounds["events"].append("nonsense")
	broken.faction_sounds["factions"].append("nobody")
	var text := "\n".join(broken.validate(data))
	assert_true(text.contains("unknown event nonsense") and text.contains("unknown faction nobody"), text)


func test_map_music_has_alternatives_and_battle_music_exists() -> void:
	var c := _catalog()
	var tracks := AudioCatalog.music_tracks(c.music_entry("map"))
	assert_eq(tracks.size(), 3, "the map theme and two alternatives")
	assert_eq(tracks[0], "res://assets/audio/music/map.ogg", "the original map theme comes first")
	assert_eq(AudioCatalog.music_tracks(c.music_entry("battle")).size(), 1)
	for e in ["battle_hit", "battle_shot", "battle_drums", "battle_horn"]:
		assert_gt((c.sounds[e]["files"] as Array).size(), 1, "%s has several takes" % e)
		assert_lt(float(c.sounds[e]["volume_db"]), -8.0, "%s stays under the battle music" % e)


func test_manager_rotates_map_themes_and_returns_from_battle() -> void:
	_cleanup()
	var m := AudioManager.new()
	m.setup(_catalog(), SETTINGS, true)
	AudioManager.set_faction("forge")
	assert_eq(m._play_event("build").stream.resource_path, "res://assets/audio/sfx/faction/build_forge.ogg")
	AudioManager.set_music("map")
	var first := m.current_bed().stream.resource_path
	assert_eq(first, "res://assets/audio/music/map.ogg")
	assert_false(m.current_bed().stream.get("loop"), "alternatives play through, then hand over")
	AudioManager.set_music("map")
	assert_eq(m.current_bed().stream.resource_path, first, "staying on the map: no restart")
	m._on_bed_finished(m.current_bed())
	assert_eq(m.current_bed().stream.resource_path, "res://assets/audio/music/map_highlands.ogg", "next theme")
	AudioManager.set_music("town", "forge")
	AudioManager.begin_battle_music()
	assert_eq(m.current_bed().stream.resource_path, "res://assets/audio/music/battle.ogg")
	assert_true(m.current_bed().stream.get("loop"), "battle music loops")
	AudioManager.end_battle_music()
	assert_eq(m.music_context, "town")
	assert_eq(m.music_faction, "forge")
	AudioManager.set_music("map")
	assert_eq(m.current_bed().stream.resource_path, "res://assets/audio/music/map_dusk.ogg",
		"coming back to the map starts the next theme")
	AudioManager.play_stinger("battle_victory")
	assert_eq(m.stinger_player().stream.resource_path, "res://assets/audio/music/battle_victory_forge.ogg")
	m.free()
	_cleanup()


func test_settings_default_clamp_and_persist() -> void:
	_cleanup()
	var c := _catalog()
	var s := AudioSettings.create(c, SETTINGS)
	assert_eq(s.volume("Music"), float(c.buses["Music"]["default"]))
	assert_false(s.muted)
	s.set_volume("Music", 0.25)
	s.set_volume("SFX", 3.0)
	s.set_volume("Nonsense", 0.5)
	s.muted = true
	assert_eq(s.save_file(), OK)
	var again := AudioSettings.create(c, SETTINGS)
	assert_eq(again.volume("Music"), 0.25)
	assert_eq(again.volume("SFX"), 1.0, "clamped")
	assert_true(again.muted)
	assert_false(again.volumes.has("Nonsense"))
	_cleanup()


func test_slider_to_decibels() -> void:
	assert_eq(AudioSettings.to_db(0.0), -80.0)
	assert_between(AudioSettings.to_db(1.0), -0.01, 0.01)
	assert_lt(AudioSettings.to_db(0.5), AudioSettings.to_db(0.8))


func test_manager_is_silent_when_disabled() -> void:
	_cleanup()
	var m := AudioManager.new()
	m.setup(_catalog(), SETTINGS, false)
	assert_false(m.enabled)
	assert_eq(m.get_child_count(), 0, "a disabled manager creates no players")
	# The static helpers are safe no-ops.
	AudioManager.play("build")
	AudioManager.play_step("grass", false)
	AudioManager.set_music("map")
	AudioManager.play_stinger("battle_victory")
	assert_eq(m.music_context, "")
	# Settings still save, so the sound menu works in any session.
	AudioManager.set_volume("UI", 0.3)
	assert_eq(AudioSettings.create(_catalog(), SETTINGS).volume("UI"), 0.3)
	m.free()
	assert_true(AudioManager.instance() == null or AudioManager.instance() != m)
	_cleanup()


func test_manager_plays_events_and_music_when_enabled() -> void:
	_cleanup()
	# The runner has no running tree, so this checks what would play (streams,
	# buses, tracks, bus levels) without actual playback.
	var m := AudioManager.new()
	m.setup(_catalog(), SETTINGS, true)
	for b in AudioCatalog.BUSES + [AudioManager.BED_BUS]:
		assert_gt(AudioServer.get_bus_index(b), -1, "bus %s exists" % b)
	var p := m._play_event("build")
	assert_true(p != null)
	assert_eq(p.stream.resource_path, "res://assets/audio/sfx/build.ogg")
	assert_eq(String(p.bus), "SFX")
	assert_eq(String(m._play_event("ui_click").bus), "UI")
	AudioManager.set_music("town", "ashen")
	var bed := m.current_bed()
	assert_eq(bed.stream.resource_path, "res://assets/audio/music/town_ashen.ogg")
	assert_true(bed.stream.get("loop"), "music loops")
	AudioManager.set_music("town", "ashen")
	assert_eq(m.current_bed(), bed, "same track: no restart")
	AudioManager.set_music("map")
	assert_ne(m.current_bed(), bed, "a new track crossfades on the other player")
	AudioManager.play_stinger("battle_defeat")
	assert_eq(m.stinger_player().stream.resource_path, "res://assets/audio/music/battle_defeat.ogg")
	AudioManager.set_volume("Music", 0.5)
	assert_between(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), AudioSettings.to_db(0.5) - 0.01,
		AudioSettings.to_db(0.5) + 0.01)
	AudioManager.set_muted(true)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	AudioManager.set_muted(false)
	# Any button added to the tree clicks.
	var btn := Button.new()
	m._on_node_added(btn)
	assert_true(btn.pressed.is_connected(m._on_button_pressed))
	var quiet := Button.new()
	quiet.set_meta("silent", true)
	m._on_node_added(quiet)
	assert_false(quiet.pressed.is_connected(m._on_button_pressed))
	btn.free()
	quiet.free()
	m.free()
	_cleanup()
