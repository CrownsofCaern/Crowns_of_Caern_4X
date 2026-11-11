class_name Hero
extends RefCounted
## A hero: identity, persistent progression and the army they lead.
## Everything in here is campaign-persistent except position and movement.

var id: String = ""
var name: String = ""
var class_id: String = ""
var faction: String = ""
var owner: int = 0
var pos: Vector2i = Vector2i.ZERO
var level: int = 1
var xp: int = 0
var attack: int = 0
var defense: int = 0
var power: int = 0
var knowledge: int = 0
var skills: Dictionary = {}
var skill_points: int = 0
var movement_left: int = 0
## Map destination retained between turns; (-1, -1) means no planned route.
var planned_destination := Vector2i(-1, -1)
var home_town: String = ""
var mana: int = 0
var spells: Array[String] = []
var battle_spell_damage: float = 0.0
var army: Army = Army.new()
var alive: bool = true
var marks: Array[String] = []   # persistent renown from encounters (campaign state), kept sorted
var equipment: Dictionary = {}  # slot -> artifact id (worn; only worn artifacts give mods)
var pack: Array[String] = []    # carried, not worn
var level_cap: int = 0          # set by a campaign chapter; 0 = none. XP keeps accruing above it.
## Temporary blessings and curses: [{source, name, until_day, mods}] from map
## sites, the week's omen and fortunes. Their mods count in modifiers() until
## the end of until_day (GameSession drops them when a later day starts).
var boons: Array = []
## Standing battle orders {stance, focus, formation, art, retreat}
## (data/tactics.json, BattleOrders).
## Kept as chosen; locked options count as the defaults in battle.
var orders: Dictionary = BattleOrders.DEFAULT.duplicate()


static func create(def: Dictionary, data: GameData) -> Hero:
	var h := Hero.new()
	var cls: Dictionary = data.hero_classes[def["class"]]
	h.id = def["id"]
	h.name = def["name"]
	h.class_id = def["class"]
	h.faction = cls["faction"]
	h.owner = int(def.get("owner", 0))
	h.pos = Vector2i(int(def["pos"][0]), int(def["pos"][1]))
	h.attack = int(cls["attack"])
	h.defense = int(cls["defense"])
	h.power = int(cls["power"])
	h.knowledge = int(cls["knowledge"])
	for sk in cls["skills"]:
		h.skills[sk] = int(cls["skills"][sk])
	h.army = Army.from_pairs(def.get("army", []))
	h.army.initialize_veterans(data)
	h.movement_left = h.max_movement(data)
	h.mana = h.max_mana(data)
	return h


## Maximum mana grows with the hero's knowledge.
func max_mana(data: GameData) -> int:
	return int(data.rules["mana_base"]) + maxi(0, knowledge) * int(data.rules["mana_per_knowledge"])


func restore_mana(amount: int, data: GameData) -> void:
	mana = mini(max_mana(data), mana + maxi(0, amount))


func known_spells(data: GameData) -> Array[String]:
	var out: Array[String] = spells.duplicate()
	if level >= int(data.magic["class_level"]):
		var kind := String(data.hero_classes[class_id].get("art", {}).get("kind", ""))
		var spell := String(data.magic["class_by_art"].get(kind, ""))
		if spell != "" and not out.has(spell):
			out.append(spell)
	out.sort()
	return out


func skill_level(skill_id: String) -> int:
	return int(skills.get(skill_id, 0))


