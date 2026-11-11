extends SceneTree
## Repaints the cosmetic layer of a map file after a builder changed its
## terrain or objects (tools/maps/maplib.py redress()).
##   godot --headless --path . --script res://tools/maps/redress_map.gd -- <in.json> <out.json> <seed>
## Drops the painted decorations, ground variants (surface) and single-tile
## scenery, keeps the large landmarks (footprint above 1x1) and authored
## decorations listed under "keep_decorations" (removed from the output), then
## runs TerrainPainter.dress with the seed. The file is written in the builders'
## layout (MapFileFormat). Exit code: 0 written and valid, 1 usage/IO error,
## 2 written but MapValidator reports problems (printed).


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	if args.size() != 3:
		printerr("usage: redress_map.gd -- <in.json> <out.json> <seed>")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(args[0])))
	if not parsed is Dictionary:
		printerr("cannot read %s" % args[0])
		quit(1)
		return
	var def: Dictionary = parsed
	var data := GameData.get_default()
	var landmarks: Array = []
	for e in def.get("scenery", []):
		var fp: Array = e.get("footprint", [1, 1])
		if int(fp[0]) > 1 or int(fp[1]) > 1:
			landmarks.append(e)
	def["scenery"] = landmarks
	def["decorations"] = def.get("keep_decorations", [])
	def.erase("keep_decorations")
	def.erase("surface")
	TerrainPainter.dress(def, data, int(args[2]))
	if (def["scenery"] as Array).is_empty():
		def.erase("scenery")
	var error := MapFreezer.write_file(def, String(args[1]))
	if error != "":
		printerr(error)
		quit(1)
		return
	var problems := MapValidator.validate(def, data)
	for problem in problems:
		printerr("  invalid: " + problem)
	GameData._default = null
	quit(0 if problems.is_empty() else 2)
