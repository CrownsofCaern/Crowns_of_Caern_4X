class_name GameData
extends RefCounted
## Read-only registry of all data definitions in res://data.
##
## Gameplay code receives a GameData instance instead of reading files itself,
## so tests can construct variants and nothing depends on autoloads.

const DATA_DIR := "res://data"
var custom_maps_directory := "user://maps"

static var _default: GameData = null

var terrains: Dictionary = {}
var terrain_by_char: Dictionary = {}
var road: Dictionary = {}
var resources: Dictionary = {}
var resource_order: Array = []
var starting_resources: Dictionary = {}
var factions: Dictionary = {}
var creatures: Dictionary = {}
var creature_sources: Dictionary = {}   # creature id -> file it was loaded from
var duplicate_creatures: Array[String] = []
var abilities: Dictionary = {}
var hero_classes: Dictionary = {}
var skills: Dictionary = {}
var skill_max_level: int = 3
var progression: Dictionary = {}
var combat: Dictionary = {}
var map_templates: Dictionary = {}
var scenario_recipes: Dictionary = {}
var terrain_painting: Dictionary = {}
var encounters: Dictionary = {}
var encounter_rules: Dictionary = {}   # chance_floor, chance_cap, marks
var town_types: Dictionary = {}   # faction id -> {name, starting_buildings, hire, buildings{}}
var economy: Dictionary = {}      # market, mines, build limits (data/buildings.json "economy")
var artifacts: Dictionary = {}
var artifact_slots: Array = []
var artifact_rules: Dictionary = {}   # pack_size, drop_slots
var artifact_sets: Dictionary = {}    # set id -> {name, pieces, bonuses: [{pieces, mods, text}]}
var campaigns: Dictionary = {}
var rules: Dictionary = {}        # game flow: town-loss timer, save slots (data/game_rules.json)
var ai_difficulty: Dictionary = {}   # computer-player levels: {order, default, levels} (data/ai_difficulty.json)
var sites: Dictionary = {}        # rare map buildings (data/sites.json, see MapSites)
var magic: Dictionary = {}
var world_events: Dictionary = {} # weekly omens and daily fortunes (data/events.json, see WorldEvents)
var hero_specialties: Dictionary = {}   # specialty id -> {name, faction, text, mods, growth, formations, heroes} (see HeroSpecialties)
var specialty_by_hero: Dictionary = {}  # hero name -> specialty id
var tactics: Dictionary = {}      # hero battle orders: stance, focus, formation, art timing, retreat (data/tactics.json, see BattleOrders)
var faction_mechanics: Dictionary = {}   # one adventure-map mechanic per faction (data/faction_mechanics.json, see FactionMechanics)


static func get_default() -> GameData:
	if _default == null:
		_default = GameData.new()
		_default.load_all(DATA_DIR)
	return _default


