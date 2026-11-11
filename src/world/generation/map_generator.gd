class_name MapGenerator
extends RefCounted
## Seeded, template-driven adventure-map generator. Output is a map definition
## dictionary in exactly the format of data/maps/*.json, so the rest of the game
## cannot tell a generated map from a hand-made one.
##
## Pipeline (see data/map_templates.json for the knobs):
##   zones (ZoneLayout) -> base terrain -> towns/anchors -> terrain painter
##   (biome patches, rivers, lakes, landmarks; TerrainPainter) -> roads -> obstacles -> gate guards on the passes -> zone content
##   (mines, piles, guarded treasure, wandering armies) -> armour drops -> rare
##   sites -> guarded hoards and scattered piles (density fill, scaled by zone
##   size) -> heroes -> scenery, decorations and ground variants (TerrainPainter.dress).
## Nothing is placed uniformly at random: content comes from per-zone profiles,
## is positioned in movement-cost distance bands from the zone's town, and zones
## that share a `group` get identical rolled content so starts are fair. Every
## result is checked by MapValidator; a failed attempt is retried with a
## derived seed, so the same (template, seed) always yields the same map.
##
## Generated maps are addressed as "gen:<template>:<seed>". GameData.load_map
## regenerates them on demand. <template> is a template of map_templates.json
## or a random-map name ("random_<size>_<players>p_<monsters>_<treasure>", see
## RandomMapTemplate), which builds the template from the options and seed.
## A template may set guard_scale (every neutral army's strength) and
## treasure_scale (how many hoards and scattered piles a zone gets).
## guard_pockets says how guarded treasure is laid out: "sealed" (the default:
## rock on every side but the guard's) or "open" (the prize stays in the open
## with its guard on a neighbouring tile; the guard rule in GameSession.claim_guard
## keeps it out of reach until that guard is beaten). Random maps use "open".

const ID_PREFIX := "gen:"
const VERSION := 13  # 13: the equipment artwork library adds 112 artifacts to the pools; 12: two ascension encounters (ember_crucible, barrow_of_the_last_rank) join the high-risk pool; 11: twice the encounters from a pool of 41, new site kinds (watchtower, drill, mana well), 3-5 extra sites; 10: every named template uses open guard pockets, town names are unique per map; 9: open guarded prizes (guard_pockets "open", random maps); 8: scenery, landmarks and ground variants
## Salt for the terrain painter's own random stream.
const PAINTER_SALT := 0x7E22A1
const MAX_ATTEMPTS := 10
## Random maps redraw their template after this many failed attempts.
const RANDOM_REDRAW_EVERY := 4
const POCKET_TRIES := 14
const GUARD_POCKETS := ["sealed", "open"]
## Mirrored zones place matching items within this many movement points of each other.
const MATCH_TOLERANCE := 120
const BASIC_RESOURCES := ["gold", "wood", "ore"]
const ROAD_PATH_COST := 40
const ROLE_NOUNS := {"infantry": "warband", "ranged": "skirmishers", "cavalry": "pack", "flyer": "flight",
	"support": "coven", "heavy": "brood"}

var data: GameData
var config: Dictionary
var template: Dictionary
var template_id: String
var seed_value: int
var last_errors: Array[String] = []
var attempts_used: int = 0
## Why earlier attempts were rejected (diagnostics for tools and tests).
var rejected: Array = []

# Per-attempt working state.
var rng: GameRng
var layout: ZoneLayout
var w: int
var h: int
var terrain := PackedStringArray()
var road := PackedByteArray()
var reserved := PackedByteArray()   # keep clear of obstacles and objects
var occupant := PackedInt32Array()  # tile -> index into objects, -1 if free
var prize_block := PackedByteArray()  # open guarded prizes: no path through them (guard_pockets "open")
var objects: Array = []
var heroes: Array = []
var anchors := PackedInt32Array()   # zone -> anchor tile
var zone_dist: Array = []           # zone -> PackedInt32Array movement cost from anchor
var _counters: Dictionary = {}
var _plans: Dictionary = {}
var _attempt_seed: int = 0
var _landmarks: Array = []
var player_factions: Array = []   # overrides the template's player factions; [] keeps them
var _template_factions: Array[String] = []   # the template's own factions, when overridden


## "gen:<template>:<seed>", plus ":<faction>,<faction>..." when the players'
## factions replace the template's (their home zones then get native ground).
static func make_id(template_name: String, seed_number: int, factions: Array = []) -> String:
	var id := "%s%s:%d" % [ID_PREFIX, template_name, seed_number]
	return id if factions.is_empty() else "%s:%s" % [id, ",".join(PackedStringArray(factions))]


static func is_generated_id(map_id: String) -> bool:
	return map_id.begins_with(ID_PREFIX)


## Returns {template, seed, factions} or {} if the id is not a generated-map id.
## `factions` is empty unless the id names the players' factions.
static func parse_id(map_id: String) -> Dictionary:
	if not is_generated_id(map_id):
		return {}
	var parts := map_id.substr(ID_PREFIX.length()).split(":")
	if parts.size() < 2 or parts.size() > 3 or not parts[1].is_valid_int():
		return {}
	var factions: Array[String] = []
	if parts.size() == 3:
		for f in parts[2].split(","):
			if f == "":
				return {}
			factions.append(f)
	return {"template": parts[0], "seed": int(parts[1]), "factions": factions}


static func generate_from_id(game_data: GameData, map_id: String) -> Dictionary:
	var p := parse_id(map_id)
	if p.is_empty():
		push_error("MapGenerator: bad generated map id %s" % map_id)
		return {}
	return generate(game_data, p["template"], p["seed"], p["factions"])


## `factions` (by player index) replaces the template's player factions, so each
## home zone is painted with its player's native terrain and gets its rare mine.
static func generate(game_data: GameData, template_name: String, seed_number: int, factions: Array = []) -> Dictionary:
	var g := MapGenerator.new(game_data)
	return g.run(template_name, seed_number, factions)


func _init(game_data: GameData) -> void:
	data = game_data
	config = data.map_templates


func run(template_name: String, seed_number: int, factions: Array = []) -> Dictionary:
	template_id = template_name
	seed_value = seed_number
	template = find_template(config, template_name, seed_number).duplicate(true)
	if template.is_empty():
		push_error("MapGenerator: unknown template %s" % template_name)
		return {}
	if not factions.is_empty():
		if not can_use_factions(data, template, factions):
			push_error("MapGenerator: factions %s do not fit template %s" % [factions, template_name])
			return {}
		player_factions = factions.duplicate()
		_override_factions()
	var base := GameRng.mix(seed_number, _stable_hash(template_name))
	var def := {}
	for attempt in MAX_ATTEMPTS:
		attempts_used = attempt + 1
		# A random map whose layout keeps failing redraws its template (other
		# anchors, widths and orientation) from a derived seed; still deterministic.
		if attempt > 0 and attempt % RANDOM_REDRAW_EVERY == 0 and RandomMapTemplate.is_random(template_name):
			template = RandomMapTemplate.build(config, template_name, seed_number, attempt / RANDOM_REDRAW_EVERY).duplicate(true)
			_override_factions()
		_attempt_seed = GameRng.mix(base, attempt)
		rng = GameRng.new(_attempt_seed)
		def = _attempt()
		if def.has("_errors"):
			last_errors.assign(def["_errors"])
			rejected.append(last_errors)
			continue
		# Round-trip through JSON so a generated definition is indistinguishable
		# from one loaded from data/maps (numbers become floats, as on load).
		def = JSON.parse_string(JSON.stringify(def))
		last_errors = MapValidator.validate(def, data)
		if last_errors.is_empty():
			return def
		rejected.append(last_errors)
	push_error("MapGenerator: %s seed %d failed after %d attempts: %s" % [template_name, seed_number, MAX_ATTEMPTS, ", ".join(last_errors)])
	return def if not def.has("_errors") else {}


## True if `factions` has one generator-ready faction per template player.
static func can_use_factions(game_data: GameData, tpl: Dictionary, factions: Array) -> bool:
	if factions.size() != (tpl.get("players", []) as Array).size():
		return false
	for f in factions:
		if not game_data.town_types.has(String(f)) or bool(game_data.factions.get(String(f), {"neutral": true}).get("neutral", false)):
			return false
	return true


func _override_factions() -> void:
	_template_factions.clear()
	for i in player_factions.size():
		_template_factions.append(String(template["players"][i]["faction"]))
		template["players"][i]["faction"] = String(player_factions[i])


## Starting-hero settings for a player's faction. A faction without its own
## settings borrows the template's; GameSetup.apply then gives the player a
## hero of the chosen faction.
func _hero_settings(player: int, faction: String) -> Dictionary:
	var all: Dictionary = config["factions"]
	if all.has(faction) or player >= _template_factions.size():
		return all[faction]
	return all[_template_factions[player]]


## The template named `template_name`: one from map_templates.json, or a random
## map built from its name and the seed; {} if there is none.
static func find_template(cfg: Dictionary, template_name: String, seed_number: int) -> Dictionary:
	if cfg.get("templates", {}).has(template_name):
		return cfg["templates"][template_name]
	if RandomMapTemplate.is_random(template_name):
		return RandomMapTemplate.build(cfg, template_name, seed_number, 0)
	return {}


## True if `template_name` names a template the generator can build.
static func has_template(cfg: Dictionary, template_name: String) -> bool:
	return cfg.get("templates", {}).has(template_name) or RandomMapTemplate.parse(cfg, template_name).size() > 0


## FNV-1a over UTF-8 bytes: stable across platforms and engine versions.
static func _stable_hash(s: String) -> int:
	var hv := 0x811C9DC5
	for b in s.to_utf8_buffer():
		hv = ((hv ^ b) * 0x01000193) & 0xFFFFFFFF
	return hv


# --------------------------------------------------------------- attempt --

