class_name RandomMapTemplate
extends RefCounted
## Builds a MapGenerator template from random-map options, so the new-game
## screen can offer maps of any size and player count without a hand-written
## template for each. The options live in the template name, which keeps the
## usual "gen:<template>:<seed>" map id working everywhere (loading, saves,
## replays):
##
##   random_<size>_<players>p_<monsters>_<treasure>[_<family>]
##   e.g. random_l_4p_normal_rich or random_m_2p_normal_normal_diagonal
##
## The sizes, strengths, amounts and layout families are data (random_maps in
## map_templates.json). Without a family the seed picks one of those that fit
## the player count ("mixed"). LayoutFamilies draws the family's zone graph;
## this file sizes the map, jitters the anchors, rolls pass widths and neutral
## towns and turns the graph into one of eight orientations, all from the seed.
## The map side follows from the player count and the size's tiles per player.
## With an even player count the map is point-symmetric (each player mirrors
## the one opposite); with an odd count the zones still share content groups
## and distances.

const PREFIX := "random_"
const MIXED := "mixed"


static func is_random(template_name: String) -> bool:
	return template_name.begins_with(PREFIX)


## The random_maps settings of map_templates.json ({} if absent).
static func settings(cfg: Dictionary) -> Dictionary:
	return cfg.get("random_maps", {})


## The template name for a set of options. An empty family or "mixed" lets the
## seed choose the family.
static func make_name(size: String, players: int, monsters: String, treasure: String, family: String = "") -> String:
	var tname := "%s%s_%dp_%s_%s" % [PREFIX, size, players, monsters, treasure]
	return tname if family == "" or family == MIXED else "%s_%s" % [tname, family]


## {size, players, monsters, treasure} (plus family when the name names one)
## from a template name, or {} if the name is not a valid random-map name
## under these settings.
static func parse(cfg: Dictionary, template_name: String) -> Dictionary:
	if not is_random(template_name):
		return {}
	var rm := settings(cfg)
	var parts := template_name.substr(PREFIX.length()).split("_")
	if rm.is_empty() or parts.size() < 4 or parts.size() > 5 or not parts[1].ends_with("p"):
		return {}
	var n_text := parts[1].trim_suffix("p")
	if not n_text.is_valid_int():
		return {}
	var out := {"size": parts[0], "players": int(n_text), "monsters": parts[2], "treasure": parts[3]}
	if not rm.get("sizes", {}).has(out["size"]) or not rm.get("monsters", {}).has(out["monsters"]) \
			or not rm.get("treasure", {}).has(out["treasure"]):
		return {}
	if out["players"] < min_players(cfg) or out["players"] > max_players(cfg, out["size"]):
		return {}
	if parts.size() == 5:
		if not LayoutFamilies.supports(cfg, parts[4], out["players"]):
			return {}
		out["family"] = parts[4]
	return out


static func min_players(cfg: Dictionary) -> int:
	return int(settings(cfg).get("min_players", 2))


static func max_players(cfg: Dictionary, size: String) -> int:
	return int(settings(cfg).get("sizes", {}).get(size, {}).get("max_players", 0))


## Option keys of a settings table ("sizes", "monsters", "treasure" or
## "families") in data order.
static func option_keys(cfg: Dictionary, table: String) -> Array:
	return (settings(cfg).get(table, {}) as Dictionary).keys()


## Optional rings of a size, in the order they are laid out (ring families).
static func rings(cfg: Dictionary, size: String) -> Array:
	return settings(cfg).get("sizes", {}).get(size, {}).get("rings", [])


## How many zones a ring-family random map of this size and player count has.
static func zone_count(cfg: Dictionary, size: String, players: int) -> int:
	return 1 + players * (2 + rings(cfg, size).size())


## Map side (the maps are square) for a size and player count: the size's
## tiles per player times the players.
static func side(cfg: Dictionary, size: String, players: int) -> int:
	var rm := settings(cfg)
	var sz: Dictionary = rm["sizes"][size]
	var s := int(round(sqrt(float(players) * float(sz["player_tiles"]))))
	return clampi(s, int(rm.get("min_side", 24)), int(rm.get("max_side", 128)))


## The family a random map name plays with this seed ("" if the name is bad).
static func family_for(cfg: Dictionary, template_name: String, seed_number: int) -> String:
	var o := parse(cfg, template_name)
	if o.is_empty():
		return ""
	if o.has("family"):
		return String(o["family"])
	return LayoutFamilies.pick(cfg, int(o["players"]), GameRng.new(GameRng.mix(seed_number, 0xFA417)))


