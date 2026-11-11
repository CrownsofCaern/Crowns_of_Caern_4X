class_name Campaign
extends RefCounted
## Campaign progress: which chapter (map) comes next and the veteran heroes
## that carry over between maps. Headless; the UI starts chapters with
## begin_chapter() and reports the outcome with complete_chapter().
##
## A veteran record is Hero.campaign_dict(): level, XP, primaries, skills,
## unspent points, marks and kept artifacts. Armies, resources and positions
## belong to each map. Campaign saves are versioned JSON and may embed the
## game in progress so one file resumes everything.

## 1: first version.
const CAMPAIGN_VERSION := 1

var campaign_id: String = ""
var chapter: int = 0                 # index of the next chapter to play
var seed_value: int = 1
var roster: Dictionary = {}          # hero id -> Hero.campaign_dict()
var completed: Array[String] = []    # chapter ids won, in order
var active_game: Dictionary = {}     # GameState.to_dict() of the chapter in progress, or {}


static func start(data: GameData, id: String, seed_in: int) -> Campaign:
	assert(data.campaigns.has(id), "unknown campaign %s" % id)
	var c := Campaign.new()
	c.campaign_id = id
	c.seed_value = seed_in
	return c


func definition(data: GameData) -> Dictionary:
	return data.campaigns[campaign_id]


func is_finished(data: GameData) -> bool:
	return chapter >= definition(data)["chapters"].size()


func current_chapter(data: GameData) -> Dictionary:
	var chapters: Array = definition(data)["chapters"]
	return chapters[chapter] if chapter < chapters.size() else {}


func chapter_seed() -> int:
	return GameRng.mix(seed_value, chapter + 1)


## Starts the current chapter: a new game on its map, with every veteran's
## progression applied to the map hero of the same id and the chapter's level
## cap set (banked XP pays out if the cap rose).
func begin_chapter(data: GameData) -> GameSession:
	var ch := current_chapter(data)
	if ch.is_empty():
		return null
	var session := GameSession.new_game(data, ch["map"], chapter_seed(), chapter_setup(ch), chapter_rules(ch))
	var cap := int(ch.get("level_cap", 0))
	for hid in definition(data)["heroes"]:
		var h := session.hero(hid)
		if h == null:
			continue
		session.adopt_veteran(hid, roster.get(hid, {}), cap)
	_take_artifacts(session, ch, data)
	var human := _human_player(session)
	if human >= 0:
		var bank: ResourceBank = session.state.player(human)["resources"]
		var bonus: Dictionary = ch.get("start_resources", {})
		for res in data.resource_order:
			if int(bonus.get(res, 0)) > 0:
				bank.add(res, int(bonus[res]))
	active_game = {}
	session.state.campaign = record()
	return session


## The new-game setup of a chapter: its "setup" (GameSetup players: faction and
## human/computer per map slot) plus its "cast" (heroes placed on the map, how
## a generated map gets the campaign's veterans).
static func chapter_setup(ch: Dictionary) -> Dictionary:
	var setup: Dictionary = ch.get("setup", {}).duplicate(true)
	if not (ch.get("cast", []) as Array).is_empty():
		setup["cast"] = ch["cast"].duplicate(true)
	return setup


## The rule overrides a chapter plays under (GameState.rules): max_tier caps the
## creature tiers every town may build and recruit; ai tunes the computer
## players (StrategicAI settings, e.g. {"passive": true} for a tutorial);
## random_events: false keeps omens and fortunes out of a chapter;
## cold_attrition: false spares a chapter the cold (ColdAttrition; on by default
## in campaigns).
static func chapter_rules(ch: Dictionary) -> Dictionary:
	var rules := {}
	if ch.has("scenario"):
		rules["scenario"] = ch["scenario"].duplicate(true)
	if ch.has("random_events"):
		rules["random_events"] = bool(ch["random_events"])
	if ch.has("cold_attrition"):
		rules["cold_attrition"] = bool(ch["cold_attrition"])
	if int(ch.get("max_tier", 0)) > 0:
		rules["max_tier"] = int(ch["max_tier"])
	var ai: Dictionary = ch.get("ai", {})
	if not ai.is_empty():
		rules["ai"] = ai.duplicate(true)
	return rules


