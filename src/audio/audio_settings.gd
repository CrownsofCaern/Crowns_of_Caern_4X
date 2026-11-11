class_name AudioSettings
extends RefCounted
## Player volume settings (0..1 per bus, plus mute), stored in a ConfigFile
## under user:// so they survive restarts. No nodes; AudioManager applies them.

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "audio"

var path := DEFAULT_PATH
var volumes: Dictionary = {}   # bus name -> 0..1
var muted := false


static func create(catalog: AudioCatalog, file_path: String = DEFAULT_PATH) -> AudioSettings:
	var s := AudioSettings.new()
	s.path = file_path
	for b in AudioCatalog.BUSES:
		s.volumes[b] = AudioCatalog.default_volume(catalog.buses.get(b))
	s.load_file()
	return s


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for b in volumes:
		volumes[b] = clampf(float(cfg.get_value(SECTION, b.to_lower(), volumes[b])), 0.0, 1.0)
	muted = bool(cfg.get_value(SECTION, "muted", muted))


func save_file() -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)   # keep other sections
	for b in volumes:
		cfg.set_value(SECTION, b.to_lower(), volumes[b])
	cfg.set_value(SECTION, "muted", muted)
	return cfg.save(path)


func volume(bus: String) -> float:
	return float(volumes.get(bus, 1.0))


func set_volume(bus: String, v: float) -> void:
	if volumes.has(bus):
		volumes[bus] = clampf(v, 0.0, 1.0)


## Bus gain in decibels for a 0..1 slider value (perceptual curve; 0 is silent).
static func to_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v * v)
