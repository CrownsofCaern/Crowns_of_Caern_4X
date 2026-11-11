class_name MapRepository
extends RefCounted
## Local authored files. All failures are returned to the caller, not asserted.

const MAX_FILE_BYTES := 8 * 1024 * 1024
## Bundled maps. Writable only in dev mode, from a source checkout.
const DATA_DIRECTORY := "res://data/maps"
## Command-line switch for dev mode: godot --path . -- --maps-dev
const DEV_FLAG := "--maps-dev"
var directory: String
## Where dev mode reads and writes bundled maps (tests point it elsewhere).
var data_directory := DATA_DIRECTORY
## Dev mode opens res://data/maps files in place and saves them back, keeping
## scenario, objectives, quests, teams and unknown keys untouched.
var dev_mode := false
var _data: GameData


func _init(data: GameData, maps_directory: String = "") -> void:
	_data = data
	directory = (maps_directory if maps_directory != "" else data.custom_maps_directory).trim_suffix("/")
	dev_mode = dev_mode_requested()


## Dev mode needs the flag and an editor build of Godot: exported games have a
## read-only res:// and never enable it.
static func dev_mode_requested() -> bool:
	return OS.has_feature("editor") and DEV_FLAG in OS.get_cmdline_user_args()


## Saves a bundled map in place (dev mode only), in the builders' file layout.
func save_data_map(document: MapDocument) -> String:
	if not dev_mode:
		return "Bundled maps can only be saved in dev mode (start with -- %s)." % DEV_FLAG
	if document.has_open_action():
		return "Finish the current edit before saving."
	if not document.is_data_map():
		return "This map is not a bundled map."
	var definition := document.definition()
	var id := String(definition["id"])
	if not valid_local_id(id):
		return "Bundled map ids use lowercase letters, numbers, - and _."
	var error := MapFreezer.write_file(definition, data_path(id))
	if error != "":
		return error
	document.mark_saved()
	return ""


## Opens a bundled map for in-place editing (dev mode only).
func open_data_map(id: String) -> Dictionary:
	if not dev_mode:
		return {"error": "Bundled maps open in place only in dev mode."}
	if not valid_local_id(id):
		return {"error": "Invalid bundled map ID."}
	var result := read_file(data_path(id))
	if not result.has("document"):
		return result
	var document: MapDocument = result["document"]
	if document.definition()["id"] != id:
		return {"error": "Map identity does not match its filename."}
	document.enable_data_editing()
	return result


## Freezes a generated (or any loadable) map id into a new bundled map
## document, unsaved; save_data_map writes it.
func freeze_to_document(source_id: String, out_id: String, title: String = "") -> Dictionary:
	if not dev_mode:
		return {"error": "Freezing maps needs dev mode."}
	var result := MapFreezer.freeze(_data, source_id, out_id, title)
	if result["error"] != "":
		return result
	var problems := MapDocument.structural_errors(result["definition"], _data)
	if not problems.is_empty():
		return {"error": "\n".join(problems)}
	var document := MapDocument.from_definition(result["definition"], _data)
	document.enable_data_editing()
	return {"document": document, "error": ""}


func data_path(id: String) -> String:
	return data_directory.trim_suffix("/").path_join(id + ".json")


func data_map_ids() -> Array[String]:
	var ids: Array[String] = []
	for file in DirAccess.get_files_at(data_directory):
		if String(file).ends_with(".json"):
			ids.append(String(file).get_basename())
	ids.sort()
	return ids


func save(document: MapDocument) -> String:
	if document.has_open_action():
		return "Finish the current edit before saving."
	if document.read_only():
		return "This map contains features that are currently read-only."
	var definition := document.definition()
	var id := String(definition["id"])
	if not id.begins_with("custom:") or not valid_local_id(id.trim_prefix("custom:")):
		return "Save a local copy with a valid custom map ID first."
	var encoded := JSON.stringify(definition, "\t", true, true)
	if encoded.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return "Map exceeds the local file size limit."
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return "Cannot create map directory: %s." % error_string(error)
	var path := _path(id.trim_prefix("custom:"))
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write map: %s." % error_string(FileAccess.get_open_error())
	file.store_string(encoded)
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return "Cannot replace map: %s." % error_string(error)
	document.mark_saved()
	return ""


func load_local(local_id: String) -> Dictionary:
	if not valid_local_id(local_id):
		return {"error": "Invalid local map ID."}
	var result := read_file(_path(local_id))
	if result.has("document"):
		var document: MapDocument = result["document"]
		if document.definition()["id"] != "custom:" + local_id:
			return {"error": "Map identity does not match its filename."}
	return result


## Also used to inspect bundled/imported maps; does not adopt or rewrite identity.
func read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open map: %s." % error_string(FileAccess.get_open_error())}
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return {"error": "Map exceeds the local file size limit."}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK:
		return {"error": "Invalid JSON at line %d: %s." % [json.get_error_line(), json.get_error_message()]}
	if not json.data is Dictionary:
		return {"error": "Map JSON must be a dictionary."}
	var problems := MapDocument.structural_errors(json.data, _data)
	if not problems.is_empty():
		return {"error": "\n".join(problems)}
	var document := MapDocument.from_definition(json.data, _data)
	document.mark_saved()
	return {"document": document, "error": ""}


## Malformed files are reported individually instead of aborting discovery.
func list_local() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(directory):
		return entries
	var files := Array(DirAccess.get_files_at(directory))
	files.sort()
	for filename in files:
		if not String(filename).ends_with(".json"):
			continue
		var id := String(filename).get_basename()
		var result := load_local(id)
		result["local_id"] = id
		entries.append(result)
	return entries


func playable_maps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in list_local():
		if not entry.has("document"):
			continue
		var definition: Dictionary = entry["document"].definition()
		if MapPlayability.errors(definition, _data).is_empty():
			out.append(definition)
	return out


static func valid_local_id(id: String) -> bool:
	if id.is_empty() or id.length() > 80:
		return false
	for ch in id:
		if not ch in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true


func _path(local_id: String) -> String:
	return directory.path_join(local_id + ".json")