## The campaign's progress without the game in progress: what a chapter's own
## save carries (GameState.campaign), so it can advance the campaign from any slot.
func record() -> Dictionary:
	var d := to_dict()
	d["active_game"] = {}
	return d


## The campaign a loaded game is a chapter of, or null (a skirmish, an old save,
## or a record this build cannot read).
static func of_session(data: GameData, session: GameSession) -> Campaign:
	var d: Dictionary = migrate(session.state.campaign)
	if d.is_empty() or not validate_save(d, data).is_empty():
		return null
	return from_dict(d)


static func _human_player(session: GameSession) -> int:
	for i in session.state.players.size():
		if session.state.player(i)["is_human"]:
			return i
	return -1


## Records the outcome of the current chapter. On a loss nothing changes and
## the chapter can be replayed. On a victory every veteran's progression is
## stored, artifacts are trimmed to carry.max_artifacts (keep: hero id -> list
## of artifact ids to prefer; otherwise the most valuable are kept; with
## carry.keep_worn, everything worn carries and the limit applies to the pack), rewards
## are granted and the campaign moves to the next chapter.
## Returns {ok, won, finished, kept: {hero id: [artifacts]}, dropped: {hero id: [artifacts]}, levels: {hero id: gained}}.
func complete_chapter(data: GameData, session: GameSession, won: bool, keep: Dictionary = {}) -> Dictionary:
	var out := {"ok": true, "won": won, "finished": false, "kept": {}, "dropped": {}, "levels": {}}
	var ch := current_chapter(data)
	if ch.is_empty():
		out["ok"] = false
		return out
	active_game = {}
	if not won:
		return out
	var carry: Dictionary = definition(data).get("carry", {})
	var max_art := int(carry.get("max_artifacts", 4))
	var keep_worn := bool(carry.get("keep_worn", false))
	var veterans: Array = definition(data)["heroes"]
	for hid in veterans:
		var h := session.hero(hid)
		if h == null:
			continue
		var before := int(roster.get(hid, {}).get("level", 1))
		var dropped := _trim_artifacts(h, max_art, keep.get(hid, []), data, keep_worn)
		roster[hid] = h.campaign_dict()
		out["kept"][hid] = h.all_artifacts(data)
		out["dropped"][hid] = dropped
		out["levels"][hid] = h.level - before
	_grant_rewards(data, ch.get("rewards", []), veterans)
	completed.append(String(ch["id"]))
	chapter += 1
	out["finished"] = is_finished(data)
	return out


## Keeps at most `max_art` artifacts: the preferred ones first (in the order
## given), then by value (ties by id). Kept worn artifacts stay worn. With
## keep_worn, worn artifacts always stay and `max_art` limits the pack only.
## A chapter's take_artifacts (artifact ids) leave the veterans for good when the
## chapter starts: the story has taken them (the Gate-Eyes set into the Nightgate).
## Worn or packed, they are removed from the map heroes and from the roster, so a
## replay of the chapter does not bring them back.
func _take_artifacts(session: GameSession, ch: Dictionary, data: GameData) -> void:
	var taken: Array = ch.get("take_artifacts", [])
	if taken.is_empty():
		return
	for hid in definition(data)["heroes"]:
		var h := session.hero(hid)
		if h == null:
			continue
		for slot in data.artifact_slots:
			if taken.has(String(h.equipment.get(slot, ""))):
				h.equipment.erase(slot)
		h.pack = h.pack.filter(func(a): return not taken.has(String(a)))
		if roster.has(hid):
			roster[hid] = h.campaign_dict()