func _attempt() -> Dictionary:
	w = int(template["width"])
	h = int(template["height"])
	objects = []
	heroes = []
	_counters = {}
	zone_dist = []
	road = PackedByteArray()
	road.resize(w * h)
	reserved = PackedByteArray()
	reserved.resize(w * h)
	occupant = PackedInt32Array()
	occupant.resize(w * h)
	occupant.fill(-1)
	prize_block = PackedByteArray()
	prize_block.resize(w * h)
	layout = ZoneLayout.new()
	if not layout.build(template, rng):
		return {"_errors": layout.errors}
	_plans = _roll_group_plans()
	_paint_base_terrain(_plans)
	_place_anchors()
	_paint_terrain()
	_lay_roads()
	_place_obstacles()
	_place_gate_guards()
	_compute_zone_distances()
	_place_zone_content(_plans)
	_place_armor_drops()
	_place_sites()
	_place_hoards()
	_place_scatter()
	_place_heroes()
	_place_trader()
	_place_cobolts()
	_apply_neutral_habitats()
	return _definition()


func _zones() -> Array:
	return template["zones"]


func _profile(z: int) -> Dictionary:
	return config["profiles"][_zones()[z]["profile"]]


## The zone's town: "owner", "neutral" or "none". Random-map zones may
## override their profile's town and garrison (LayoutFamilies.assign_towns).
func _zone_town(z: int) -> String:
	var prof := _profile(z)
	if String(prof.get("town", "none")) == "owner":
		return "owner"
	return String(_zones()[z].get("town", prof.get("town", "none")))


func _zone_garrison(z: int) -> String:
	return String(_zones()[z].get("garrison", _profile(z).get("garrison", "none")))


func _player_faction(z: int) -> String:
	var zone: Dictionary = _zones()[z]
	if not zone.has("player"):
		return ""
	return String(template["players"][int(zone["player"])]["faction"])


func _passable(i: int) -> bool:
	return road[i] == 1 or bool(data.terrain(terrain[i]).get("passable", false))


func _move_cost(i: int) -> int:
	if road[i] == 1:
		return int(data.road["move_cost"])
	return int(data.terrain(terrain[i]).get("move_cost", 0))


func _next_id(prefix: String) -> String:
	_counters[prefix] = int(_counters.get(prefix, 0)) + 1
	return "%s_%d" % [prefix, _counters[prefix]]


# ---------------------------------------------------------------- planning --

## Rolls the content of each zone group once. All zones of a group receive the
## same plan, which is what makes mirrored starts fair.
func _roll_group_plans() -> Dictionary:
	var plans := {}
	var guard_levels: Dictionary = config["guard_levels"]
	var used_terrain := {}
	var used_encounters := {}
	for z in _zones().size():
		var group := String(_zones()[z].get("group", _zones()[z]["id"]))
		if plans.has(group):
			continue
		var prof := _profile(z)
		var plan := {"terrain": "", "items": [], "town_faction": ""}
		if prof["terrain"] is Array:
			# Prefer a base terrain no other group uses yet, so zones look distinct.
			var opts: Array = (prof["terrain"] as Array).filter(func(t): return not used_terrain.has(t))
			if opts.is_empty():
				opts = prof["terrain"]
			plan["terrain"] = String(opts[rng.next_int(0, opts.size() - 1)])
			used_terrain[plan["terrain"]] = true
		elif _zones()[z].has("player"):
			for t in data.factions.get(_player_faction(z), {}).get("native_terrain", []):
				used_terrain[t] = true
		var playable := _playable_factions()
		plan["town_faction"] = playable[rng.next_int(0, playable.size() - 1)]
		var terrain_hint := String(plan["terrain"]) if plan["terrain"] != "" else "grass"
		var gv_town := int(guard_levels[_zone_garrison(z)]) if _zone_town(z) == "neutral" else 0
		plan["garrison"] = _roll_army(gv_town, terrain_hint) if gv_town > 0 else {}
		for m in prof.get("mines", []):
			var res := String(m["resource"])
			if res == "rare":
				res = _rare_resources()[rng.next_int(0, _rare_resources().size() - 1)]
			var item := {"kind": "mine", "resource": res, "band": m["band"], "guard": {}}
			var gv := int(guard_levels[m.get("guard", "none")])
			if gv > 0:
				item["guard"] = _roll_army(gv, terrain_hint)
			plan["items"].append(item)
		for t in prof.get("treasures", []):
			var as_gold := rng.chance(0.5)
			var res := "gold" if as_gold else _rare_resources()[rng.next_int(0, _rare_resources().size() - 1)]
			var amt := _roll_amount(config["treasure_amounts"]["gold" if as_gold else "rare"])
			plan["items"].append({"kind": "treasure", "resource": res, "amount": amt, "band": t["band"],
				"guard": _roll_army(int(guard_levels[t["guard"]]), terrain_hint)})
		for p in prof.get("piles", []):
			var res := String(p["resource"])
			var key := res
			if res == "rare":
				res = _rare_resources()[rng.next_int(0, _rare_resources().size() - 1)]
			plan["items"].append({"kind": "pile", "resource": res, "amount": _roll_amount(config["pile_amounts"][key]), "band": p["band"]})
		for e in prof.get("encounters", []):
			var eid := _pick_encounter(String(e["risk"]), used_encounters)
			if eid != "":
				plan["items"].append({"kind": "encounter", "encounter": eid, "band": e["band"]})
		for wd in prof.get("wanderers", []):
			plan["items"].append({"kind": "wanderer", "band": wd["band"], "guard": _roll_army(int(guard_levels[wd["guard"]]), terrain_hint)})
		plans[group] = plan
	return plans


## An encounter of the given risk tier not used elsewhere on the map if possible.
func _pick_encounter(risk: String, used: Dictionary) -> String:
	var pool: Array = config.get("encounter_risk", {}).get(risk, []).filter(func(e): return data.encounters.has(e))
	var fresh: Array = pool.filter(func(e): return not used.has(e))
	if fresh.is_empty():
		fresh = pool
	if fresh.is_empty():
		return ""
	var eid: String = fresh[rng.next_int(0, fresh.size() - 1)]
	used[eid] = true
	return eid


func _roll_amount(spec: Array) -> int:
	var lo := int(spec[0])
	var hi := int(spec[1])
	var step := maxi(1, int(spec[2]))
	return lo + step * rng.next_int(0, (hi - lo) / step)


func _playable_factions() -> Array[String]:
	var out: Array[String] = []
	for fid in data.factions:
		if not bool(data.factions[fid].get("neutral", false)) and data.town_types.has(fid):
			out.append(String(fid))
	return out


func _rare_resources() -> Array[String]:
	var out: Array[String] = []
	for r in data.resource_order:
		if not BASIC_RESOURCES.has(r):
			out.append(String(r))
	return out


## The non-basic resource a faction's creatures need most.
func faction_rare(faction: String) -> String:
	var need := {}
	for cid in data.creatures:
		var c: Dictionary = data.creatures[cid]
		if c["faction"] != faction:
			continue
		for res in c["cost"]:
			if not BASIC_RESOURCES.has(res):
				need[res] = int(need.get(res, 0)) + int(c["cost"][res])
	var best := ""
	for res in _rare_resources():
		if need.has(res) and (best == "" or int(need[res]) > int(need[best])):
			best = res
	return best if best != "" else _rare_resources()[0]


static func creature_value(c: Dictionary) -> int:
	var v := 0
	for res in c.get("cost", {}):
		v += int(c["cost"][res]) if res == "gold" else int(c["cost"][res]) * 250
	return maxi(1, v)


## Builds a neutral army worth about `value` gold. Prefers higher tiers and
## creatures at home on the given terrain; always at least a handful of units.
func _roll_army(value: int, terrain_id: String, min_tier: int = 1, habitat: bool = false) -> Dictionary:
	if not habitat:
		value = maxi(1, int(round(value * float(template.get("guard_scale", 1.0)) / 50.0)) * 50)
	var ids: Array = data.creatures.keys()
	ids.sort()
	var cands: Array = []
	var weights: Array = []
	for cid in ids:
		var c: Dictionary = data.creatures[cid]
		if c["faction"] == "cobolts":
			continue
		if int(c["tier"]) < min_tier or creature_value(c) * 5 > value:
			continue
		var wgt := pow(float(c["tier"]), 1.3)
		var fac: Dictionary = data.factions.get(c["faction"], {})
		if c.get("terrain", {}).has(terrain_id) or fac.get("native_terrain", []).has(terrain_id):
			wgt *= 3.0
		if bool(fac.get("neutral", false)):
			wgt *= 1.5
		cands.append(cid)
		weights.append(wgt)
	if cands.is_empty():
		var cheapest := ""
		for cid in ids:
			if data.creatures[cid]["faction"] == "cobolts" or int(data.creatures[cid]["tier"]) < min_tier:
				continue
			if cheapest == "" or creature_value(data.creatures[cid]) < creature_value(data.creatures[cheapest]):
				cheapest = cid
		cands.append(cheapest)
		weights.append(1.0)
	if habitat and rng.chance(float(config.get("neutral_habitats", {}).get("native_chance", 0.85))):
		var local: Array = []
		var local_weights: Array = []
		for i in cands.size():
			if native_to(data, String(cands[i]), terrain_id):
				local.append(cands[i])
				local_weights.append(weights[i])
		if not local.is_empty():
			cands = local
			weights = local_weights
	var main: String = cands[rng.weighted_index(weights)]
	var stacks: Array = []
	var share := 1.0
	if value >= 3000 and cands.size() > 1 and rng.chance(0.5):
		var i2 := cands.find(main)
		var w2 := weights.duplicate()
		w2[i2] = 0.0
		var second: String = cands[rng.weighted_index(w2)]
		share = 0.65
		stacks.append([second, maxi(1, int(round(value * 0.35 / creature_value(data.creatures[second]))))])
	stacks.push_front([main, maxi(1, int(round(value * share / creature_value(data.creatures[main]))))])
	var mc: Dictionary = data.creatures[main]
	return {"name": "%s %s" % [mc["name"], ROLE_NOUNS.get(mc["role"], "band")], "stacks": stacks, "value": value}