static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("GameData: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("GameData: invalid JSON in %s" % path)
	return parsed


func load_all(dir: String) -> void:
	var t: Dictionary = read_json(dir + "/terrains.json")
	terrains = t["terrains"]
	road = t["road"]
	for id in terrains:
		terrain_by_char[terrains[id]["char"]] = id
	var r: Dictionary = read_json(dir + "/resources.json")
	resources = r["resources"]
	resource_order = r["order"]
	starting_resources = r["starting"]
	factions = read_json(dir + "/factions.json")["factions"]
	_load_creatures(dir)
	abilities = read_json(dir + "/abilities.json")["abilities"]
	hero_classes = read_json(dir + "/hero_classes.json")["classes"]
	var s: Dictionary = read_json(dir + "/skills.json")
	skills = s["skills"]
	skill_max_level = int(s["max_level"])
	progression = read_json(dir + "/progression.json")
	magic = read_json(dir + "/spells.json")
	combat = read_json(dir + "/combat_config.json")
	if FileAccess.file_exists(dir + "/scenario_recipes.json"):
		scenario_recipes = read_json(dir + "/scenario_recipes.json")
	if FileAccess.file_exists(dir + "/map_templates.json"):
		map_templates = read_json(dir + "/map_templates.json")
	if FileAccess.file_exists(dir + "/terrain_painting.json"):
		terrain_painting = read_json(dir + "/terrain_painting.json")
	var e: Dictionary = read_json(dir + "/encounters.json")
	encounters = e["encounters"]
	encounter_rules = {"chance_floor": float(e.get("chance_floor", 0.05)), "chance_cap": float(e.get("chance_cap", 0.95)),
		"marks": e.get("marks", {})}
	var b: Dictionary = read_json(dir + "/buildings.json")
	town_types = b["towns"]
	economy = b["economy"]
	var art: Dictionary = read_json(dir + "/artifacts.json")
	artifacts = art["artifacts"]
	artifact_slots = art["slots"]
	artifact_rules = {"pack_size": int(art.get("pack_size", 8)), "drop_slots": art.get("drop_slots", [])}
	artifact_sets = art.get("sets", {})
	campaigns = read_json(dir + "/campaigns.json")["campaigns"]
	rules = read_json(dir + "/game_rules.json")
	ai_difficulty = read_json(dir + "/ai_difficulty.json")
	if FileAccess.file_exists(dir + "/sites.json"):
		sites = read_json(dir + "/sites.json")["sites"]
	if FileAccess.file_exists(dir + "/events.json"):
		world_events = read_json(dir + "/events.json")
	if FileAccess.file_exists(dir + "/tactics.json"):
		tactics = read_json(dir + "/tactics.json")
	if FileAccess.file_exists(dir + "/faction_mechanics.json"):
		faction_mechanics = read_json(dir + "/faction_mechanics.json")
		faction_mechanics.erase("_doc")
	hero_specialties = {}
	specialty_by_hero = {}
	if FileAccess.file_exists(dir + "/hero_specialties.json"):
		hero_specialties = read_json(dir + "/hero_specialties.json")["specialties"]
		for sid in hero_specialties:
			for hname in hero_specialties[sid].get("heroes", []):
				if not specialty_by_hero.has(hname):
					specialty_by_hero[hname] = sid


## Merges data/creatures.json with every data/creatures/*.json (file names
## sorted, so the result never depends on directory order).
func _load_creatures(dir: String) -> void:
	creatures = {}
	creature_sources = {}
	duplicate_creatures = []
	var files: Array[String] = [dir + "/creatures.json"]
	var sub := DirAccess.open(dir + "/creatures")
	if sub != null:
		var names := Array(sub.get_files()).filter(func(n): return n.ends_with(".json"))
		names.sort()
		for n in names:
			files.append(dir + "/creatures/" + n)
	for path in files:
		var parsed: Variant = read_json(path)
		if parsed == null:
			continue
		var defs: Dictionary = parsed.get("creatures", {})
		for id in defs:
			if creatures.has(id):
				duplicate_creatures.append("%s (%s and %s)" % [id, creature_sources[id], path.get_file()])
				continue
			creatures[id] = defs[id]
			creature_sources[id] = path.get_file()


func creature(id: String) -> Dictionary:
	return creatures.get(id, {})


## The highest creature tier in the data (8 with the current rosters).
func max_creature_tier() -> int:
	var top := 0
	for id in creatures:
		top = maxi(top, int(creatures[id].get("tier", 0)))
	return top


func terrain(id: String) -> Dictionary:
	return terrains.get(id, {})


func load_map(map_id: String) -> Dictionary:
	if map_id.begins_with("custom:"):
		var result := MapRepository.new(self).load_local(map_id.trim_prefix("custom:"))
		if not result.has("document"):
			return {}
		var definition: Dictionary = result["document"].definition()
		return definition if MapPlayability.errors(definition, self).is_empty() else {}
	# Generated maps ("gen:<template>:<seed>") are rebuilt deterministically.
	if ScenarioGenerator.is_generated_id(map_id):
		return ScenarioGenerator.generate_from_id(self, map_id)
	if MapGenerator.is_generated_id(map_id):
		return MapGenerator.generate_from_id(self, map_id)
	return read_json("%s/maps/%s.json" % [DATA_DIR, map_id])


## Returns a list of human-readable problems. Empty means the data is consistent.
func validate() -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(_validate_rules())
	errors.append_array(_validate_ai_difficulty())
	errors.append_array(validate_tactics())
	errors.append_array(HeroSpecialties.validate(self))
	var roles := ["infantry", "ranged", "cavalry", "flyer", "support", "heavy"]
	for dup in duplicate_creatures:
		errors.append("creature defined twice: %s" % dup)
	for id in creatures:
		var c: Dictionary = creatures[id]
		for key in ["name", "faction", "tier", "role", "hp", "attack", "defense", "damage", "speed", "initiative", "growth", "cost", "abilities", "terrain"]:
			if not c.has(key):
				errors.append("creature %s missing %s" % [id, key])
		if not factions.has(c.get("faction", "")):
			errors.append("creature %s has unknown faction %s" % [id, c.get("faction", "")])
		if not roles.has(c.get("role", "")):
			errors.append("creature %s has unknown role %s" % [id, c.get("role", "")])
		var tier := int(c.get("tier", 0))
		if tier < 1 or tier > 8:
			errors.append("creature %s has tier %d outside 1-8" % [id, tier])
		var dmg: Array = c.get("damage", [0, 0])
		if dmg.size() != 2 or dmg[0] > dmg[1] or dmg[0] < 1:
			errors.append("creature %s has invalid damage range" % id)
		for a in c.get("abilities", []):
			var aid: String = a.get("id", "")
			if not abilities.has(aid):
				errors.append("creature %s has unknown ability %s" % [id, aid])
				continue
			for k in a:
				if k != "id" and not abilities[aid]["params"].has(k):
					errors.append("creature %s: ability %s has unknown parameter %s" % [id, aid, k])
		errors.append_array(_validate_upgrade(id, c))
		for tid in c.get("terrain", {}):
			if not terrains.has(tid):
				errors.append("creature %s has unknown terrain %s" % [id, tid])
		var key_res: Array = factions.get(c.get("faction", ""), {}).get("economy", {}).get("key_resources", [])
		for res in c.get("cost", {}):
			if not resources.has(res):
				errors.append("creature %s costs unknown resource %s" % [id, res])
			elif not key_res.is_empty() and not (res in ["gold", "wood", "ore"] or key_res.has(res)):
				errors.append("creature %s costs %s, not a key resource of its faction" % [id, res])
	for fid in factions:
		var eco: Dictionary = factions[fid].get("economy", {})
		if not eco.is_empty() and not ["early", "steady", "late"].has(eco.get("curve", "")):
			errors.append("faction %s has unknown economy curve %s" % [fid, eco.get("curve", "")])
		for res in eco.get("key_resources", []):
			if not resources.has(res):
				errors.append("faction %s has unknown key resource %s" % [fid, res])
		for tid in factions[fid].get("native_terrain", []) + factions[fid].get("hostile_terrain", []):
			if not terrains.has(tid):
				errors.append("faction %s references unknown terrain %s" % [fid, tid])
	errors.append_array(validate_heroes())
	errors.append_array(validate_combat_config())
	errors.append_array(MapGenerator.validate_templates(self))
	errors.append_array(_validate_terrain_painting())
	errors.append_array(ScenarioGenerator.validate(self))
	errors.append_array(GameSetup.validate_curated(self, RandomMapTemplate.settings(map_templates).get("curated")))
	errors.append_array(validate_encounters())
	errors.append_array(Economy.validate(self))
	var spells: Dictionary = magic.get("spells", {})
	if int(magic.get("class_level", 0)) < 2 or spells.is_empty():
		errors.append("magic needs a class level and spells")
	for kind in ["rally", "hex", "mend", "strike", "ward", "storm"]:
		var id := String(magic.get("class_by_art", {}).get(kind, ""))
		if not spells.has(id) or spells[id].get("source", "") != "class":
			errors.append("magic has no class spell for %s" % kind)
	for id in spells:
		var spell: Dictionary = spells[id]
		if not spell.has("name") or not spell.has("description") or int(spell.get("cost", 0)) <= 0 or float(spell.get("amount", 0)) <= 0 or float(spell.get("amount", 0)) > 1.0 or not spell.get("effect", "") in ["movement", "battle_damage", "home", "town_gate"] or not spell.get("source", "") in ["class", "rare"]:
			errors.append("invalid spell %s" % id)
	errors.append_array(MapSites.validate(self))
	errors.append_array(WorldEvents.validate(self))
	errors.append_array(FactionMechanics.validate(self))
	return errors


const ART_KINDS := ["strike", "storm", "mend", "rally", "hex", "ward"]


## Skills, hero classes, artifacts and campaigns.
## data/terrain_painting.json, with decoration kinds checked against the
## decoration atlas when the asset manifest is present.
func _validate_terrain_painting() -> Array[String]:
	var kinds: Array = []
	var variants := 0
	if FileAccess.file_exists("res://assets/manifest.json"):
		var deco: Dictionary = read_json("res://assets/manifest.json").get("terrain", {}).get("deco", {})
		kinds = deco.get("kinds", {}).keys()
		variants = int(deco.get("variants", 0))
	return TerrainPainter.validate_config(self, kinds, variants)


func validate_heroes() -> Array[String]:
	var errors: Array[String] = []
	for sk in skills:
		var levels: Array = skills[sk].get("levels", [])
		if not skills[sk].has("name") or levels.size() != skill_max_level:
			errors.append("skill %s needs a name and %d levels" % [sk, skill_max_level])
		for i in levels.size():
			if not levels[i].has("text") or levels[i].get("mods", {}).is_empty():
				errors.append("skill %s level %d needs text and an effect" % [sk, i + 1])
			errors.append_array(HeroModifiers.validate(levels[i].get("mods", {}), "skill %s level %d" % [sk, i + 1], self))
	var factions_with_classes := {}
	for cid in hero_classes:
		var c: Dictionary = hero_classes[cid]
		var where := "class %s" % cid
		for key in ["name", "faction", "text", "attack", "defense", "power", "knowledge", "growth", "skills", "skill_weights", "trait", "art"]:
			if not c.has(key):
				errors.append("%s missing %s" % [where, key])
		if not factions.has(c.get("faction", "")) or bool(factions.get(c.get("faction", ""), {}).get("neutral", false)):
			errors.append("%s has unknown or neutral faction %s" % [where, c.get("faction", "")])
		factions_with_classes[c.get("faction", "")] = int(factions_with_classes.get(c.get("faction", ""), 0)) + 1
		for sk in c.get("skills", {}):
			if not skills.has(sk):
				errors.append("%s starts with unknown skill %s" % [where, sk])
		var weighted := 0
		for sk in c.get("skill_weights", {}):
			if not skills.has(sk):
				errors.append("%s weights unknown skill %s" % [where, sk])
			elif float(c["skill_weights"][sk]) > 0.0:
				weighted += 1
		if weighted < 4:
			errors.append("%s should offer at least 4 skills" % where)
		var growth_total := 0
		for a in c.get("growth", {}):
			if not ATTRIBUTES.has(a) or int(c["growth"][a]) < 0:
				errors.append("%s has invalid growth %s" % [where, a])
			else:
				growth_total += int(c["growth"][a])
		if growth_total <= 0:
			errors.append("%s growth must have a positive weight" % where)
		var tr: Dictionary = c.get("trait", {})
		if not tr.has("name") or not tr.has("text"):
			errors.append("%s trait needs name and text" % where)
		if tr.get("mods", {}).is_empty() and tr.get("per_level", {}).is_empty():
			errors.append("%s trait has no effect" % where)
		errors.append_array(HeroModifiers.validate(tr.get("mods", {}), where + " trait", self))
		errors.append_array(HeroModifiers.validate(tr.get("per_level", {}), where + " trait per_level", self))
		for k in tr.get("per_level", {}):
			if HeroModifiers.KEYS.get(k, "") not in ["pct", "num"]:
				errors.append("%s per_level modifier %s must be a pct or num key" % [where, k])
		var art: Dictionary = c.get("art", {})
		if not ART_KINDS.has(art.get("kind", "")) or not art.has("name") or not art.has("text"):
			errors.append("%s art needs a name, text and a known kind" % where)
		if float(art.get("base", 0)) <= 0.0 or float(art.get("per_power", -1)) < 0.0:
			errors.append("%s art needs a positive base and non-negative per_power" % where)
	for fid in factions:
		if not bool(factions[fid].get("neutral", false)) and int(factions_with_classes.get(fid, 0)) < 2:
			errors.append("faction %s needs at least two hero classes" % fid)
	for slot in artifact_slots:
		if typeof(slot) != TYPE_STRING:
			errors.append("artifact slots must be strings")
	for aid in artifacts:
		var a: Dictionary = artifacts[aid]
		var where := "artifact %s" % aid
		if not a.has("name") or not a.has("text") or not artifact_slots.has(a.get("slot", "")):
			errors.append("%s needs a name, text and a known slot" % where)
		if not a.get("rarity", "") in ["minor", "major", "relic"] or int(a.get("value", 0)) <= 0:
			errors.append("%s needs a rarity and a positive value" % where)
		if a.get("mods", {}).is_empty():
			errors.append("%s has no effect" % where)
		errors.append_array(HeroModifiers.validate(a.get("mods", {}), where, self))
	for slot in artifact_rules["drop_slots"]:
		if not artifact_slots.has(slot):
			errors.append("artifact drop slot %s is not a slot" % slot)
	errors.append_array(_validate_artifact_sets())
	errors.append_array(Campaign.validate(self))
	return errors


## Artifact sets: known pieces of different slots, each piece in one set only,
## and bonuses with a real effect at a reachable piece count.
func _validate_artifact_sets() -> Array[String]:
	var errors: Array[String] = []
	var piece_set := {}
	for sid in artifact_sets:
		var st: Dictionary = artifact_sets[sid]
		var where := "artifact set %s" % sid
		var pieces: Array = st.get("pieces", [])
		if not st.has("name") or pieces.size() < 2:
			errors.append("%s needs a name and at least two pieces" % where)
		var slots := {}
		for a in pieces:
			if not artifacts.has(a):
				errors.append("%s has unknown piece %s" % [where, a])
				continue
			var slot := String(artifacts[a]["slot"])
			if slots.has(slot):
				errors.append("%s has two %s pieces" % [where, slot])
			slots[slot] = true
			if piece_set.has(a):
				errors.append("%s: %s already belongs to set %s" % [where, a, piece_set[a]])
			piece_set[a] = sid
		var bonuses: Array = st.get("bonuses", [])
		if bonuses.is_empty():
			errors.append("%s has no bonuses" % where)
		for b in bonuses:
			var n := int(b.get("pieces", 0))
			if n < 2 or n > pieces.size() or not b.has("text") or b.get("mods", {}).is_empty():
				errors.append("%s has a bonus without a valid piece count, text or effect" % where)
			errors.append_array(HeroModifiers.validate(b.get("mods", {}), where, self))
	return errors


## The set an artifact belongs to, or "".
func artifact_set_of(artifact_id: String) -> String:
	for sid in artifact_sets:
		if (artifact_sets[sid].get("pieces", []) as Array).has(artifact_id):
			return String(sid)
	return ""


## Every tuning value CombatSimulator reads must exist and be in a sane range.
func validate_combat_config() -> Array[String]:
	var errors: Array[String] = []
	var ranges := {
		"max_rounds": [1, 100], "initiative_jitter": [0, 10],
		"attack_bonus_per_point": [0.0, 1.0], "attack_bonus_cap": [1.0, 10.0],
		"defense_reduction_per_point": [0.0, 1.0], "defense_reduction_floor": [0.0, 1.0],
		"battle_fortune_spread": [0.0, 0.5],
		"ranged_melee_penalty": [0.0, 1.0], "engaged_ranged_penalty": [0.0, 1.0],
		"cavalry_bypass_chance": [0.0, 1.0], "cavalry_bypass_with_anchor": [0.0, 1.0], "flyer_backline_preference": [0.0, 1.0],
		"front_pinned_target_weight": [0.0, 10.0], "flank_pinned_target_weight": [0.0, 10.0],
		"ranged_pinned_target_weight": [0.0, 10.0], "counter_battery_weight": [0.0, 10.0],
		"stand_and_shoot_mult": [0.0, 2.0], "opening_volley_mult": [0.0, 2.0], "cavalry_hold_max_rounds": [0, 15],
		"frontage_hp_ratio": [0.5, 100.0], "frontage_min_creatures": [1, 1000],
		"frontage_overflow_targets": [0, 20], "frontage_overflow_mult": [0.0, 1.0],
		"morale_chance_per_point": [0.0, 0.3], "morale_cap": [0, 10],
		"brace_retaliation_mult": [0.0, 5.0], "retaliation_after_acting_mult": [0.0, 1.0], "retaliations_per_round": [0, 5],
		"prediction_simulations": [1, 10000], "hover_simulations": [1, 10000], "xp_per_enemy_hp_killed": [0.0, 10.0],
	}
	for key in ranges:
		if not combat.has(key):
			errors.append("combat_config missing %s" % key)
			continue
		var v = combat[key]
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			errors.append("combat_config %s must be a number" % key)
		elif v < ranges[key][0] or v > ranges[key][1]:
			errors.append("combat_config %s=%s outside [%s, %s]" % [key, v, ranges[key][0], ranges[key][1]])
	for key in ["opening_volley", "flank_attacks_prevent_retaliation", "retaliation_pool", "frontage_overflow", "volley_spill", "flyers_hold_for_the_line"]:
		if typeof(combat.get(key)) != TYPE_BOOL:
			errors.append("combat_config %s must be true or false" % key)
	var matchups = combat.get("role_matchups", {})
	if typeof(matchups) != TYPE_DICTIONARY:
		errors.append("combat_config role_matchups must be an object")
	else:
		for att_role in matchups:
			if not ROLES.has(att_role) or typeof(matchups[att_role]) != TYPE_DICTIONARY:
				errors.append("combat_config role_matchups has unknown role %s" % att_role)
				continue
			for def_role in matchups[att_role]:
				var b = matchups[att_role][def_role]
				if not ROLES.has(def_role):
					errors.append("combat_config role_matchups %s has unknown role %s" % [att_role, def_role])
				elif (typeof(b) != TYPE_INT and typeof(b) != TYPE_FLOAT) or b < -0.9 or b > 2.0:
					errors.append("combat_config role_matchups %s vs %s must be a number in [-0.9, 2]" % [att_role, def_role])
	for pair in combat.get("approach_round_by_speed", []):
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
			errors.append("combat_config approach_round_by_speed entries must be [min_speed, round]")
	return errors


## data/tactics.json: both tables hold their default option at level 1, every
## option has a name, a description, a min_level and known effects.
func validate_tactics() -> Array[String]:
	var errors: Array[String] = []
	if tactics.is_empty():
		return errors
	var disc = tactics.get("tactics_skill_discount", 0)
	if typeof(disc) != TYPE_INT and typeof(disc) != TYPE_FLOAT or disc < 0 or disc > 5:
		errors.append("tactics: tactics_skill_discount must be a number in [0, 5]")
	var drill = tactics.get("formation_drill", {})
	if typeof(drill) != TYPE_DICTIONARY:
		errors.append("tactics: formation_drill must be an object")
	else:
		for key in ["class_pct", "per_skill_level_pct", "max_pct"]:
			var v = drill.get(key, 0.0)
			if (typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT) or v < 0.0 or v > 2.0:
				errors.append("tactics: formation_drill.%s must be a number in [0, 2]" % key)
	for kind in BattleOrders.KINDS:
		var tbl: Dictionary = BattleOrders.table(self, kind)
		var def: String = BattleOrders.DEFAULT[kind]
		if not tbl.has(def) or int(tbl[def].get("min_level", 0)) != 1 or not (tbl[def].get("effects", {}) as Dictionary).is_empty():
			errors.append("tactics: %s needs the default %s at min_level 1 without effects" % [kind, def])
		for id in tbl:
			var opt: Dictionary = tbl[id]
			for key in ["name", "desc", "min_level", "effects"]:
				if not opt.has(key):
					errors.append("tactics %s %s missing %s" % [kind, id, key])
			if int(opt.get("min_level", 0)) < 1:
				errors.append("tactics %s %s: min_level must be at least 1" % [kind, id])
			if opt.has("skill") and not skills.has(String(opt["skill"])):
				errors.append("tactics %s %s: unknown skill %s" % [kind, id, opt["skill"]])
			if opt.has("classes"):
				if typeof(opt["classes"]) != TYPE_ARRAY:
					errors.append("tactics %s %s: classes must be a list" % [kind, id])
				else:
					for c in opt["classes"]:
						if not hero_classes.has(String(c)):
							errors.append("tactics %s %s: unknown hero class %s" % [kind, id, c])
			var fx = opt.get("effects", {})
			if typeof(fx) != TYPE_DICTIONARY:
				errors.append("tactics %s %s: effects must be an object" % [kind, id])
				continue
			for k in fx:
				if not BattleOrders.EFFECT_RANGES.has(k):
					errors.append("tactics %s %s has unknown effect %s" % [kind, id, k])
					continue
				var r: Array = BattleOrders.EFFECT_RANGES[k]
				var v = fx[k]
				if (typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT) or v < r[0] or v > r[1]:
					errors.append("tactics %s %s: %s must be a number in [%s, %s]" % [kind, id, k, r[0], r[1]])
	return errors


const ENCOUNTER_CONDITIONS := ["class", "not_class", "faction", "skill", "attr", "army_tag", "army_role",
	"min_creatures", "terrain", "mark", "no_mark", "min_level", "min_week", "any"]
const ENCOUNTER_EFFECTS := ["resources", "xp", "recruit", "casualties", "movement", "skill_point", "mark", "reveal", "ambush", "artifact",
	"boon", "mana", "veteran_xp", "ascend"]
const ROLES := ["infantry", "ranged", "cavalry", "flyer", "support", "heavy"]
const ATTRIBUTES := ["attack", "defense", "power", "knowledge"]


func validate_encounters() -> Array[String]:
	var errors: Array[String] = []
	var sprite_ids: Dictionary = {}
	if FileAccess.file_exists("res://assets/manifest.json"):
		sprite_ids = read_json("res://assets/manifest.json").get("sprites", {})
	var marks: Dictionary = encounter_rules.get("marks", {})
	for eid in encounters:
		var enc: Dictionary = encounters[eid]
		var where := "encounter %s" % eid
		if not enc.has("name") or not enc.has("text"):
			errors.append("%s missing name or text" % where)
		if enc.has("sprite") and not sprite_ids.is_empty() and not sprite_ids.has(String(enc["sprite"])):
			errors.append("%s uses unknown sprite %s" % [where, enc["sprite"]])
		var choices: Array = enc.get("choices", [])
		if choices.size() < 2:
			errors.append("%s needs at least two choices" % where)
		for i in choices.size():
			var c: Dictionary = choices[i]
			var cw := "%s choice %d" % [where, i]
			if not c.has("text"):
				errors.append("%s missing text" % cw)
			if bool(c.get("leave", false)):
				continue
			if c.has("requires"):
				_validate_condition(c["requires"], cw, marks, errors)
			for k in c.get("cost", {}):
				if k != "movement" and not resources.has(k):
					errors.append("%s costs unknown resource %s" % [cw, k])
				elif int(c["cost"][k]) <= 0:
					errors.append("%s has non-positive cost %s" % [cw, k])
			if not c.has("success"):
				errors.append("%s has no success outcome" % cw)
			if c.has("check"):
				var chk: Dictionary = c["check"]
				if not c.has("failure"):
					errors.append("%s has a check but no failure outcome" % cw)
				var p := float(chk.get("chance", -1.0))
				if p < 0.0 or p > 1.0:
					errors.append("%s check chance must be in [0, 1]" % cw)
				for a in chk.get("per_attr", {}):
					if not ATTRIBUTES.has(a):
						errors.append("%s check uses unknown attribute %s" % [cw, a])
				for sk in chk.get("per_skill", {}):
					if not skills.has(sk):
						errors.append("%s check uses unknown skill %s" % [cw, sk])
				for m in chk.get("mods", []):
					if not m.has("when") or not m.has("add"):
						errors.append("%s check modifier needs when and add" % cw)
					else:
						_validate_condition(m["when"], cw, marks, errors)
			elif c.has("failure"):
				errors.append("%s has a failure outcome but no check" % cw)
			for key in ["success", "failure"]:
				for e in c.get(key, {}).get("effects", []):
					_validate_effect(e, "%s %s" % [cw, key], marks, errors)
	return errors


func _validate_condition(cond: Dictionary, where: String, marks: Dictionary, errors: Array[String]) -> void:
	for k in cond:
		if not ENCOUNTER_CONDITIONS.has(k):
			errors.append("%s has unknown condition %s" % [where, k])
	for cid in cond.get("class", []) + cond.get("not_class", []):
		if not hero_classes.has(cid):
			errors.append("%s references unknown class %s" % [where, cid])
	for fid in cond.get("faction", []):
		if not factions.has(fid):
			errors.append("%s references unknown faction %s" % [where, fid])
	for sk in cond.get("skill", {}):
		if not skills.has(sk):
			errors.append("%s references unknown skill %s" % [where, sk])
	for a in cond.get("attr", {}):
		if not ATTRIBUTES.has(a):
			errors.append("%s references unknown attribute %s" % [where, a])
	for tid in cond.get("terrain", []):
		if not terrains.has(tid):
			errors.append("%s references unknown terrain %s" % [where, tid])
	if cond.has("army_role") and not ROLES.has(cond["army_role"]):
		errors.append("%s references unknown role %s" % [where, cond["army_role"]])
	for mk in ["mark", "no_mark"]:
		if cond.has(mk) and not marks.has(cond[mk]):
			errors.append("%s references undeclared mark %s" % [where, cond[mk]])
	for sub in cond.get("any", []):
		_validate_condition(sub, where, marks, errors)


func _validate_effect(e: Dictionary, where: String, marks: Dictionary, errors: Array[String]) -> void:
	var t := String(e.get("type", ""))
	if not ENCOUNTER_EFFECTS.has(t):
		errors.append("%s has unknown effect %s" % [where, t])
		return
	match t:
		"resources":
			for res in e.get("resources", {}):
				if not resources.has(res):
					errors.append("%s grants unknown resource %s" % [where, res])
		"recruit":
			if not creatures.has(e.get("creature", "")) or int(e.get("count", 0)) <= 0:
				errors.append("%s recruits an unknown creature or no creatures" % where)
		"ambush":
			if e.get("stacks", []).is_empty() or e["stacks"].size() > Army.MAX_SLOTS:
				errors.append("%s ambush needs 1-%d stacks" % [where, Army.MAX_SLOTS])
			for s in e.get("stacks", []):
				if not creatures.has(s.get("creature", "")) or int(s.get("count", 0)) <= 0:
					errors.append("%s ambush has an invalid stack" % where)
		"casualties":
			var f := float(e.get("fraction", 0.0))
			if f <= 0.0 or f > 0.5:
				errors.append("%s casualties fraction must be in (0, 0.5]" % where)
			if e.has("role") and not ROLES.has(e["role"]):
				errors.append("%s casualties role unknown" % where)
		"artifact":
			if not artifacts.has(e.get("artifact", "")):
				errors.append("%s grants unknown artifact %s" % [where, e.get("artifact", "")])
		"mark":
			if not marks.has(e.get("mark", "")):
				errors.append("%s grants undeclared mark %s" % [where, e.get("mark", "")])
		"xp", "movement", "skill_point":
			if not e.has("amount") and t != "skill_point":
				errors.append("%s needs amount" % where)
		"reveal":
			if int(e.get("radius", 0)) <= 0:
				errors.append("%s needs a positive radius" % where)
		"boon":
			if (e.get("mods", {}) as Dictionary).is_empty():
				errors.append("%s boon grants no mods" % where)
			errors.append_array(HeroModifiers.validate(e.get("mods", {}), where, self))
			if int(e.get("days", 0)) < 1:
				errors.append("%s boon needs days >= 1" % where)
		"mana", "veteran_xp":
			if int(e.get("amount", 0)) <= 0:
				errors.append("%s needs a positive amount" % where)


func _validate_rules() -> Array[String]:
	var errors: Array[String] = []
	for key in ["mana_base", "mana_per_knowledge", "mana_daily_regen"]:
		var v: Variant = rules.get(key)
		if not (v is int or v is float) or float(v) < 0 or float(v) != floor(float(v)):
			errors.append("game_rules %s must be a nonnegative integer" % key)
	for key in ["town_loss_grace_days", "save_slots", "hero_defeat_xp_bonus"]:
		if not rules.has(key):
			errors.append("game_rules missing %s" % key)
	if errors.is_empty():
		if int(rules["town_loss_grace_days"]) < 1:
			errors.append("game_rules town_loss_grace_days must be >= 1")
		if int(rules["save_slots"]) < 1 or int(rules["save_slots"]) > 20:
			errors.append("game_rules save_slots must be 1..20")
		if float(rules["hero_defeat_xp_bonus"]) < 0.0:
			errors.append("game_rules hero_defeat_xp_bonus must be >= 0")
		var sg: Variant = rules.get("starting_garrison_weeks", {})
		if typeof(sg) != TYPE_DICTIONARY:
			errors.append("game_rules starting_garrison_weeks must map tiers to weeks")
		else:
			for tier in sg:
				if not String(tier).is_valid_int() or int(tier) < 1 or int(tier) > 8 or float(sg[tier]) < 0.0:
					errors.append("game_rules starting_garrison_weeks: tier %s must be 1..8 with weeks >= 0" % tier)
		if int(rules.get("threat_warning_days", 0)) < 0:
			errors.append("game_rules threat_warning_days must be >= 0")
		for key in ["scout_movement", "scout_range_bonus"]:
			var v: Variant = rules.get(key)
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				errors.append("game_rules missing %s" % key)
			elif int(v) < 0 or int(v) > 5000:
				errors.append("game_rules %s must be 0..5000" % key)
		var limit := int(economy.get("max_heroes_per_player", 8))
		if int(rules.get("starting_heroes", 1)) < 1 or int(rules.get("starting_heroes", 1)) > limit:
			errors.append("game_rules starting_heroes must be 1..max_heroes_per_player")
		if int(rules.get("starting_army_max_tier", 2)) < 1 or int(rules.get("starting_army_max_tier", 2)) > 8:
			errors.append("game_rules starting_army_max_tier must be 1..8")
		if typeof(rules.get("cold_attrition", false)) != TYPE_BOOL:
			errors.append("game_rules cold_attrition must be true or false")
		var cold_pct: Variant = rules.get("cold_attrition_pct", 0.0)
		if not (cold_pct is int or cold_pct is float) or float(cold_pct) < 0.0 or float(cold_pct) > 1.0:
			errors.append("game_rules cold_attrition_pct must be 0..1")
		var cold_terrains: Variant = rules.get("cold_attrition_terrains", [])
		if typeof(cold_terrains) != TYPE_ARRAY:
			errors.append("game_rules cold_attrition_terrains must be a list of terrain ids")
		else:
			for tid in cold_terrains:
				if not terrains.has(String(tid)):
					errors.append("game_rules cold_attrition_terrains: unknown terrain %s" % tid)
		for fid in factions:
			if factions[fid].has("starting_heroes") and (int(factions[fid]["starting_heroes"]) < 1 or int(factions[fid]["starting_heroes"]) > limit):
				errors.append("faction %s starting_heroes must be 1..max_heroes_per_player" % fid)
	return errors


## How many heroes a player of this faction starts a standard game with:
## the faction's starting_heroes (a faction trait), else game_rules' starting_heroes.
func starting_heroes(faction: String) -> int:
	var f: Dictionary = factions.get(faction, {})
	return int(f.get("starting_heroes", rules.get("starting_heroes", 1)))


## Computer-player difficulty ids in menu order.
func difficulty_levels() -> Array:
	return ai_difficulty.get("order", [])


## The level a slot plays at when it names none.
func default_difficulty() -> String:
	return String(ai_difficulty.get("default", "normal"))


## A difficulty level's definition ({name, description, income_percent, ai});
## an unknown id falls back to the default level.
func difficulty(id: String) -> Dictionary:
	var levels: Dictionary = ai_difficulty.get("levels", {})
	return levels.get(id, levels.get(default_difficulty(), {}))


func _validate_ai_difficulty() -> Array[String]:
	var errors: Array[String] = []
	var levels: Variant = ai_difficulty.get("levels", null)
	var order: Variant = ai_difficulty.get("order", null)
	if typeof(levels) != TYPE_DICTIONARY or typeof(order) != TYPE_ARRAY:
		errors.append("ai_difficulty needs levels and order")
		return errors
	if not (levels as Dictionary).has(default_difficulty()):
		errors.append("ai_difficulty default %s is not a level" % default_difficulty())
	for id in order:
		if not (levels as Dictionary).has(id):
			errors.append("ai_difficulty order lists unknown level %s" % id)
	for id in levels:
		var lv: Dictionary = levels[id]
		if not (order as Array).has(id):
			errors.append("ai_difficulty level %s is missing from order" % id)
		if String(lv.get("name", "")) == "":
			errors.append("ai_difficulty level %s has no name" % id)
		var pct := int(lv.get("income_percent", 100))
		if pct < 10 or pct > 400:
			errors.append("ai_difficulty level %s income_percent must be 10..400" % id)
		for e in Campaign.validate_ai_settings(lv.get("ai", {})):
			errors.append("ai_difficulty level %s ai %s" % [id, e])
	return errors


## Upgrade pairs: base.upgrade <-> upgraded.upgrade_of, same faction/tier/growth/role.
func _validate_upgrade(id: String, c: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if c.has("upgrade"):
		var up: Dictionary = creatures.get(c["upgrade"], {})
		if up.is_empty():
			errors.append("creature %s upgrades to unknown %s" % [id, c["upgrade"]])
		elif up.get("upgrade_of", "") != id:
			errors.append("creature %s upgrades to %s, which is not upgrade_of it" % [id, c["upgrade"]])
	if c.has("upgrade_of"):
		var base: Dictionary = creatures.get(c["upgrade_of"], {})
		if base.is_empty():
			errors.append("creature %s is upgrade_of unknown %s" % [id, c["upgrade_of"]])
		elif base.get("upgrade", "") != id:
			errors.append("creature %s is upgrade_of %s, which does not upgrade to it" % [id, c["upgrade_of"]])
		else:
			for k in ["faction", "tier", "growth", "role"]:
				if base.get(k) != c.get(k):
					errors.append("upgrade %s differs from its base in %s" % [id, k])
		if c.has("upgrade"):
			errors.append("creature %s is both an upgrade and upgradable" % id)
	return errors
