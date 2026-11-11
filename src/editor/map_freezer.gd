class_name MapFreezer
extends RefCounted
## Turns any loadable map id (a generated "gen:<template>:<seed>", a random
## "gen:random_...:<seed>", a mission "scenario:<recipe>:<seed>" or an existing
## data map) into a standalone data/maps definition that can be hand-tuned.
## Deterministic: the same id, output id and title always give the same bytes.
## Headless; used by tools/maps/freeze_map.gd and by the editor's dev mode.

## Leading keys in the order the builders in tools/maps write them; any other
## key follows in the generator's order, then the provenance block.
const KEY_ORDER := ["_doc", "id", "name", "width", "height", "terrain", "roads", "decorations",
	"players", "heroes", "objects", "scenario"]


## Returns {"definition": Dictionary, "error": ""} or {"error": "..."}.
static func freeze(data: GameData, source_id: String, out_id: String, title: String = "") -> Dictionary:
	if not MapRepository.valid_local_id(out_id):
		return {"error": "Map ids use 1-80 lowercase letters, digits, - and _: %s" % out_id}
	var source: Variant = data.load_map(source_id)
	if not source is Dictionary or (source as Dictionary).is_empty():
		return {"error": "Cannot load map %s." % source_id}
	var generated: Dictionary = (source as Dictionary).duplicate(true)
	var body := generated.duplicate(true)
	body["id"] = out_id
	body["name"] = title if title != "" else String(generated.get("name", out_id))
	body["_doc"] = _doc(source_id, generated)
	var provenance := {"map_id": source_id}
	# The generator block switches on generator fairness checks in MapValidator.
	# A frozen map is authored from here on, so keep it only as provenance,
	# like MapDocument.copy_as does for editor copies.
	if body.has("generator"):
		provenance["generator"] = body["generator"]
		body.erase("generator")
	body.erase("editor_source")
	var out := {}
	for key in KEY_ORDER:
		if body.has(key):
			out[key] = body[key]
	for key in body:
		if not out.has(key):
			out[key] = body[key]
	out["editor_source"] = provenance
	# Round-trip through the file format so the result equals what a reader of
	# the written file gets (plain arrays, no engine vector types).
	var parsed: Variant = JSON.parse_string(MapFileFormat.encode(out))
	if not parsed is Dictionary:
		return {"error": "Frozen map %s does not encode as JSON." % source_id}
	return {"definition": parsed, "error": ""}


## Freezes and writes <directory>/<out_id>.json. Returns "" or an error.
static func freeze_to_file(data: GameData, source_id: String, out_id: String, directory: String,
		title: String = "") -> String:
	var result := freeze(data, source_id, out_id, title)
	if result["error"] != "":
		return result["error"]
	return write_file(result["definition"], directory.path_join(out_id + ".json"))


## Atomic write in MapFileFormat. Accepts res://, user:// or absolute paths.
static func write_file(definition: Dictionary, path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		return "Cannot create %s: %s." % [absolute.get_base_dir(), error_string(error)]
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write %s: %s." % [temporary, error_string(FileAccess.get_open_error())]
	file.store_string(MapFileFormat.encode(definition))
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return "Cannot replace %s: %s." % [absolute, error_string(error)]
	return ""


static func _doc(source_id: String, source: Dictionary) -> String:
	var origin := source_id
	if source.has("generator"):
		origin = "%s (MapGenerator v%d, attempt %d)" % [source_id, int(source["generator"].get("version", 0)),
			int(source["generator"].get("attempt", 0))]
	elif source.get("scenario", {}).has("recipe"):
		origin = "%s (scenario recipe v%d)" % [source_id, int(source["scenario"]["recipe"].get("version", 0))]
	return "Frozen from %s by tools/maps/freeze_map.gd. Hand-tune freely: this file no longer follows the generator." % origin
