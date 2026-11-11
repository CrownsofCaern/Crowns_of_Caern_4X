class_name MapPlayability
extends RefCounted
## Safe launch checks for authored conquest definitions. Drafts remain saveable.
## All shape/type checks precede the shared validator and runtime constructors.

static func errors(definition: Dictionary, data: GameData) -> Array[String]:
	var problems := MapDocument.structural_errors(definition, data)
	if not problems.is_empty():
		return problems
	if definition.has("scenario"):
		return ["Scenario maps are read-only in this editor and cannot be launched as custom conquest maps."]
	if definition.has("generator"):
		return ["Create an authored copy of the generated map before launching it."]
	var players: Array = definition["players"]
	if players.is_empty() or players.size() > MapAuthoring.MAX_PLAYERS:
		return ["Configure between 1 and %d players." % MapAuthoring.MAX_PLAYERS]
	var humans := 0
	var colours := {}
	var sides := {}
	for i in players.size():
		var player: Dictionary = players[i]
		for key in ["id", "name", "faction", "color", "is_human"]:
			if not player.has(key):
				problems.append("Player %d is missing %s. Open Players and apply its settings." % [i + 1, key])
		if player.get("id", -1) != i:
			problems.append("Player IDs must match their slot order. Apply Players to renumber them.")
		if not player.get("faction", "") in GameSetup.playable_factions(data):
			problems.append("Player %d needs a playable faction." % (i + 1))
		if not data.difficulty_levels().has(player.get("difficulty", data.default_difficulty())):
			problems.append("Player %d has an unknown difficulty." % (i + 1))
		var team := int(player.get("team", 0))
		if team < 0 or team > GameSetup.MAX_TEAMS:
			problems.append("Player %d has an invalid team." % (i + 1))
		sides[team if team > 0 else -1 - i] = true
		if player.get("is_human", false):
			humans += 1
		if player.has("color"):
			var colour := Color(player["color"]).to_html(false)
			if colours.has(colour):
				problems.append("Players need distinct colours.")
			colours[colour] = true
	if humans == 0:
		problems.append("At least one player must be human.")
	if players.size() > 1 and sides.size() == 1:
		problems.append("Every player is on the same team; choose opposing sides.")
	for field in ["objects", "heroes"]:
		for entity in definition[field]:
			var hero: bool = field == "heroes"
			for key in ["sprite", "zone", "role", "guarded_by"]:
				if entity.has(key) and not entity[key] is String:
					problems.append("%s: %s must be text." % [entity["id"], key])
			for problem in MapAuthoring.entity_errors(entity, hero, definition, data):
				problems.append("%s: %s" % [entity["id"], problem])
			if hero and (not entity.has("name") or not entity.has("army") or not entity["army"] is Array or entity["army"].is_empty()):
				problems.append("Hero %s needs a name and a starting army." % entity["id"])
			# Runtime normalization reads these optional authored fields directly.
			for key in ["visitors", "stock"]:
				if entity.has(key) and not entity[key] is Array:
					problems.append("%s: %s must be a list." % [entity["id"], key])
			if entity.get("visitors") is Array:
				for visitor in entity["visitors"]:
					if not visitor is String:
						problems.append("%s: visitor IDs must be text." % entity["id"])
			if MapCobolts.is_post(entity, data):
				for problem in MapCobolts.object_errors(entity, data):
					problems.append("%s: %s" % [entity["id"], problem])
			if entity.get("stock") is Array and not MapCobolts.is_post(entity, data):
				for offer in entity["stock"]:
					if not offer is Dictionary:
						problems.append("%s: stock entries must be dictionaries." % entity["id"])
						continue
					if offer.get("kind") not in ["artifact", "map"]:
						problems.append("%s: unknown trade offer kind." % entity["id"])
					for key in ["price", "remaining"]:
						if not offer.has(key):
							problems.append("%s: trade offer is missing %s." % [entity["id"], key])
					if offer.get("kind") == "artifact" and not data.artifacts.has(offer.get("artifact", "")):
						problems.append("%s: unknown trade artifact." % entity["id"])
					for key in ["price", "remaining", "tiles"]:
						if offer.has(key) and (not MapDocument._integer(offer[key]) or offer[key] < 0):
							problems.append("%s: trade quantities must be non-negative whole numbers." % entity["id"])
			if entity.has("last_build_day") and not MapDocument._integer(entity["last_build_day"]):
				problems.append("%s: last build day must be a whole number." % entity["id"])
			if entity.get("type") == "town" and entity.has("available"):
				if not entity["available"] is Dictionary:
					problems.append("%s: town recruit stock must be a dictionary." % entity["id"])
				else:
					for creature in entity["available"]:
						var count: Variant = entity["available"][creature]
						if not data.creatures.has(creature) or not MapDocument._integer(count) or count < 0:
							problems.append("%s: invalid town recruit stock." % entity["id"])
			if entity.get("type") == "site" and data.sites.get(entity.get("site", ""), {}).get("kind") == "spell":
				var spell: Variant = entity.get("spell", "")
				if not spell is String or data.magic.get("spells", {}).get(spell, {}).get("source") != "rare":
					problems.append("%s: choose a rare spell for this site." % entity["id"])
	if not problems.is_empty():
		return problems
	for i in players.size():
		if not definition["heroes"].any(func(hero): return hero.get("owner", -1) == i):
			problems.append("Player %d needs a starting hero." % (i + 1))
		if not definition["objects"].any(func(object): return object.get("type") == "town" and object.get("owner", -1) == i):
			problems.append("Player %d needs a starting town." % (i + 1))
	if not problems.is_empty():
		return problems
	return MapValidator.validate(definition, data)
