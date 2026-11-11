class_name AudioCatalog
extends RefCounted
## Data side of the audio system (data/audio.json): which file an event plays,
## on which bus and how loud, which step sound a terrain makes, which track a
## music context uses. Pure data and bookkeeping, no nodes, so it is tested
## headless; AudioManager does the playing.

const DEFAULT_PATH := "res://data/audio.json"
const AUDIO_DIR := "res://assets/audio/"
const BUSES := ["Master", "Music", "SFX", "UI"]
## Every event and music context the game code asks for. validate() fails if
## one is missing from the data, so a typo or a deleted entry cannot go silent.
const REQUIRED_EVENTS := ["ui_click", "ui_open", "ui_close", "ui_error", "pickup_resource", "capture_mine",
	"capture_town", "build", "recruit", "upgrade", "hire_hero", "trade", "battle_prepare", "battle_start",
	"hero_fallen", "town_lost", "turn_begin", "week_begin", "level_up", "encounter_good", "encounter_bad",
	"battle_hit", "battle_shot", "battle_drums", "battle_horn"]
const REQUIRED_MUSIC := ["menu", "map", "town", "battle", "battle_victory", "battle_defeat", "game_victory", "game_defeat"]

var buses: Dictionary = {}
var sounds: Dictionary = {}
var terrain_steps: Dictionary = {}
var pickups: Dictionary = {}
var music: Dictionary = {}
var music_fade_seconds := 1.5
## Faction colour: {dir, events[], factions[]}. An event in events, played for a faction in factions, uses
## <dir>/<event>_<faction>.ogg (same bus, volume and pitch as the event) instead of its own files.
var faction_sounds: Dictionary = {}
var _plays: Dictionary = {}   # event id -> times played (round-robin variants, pitch sequence)


static func load_from(path: String = DEFAULT_PATH) -> AudioCatalog:
	var c := AudioCatalog.new()
	var d: Variant = GameData.read_json(path)
	if typeof(d) != TYPE_DICTIONARY:
		return c
	c.buses = d.get("buses", {})
	c.sounds = d.get("sounds", {})
	c.terrain_steps = d.get("terrain_steps", {})
	c.pickups = d.get("pickups", {})
	c.music = d.get("music", {})
	c.music_fade_seconds = float(d.get("music_fade_seconds", 1.5))
	c.faction_sounds = d.get("faction_sounds", {})
	return c


func has_event(event_id: String) -> bool:
	return sounds.has(event_id)


## The next play of an event: {path, bus, volume_db, pitch}, or {} if unknown.
## Variants rotate and the pitch follows a fixed low-discrepancy sequence, so
## repeats sound varied without any randomness. With a faction that has its own
## colour for the event, that faction's file plays instead.
func next_play(event_id: String, faction: String = "") -> Dictionary:
	var s: Dictionary = sounds.get(event_id, {})
	if s.is_empty():
		return {}
	var n := int(_plays.get(event_id, 0))
	_plays[event_id] = n + 1
	var files: Array = s["files"]
	var spread := float(s.get("pitch_variation", 0.0))
	var pitch := 1.0
	if spread > 0.0:
		pitch = 1.0 + spread * (fposmod(n * 0.6180339887, 1.0) * 2.0 - 1.0)
	var path := AUDIO_DIR + String(files[n % files.size()])
	if has_faction_sound(event_id, faction):
		path = faction_sound_path(event_id, faction)
	return {"path": path, "bus": s.get("bus", "SFX"), "volume_db": float(s.get("volume_db", 0.0)), "pitch": pitch}


func has_faction_sound(event_id: String, faction: String) -> bool:
	return faction != "" and Array(faction_sounds.get("events", [])).has(event_id) \
		and Array(faction_sounds.get("factions", [])).has(faction)


func faction_sound_path(event_id: String, faction: String) -> String:
	return AUDIO_DIR + "%s/%s_%s.ogg" % [String(faction_sounds.get("dir", "")), event_id, faction]


## The footstep event for a tile: the road sound on roads, else the terrain's.
func step_event(terrain_id: String, on_road: bool) -> String:
	if on_road and terrain_steps.has("road"):
		return terrain_steps["road"]
	return terrain_steps.get(terrain_id, terrain_steps.get("default", ""))


func pickup_event(resource_id: String) -> String:
	return pickups.get(resource_id, pickups.get("default", "pickup_resource"))