## Habitat means faction-native terrain or a positive creature terrain affinity.
## Negative combat modifiers alone do not make a creature native.
static func native_to(game_data: GameData, creature_id: String, terrain_id: String) -> bool:
	var c: Dictionary = game_data.creatures[creature_id]
	if game_data.factions.get(c["faction"], {}).get("native_terrain", []).has(terrain_id):
		return true
	for amount in c.get("terrain", {}).get(terrain_id, {}).values():
		if float(amount) > 0.0:
			return true
	return false


## Roll ecology only after placement: the tile's actual biome, rather than a
## zone's early terrain hint, determines its inhabitants. Isolated streams keep
## this pass from moving roads, treasure or heroes. Equivalent mirrored guards
## on the same terrain receive the same composition and keep their value budget.
func _apply_neutral_habitats() -> void:
	var main_rng := rng
	var armies := {}
	for o in objects:
		if MapCobolts.is_post(o, data):
			continue
		var field := "stacks" if o["type"] == "neutral_army" else "guard"
		if not o.has(field) or (o[field] as Array).is_empty():
			continue
		var p: Array = o["pos"]
		var tile := int(p[1]) * w + int(p[0])
		var biome := String(data.terrain(terrain[tile]).get("combat_terrain", terrain[tile]))
		var budget := int(o.get("value", 0))
		if budget <= 0:
			for stack in o[field]:
				budget += creature_value(data.creatures[String(stack[0])]) * int(stack[1])
		var key := "%s:%d:%s" % [biome, budget, JSON.stringify(o[field])]
		if not armies.has(key):
			rng = GameRng.new(GameRng.mix(_attempt_seed, _stable_hash("habitat:" + key)))
			armies[key] = _roll_army(budget, biome, 1, true)
		var army: Dictionary = armies[key]
		o[field] = army["stacks"].duplicate(true)
		if o["type"] == "neutral_army":
			o["name"] = army["name"]
	rng = main_rng


# ----------------------------------------------------------------- terrain --

func _paint_base_terrain(plans: Dictionary) -> void:
	terrain.resize(w * h)
	for i in w * h:
		var z := layout.zone_of[i]
		if layout.wall[i] != 0:
			terrain[i] = "water" if layout.wall_kind[i] == ZoneLayout.WALL_WATER else "mountain"
			continue
		terrain[i] = _base_terrain(z)


func _base_terrain(z: int) -> String:
	var t := String(_plans[String(_zones()[z].get("group", _zones()[z]["id"]))]["terrain"])
	if t != "":
		return t
	var native: Array = data.factions.get(_player_faction(z), {}).get("native_terrain", [])
	return String(native[0]) if not native.is_empty() else "grass"


## Clearance = steps to the nearest wall or map edge.
func _clearance() -> PackedInt32Array:
	var cost := PackedInt32Array()
	cost.resize(w * h)
	cost.fill(1)
	var sources := PackedInt32Array()
	for i in w * h:
		var p := layout.pos(i)
		if layout.wall[i] != 0 or p.x == 0 or p.y == 0 or p.x == w - 1 or p.y == h - 1:
			sources.append(i)
	return GridSearch.distances(w, h, cost, sources)


func _place_anchors() -> void:
	var clear := _clearance()
	anchors.resize(_zones().size())
	for z in _zones().size():
		var tiles := layout.open_tiles(z)
		var best := -1
		var best_score := INF
		for i in tiles:
			if layout.gates.any(func(g): return (g["tiles"] as PackedInt32Array).has(i)):
				continue
			var c := clear[i]
			# Prefer roomy tiles near the zone seed.
			var score := Vector2(layout.pos(i)).distance_to(layout.seeds[z]) + maxf(0.0, 3.0 - c) * 6.0
			if score < best_score:
				best_score = score
				best = i
		anchors[z] = best
		var p := layout.pos(best)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := p + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
					reserved[layout.idx(q)] = 1
	for g in layout.gates:
		for t in g["tiles"]:
			reserved[t] = 1
			# Keep the tiles right in front of each pass clear too.
			for n in GridSearch.neighbors4(w, h, t):
				if layout.wall[n] == 0:
					reserved[n] = 1


## Biome patches, rivers and lakes (data/terrain_painting.json). Runs before
## roads and objects, so roads route around lakes and nothing sits on water.
func _paint_terrain() -> void:
	var info: Array = []
	for z in _zones().size():
		var zd: Dictionary = _zones()[z]
		var prof := _profile(z)
		info.append({"profile": String(zd["profile"]), "group": String(zd.get("group", zd["id"])), "biome": _base_terrain(z),
			"patches": prof.get("patches", []), "river": bool(prof.get("river", false))})
		if zd.has("player"):
			info[z]["player"] = int(zd["player"])
	var painter := TerrainPainter.new(data, GameRng.new(GameRng.mix(_attempt_seed, PAINTER_SALT)))
	terrain = painter.paint_terrain(layout, terrain, reserved, anchors, info, String(template.get("symmetry", "none")) == "rotate180")
	_landmarks = painter.landmarks.duplicate(true)


func _lay_roads() -> void:
	var conns: Array = template["connections"]
	for ci in conns.size():
		var c: Dictionary = conns[ci]
		if not bool(c.get("road", false)):
			continue
		var za := int(layout.zone_index[c["a"]])
		var zb := int(layout.zone_index[c["b"]])
		var cost := PackedInt32Array()
		cost.resize(w * h)
		for i in w * h:
			var z := layout.zone_of[i]
			if layout.wall[i] == 0 and (z == za or z == zb) and _passable(i):
				cost[i] = ROAD_PATH_COST if road[i] == 1 else _move_cost(i)
		var route := GridSearch.path(w, h, cost, anchors[za], anchors[zb])
		for i in route:
			road[i] = 1
			reserved[i] = 1


func _zone_open_mask(z: int, blockers: bool) -> PackedByteArray:
	var open := PackedByteArray()
	open.resize(w * h)
	for i in w * h:
		if layout.zone_of[i] == z and layout.wall[i] == 0 and _passable(i):
			if blockers and ((occupant[i] >= 0 and blocks_path(objects[occupant[i]])) or prize_block[i] != 0):
				continue
			open[i] = 1
	return open


## Objects a hero cannot walk through without fighting or resolving them:
## neutral armies, encounters, guarded mines and garrisoned neutral towns.
static func blocks_path(o: Dictionary) -> bool:
	if o.get("type", "") == "site" and MapCobolts.POSTS.has(o.get("site", "")):
		return false
	match String(o.get("type", "")):
		"neutral_army", "encounter":
			return true
		"mine", "site", "scenario_site":
			return not (o.get("guard", []) as Array).is_empty()
		"town":
			return int(o.get("owner", -1)) < 0 and not (o.get("garrison", []) as Array).is_empty()
	return false


func _zone_reach(z: int) -> int:
	var open := _zone_open_mask(z, true)
	return GridSearch.count(GridSearch.flood(w, h, open, PackedInt32Array([anchors[z]])))


func _place_obstacles() -> void:
	for z in _zones().size():
		var prof := _profile(z)
		var tiles := layout.open_tiles(z)
		var n := int(round(tiles.size() * float(prof.get("obstacle_density", 0.0)) / 3.0))
		var reach := _zone_reach(z)
		for _k in n:
			var start := tiles[rng.next_int(0, tiles.size() - 1)]
			var kind := "water" if rng.chance(0.3) else "mountain"
			var blob := PackedInt32Array([start])
			var size := rng.next_int(2, 4)
			var cur := start
			for _s in size * 3:
				if blob.size() >= size:
					break
				var nb := GridSearch.neighbors4(w, h, cur)
				cur = nb[rng.next_int(0, nb.size() - 1)]
				if not blob.has(cur):
					blob.append(cur)
			var ok := true
			for i in blob:
				if layout.zone_of[i] != z or layout.wall[i] != 0 or reserved[i] != 0 or road[i] != 0 or terrain[i] == "river" or not _passable(i):
					ok = false
					break
			if not ok:
				continue
			var old := PackedStringArray()
			for i in blob:
				old.append(terrain[i])
				terrain[i] = kind
			var now := _zone_reach(z)
			if now == reach - blob.size():
				reach = now
			else:
				for j in blob.size():
					terrain[blob[j]] = old[j]


# ----------------------------------------------------------------- objects --

func _add_object(o: Dictionary, i: int) -> void:
	o["pos"] = [layout.pos(i).x, layout.pos(i).y]
	occupant[i] = objects.size()
	objects.append(o)


func _neutral(army: Dictionary, z: int, role: String) -> Dictionary:
	return {"id": _next_id("neutral"), "type": "neutral_army", "name": army["name"],
		"stacks": army["stacks"].duplicate(true), "value": int(army["value"]), "role": role, "zone": _zones()[z]["id"]}


func _place_gate_guards() -> void:
	var conns: Array = template["connections"]
	var by_group := {}
	for ci in conns.size():
		var c: Dictionary = conns[ci]
		var gv := int(config["guard_levels"][c.get("guard", "none")])
		var gate: Dictionary = layout.gates[ci]
		if gv <= 0 or int(gate["center"]) < 0:
			continue
		var key := String(c.get("group", "conn_%d" % ci))
		if not by_group.has(key):
			by_group[key] = _roll_army(gv, terrain[int(gate["center"])])
		var z := layout.zone_of[int(gate["center"])]
		var o := _neutral(by_group[key], z, "gate")
		o["connection"] = "%s-%s" % [c["a"], c["b"]]
		_add_object(o, int(gate["center"]))


func _compute_zone_distances() -> void:
	for z in _zones().size():
		var open := _zone_open_mask(z, true)
		var cost := PackedInt32Array()
		cost.resize(w * h)
		for i in w * h:
			if open[i] != 0:
				cost[i] = _move_cost(i)
		zone_dist.append(GridSearch.distances(w, h, cost, PackedInt32Array([anchors[z]])))


func _free_for_object(i: int) -> bool:
	return occupant[i] < 0 and reserved[i] == 0 and road[i] == 0 and layout.wall[i] == 0 and _passable(i) and terrain[i] != "river"


func _spaced(i: int) -> bool:
	var p := layout.pos(i)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := p + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and occupant[layout.idx(q)] >= 0:
				return false
	return true


