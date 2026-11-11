extends SceneTree
## Map generator quality report and contact sheets (map overhaul, step 1).
##
##   godot --headless --path . --script res://tools/mapgen_quality.gd -- \
##       [seeds=50] [report.md] [size=m] [players=2] [families=all|a,b] [sheet_dir] [sheet_seeds=20]
##
## For every layout family it generates `seeds` random maps
## (random_<size>_<players>p_normal_normal_<family>) and reports:
##   validity      maps that pass MapValidator, attempts, time
##   size          map side and open tiles per player
##   start spread  movement cost between the two first starts (mean, min-max, spread)
##   town spots    how many different tiles player 0's town used, and how far
##                 those tiles lie from their average (share of the map side)
##   direction     compass direction from player 0's town to player 1's town
##                 (8 sectors): distinct sectors and the most common one's share
##   passes        widths of unguarded and guarded passes
##   optional      share of open tiles in optional zones (valleys, mine lands, ruins, backwaters)
##   towns         neutral towns per map
##   walls         share of lake among wall and obstacle tiles
## `families` may also name a plain template (e.g. "legacy:random_m_2p_normal_normal"
## or "legacy:twin_marches") to measure the old generator output side by side.
## With a sheet_dir it also renders a contact sheet of the first sheet_seeds
## maps per family as minimaps (sheet_<family>.png).

const SECTORS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const PX := 3


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 50
	var out_path := args[1] if args.size() > 1 else ""
	var size := args[2] if args.size() > 2 else "m"
	var players := int(args[3]) if args.size() > 3 else 2
	var fam_arg := args[4] if args.size() > 4 else "all"
	var sheet_dir := args[5] if args.size() > 5 else ""
	var sheet_seeds := int(args[6]) if args.size() > 6 else 20
	var data := GameData.get_default()
	var cfg := data.map_templates
	var fams: Array = LayoutFamilies.for_players(cfg, players) if fam_arg == "all" else Array(fam_arg.split(","))
	var lines: Array[String] = []
	lines.append("# Map generator quality report")
	lines.append("")
	lines.append("%d seeds per family, size %s, %d players, normal monsters and treasure. Generator v%d." % [seeds, size, players, MapGenerator.VERSION])
	lines.append("")
	lines.append("| Family | Valid | Attempts | ms/map | Side | Tiles/player | Start cost mean (min-max) | Spread | Town tiles | Town drift | Directions | Top dir | Open pass widths | Guarded widths | Optional | Neutral towns | Lake share |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	var summary := {}
	for fam in fams:
		var tname := String(fam).trim_prefix("legacy:") if String(fam).begins_with("legacy:") else RandomMapTemplate.make_name(size, players, "normal", "normal", String(fam))
		var r := _measure(data, tname, seeds, sheet_dir, sheet_seeds, String(fam).replace(":", "_"))
		summary[fam] = r
		lines.append("| %s | %d/%d | %.2f | %d | %d | %d | %d (%d-%d) | %.2f | %d | %.1f%% | %d | %s %d%% | %s | %s | %.0f%% | %s | %.0f%% |" % [fam, r["valid"], seeds,
			r["attempts"], r["ms"], r["side"], r["tiles_per_player"], r["cost_mean"], r["cost_min"], r["cost_max"], r["cost_spread"],
			r["town_tiles"], r["town_drift"] * 100.0, r["directions"], r["top_dir"], int(r["top_share"] * 100.0),
			_hist(r["open_widths"]), _hist(r["guard_widths"]), r["optional"] * 100.0, _hist(r["towns"]), r["lake"] * 100.0])
		print(lines[lines.size() - 1])
	lines.append("")
	lines.append("Spread: (max - min) / mean of the start-to-start movement cost across seeds. Town drift: mean distance of")
	lines.append("player 0's town from its average position, as a share of the map side. Directions: compass sectors (of 8)")
	lines.append("seen for the line from player 0's town to player 1's. Widths and towns are histograms (value x count).")
	var text := "\n".join(lines) + "\n"
	if out_path != "":
		var dir := out_path.get_base_dir()
		if dir != "":
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir)
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print("wrote ", out_path)
	quit()


