class_name AudioManager
extends Node
## Plays sound effects and music. Registered as the autoload "Audio"
## (project.godot); game code calls the static helpers (AudioManager.play(),
## AudioManager.set_music(), ...), which do nothing when no manager runs, so
## tools, tests and headless runs need no audio at all.
##
## Buses: Master <- Music (stingers) <- MusicBed (looping tracks, ducked under
## stingers), Master <- SFX, Master <- UI. Volumes persist via AudioSettings.
## What plays for which event is data (data/audio.json, see AudioCatalog).

const SILENT_DB := -60.0
const DUCK_DB := -18.0
const POOL_SIZES := {"SFX": 10, "UI": 4}
const BED_BUS := "MusicBed"

static var _instance: AudioManager

var catalog: AudioCatalog
var settings: AudioSettings
## False in headless runs or with the user argument --mute: nothing is loaded or played.
var enabled := false
var music_context := ""
var music_faction := ""
## The faction whose colour faction-flavoured sounds and stingers take (the player at the controls).
var faction := ""
var _turns: Dictionary = {}   # music context -> next alternative to play
var _tracks: Array[String] = []   # alternatives of the current context, played in turn
var _track := 0
var _before_battle: Array = []   # [context, faction] to return to after battle music
var _pools: Dictionary = {}   # bus -> Array[AudioStreamPlayer]
var _next_slot: Dictionary = {}
var _beds: Array[AudioStreamPlayer] = []
var _bed := 0
var _stinger: AudioStreamPlayer
var _bed_path := ""
var _fades: Dictionary = {}   # player -> Tween
var _duck: Tween


func _ready() -> void:
	if catalog == null:
		setup(AudioCatalog.load_from(), AudioSettings.DEFAULT_PATH, should_enable())
	if enabled:
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	_release()


## Stops everything and drops the streams. Call a frame or two before quitting
## so the audio server lets go of its playbacks (else Godot reports leaks).
static func stop_all() -> void:
	if _instance != null:
		_instance._release()


func _release() -> void:
	for c in get_children():
		if c is AudioStreamPlayer:
			c.stop()
			c.stream = null
	_bed_path = ""


## Audio plays only with a real display and without --mute.
static func should_enable() -> bool:
	return DisplayServer.get_name() != "headless" and not "--mute" in OS.get_cmdline_user_args()


static func instance() -> AudioManager:
	return _instance


## Call before adding to the tree to inject data or a settings file (tests).
func setup(cat: AudioCatalog, settings_path: String, play_enabled: bool) -> void:
	_instance = self
	catalog = cat
	settings = AudioSettings.create(cat, settings_path)
	enabled = play_enabled
	if not enabled:
		return
	_ensure_buses()
	apply_settings()
	for bus in POOL_SIZES:
		var pool: Array[AudioStreamPlayer] = []
		for i in POOL_SIZES[bus]:
			pool.append(_player(bus))
		_pools[bus] = pool
		_next_slot[bus] = 0
	for i in 2:
		var bed := _player(BED_BUS)
		bed.finished.connect(_on_bed_finished.bind(bed))
		_beds.append(bed)
	_stinger = _player("Music")
	_stinger.finished.connect(_unduck)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


static func _ensure_bus(bus_name: String, send: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)


func _ensure_buses() -> void:
	for b in AudioCatalog.BUSES:
		if b != "Master":
			_ensure_bus(b, "Master")
	_ensure_bus(BED_BUS, "Music")


## Pushes the settings to the buses.
func apply_settings() -> void:
	if not enabled:
		return
	for b in AudioCatalog.BUSES:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(b), AudioSettings.to_db(settings.volume(b)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), settings.muted)


# ------------------------------------------------------------ static API --

## Plays a sound event from data/audio.json.
static func play(event_id: String) -> void:
	if _instance != null and _instance.enabled:
		_instance._play_event(event_id)


## Footstep for a hero entering a tile.
static func play_step(terrain_id: String, on_road: bool) -> void:
	if _instance != null and _instance.enabled:
		_instance._play_event(_instance.catalog.step_event(terrain_id, on_road))


static func play_pickup(resource_id: String) -> void:
	if _instance != null and _instance.enabled:
		_instance._play_event(_instance.catalog.pickup_event(resource_id))


## Switches the looping music ("menu", "map", "town" with a faction, ...) with a crossfade.
static func set_music(context: String, faction: String = "") -> void:
	if _instance != null and _instance.enabled:
		_instance._set_music(context, faction)


## The faction of the player at the controls: faction-flavoured events and stingers take its colour ("" for none).
static func set_faction(faction_id: String) -> void:
	if _instance != null:
		_instance.faction = faction_id


## Battle music while a fight is watched; end_battle_music() returns to what played before.
static func begin_battle_music() -> void:
	if _instance != null and _instance.enabled and _instance.music_context != "battle":
		_instance._before_battle = [_instance.music_context, _instance.music_faction]
		_instance._set_music("battle", "")


static func end_battle_music() -> void:
	if _instance != null and _instance.enabled and _instance.music_context == "battle":
		var back: Array = _instance._before_battle if not _instance._before_battle.is_empty() else ["map", ""]
		_instance._set_music(String(back[0]), String(back[1]))