## Free tiles of zone z whose distance from the anchor falls in the band,
## widening the band step by step if the zone is too cramped.
func _band_candidates(z: int, band: String) -> PackedInt32Array:
	var range_: Array = config["distance_bands"][band]
	var dist: PackedInt32Array = zone_dist[z]
	for widen in [0, 200, 500, 2000, 100000]:
		var lo: int = int(range_[0]) - int(widen)
		var hi: int = int(range_[1]) + int(widen)
		var out := PackedInt32Array()
		for i in w * h:
			if layout.zone_of[i] == z and dist[i] >= lo and dist[i] <= hi and _free_for_object(i) and _spaced(i):
				out.append(i)
		if not out.is_empty():
			return out
	return PackedInt32Array()


## A town name not yet used on this map: one seeded draw from the pool, then
## the next unused name after it; when every name is taken, the drawn name
## with a numbered suffix ("Marrowgate II", "Marrowgate III", ...).
func _town_name() -> String:
	var names: Array = config["town_names"]
	var used := {}
	for o in objects:
		if o["type"] == "town":
			used[String(o.get("name", ""))] = true
	var first := rng.next_int(0, names.size() - 1)
	for k in names.size():
		var candidate := String(names[(first + k) % names.size()])
		if not used.has(candidate):
			return candidate
	var suffix := 2
	while used.has("%s %s" % [names[first], _roman(suffix)]):
		suffix += 1
	return "%s %s" % [names[first], _roman(suffix)]


static func _roman(n: int) -> String:
	var out := ""
	for pair in [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]:
		while n >= int(pair[0]):
			out += String(pair[1])
			n -= int(pair[0])
	return out


func _place_zone_content(plans: Dictionary) -> void:
	for z in _zones().size():
		var zone: Dictionary = _zones()[z]
		var plan: Dictionary = plans[String(zone.get("group", zone["id"]))]
		var prof := _profile(z)
		var town := _zone_town(z)
		if town != "none":
			var owner := int(zone["player"]) if town == "owner" else -1
			var faction := _player_faction(z) if town == "owner" else String(plan["town_faction"])
			var t := {"id": "town_%s" % zone["id"], "type": "town", "name": _town_name(),
				"town_type": faction, "owner": owner, "zone": zone["id"]}
			if owner < 0 and not (plan["garrison"] as Dictionary).is_empty():
				t["garrison"] = plan["garrison"]["stacks"].duplicate(true)
			_add_object(t, anchors[z])
		for item in plan["items"]:
			match String(item["kind"]):
				"mine":
					var res := String(item["resource"])
					if res == "faction_rare":
						var f := _player_faction(z)
						res = faction_rare(f) if f != "" else _rare_resources()[0]
					var o := {"id": _next_id("mine"), "type": "mine", "resource": res, "owner": -1, "zone": zone["id"]}
					if (item["guard"] as Dictionary).is_empty():
						_place_free(o, z, item)
					else:
						# Guarded mines hold their own guard and block the path (see Economy).
						o["guard"] = item["guard"]["stacks"].duplicate(true)
						_place_blocker(o, z, item)
				"treasure":
					var o := {"id": _next_id("res"), "type": "resource", "resource": item["resource"], "amount": int(item["amount"]),
						"treasure": true, "zone": zone["id"]}
					_place_guarded(o, item["guard"], z, item)
				"pile":
					_place_free({"id": _next_id("res"), "type": "resource", "resource": item["resource"],
						"amount": int(item["amount"]), "zone": zone["id"]}, z, item)
				"encounter":
					_place_blocker({"id": _next_id("enc"), "type": "encounter", "encounter": item["encounter"], "zone": zone["id"]}, z, item)
				"wanderer":
					_place_blocker(_neutral(item["guard"], z, "wander"), z, item)


## Armour pieces (artifacts of the drop slots, see armor_drops in
## map_templates.json): the same guarded piece at the same distance in every
## start zone, then a few random extras in the open zones, rarer ones behind
## stronger guards. Draws from its own stream, so adding or tuning drops never
## reshuffles the rest of the map.
func _place_armor_drops() -> void:
	var cfg: Dictionary = config.get("armor_drops", {})
	if cfg.is_empty():
		return
	var main_rng := rng
	rng = GameRng.new(GameRng.mix(_attempt_seed, _stable_hash("armor_drops")))
	var levels: Dictionary = config["guard_levels"]
	var used := {}
	var per: Dictionary = cfg.get("per_player", {})
	if not per.is_empty():
		var aid := _pick_armor(String(per["rarity"]), used)
		var starts: Array[int] = []
		for z in _zones().size():
			if _zones()[z].has("player"):
				starts.append(z)
		if aid != "" and not starts.is_empty():
			var gv := int(levels[per.get("guard", "none")])
			var army := _roll_army(gv, _base_terrain(starts[0])) if gv > 0 else {}
			var item := {"band": per["band"]}   # shared: mirrored starts match the first one's distance
			for z in starts:
				_place_armor(aid, army, z, item)
	var extra: Dictionary = cfg.get("extras", {})
	if not extra.is_empty():
		var zones: Array[int] = []
		var zone_w: Array = []
		var zw: Dictionary = extra.get("zone_weights", {})
		for z in _zones().size():
			var wgt := float(zw.get(_zones()[z]["profile"], 0))
			if not _zones()[z].has("player") and wgt > 0.0:
				zones.append(z)
				zone_w.append(wgt)
		var rarities: Array = (extra["rarity_weights"] as Dictionary).keys()
		var rarity_w: Array = rarities.map(func(r): return float(extra["rarity_weights"][r]))
		var count := rng.next_int(int(extra["min"]), int(extra["max"])) if not zones.is_empty() else 0
		for _k in count:
			var z: int = zones[rng.weighted_index(zone_w)]
			var rarity := String(rarities[rng.weighted_index(rarity_w)])
			var aid := _pick_armor(rarity, used)
			if aid == "":
				break
			var gv := int(levels[extra["guards"].get(rarity, "none")])
			var army := _roll_army(gv, _base_terrain(z)) if gv > 0 else {}
			_place_armor(aid, army, z, {"band": extra["band"]})
	rng = main_rng


## Rare map buildings (data/sites.json, see sites in map_templates.json):
## one identical non-dwelling site in every start zone at the same distance,
## then a few random sites in the open zones. A pick is placed in every zone of
## the chosen zone group, with the same guard and creature, so mirrored zones
## stay fair. Draws from its own stream, like the armour drops.
func _place_sites() -> void:
	var cfg: Dictionary = config.get("sites", {})
	if cfg.is_empty() or data.sites.is_empty():
		return
	var main_rng := rng
	rng = GameRng.new(GameRng.mix(_attempt_seed, _stable_hash("sites")))
	# The Crown layouts have a deliberately curated collection: an identical
	# waystation for each realm and a variety of guarded sites in the heart.
	if template_id.begins_with("crown_of_"):
		_place_crown_sites()
		rng = main_rng
		return
	var used := {}
	var per: Dictionary = cfg.get("per_player", {})
	if not per.is_empty():
		var starts: Array[int] = []
		for z in _zones().size():
			if _zones()[z].has("player"):
				starts.append(z)
		var sid := _pick_site(per.get("kinds", []), used)
		if sid != "" and not starts.is_empty():
			_place_site_group(sid, starts, {"band": per["band"]})
	var extra: Dictionary = cfg.get("extras", {})
	if not extra.is_empty():
		var groups: Array = []
		var group_zones := {}
		var group_w: Array = []
		var zw: Dictionary = extra.get("zone_weights", {})
		for z in _zones().size():
			var wgt := float(zw.get(_zones()[z]["profile"], 0))
			if _zones()[z].has("player") or wgt <= 0.0:
				continue
			var g := String(_zones()[z].get("group", _zones()[z]["id"]))
			if not group_zones.has(g):
				group_zones[g] = []
				groups.append(g)
				group_w.append(wgt)
			group_zones[g].append(z)
		var count := rng.next_int(int(extra["min"]), int(extra["max"])) if not groups.is_empty() else 0
		for _k in count:
			var g: String = groups[rng.weighted_index(group_w)]
			var sid := _pick_site([], used)
			if sid == "":
				break
			var zones: Array[int] = []
			zones.assign(group_zones[g])
			_place_site_group(sid, zones, {"band": extra["band"]})
	# Ruins and similar profiles ask for their own sites ("site_picks"), the
	# same site in every zone of the group.
	var done_groups := {}
	for z in _zones().size():
		var picks := int(_profile(z).get("site_picks", 0))
		var g := String(_zones()[z].get("group", _zones()[z]["id"]))
		if picks <= 0 or done_groups.has(g) or _zones()[z].has("player"):
			continue
		done_groups[g] = true
		var members: Array[int] = []
		for other in _zones().size():
			if String(_zones()[other].get("group", _zones()[other]["id"])) == g:
				members.append(other)
		for _k in picks:
			var sid := _pick_site([], used)
			if sid == "":
				break
			_place_site_group(sid, members, {"band": String(_profile(z).get("site_band", "far"))})
	rng = main_rng


## Authored building selection for the free-for-all heartland. The identical
## rim sites are rolled once and placed at matched distances for every player.
func _place_crown_sites() -> void:
	var starts: Array[int] = []
	for z in _zones().size():
		if _zones()[z].has("player"):
			starts.append(z)
	if data.sites.has("wardens_causeway") and not starts.is_empty():
		_place_site_group("wardens_causeway", starts, {"band": "mid"})
	var heart: Array[int] = [int(layout.zone_index["heart"])]
	for sid in ["pyre_citadel", "sellsword_gate", "bleeding_rift", "elder_rings", "outcast_camp", "pilgrims_rest"]:
		if data.sites.has(sid):
			var placement := {"band": "far"}
			if String(data.sites[sid].get("guard", "none")) != "none":
				placement["guard_override"] = "strong"
			_place_site_group(sid, heart, placement)


