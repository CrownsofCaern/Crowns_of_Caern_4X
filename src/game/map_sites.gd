class_name MapSites
extends RefCounted
## Rare map buildings ("site" map objects, data/sites.json). A site is a map
## object dictionary (so it saves with the map):
##   id, type = "site", pos, site (data id), guard?: [[creature, count]] (fought
##   once, like a guarded mine), and by kind:
##   dwelling:  owner (-1 = nobody), creature, available (weekly pool)
##   village:   owner (-1 = nobody; the first player to free it keeps it for
##              good), stock [[creature, count]] (a one-off stock, never refilled)
##   attribute, lore: visitors [hero ids] (each hero benefits once)
##   boon:      nothing; a hero holds the boon (Hero.boons, source = site id)
##   trader:    stock [{kind, artifact?, tiles?, price, remaining}] (MapTraders)
##   watchtower: visitors ["p<player index>"] (each player sees from it once)
##   drill:     visitors [hero ids] (each hero's army drills once)
##   mana_well: drawn {hero id: week} (each hero draws once a week)
## All functions are static and take the dictionaries, like Town.

const KINDS := ["dwelling", "village", "attribute", "boon", "lore", "spell", "trader", "watchtower", "drill", "mana_well", "cobolt"]
## Kinds a player owns and recruits from.
const RECRUIT_KINDS := ["dwelling", "village"]
const ATTRIBUTES := ["attack", "defense", "power", "knowledge"]


static func definition(obj: Dictionary, data: GameData) -> Dictionary:
	return data.sites.get(String(obj.get("site", "")), {})


static func site_name(obj: Dictionary, data: GameData) -> String:
	return "Plundered Cobolt Post" if bool(obj.get("plundered", false)) else String(definition(obj, data).get("name", "Site"))


static func kind(obj: Dictionary, data: GameData) -> String:
	return String(definition(obj, data).get("kind", ""))


## Fills in defaults and coerces JSON floats. Idempotent.
static func normalize(obj: Dictionary, data: GameData) -> void:
	if MapCobolts.is_post(obj, data):
		MapCobolts.normalize(obj, data)
	if kind(obj, data) == "trader":
		MapTraders.normalize(obj, data)
	var g: Array = []
	for pair in obj.get("guard", []):
		g.append([String(pair[0]), int(pair[1])])
	if g.is_empty():
		obj.erase("guard")
	else:
		obj["guard"] = g
	var vis: Array = []
	for v in obj.get("visitors", []):
		vis.append(String(v))
	vis.sort()
	obj["visitors"] = vis
	if kind(obj, data) == "mana_well":
		var drawn := {}
		for hid in obj.get("drawn", {}):
			drawn[String(hid)] = int(obj["drawn"][hid])
		obj["drawn"] = drawn
	if kind(obj, data) == "dwelling":
		obj["owner"] = int(obj.get("owner", -1))
		var c := String(obj.get("creature", ""))
		if c == "" or data.creature(c).is_empty():
			var pool := creature_pool(definition(obj, data), data)
			c = pool[0] if not pool.is_empty() else ""
		obj["creature"] = c
		if not obj.has("available"):
			obj["available"] = weekly_growth(obj, data)
		obj["available"] = int(obj["available"])
	elif kind(obj, data) == "village":
		obj["owner"] = int(obj.get("owner", -1))
		if not obj.has("stock"):
			obj["stock"] = default_stock(obj, data)
		var stock: Array = []
		for pair in obj["stock"]:
			stock.append([String(pair[0]), maxi(0, int(pair[1]))])
		obj["stock"] = stock


## The stock of a village placed without one (an authored or editor map):
## stock_types creatures of the def's pool, picked from the object id so the
## same map always offers the same folk, stock_weeks of their weekly growth each.
static func default_stock(obj: Dictionary, data: GameData) -> Array:
	var def := definition(obj, data)
	var pool := creature_pool(def, data)
	var out: Array = []
	if pool.is_empty():
		return out
	var types := mini(pool.size(), maxi(1, int(def.get("stock_types", 1))))
	var start := absi(String(obj.get("id", "")).hash()) % pool.size()
	for i in types:
		var c: String = pool[(start + i * 2) % pool.size()]
		if out.any(func(p): return p[0] == c):
			continue
		out.append([c, maxi(1, int(round(float(data.creature(c).get("growth", 1)) * float(def.get("stock_weeks", 1.0)))))])
	return out


