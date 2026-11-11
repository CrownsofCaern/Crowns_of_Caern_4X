class_name MapTipInfo
extends RefCounted
## What the hover card says about a map tile: the structure or hero on it, what
## it is ("Mine", "Rare building"), who holds it and what it does. Read-only:
## it reads the session's state and data, never changes them. Hostile armies
## get their troops and odds from GameSession.intel() on top (see MapTip).

const FLAVOR_CHARS := 130


## {title, kind, lines: [[text, colour], ...]} for the object or hero on t as
## the current player sees it, or {} for plain ground (or unexplored tiles).
## hero: the selected hero (for "already visited" notes), may be null.
static func describe(session: GameSession, t: Vector2i, hero: Hero) -> Dictionary:
	var map := session.state.map
	var me := session.state.current_player
	if not map.in_bounds(t) or not (session.current_player()["fog"] as FogOfWar).is_explored(t):
		return {}
	var o := map.object_at(t)
	var h := session.state.hero_at(t)
	# A hero in a town is described with the town.
	if h != null and (o.is_empty() or o["type"] != "town"):
		return _hero(session, h, me)
	if o.is_empty():
		return {}
	var data := session.data
	var lines := []
	match String(o["type"]):
		"town":
			var owner := int(o["owner"])
			lines.append(_owner_line(session, owner, me))
			var walls := Town.defense_bonus(o, data)
			if walls > 0:
				lines.append(["Walls: +%d defense for its defenders" % walls, UiStyle.TEXT])
			var inc := Town.daily_income(o, data)
			if not inc.is_empty():
				lines.append(["Income: %s a day" % _resources(inc, data), UiStyle.TEXT])
			if h != null:
				lines.append(["%s stands in the town" % h.name, UiStyle.TEXT])
			if session.allied(owner, me) and owner >= 0:
				var g := Town.garrison(o)
				if not g.is_empty():
					lines.append(["Garrison: %d creatures" % g.total_creatures(), UiStyle.TEXT_DIM])
				lines.append(["Enter to build and recruit" if owner == me else "An ally's town", UiStyle.TEXT_DIM])
			elif o.has("requires_quest") and ScenarioQuests.status(session.state, String(o["requires_quest"])) != "complete":
				lines.append(["Complete this settlement's pact to earn its alliance.", UiStyle.BRASS])
			elif not session.is_guarded(o, me):
				lines.append(["Undefended: march in to take it", UiStyle.GOOD])
			return {"title": String(o["name"]), "kind": "Town · %s" % data.town_types[o["town_type"]]["name"], "lines": lines}
		"mine":
			var owner := int(o["owner"])
			lines.append(["+%d %s a day to its owner" % [Economy.mine_income(o, data), data.resources[o["resource"]]["name"]], UiStyle.BRASS])
			lines.append(_owner_line(session, owner, me, "Unclaimed"))
			if _guard_line(session, o, me, lines):
				pass
			elif owner != me and not session.is_guarded(o, me) and not session.allied(owner, me):
				lines.append(["Step on it to claim it", UiStyle.TEXT_DIM])
			return {"title": Economy.mine_name(o, data), "kind": "Mine", "lines": lines}
		"resource":
			lines.append(["%d %s" % [int(o["amount"]), data.resources[o["resource"]]["name"]], UiStyle.BRASS])
			if not _guard_line(session, o, me, lines):
				lines.append(["Walk over it to pick it up", UiStyle.TEXT_DIM])
			return {"title": String(data.resources[o["resource"]]["name"]), "kind": "Resource pile", "lines": lines}
		"artifact":
			var art: Dictionary = data.artifacts.get(String(o["artifact"]), {})
			lines.append([String(art.get("text", "")), UiStyle.BRASS])
			if not _guard_line(session, o, me, lines):
				lines.append(["Walk over it to take it into the pack", UiStyle.TEXT_DIM])
			return {"title": String(art.get("name", "Artifact")),
				"kind": "Artifact · %s · %s" % [String(art.get("slot", "")).capitalize(), String(art.get("rarity", "")).capitalize()], "lines": lines}
		"encounter":
			var enc: Dictionary = data.encounters.get(String(o["encounter"]), {})
			var flavor := flavor_text(String(enc.get("text", "")))
			if flavor != "":
				lines.append([flavor, UiStyle.TEXT_DIM])
			var choices := []
			for c in enc.get("choices", []):
				choices.append(String(c.get("text", "")))
			if not choices.is_empty():
				lines.append(["Choices: " + ", ".join(choices), UiStyle.TEXT])
			lines.append(["Step on it to choose; it is gone once resolved", UiStyle.TEXT_DIM])
			return {"title": String(enc.get("name", "Encounter")), "kind": "Encounter", "lines": lines}
		"site":
			var def := MapSites.definition(o, data)
			var kind := MapSites.kind(o, data)
			lines.append([MapSites.summary(o, data), UiStyle.BRASS])
			if MapSites.RECRUIT_KINDS.has(kind):
				lines.append(_owner_line(session, int(o.get("owner", -1)), me, "Unclaimed"))
			elif hero != null and hero.owner == me:
				var why := MapSites.visit_block(hero, o, data, session.state.day)
				if why != "":
					lines.append([why, UiStyle.TEXT_DIM])
			var flavor := flavor_text(String(def.get("text", "")))
			if flavor != "":
				lines.append([flavor, UiStyle.TEXT_DIM])
			return {"title": MapSites.site_name(o, data), "kind": "Rare building · %s" % _site_kind(kind), "lines": lines}
		"scenario_site":
			lines.append([String(o.get("text", "")), UiStyle.TEXT])
			lines.append(["Secured" if bool(o.get("claimed", false)) else "Visit to inspect this mission opportunity", UiStyle.BRASS])
			if not bool(o.get("claimed", false)) and session.state.day < int(o.get("unlock_day", 1)):
				lines.append(["Opens on day %d" % int(o["unlock_day"]), UiStyle.TEXT_DIM])
			return {"title": o.get("name", "Mission site"), "kind": "Mission · " + String(o.get("kind", "site")).capitalize(), "lines": lines}
		"quest_item":
			lines.append(["A quest relic. Carry it back to the quest giver; it uses no equipment space.", UiStyle.BRASS])
			if session.state.map.objects.has(String(o.get("guarded_by", ""))):
				lines.append(["Defeat its guardian before taking it.", UiStyle.WARN])
			return {"title": o.get("name", "Relic"), "kind": "Quest item", "lines": lines}
		"gate":
			lines.append(["Sealed: armies must use an alternate route." if bool(o.get("closed", false)) else "Open. Capture the connected nest to seal it.", UiStyle.BRASS])
			return {"title": o.get("name", "Tunnel"), "kind": "Strategic gate", "lines": lines}
		"neutral_army":
			return {"title": String(o.get("name", "Neutral army")), "kind": "Neutral army", "lines": lines}
	return {}