## A site of one of the kinds (any if empty) not used on this map yet, by weight; "" if none is left.
func _pick_site(kinds: Array, used: Dictionary) -> String:
	var ids := data.sites.keys()
	ids.sort()
	var pool: Array = ids.filter(func(id): return data.sites[id]["kind"] not in ["trader", "village", "cobolt"] and not used.has(id) and (kinds.is_empty() or kinds.has(data.sites[id]["kind"])))
	if pool.is_empty():
		return ""
	var pick := String(pool[rng.weighted_index(pool.map(func(id): return float(data.sites[id].get("weight", 1))))])
	used[pick] = true
	return pick


func _place_site_group(sid: String, zones: Array[int], item: Dictionary) -> void:
	var def: Dictionary = data.sites[sid]
	var gv := int(config["guard_levels"].get(String(item.get("guard_override", def.get("guard", "none"))), 0))
	if String(def["kind"]) == "spell":
		gv = maxi(gv, int(config["guard_levels"].get(String(def["guard"]), 0)))
	var army := _roll_army(gv, _base_terrain(zones[0]), 4 if String(def["kind"]) == "spell" else 1) if gv > 0 else {}
	var spell_id := ""
	if String(def["kind"]) == "spell":
		var rare: Array = data.magic["spells"].keys().filter(func(id): return data.magic["spells"][id]["source"] == "rare")
		rare.sort()
		if not rare.is_empty():
			spell_id = String(rare[rng.next_int(0, rare.size() - 1)])
	var creature := ""
	if String(def["kind"]) == "dwelling":
		var pool := MapSites.creature_pool(def, data)
		creature = pool[rng.next_int(0, pool.size() - 1)]
	for z in zones:
		var o := {"id": _next_id("site"), "type": "site", "site": sid, "zone": _zones()[z]["id"]}
		if spell_id != "":
			o["spell"] = spell_id
		if creature != "":
			o["creature"] = creature
			o["owner"] = -1
		if army.is_empty():
			_place_free(o, z, item)
		else:
			o["guard"] = army["stacks"].duplicate(true)
			_place_blocker(o, z, item)


## Guarded hoards (the "hoards" key of a profile, rules in hoard_rules of
## map_templates.json): the density fill. Each zone group gets one hoard per
## `per_tiles` open tiles of its zone (up to `max`); each hoard is a resource
## cache or an armour piece sealed in a pocket behind a neutral army. The pick
## sets the guard level and the distance band, so the profiles decide how
## strength grows from the quiet backwaters to the contested heart. The prize
## scales with the guard actually rolled. Every zone of a group gets the same
## hoards (same guard, prize and distance), so mirrored zones stay fair. Draws
## from its own stream, so tuning the fill never reshuffles the rest.
func _place_hoards() -> void:
	var rules: Dictionary = config.get("hoard_rules", {})
	if rules.is_empty():
		return
	var main_rng := rng
	rng = GameRng.new(GameRng.mix(_attempt_seed, _stable_hash("hoards")))
	var levels: Dictionary = config["guard_levels"]
	var used := {}
	for o in objects:
		if o["type"] == "artifact":
			used[String(o["artifact"])] = true
	var groups: Array[String] = []
	var group_zones := {}
	for z in _zones().size():
		var g := String(_zones()[z].get("group", _zones()[z]["id"]))
		if not group_zones.has(g):
			group_zones[g] = []
			groups.append(g)
		group_zones[g].append(z)
	for g in groups:
		var zones: Array[int] = []
		zones.assign(group_zones[g])
		var fill: Dictionary = _profile(zones[0]).get("hoards", {})
		var picks: Array = fill.get("picks", [])
		if picks.is_empty():
			continue
		var count := hoard_count(layout.open_tiles(zones[0]).size(), fill, _treasure_scale())
		var pick_w: Array = picks.map(func(p): return float(p.get("weight", 1)))
		for _k in count:
			var pick: Dictionary = picks[rng.weighted_index(pick_w)]
			var level := String(pick["guard"])
			var spread := float(rules.get("guard_spread", 0.0))
			var gv := int(round(float(levels[level]) * rng.next_float_range(1.0 - spread, 1.0 + spread) / 50.0)) * 50
			var army := _roll_army(gv, _base_terrain(zones[0]))
			var prize := _roll_hoard_prize(rules, level, gv, used)
			var item := {"band": pick["band"]}
			for z in zones:
				var o := prize.duplicate(true)
				o["id"] = _next_id("art" if o["type"] == "artifact" else "res")
				o["zone"] = _zones()[z]["id"]
				o["hoard"] = true
				if _place_guarded(o, army, z, item):
					objects[-1]["hoard"] = true   # the guard, placed last
	rng = main_rng


## How many hoards (or scattered piles) a zone of `tiles` open tiles gets
## under a profile's hoards (or scatter) settings; `scale` is the template's
## treasure_scale, which moves both the rate and the cap.
static func hoard_count(tiles: int, fill: Dictionary, scale: float = 1.0) -> int:
	var per := maxi(1, int(fill.get("per_tiles", 100)))
	var hi := int(round(float(fill.get("max", 99)) * scale))
	return clampi(int(round(float(tiles) * scale / per)), mini(int(fill.get("min", 0)), hi), hi)


func _treasure_scale() -> float:
	return float(template.get("treasure_scale", 1.0))


## Scattered piles (the "scatter" key of a profile, rules in scatter_rules of
## map_templates.json): unguarded resource piles, one per `per_tiles` open
## tiles of a zone (up to `max`), so big zones are not emptier than small
## ones. Like hoards, every zone of a group gets the same piles at about the
## same distance, and they draw from their own stream.
func _place_scatter() -> void:
	var rules: Dictionary = config.get("scatter_rules", {})
	if rules.is_empty():
		return
	var main_rng := rng
	rng = GameRng.new(GameRng.mix(_attempt_seed, _stable_hash("scatter")))
	var kinds: Dictionary = rules.get("resource_weights", {"gold": 1})
	var keys: Array = kinds.keys()
	keys.sort()
	var kind_w: Array = keys.map(func(k): return float(kinds[k]))
	var bands: Dictionary = rules.get("band_weights", {"mid": 1})
	var band_keys: Array = bands.keys()
	band_keys.sort()
	var band_w: Array = band_keys.map(func(k): return float(bands[k]))
	var groups: Array[String] = []
	var group_zones := {}
	for z in _zones().size():
		var g := String(_zones()[z].get("group", _zones()[z]["id"]))
		if not group_zones.has(g):
			group_zones[g] = []
			groups.append(g)
		group_zones[g].append(z)
	for g in groups:
		var zones: Array[int] = []
		zones.assign(group_zones[g])
		var fill: Dictionary = _profile(zones[0]).get("scatter", {})
		if fill.is_empty():
			continue
		var count := hoard_count(layout.open_tiles(zones[0]).size(), fill, _treasure_scale())
		for _k in count:
			var kind := String(keys[rng.weighted_index(kind_w)])
			var res := kind
			if kind == "rare":
				res = _rare_resources()[rng.next_int(0, _rare_resources().size() - 1)]
			var amount := _roll_amount(config["pile_amounts"][kind])
			var item := {"band": String(band_keys[rng.weighted_index(band_w)])}
			for z in zones:
				_place_free({"id": _next_id("res"), "type": "resource", "resource": res, "amount": amount,
					"zone": _zones()[z]["id"], "scatter": true}, z, item)
	rng = main_rng


## The prize of one hoard (without id or zone): sometimes an armour piece of
## the rarity the guard level earns, otherwise resources worth a share of the guard.
func _roll_hoard_prize(rules: Dictionary, level: String, gv: int, used: Dictionary) -> Dictionary:
	var rarity := String(rules.get("artifact_rarity", {}).get(level, ""))
	if rarity != "" and rng.chance(float(rules.get("artifact_chance", 0.0))):
		var aid := _pick_armor(rarity, used)
		if aid != "":
			return {"type": "artifact", "artifact": aid}
	var ratio: Array = rules.get("value_ratio", [0.5, 0.5])
	var value := maxf(float(rules.get("min_value", 0)), gv * rng.next_float_range(float(ratio[0]), float(ratio[1])))
	var kinds: Dictionary = rules.get("resource_weights", {"gold": 1})
	var keys: Array = kinds.keys()
	keys.sort()
	var kind := String(keys[rng.weighted_index(keys.map(func(k): return float(kinds[k])))])
	var res := kind
	if kind == "rare":
		res = _rare_resources()[rng.next_int(0, _rare_resources().size() - 1)]
	var unit := float(MapValidator.RESOURCE_VALUE.get(res, MapValidator.RARE_VALUE))
	var amount := int(round(value / unit))
	if res == "gold":
		amount = maxi(100, int(round(value / 100.0)) * 100)
	return {"type": "resource", "resource": res, "amount": maxi(1, amount), "treasure": true}


func _place_armor(aid: String, army: Dictionary, z: int, item: Dictionary) -> bool:
	var o := {"id": _next_id("art"), "type": "artifact", "artifact": aid, "zone": _zones()[z]["id"]}
	if army.is_empty():
		return _place_free(o, z, item)
	return _place_guarded(o, army, z, item)


## A droppable armour piece of the rarity not yet on this map (any rarity if
## none is left), or "" when every piece is used. Marks it used.
func _pick_armor(rarity: String, used: Dictionary) -> String:
	var drop_slots: Array = data.artifact_rules.get("drop_slots", [])
	var pool: Array[String] = []
	var any: Array[String] = []
	for aid in data.artifacts:
		var a: Dictionary = data.artifacts[aid]
		if used.has(aid) or not drop_slots.has(a["slot"]):
			continue
		any.append(String(aid))
		if String(a["rarity"]) == rarity:
			pool.append(String(aid))
	if pool.is_empty():
		pool = any
	if pool.is_empty():
		return ""
	pool.sort()
	var pick := pool[rng.next_int(0, pool.size() - 1)]
	used[pick] = true
	return pick