## What can be recruited at a dwelling or village site now: [[creature, available]],
## in stock order (a dwelling has one entry). Other kinds offer nothing.
static func offers(obj: Dictionary, data: GameData) -> Array:
	match kind(obj, data):
		"dwelling":
			return [[String(obj.get("creature", "")), int(obj.get("available", 0))]]
		"village":
			return (obj.get("stock", []) as Array).duplicate(true)
	return []


## How many of creature the site still offers (0 if none or not offered).
static func available(obj: Dictionary, creature: String, data: GameData) -> int:
	for pair in offers(obj, data):
		if String(pair[0]) == creature:
			return int(pair[1])
	return 0


## Takes count creatures out of the site's pool (callers check availability).
static func take(obj: Dictionary, creature: String, count: int, data: GameData) -> void:
	if kind(obj, data) == "dwelling":
		obj["available"] = int(obj["available"]) - count
		return
	for pair in obj.get("stock", []):
		if String(pair[0]) == creature:
			pair[1] = int(pair[1]) - count


## The base creatures a dwelling site may house: tiers within the def's range,
## of the six town factions ("playable") or any faction including the wilds
## ("any"), never an upgraded form. Sorted by id.
static func creature_pool(def: Dictionary, data: GameData) -> Array[String]:
	var out: Array[String] = []
	var tiers: Array = def.get("tiers", [1, 8])
	var any := String(def.get("factions", "playable")) == "any"
	for id in data.creatures:
		var c: Dictionary = data.creatures[id]
		if c.get("faction", "") == "cobolts" or c.has("upgrade_of") or int(c.get("growth", 0)) <= 0:
			continue
		var t := int(c["tier"])
		if t < int(tiers[0]) or t > int(tiers[1]):
			continue
		if not (any or data.town_types.has(String(c["faction"]))):
			continue
		out.append(String(id))
	out.sort()
	return out


## Creatures added to a dwelling site's pool each week; extra_pct is the week's
## omen bonus for that creature (WorldEvents.growth_bonus).
static func weekly_growth(obj: Dictionary, data: GameData, extra_pct: float = 0.0) -> int:
	var c := String(obj.get("creature", ""))
	if c == "":
		return 0
	var pct := float(definition(obj, data).get("growth_pct", 1.0))
	return maxi(0, int(floor(float(data.creature(c).get("growth", 0)) * pct * (1.0 + extra_pct))))


## Why this hero gains nothing by visiting, or "" if the visit pays off.
## Dwellings are always worth entering (capture and recruitment). day: the
## current day (only a mana well needs it: one draw per hero per week).
static func visit_block(h: Hero, obj: Dictionary, data: GameData, day: int = 0) -> String:
	match kind(obj, data):
		"attribute", "lore", "drill":
			if (obj.get("visitors", []) as Array).has(h.id):
				return "%s has already been here" % h.name
			if kind(obj, data) == "drill" and h.army.is_empty():
				return "%s has no army to drill" % h.name
		"watchtower":
			if (obj.get("visitors", []) as Array).has(player_key(h.owner)):
				return "Your scouts have already climbed it"
		"mana_well":
			if h.mana >= h.max_mana(data):
				return "%s's mana is already full" % h.name
			if day > 0 and int(obj.get("drawn", {}).get(h.id, 0)) == week_of(day):
				return "%s has drawn from it this week" % h.name
		"spell":
			if h.known_spells(data).has(String(obj.get("spell", ""))):
				return "%s already knows this spell" % h.name
		"boon":
			if h.has_boon(String(obj["id"])):
				return "%s still carries this blessing" % h.name
	return ""


