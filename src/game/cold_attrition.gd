class_name ColdAttrition
extends RefCounted
## Cold attrition: at the start of each day, every living hero standing on a
## cold terrain (game_rules cold_attrition_terrains, the snowfield) loses a share
## of each stack whose creatures' faction counts that terrain as hostile
## (factions.json hostile_terrain). The share is game_rules cold_attrition_pct
## of the stack, rounded up, and a stack never drops below one creature. Town
## garrisons are not hero armies and never freeze; a hero inside a town is
## sheltered too. A hero whose summed modifiers carry ignore_hostile_terrain
## (the Forgewarm Harness at two pieces, Rime Shroud, Pathfinding) is spared.
##
## The rule is GameState.rules "cold_attrition": a campaign chapter may set it
## (chapter field cold_attrition); without it a campaign game plays with cold
## and a skirmish uses game_rules cold_attrition (off). Headless and
## deterministic: no randomness, heroes in id order, stacks in slot order.

const NEWS_PREFIX := "The cold takes its toll"


static func enabled(state: GameState, data: GameData) -> bool:
	if state.rules.has("cold_attrition"):
		return bool(state.rules["cold_attrition"])
	if not state.campaign.is_empty():
		return true
	return bool(data.rules.get("cold_attrition", false))


static func is_cold(terrain_id: String, data: GameData) -> bool:
	return (data.rules.get("cold_attrition_terrains", []) as Array).has(terrain_id)


## Creatures a stack of this size loses to one day of cold.
static func loss(count: int, data: GameData) -> int:
	if count <= 1:
		return 0
	var pct := float(data.rules.get("cold_attrition_pct", 0.0))
	return mini(count - 1, ceili(count * pct - 0.000001))


## Whether this stack's creatures suffer on this terrain.
static func stack_freezes(creature_id: String, terrain_id: String, data: GameData) -> bool:
	var fac := String(data.creature(creature_id).get("faction", ""))
	return (data.factions.get(fac, {}).get("hostile_terrain", []) as Array).has(terrain_id)


## Whether the hero is exposed where it stands: on cold terrain that is hostile
## to at least one of its stacks, outside a town and without protection.
static func exposed(h: Hero, state: GameState, data: GameData) -> bool:
	if not h.alive or h.army.is_empty():
		return false
	var terrain := state.map.terrain_at(h.pos)
	if not is_cold(terrain, data):
		return false
	if String(state.map.object_at(h.pos).get("type", "")) == "town":
		return false
	if HeroModifiers.whole(h.modifiers(data), "ignore_hostile_terrain") > 0:
		return false
	for s in h.army.slots:
		if not s.is_empty() and stack_freezes(String(s["creature"]), terrain, data):
			return true
	return false


## What a day of cold would take from this hero: [{slot, creature, lost}] in
## slot order (empty when the hero is safe). Used by apply() and by the UI.
static func preview(h: Hero, state: GameState, data: GameData) -> Array:
	var out := []
	if not exposed(h, state, data):
		return out
	var terrain := state.map.terrain_at(h.pos)
	for i in Army.MAX_SLOTS:
		var s: Dictionary = h.army.slots[i]
		if s.is_empty() or not stack_freezes(String(s["creature"]), terrain, data):
			continue
		var lost := loss(int(s["count"]), data)
		if lost > 0:
			out.append({"slot": i, "creature": String(s["creature"]), "lost": lost})
	return out


## Applies one day of cold to every exposed hero and reports it to the owners.
## Returns [{hero, losses}] for the heroes that lost creatures.
static func on_day(session: GameSession) -> Array:
	var st := session.state
	var data := session.data
	var report := []
	if st.game_over or not enabled(st, data):
		return report
	for h in session._all_heroes_sorted():
		var losses := preview(h, st, data)
		if losses.is_empty():
			continue
		var parts := []
		for e in losses:
			var slot: Dictionary = h.army.slots[int(e["slot"])]
			slot["count"] = int(slot["count"]) - int(e["lost"])
			parts.append("%d %s" % [int(e["lost"]), String(data.creature(String(e["creature"])).get("name", e["creature"]))])
		report.append({"hero": h.id, "losses": losses})
		if h.owner < 0 or h.owner >= st.players.size():
			continue
		var p := st.player(h.owner)
		if not p["defeated"]:
			session._add_news(p, "%s. %s's army loses %s on the %s." % [NEWS_PREFIX, h.name, ", ".join(parts),
				String(data.terrains.get(st.map.terrain_at(h.pos), {}).get("name", "snow")).to_lower()])
	return report