static func _trim_artifacts(h: Hero, max_art: int, prefer: Array, data: GameData, keep_worn: bool = false) -> Array[String]:
	var owned: Array = h.all_artifacts(data)
	var worn: Array[String] = []
	if keep_worn:
		for slot in data.artifact_slots:
			if String(h.equipment.get(slot, "")) != "":
				worn.append(String(h.equipment[slot]))
		owned = owned.filter(func(a): return not worn.has(a))
	var ranked: Array[String] = []
	for a in prefer:
		if owned.has(String(a)) and not ranked.has(String(a)):
			ranked.append(String(a))
	var rest := owned.filter(func(a): return not ranked.has(a))
	rest.sort_custom(func(a, b):
		var va := int(data.artifacts[a]["value"])
		var vb := int(data.artifacts[b]["value"])
		return va > vb or (va == vb and a < b))
	for a in rest:
		ranked.append(String(a))
	var kept := ranked.slice(0, maxi(0, max_art))
	kept.append_array(worn)
	var dropped: Array[String] = []
	for slot in data.artifact_slots:
		var a := String(h.equipment.get(slot, ""))
		if a != "" and not kept.has(a):
			h.equipment.erase(slot)
			dropped.append(a)
	var pack: Array[String] = []
	for a in h.pack:
		if kept.has(a):
			pack.append(a)
		else:
			dropped.append(a)
	h.pack = pack
	for a in pack.duplicate():
		if String(h.equipment.get(data.artifacts[a]["slot"], "")) == "":
			h.equip(a, data)
	return dropped


func _grant_rewards(data: GameData, rewards: Array, veterans: Array) -> void:
	for r in rewards:
		match String(r["type"]):
			"xp":
				for hid in veterans:
					if roster.has(hid):
						var h := _record_hero(hid, data)
						h.add_xp(h.xp_with_bonus(int(r["amount"]), data), data)
						roster[hid] = h.campaign_dict()
			"artifact":
				for hid in veterans:
					if roster.has(hid):
						var h := _record_hero(hid, data)
						if h.give_artifact(String(r["artifact"]), data):
							roster[hid] = h.campaign_dict()
						break


## A detached Hero built from a roster record (for applying rewards).
func _record_hero(hid: String, data: GameData) -> Hero:
	var rec: Dictionary = roster[hid]
	var h := Hero.new()
	h.id = hid
	h.name = rec["name"]
	h.class_id = rec["class"]
	h.faction = rec["faction"]
	h.apply_campaign(rec)
	h.level_cap = int(current_chapter(data).get("level_cap", 0)) if not is_finished(data) else 0
	return h


# ------------------------------------------------------------- save/load --

func to_dict(session: GameSession = null) -> Dictionary:
	var game := active_game
	if session != null:
		game = session.state.to_dict()
	return {"campaign_version": CAMPAIGN_VERSION, "campaign": campaign_id, "chapter": chapter, "seed": seed_value,
		"roster": roster.duplicate(true), "completed": completed.duplicate(), "active_game": game.duplicate(true)}


## Campaigns that were folded into others: old id -> {campaign, chapter_offset,
## chapters: {old chapter id: new chapter id}}. Their saves load as the new one.
const LEGACY := {
	"ember_chronicle": {"campaign": "last_light", "chapter_offset": 7,
		"chapters": {"ford_burning": "ll_ford", "ford_ashes": "ll_ashes", "ford_embers": "ll_embers"}},
}


## A campaign record of a folded campaign rewritten as the campaign it became
## (other records are returned unchanged).
static func migrate(d: Dictionary) -> Dictionary:
	var legacy: Dictionary = LEGACY.get(String(d.get("campaign", "")), {})
	if legacy.is_empty():
		return d
	var out := d.duplicate(true)
	out["campaign"] = legacy["campaign"]
	out["chapter"] = int(d.get("chapter", 0)) + int(legacy["chapter_offset"])
	var done := []
	for id in d.get("completed", []):
		done.append(legacy["chapters"].get(String(id), String(id)))
	out["completed"] = done
	var game: Dictionary = out.get("active_game", {})
	if not game.is_empty() and typeof(game.get("campaign", null)) == TYPE_DICTIONARY and not game["campaign"].is_empty():
		game["campaign"] = migrate(game["campaign"])
	return out


