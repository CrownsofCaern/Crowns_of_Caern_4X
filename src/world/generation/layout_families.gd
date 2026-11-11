class_name LayoutFamilies
extends RefCounted
## Zone graphs ("layout families") for random maps. RandomMapTemplate asks for
## a family's zones and connections in a base orientation; this file then
## jitters the anchors, rolls the width of every open pass, decides which zones
## hold a neutral town and finally turns the whole graph into one of eight
## orientations. All of it is driven by the map seed, so one family never plays
## the same direction or puts its towns on the same tiles twice.
##
## Families (settings in random_maps.families of map_templates.json):
##   ring         starts on a ring around a contested heart, flanks between
##                neighbours, optional rings by size (the classic random map)
##   hub          spokes: each start reaches the heart through its own spoke and
##                has a side valley; neighbours only meet in the heart
##   archipelago  the ring graph cut into islands by thick lakes; passes are
##                land bridges
##   diagonal     two starts in opposite corners; the main road runs corner to
##                corner through the heart, long loops round the other corners
##   lanes        two starts on opposite edges and three parallel lanes between
##                them, with contested valleys on the outer lanes
##   tree         a branching tree: trunk, two branches and a deep dead-end
##                valley per player, one contact through the heart
##
## Zones of the same `group` get identical content (MapGenerator); twins of a
## two-player family are point mirrors (`mirror`), so fairness holds in every
## orientation. A connection with `width: WIDE` and no guard becomes a 2-4 tile
## pass; a guarded connection is always one tile wide (the guard is the
## chokepoint, since there is no zone of control).

const WIDE := -1
const FAMILIES := ["ring", "hub", "archipelago", "diagonal", "lanes", "tree"]
const OPTIONAL_PROFILES := ["wild", "valley", "mineland", "ruins"]
const ORIENTATIONS := 8


## Settings of one family ({} if unknown).
static func family(cfg: Dictionary, id: String) -> Dictionary:
	return RandomMapTemplate.settings(cfg).get("families", {}).get(id, {})


## Family ids from the data, in data order.
static func ids(cfg: Dictionary) -> Array:
	return (RandomMapTemplate.settings(cfg).get("families", {}) as Dictionary).keys()


## True if the family can hold this many players.
static func supports(cfg: Dictionary, id: String, players: int) -> bool:
	var f := family(cfg, id)
	return not f.is_empty() and players >= int(f.get("min_players", 2)) and players <= int(f.get("max_players", 2))


## Families that can hold `players`, in data order.
static func for_players(cfg: Dictionary, players: int) -> Array:
	return ids(cfg).filter(func(id): return supports(cfg, id, players))


## A family for a "mixed" random map, picked by weight from those that fit.
static func pick(cfg: Dictionary, players: int, rng: GameRng) -> String:
	var fits := for_players(cfg, players)
	if fits.is_empty():
		return ""
	var weights := fits.map(func(id): return float(family(cfg, id).get("weight", 1.0)))
	return String(fits[rng.weighted_index(weights)])


## {zones, connections, symmetric} of a family in its base orientation, with
## optional zone profiles rolled; {} if the family is unknown.
static func build_graph(cfg: Dictionary, id: String, players: int, rings: Array, rng: GameRng) -> Dictionary:
	var out := {}
	match id:
		"ring":
			out = _ring(players, rings, rng, false)
		"archipelago":
			out = _ring(players, rings, rng, true)
		"hub":
			out = _hub(players, rng)
		"diagonal":
			out = _diagonal()
		"lanes":
			out = _lanes()
		"tree":
			out = _tree()
		_:
			return {}
	_roll_optional_profiles(cfg, out["zones"], rng)
	_drop_optional_loops(out, float(family(cfg, id).get("loop_chance", 0.5)), rng)
	return out


## Moves every anchor a little (twins stay mirrored), so zone shapes and town
## tiles change from seed to seed.
static func jitter_anchors(zones: Array, amount: float, rng: GameRng) -> void:
	var by_id := {}
	for z in zones:
		by_id[z["id"]] = z
		var mirror := String(z.get("mirror", ""))
		var a: Array = z["anchor"]
		if mirror == "self":
			continue
		if mirror != "" and by_id.has(mirror):
			var m: Array = by_id[mirror]["anchor"]
			z["anchor"] = [snappedf(1.0 - float(m[0]), 0.001), snappedf(1.0 - float(m[1]), 0.001)]
			continue
		z["anchor"] = [snappedf(clampf(float(a[0]) + rng.next_float_range(-amount, amount), 0.06, 0.94), 0.001),
			snappedf(clampf(float(a[1]) + rng.next_float_range(-amount, amount), 0.06, 0.94), 0.001)]