## Applies the visit's effect to the hero (and records it on the site).
## Returns {applied, lines, levels}. Dwellings are captured by the session.
static func visit(h: Hero, obj: Dictionary, day: int, data: GameData) -> Dictionary:
	var out := {"applied": false, "lines": [], "levels": 0, "reveal": 0}
	if visit_block(h, obj, data, day) != "":
		return out
	var def := definition(obj, data)
	match String(def.get("kind", "")):
		"attribute":
			var attrs: Dictionary = def.get("attributes", {})
			for a in ATTRIBUTES:
				if attrs.has(a):
					h.set(a, int(h.get(a)) + int(attrs[a]))
					out["lines"].append("%+d %s" % [int(attrs[a]), a.capitalize()])
			_add_visitor(obj, h.id)
		"lore":
			var gained := h.xp_with_bonus(int(def.get("xp", 0)), data)
			out["levels"] = h.add_xp(gained, data)
			out["lines"].append("+%d experience" % gained)
			_add_visitor(obj, h.id)
		"spell":
			var spell_id := String(obj.get("spell", ""))
			if not data.magic.get("spells", {}).has(spell_id) or data.magic["spells"][spell_id].get("source", "") != "rare":
				return out
			h.spells.append(spell_id)
			h.spells.sort()
			out["lines"].append("Learned %s" % data.magic["spells"][spell_id]["name"])
		"boon":
			var days := int(def.get("days", 7))
			h.add_boon(String(obj["id"]), String(def["name"]), day + days - 1, def.get("mods", {}))
			out["lines"].append("%s for %d days" % [describe_mods(def.get("mods", {})), days])
		"watchtower":
			out["reveal"] = int(def.get("radius", 10))
			out["lines"].append("the land for %d tiles around lies open" % int(out["reveal"]))
			_add_visitor(obj, player_key(h.owner))
		"drill":
			h.army.gain_veteran_xp(int(def.get("veteran_xp", 0)), data)
			out["lines"].append("+%d veteran experience for every stack" % int(def.get("veteran_xp", 0)))
			_add_visitor(obj, h.id)
		"mana_well":
			var before := h.mana
			h.restore_mana(h.max_mana(data), data)
			out["lines"].append("+%d mana" % (h.mana - before))
			var drawn: Dictionary = obj.get("drawn", {})
			drawn[h.id] = week_of(day)
			obj["drawn"] = drawn
		_:
			return out
	out["applied"] = true
	return out


static func player_key(player_idx: int) -> String:
	return "p%d" % player_idx


static func week_of(day: int) -> int:
	return (maxi(1, day) - 1) / 7 + 1


static func _add_visitor(obj: Dictionary, hero_id: String) -> void:
	var vis: Array = obj.get("visitors", [])
	if not vis.has(hero_id):
		vis.append(hero_id)
		vis.sort()
	obj["visitors"] = vis


## Short text for a mods dictionary of the keys sites and events use.
static func describe_mods(mods: Dictionary) -> String:
	var parts := []
	var keys := mods.keys()
	keys.sort()
	for k in keys:
		var v: Variant = mods[k]
		if HeroModifiers.KEYS.get(k, "") == "pct":
			parts.append("%+d%% %s" % [roundi(float(v) * 100.0), String(k).trim_suffix("_pct").replace("_", " ")])
		elif typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			parts.append("%+d %s" % [int(v), String(k).replace("_", " ")])
	return ", ".join(parts)


## One line on what the site does, for tooltips and dialogs.
static func summary(obj: Dictionary, data: GameData) -> String:
	var def := definition(obj, data)
	match String(def.get("kind", "")):
		"cobolt":
			return "Plundered: trade has ended" if obj.get("plundered", false) else "One recruit type, one artefact and one fixed exchange · 40% cheaper"
		"trader":
			return "Buy artifacts and maps that uncover %d random hidden tiles" % int(def.get("trade", {}).get("map_tiles", 40))
		"dwelling":
			var c := String(obj.get("creature", ""))
			var cname: String = data.creature(c).get("name", "?")
			return "Recruit %s (%d available)%s" % [cname, int(obj.get("available", 0)),
				", a new company each week" if bool(def.get("rotate", false)) else ""]
		"village":
			var parts := []
			for pair in obj.get("stock", []):
				if int(pair[1]) > 0:
					parts.append("%d %s" % [int(pair[1]), data.creature(String(pair[0])).get("name", "?")])
			if parts.is_empty():
				return "Its volunteers have all marched off"
			return "Volunteers, once only: %s" % ", ".join(parts)
		"attribute":
			var parts := []
			for a in ATTRIBUTES:
				if def.get("attributes", {}).has(a):
					parts.append("%+d %s" % [int(def["attributes"][a]), a.capitalize()])
			return "%s for every hero, once" % ", ".join(parts)
		"boon":
			return "%s for %d days" % [describe_mods(def.get("mods", {})), int(def.get("days", 7))]
		"spell":
			return "Ancient spell: %s" % data.magic.get("spells", {}).get(String(obj.get("spell", "")), {}).get("name", "unknown")
		"lore":
			return "+%d experience for every hero, once" % int(def.get("xp", 0))
		"watchtower":
			return "Reveals the land for %d tiles around, once for each player" % int(def.get("radius", 10))
		"drill":
			return "+%d veteran experience for every stack, once per hero" % int(def.get("veteran_xp", 0))
		"mana_well":
			return "Refills a hero's mana, once a week"
	return ""


# ------------------------------------------------------------- validation --