## Everything that modifies game systems for this hero, summed from the class
## trait (plus its per-level part), the personal specialty, learned skills and
## worn artifacts. See HeroModifiers for the keys and their consumers.
func modifiers(data: GameData) -> Dictionary:
	var out := {}
	var tr: Dictionary = data.hero_classes[class_id].get("trait", {})
	HeroModifiers.combine(out, tr.get("mods", {}))
	if level > 1:
		HeroModifiers.combine(out, tr.get("per_level", {}), float(level - 1))
	var sid := HeroSpecialties.id_for(name, faction, data)
	if sid != "":
		HeroModifiers.combine(out, HeroSpecialties.mods_at(data.hero_specialties[sid], level))
	var ids := skills.keys()
	ids.sort()
	for sk in ids:
		HeroModifiers.combine(out, HeroModifiers.skill_mods(sk, skill_level(sk), data))
	for slot in data.artifact_slots:
		var art_id: String = equipment.get(slot, "")
		if art_id != "" and data.artifacts.has(art_id):
			HeroModifiers.combine(out, data.artifacts[art_id].get("mods", {}))
	for bonus in active_set_bonuses(data):
		HeroModifiers.combine(out, bonus.get("mods", {}))
	for b in boons:
		HeroModifiers.combine(out, b.get("mods", {}))
	HeroModifiers.combine(out, FactionMechanics.hero_mods(faction, data))
	return HeroModifiers.clamp_all(out)


func has_boon(source: String) -> bool:
	for b in boons:
		if String(b["source"]) == source:
			return true
	return false


## Adds (or renews) a boon; a boon from the same source is replaced.
func add_boon(source: String, boon_name: String, until_day: int, mods: Dictionary) -> void:
	remove_boon(source)
	boons.append({"source": source, "name": boon_name, "until_day": until_day, "mods": mods.duplicate(true)})


func remove_boon(source: String) -> void:
	boons = boons.filter(func(b): return String(b["source"]) != source)


## Drops the boons that ran out before this day. Returns how many.
func expire_boons(day: int) -> int:
	var before := boons.size()
	boons = boons.filter(func(b): return int(b["until_day"]) >= day)
	return before - boons.size()


## Set bonuses earned by the worn artifacts: every bonus of every set whose
## piece count is reached, in data order. Each entry is the bonus dictionary
## plus "set" (id) and "name" (the set's name).
func active_set_bonuses(data: GameData) -> Array:
	var out := []
	for sid in data.artifact_sets:
		var st: Dictionary = data.artifact_sets[sid]
		var worn := worn_set_pieces(String(sid), data)
		for b in st.get("bonuses", []):
			if worn >= int(b["pieces"]):
				var e: Dictionary = (b as Dictionary).duplicate()
				e["set"] = String(sid)
				e["name"] = String(st["name"])
				out.append(e)
	return out


## How many pieces of a set this hero wears.
func worn_set_pieces(set_id: String, data: GameData) -> int:
	var n := 0
	for a in data.artifact_sets.get(set_id, {}).get("pieces", []):
		if equipment.values().has(a):
			n += 1
	return n


## The hero's personal specialty at its current level: {id, name, text, mods,
## formations, steps}, or {} (see HeroSpecialties). Follows from name and
## faction, so it is never saved.
func specialty(data: GameData = null) -> Dictionary:
	if data == null:
		data = GameData.get_default()
	return HeroSpecialties.describe(name, faction, level, data)


## Primary attribute including worn artifacts and the class trait (never below 0).
func total_attr(attr: String, data: GameData) -> int:
	return maxi(0, int(get(attr)) + HeroModifiers.whole(modifiers(data), attr))


func max_movement(data: GameData) -> int:
	var base := int(data.progression["base_movement"])
	return int(round(base * (1.0 + HeroModifiers.num(modifiers(data), "movement_pct"))))


func vision_radius(data: GameData) -> int:
	return int(data.progression["base_vision"]) + HeroModifiers.whole(modifiers(data), "vision")


## Terrain cost reductions for Pathfinder.step_costs (Wayfinding, class
## terrain affinities, artifacts).
func move_cost_mods(data: GameData) -> Dictionary:
	var mods := modifiers(data)
	var rough := HeroModifiers.num(mods, "rough_ground_pct")
	var terr: Dictionary = mods.get("terrain_move_pct", {})
	if rough == 0.0 and terr.is_empty():
		return {}
	return {"rough": rough, "terrain": terr.duplicate()}


