class_name EncounterSystem
extends RefCounted
## Rules for adventure-map encounters (choice events defined in
## data/encounters.json). Headless: GameSession owns an instance and exposes
## encounter_options() / resolve_encounter() as commands.
##
## An encounter offers choices. A choice can be gated (requires), cost
## resources or movement, and either always succeed or roll a success check
## whose chance depends on the hero (class, faction, attributes, skills,
## persistent marks), the army (tags, roles, size), the encounter's terrain and
## the week. All rolls use the game's GameRng.

var data: GameData
var state: GameState


func _init(game_data: GameData, game_state: GameState) -> void:
	data = game_data
	state = game_state


## Atlas sprite of an encounter: its own "sprite" (art shared with another
## encounter or a landmark) or encounter_<id>.
static func sprite_id(encounter_id: String, game_data: GameData) -> String:
	var def: Dictionary = game_data.encounters.get(encounter_id, {})
	return String(def.get("sprite", "encounter_" + encounter_id))


func definition(obj: Dictionary) -> Dictionary:
	return data.encounters.get(String(obj.get("encounter", "")), {})


## Everything the encounter dialog needs: name, text and per-choice availability,
## costs and success chance (the chance is shown to the player before choosing).
func options(h: Hero, obj: Dictionary) -> Dictionary:
	var def := definition(obj)
	var choices := []
	var raw: Array = def.get("choices", [])
	for i in raw.size():
		var c: Dictionary = raw[i]
		var problems := unmet(h, obj, c)
		choices.append({
			"index": i,
			"text": c["text"],
			"available": problems.is_empty(),
			"reason": "; ".join(problems),
			"has_check": c.has("check"),
			"chance": success_chance(h, obj, c),
			"cost": c.get("cost", {}),
			"cost_text": cost_text(c.get("cost", {})),
			"leave": bool(c.get("leave", false)),
		})
	return {"id": obj.get("encounter", ""), "object_id": obj.get("id", ""), "name": def.get("name", "Encounter"),
		"sprite": sprite_id(String(obj.get("encounter", "")), data),
		"text": def.get("text", ""), "terrain": state.map.terrain_at(AdventureMap.object_pos(obj)), "choices": choices}