## Candidate tiles for a plan item, in the order they should be tried. The
## first zone of a group picks freely inside the distance band and records the
## distance; mirrored zones then prefer tiles at about the same distance.
func _candidate_order(z: int, item: Dictionary) -> PackedInt32Array:
	var cands := _band_candidates(z, String(item["band"]))
	var dist: PackedInt32Array = zone_dist[z]
	if item.has("target"):
		var target := int(item["target"])
		var close := PackedInt32Array()
		for i in cands:
			if absi(dist[i] - target) <= MATCH_TOLERANCE:
				close.append(i)
		if close.size() < 3:
			# Too few close matches: take the nearest few instead.
			var arr: Array = Array(cands)
			arr.sort_custom(func(a, b): return absi(dist[a] - target) < absi(dist[b] - target) or (absi(dist[a] - target) == absi(dist[b] - target) and a < b))
			close = PackedInt32Array(arr.slice(0, 3))
		cands = close
	# Deterministic shuffle.
	for k in range(cands.size() - 1, 0, -1):
		var j := rng.next_int(0, k)
		var t := cands[k]
		cands[k] = cands[j]
		cands[j] = t
	return cands


func _remember_target(item: Dictionary, z: int, i: int) -> void:
	if not item.has("target"):
		item["target"] = (zone_dist[z] as PackedInt32Array)[i]


func _place_free(o: Dictionary, z: int, item: Dictionary) -> bool:
	var cands := _candidate_order(z, item)
	if cands.is_empty():
		return false
	_add_object(o, cands[0])
	_remember_target(item, z, cands[0])
	return true


## Places an object that blocks movement without cutting the zone apart.
func _place_blocker(o: Dictionary, z: int, item: Dictionary) -> bool:
	var reach := _zone_reach(z)
	var cands := _candidate_order(z, item)
	for k in mini(cands.size(), 10):
		var i := cands[k]
		_add_object(o, i)
		if _zone_ok(z, reach, 1):
			_remember_target(item, z, i)
			return true
		_remove_last(i)
	return false


func _remove_last(i: int) -> void:
	objects.pop_back()
	occupant[i] = -1


## Reached-mask of zone z from its anchor with neutral armies blocking.
func _zone_flood(z: int) -> PackedByteArray:
	return GridSearch.flood(w, h, _zone_open_mask(z, true), PackedInt32Array([anchors[z]]))


## True if the zone lost exactly `lost` reachable tiles and every blocking
## object in it (including the new one) still borders reached ground, so
## nothing that must be fought or visited has been walled in.
func _zone_ok(z: int, reach: int, lost: int) -> bool:
	var mask := _zone_flood(z)
	if GridSearch.count(mask) != reach - lost:
		return false
	for o in objects:
		if not blocks_path(o) or o["zone"] != _zones()[z]["id"]:
			continue
		var at := layout.idx(Vector2i(int(o["pos"][0]), int(o["pos"][1])))
		var touches := false
		for n in GridSearch.neighbors4(w, h, at):
			if mask[n] != 0:
				touches = true
				break
		if not touches and o.get("role", "") != "gate":
			return false
	return true


## Puts the object in a pocket: every side but one is sealed with rock and the
## guard stands on the open side, so it really has to be fought for.
func _place_guarded(o: Dictionary, army: Dictionary, z: int, item: Dictionary) -> bool:
	var dist: PackedInt32Array = zone_dist[z]
	var reach := _zone_reach(z)
	var cands := _candidate_order(z, item)
	if String(template.get("guard_pockets", "sealed")) == "open":
		return _place_guarded_open(o, army, z, item, cands, reach)
	for k in mini(cands.size(), POCKET_TRIES):
		var site := cands[k]
		# Guard on the side facing the anchor.
		var guard := -1
		for n in GridSearch.neighbors4(w, h, site):
			if _free_for_object(n) and dist[n] >= 0 and (guard < 0 or dist[n] < dist[guard]):
				guard = n
		if guard < 0:
			continue
		var seal := PackedInt32Array()
		var ok := true
		for n in GridSearch.neighbors4(w, h, site):
			if n == guard or not _passable(n):
				continue
			if not _free_for_object(n) or layout.zone_of[n] != z:
				ok = false
				break
			seal.append(n)
		if not ok:
			continue
		var old := PackedStringArray()
		for n in seal:
			old.append(terrain[n])
			terrain[n] = "mountain"
		_add_object(o, site)
		var g := _neutral(army, z, "guard")
		g["guards"] = o["id"]
		_add_object(g, guard)
		if _zone_ok(z, reach, seal.size() + 2):
			o["guarded_by"] = g["id"]
			_remember_target(item, z, site)
			return true
		_remove_last(guard)
		_remove_last(site)
		for j in seal.size():
			terrain[seal[j]] = old[j]
	# Cramped zone: fall back to an unsealed spot with the guard next to it.
	for k in mini(cands.size(), POCKET_TRIES):
		var site := cands[k]
		if occupant[site] >= 0:
			continue
		for n in GridSearch.neighbors4(w, h, site):
			if not _free_for_object(n):
				continue
			_add_object(o, site)
			var g := _neutral(army, z, "guard")
			g["guards"] = o["id"]
			_add_object(g, n)
			if _zone_ok(z, reach, 1):
				o["guarded_by"] = g["id"]
				_remember_target(item, z, site)
				return true
			_remove_last(n)
			_remove_last(site)
	return false


## guard_pockets "open": the prize stays in the open with its guard on the
## neighbouring tile facing the anchor; no rock is raised. Neither the guard
## nor the prize (which cannot be claimed or crossed while its guard lives)
## may cut off any other ground of the zone.
func _place_guarded_open(o: Dictionary, army: Dictionary, z: int, item: Dictionary, cands: PackedInt32Array, reach: int) -> bool:
	var dist: PackedInt32Array = zone_dist[z]
	for k in mini(cands.size(), POCKET_TRIES):
		var site := cands[k]
		if occupant[site] >= 0:
			continue
		var guard := -1
		for n in GridSearch.neighbors4(w, h, site):
			if _free_for_object(n) and dist[n] >= 0 and (guard < 0 or dist[n] < dist[guard]):
				guard = n
		if guard < 0:
			continue
		_add_object(o, site)
		var g := _neutral(army, z, "guard")
		g["guards"] = o["id"]
		_add_object(g, guard)
		prize_block[site] = 1
		if _zone_ok(z, reach, 2):
			o["guarded_by"] = g["id"]
			_remember_target(item, z, site)
			return true
		prize_block[site] = 0
		_remove_last(guard)
		_remove_last(site)
	return false


## Traders are rolled separately from rare buildings, on an independent stream.
## Neutral zones keep asymmetric shop access out of mirrored starting areas.
func _place_trader() -> void:
	var main_rng := rng
	rng = GameRng.new(GameRng.mix(_attempt_seed, _stable_hash("traders")))
	if rng.chance(MapTraders.spawn_chance(w, h, data)):
		var candidates: Array[int] = []
		for z in _zones().size():
			if _zones()[z].has("player"):
				continue
			for i in layout.open_tiles(z):
				if _free_for_object(i) and zone_dist[z][i] >= 0 and not heroes.any(func(hero): return hero["pos"] == [i % w, i / w]):
					candidates.append(i)
		if not candidates.is_empty():
			var i := candidates[rng.next_int(0, candidates.size() - 1)]
			_add_object({"id": _next_id("trader"), "type": "site", "site": MapTraders.SITE_ID,
				"zone": _zones()[layout.zone_of[i]]["id"], "stock": MapTraders.make_stock(data, rng)}, i)
	rng = main_rng


func _place_heroes() -> void:
	var order := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	var used_names := {}
	for z in _zones().size():
		var zone: Dictionary = _zones()[z]
		if not zone.has("player"):
			continue
		var pl := int(zone["player"])
		var faction := _player_faction(z)
		var fc := _hero_settings(pl, faction)
		var a := layout.pos(anchors[z])
		var spot := a
		for d in order:
			var q: Vector2i = a + d
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
				var i := layout.idx(q)
				if _passable(i) and occupant[i] < 0 and layout.wall[i] == 0:
					spot = q
					break
		var names: Array = fc["hero_names"]
		var name: String = names[rng.next_int(0, names.size() - 1)]
		if used_names.has(name):
			name = "%s the Younger" % name
		used_names[name] = true
		heroes.append({"id": "hero_p%d" % pl, "name": name, "class": fc["hero_class"], "owner": pl,
			"pos": [spot.x, spot.y], "army": fc["army"].duplicate(true)})


# -------------------------------------------------------------- definition --

func _definition() -> Dictionary:
	var rows: Array = []
	for y in h:
		var row := ""
		for x in w:
			row += String(data.terrain(terrain[y * w + x])["char"])
		rows.append(row)
	var players: Array = []
	var tp: Array = template["players"]
	for pi in tp.size():
		var p: Dictionary = tp[pi]
		var fname := String(data.factions[p["faction"]]["name"])
		players.append({"id": pi, "name": "Player" if bool(p["is_human"]) else fname, "faction": p["faction"],
			"color": p.get("color", data.factions[p["faction"]]["color"]), "is_human": bool(p["is_human"])})
	var zones: Array = []
	for z in _zones().size():
		var zd := {"id": _zones()[z]["id"], "profile": _zones()[z]["profile"], "anchor": [layout.pos(anchors[z]).x, layout.pos(anchors[z]).y],
			"tiles": layout.open_tiles(z).size(), "terrain": _base_terrain(z)}
		if _zones()[z].has("player"):
			zd["player"] = int(_zones()[z]["player"])
		if bool(_zones()[z].get("optional", false)):
			zd["optional"] = true
		zones.append(zd)
	var conns: Array = []
	var tc: Array = template["connections"]
	for ci in tc.size():
		var gate: Dictionary = layout.gates[ci]
		var tiles: Array = []
		for t in gate["tiles"]:
			tiles.append([layout.pos(t).x, layout.pos(t).y])
		var guard := ""
		if int(gate["center"]) >= 0 and occupant[int(gate["center"])] >= 0:
			guard = objects[occupant[int(gate["center"])]]["id"]
		conns.append({"a": tc[ci]["a"], "b": tc[ci]["b"], "gate": tiles, "guard": guard})
	var def := {
		"_doc": "Generated by MapGenerator v%d from template '%s', seed %d." % [VERSION, template_id, seed_value],
		"id": make_id(template_id, seed_value, player_factions),
		"name": "%s (%d)" % [template.get("name", template_id), seed_value],
		"width": w, "height": h,
		"terrain": rows,
		"roads": _road_segments(),
		"decorations": _landmark_decorations(),
		"decor": TerrainPainter.DECOR_MODE,
		"players": players,
		"heroes": heroes,
		"objects": objects,
		"generator": {"version": VERSION, "template": template_id, "seed": seed_value, "attempt": attempts_used,
			"zones": zones, "connections": conns,
			"policy": template.get("policy", "fair"), "layout_family": template.get("layout_family", "classic"),
			"orientation": int(template.get("orientation", 0)),
			"recipe_version": int(template.get("recipe_version", 1))},
	}
	def["scenery"] = _landmarks.duplicate(true)
	TerrainPainter.dress(def, data, _attempt_seed)
	return def