static func from_dict(d_in: Dictionary) -> Campaign:
	var d := migrate(d_in)
	var c := Campaign.new()
	c.campaign_id = d["campaign"]
	c.chapter = int(d["chapter"])
	c.seed_value = int(d["seed"])
	c.roster = d["roster"].duplicate(true)
	for id in d.get("completed", []):
		c.completed.append(String(id))
	c.active_game = d.get("active_game", {}).duplicate(true)
	return c


static func validate_save(d_in: Dictionary, data: GameData) -> Array[String]:
	var d := migrate(d_in)
	var errors: Array[String] = []
	for key in ["campaign_version", "campaign", "chapter", "seed", "roster"]:
		if not d.has(key):
			errors.append("missing '%s'" % key)
	if not errors.is_empty():
		return errors
	if int(d["campaign_version"]) > CAMPAIGN_VERSION:
		errors.append("campaign save version %d is newer than supported %d" % [int(d["campaign_version"]), CAMPAIGN_VERSION])
	if not data.campaigns.has(d["campaign"]):
		errors.append("unknown campaign %s" % d["campaign"])
	elif int(d["chapter"]) < 0 or int(d["chapter"]) > data.campaigns[d["campaign"]]["chapters"].size():
		errors.append("chapter out of range")
	for hid in d["roster"]:
		var rec: Dictionary = d["roster"][hid]
		if not data.hero_classes.has(rec.get("class", "")):
			errors.append("veteran %s has unknown class" % hid)
	var game: Dictionary = d.get("active_game", {})
	if not game.is_empty():
		for e in GameState.validate_save(game):
			errors.append("active game: " + e)
	return errors


## The chapter in progress from a loaded campaign save, or null if none.
func resume(data: GameData) -> GameSession:
	if active_game.is_empty():
		return null
	var session := GameSession.from_state(data, GameState.from_dict(active_game, data))
	# Progress files written before save v7 hold a chapter without its campaign
	# record; attach it so a later save to any slot still advances the campaign.
	if session.state.campaign.is_empty():
		session.state.campaign = record()
	return session


func save_to_file(path: String, session: GameSession = null) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(session), "\t"))
	return OK


static func load_from_file(data: GameData, path: String) -> Campaign:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or not validate_save(d, data).is_empty():
		return null
	return from_dict(d)


# --------------------------------------------------------------- progress --
# One progress file per campaign, so the menu can continue where the player
# stopped. It embeds the chapter in progress (see to_dict()).

const SAVE_DIR := "user://saves"


static func progress_path(id: String, dir: String = SAVE_DIR) -> String:
	return dir.path_join("campaign_%s.json" % id)


## Writes this campaign's progress, with the chapter being played if given.
func save_progress(session: GameSession = null, dir: String = SAVE_DIR) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	return save_to_file(progress_path(campaign_id, dir), session)


## The saved progress of a campaign, or null if there is none (or it is unreadable).
static func load_progress(data: GameData, id: String, dir: String = SAVE_DIR) -> Campaign:
	var path := progress_path(id, dir)
	if not FileAccess.file_exists(path):
		# Progress of a campaign that was folded into this one.
		for old in LEGACY:
			if String(LEGACY[old]["campaign"]) == id and FileAccess.file_exists(progress_path(old, dir)):
				path = progress_path(old, dir)
				break
	if not FileAccess.file_exists(path):
		return null
	var c := load_from_file(data, path)
	return c if c != null and c.campaign_id == id else null


## Chapters for the campaign menu: [{index, id, name, text, map, level_cap,
## state: "done" | "current" | "locked"}].
func chapter_list(data: GameData) -> Array:
	var out := []
	var chapters: Array = definition(data)["chapters"]
	for i in chapters.size():
		var ch: Dictionary = chapters[i]
		out.append({"index": i, "id": ch["id"], "name": ch["name"], "text": ch.get("text", ""), "map": ch["map"],
			"level_cap": int(ch.get("level_cap", 0)), "max_tier": int(ch.get("max_tier", 0)),
			"state": "done" if i < chapter else ("current" if i == chapter else "locked")})
	return out