## Reasons a choice cannot be taken right now (empty = available).
func unmet(h: Hero, obj: Dictionary, choice: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var req: Dictionary = choice.get("requires", {})
	if not req.is_empty() and not condition_holds(req, h, obj):
		out.append("Requires " + condition_text(req))
	var bank: ResourceBank = state.player(h.owner)["resources"]
	var cost: Dictionary = choice.get("cost", {})
	for res in data.resource_order:
		if cost.has(res) and bank.get_amount(res) < int(cost[res]):
			out.append("Not enough %s" % data.resources[res]["name"])
	if cost.has("movement") and h.movement_left < int(cost["movement"]):
		out.append("Not enough movement left today")
	# Recruits need a free slot or a matching stack.
	for e in choice.get("success", {}).get("effects", []):
		if e["type"] == "recruit" and not _has_room(h, String(e["creature"])):
			out.append("No free army slot for %s" % data.creature(e["creature"])["name"])
		if e["type"] == "ascend" and h.army.ascendable_slots().is_empty():
			out.append("Every unit in the army is already at the top veteran level")
	return out


## Success probability in [0, 1]; 1.0 for choices without a check.
func success_chance(h: Hero, obj: Dictionary, choice: Dictionary) -> float:
	if not choice.has("check"):
		return 1.0
	var chk: Dictionary = choice["check"]
	var p := float(chk.get("chance", 0.5))
	var per_attr: Dictionary = chk.get("per_attr", {})
	for a in ["attack", "defense", "power", "knowledge"]:
		if per_attr.has(a):
			p += float(per_attr[a]) * _attr(h, a)
	var per_skill: Dictionary = chk.get("per_skill", {})
	for sk in _sorted_keys(per_skill):
		p += float(per_skill[sk]) * h.skill_level(sk)
	for m in chk.get("mods", []):
		if condition_holds(m["when"], h, obj):
			p += float(m["add"])
	return clampf(p, float(data.encounter_rules.get("chance_floor", 0.05)), float(data.encounter_rules.get("chance_cap", 0.95)))


## Applies a choice. Returns {ok, success, leave, text, lines[], battle, xp_gained, levels_gained}.
## battle is the id of an ambushing neutral army placed on the encounter tile.
func resolve(h: Hero, obj: Dictionary, choice_idx: int) -> Dictionary:
	var out := {"ok": false, "success": false, "leave": false, "text": "", "lines": [], "battle": "",
		"xp_gained": 0, "levels_gained": 0, "encounter": obj.get("encounter", ""), "name": definition(obj).get("name", ""),
		"sprite": sprite_id(String(obj.get("encounter", "")), data)}
	var choices: Array = definition(obj).get("choices", [])
	if choice_idx < 0 or choice_idx >= choices.size():
		return out
	var c: Dictionary = choices[choice_idx]
	if not unmet(h, obj, c).is_empty():
		return out
	out["ok"] = true
	if bool(c.get("leave", false)):
		out["leave"] = true
		return out
	# Pay.
	var cost: Dictionary = c.get("cost", {})
	var res_cost := {}
	for res in data.resource_order:
		if cost.has(res):
			res_cost[res] = int(cost[res])
	state.player(h.owner)["resources"].spend(res_cost)
	if cost.has("movement"):
		h.movement_left = maxi(0, h.movement_left - int(cost["movement"]))
	# Roll.
	var success := true
	if c.has("check"):
		success = state.rng.next_float() < success_chance(h, obj, c)
	out["success"] = success
	out["had_check"] = c.has("check")
	var outcome: Dictionary = c.get("success" if success else "failure", {})
	out["text"] = outcome.get("text", "")
	state.map.remove_object(obj["id"])
	for e in outcome.get("effects", []):
		_apply(e, h, obj, out)
	return out


# ------------------------------------------------------------ conditions --

func condition_holds(cond: Dictionary, h: Hero, obj: Dictionary) -> bool:
	if cond.has("class") and not cond["class"].has(h.class_id):
		return false
	if cond.has("not_class") and cond["not_class"].has(h.class_id):
		return false
	if cond.has("faction") and not cond["faction"].has(h.faction):
		return false
	for sk in cond.get("skill", {}):
		if h.skill_level(sk) < int(cond["skill"][sk]):
			return false
	for a in cond.get("attr", {}):
		if _attr(h, a) < int(cond["attr"][a]):
			return false
	if cond.has("army_tag") and not _army_has(h, "tags", String(cond["army_tag"])):
		return false
	if cond.has("army_role") and not _army_has(h, "role", String(cond["army_role"])):
		return false
	if cond.has("min_creatures") and h.army.total_creatures() < int(cond["min_creatures"]):
		return false
	if cond.has("terrain") and not cond["terrain"].has(state.map.terrain_at(AdventureMap.object_pos(obj))):
		return false
	if cond.has("mark") and not h.has_mark(String(cond["mark"])):
		return false
	if cond.has("no_mark") and h.has_mark(String(cond["no_mark"])):
		return false
	if cond.has("min_level") and h.level < int(cond["min_level"]):
		return false
	if cond.has("min_week") and state.week() < int(cond["min_week"]):
		return false
	if cond.has("any"):
		var any_ok := false
		for sub in cond["any"]:
			if condition_holds(sub, h, obj):
				any_ok = true
				break
		if not any_ok:
			return false
	return true


func condition_text(cond: Dictionary) -> String:
	var parts := []
	if cond.has("class"):
		parts.append(" or ".join(cond["class"].map(func(c): return data.hero_classes[c]["name"])))
	if cond.has("not_class"):
		parts.append("not " + " or ".join(cond["not_class"].map(func(c): return data.hero_classes[c]["name"])))
	if cond.has("faction"):
		parts.append(" or ".join(cond["faction"].map(func(f): return data.factions[f]["adjective"])) + " hero")
	for sk in _sorted_keys(cond.get("skill", {})):
		parts.append("%s %d" % [data.skills[sk]["name"], int(cond["skill"][sk])])
	for a in _sorted_keys(cond.get("attr", {})):
		parts.append("%s %d" % [String(a).capitalize(), int(cond["attr"][a])])
	if cond.has("army_tag"):
		parts.append("%s creatures in the army" % String(cond["army_tag"]))
	if cond.has("army_role"):
		parts.append("%s units in the army" % String(cond["army_role"]))
	if cond.has("min_creatures"):
		parts.append("an army of %d+" % int(cond["min_creatures"]))
	if cond.has("terrain"):
		parts.append(" or ".join(cond["terrain"].map(func(t): return data.terrains[t]["name"])))
	if cond.has("mark"):
		parts.append("renown: %s" % mark_name(String(cond["mark"])))
	if cond.has("no_mark"):
		parts.append("no %s" % mark_name(String(cond["no_mark"])))
	if cond.has("min_level"):
		parts.append("level %d" % int(cond["min_level"]))
	if cond.has("min_week"):
		parts.append("week %d" % int(cond["min_week"]))
	if cond.has("any"):
		parts.append(" or ".join(cond["any"].map(func(s): return condition_text(s))))
	return ", ".join(parts)


func mark_name(mark: String) -> String:
	return String(data.encounter_rules.get("marks", {}).get(mark, {}).get("name", mark.capitalize()))


func cost_text(cost: Dictionary) -> String:
	var parts := []
	for res in data.resource_order:
		if cost.has(res):
			parts.append("%d %s" % [int(cost[res]), data.resources[res]["name"]])
	if cost.has("movement"):
		parts.append("%d movement" % int(cost["movement"]))
	return ", ".join(parts)


# --------------------------------------------------------------- effects --

## Creature count for the current week (encounters grow as the map ages).
func scaled_count(e: Dictionary) -> int:
	return int(e["count"]) + int(e.get("per_week", 0)) * (state.week() - 1)


func _apply(e: Dictionary, h: Hero, obj: Dictionary, out: Dictionary) -> void:
	var bank: ResourceBank = state.player(h.owner)["resources"]
	var lines: Array = out["lines"]
	match String(e["type"]):
		"resources":
			for res in data.resource_order:
				if not e["resources"].has(res):
					continue
				var n := int(e["resources"][res])
				if n >= 0:
					bank.add(res, n)
					lines.append("+%d %s" % [n, data.resources[res]["name"]])
				else:
					var lost := mini(-n, bank.get_amount(res))
					bank.spend({res: lost})
					lines.append("-%d %s" % [lost, data.resources[res]["name"]])
		"xp":
			var amount := h.xp_with_bonus(int(e["amount"]), data)
			out["xp_gained"] += amount
			out["levels_gained"] += h.add_xp(amount, data)
			lines.append("+%d experience" % amount)
		"recruit":
			var cid := String(e["creature"])
			var n := scaled_count(e)
			var veteran_xp: int = Army.VETERAN_THRESHOLDS[2] if data.creature(cid).has("upgrade_of") else 0
			if h.army.add(cid, n, veteran_xp):
				lines.append("%d %s join your army" % [n, data.creature(cid)["name"]])
		"casualties":
			var lost := _casualties(h, float(e["fraction"]), String(e.get("role", "")))
			for line in lost:
				lines.append(line)
		"movement":
			var before := h.movement_left
			h.movement_left = maxi(0, h.movement_left + int(e["amount"]))
			lines.append("%+d movement today" % (h.movement_left - before))
		"skill_point":
			h.skill_points += int(e.get("amount", 1))
			lines.append("+%d skill point" % int(e.get("amount", 1)))
		"artifact":
			var aid := String(e["artifact"])
			if h.give_artifact(aid, data):
				lines.append("Found: %s" % data.artifacts[aid]["name"])
			else:
				lines.append("%s is left behind: the pack is full" % data.artifacts[aid]["name"])
		"boon":
			var days := int(e.get("days", 7))
			h.add_boon("encounter_" + String(out["encounter"]), String(out["name"]), state.day + days - 1, e["mods"])
			lines.append("%s for %d days" % [MapSites.describe_mods(e["mods"]), days])
		"mana":
			var before := h.mana
			h.restore_mana(int(e["amount"]), data)
			lines.append("+%d mana" % (h.mana - before))
		"veteran_xp":
			h.army.gain_veteran_xp(int(e["amount"]), data)
			lines.append("+%d veteran experience for every stack" % int(e["amount"]))
		"ascend":
			var slot := h.army.ascend_random(state.rng, data)
			if slot >= 0:
				var st: Dictionary = h.army.slots[slot]
				lines.append("%d %s rise to veteran level 5" % [int(st["count"]), String(Army.creature_stats(st, data)["name"])])
				out["ascended_slot"] = slot
		"mark":
			if h.add_mark(String(e["mark"])):
				lines.append("Renown gained: %s" % mark_name(String(e["mark"])))
		"reveal":
			var fog: FogOfWar = state.player(h.owner)["fog"]
			var n := fog.reveal(AdventureMap.object_pos(obj), int(e["radius"]))
			lines.append("%d tiles revealed" % n)
		"ambush":
			var stacks := []
			for s in e["stacks"]:
				stacks.append([String(s["creature"]), scaled_count(s)])
			var army := {"id": String(obj["id"]) + "_ambush", "type": "neutral_army", "pos": obj["pos"].duplicate(),
				"name": e.get("name", "Ambush"), "stacks": stacks}
			state.map.add_object(army)
			out["battle"] = army["id"]
			lines.append("%s attack!" % army["name"])


## Removes a fraction of every matching stack (rounded, at least one per
## affected stack) but never wipes out the hero's whole army.
func _casualties(h: Hero, fraction: float, role: String) -> Array:
	var lines := []
	var total := h.army.total_creatures()
	for i in Army.MAX_SLOTS:
		var s: Dictionary = h.army.slots[i]
		if s.is_empty():
			continue
		var c := data.creature(s["creature"])
		if role != "" and c["role"] != role:
			continue
		var count := int(s["count"])
		var lost := clampi(int(round(count * fraction)), 1, count)
		lost = mini(lost, total - 1)
		if lost <= 0:
			continue
		total -= lost
		h.army.set_survivors({i: count - lost})
		lines.append("-%d %s" % [lost, c["name"]])
	return lines


# --------------------------------------------------------------- helpers --

func _has_room(h: Hero, creature_id: String) -> bool:
	for s in h.army.slots:
		if s.is_empty() or s["creature"] == creature_id:
			return true
	return false


func _army_has(h: Hero, field: String, value: String) -> bool:
	for s in h.army.slots:
		if s.is_empty():
			continue
		var c := data.creature(s["creature"])
		if field == "tags" and c.get("tags", []).has(value):
			return true
		if field == "role" and c.get("role", "") == value:
			return true
	return false


static func _attr(h: Hero, a: String) -> int:
	match a:
		"attack": return h.attack
		"defense": return h.defense
		"power": return h.power
		"knowledge": return h.knowledge
	return 0


static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k