## Adds the warning for a prize a neutral army stands guard over (see
## GameSession.claim_guard); true if there was one.
static func _guard_line(session: GameSession, o: Dictionary, me: int, lines: Array) -> bool:
	var guard := session.claim_guard(o, me)
	if guard.is_empty():
		return false
	lines.append(["Guarded by %s: stepping on it starts a battle" % String(guard.get("name", "a neutral army")), UiStyle.WARN])
	return true


static func _hero(session: GameSession, h: Hero, me: int) -> Dictionary:
	var data := session.data
	var lines := [_owner_line(session, h.owner, me)]
	if h.owner == me:
		lines.append(["Movement left: %d of %d" % [h.movement_left, h.max_movement(data)], UiStyle.TEXT])
		lines.append(["Army: %d creatures" % h.army.total_creatures(), UiStyle.TEXT_DIM])
	return {"title": h.name, "kind": "Hero · level %d %s" % [h.level, data.hero_classes[h.class_id]["name"]], "lines": lines}


## "Yours", "Ally: Name", "Enemy: Name" or the neutral word, coloured.
static func _owner_line(session: GameSession, owner: int, me: int, neutral: String = "Neutral") -> Array:
	if owner < 0:
		return [neutral, UiStyle.TEXT_DIM]
	if owner == me:
		return ["Yours", UiStyle.GOOD]
	var who := String(session.state.player(owner)["name"])
	if session.allied(owner, me):
		return ["Ally: " + who, UiStyle.GOOD]
	return ["Enemy: " + who, UiStyle.BAD]


static func _resources(amounts: Dictionary, data: GameData) -> String:
	var parts := []
	for res in data.resource_order:
		if int(amounts.get(res, 0)) > 0:
			parts.append("%d %s" % [int(amounts[res]), data.resources[res]["name"]])
	return ", ".join(parts)


static func _site_kind(kind: String) -> String:
	match kind:
		"trader": return "trader · artifacts & maps"
		"cobolt": return "neutral cobolt trading house"
		"dwelling": return "dwelling"
		"village": return "village · recruits once"
		"attribute": return "training ground"
		"boon": return "blessing"
		"lore": return "lore"
	return kind


## The first sentence (or two) of a flavour text, at most FLAVOR_CHARS long.
static func flavor_text(text: String) -> String:
	text = text.strip_edges()
	if text.length() <= FLAVOR_CHARS:
		return text
	var cut := text.substr(0, FLAVOR_CHARS)
	var dot := cut.rfind(". ")
	if dot > 40:
		return cut.substr(0, dot + 1)
	var sp := cut.rfind(" ")
	return cut.substr(0, sp if sp > 0 else FLAVOR_CHARS) + "…"
