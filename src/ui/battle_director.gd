class_name BattleDirector
extends RefCounted
## Choreographs the melee of the 3D battle between the logged blows. The
## combat log stays the truth (BattleViewer still plays every blow, count and
## death from it); the director only decides where each figure of a battalion
## locked in melee stands and whom it fights:
##
## - every figure of an engaged battalion gets a duel with one enemy figure of
##   the battalions it fights, the nearest one that still has room;
## - a big creature has room for several attackers (by footprint), so a giant
##   ends up surrounded instead of facing one man while the rest stand by;
## - each attacker steps into its own place round its foe (spread round the
##   foe's side facing the attacker's army), squares up to it and fights;
## - of two figures that duel each other only one walks (the one from the
##   attacking side), so they do not chase each other round the field.
##
## Pure presentation: no gameplay state, and no randomness at all.

## Field y pixels count this much more than x pixels on the ground (the
## camera looks down at the field, see BattleViewer.ROOM_DEPTH).
const DEPTH := 2.2
## Angles (radians) of the 1st, 2nd, ... attacker's place round its foe,
## from the side that faces the attacker's army.
const SPREAD := [0.0, 0.75, -0.75, 1.5, -1.5, 2.2, -2.2, PI]
## A figure walks to its place when it stands farther than this from it.
const SLACK := 14.0
## Share of the two figures' summed radii between a duelist and its foe.
const CLOSE := 0.95
## A body this many times longer than wide takes its attackers along its
## flanks (a wyrm, a serpent), not round a circle.
const LONG := 1.8
## Extra reach (field pixels) at which a figure that holds its ground still
## swings at its foe.
const REACH := 40.0

## "stack:figure" -> [foe stack key, foe figure, slot round that foe]
var duels: Dictionary = {}
var _skip: Dictionary = {}
var _edges: Dictionary = {}


## How many enemy figures of `own` may fight one figure of `foe` at once: two
## for a foe of the same size, up to SPREAD's size for a giant.
static func room_for(foe_radius: float, own_radius: float) -> int:
	return clampi(int(round(2.0 * foe_radius / maxf(1.0, own_radius))), 2, SPREAD.size())


## The place of the `slot`-th attacker of a foe standing at `foe_at` (field
## pixels), for an attacker whose army stands on side `side` (0 left, 1
## right), with summed radii `radii`.
static func place(foe_at: Vector2, slot: int, side: int, radii: float) -> Vector2:
	var base := PI if side == 0 else 0.0
	var a: float = base + float(SPREAD[slot % SPREAD.size()]) * (1.0 if side == 0 else -1.0)
	var r := radii * CLOSE
	return foe_at + Vector2(cos(a) * r, sin(a) * r / DEPTH)


## The place of the `slot`-th attacker of a block figure at `foe_at` on the
## block's edge facing `out`: outside the block, spread a little along it.
static func edge_place(foe_at: Vector2, out: Vector2, slot: int, radii: float) -> Vector2:
	var a := out.angle() + float(SPREAD[slot % SPREAD.size()]) * 0.6
	var r := radii * CLOSE
	return foe_at + Vector2(cos(a) * r, sin(a) * r / DEPTH)


static func _side(k: String) -> int:
	return int(k.get_slice(":", 0))


static func _id(k: String, i: int) -> String:
	return "%s#%d" % [k, i]


func clear() -> void:
	duels.clear()