## The generator template for a random-map name; {} if the name is not valid.
## The seed picks the family (unless named), turns and mirrors the layout,
## jitters the zones and rolls pass widths and neutral towns.
## `redraw` > 0 draws another variant of the same family (MapGenerator uses it
## when a layout keeps failing validation).
static func build(cfg: Dictionary, template_name: String, seed_number: int, redraw: int = 0) -> Dictionary:
	var o := parse(cfg, template_name)
	if o.is_empty():
		return {}
	var rm := settings(cfg)
	var n := int(o["players"])
	var size := String(o["size"])
	var sz: Dictionary = rm["sizes"][size]
	var fam_id := family_for(cfg, template_name, seed_number)
	var fam := LayoutFamilies.family(cfg, fam_id)
	var s := side(cfg, size, n)
	var rng := GameRng.new(GameRng.mix(seed_number, 0x5EED) if redraw == 0 else GameRng.mix(GameRng.mix(seed_number, 0x5EED), redraw))
	var graph := LayoutFamilies.build_graph(cfg, fam_id, n, sz.get("rings", []), rng)
	if graph.is_empty():
		return {}
	var zones: Array = graph["zones"]
	var conns: Array = graph["connections"]
	var symmetric: bool = graph["symmetric"]
	# Crowded rings of many players tolerate less jitter before linked zones lose their shared border.
	LayoutFamilies.jitter_anchors(zones, float(rm.get("anchor_jitter", 0.03)) * minf(1.0, 3.0 / n), rng)
	var pw: Array = rm.get("pass_width", [2, 4])
	LayoutFamilies.roll_widths(conns, int(pw[0]), int(pw[1]), rng)
	var towns := LayoutFamilies.assign_towns(cfg, zones, conns, n, rng)
	var orientation := rng.next_int(0, LayoutFamilies.ORIENTATIONS - 1)
	LayoutFamilies.orient(zones, orientation)

	var players := []
	var factions: Array = rm.get("factions", ["concord", "ashen"])
	var colors: Array = rm.get("colors", [])
	for i in n:
		var p := {"faction": String(factions[i % factions.size()]), "is_human": i == 0}
		if i < colors.size():
			p["color"] = String(colors[i])
		players.append(p)

	var monsters: Dictionary = rm["monsters"][o["monsters"]]
	var treasure: Dictionary = rm["treasure"][o["treasure"]]
	var fam_name := String(fam.get("name", fam_id))
	return {
		"name": "%s %s, %d players" % [String(sz.get("name", size)), fam_name.to_lower(), n],
		"description": "A random %s map for %d players. %s" % [fam_name.to_lower(), n, String(fam.get("description", ""))],
		"width": s, "height": s, "symmetry": "rotate180" if symmetric else "none",
		"jitter": float(rm.get("zone_jitter", 0.02)), "warp": float(fam.get("warp", rm.get("warp", 3.0))),
		"walls": fam.get("walls", {}),
		"guard_scale": float(monsters.get("scale", 1.0)), "treasure_scale": float(treasure.get("scale", 1.0)),
		"guard_pockets": String(rm.get("guard_pockets", "open")),
		"players": players, "zones": zones, "connections": conns,
		"layout_family": fam_id, "orientation": orientation, "neutral_town_groups": towns,
		"random": o,
	}


## Problems in the random_maps settings. Called from MapGenerator.validate_templates.
static func validate(cfg: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rm := settings(cfg)
	if rm.is_empty():
		return errors
	for key in ["sizes", "monsters", "treasure", "factions"]:
		if not rm.has(key) or rm[key].is_empty():
			errors.append("random_maps: missing %s" % key)
	if not String(rm.get("guard_pockets", "open")) in MapGenerator.GUARD_POCKETS:
		errors.append("random_maps: guard_pockets must be one of %s" % ", ".join(MapGenerator.GUARD_POCKETS))
	if not errors.is_empty():
		return errors
	var lo := min_players(cfg)
	if lo < 2:
		errors.append("random_maps: min_players must be at least 2")
	for size in rm["sizes"]:
		var sz: Dictionary = rm["sizes"][size]
		if String(size).contains("_"):
			errors.append("random_maps: size id %s must not contain _" % size)
		if int(sz.get("max_players", 0)) < lo:
			errors.append("random_maps size %s: max_players below min_players" % size)
		if int(sz.get("player_tiles", 0)) < 600:
			errors.append("random_maps size %s: player_tiles must be at least 600" % size)
		for r in sz.get("rings", []):
			if not ["wild", "approach", "outer"].has(r):
				errors.append("random_maps size %s: unknown ring %s" % [size, r])
		if (sz.get("rings", []) as Array).has("outer") and not (sz.get("rings", []) as Array).has("wild"):
			errors.append("random_maps size %s: the outer ring needs the wild ring" % size)
	for table in ["monsters", "treasure"]:
		for k in rm[table]:
			if String(k).contains("_"):
				errors.append("random_maps %s id %s must not contain _" % [table, k])
			if float(rm[table][k].get("scale", 0.0)) <= 0.0:
				errors.append("random_maps %s %s: scale must be > 0" % [table, k])
	for f in rm["factions"]:
		if not cfg.get("factions", {}).has(f):
			errors.append("random_maps: faction %s has no generator settings" % f)
	errors.append_array(LayoutFamilies.validate(cfg))
	for profile in ["start", "flank", "wild", "center", "valley"]:
		if not cfg.get("profiles", {}).has(profile):
			errors.append("random_maps need the %s profile" % profile)
	return errors