## A deliberately arranged ruined crown around the central town. The decoration
## never covers roads, gameplay objects, heroes, or impassable ground.
func _landmark_decorations() -> Array:
	if not template_id.begins_with("crown_of_"):
		return []
	var z := int(layout.zone_index["heart"])
	var center := layout.pos(anchors[z])
	var result: Array = []
	var pattern := [[-5, -3, "obsidian"], [-4, -5, "boulders"], [-2, -6, "gravestone"],
		[0, -6, "obsidian"], [2, -6, "gravestone"], [4, -5, "boulders"], [5, -3, "obsidian"],
		[-6, 0, "gravestone"], [6, 0, "gravestone"], [-5, 3, "obsidian"],
		[-4, 5, "boulders"], [-2, 6, "gravestone"], [0, 6, "obsidian"],
		[2, 6, "gravestone"], [4, 5, "boulders"], [5, 3, "obsidian"]]
	_append_landmark(result, z, center, pattern)
	# Each rim realm gets a small ruined waystation, facing the shared heart.
	# The offset and palette are fixed; collisions never change gameplay.
	for home in _zones().size():
		if not _zones()[home].has("player"):
			continue
		var origin := layout.pos(anchors[home])
		var toward := Vector2(center - origin).normalized()
		var site := origin + Vector2i(roundi(toward.x * 8.0), roundi(toward.y * 8.0))
		for o in objects:
			if o.get("type", "") == "site" and o.get("zone", "") == _zones()[home]["id"] and o.get("site", "") == "wardens_causeway":
				site = Vector2i(int(o["pos"][0]), int(o["pos"][1]))
				break
		var stone := "obsidian" if _player_faction(home) == "ashen" else "boulders"
		var tree := "dead_tree" if _player_faction(home) == "ashen" else "pines"
		var outpost := [[-3, -2, stone], [0, -3, tree], [3, -2, stone],
			[-3, 2, tree], [0, 3, stone], [3, 2, tree]]
		_append_landmark(result, home, site, outpost)
	return result


func _append_landmark(result: Array, z: int, center: Vector2i, pattern: Array) -> void:
	for piece in pattern:
		var p := center + Vector2i(int(piece[0]), int(piece[1]))
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var i := layout.idx(p)
		if layout.zone_of[i] != z or road[i] != 0 or occupant[i] >= 0 or not _passable(i):
			continue
		if heroes.any(func(hero): return hero["pos"] == [p.x, p.y]):
			continue
		var near_site := false
		for o in objects:
			if o["type"] == "site":
				var q := Vector2i(int(o["pos"][0]), int(o["pos"][1]))
				if maxi(absi(q.x - p.x), absi(q.y - p.y)) <= 2:
					near_site = true
					break
		if not near_site:
			result.append({"pos": [p.x, p.y], "kind": piece[2]})


## Compresses road tiles into straight segments (horizontal runs first).
func _road_segments() -> Array:
	var segs: Array = []
	var covered := PackedByteArray()
	covered.resize(w * h)
	for y in h:
		var x := 0
		while x < w:
			if road[y * w + x] == 1:
				var x2 := x
				while x2 + 1 < w and road[y * w + x2 + 1] == 1:
					x2 += 1
				if x2 > x:
					segs.append({"from": [x, y], "to": [x2, y]})
					for k in range(x, x2 + 1):
						covered[y * w + k] = 1
				x = x2 + 1
			else:
				x += 1
	for x in w:
		var y := 0
		while y < h:
			if road[y * w + x] == 1 and covered[y * w + x] == 0:
				var y2 := y
				while y2 + 1 < h and road[(y2 + 1) * w + x] == 1 and covered[(y2 + 1) * w + x] == 0:
					y2 += 1
				segs.append({"from": [x, y], "to": [x, y2]})
				y = y2 + 1
			else:
				y += 1
	return segs


# --------------------------------------------------------------- validation --