static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = MapTraders.validate(data)
	errors.append_array(MapCobolts.validate(data))
	var levels: Dictionary = data.map_templates.get("guard_levels", {})
	for sid in data.sites:
		var d: Dictionary = data.sites[sid]
		var where := "site %s" % sid
		for key in ["name", "kind", "text", "sprite"]:
			if not d.has(key):
				errors.append("%s missing %s" % [where, key])
		var k := String(d.get("kind", ""))
		if not KINDS.has(k):
			errors.append("%s has unknown kind %s" % [where, k])
		if not levels.is_empty() and not levels.has(String(d.get("guard", "none"))):
			errors.append("%s has unknown guard level %s" % [where, d.get("guard", "")])
		if float(d.get("weight", 1)) <= 0.0:
			errors.append("%s needs a positive weight" % where)
		match k:
			"dwelling":
				var tiers: Array = d.get("tiers", [])
				if tiers.size() != 2 or int(tiers[0]) < 1 or int(tiers[0]) > int(tiers[1]):
					errors.append("%s needs tiers [min, max]" % where)
				elif creature_pool(d, data).is_empty():
					errors.append("%s has no creature to house" % where)
				if not ["playable", "any"].has(String(d.get("factions", "playable"))):
					errors.append("%s has unknown factions %s" % [where, d.get("factions", "")])
				if float(d.get("growth_pct", 1.0)) <= 0.0:
					errors.append("%s needs a positive growth_pct" % where)
			"village":
				var tiers: Array = d.get("tiers", [])
				if tiers.size() != 2 or int(tiers[0]) < 1 or int(tiers[0]) > int(tiers[1]):
					errors.append("%s needs tiers [min, max]" % where)
				elif creature_pool(d, data).is_empty():
					errors.append("%s has no creature to house" % where)
				if not ["playable", "any"].has(String(d.get("factions", "playable"))):
					errors.append("%s has unknown factions %s" % [where, d.get("factions", "")])
				if int(d.get("stock_types", 0)) < 1 or int(d.get("stock_types", 0)) > 2:
					errors.append("%s needs stock_types 1 or 2" % where)
				if float(d.get("stock_weeks", 0.0)) <= 0.0:
					errors.append("%s needs a positive stock_weeks" % where)
				if String(d.get("guard", "none")) == "none":
					errors.append("%s must be guarded" % where)
			"attribute":
				var attrs: Dictionary = d.get("attributes", {})
				if attrs.is_empty():
					errors.append("%s grants no attributes" % where)
				for a in attrs:
					if not ATTRIBUTES.has(a) or int(attrs[a]) <= 0:
						errors.append("%s has invalid attribute %s" % [where, a])
			"boon":
				if (d.get("mods", {}) as Dictionary).is_empty():
					errors.append("%s grants no mods" % where)
				errors.append_array(HeroModifiers.validate(d.get("mods", {}), where, data))
				if int(d.get("days", 0)) < 1:
					errors.append("%s needs days >= 1" % where)
			"lore":
				if int(d.get("xp", 0)) <= 0:
					errors.append("%s needs xp > 0" % where)
			"watchtower":
				if int(d.get("radius", 0)) <= 0:
					errors.append("%s needs radius > 0" % where)
			"drill":
				if int(d.get("veteran_xp", 0)) <= 0:
					errors.append("%s needs veteran_xp > 0" % where)
		if not RECRUIT_KINDS.has(k):
			var ai: Dictionary = d.get("ai", {})
			if not ai.has("flat") or not ai.has("army_pct"):
				errors.append("%s needs ai {flat, army_pct}" % where)
	var cfg: Dictionary = data.map_templates.get("sites", {})
	var bands: Dictionary = data.map_templates.get("distance_bands", {})
	var per: Dictionary = cfg.get("per_player", {})
	if not per.is_empty():
		if not bands.has(String(per.get("band", ""))):
			errors.append("map_templates sites.per_player: unknown band")
		for k in per.get("kinds", []):
			if not KINDS.has(k) or k == "village":
				errors.append("map_templates sites.per_player: unknown kind %s" % k)
	var extra: Dictionary = cfg.get("extras", {})
	if not extra.is_empty():
		if not bands.has(String(extra.get("band", ""))):
			errors.append("map_templates sites.extras: unknown band")
		if int(extra.get("min", 0)) < 0 or int(extra.get("min", 0)) > int(extra.get("max", 0)):
			errors.append("map_templates sites.extras: need 0 <= min <= max")
		for pid in extra.get("zone_weights", {}):
			if not data.map_templates.get("profiles", {}).has(pid):
				errors.append("map_templates sites.extras: unknown profile %s" % pid)
	return errors