## One step of direction. `figs`: stack key -> BattleFigure; `engaged`: keys
## of battalions locked in melee; `groups`: stack key -> {foe key: ...} (who
## fights whom); `held`: the side holding the line, or -1.
## `skip`: stack keys whose figures keep their own places (melee blocks).
## `edges`: block figures on a block's outer edge -> the way out there; other
## figures fight a block only at its edge, from outside.
func step(figs: Dictionary, engaged: Dictionary, groups: Dictionary, held: int, skip: Dictionary = {}, edges: Dictionary = {}) -> void:
	_skip = skip
	_edges = edges
	_drop_stale(figs, engaged, groups)
	var taken := {}   # foe figure id -> {slot: true}
	for d in duels:
		var foe: Array = duels[d]
		var fid := _id(String(foe[0]), int(foe[1]))
		if not taken.has(fid):
			taken[fid] = {}
		taken[fid][int(foe[2])] = true
	var spare := []   # [stack key, figure] without a foe of their own
	for k in engaged:
		var f: BattleFigure = figs.get(k)
		if f == null or f.is_dead() or skip.has(k):
			continue
		var foes: Array = groups.get(k, {}).keys()
		if foes.is_empty():
			continue
		for i in f.alive_members():
			var me := _id(k, i)
			if duels.has(me):
				continue
			if f.is_moving(i):
				continue
			var pick := _pick(f, i, foes, figs, taken, held == _side(k))
			if pick.is_empty():
				spare.append([k, i])
				continue
			var fid := _id(String(pick[0]), int(pick[1]))
			if not taken.has(fid):
				taken[fid] = {}
			var slot := 0
			while taken[fid].has(slot):
				slot += 1
			taken[fid][slot] = true
			duels[me] = [pick[0], pick[1], slot]
	for d in duels.keys():
		if duels.has(d):
			_stand(String(d), figs, held)
	_back_up(spare, figs, held)


## Duels end when either figure falls or the battalions are no longer locked.
func _drop_stale(figs: Dictionary, engaged: Dictionary, groups: Dictionary) -> void:
	var gone := []
	for d in duels:
		var k := String(d).get_slice("#", 0)
		var i := int(String(d).get_slice("#", 1))
		var foe: Array = duels[d]
		var f: BattleFigure = figs.get(k)
		var g: BattleFigure = figs.get(foe[0])
		if f == null or g == null or not engaged.has(k) or not f.is_member_alive(i) \
				or not g.is_member_alive(int(foe[1])) or not groups.get(k, {}).has(foe[0]) \
				or (_skip.has(foe[0]) and not _edges.has(_id(String(foe[0]), int(foe[1])))):
			gone.append(d)
	for d in gone:
		duels.erase(d)


## How many attackers figure j of `g` has room for, against figures of `f`:
## by its footprint, a long body all along its flanks.
static func _room(g: BattleFigure, j: int, f: BattleFigure) -> int:
	var ext := g.member_extent(j)
	if ext.x > ext.y * LONG:
		return SPREAD.size()
	return room_for(maxf(g.member_radius(), ext.y), f.member_radius())


## The enemy figure figure i of `f` should fight: the nearest with room left,
## distance weighed up by how crowded it already is. [] when all are full.
## A figure of a held line only takes on foes already in its reach.
func _pick(f: BattleFigure, i: int, foes: Array, figs: Dictionary, taken: Dictionary, in_reach_only: bool = false) -> Array:
	var at := f.member_pos(i)
	var best: Array = []
	var best_score := INF
	for fk in foes:
		var g: BattleFigure = figs.get(fk)
		if g == null or g.is_dead():
			continue
		for j in g.alive_members():
			if _skip.has(fk) and not _edges.has(_id(String(fk), j)):
				continue   # inside a block: out of reach from outside
			var room := _room(g, j, f)
			var n: int = (taken.get(_id(String(fk), j), {}) as Dictionary).size()
			if n >= room:
				continue
			# Where the foe will stand, not where it passes on its way.
			var gap := g.member_goal(j) - at
			var dist := Vector2(gap.x, gap.y * DEPTH).length()
			if in_reach_only and dist > (f.member_radius() + g.member_radius()) * CLOSE + REACH:
				continue
			var score := dist * (1.0 + float(n) / float(room))
			if score < best_score:
				best_score = score
				best = [fk, j]
	return best


## The place of an attacker in `slot` round a long body (half length/width
## `ext`, facing `look` along x) for an attacker of radius `r`: the head
## first, then along both flanks, the tail last.
static func flank_place(foe_at: Vector2, ext: Vector2, look: float, slot: int, r: float) -> Vector2:
	const SPOTS := [[1.0, 0.0], [0.35, 1.0], [0.35, -1.0], [-0.25, 1.0], [-0.25, -1.0], [0.8, 1.0], [0.8, -1.0], [-1.0, 0.0]]
	var s: Array = SPOTS[slot % SPOTS.size()]
	var along := float(s[0]) * (ext.x + (r * CLOSE if absf(float(s[1])) < 0.5 else 0.0))
	var across := float(s[1]) * (ext.y + r) * CLOSE
	return foe_at + Vector2(look * along, across / DEPTH)


