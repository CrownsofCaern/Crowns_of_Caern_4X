class_name MapAuthoring
extends RefCounted
## Validated authoring commands. Draft terrain may remain invalid elsewhere;
## these commands validate the edited entity and never initialize a game.

const TYPES := ["town", "hero", "mine", "resource", "neutral_army", "encounter", "artifact", "site"]
const OWNED_TYPES := ["town", "hero", "mine", "site"]
const MAX_PLAYERS := 8


static func registry(data: GameData, type: String) -> Dictionary:
	match type:
		"town": return data.town_types
		"hero": return data.hero_classes
		"mine", "resource": return data.resources
		"neutral_army": return data.creatures
		"encounter": return data.encounters
		"artifact": return data.artifacts
		"site": return data.sites
	return {}


static func content_field(type: String) -> String:
	return {"town": "town_type", "hero": "class", "mine": "resource", "resource": "resource",
		"encounter": "encounter", "artifact": "artifact", "site": "site"}.get(type, "")


static func supports_owner(data: GameData, type: String, content: String) -> bool:
	return data.sites.get(content, {}).get("kind") == "dwelling" if type == "site" else type in ["town", "hero", "mine"]


static func make_entity(data: GameData, type: String, content: String, owner: int) -> Dictionary:
	var definitions := registry(data, type)
	if not definitions.has(content):
		return {}
	var entity := {"name": str(definitions[content].get("name", content))}
	if type != "hero":
		entity["type"] = type
	if not content_field(type).is_empty():
		entity[content_field(type)] = content
	if supports_owner(data, type, content):
		entity["owner"] = owner
	match type:
		"hero":
			var faction: String = data.hero_classes[content]["faction"]
			entity["army"] = data.town_types.get(faction, {}).get("hire", {}).get("army", []).duplicate(true)
		"town":
			entity["built"] = data.town_types[content].get("starting_buildings", []).duplicate()
			entity["garrison"] = []
		"resource": entity["amount"] = 500 if content == "gold" else 5
		"neutral_army": entity["stacks"] = [[content, 10]]
		"site":
			if data.sites[content].get("kind") == "dwelling":
				var pool := MapSites.creature_pool(data.sites[content], data)
				if not pool.is_empty():
					entity["creature"] = pool[0]
			elif data.sites[content].get("kind") == "spell":
				var spells: Array = data.magic.get("spells", {}).keys()
				spells.sort()
				for spell in spells:
					if data.magic["spells"][spell].get("source") == "rare":
						entity["spell"] = spell
						break
	return entity


static func place(document: MapDocument, data: GameData, type: String, content: String,
		pos: Vector2i, owner: int = -1) -> Dictionary:
	var value := make_entity(data, type, content, owner)
	if value.is_empty():
		return {"error": "Choose a registered content item first."}
	value["id"] = document.unique_entity_id(type)
	value["pos"] = [pos.x, pos.y]
	var error := store(document, data, value, type == "hero")
	return {"error": error, "id": value["id"], "hero": type == "hero"}