## Gives every WIDE pass a width of `lo`-`hi` tiles (the same within a
## connection group) and keeps every guarded pass one tile wide.
static func roll_widths(conns: Array, lo: int, hi: int, rng: GameRng) -> void:
	var by_group := {}
	for c in conns:
		if String(c.get("guard", "none")) != "none":
			c["width"] = 1
			continue
		if int(c.get("width", 1)) != WIDE:
			continue
		var g := String(c.get("group", "%s-%s" % [c["a"], c["b"]]))
		if not by_group.has(g):
			by_group[g] = rng.next_int(lo, hi)
		c["width"] = int(by_group[g])


## Decides which zone groups hold a neutral town: 0-2 for two players (more
## with more players, never more than the player count), picked by contest
## value, i.e. zones about as far from every start as from the nearest one.
## Writes "town" ("neutral" or "none") and "garrison" on every non-start zone.
static func assign_towns(cfg: Dictionary, zones: Array, conns: Array, players: int, rng: GameRng) -> Array:
	var rule: Dictionary = RandomMapTemplate.settings(cfg).get("neutral_towns", {})
	var weights: Array = rule.get("weights", [1, 3, 2])
	var target := rng.weighted_index(weights)
	target = mini(players, int(round(target * maxf(1.0, players / 2.0))))
	var hops := _hops_from_starts(zones, conns)
	var orbits := {}
	var order: Array = []
	for z in zones:
		if z.has("player"):
			continue
		var g := String(z.get("group", z["id"]))
		if not orbits.has(g):
			orbits[g] = []
			order.append(g)
		orbits[g].append(z)
	var score := {}
	for g in order:
		var total := 0.0
		for z in orbits[g]:
			var d: Array = hops[z["id"]]
			var lo := 9999
			var hi := 0
			for v in d:
				lo = mini(lo, int(v))
				hi = maxi(hi, int(v))
			total += 0.0 if lo < 1 or hi <= 0 else float(lo) / float(hi)
		score[g] = total / float(orbits[g].size())
	var chosen: Array = []
	var left := target
	while left > 0:
		var fits: Array = order.filter(func(g): return not chosen.has(g) and (orbits[g] as Array).size() <= left and float(score[g]) > 0.0)
		if fits.is_empty():
			break
		var g: String = fits[rng.weighted_index(fits.map(func(k): return pow(float(score[k]), 3.0) + 0.01))]
		chosen.append(g)
		left -= (orbits[g] as Array).size()
	var profiles: Dictionary = cfg.get("profiles", {})
	for z in zones:
		if z.has("player"):
			continue
		var g := String(z.get("group", z["id"]))
		if chosen.has(g):
			var prof: Dictionary = profiles.get(z["profile"], {})
			z["town"] = "neutral"
			z["garrison"] = String(prof.get("garrison", "medium")) if String(prof.get("town", "none")) == "neutral" else String(rule.get("garrison", "medium"))
		else:
			z["town"] = "none"
	chosen.sort()
	return chosen


## Turns anchors into one of the eight orientations (rotations and mirrors of
## the square). Point symmetry survives every one of them.
static func orient(zones: Array, orientation: int) -> void:
	for z in zones:
		var a: Array = z["anchor"]
		z["anchor"] = oriented(Vector2(float(a[0]), float(a[1])), orientation)


## One anchor in orientation `o` (0-7): bit 2 swaps the axes, bit 0 mirrors x,
## bit 1 mirrors y.
static func oriented(p: Vector2, o: int) -> Array:
	var q := p
	if o & 4:
		q = Vector2(q.y, q.x)
	if o & 1:
		q.x = 1.0 - q.x
	if o & 2:
		q.y = 1.0 - q.y
	return [snappedf(q.x, 0.001), snappedf(q.y, 0.001)]