## The music entry for a context; "town" takes a faction ("town:<faction>",
## falling back to the generic "town" track). {} if none.
func music_entry(context: String, faction: String = "") -> Dictionary:
	if faction != "" and music.has(context + ":" + faction):
		return music[context + ":" + faction]
	return music.get(context, {})


## The tracks of a music entry: "file" (one track) or "files" (alternatives played in turn).
static func music_tracks(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if entry.has("file"):
		out.append(AUDIO_DIR + String(entry["file"]))
	for f in entry.get("files", []):
		out.append(AUDIO_DIR + String(f))
	return out


## The first track of an entry ("" if none).
static func music_path(entry: Dictionary) -> String:
	var tracks := music_tracks(entry)
	return tracks[0] if not tracks.is_empty() else ""


static func default_volume(bus_entry: Variant) -> float:
	return clampf(float(bus_entry.get("default", 1.0)), 0.0, 1.0) if bus_entry is Dictionary else 1.0


## Data errors; game_data supplies the terrains, resources and factions that
## need a sound. Checks that every referenced file exists as an imported resource.
func validate(game_data: GameData) -> Array[String]:
	var errors: Array[String] = []
	for b in BUSES:
		if not buses.has(b):
			errors.append("audio: bus %s missing" % b)
	for b in buses:
		if not b in BUSES:
			errors.append("audio: unknown bus %s" % b)
		elif float(buses[b].get("default", -1)) < 0.0 or float(buses[b].get("default", -1)) > 1.0:
			errors.append("audio: bus %s default must be in [0, 1]" % b)
	for id in sounds:
		var s: Dictionary = sounds[id]
		var files: Variant = s.get("files")
		if not files is Array or (files as Array).is_empty():
			errors.append("audio: sound %s has no files" % id)
			continue
		for f in files:
			if not ResourceLoader.exists(AUDIO_DIR + String(f)):
				errors.append("audio: sound %s: missing file %s" % [id, f])
		if not s.get("bus", "") in ["SFX", "UI"]:
			errors.append("audio: sound %s must use the SFX or UI bus" % id)
		if float(s.get("pitch_variation", 0.0)) < 0.0 or float(s.get("pitch_variation", 0.0)) > 0.3:
			errors.append("audio: sound %s pitch_variation must be in [0, 0.3]" % id)
	for e in REQUIRED_EVENTS:
		if not sounds.has(e):
			errors.append("audio: required event %s missing" % e)
	for key in terrain_steps:
		if not sounds.has(terrain_steps[key]):
			errors.append("audio: terrain_steps.%s -> unknown sound %s" % [key, terrain_steps[key]])
		elif key != "default" and key != "road" and not game_data.terrains.has(key):
			errors.append("audio: terrain_steps names unknown terrain %s" % key)
	if not terrain_steps.has("default"):
		errors.append("audio: terrain_steps needs a default")
	for key in pickups:
		if not sounds.has(pickups[key]):
			errors.append("audio: pickups.%s -> unknown sound %s" % [key, pickups[key]])
		elif key != "default" and not game_data.resources.has(key):
			errors.append("audio: pickups names unknown resource %s" % key)
	if not pickups.has("default"):
		errors.append("audio: pickups needs a default")
	for ctx in REQUIRED_MUSIC:
		if not music.has(ctx):
			errors.append("audio: music context %s missing" % ctx)
	for ctx in music:
		var m: Dictionary = music[ctx]
		var tracks := music_tracks(m)
		if tracks.is_empty():
			errors.append("audio: music %s has no file" % ctx)
		if m.has("files") and not bool(m.get("loop", true)):
			errors.append("audio: music %s: alternatives (files) are only for looping music" % ctx)
		for t in tracks:
			if not ResourceLoader.exists(t):
				errors.append("audio: music %s: missing file %s" % [ctx, t.trim_prefix(AUDIO_DIR)])
		if ctx.contains(":") and not game_data.factions.has(ctx.get_slice(":", 1)):
			errors.append("audio: music %s names unknown faction" % ctx)
	for e in faction_sounds.get("events", []):
		if not sounds.has(e):
			errors.append("audio: faction_sounds names unknown event %s" % e)
	for f in faction_sounds.get("factions", []):
		if not game_data.factions.has(f):
			errors.append("audio: faction_sounds names unknown faction %s" % f)
			continue
		for e in faction_sounds.get("events", []):
			if not ResourceLoader.exists(faction_sound_path(e, f)):
				errors.append("audio: faction sound missing: %s" % faction_sound_path(e, f).trim_prefix(AUDIO_DIR))
	return errors
