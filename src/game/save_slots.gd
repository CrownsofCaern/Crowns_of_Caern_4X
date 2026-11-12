class_name SaveSlots
extends RefCounted
## Numbered save slots plus an autosave slot, as versioned JSON files under
## user://saves. Each file is a normal GameState save with an extra "meta"
## block (map name, day, players, time) that the save/load menu shows without
## rebuilding the game. Headless; the directory can be overridden for tests.

const DEFAULT_DIR := "user://saves"
const AUTOSAVE := "auto"
## Online games keep their own slot per match ("online_<match id>", see OnlineMatch.save_slot).
const ONLINE_PREFIX := "online_"


static func slot_ids(data: GameData) -> Array[String]:
	var out: Array[String] = [AUTOSAVE]
	for i in int(data.rules["save_slots"]):
		out.append(str(i + 1))
	return out


static func path_for(slot: String, dir: String = DEFAULT_DIR) -> String:
	return dir.path_join("slot_%s.json" % slot)


static func save(session: GameSession, slot: String, dir: String = DEFAULT_DIR) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var d := session.state.to_dict()
	d["meta"] = describe(session)
	var f := FileAccess.open(path_for(slot, dir), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "\t"))
	return OK


## What the menu shows for a running game.
static func describe(session: GameSession) -> Dictionary:
	var st := session.state
	var names := []
	for p in st.players:
		if not p["defeated"]:
			names.append(p["name"])
	var chapter := ""
	if not st.campaign.is_empty() and session.data.campaigns.has(String(st.campaign.get("campaign", ""))):
		var chapters: Array = session.data.campaigns[st.campaign["campaign"]]["chapters"]
		var i := int(st.campaign.get("chapter", 0))
		chapter = String(chapters[i]["name"]) if i >= 0 and i < chapters.size() else ""
	return {"chapter": chapter, "map_name": st.map.name, "day": st.day, "week": st.week(), "day_of_week": st.day_of_week(),
		"current": st.player(st.current_player)["name"], "players": names, "game_over": st.game_over,
		"saved_at": Time.get_datetime_string_from_system(false, true)}


static func load_slot(data: GameData, slot: String, dir: String = DEFAULT_DIR) -> GameSession:
	return GameSession.load_from_file(data, path_for(slot, dir))


## The online games saved in dir (slot ids), in name order.
static func online_slots(dir: String = DEFAULT_DIR) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		var fname := String(f)
		if fname.begins_with("slot_" + ONLINE_PREFIX) and fname.ends_with(".json"):
			out.append(fname.trim_prefix("slot_").trim_suffix(".json"))
	return out


static func is_online_slot(slot: String) -> bool:
	return slot.begins_with(ONLINE_PREFIX)


## Every slot, autosave first, online games last: [{slot, path, exists, valid, label, meta}].
static func list(data: GameData, dir: String = DEFAULT_DIR) -> Array:
	var out := []
	var slots := slot_ids(data)
	slots.append_array(online_slots(dir))
	for slot in slots:
		var path := path_for(slot, dir)
		var row := {"slot": slot, "path": path, "exists": FileAccess.file_exists(path), "valid": false, "meta": {},
			"label": "Autosave" if slot == AUTOSAVE else ("Online" if is_online_slot(slot) else "Slot %s" % slot)}
		if row["exists"]:
			var f := FileAccess.open(path, FileAccess.READ)
			var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
			if typeof(d) == TYPE_DICTIONARY and GameState.validate_save(d).is_empty():
				row["valid"] = true
				row["meta"] = d.get("meta", {"map_name": String(d["map_id"]), "day": int(d["day"])})
		out.append(row)
	return out


static func delete(slot: String, dir: String = DEFAULT_DIR) -> Error:
	var path := path_for(slot, dir)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path)


## One line for the menu: "Mournfield Crossroads - week 2, day 3 - Player to move".
static func summary(row: Dictionary) -> String:
	if not row["exists"]:
		return "Empty"
	if not row["valid"]:
		return "Unreadable save"
	var m: Dictionary = row["meta"]
	var parts := [String(m.get("map_name", "?")) if String(m.get("chapter", "")) == "" else "%s (campaign)" % m["chapter"]]
	if m.has("week"):
		parts.append("week %d, day %d" % [int(m["week"]), int(m["day_of_week"])])
	else:
		parts.append("day %d" % int(m.get("day", 1)))
	if bool(m.get("game_over", false)):
		parts.append("finished")
	elif m.has("current"):
		parts.append("%s to move" % m["current"])
	if m.has("saved_at"):
		parts.append(String(m["saved_at"]))
	return "  ·  ".join(parts)
