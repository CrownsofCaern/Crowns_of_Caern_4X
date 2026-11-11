class_name HeroSpecialties
extends RefCounted
## Personal hero specialties (data/hero_specialties.json).
##
## Every hero has exactly one. Named heroes (tavern heroes, campaign and map
## heroes) are listed by their exact name in a specialty's "heroes"; any other
## hero gets one of its faction's specialties, picked by a stable checksum of
## its name, so the choice never depends on hashing or save data. Because the
## specialty follows from name and class alone, nothing about it is saved.
##
## A specialty's effect is a HeroModifiers "mods" dictionary plus "growth":
## {every, mods, max}, which adds its mods once per `every` levels after
## level 1, at most `max` times. "formations" ({id: {unlock, bonus_pct}}) is
## read by BattleOrders for pre-battle formations.


## The specialty id for a hero name of a faction, or "" if the faction has none.
static func id_for(hero_name: String, faction: String, data: GameData) -> String:
	if data.specialty_by_hero.has(hero_name):
		return String(data.specialty_by_hero[hero_name])
	var pool := faction_pool(faction, data)
	if pool.is_empty():
		return ""
	return pool[checksum(hero_name) % pool.size()]


## The faction's specialty ids, sorted.
static func faction_pool(faction: String, data: GameData) -> Array[String]:
	var out: Array[String] = []
	for sid in data.hero_specialties:
		if String(data.hero_specialties[sid].get("faction", "")) == faction:
			out.append(String(sid))
	out.sort()
	return out


## A stable, platform-independent checksum of a string.
static func checksum(text: String) -> int:
	var h := 7
	for i in text.length():
		h = (h * 31 + text.unicode_at(i)) % 1000003
	return h


## How many growth steps a specialty has reached at a hero level.
static func growth_steps(spec: Dictionary, level: int) -> int:
	var g: Dictionary = spec.get("growth", {})
	if g.is_empty() or level <= 1:
		return 0
	var steps := (level - 1) / maxi(1, int(g.get("every", 1)))
	if g.has("max"):
		steps = mini(steps, int(g["max"]))
	return steps


## The summed mods of a specialty at a hero level.
static func mods_at(spec: Dictionary, level: int) -> Dictionary:
	var out := {}
	HeroModifiers.combine(out, spec.get("mods", {}))
	var steps := growth_steps(spec, level)
	if steps > 0:
		HeroModifiers.combine(out, spec["growth"].get("mods", {}), float(steps))
	return out


## The full specialty of a hero at a level: {id, name, text, mods, formations,
## steps}, or {} if there is none.
static func describe(hero_name: String, faction: String, level: int, data: GameData) -> Dictionary:
	var sid := id_for(hero_name, faction, data)
	if sid == "":
		return {}
	var spec: Dictionary = data.hero_specialties[sid]
	return {"id": sid, "name": String(spec["name"]), "text": String(spec["text"]), "mods": mods_at(spec, level),
		"formations": spec.get("formations", {}).duplicate(true), "steps": growth_steps(spec, level)}


## The base creature of a line (an upgraded creature maps to the one it upgrades).
static func line_of(creature_id: String, creature: Dictionary) -> String:
	return String(creature.get("upgrade_of", creature_id))


## Problems in the specialty data.
static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	for sid in data.hero_specialties:
		var s: Dictionary = data.hero_specialties[sid]
		var where := "hero specialty %s" % sid
		if String(s.get("name", "")) == "" or String(s.get("text", "")) == "":
			errors.append("%s needs a name and text" % where)
		var fac := String(s.get("faction", ""))
		if not data.factions.has(fac) or bool(data.factions[fac].get("neutral", false)):
			errors.append("%s has unknown or neutral faction %s" % [where, fac])
		if s.get("mods", {}).is_empty():
			errors.append("%s has no effect" % where)
		errors.append_array(HeroModifiers.validate(s.get("mods", {}), where, data))
		var g: Dictionary = s.get("growth", {})
		if not g.is_empty():
			if int(g.get("every", 0)) < 1 or g.get("mods", {}).is_empty():
				errors.append("%s growth needs every >= 1 and mods" % where)
			if g.has("max") and int(g["max"]) < 1:
				errors.append("%s growth max must be at least 1" % where)
			errors.append_array(HeroModifiers.validate(g.get("mods", {}), where + " growth", data))
		for key in ["creature_attack", "creature_defense"]:
			for cid in s.get("mods", {}).get(key, {}):
				if data.creatures.has(cid) and data.creatures[cid].has("upgrade_of"):
					errors.append("%s names upgraded creature %s; use the base creature of the line" % [where, cid])
		var known_formations: Dictionary = data.tactics.get("formations", {})
		for fid in s.get("formations", {}):
			var f: Variant = s["formations"][fid]
			if typeof(f) != TYPE_DICTIONARY or float(f.get("bonus_pct", 0.0)) < 0.0 or float(f.get("bonus_pct", 0.0)) > 1.0:
				errors.append("%s formation %s needs {unlock, bonus_pct in [0, 1]}" % [where, fid])
			# Formations arrive with the pre-battle formation rules; once
			# data/tactics.json lists them, unknown ids are errors.
			if not known_formations.is_empty() and not known_formations.has(fid):
				errors.append("%s names unknown formation %s" % [where, fid])
		for hname in s.get("heroes", []):
			if seen.has(hname):
				errors.append("hero %s has two specialties (%s and %s)" % [hname, seen[hname], sid])
			seen[hname] = sid
	# Every tavern hero has a personal specialty of its own faction.
	for fid in data.town_types:
		for h in data.town_types[fid].get("hire", {}).get("heroes", []):
			var sid := String(seen.get(h["name"], ""))
			if sid == "":
				errors.append("tavern hero %s has no specialty" % h["name"])
			elif data.hero_classes.has(h["class"]) and String(data.hero_specialties[sid]["faction"]) != String(data.hero_classes[h["class"]]["faction"]):
				errors.append("tavern hero %s has specialty %s of another faction" % [h["name"], sid])
	for fid in data.factions:
		if not bool(data.factions[fid].get("neutral", false)) and faction_pool(fid, data).is_empty():
			errors.append("faction %s has no hero specialties" % fid)
	return errors
