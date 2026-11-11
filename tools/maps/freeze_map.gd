extends SceneTree
## Freezes a generated map into a hand-tunable data/maps file.
##   godot --headless --path . --script res://tools/maps/freeze_map.gd -- <source_id> <out_id> \
##       [--name "Title"] [--dir res://data/maps] [--preview /tmp/out.png] [--force]
## <source_id> is anything GameData.load_map accepts: gen:<template>:<seed>,
## gen:random_<size>_<n>p_<monsters>_<treasure>:<seed>, scenario:<recipe>:<seed>,
## or an existing data map id. The output is deterministic (same arguments, same
## bytes) and uses the builders' file layout (tools/maps/maplib.py write()).
## An existing file is only replaced with --force, so hand edits are not lost.
## Exit code: 0 written and valid, 1 usage/IO error, 2 written but MapValidator
## reports problems (printed).


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var options := {"--name": "", "--dir": MapRepository.DATA_DIRECTORY, "--preview": ""}
	var positional: Array[String] = []
	var force := false
	var i := 0
	while i < args.size():
		var arg := String(args[i])
		if arg == "--force":
			force = true
		elif options.has(arg) and i + 1 < args.size():
			options[arg] = String(args[i + 1])
			i += 1
		else:
			positional.append(arg)
		i += 1
	if positional.size() != 2:
		printerr("usage: freeze_map.gd -- <source_id> <out_id> [--name T] [--dir D] [--preview P.png] [--force]")
		quit(1)
		return
	var data := GameData.get_default()
	var source := positional[0]
	var out_id := positional[1]
	var path := String(options["--dir"]).path_join(out_id + ".json")
	var result := MapFreezer.freeze(data, source, out_id, String(options["--name"]))
	if result["error"] != "":
		printerr(result["error"])
		quit(1)
		return
	var definition: Dictionary = result["definition"]
	if FileAccess.file_exists(path) and not force:
		var existing := FileAccess.get_file_as_string(path)
		if existing != MapFileFormat.encode(definition):
			printerr("%s exists and differs (hand edits?). Pass --force to replace it." % path)
			quit(1)
			return
	var error := MapFreezer.write_file(definition, path)
	if error != "":
		printerr(error)
		quit(1)
		return
	print("Froze %s -> %s (%dx%d, %d objects, %d heroes)" % [source, ProjectSettings.globalize_path(path),
		int(definition["width"]), int(definition["height"]), definition["objects"].size(), definition["heroes"].size()])
	if String(options["--preview"]) != "":
		error = MapPreview.save_png(definition, data, String(options["--preview"]))
		print(error if error != "" else "Preview: " + ProjectSettings.globalize_path(String(options["--preview"])))
	var problems := MapValidator.validate(definition, data)
	for problem in problems:
		printerr("  invalid: " + problem)
	GameData._default = null
	quit(0 if problems.is_empty() else 2)