static func entity_errors(value: Dictionary, hero: bool, definition: Dictionary, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var type := "hero" if hero else str(value.get("type", ""))
	if not type in TYPES:
		return ["Unsupported object type."]
	var field := content_field(type)
	if field != "" and not registry(data, type).has(value.get(field, "")):
		errors.append("Choose a known %s." % field)
	if not value.get("name", "") is String:
		errors.append("Name must be text.")
	if value.has("owner") or hero:
		var owner: Variant = value.get("owner", -1)
		if not MapDocument._integer(owner):
			errors.append("Owner must be a player slot.")
		elif int(owner) == -1 and not hero:
			pass
		elif not definition["players"].any(func(player): return player.get("id") == owner):
			errors.append("Choose an existing player for this %s." % type)
	for key in ["army", "stacks", "guard", "garrison"]:
		if not value.has(key):
			continue
		if not value[key] is Array or value[key].size() > Army.MAX_SLOTS:
			errors.append("%s must contain at most %d stacks." % [key, Army.MAX_SLOTS])
			continue
		for stack in value[key]:
			if not stack is Array or stack.size() < 2 or not stack[0] is String or not data.creatures.has(stack[0]) or not MapDocument._integer(stack[1]) or stack[1] < 1 or stack[1] > 1000000:
				errors.append("%s needs known creatures and positive whole counts (up to 1,000,000)." % key)
	if type == "neutral_army":
		var stacks: Variant = value.get("stacks", [])
		if not stacks is Array or stacks.is_empty():
			errors.append("A neutral army needs at least one stack.")
	if type == "resource" or value.has("amount"):
		if not MapDocument._integer(value.get("amount")) or int(value["amount"]) < 1:
			errors.append("Amount must be a positive whole number.")
	if type == "town" and data.town_types.has(value.get("town_type", "")):
		var buildings: Dictionary = data.town_types[value["town_type"]]["buildings"]
		if not value.get("built", []) is Array:
			errors.append("Built buildings must be a list.")
		else:
			for building in value.get("built", []):
				if not buildings.has(building):
					errors.append("Unknown building: %s." % str(building))
	if type == "site" and data.sites.has(value.get("site", "")) and data.sites[value["site"]].get("kind") == "dwelling":
		var pool := MapSites.creature_pool(data.sites[value["site"]], data)
		if not value.get("creature", "") in pool:
			errors.append("Choose a creature allowed by this dwelling.")
	if type == "site" and value.has("available") and (not MapDocument._integer(value["available"]) or int(value["available"]) < 0):
		errors.append("Starting recruits must be a non-negative whole number.")
	if value.get("guarded_by", "") != "":
		var found: bool = definition["objects"].any(func(object): return object.get("type") == "neutral_army" and object["id"] == value["guarded_by"] and object["id"] != value["id"])
		if not found:
			errors.append("The linked guard must be an existing neutral army.")
	return errors


static func store(document: MapDocument, data: GameData, value: Dictionary, hero: bool,
		existing_id: String = "") -> String:
	if document.read_only() or document.has_open_action():
		return "Finish the current action; scenario maps are read-only."
	if existing_id != "" and (value.get("id") != existing_id or document.entity(existing_id, hero).is_empty()):
		return "The original entity no longer exists; entity IDs cannot be renamed here."
	var definition := document.definition()
	var candidate := definition.duplicate(true)
	var field := "heroes" if hero else "objects"
	candidate[field] = candidate[field].filter(func(entry): return entry["id"] != existing_id)
	candidate[field].append(value)
	var errors := MapDocument.structural_errors(candidate, data)
	if not errors.is_empty():
		return "\n".join(errors)
	errors = entity_errors(value, hero, candidate, data)
	if not errors.is_empty():
		return "\n".join(errors)
	var pos := AdventureMap.object_pos(value)
	var map := AdventureMap.from_definition(candidate, data)
	if not map.is_passable(pos):
		return "Choose a passable tile, or paint a road/bridge first."
	for other in definition["objects"] + definition["heroes"]:
		if other["id"] == existing_id or AdventureMap.object_pos(other) != pos:
			continue
		var town_and_hero: bool = (hero and other.get("type") == "town") or (value.get("type") == "town" and other.has("class"))
		if not (town_and_hero and value.get("owner", -1) != -1 and value.get("owner") == other.get("owner")):
			return "That tile is occupied by %s." % str(other.get("name", other["id"]))
	if not document.put_entity(value, hero):
		return "The entity could not be changed."
	return ""


static func move(document: MapDocument, data: GameData, id: String, hero: bool, pos: Vector2i,
		duplicate: bool = false) -> Dictionary:
	var value := document.entity(id, hero)
	if value.is_empty():
		return {"error": "Select an existing entity first."}
	value["pos"] = [pos.x, pos.y]
	if duplicate:
		value["id"] = document.unique_entity_id("hero" if hero else str(value["type"]))
		value["name"] = str(value.get("name", id)) + " copy"
	return {"error": store(document, data, value, hero, "" if duplicate else id), "id": value["id"], "hero": hero}


static func delete(document: MapDocument, id: String, hero: bool) -> String:
	if document.read_only() or document.has_open_action():
		return "This document cannot be changed right now."
	if document.entity(id, hero).is_empty():
		return "Select an existing entity first."
	for other in document.definition()["objects"]:
		if other["id"] != id and other.get("guarded_by", "") == id:
			return "%s still links to this guard. Remove its Guarded by link first." % str(other.get("name", other["id"]))
	document.remove_entity(id, hero)
	return ""


## Rows retain original IDs while the dialog is open. Removing a referenced slot
## is blocked; surviving owners are remapped atomically when rows are reordered.
static func replace_players(document: MapDocument, data: GameData, rows: Array) -> String:
	if document.read_only() or document.has_open_action():
		return "This document cannot be changed right now."
	if rows.size() > MAX_PLAYERS:
		return "Maps support up to %d players." % MAX_PLAYERS
	var mapping := {}
	var players: Array = []
	for row in rows:
		if not row is Dictionary or not MapDocument._integer(row.get("id")) or int(row["id"]) < 0 or mapping.has(row["id"]):
			return "Player IDs must be distinct non-negative whole numbers."
		if not row.get("faction", "") in GameSetup.playable_factions(data):
			return "Choose a playable faction for every player."
		if not row.get("name") is String or not row.get("is_human") is bool or not row.get("color") is String or not Color.html_is_valid(row["color"]):
			return "Each player needs a name, controller and valid colour."
		if not data.difficulty_levels().has(row.get("difficulty", data.default_difficulty())):
			return "Choose a known computer difficulty."
		if not MapDocument._integer(row.get("team", 0)) or int(row.get("team", 0)) < 0 or int(row.get("team", 0)) > GameSetup.MAX_TEAMS:
			return "Team must be between 0 and %d." % GameSetup.MAX_TEAMS
		mapping[row["id"]] = players.size()
		var player: Dictionary = row.duplicate(true)
		player["id"] = players.size()
		players.append(player)
	var definition := document.definition()
	for value in definition["objects"] + definition["heroes"]:
		var owner: Variant = value.get("owner", -1)
		if owner != -1 and not mapping.has(owner):
			return "%s still belongs to removed player %s. Reassign or delete it first." % [str(value.get("name", value["id"])), str(owner)]
	document.begin_action("Configure players")
	if not document.set_players(players):
		document.cancel_action()
		return "Invalid player setup."
	for field in ["objects", "heroes"]:
		for value in definition[field]:
			var owner: Variant = value.get("owner", -1)
			if mapping.has(owner) and mapping[owner] != owner:
				value["owner"] = mapping[owner]
				if not document.put_entity(value, field == "heroes"):
					document.cancel_action()
					return "Player ownership could not be updated."
	document.end_action()
	return ""
