extends SceneTree
## Applies a new-game setup (GameSetup.apply: factions, names, colours, teams,
## difficulty per slot) to a map file, so a campaign builder can store a frozen
## generator map with its story factions instead of converting at every start
## (tools/maps/maplib.py apply_setup()). Hero ids stay as they were, so
## campaign casts can still replace hero_p0/hero_p1.
##   godot --headless --path . --script res://tools/maps/apply_setup.gd -- <in.json> <setup.json> <out.json>
## Exit code: 0 written, 1 usage/IO error or invalid setup.


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	if args.size() != 3:
		printerr("usage: apply_setup.gd -- <in.json> <setup.json> <out.json>")
		quit(1)
		return
	var def: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(args[0])))
	var setup: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(args[1])))
	if not def is Dictionary or not setup is Dictionary:
		printerr("cannot read %s or %s" % [args[0], args[1]])
		quit(1)
		return
	var data := GameData.get_default()
	var errors := GameSetup.validate(def, setup, data)
	if not errors.is_empty():
		printerr("invalid setup: " + ", ".join(errors))
		quit(1)
		return
	var out := GameSetup.apply(def, setup, data)
	var ids := {}
	for hd in def["heroes"]:
		ids[Vector2i(int(hd["pos"][0]), int(hd["pos"][1]))] = hd["id"]
	for hd in out["heroes"]:
		var key := Vector2i(int(hd["pos"][0]), int(hd["pos"][1]))
		if ids.has(key):
			hd["id"] = ids[key]
	for p in out["players"]:
		for key in ["hero_class"]:
			if String(p.get(key, "")) == "":
				p.erase(key)
		if int(p.get("team", 0)) == 0:
			p.erase("team")
		if String(p.get("difficulty", "")) == data.default_difficulty():
			p.erase("difficulty")
	var error := MapFreezer.write_file(out, String(args[2]))
	if error != "":
		printerr(error)
		quit(1)
		return
	GameData._default = null
	quit(0)
