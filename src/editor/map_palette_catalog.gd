class_name MapPaletteCatalog
extends RefCounted
## Groups and orders editor palette content: faction tabs (with Wild last) for
## creatures and heroes, slot tabs for artifacts, kind tabs for sites. Creatures
## are sorted by tier with each base unit before its upgrade. Headless and pure,
## so the palettes and the stack editor share one ordering.

const ALL := "all"
const RARITY_ORDER := ["minor", "major", "relic"]
const SLOT_ORDER := ["weapon", "armor", "helm", "shield", "boots", "charm", "banner"]


## Tabs for a palette type: [{id, label, tooltip}], "all" first. Empty when
## the type is small enough not to need tabs.
static func categories(data: GameData, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = []
	match type:
		"neutral_army", "hero":
			ids = faction_order(data)
		"artifact":
			ids = _ordered(_values(data.artifacts, "slot"), SLOT_ORDER)
		"site":
			ids = _values(data.sites, "kind")
			ids.sort()
		_:
			return out
	var present := {}
	for id in MapAuthoring.registry(data, type):
		present[category_of(data, type, str(id))] = true
	out.append({"id": ALL, "label": "All", "tooltip": "Show everything"})
	for id in ids:
		if present.has(id):
			out.append({"id": id, "label": category_label(data, type, id), "tooltip": _category_tooltip(data, type, id)})
	return out


## Playable factions alphabetically, then neutral ones (the wild creatures).
static func faction_order(data: GameData) -> Array:
	var out: Array = GameSetup.playable_factions(data).duplicate()
	var ids := data.factions.keys()
	ids.sort()
	var neutral: Array = []
	for id in ids:
		if not out.has(id):
			if bool(data.factions[id].get("neutral", false)):
				neutral.append(id)
			else:
				out.append(id)
	out.append_array(neutral)
	return out


static func category_of(data: GameData, type: String, id: String) -> String:
	var definition: Dictionary = MapAuthoring.registry(data, type).get(id, {})
	match type:
		"neutral_army", "hero": return str(definition.get("faction", ""))
		"artifact": return str(definition.get("slot", ""))
		"site": return str(definition.get("kind", ""))
	return ""


static func category_label(data: GameData, type: String, id: String) -> String:
	if id == ALL:
		return "All"
	if type in ["neutral_army", "hero"]:
		return str(data.factions.get(id, {}).get("adjective", id.capitalize()))
	return id.capitalize()


## Ordered, filtered entries: [{id, label, group}]. group is a heading text
## that changes where a new section starts (tier, faction or rarity).
static func entries(data: GameData, type: String, category: String = ALL, query: String = "") -> Array[Dictionary]:
	var definitions := MapAuthoring.registry(data, type)
	var ids: Array = definitions.keys()
	var context := {"factions": faction_order(data), "bases": _upgrade_bases(data)}
	var keys := {}
	for id in ids:
		keys[id] = _sort_key(data, type, str(id), context)
	ids.sort_custom(func(a, b): return _less(keys[a], keys[b]))
	var out: Array[Dictionary] = []
	var needle := query.strip_edges().to_lower()
	for id in ids:
		var key := str(id)
		if category != ALL and category_of(data, type, key) != category:
			continue
		if needle != "" and not search_text(data, type, key).contains(needle):
			continue
		out.append({"id": key, "label": _label(data, type, key, context), "group": _group(data, type, key, category)})
	return out


static func entry_label(data: GameData, type: String, id: String) -> String:
	return _label(data, type, id, {"bases": _upgrade_bases(data)})


static func _label(data: GameData, type: String, id: String, context: Dictionary) -> String:
	var definition: Dictionary = MapAuthoring.registry(data, type).get(id, {})
	var name := str(definition.get("name", id))
	if type == "neutral_army":
		return "T%d%s %s" % [int(definition.get("tier", 0)), "+" if context["bases"].has(id) else "", name]
	return name


static func search_text(data: GameData, type: String, id: String) -> String:
	var definition: Dictionary = MapAuthoring.registry(data, type).get(id, {})
	var category := category_of(data, type, id)
	return " ".join([str(MapAuthoring.registry(data, type).get(id, {}).get("name", id)), id, category, category_label(data, type, category) if category != "" else ""]).to_lower()


## True for a creature that some other creature upgrades into.
static func is_upgrade(data: GameData, id: String) -> bool:
	for creature in data.creatures.values():
		if str(creature.get("upgrade", "")) == id:
			return true
	return false


## Upgrade id -> base id.
static func _upgrade_bases(data: GameData) -> Dictionary:
	var out := {}
	var ids := data.creatures.keys()
	ids.sort()
	for id in ids:
		var upgrade := str(data.creatures[id].get("upgrade", ""))
		if upgrade != "" and not out.has(upgrade):
			out[upgrade] = str(id)
	return out


static func _sort_key(data: GameData, type: String, id: String, context: Dictionary) -> Array:
	var definition: Dictionary = MapAuthoring.registry(data, type).get(id, {})
	var name := str(definition.get("name", id))
	match type:
		"neutral_army":
			var faction: int = context["factions"].find(str(definition.get("faction", "")))
			# Base before upgrade: an upgrade sorts right after its base unit.
			var base := str(context["bases"].get(id, id))
			var base_name := str(data.creatures.get(base, {}).get("name", base))
			return [faction, int(definition.get("tier", 0)), base_name, 1 if base != id else 0, name]
		"hero":
			return [context["factions"].find(str(definition.get("faction", ""))), name]
		"artifact":
			return [_rank(str(definition.get("slot", "")), SLOT_ORDER), _rank(str(definition.get("rarity", "")), RARITY_ORDER), name]
		"site":
			return [str(definition.get("kind", "")), name]
	return [name, id]


static func _group(data: GameData, type: String, id: String, category: String) -> String:
	var definition: Dictionary = MapAuthoring.registry(data, type).get(id, {})
	match type:
		"neutral_army":
			var tier := "Tier %d" % int(definition.get("tier", 0))
			return tier if category != ALL else category_label(data, type, category_of(data, type, id)) + " · " + tier
		"hero":
			return "" if category != ALL else category_label(data, type, category_of(data, type, id))
		"artifact":
			var rarity := str(definition.get("rarity", "")).capitalize()
			return rarity if category != ALL else str(definition.get("slot", "")).capitalize() + " · " + rarity
		"site":
			return "" if category != ALL else str(definition.get("kind", "")).capitalize()
	return ""


static func _category_tooltip(data: GameData, type: String, id: String) -> String:
	if type in ["neutral_army", "hero"]:
		return str(data.factions.get(id, {}).get("name", id))
	return id.capitalize()


static func _values(definitions: Dictionary, field: String) -> Array:
	var seen := {}
	for definition in definitions.values():
		if definition is Dictionary and definition.has(field):
			seen[str(definition[field])] = true
	return seen.keys()


static func _ordered(values: Array, preferred: Array) -> Array:
	var out: Array = []
	for value in preferred:
		if values.has(value):
			out.append(value)
	var rest: Array = []
	for value in values:
		if not out.has(value):
			rest.append(value)
	rest.sort()
	out.append_array(rest)
	return out


static func _rank(value: String, order: Array) -> int:
	var index := order.find(value)
	return index if index >= 0 else order.size()


static func _less(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] == b[i]:
			continue
		if typeof(a[i]) != typeof(b[i]):
			return str(a[i]) < str(b[i])
		return a[i] < b[i]
	return a.size() < b.size()
