extends SceneTree
## Minimap PNGs of map files for PRs (no renderer needed, see MapPreview).
##   godot --headless --path . --script res://tools/maps/map_preview.gd -- <map> <out.png> [tile_px]
##   godot --headless --path . --script res://tools/maps/map_preview.gd -- --all <out_dir> [tile_px]
## <map> is a map id (data map, gen:..., scenario:..., custom:...) or a path to
## a .json map file. --all renders every res://data/maps file into <out_dir>.


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	if args.size() < 2:
		printerr("usage: map_preview.gd -- <map id | file.json | --all> <out.png | out_dir> [tile_px]")
		quit(1)
		return
	var data := GameData.get_default()
	var tile := int(args[2]) if args.size() > 2 else 6
	var jobs: Array = []
	if String(args[0]) == "--all":
		for id in MapRepository.new(data).data_map_ids():
			jobs.append([id, String(args[1]).path_join(id + ".png")])
	else:
		jobs.append([String(args[0]), String(args[1])])
	var failures := 0
	for job in jobs:
		var definition := _load(data, String(job[0]))
		var error := "Cannot load map %s." % job[0] if definition.is_empty() else MapPreview.save_png(definition, data, String(job[1]), tile)
		if error != "":
			printerr(error)
			failures += 1
		else:
			print("%s -> %s" % [job[0], ProjectSettings.globalize_path(String(job[1]))])
	GameData._default = null
	quit(1 if failures > 0 else 0)


static func _load(data: GameData, source: String) -> Dictionary:
	if source.ends_with(".json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
		return parsed if parsed is Dictionary else {}
	var definition: Variant = data.load_map(source)
	return definition if definition is Dictionary else {}