func _measure(data: GameData, tname: String, seeds: int, sheet_dir: String, sheet_seeds: int, label: String) -> Dictionary:
	var r := {"valid": 0, "attempts": 0.0, "ms": 0, "side": 0, "tiles_per_player": 0, "cost_mean": 0, "cost_min": 0, "cost_max": 0,
		"cost_spread": 0.0, "town_tiles": 0, "town_drift": 0.0, "directions": 0, "top_dir": "-", "top_share": 0.0,
		"open_widths": {}, "guard_widths": {}, "optional": 0.0, "towns": {}, "lake": 0.0}
	var costs: Array = []
	var town_pos: Array = []
	var dirs := {}
	var opt_sum := 0.0
	var lake_sum := 0.0
	var tiles_sum := 0
	var total_ms := 0
	var total_attempts := 0
	var thumbs: Array = []
	for s in range(1, seeds + 1):
		var gen := MapGenerator.new(data)
		var t0 := Time.get_ticks_msec()
		var def := gen.run(tname, s)
		total_ms += Time.get_ticks_msec() - t0
		total_attempts += gen.attempts_used
		if def.is_empty() or not MapValidator.validate(def, data).is_empty():
			continue
		r["valid"] += 1
		var w := int(def["width"])
		var h := int(def["height"])
		r["side"] = w
		var starts := {}
		for o in def["objects"]:
			if o["type"] == "town" and int(o.get("owner", -1)) >= 0:
				starts[int(o["owner"])] = Vector2(float(o["pos"][0]), float(o["pos"][1]))
		var neutral := (def["objects"] as Array).filter(func(o): return o["type"] == "town" and int(o.get("owner", -1)) < 0).size()
		r["towns"][neutral] = int(r["towns"].get(neutral, 0)) + 1
		if starts.has(0) and starts.has(1):
			town_pos.append(starts[0] / float(w))
			var v: Vector2 = starts[1] - starts[0]
			var sector := int(round(fposmod(v.angle(), TAU) / (TAU / 8.0))) % 8
			dirs[sector] = int(dirs.get(sector, 0)) + 1
		var fair := MapValidator.fairness(def, data)
		if not fair.is_empty() and int(fair[0]["enemy_town_cost"]) > 0:
			costs.append(int(fair[0]["enemy_town_cost"]))
		var gz: Array = def["generator"]["zones"]
		var open := 0
		var opt := 0
		for z in gz:
			open += int(z["tiles"])
			if bool(z.get("optional", false)):
				opt += int(z["tiles"])
		opt_sum += float(opt) / maxf(1.0, float(open))
		tiles_sum += open / maxi(1, (def["players"] as Array).size())
		var gates := {}
		for c in def["generator"]["connections"]:
			var width := (c["gate"] as Array).size()
			var key := "guard_widths" if String(c.get("guard", "")) != "" else "open_widths"
			r[key][width] = int(r[key].get(width, 0)) + 1
		var rock := 0
		var lake := 0
		for row in def["terrain"]:
			for ch in String(row):
				if ch == String(data.terrain("water")["char"]):
					lake += 1
				elif ch == String(data.terrain("mountain")["char"]):
					rock += 1
		lake_sum += float(lake) / maxf(1.0, float(lake + rock))
		if sheet_dir != "" and thumbs.size() < sheet_seeds:
			thumbs.append(_thumb(def, data))
	var n := maxi(1, int(r["valid"]))
	r["attempts"] = float(total_attempts) / float(seeds)
	r["ms"] = total_ms / maxi(1, seeds)
	r["tiles_per_player"] = tiles_sum / n
	r["optional"] = opt_sum / n
	r["lake"] = lake_sum / n
	if not costs.is_empty():
		var sum := 0
		for c in costs:
			sum += int(c)
		r["cost_mean"] = sum / costs.size()
		r["cost_min"] = costs.min()
		r["cost_max"] = costs.max()
		r["cost_spread"] = float(int(r["cost_max"]) - int(r["cost_min"])) / maxf(1.0, float(r["cost_mean"]))
	if not town_pos.is_empty():
		var unique := {}
		var mean := Vector2.ZERO
		for p in town_pos:
			mean += p
		mean /= float(town_pos.size())
		var drift := 0.0
		for p in town_pos:
			unique["%.3f,%.3f" % [p.x, p.y]] = true
			drift += (p - mean).length()
		r["town_tiles"] = unique.size()
		r["town_drift"] = drift / float(town_pos.size())
		r["directions"] = dirs.size()
		var best := -1
		for k in dirs:
			if best < 0 or int(dirs[k]) > int(dirs[best]) or (int(dirs[k]) == int(dirs[best]) and int(k) < best):
				best = int(k)
		r["top_dir"] = SECTORS[best]
		r["top_share"] = float(dirs[best]) / float(town_pos.size())
	if sheet_dir != "" and not thumbs.is_empty():
		DirAccess.make_dir_recursive_absolute(sheet_dir)
		_sheet(thumbs).save_png("%s/sheet_%s.png" % [sheet_dir, label])
	return r