## Experience after the hero's bonus (Lore, Clear Sight, artifacts).
func xp_with_bonus(amount: int, data: GameData) -> int:
	return int(round(maxi(0, amount) * (1.0 + HeroModifiers.num(modifiers(data), "xp_pct"))))


## Adds experience and applies any level-ups. Returns the number of levels gained.
## Each level grants +1 to a primary attribute (class growth, deterministic) and
## one skill point to spend via learn_skill(). A campaign level_cap holds levels
## back (the XP is kept and pays out when the cap rises: call add_xp(0, data)).
func add_xp(amount: int, data: GameData) -> int:
	army.gain_veteran_xp(int(round(maxi(0, amount) * (1.0 + HeroModifiers.num(modifiers(data), "veteran_xp_pct")))), data)
	xp += maxi(0, amount)
	var thresholds: Array = data.progression["xp_thresholds"]
	var gained := 0
	while level < thresholds.size() and xp >= int(thresholds[level]) and (level_cap <= 0 or level < level_cap):
		level += 1
		gained += 1
		skill_points += 1
		_grant_primary_for_level(data)
	return gained


## XP needed for the next level, or -1 at the top of the table.
func next_level_xp(data: GameData) -> int:
	var thresholds: Array = data.progression["xp_thresholds"]
	return int(thresholds[level]) if level < thresholds.size() else -1


func _grant_primary_for_level(data: GameData) -> void:
	# Deterministic: cycle through attributes in proportion to the class's
	# growth weights so knights trend defensive and warlocks trend to power.
	var cls: Dictionary = data.hero_classes[class_id]
	var growth: Dictionary = cls.get("growth", cls)
	var order := []
	for attr in ["attack", "defense", "power", "knowledge"]:
		for i in int(growth.get(attr, 0)):
			order.append(attr)
	if order.is_empty():
		order = ["attack", "defense", "power", "knowledge"]
	match order[(level - 2) % order.size()]:
		"attack": attack += 1
		"defense": defense += 1
		"power": power += 1
		"knowledge": knowledge += 1


## Skill choices offered on level-up: up to two skills the hero can still improve,
## ordered by class preference.
func skill_offers(data: GameData) -> Array:
	var weights: Dictionary = data.hero_classes[class_id]["skill_weights"]
	var ids := weights.keys()
	ids = ids.filter(func(s): return float(weights[s]) > 0.0 and skill_level(s) < data.skill_max_level)
	ids.sort_custom(func(a, b): return weights[a] > weights[b] or (weights[a] == weights[b] and a < b))
	return ids.slice(0, 2)


## Level-up choices: up to `count` distinct skills the hero can still improve,
## drawn by class skill_weights with a seeded generator. The same seed always
## yields the same offer, so reopening the dialog never rerolls it.
func skill_offers_seeded(data: GameData, seed_value: int, count: int = 2) -> Array:
	var weights: Dictionary = data.hero_classes[class_id]["skill_weights"]
	var pool := weights.keys().filter(func(s): return float(weights[s]) > 0.0 and skill_level(s) < data.skill_max_level)
	pool.sort()
	var rng := GameRng.new(seed_value)
	var out := []
	while out.size() < count and not pool.is_empty():
		var w := pool.map(func(s): return float(weights[s]))
		var i := rng.weighted_index(w)
		out.append(pool[i])
		pool.remove_at(i)
	return out


func has_mark(mark: String) -> bool:
	return marks.has(mark)


## Returns true if the mark was new.
func add_mark(mark: String) -> bool:
	if marks.has(mark):
		return false
	marks.append(mark)
	marks.sort()
	return true


func learn_skill(skill_id: String, data: GameData) -> bool:
	if skill_points <= 0 or not data.skills.has(skill_id):
		return false
	if skill_level(skill_id) >= data.skill_max_level:
		return false
	skills[skill_id] = skill_level(skill_id) + 1
	skill_points -= 1
	return true


# -------------------------------------------------------------- equipment --