## Plays a one-shot music cue ("battle_victory", ...) over the ducked loop.
static func play_stinger(context: String) -> void:
	if _instance != null and _instance.enabled:
		_instance._play_stinger(context)


## Settings changes from the UI: saved at once and applied.
static func set_volume(bus: String, value: float) -> void:
	if _instance != null:
		_instance.settings.set_volume(bus, value)
		_instance.settings.save_file()
		_instance.apply_settings()


static func set_muted(on: bool) -> void:
	if _instance != null:
		_instance.settings.muted = on
		_instance.settings.save_file()
		_instance.apply_settings()


static func is_muted() -> bool:
	return _instance != null and _instance.settings.muted


static func volume(bus: String) -> float:
	return _instance.settings.volume(bus) if _instance != null else 0.0


# --------------------------------------------------------------- playing --

func _play_event(event_id: String) -> AudioStreamPlayer:
	var p := catalog.next_play(event_id, faction)
	if p.is_empty():
		push_warning("AudioManager: unknown sound event %s" % event_id)
		return null
	var stream: AudioStream = load(p["path"])
	if stream == null:
		return null
	var pool: Array = _pools.get(p["bus"], _pools["SFX"])
	var bus: String = p["bus"] if _pools.has(p["bus"]) else "SFX"
	var player: AudioStreamPlayer = null
	for q in pool:
		if not q.playing:
			player = q
			break
	if player == null:   # all busy: take the next in turn
		player = pool[_next_slot[bus]]
		_next_slot[bus] = (_next_slot[bus] + 1) % pool.size()
	player.stream = stream
	player.volume_db = p["volume_db"]
	player.pitch_scale = p["pitch"]
	if player.is_inside_tree():
		player.play()
	return player


## Contexts with alternatives ("files") play them one after another, starting
## each visit with the next one; a single track loops.
func _set_music(context: String, faction_id: String) -> void:
	if context == music_context and faction_id == music_faction and _bed_path != "":
		return
	music_context = context
	music_faction = faction_id
	var entry := catalog.music_entry(context, faction_id)
	_tracks = AudioCatalog.music_tracks(entry)
	_track = int(_turns.get(context, 0))
	if _tracks.size() > 1:
		_turns[context] = _track + 1
	_start_track(_tracks[_track % _tracks.size()] if not _tracks.is_empty() else "", entry)


func _start_track(path: String, entry: Dictionary) -> void:
	if path == _bed_path:
		return
	_bed_path = path
	var old := _beds[_bed]
	_fade(old, SILENT_DB, true)
	if path == "":
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	if "loop" in stream:
		stream.set("loop", bool(entry.get("loop", true)) and _tracks.size() <= 1)
	_bed = 1 - _bed
	var nxt := _beds[_bed]
	nxt.stream = stream
	nxt.volume_db = SILENT_DB
	if nxt.is_inside_tree():
		nxt.play()
	_fade(nxt, float(entry.get("volume_db", 0.0)), false)


## A track of a playlist ended: the next alternative takes over.
func _on_bed_finished(bed: AudioStreamPlayer) -> void:
	if bed != _beds[_bed] or _tracks.size() <= 1:
		return
	_track += 1
	_turns[music_context] = _track + 1
	_start_track(_tracks[_track % _tracks.size()], catalog.music_entry(music_context, music_faction))


func _fade(p: AudioStreamPlayer, to_db: float, stop_after: bool) -> void:
	if _fades.has(p) and _fades[p].is_valid():
		_fades[p].kill()
	if not p.is_inside_tree() or not p.playing:
		if stop_after and p.is_inside_tree():
			p.stop()
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, catalog.music_fade_seconds)
	if stop_after:
		tw.tween_callback(p.stop)
	_fades[p] = tw


func _play_stinger(context: String) -> void:
	var entry := catalog.music_entry(context, faction)
	var path := AudioCatalog.music_path(entry)
	if path == "":
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	if "loop" in stream:
		stream.set("loop", false)
	_stinger.stream = stream
	_stinger.volume_db = float(entry.get("volume_db", 0.0))
	if _stinger.is_inside_tree():
		_stinger.play()
	_set_duck(DUCK_DB, 0.4)


func _unduck() -> void:
	_set_duck(0.0, 2.5)


func _set_duck(db: float, secs: float) -> void:
	if _duck != null and _duck.is_valid():
		_duck.kill()
	var idx := AudioServer.get_bus_index(BED_BUS)
	if not is_inside_tree():
		AudioServer.set_bus_volume_db(idx, db)
		return
	_duck = create_tween()
	_duck.tween_method(func(v: float): AudioServer.set_bus_volume_db(idx, v),
		AudioServer.get_bus_volume_db(idx), db, secs)


## Every button in the game clicks, without each screen wiring it up.
func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("silent") and not n.pressed.is_connected(_on_button_pressed):
		n.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	_play_event("ui_click")


## The player currently carrying the looping music (tests, debugging).
func current_bed() -> AudioStreamPlayer:
	return _beds[_bed] if not _beds.is_empty() else null


func stinger_player() -> AudioStreamPlayer:
	return _stinger