## Problems in data/map_templates.json. Called from GameData.validate().
static func validate_templates(game_data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var habitats: Variant = game_data.map_templates.get("neutral_habitats", {})
	if typeof(habitats) != TYPE_DICTIONARY:
		errors.append("neutral_habitats must be a dictionary")
	else:
		var chance: Variant = habitats.get("native_chance", 0.85)
		if typeof(chance) not in [TYPE_INT, TYPE_FLOAT] or float(chance) < 0.0 or float(chance) > 1.0:
			errors.append("neutral_habitats.native_chance must be between 0 and 1")
	var cfg := game_data.map_templates
	if cfg.is_empty():
		return errors
	var levels: Dictionary = cfg.get("guard_levels", {})
	var bands: Dictionary = cfg.get("distance_bands", {})
	for key in ["guard_levels", "distance_bands", "pile_amounts", "treasure_amounts", "town_names", "encounter_risk", "factions", "profiles", "templates"]:
		if not cfg.has(key):
			errors.append("map_templates missing %s" % key)
	if not errors.is_empty():
		return errors
	for risk in cfg["encounter_risk"]:
		for eid in cfg["encounter_risk"][risk]:
			if not game_data.encounters.has(eid):
				errors.append("map_templates: unknown encounter %s" % eid)
	for fid in cfg["factions"]:
		var f: Dictionary = cfg["factions"][fid]
		if not game_data.factions.has(fid) or not game_data.town_types.has(fid):
			errors.append("map_templates: faction %s has no faction or town type" % fid)
		if not game_data.hero_classes.has(f.get("hero_class", "")):
			errors.append("map_templates: faction %s has unknown hero_class" % fid)
		for pair in f.get("army", []):
			if not game_data.creatures.has(pair[0]):
				errors.append("map_templates: faction %s army has unknown creature %s" % [fid, pair[0]])
		if f.get("hero_names", []).is_empty():
			errors.append("map_templates: faction %s has no hero_names" % fid)
	var resource_words := ["rare", "faction_rare"]
	for pid in cfg["profiles"]:
		var p: Dictionary = cfg["profiles"][pid]
		var ts: Variant = p.get("terrain", "")
		if ts is Array:
			for t in ts:
				if not game_data.terrains.has(t):
					errors.append("profile %s: unknown terrain %s" % [pid, t])
		elif ts != "native":
			errors.append("profile %s: terrain must be a list or \"native\"" % pid)
		for t in p.get("patches", []):
			if not game_data.terrains.has(t):
				errors.append("profile %s: unknown patch terrain %s" % [pid, t])
		if not ["owner", "neutral", "none"].has(p.get("town", "none")):
			errors.append("profile %s: bad town value" % pid)
		if not levels.has(p.get("garrison", "none")):
			errors.append("profile %s: unknown garrison level" % pid)
		if int(p.get("site_picks", 0)) < 0 or int(p.get("site_picks", 0)) > 4:
			errors.append("profile %s: site_picks must be 0-4" % pid)
		if p.has("site_band") and not bands.has(p["site_band"]):
			errors.append("profile %s: unknown site_band %s" % [pid, p["site_band"]])
		for e in p.get("encounters", []):
			if not cfg["encounter_risk"].has(e.get("risk", "")):
				errors.append("profile %s: unknown encounter risk %s" % [pid, e.get("risk", "")])
		for list_key in ["mines", "piles", "treasures", "wanderers", "encounters"]:
			for item in p.get(list_key, []):
				if item.has("band") and not bands.has(item["band"]):
					errors.append("profile %s %s: unknown band %s" % [pid, list_key, item["band"]])
				if item.has("guard") and not levels.has(item["guard"]):
					errors.append("profile %s %s: unknown guard %s" % [pid, list_key, item["guard"]])
				if item.has("resource") and not (game_data.resources.has(item["resource"]) or resource_words.has(item["resource"])):
					errors.append("profile %s %s: unknown resource %s" % [pid, list_key, item["resource"]])
				if list_key == "piles" and item.has("resource") and not cfg["pile_amounts"].has(item["resource"]):
					errors.append("profile %s: no pile_amounts for %s" % [pid, item["resource"]])
	errors.append_array(_validate_armor_drops(game_data, cfg.get("armor_drops", {})))
	errors.append_array(_validate_hoards(game_data, cfg))
	errors.append_array(_validate_scatter(game_data, cfg))
	errors.append_array(RandomMapTemplate.validate(cfg))
	for tid in cfg["templates"]:
		var t: Dictionary = cfg["templates"][tid]
		if t.get("policy", "fair") not in ["fair", "adventure"]:
			errors.append("template %s: unknown generation policy" % tid)
		if t.get("graph", "fixed") not in ["fixed", "spatial"]:
			errors.append("template %s: unknown graph strategy" % tid)
		if float(t.get("loop_chance", 0.25)) < 0.0 or float(t.get("loop_chance", 0.25)) > 1.0:
			errors.append("template %s: invalid loop chance" % tid)
		if t.has("recipe_version") and not ScenarioRules._whole(t["recipe_version"], 1):
			errors.append("template %s: invalid recipe version" % tid)
		if t.get("graph", "fixed") == "spatial":
			if t.get("layout_family", "") not in ["frontiers", "ringlands", "broken_marches"]:
				errors.append("template %s: unknown spatial layout family" % tid)
			if t.get("layout_family", "") == "ringlands":
				var ring: Variant = t.get("ring_order", null)
				var expected: Array = t.get("zones", []).map(func(z): return z["id"])
				if typeof(ring) != TYPE_ARRAY or ring.size() != expected.size():
					errors.append("template %s: ring_order must include every zone once" % tid)
				else:
					var sorted: Array = ring.duplicate()
					sorted.sort()
					expected.sort()
					if sorted != expected:
						errors.append("template %s: invalid ring_order" % tid)
		if RandomMapTemplate.is_random(tid):
			errors.append("template %s: the random_ prefix is reserved for random maps" % tid)
		for key in ["guard_scale", "treasure_scale"]:
			if t.has(key) and float(t[key]) <= 0.0:
				errors.append("template %s: %s must be > 0" % [tid, key])
		if not String(t.get("guard_pockets", "sealed")) in GUARD_POCKETS:
			errors.append("template %s: guard_pockets must be one of %s" % [tid, ", ".join(GUARD_POCKETS)])
		var ids := {}
		var players: Array = t.get("players", [])
		for pl in players:
			if not cfg["factions"].has(pl.get("faction", "")):
				errors.append("template %s: player faction %s has no generator settings" % [tid, pl.get("faction", "")])
		var seen_players := {}
		for z in t.get("zones", []):
			var zid := String(z.get("id", ""))
			if ids.has(zid):
				errors.append("template %s: duplicate zone %s" % [tid, zid])
			if not cfg["profiles"].has(z.get("profile", "")):
				errors.append("template %s zone %s: unknown profile" % [tid, zid])
			var mirror := String(z.get("mirror", ""))
			if mirror != "" and mirror != "self" and not ids.has(mirror):
				errors.append("template %s zone %s: mirror must name an earlier zone" % [tid, zid])
			if z.has("player"):
				var pi := int(z["player"])
				if pi < 0 or pi >= players.size():
					errors.append("template %s zone %s: bad player index" % [tid, zid])
				seen_players[pi] = true
				if cfg["profiles"].get(z.get("profile", ""), {}).get("town", "") != "owner":
					errors.append("template %s zone %s: player zones need a profile with an owned town" % [tid, zid])
			ids[zid] = true
		if seen_players.size() != players.size():
			errors.append("template %s: every player needs exactly one start zone" % tid)
		for c in t.get("connections", []):
			if not ids.has(c.get("a", "")) or not ids.has(c.get("b", "")):
				errors.append("template %s: connection between unknown zones %s-%s" % [tid, c.get("a", ""), c.get("b", "")])
			if not levels.has(c.get("guard", "none")):
				errors.append("template %s: unknown guard level %s" % [tid, c.get("guard", "")])
			if int(c.get("width", 1)) < 1:
				errors.append("template %s: connection width must be >= 1" % tid)
	return errors


static func _validate_armor_drops(game_data: GameData, cfg: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if cfg.is_empty():
		return errors
	var levels: Dictionary = game_data.map_templates["guard_levels"]
	var bands: Dictionary = game_data.map_templates["distance_bands"]
	var rarities := {}
	for aid in game_data.artifacts:
		if (game_data.artifact_rules.get("drop_slots", []) as Array).has(game_data.artifacts[aid]["slot"]):
			rarities[String(game_data.artifacts[aid]["rarity"])] = true
	if rarities.is_empty():
		errors.append("armor_drops: no artifact fits a drop slot")
	var per: Dictionary = cfg.get("per_player", {})
	if not per.is_empty():
		if not rarities.has(per.get("rarity", "")):
			errors.append("armor_drops.per_player: no droppable piece of rarity %s" % per.get("rarity", ""))
		if not bands.has(per.get("band", "")) or not levels.has(per.get("guard", "none")):
			errors.append("armor_drops.per_player: unknown band or guard")
	var extra: Dictionary = cfg.get("extras", {})
	if not extra.is_empty():
		if int(extra.get("min", -1)) < 0 or int(extra.get("max", -1)) < int(extra.get("min", 0)):
			errors.append("armor_drops.extras: need 0 <= min <= max")
		if not bands.has(extra.get("band", "")):
			errors.append("armor_drops.extras: unknown band")
		for pid in extra.get("zone_weights", {}):
			if not game_data.map_templates["profiles"].has(pid):
				errors.append("armor_drops.extras: unknown profile %s" % pid)
		var rw: Dictionary = extra.get("rarity_weights", {})
		if rw.is_empty():
			errors.append("armor_drops.extras: no rarity_weights")
		for r in rw:
			if not rarities.has(r):
				errors.append("armor_drops.extras: no droppable piece of rarity %s" % r)
			if not extra.get("guards", {}).has(r) or not levels.has(extra["guards"][r]):
				errors.append("armor_drops.extras: unknown guard for %s" % r)
	return errors


## Problems in scatter_rules and the profiles' scatter settings.
static func _validate_scatter(game_data: GameData, cfg: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rules: Dictionary = cfg.get("scatter_rules", {})
	if not rules.is_empty():
		var rw: Dictionary = rules.get("resource_weights", {})
		if rw.is_empty():
			errors.append("scatter_rules: no resource_weights")
		for r in rw:
			if not cfg["pile_amounts"].has(r):
				errors.append("scatter_rules: no pile_amounts for %s" % r)
			if float(rw[r]) <= 0.0:
				errors.append("scatter_rules: weight of %s must be > 0" % r)
		var bw: Dictionary = rules.get("band_weights", {})
		if bw.is_empty():
			errors.append("scatter_rules: no band_weights")
		for b in bw:
			if not cfg["distance_bands"].has(b) or float(bw[b]) <= 0.0:
				errors.append("scatter_rules: bad band weight %s" % b)
	for pid in cfg["profiles"]:
		var fill: Dictionary = cfg["profiles"][pid].get("scatter", {})
		if fill.is_empty():
			continue
		if rules.is_empty():
			errors.append("profile %s: scatter needs scatter_rules" % pid)
		if int(fill.get("per_tiles", 0)) <= 0:
			errors.append("profile %s scatter: per_tiles must be > 0" % pid)
		if int(fill.get("min", 0)) < 0 or int(fill.get("max", 99)) < int(fill.get("min", 0)):
			errors.append("profile %s scatter: need 0 <= min <= max" % pid)
	return errors


## Problems in hoard_rules and the profiles' hoards settings.
static func _validate_hoards(game_data: GameData, cfg: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rules: Dictionary = cfg.get("hoard_rules", {})
	var levels: Dictionary = cfg["guard_levels"]
	var bands: Dictionary = cfg["distance_bands"]
	if not rules.is_empty():
		var ratio: Array = rules.get("value_ratio", [])
		if ratio.size() != 2 or float(ratio[0]) <= 0.0 or float(ratio[1]) < float(ratio[0]):
			errors.append("hoard_rules: value_ratio must be [lo, hi] with 0 < lo <= hi")
		var spread := float(rules.get("guard_spread", 0.0))
		if spread < 0.0 or spread >= 1.0:
			errors.append("hoard_rules: guard_spread must be in [0, 1)")
		var rw: Dictionary = rules.get("resource_weights", {})
		if rw.is_empty():
			errors.append("hoard_rules: no resource_weights")
		for r in rw:
			if r != "rare" and not game_data.resources.has(r):
				errors.append("hoard_rules: unknown resource %s" % r)
		var rarities := {}
		for aid in game_data.artifacts:
			if (game_data.artifact_rules.get("drop_slots", []) as Array).has(game_data.artifacts[aid]["slot"]):
				rarities[String(game_data.artifacts[aid]["rarity"])] = true
		for lvl in rules.get("artifact_rarity", {}):
			if not levels.has(lvl):
				errors.append("hoard_rules.artifact_rarity: unknown guard level %s" % lvl)
			if not rarities.has(rules["artifact_rarity"][lvl]):
				errors.append("hoard_rules.artifact_rarity: no droppable piece of rarity %s" % rules["artifact_rarity"][lvl])
	for pid in cfg["profiles"]:
		var fill: Dictionary = cfg["profiles"][pid].get("hoards", {})
		if fill.is_empty():
			continue
		if rules.is_empty():
			errors.append("profile %s: hoards need hoard_rules" % pid)
		if int(fill.get("per_tiles", 0)) <= 0:
			errors.append("profile %s hoards: per_tiles must be > 0" % pid)
		if int(fill.get("min", 0)) < 0 or int(fill.get("max", 99)) < int(fill.get("min", 0)):
			errors.append("profile %s hoards: need 0 <= min <= max" % pid)
		if (fill.get("picks", []) as Array).is_empty():
			errors.append("profile %s hoards: no picks" % pid)
		for pick in fill.get("picks", []):
			if not bands.has(pick.get("band", "")):
				errors.append("profile %s hoards: unknown band %s" % [pid, pick.get("band", "")])
			if not levels.has(pick.get("guard", "")) or int(levels.get(pick.get("guard", ""), 0)) <= 0:
				errors.append("profile %s hoards: guard must be a level above none" % pid)
			if float(pick.get("weight", 1)) <= 0.0:
				errors.append("profile %s hoards: weight must be > 0" % pid)
	return errors


## Shops are opportunities in neutral regions, never hidden blockers on routes.
func _place_cobolts() -> void:
	var saved_rng := rng
	rng = GameRng.new(GameRng.mix(_attempt_seed, _stable_hash("cobolts")))
	var candidates: Array[int] = []
	for z in _zones().size():
		if _zones()[z].has("player"):
			continue
		for i in layout.open_tiles(z):
			if _free_for_object(i) and zone_dist[z][i] >= 0 and not heroes.any(func(hero): return hero["pos"] == [i % w, i / w]):
				candidates.append(i)
	var count := clampi(w * h / 4900, 1, 3)
	for n in count:
		if candidates.is_empty():
			break
		var at := rng.next_int(0, candidates.size() - 1)
		var i := candidates[at]
		candidates.remove_at(at)
		var obj := {"id": _next_id("cobolt") + "_%d" % _attempt_seed, "type": "site", "site": MapCobolts.POSTS[rng.next_int(0, 2)],
			"zone": _zones()[layout.zone_of[i]]["id"]}
		MapCobolts.normalize(obj, data)
		_add_object(obj, i)
	rng = saved_rng