## Gives an artifact: worn if its slot is free, otherwise packed. False if the pack is full.
func give_artifact(artifact_id: String, data: GameData) -> bool:
	if not data.artifacts.has(artifact_id):
		return false
	var slot: String = data.artifacts[artifact_id]["slot"]
	if String(equipment.get(slot, "")) == "":
		equipment[slot] = artifact_id
		return true
	if pack.size() >= int(data.artifact_rules["pack_size"]):
		return false
	pack.append(artifact_id)
	return true


## Wears an artifact from the pack; whatever was in its slot goes to the pack.
func equip(artifact_id: String, data: GameData) -> bool:
	var i := pack.find(artifact_id)
	if i < 0 or not data.artifacts.has(artifact_id):
		return false
	var slot: String = data.artifacts[artifact_id]["slot"]
	pack.remove_at(i)
	var previous := String(equipment.get(slot, ""))
	if previous != "":
		pack.append(previous)
	equipment[slot] = artifact_id
	return true


## Moves the artifact worn in `slot` to the pack.
func unequip(slot: String, data: GameData) -> bool:
	var art := String(equipment.get(slot, ""))
	if art == "" or pack.size() >= int(data.artifact_rules["pack_size"]):
		return false
	equipment.erase(slot)
	pack.append(art)
	return true


## Every artifact the hero owns (worn first, in slot order, then the pack).
func all_artifacts(data: GameData) -> Array[String]:
	var out: Array[String] = []
	for slot in data.artifact_slots:
		if String(equipment.get(slot, "")) != "":
			out.append(String(equipment[slot]))
	out.append_array(pack)
	return out


## Snapshot used by the combat engine (decoupled from the Hero class): totals of
## the primaries, the summed modifiers and the class battle art.
func combat_profile(data: GameData = null) -> Dictionary:
	if data == null:
		data = GameData.get_default()
	var mods := modifiers(data)
	if battle_spell_damage > 0.0:
		HeroModifiers.combine(mods, {"melee_damage_pct": battle_spell_damage, "ranged_damage_pct": battle_spell_damage})
	var p := {"name": name, "faction": faction, "skills": skills.duplicate(), "mods": mods,
		"art": data.hero_classes[class_id].get("art", {})}
	for a in ["attack", "defense", "power", "knowledge"]:
		p[a] = maxi(0, int(get(a)) + HeroModifiers.whole(mods, a))
	p["orders"] = battle_orders(data)
	var spec := specialty(data)
	if not spec.is_empty():
		p["specialty"] = spec["name"]
	return p


## The orders this hero gives in battle: its standing orders where its level
## (and Tactics skill) allow them, otherwise the defaults.
func battle_orders(data: GameData = null) -> Dictionary:
	if data == null:
		data = GameData.get_default()
	return BattleOrders.sanitized(data, orders, level, skill_level("tactics"), commander(data))


## What the order gates need to know: level, class, skills and the specialty
## (HeroSpecialties), which may unlock and drill formations.
func commander(data: GameData = null) -> Dictionary:
	return BattleOrders.commander(level, class_id, skills, specialty(data))


## True if this hero may give the option (a BattleOrders kind).
func can_order(kind: String, id: String, data: GameData = null) -> bool:
	if data == null:
		data = GameData.get_default()
	return BattleOrders.is_open(data, kind, id, level, skill_level("tactics"), commander(data))


# --------------------------------------------------------------- campaign --

## The part of a hero that carries over between campaign maps.
func campaign_dict() -> Dictionary:
	return {
		"id": id, "name": name, "class": class_id, "faction": faction, "level": level, "xp": xp,
		"attack": attack, "defense": defense, "power": power, "knowledge": knowledge,
		"skills": skills.duplicate(), "skill_points": skill_points, "marks": marks.duplicate(),
		"equipment": equipment.duplicate(), "pack": pack.duplicate(), "orders": orders.duplicate(), "mana": mana, "spells": spells.duplicate(),
	}