## Puts duelist `me` in its slot round its foe: walks there when it is out of
## place, otherwise squares up and fights.
func _stand(me: String, figs: Dictionary, held: int) -> void:
	var k := me.get_slice("#", 0)
	var i := int(me.get_slice("#", 1))
	var foe: Array = duels[me]
	var f: BattleFigure = figs[k]
	var g: BattleFigure = figs[foe[0]]
	var j := int(foe[1])
	var slot := int(foe[2])
	var foe_at := g.member_pos(j)
	var at := f.member_pos(i)
	f.aim_member(i, foe_at - at)
	if f.is_moving(i) or f.is_striking(i):
		return
	var radii := f.member_radius() + g.member_radius()
	var ext := g.member_extent(j)
	var long := ext.x > ext.y * LONG
	var gap := foe_at - at
	var reach := (ext.x if long else radii * CLOSE) + f.member_radius() + REACH
	var in_reach := Vector2(gap.x, gap.y * DEPTH).length() <= reach
	# Two figures that fight each other: the attacking side's walks, the
	# other holds its ground; a held line never moves.
	var back: Array = duels.get(_id(String(foe[0]), j), [])
	var mutual := not back.is_empty() and String(back[0]) == k and int(back[1]) == i
	var walker := 1 - held if held >= 0 else 0
	if held == _side(k) or (mutual and _side(k) != walker):
		if in_reach:
			f.set_brawling([i], true)
		else:
			# Its foe stepped out of reach: free to take on whoever comes.
			duels.erase(me)
		return
	# The foe's own place, so nobody chases a figure still on its way.
	var base := g.member_goal(j)
	var edge: Vector2 = _edges.get(_id(String(foe[0]), j), Vector2.ZERO)
	var spot := flank_place(base, ext, g.facing_of(j), slot, f.member_radius()) if long \
			else place(base, slot, _side(k), radii)
	if _skip.has(foe[0]) and edge != Vector2.ZERO:
		spot = edge_place(base, edge, slot, radii)
	var off := spot - at
	if Vector2(off.x, off.y * DEPTH).length() > SLACK:
		f.send(i, spot, signf(base.x - spot.x) if base.x != spot.x else f.facing, 0.0, 1.0)
	f.set_brawling([i], true)


## Figures with no foe of their own wait one rank behind a comrade who has
## one, facing the fight (not swinging at air), and step in when a duel ends.
func _back_up(spare: Array, figs: Dictionary, held: int) -> void:
	var backed := {}
	for e in spare:
		var k := String(e[0])
		var i := int(e[1])
		var f: BattleFigure = figs[k]
		var at := f.member_pos(i)
		var best := ""
		var best_d := INF
		for d in duels:
			if not String(d).begins_with(k + "#") or backed.has(d):
				continue
			var c := int(String(d).get_slice("#", 1))
			var dist := f.member_pos(c).distance_to(at)
			if dist < best_d:
				best_d = dist
				best = d
		if best == "":
			continue
		backed[best] = true
		var c := int(best.get_slice("#", 1))
		var foe: Array = duels[best]
		var g: BattleFigure = figs[foe[0]]
		var front := f.member_goal(c)
		var toward := signf(g.member_pos(int(foe[1])).x - front.x)
		if toward == 0.0:
			toward = f.facing
		var spot := front - Vector2(toward * f.member_radius() * 2.0, 0.0)
		f.set_brawling([i], false)
		var off := spot - at
		if held != _side(k) and Vector2(off.x, off.y * DEPTH).length() > SLACK and not f.is_striking(i):
			f.send(i, spot, toward, 0.0, 1.0)
		else:
			f.aim_member(i, Vector2(toward, 0.0))