## One line per veteran for the menu: "Aldous Wren, level 3 Knight".
func roster_lines(data: GameData) -> Array[String]:
	var out: Array[String] = []
	for hid in definition(data)["heroes"]:
		if not roster.has(hid):
			continue
		var rec: Dictionary = roster[hid]
		var cls: Dictionary = data.hero_classes.get(rec.get("class", ""), {})
		out.append("%s, level %d %s" % [rec.get("name", hid), int(rec.get("level", 1)), cls.get("name", "")])
	return out


# ------------------------------------------------------------- validation --

## Campaign definitions in data/campaigns.json.
static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var top := (data.progression["xp_thresholds"] as Array).size()
	for cid in data.campaigns:
		var c: Dictionary = data.campaigns[cid]
		var where := "campaign %s" % cid
		if not c.has("name") or c.get("heroes", []).is_empty() or c.get("chapters", []).is_empty():
			errors.append("%s needs a name, heroes and chapters" % where)
			continue
		if not data.factions.has(c.get("faction", "")):
			errors.append("%s has unknown faction" % where)
		var last_cap := 0
		var last_tier := 0
		var ids := {}
		for ch in c["chapters"]:
			var cw := "%s chapter %s" % [where, ch.get("id", "?")]
			if ids.has(ch.get("id", "")):
				errors.append("%s id is not unique" % cw)
			ids[ch.get("id", "")] = true
			var map_id := String(ch.get("map", ""))
			var map_heroes := {}
			var scenario_map := {}
			if ScenarioGenerator.is_generated_id(map_id):
				var parsed := ScenarioGenerator.parse_id(map_id)
				if parsed.is_empty() or not data.scenario_recipes.get("recipes", {}).has(parsed.get("recipe", "")):
					errors.append("%s uses unknown scenario recipe %s" % [cw, map_id])
					continue
			elif MapGenerator.is_generated_id(map_id):
				var parsed := MapGenerator.parse_id(map_id)
				if parsed.is_empty() or not MapGenerator.has_template(data.map_templates, parsed["template"]):
					errors.append("%s uses unknown map template %s" % [cw, map_id])
					continue
			else:
				var path := "%s/maps/%s.json" % [GameData.DATA_DIR, map_id]
				if not FileAccess.file_exists(path):
					errors.append("%s uses unknown map %s" % [cw, map_id])
					continue
				var m: Dictionary = GameData.read_json(path)
				scenario_map = m.duplicate(true) if ch.has("scenario") else {}
				for h in m.get("heroes", []):
					map_heroes[h["id"]] = h
			for cd in ch.get("cast", []):
				for key in ["id", "name", "class"]:
					if not cd.has(key):
						errors.append("%s cast hero needs %s" % [cw, key])
				map_heroes[cd.get("id", "")] = cd
				for st in cd.get("army", []):
					if data.creature(String(st[0])).is_empty():
						errors.append("%s cast hero %s has unknown creature %s" % [cw, cd.get("id", ""), st[0]])
			var setup_errors := _validate_setup(ch, data)
			for e in setup_errors:
				errors.append("%s setup %s" % [cw, e])
			if not map_heroes.has(c["heroes"][0]):
				errors.append("%s map has no lead hero %s" % [cw, c["heroes"][0]])
			for hid in c["heroes"]:
				if map_heroes.has(hid) and not data.hero_classes.has(map_heroes[hid].get("class", "")):
					errors.append("%s hero %s has unknown class" % [cw, hid])
			var cap := int(ch.get("level_cap", 0))
			if cap < 0 or cap > top or (cap > 0 and cap < last_cap):
				errors.append("%s level_cap must rise from chapter to chapter and stay within the XP table" % cw)
			last_cap = maxi(last_cap, cap)
			if ch.has("cold_attrition") and typeof(ch["cold_attrition"]) != TYPE_BOOL:
				errors.append("%s cold_attrition must be true or false" % cw)
			var tier := int(ch.get("max_tier", 0))
			var top_tier := data.max_creature_tier()
			var eff_tier := tier if tier > 0 else top_tier
			if tier < 0 or tier > top_tier or eff_tier < last_tier:
				errors.append("%s max_tier must not fall from chapter to chapter and must stay within 1-%d (0 = no limit)" % [cw, top_tier])
			last_tier = maxi(last_tier, eff_tier)
			var scenario_errors := ScenarioRules.validate(ch.get("scenario", {}), {}, data)
			if scenario_errors.is_empty() and not scenario_map.is_empty() and not ch.get("scenario", {}).is_empty() and setup_errors.is_empty():
				scenario_map = GameSetup.apply(scenario_map, chapter_setup(ch), data)
				var scenario_heroes := {}
				for hd in scenario_map["heroes"]:
					scenario_heroes[String(hd["id"])] = hd
				for cd in ch.get("cast", []):
					scenario_heroes.erase(String(cd.get("replaces", "")))
					scenario_heroes[String(cd["id"])] = cd
				scenario_map["heroes"] = scenario_heroes.values()
				scenario_errors = ScenarioRules.validate(ch["scenario"], scenario_map, data)
			for e in scenario_errors:
				errors.append("%s scenario %s" % [cw, e])
			for e in validate_ai_settings(ch.get("ai", {})):
				errors.append("%s ai %s" % [cw, e])
			for key in ["text", "intro", "outro"]:
				if ch.has(key) and typeof(ch[key]) != TYPE_STRING:
					errors.append("%s %s must be text" % [cw, key])
			for res in ch.get("start_resources", {}):
				if not data.resources.has(res):
					errors.append("%s grants unknown resource %s" % [cw, res])
			for a in ch.get("take_artifacts", []):
				if typeof(a) != TYPE_STRING or not data.artifacts.has(a):
					errors.append("%s takes unknown artifact %s" % [cw, a])
			for r in ch.get("rewards", []):
				match String(r.get("type", "")):
					"xp":
						if int(r.get("amount", 0)) <= 0:
							errors.append("%s xp reward needs a positive amount" % cw)
					"artifact":
						if not data.artifacts.has(r.get("artifact", "")):
							errors.append("%s rewards unknown artifact" % cw)
					_:
						errors.append("%s has unknown reward %s" % [cw, r.get("type", "")])
	return errors