## Overwrites progression with a campaign record (position, army, owner stay).
func apply_campaign(d: Dictionary) -> void:
	level = int(d["level"])
	xp = int(d["xp"])
	attack = int(d["attack"])
	defense = int(d["defense"])
	power = int(d["power"])
	knowledge = int(d["knowledge"])
	skills = {}
	for k in d["skills"]:
		skills[k] = int(d["skills"][k])
	skill_points = int(d.get("skill_points", 0))
	if d.has("mana"):
		mana = maxi(0, int(d["mana"]))
	spells.clear()
	for spell in d.get("spells", []):
		spells.append(String(spell))
	marks.clear()
	for m in d.get("marks", []):
		marks.append(String(m))
	marks.sort()
	_read_equipment(d)
	_read_orders(d)


## Standing orders from a save or campaign record (absent before save version
## 13; formation, art and retreat absent before 22: the defaults).
func _read_orders(d: Dictionary) -> void:
	orders = BattleOrders.DEFAULT.duplicate()
	var o: Variant = d.get("orders", {})
	if typeof(o) == TYPE_DICTIONARY:
		for kind in BattleOrders.KINDS:
			if o.has(kind):
				orders[kind] = String(o[kind])


func _read_equipment(d: Dictionary) -> void:
	equipment = {}
	var eq: Dictionary = d.get("equipment", {})
	for slot in eq:
		equipment[String(slot)] = String(eq[slot])
	pack.clear()
	for a in d.get("pack", []):
		pack.append(String(a))


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "class": class_id, "faction": faction, "owner": owner,
		"pos": [pos.x, pos.y], "level": level, "xp": xp,
		"attack": attack, "defense": defense, "power": power, "knowledge": knowledge,
		"skills": skills.duplicate(), "skill_points": skill_points,
		"movement_left": movement_left, "planned_destination": [planned_destination.x, planned_destination.y], "home_town": home_town, "mana": mana, "spells": spells.duplicate(), "battle_spell_damage": battle_spell_damage, "army": army.to_dict(), "alive": alive,
		"marks": marks.duplicate(), "equipment": equipment.duplicate(), "pack": pack.duplicate(),
		"level_cap": level_cap, "boons": boons.duplicate(true), "orders": orders.duplicate(),
	}


static func from_dict(d: Dictionary) -> Hero:
	var h := Hero.new()
	h.id = d["id"]
	h.name = d["name"]
	h.class_id = d["class"]
	h.faction = d["faction"]
	h.owner = int(d["owner"])
	h.pos = Vector2i(int(d["pos"][0]), int(d["pos"][1]))
	h.level = int(d["level"])
	h.xp = int(d["xp"])
	h.attack = int(d["attack"])
	h.defense = int(d["defense"])
	h.power = int(d["power"])
	h.knowledge = int(d["knowledge"])
	h.skills = {}
	for k in d["skills"]:
		h.skills[k] = int(d["skills"][k])
	h.skill_points = int(d.get("skill_points", 0))
	h.movement_left = int(d["movement_left"])
	var destination: Array = d.get("planned_destination", [-1, -1])
	if destination.size() == 2:
		h.planned_destination = Vector2i(int(destination[0]), int(destination[1]))
	h.home_town = String(d.get("home_town", ""))
	h.mana = maxi(0, int(d.get("mana", 0)))
	for spell in d.get("spells", []):
		h.spells.append(String(spell))
	h.battle_spell_damage = maxf(0.0, float(d.get("battle_spell_damage", 0.0)))
	h.army = Army.from_dict(d["army"])
	h.alive = bool(d.get("alive", true))
	for m in d.get("marks", []):  # absent in version 1 saves
		h.marks.append(String(m))
	h.marks.sort()
	h._read_equipment(d)  # absent before save version 4
	h.level_cap = int(d.get("level_cap", 0))
	h._read_orders(d)  # absent before save version 13
	for b in d.get("boons", []):  # absent before save version 10
		h.boons.append({"source": String(b["source"]), "name": String(b.get("name", "")),
			"until_day": int(b["until_day"]), "mods": (b.get("mods", {}) as Dictionary).duplicate(true)})
	return h
