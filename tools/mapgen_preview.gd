extends SceneTree
## Generates maps headless and prints an ASCII preview plus fairness metrics.
## Optionally writes a PNG per map (no renderer needed):
##   godot --headless --path . --script res://tools/mapgen_preview.gd -- <template> <seed> [count] [png_dir]
## Legend: T town, M mine (m guarded), $ pile, * guarded treasure, E encounter, G gate guard, g guard,
## w wanderer, H hero, = road.

const TILE := 12


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var tpl := args[0] if args.size() > 0 else "twin_marches"
	var first := int(args[1]) if args.size() > 1 else 1
	var count := int(args[2]) if args.size() > 2 else 1
	var png_dir := args[3] if args.size() > 3 else ""
	var data := GameData.get_default()
	var t0 := Time.get_ticks_msec()
	var failures := 0
	for s in range(first, first + count):
		var gen := MapGenerator.new(data)
		var t := Time.get_ticks_msec()
		var def := gen.run(tpl, s)
		var ms := Time.get_ticks_msec() - t
		var errs: Array = Array(MapValidator.validate(def, data)) if not def.is_empty() else ["generation failed"]
		if not errs.is_empty():
			failures += 1
		print("== %s seed %d: %d ms, attempt %d, %d objects, %s" % [tpl, s, ms, gen.attempts_used,
			def.get("objects", []).size(), "OK" if errs.is_empty() else "INVALID: " + ", ".join(errs)])
		for r in gen.rejected:
			print("   rejected attempt: %s" % ", ".join(r))
		if count == 1 and not def.is_empty():
			print(ascii(def))
			for m in MapValidator.fairness(def, data):
				print("player %d: mines %s, day-one pickups %d, enemy town %d, guards %d" % [m["player"], m["mine_cost"],
					m["day_one_value"], m["enemy_town_cost"], m["guard_value"]])
		if png_dir != "" and not def.is_empty():
			DirAccess.make_dir_recursive_absolute(png_dir)
			render(def, data).save_png("%s/%s_%d.png" % [png_dir, tpl, s])
	print("%d maps, %d invalid, %.1fs" % [count, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


static func _symbol(o: Dictionary) -> String:
	match String(o["type"]):
		"town":
			return "T"
		"mine":
			return "m" if o.has("guard") else "M"
		"encounter":
			return "E"
		"resource":
			return "*" if o.get("treasure", false) else "$"
		"neutral_army":
			return {"gate": "G", "guard": "g"}.get(o.get("role", ""), "w")
	return "?"


static func ascii(def: Dictionary) -> String:
	var rows: Array = def["terrain"].duplicate()
	var map := AdventureMap.from_definition(def.merged({"objects": []}, true), GameData.get_default())
	for y in rows.size():
		var r := String(rows[y])
		for x in r.length():
			if map.has_road(Vector2i(x, y)):
				r[x] = "="
		rows[y] = r
	for o in def["objects"]:
		var r := String(rows[int(o["pos"][1])])
		r[int(o["pos"][0])] = _symbol(o)
		rows[int(o["pos"][1])] = r
	for hd in def["heroes"]:
		var r := String(rows[int(hd["pos"][1])])
		r[int(hd["pos"][0])] = "H"
		rows[int(hd["pos"][1])] = r
	return "\n".join(rows)


static func render(def: Dictionary, data: GameData) -> Image:
	var map := AdventureMap.from_definition(def.merged({"objects": []}, true), data)
	var img := Image.create(map.width * TILE, map.height * TILE, false, Image.FORMAT_RGBA8)
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var col := Color(data.terrain(map.terrain_at(p))["color"])
			if map.has_road(p):
				col = Color(data.road["color"])
			img.fill_rect(Rect2i(x * TILE, y * TILE, TILE, TILE), col)
	var colors := {"T": Color.WHITE, "M": Color("#e8c547"), "m": Color("#b08a20"), "E": Color("#c9a24a"), "$": Color("#5ac8c8"), "*": Color("#ff7ae0"),
		"G": Color("#d01818"), "g": Color("#ff5a3c"), "w": Color("#9a2a8a")}
	for o in def["objects"]:
		var c: Color = colors.get(_symbol(o), Color.BLACK)
		img.fill_rect(Rect2i(int(o["pos"][0]) * TILE + 1, int(o["pos"][1]) * TILE + 1, TILE - 2, TILE - 2), Color.BLACK)
		img.fill_rect(Rect2i(int(o["pos"][0]) * TILE + 2, int(o["pos"][1]) * TILE + 2, TILE - 4, TILE - 4), c)
	for hd in def["heroes"]:
		img.fill_rect(Rect2i(int(hd["pos"][0]) * TILE + 1, int(hd["pos"][1]) * TILE + 1, TILE - 2, TILE - 2), Color("#3d6fc4") if int(hd["owner"]) == 0 else Color("#b8402c"))
	return img