static func _hist(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	return " ".join(keys.map(func(k): return "%sx%d" % [k, d[k]])) if not keys.is_empty() else "-"


## A minimap: terrain, roads, object dots, towns as white blocks with the owner's colour.
static func _thumb(def: Dictionary, data: GameData) -> Image:
	var w := int(def["width"])
	var h := int(def["height"])
	var img := Image.create(w * PX, h * PX, false, Image.FORMAT_RGBA8)
	var colors := {}
	for t in data.terrains:
		colors[String(data.terrain(t)["char"])] = Color(data.terrain(t)["color"])
	for y in h:
		var row := String(def["terrain"][y])
		for x in w:
			img.fill_rect(Rect2i(x * PX, y * PX, PX, PX), colors.get(row[x], Color.MAGENTA))
	var road_col := Color(data.road["color"])
	for seg in def.get("roads", []):
		var a := Vector2i(int(seg["from"][0]), int(seg["from"][1]))
		var b := Vector2i(int(seg["to"][0]), int(seg["to"][1]))
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
				img.fill_rect(Rect2i(x * PX, y * PX, PX, PX), road_col)
	var player_col := {}
	for p in def["players"]:
		player_col[int(p["id"])] = Color(p["color"])
	for o in def["objects"]:
		var x := int(o["pos"][0]) * PX
		var y := int(o["pos"][1]) * PX
		match String(o["type"]):
			"town":
				var c: Color = player_col.get(int(o.get("owner", -1)), Color.WHITE)
				img.fill_rect(Rect2i(x - PX, y - PX, PX * 3, PX * 3), Color.BLACK)
				img.fill_rect(Rect2i(x - PX + 1, y - PX + 1, PX * 3 - 2, PX * 3 - 2), c)
			"neutral_army":
				img.fill_rect(Rect2i(x, y, PX, PX), Color("#d01818") if o.get("role", "") == "gate" else Color("#ff7a5c"))
			"mine":
				img.fill_rect(Rect2i(x, y, PX, PX), Color("#f0c838"))
			"site":
				img.fill_rect(Rect2i(x, y, PX, PX), Color("#b46cff"))
	return img


static func _sheet(thumbs: Array) -> Image:
	var cols := 5
	var cell := 0
	for t in thumbs:
		cell = maxi(cell, (t as Image).get_width())
	cell += 6
	var rows := int(ceil(thumbs.size() / float(cols)))
	var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#141014"))
	for k in thumbs.size():
		var t: Image = thumbs[k]
		sheet.blit_rect(t, Rect2i(Vector2i.ZERO, t.get_size()), Vector2i((k % cols) * cell + 3, (k / cols) * cell + 3))
	return sheet