## Errors in a chapter's computer-player settings: every key must be a
## StrategicAI setting and keep that setting's type.
static func validate_ai_settings(ai: Variant) -> Array[String]:
	var errors: Array[String] = []
	if typeof(ai) != TYPE_DICTIONARY:
		errors.append("must be a dictionary")
		return errors
	for key in ai:
		if not StrategicAI.DEFAULT_SETTINGS.has(key):
			errors.append("has unknown setting %s" % key)
			continue
		var want := typeof(StrategicAI.DEFAULT_SETTINGS[key])
		var have := typeof(ai[key])
		var numeric := [TYPE_INT, TYPE_FLOAT]
		if want != have and not (numeric.has(want) and numeric.has(have)):
			errors.append("setting %s has the wrong type" % key)
	return errors


## Errors in a chapter's setup: known factions, difficulty levels, teams and a known
## human/computer type per slot (the slot count is checked when the map loads).
static func _validate_setup(ch: Dictionary, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	for o in ch.get("setup", {}).get("players", []):
		if not ["human", "computer", "closed"].has(String(o.get("type", "computer"))):
			errors.append("has unknown player type %s" % o.get("type", ""))
		if o.has("faction") and not GameSetup.playable_factions(data).has(String(o["faction"])):
			errors.append("has unplayable faction %s" % o["faction"])
		if o.has("difficulty") and not data.difficulty_levels().has(String(o["difficulty"])):
			errors.append("has unknown difficulty %s" % o["difficulty"])
		if o.has("team") and (typeof(o["team"]) != TYPE_FLOAT and typeof(o["team"]) != TYPE_INT or int(o["team"]) < 0 or int(o["team"]) > GameSetup.MAX_TEAMS):
			errors.append("has invalid team %s (0 = none, up to %d)" % [o["team"], GameSetup.MAX_TEAMS])
	return errors