## Problems in the families and neutral-town settings.
static func validate(cfg: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rm := RandomMapTemplate.settings(cfg)
	var fams: Dictionary = rm.get("families", {})
	if fams.is_empty():
		errors.append("random_maps: missing families")
	for id in fams:
		var f: Dictionary = fams[id]
		if not FAMILIES.has(id):
			errors.append("random_maps family %s: unknown (known: %s)" % [id, ", ".join(FAMILIES)])
		if String(id).contains("_"):
			errors.append("random_maps family id %s must not contain _" % id)
		if int(f.get("min_players", 2)) < 2 or int(f.get("max_players", 2)) < int(f.get("min_players", 2)):
			errors.append("random_maps family %s: bad player range" % id)
		if float(f.get("weight", 1.0)) <= 0.0:
			errors.append("random_maps family %s: weight must be > 0" % id)
		var walls: Dictionary = f.get("walls", {})
		if float(walls.get("water", 0.0)) < 0.0 or float(walls.get("water", 0.0)) > 1.0:
			errors.append("random_maps family %s: walls.water must be between 0 and 1" % id)
		var thick: Array = walls.get("thick", [0, 0])
		if thick.size() != 2 or int(thick[0]) < 0 or int(thick[1]) < int(thick[0]) or int(thick[1]) > 4:
			errors.append("random_maps family %s: walls.thick must be [lo, hi] with 0 <= lo <= hi <= 4" % id)
	for pid in rm.get("optional_profiles", {}):
		if not OPTIONAL_PROFILES.has(pid) or not cfg.get("profiles", {}).has(pid):
			errors.append("random_maps: optional profile %s is unknown" % pid)
	var nt: Dictionary = rm.get("neutral_towns", {})
	var weights: Array = nt.get("weights", [1, 3, 2])
	if weights.size() != 3 or weights.any(func(v): return float(v) < 0.0):
		errors.append("random_maps: neutral_towns.weights needs three chances for 0, 1 and 2 towns")
	if not cfg.get("guard_levels", {}).has(String(nt.get("garrison", "medium"))):
		errors.append("random_maps: neutral_towns.garrison is not a guard level")
	var pw: Array = rm.get("pass_width", [2, 4])
	if pw.size() != 2 or int(pw[0]) < 2 or int(pw[1]) < int(pw[0]):
		errors.append("random_maps: pass_width must be [lo, hi] with 2 <= lo <= hi")
	return errors


# ---------------------------------------------------------------- families --

static func _zone(id: String, profile: String, anchor: Array, size: float, extra: Dictionary = {}) -> Dictionary:
	var z := {"id": id, "profile": profile, "group": _base(id), "anchor": anchor, "size": size}
	z.merge(extra)
	return z


static func _conn(a: String, b: String, guard: String, width: int, road: bool, optional: bool = false) -> Dictionary:
	var names := [_base(a), _base(b)]
	names.sort()
	var c := {"a": a, "b": b, "guard": guard, "width": width if guard == "none" else 1, "road": road,
		"group": "%s-%s" % names}
	if optional:
		c["optional"] = true
	return c


## "lane_a_0" -> "lane_a"; ids without a player suffix stay as they are.
static func _base(id: String) -> String:
	var k := id.rfind("_")
	return id.substr(0, k) if k > 0 and id.substr(k + 1).is_valid_int() else id


static func _twin(id: String) -> String:
	if id.ends_with("_0"):
		return id.trim_suffix("_0") + "_1"
	if id.ends_with("_1"):
		return id.trim_suffix("_1") + "_0"
	return id


## Two-player families are drawn for player 0 (ids ending in _0) plus shared
## zones; player 1's half is the point mirror.
static func _mirrored(side: Array, shared: Array, conns: Array) -> Dictionary:
	var zones: Array = []
	zones.append_array(side)
	for z in shared:
		z["mirror"] = "self"
		zones.append(z)
	for z in side:
		var m: Dictionary = z.duplicate(true)
		m["id"] = _twin(z["id"])
		m["anchor"] = [snappedf(1.0 - float(z["anchor"][0]), 0.001), snappedf(1.0 - float(z["anchor"][1]), 0.001)]
		m["mirror"] = z["id"]
		if m.has("player"):
			m["player"] = 1
		zones.append(m)
	var out: Array = []
	var seen := {}
	for c in conns:
		for cc in [c, _mirror_conn(c)]:
			var k := _conn_key(cc)
			if not seen.has(k):
				seen[k] = true
				out.append(cc)
	return {"zones": zones, "connections": out, "symmetric": true}


static func _mirror_conn(c: Dictionary) -> Dictionary:
	var m := c.duplicate(true)
	m["a"] = _twin(c["a"])
	m["b"] = _twin(c["b"])
	return m


static func _conn_key(c: Dictionary) -> String:
	var k := [String(c["a"]), String(c["b"])]
	k.sort()
	return "%s|%s" % k


## The classic ring: starts around the heart, a flank zone between each pair
## of neighbours, optional rings (wild backwaters, approaches, outer edges).
## As an archipelago the starts have no pass of their own into the heart: the
## heart island is reached over the flank islands (or an approach island).
static func _ring(n: int, ring_set: Array, rng: GameRng, islands: bool) -> Dictionary:
	var has_wild := ring_set.has("wild")
	var has_approach := ring_set.has("approach")
	var has_outer := ring_set.has("outer")
	var symmetric := n % 2 == 0
	var base := PI * (0.75 if rng.chance(0.5) else 0.25) if n == 2 else rng.next_float_range(0.0, TAU)
	# Ring radii as fractions of the map side (0.5 reaches the edge), tuned so
	# that every linked pair of zones shares a border for 2 to 6 players.
	var r_start := 0.30
	var r_flank := 0.28
	var r_wild := 0.46
	var r_approach := 0.21
	var r_outer := 0.46
	if has_approach:
		r_start = 0.38
		r_flank = 0.22
		r_wild = 0.47
	elif has_wild:
		r_start = 0.29
		r_flank = 0.27
	var half := PI / n
	var zones := []
	var add := func(kind: String, i: int, profile: String, angle: float, radius: float, zsize: float, extra: Dictionary) -> void:
		var z := {"id": "%s_%d" % [kind, i], "profile": profile, "group": kind,
			"anchor": [snappedf(0.5 + radius * cos(angle), 0.001), snappedf(0.5 + radius * sin(angle), 0.001)], "size": zsize}
		if symmetric and i >= n / 2:
			z["mirror"] = "%s_%d" % [kind, i - n / 2]
		z.merge(extra)
		zones.append(z)
	for i in n:
		add.call("start", i, "start", base + TAU * i / n, r_start, 1.25, {"player": i})
	for i in n:
		add.call("flank", i, "flank", base + TAU * i / n + half, r_flank, 1.0, {})
	if has_wild:
		for i in n:
			add.call("wild", i, "wild", base + TAU * i / n, r_wild, 0.85, {"optional": true})
	if has_approach:
		for i in n:
			add.call("approach", i, "wild", base + TAU * i / n, r_approach, 0.8, {})
	if has_outer:
		for i in n:
			add.call("outer", i, "wild", base + TAU * i / n + half, r_outer, 0.85, {"optional": true})
	zones.append({"id": "heart", "profile": "center", "group": "heart", "anchor": [0.5, 0.5],
		"size": 1.2 + 0.1 * n, "mirror": "self"})
	var conns := []
	var link := func(a: String, b: String, width: int, guard: String, road: bool, group: String) -> void:
		conns.append({"a": a, "b": b, "width": width if guard == "none" else 1, "guard": guard, "road": road, "group": group})
	for i in n:
		var prev := (i + n - 1) % n
		link.call("start_%d" % i, "flank_%d" % i, 1, "weak", true, "flank")
		link.call("start_%d" % i, "flank_%d" % prev, 1, "weak", false, "flank_back")
		link.call("flank_%d" % i, "heart", 1, "strong" if islands else "medium", islands, "flank_heart")
		if has_approach:
			link.call("start_%d" % i, "approach_%d" % i, WIDE, "none", true, "approach")
			link.call("approach_%d" % i, "heart", 1, "strong", true, "pass")
		elif not islands:
			link.call("start_%d" % i, "heart", 1, "strong", true, "pass")
		if has_wild:
			link.call("start_%d" % i, "wild_%d" % i, WIDE, "none", false, "back")
		if has_outer:
			link.call("flank_%d" % i, "outer_%d" % i, 1, "medium", false, "outer")
	return {"zones": zones, "connections": conns, "symmetric": symmetric}


## Hub with spokes: start -> spoke -> heart for every player, a side valley off
## each start, no direct contact between neighbours (except optional rim loops).
static func _hub(n: int, rng: GameRng) -> Dictionary:
	var symmetric := n % 2 == 0
	var base := PI * (0.75 if rng.chance(0.5) else 0.25) if n == 2 else rng.next_float_range(0.0, TAU)
	var half := PI / n
	var r_start := 0.38 if n > 2 else 0.33
	var zones := []
	var add := func(kind: String, i: int, profile: String, angle: float, radius: float, zsize: float, extra: Dictionary) -> void:
		var z := {"id": "%s_%d" % [kind, i], "profile": profile, "group": kind,
			"anchor": [snappedf(0.5 + radius * cos(angle), 0.001), snappedf(0.5 + radius * sin(angle), 0.001)], "size": zsize}
		if symmetric and i >= n / 2:
			z["mirror"] = "%s_%d" % [kind, i - n / 2]
		z.merge(extra)
		zones.append(z)
	for i in n:
		add.call("start", i, "start", base + TAU * i / n, r_start, 1.25, {"player": i})
	for i in n:
		add.call("spoke", i, "wild", base + TAU * i / n, 0.19, 0.75, {})
	for i in n:
		add.call("valley", i, "valley", base + TAU * i / n + half, 0.38 if n > 2 else 0.4, 0.9, {"optional": true})
	zones.append({"id": "heart", "profile": "center", "group": "heart", "anchor": [0.5, 0.5],
		"size": 1.0 + 0.1 * n, "mirror": "self"})
	var conns := []
	for i in n:
		var nxt := (i + 1) % n
		conns.append({"a": "start_%d" % i, "b": "spoke_%d" % i, "width": WIDE, "guard": "none", "road": true, "group": "spoke"})
		conns.append({"a": "spoke_%d" % i, "b": "heart", "width": 1, "guard": "strong", "road": true, "group": "pass"})
		conns.append({"a": "start_%d" % i, "b": "valley_%d" % i, "width": 1, "guard": "weak", "road": false, "group": "valley"})
		conns.append({"a": "valley_%d" % i, "b": "spoke_%d" % nxt, "width": 1, "guard": "strong", "road": false,
			"group": "rim", "optional": true})
	return {"zones": zones, "connections": conns, "symmetric": symmetric}


## Corner to corner: the main road runs start -> route -> heart -> route ->
## start along the diagonal; side marches and far corners make long loops.
static func _diagonal() -> Dictionary:
	var side := [
		_zone("start_0", "start", [0.14, 0.86], 1.3, {"player": 0}),
		_zone("route_0", "wild", [0.35, 0.65], 0.9),
		_zone("back_0", "valley", [0.11, 0.5], 0.9, {"optional": true}),
		_zone("march_0", "flank", [0.5, 0.89], 1.0),
		_zone("corner_0", "valley", [0.87, 0.87], 0.85, {"optional": true}),
	]
	var shared := [_zone("heart", "center", [0.5, 0.5], 1.3)]
	var conns := [
		_conn("start_0", "route_0", "none", WIDE, true),
		_conn("route_0", "heart", "strong", 1, true),
		_conn("start_0", "back_0", "none", WIDE, false),
		_conn("start_0", "march_0", "weak", 1, true),
		_conn("march_0", "heart", "medium", 1, false),
		_conn("march_0", "corner_0", "medium", 1, false),
		_conn("corner_0", "back_1", "strong", 1, false, true),
	]
	return _mirrored(side, shared, conns)


## Lanes: starts on opposite edges, a guarded middle road through the heart
## and two outer lanes; halfway along each outer lane lies a contested march,
## and a dead-end valley sits in the corner behind each start.
static func _lanes() -> Dictionary:
	var side := [
		_zone("start_0", "start", [0.5, 0.86], 1.3, {"player": 0}),
		_zone("lane_a_0", "wild", [0.2, 0.72], 0.95),
		_zone("lane_b_0", "wild", [0.8, 0.72], 0.95),
		_zone("march_0", "flank", [0.1, 0.5], 0.8),
		_zone("valley_0", "valley", [0.07, 0.93], 0.6, {"optional": true}),
	]
	var shared := [_zone("heart", "center", [0.5, 0.5], 1.1)]
	var conns := [
		_conn("start_0", "lane_a_0", "none", WIDE, true),
		_conn("start_0", "lane_b_0", "none", WIDE, false),
		_conn("start_0", "heart", "strong", 1, true),
		_conn("lane_a_0", "march_0", "medium", 1, true),
		_conn("lane_b_0", "march_1", "medium", 1, true),
		_conn("lane_a_0", "valley_0", "weak", 1, false),
		_conn("lane_b_0", "heart", "medium", 1, false, true),
	]
	return _mirrored(side, shared, conns)


## Branching tree: start -> trunk -> heart, two branches off the trunk and a
## deep valley at the end of one branch.
static func _tree() -> Dictionary:
	var side := [
		_zone("start_0", "start", [0.12, 0.5], 1.25, {"player": 0}),
		_zone("trunk_0", "wild", [0.31, 0.5], 0.85),
		_zone("branch_a_0", "valley", [0.21, 0.15], 0.9, {"optional": true}),
		_zone("branch_b_0", "valley", [0.21, 0.85], 0.9, {"optional": true}),
		_zone("deep_0", "valley", [0.5, 0.1], 0.8, {"optional": true}),
	]
	var shared := [_zone("heart", "center", [0.5, 0.5], 1.15)]
	var conns := [
		_conn("start_0", "trunk_0", "none", WIDE, true),
		_conn("trunk_0", "heart", "strong", 1, true),
		_conn("trunk_0", "branch_a_0", "weak", 1, false),
		_conn("trunk_0", "branch_b_0", "medium", 1, false),
		_conn("branch_a_0", "deep_0", "strong", 1, false),
		_conn("branch_b_0", "deep_1", "deadly", 1, false, true),
	]
	return _mirrored(side, shared, conns)


# ------------------------------------------------------------------ rolls --

## Optional zones (marked `optional`) get a profile rolled by the weights in
## random_maps.optional_profiles: treasure valleys, mine clusters, ruins or a
## plain backwater. Twins and rings share their group, so they share the roll.
static func _roll_optional_profiles(cfg: Dictionary, zones: Array, rng: GameRng) -> void:
	var table: Dictionary = RandomMapTemplate.settings(cfg).get("optional_profiles", {})
	if table.is_empty():
		return
	var keys := table.keys()
	var weights := keys.map(func(k): return float(table[k]))
	var by_group := {}
	for z in zones:
		if not bool(z.get("optional", false)):
			continue
		var g := String(z.get("group", z["id"]))
		if not by_group.has(g):
			by_group[g] = String(keys[rng.weighted_index(weights)])
		z["profile"] = by_group[g]


## Connections marked `optional` (extra loops) are kept with the family's
## loop chance, rolled once per connection group.
static func _drop_optional_loops(graph: Dictionary, chance: float, rng: GameRng) -> void:
	var keep := {}
	var out: Array = []
	for c in graph["connections"]:
		if not bool(c.get("optional", false)):
			out.append(c)
			continue
		var g := String(c.get("group", ""))
		if not keep.has(g):
			keep[g] = rng.chance(chance)
		if keep[g]:
			out.append(c)
	graph["connections"] = out


## Zone graph hop counts from every start: zone id -> [hops from player 0, ...].
static func _hops_from_starts(zones: Array, conns: Array) -> Dictionary:
	var adj := {}
	for z in zones:
		adj[z["id"]] = []
	for c in conns:
		adj[c["a"]].append(c["b"])
		adj[c["b"]].append(c["a"])
	var out := {}
	for z in zones:
		out[z["id"]] = []
	var starts := zones.filter(func(z): return z.has("player"))
	starts.sort_custom(func(a, b): return int(a["player"]) < int(b["player"]))
	for s in starts:
		var dist := {s["id"]: 0}
		var queue := [s["id"]]
		var head := 0
		while head < queue.size():
			var cur: String = queue[head]
			head += 1
			for nb in adj[cur]:
				if not dist.has(nb):
					dist[nb] = int(dist[cur]) + 1
					queue.append(nb)
		for z in zones:
			out[z["id"]].append(int(dist.get(z["id"], 0)))
	return out
