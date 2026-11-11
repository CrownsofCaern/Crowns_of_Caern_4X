"""Shared helpers for the hand-made map builders in tools/maps (grid painting,
object constructors, a quick reachability check and the JSON writer)."""
import json, sys

PASSABLE = set(".fdswir~")


class Grid:
    def __init__(s, w, h, fill='.'):
        s.w, s.h = w, h
        s.g = [[fill] * w for _ in range(h)]

    def set(s, x, y, c):
        if 0 <= x < s.w and 0 <= y < s.h:
            s.g[y][x] = c

    def rect(s, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                s.set(x, y, c)

    def blob(s, cx, cy, r, c, squash=1.0):
        for y in range(s.h):
            for x in range(s.w):
                if ((x - cx) ** 2 + ((y - cy) * squash) ** 2) <= r * r + r * 0.6:
                    s.set(x, y, c)

    def rows(s):
        return ["".join(r) for r in s.g]


def roads(pts):
    segs = []
    for a, b in zip(pts, pts[1:]):
        assert a[0] == b[0] or a[1] == b[1], (a, b)
        segs.append({"from": list(a), "to": list(b)})
    return segs


def town(id, x, y, tt, name, owner, built=None, garrison=None):
    o = {"id": id, "type": "town", "pos": [x, y], "town_type": tt, "name": name, "owner": owner}
    if built: o["built"] = built
    if garrison: o["garrison"] = garrison
    return o


def mine(id, x, y, res, guard=None):
    o = {"id": id, "type": "mine", "pos": [x, y], "resource": res}
    if guard: o["guard"] = guard
    return o


def res(id, x, y, r, amt): return {"id": id, "type": "resource", "pos": [x, y], "resource": r, "amount": amt}
def army(id, x, y, name, stacks): return {"id": id, "type": "neutral_army", "pos": [x, y], "name": name, "stacks": stacks}
def enc(id, x, y, e): return {"id": id, "type": "encounter", "pos": [x, y], "encounter": e}
def art(id, x, y, a): return {"id": id, "type": "artifact", "pos": [x, y], "artifact": a}


CONCORD = {"id": 0, "name": "Aldmere Concord", "faction": "concord", "color": "#3d6fc4", "is_human": True}
def hollow(name="The Hollow Dominion"): return {"id": 1, "name": name, "faction": "hollow", "color": "#6b7a5a", "is_human": False}
COLORS = {"concord": "#3d6fc4", "ashen": "#b8402c", "hollow": "#6f8a5a", "thornwood": "#3f7a3a", "forge": "#a8743a", "frostmarch": "#9fc4d8"}
def player(id, name, faction, human=False, color=None, difficulty=None, team=0):
    """A map player slot; color defaults to the faction's (give another for a rival of the same faction).
    difficulty: a data/ai_difficulty.json level for a computer player (absent = the default).
    team: players with the same team above 0 are allies (absent = alone)."""
    p = {"id": id, "name": name, "faction": faction, "color": color or COLORS[faction], "is_human": human}
    if difficulty: p["difficulty"] = difficulty
    if team: p["team"] = team
    return p
def hero(id, name, cls, owner, x, y, army): return {"id": id, "name": name, "class": cls, "owner": owner, "pos": [x, y], "army": army}


def scaled(d, f, piles=(), seed=1):
    """The map drawn larger by factor f (>= 1): every tile becomes a block of tiles,
    so walls, passes and reachability keep their shape; one-tile corridors stay
    one tile wide (along the block's middle line, where objects and roads go). Objects, heroes and road
    ends move to the middle of their tile's block. piles: extra resource piles
    [(resource, amount), ...] spread over the new open ground (at least three tiles
    from anything else, deterministic for the seed) so the larger map is not emptier."""
    import math, random
    assert f >= 1.0
    w, h = d["width"], d["height"]
    W, H = math.ceil(w * f), math.ceil(h * f)
    src = lambda X, n: min(n - 1, int(X / f))
    cols = [[X for X in range(W) if src(X, w) == x] for x in range(w)]
    rows_ = [[Y for Y in range(H) if src(Y, h) == y] for y in range(h)]
    cx = lambda x: cols[x][len(cols[x]) // 2]
    cy = lambda y: rows_[y][len(rows_[y]) // 2]
    out = dict(d)
    out["width"], out["height"] = W, H
    t = d["terrain"]
    def wall_at(x, y):
        return not (0 <= x < w and 0 <= y < h) or t[y][x] not in PASSABLE
    def cell(X, Y):
        # A one-tile corridor (walls on both sides) stays one tile wide: only the
        # block's middle line is open, the rest takes the wall's terrain. There is
        # no zone of control, so a widened pass would let heroes slip past its guard.
        x, y = src(X, w), src(Y, h)
        c = t[y][x]
        if c in PASSABLE:
            if wall_at(x - 1, y) and wall_at(x + 1, y) and X != cx(x):
                return t[y][x - 1] if x > 0 else t[y][x + 1] if x + 1 < w else "^"
            if wall_at(x, y - 1) and wall_at(x, y + 1) and Y != cy(y):
                return t[y - 1][x] if y > 0 else t[y + 1][x] if y + 1 < h else "^"
        return c
    out["terrain"] = ["".join(cell(X, Y) for X in range(W)) for Y in range(H)]
    out["roads"] = [{"from": [cx(s_["from"][0]), cy(s_["from"][1])], "to": [cx(s_["to"][0]), cy(s_["to"][1])]} for s_ in d.get("roads", [])]
    def moved(o):
        o = dict(o)
        o["pos"] = [cx(o["pos"][0]), cy(o["pos"][1])]
        return o
    out["heroes"] = [moved(o) for o in d["heroes"]]
    out["objects"] = [moved(o) for o in d["objects"]]
    road = set()
    for seg in out["roads"]:
        (x0, y0), (x1, y1) = seg["from"], seg["to"]
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                road.add((x, y))
    taken = [tuple(o["pos"]) for o in out["objects"] + out["heroes"]]
    rnd = random.Random(seed)
    free = [(x, y) for y in range(1, H - 1) for x in range(1, W - 1)
            if out["terrain"][y][x] in PASSABLE and (x, y) not in road]
    rnd.shuffle(free)
    n = 0
    for resource, amount in piles:
        for p_ in free:
            if all(max(abs(p_[0] - q[0]), abs(p_[1] - q[1])) >= 3 for q in taken):
                n += 1
                out["objects"].append(res("res_extra_%d" % n, p_[0], p_[1], resource, amount))
                taken.append(p_)
                break
    return out


def enlarge(maps, factors):
    """Scales the named maps (id -> factor) in place with scaled(), adding as many
    extra piles as the existing ones times the area gained (same resources and
    amounts, in their order), and notes the scaling in each map's _doc."""
    for mid, f in factors.items():
        d = maps[mid]
        piles = [o for o in d["objects"] if o["type"] == "resource"]
        n = round((f * f - 1.0) * len(piles))
        extra = [(piles[i % len(piles)]["resource"], piles[i % len(piles)]["amount"]) for i in range(n)]
        big = scaled(d, f, extra, seed=sum(ord(c) for c in mid))
        big["_doc"] = d["_doc"] + " Laid out on a %dx%d grid and drawn %sx larger." % (d["width"], d["height"], f)
        maps[mid] = big


def check(d):
    """Every object and hero on a passable tile, no shared tiles, all reachable from the first hero."""
    rows, w, h = d["terrain"], d["width"], d["height"]
    road = set()
    for seg in d.get("roads", []):
        (x0, y0), (x1, y1) = seg["from"], seg["to"]
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                road.add((x, y))
    ok = lambda x, y: 0 <= x < w and 0 <= y < h and (rows[y][x] in PASSABLE or (x, y) in road)
    assert len(rows) == h and all(len(r) == w for r in rows), "bad terrain size"
    seen, at = set(), {}
    things = d["objects"] + d["heroes"]
    for o in things:
        assert o["id"] not in seen, "duplicate id " + o["id"]
        seen.add(o["id"])
        p = tuple(o["pos"])
        assert ok(*p), "%s on impassable tile %s" % (o["id"], p)
        if p in at:
            assert "class" in o and at[p][0] == "town" and at[p][1] == o["owner"], "%s shares %s" % (o["id"], p)
        at[p] = (o.get("type", "hero"), o.get("owner"))
    start = tuple(d["heroes"][0]["pos"])
    reach, todo = {start}, [start]
    while todo:
        x, y = todo.pop()
        for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if q not in reach and ok(*q):
                reach.add(q); todo.append(q)
    for o in things:
        assert tuple(o["pos"]) in reach, "%s unreachable" % o["id"]
    stranded = sum(1 for y in range(h) for x in range(w) if ok(x, y) and (x, y) not in reach)
    assert stranded == 0, "%d stranded tiles" % stranded


def write(out, mid, d):
    with open(f"{out}/{mid}.json", "w") as f:
        f.write("{\n")
        keys = list(d.keys())
        for i, k in enumerate(keys):
            v = d[k]
            sep = "," if i < len(keys) - 1 else ""
            if k == "terrain":
                f.write(f'  "{k}": [\n' + ",\n".join(f'    "{r}"' for r in v) + f"\n  ]{sep}\n")
            elif k in ("heroes", "objects", "players", "roads"):
                f.write(f'  "{k}": [\n' + ",\n".join("    " + json.dumps(x) for x in v) + f"\n  ]{sep}\n")
            else:
                f.write(f'  "{k}": {json.dumps(v)}{sep}\n')
        f.write("}\n")



# Individually chosen story locations and visual themes. Each arrangement uses
# existing atlas art and is cosmetic; roads, objects and blocking terrain stay clear.
STORY_LANDMARKS = {
    "burning_ford": [("enc_shrine", "cinders"), ("enc_courier", "graves")],
    "ashes_return": [("enc_barrows", "graves"), ("enc_pit", "cinders")],
    "into_the_embers": [("enc_rift", "cinders"), ("enc_hall", "stones")],
    "warm_earth": [("enc_barrows", "graves"), ("enc_chapel", "graves")],
    "twice_dead": [("enc_chapel", "graves"), ("enc_barrows", "graves")],
    "pale_crown": [("enc_barrows", "graves"), ("enc_rift", "cinders")],
    "deep_shift": [("enc_echoes", "stones"), ("enc_barrows", "graves")],
    "fallen_hold": [("enc_echoes", "stones"), ("enc_rift", "cinders")],
    "second_lockstone": [("enc_echoes", "stones"), ("enc_rift", "cinders")],
    "axe_line": [("enc_den", "grove"), ("enc_wagon", "grove")],
    "roots_remember": [("enc_heartroots", "grove"), ("enc_rift", "cinders")],
    "briar_seal": [("enc_wound", "cinders"), ("enc_den", "grove")],
    "sun_goes_out": [("enc_column", "winter"), ("enc_cartographer", "winter")],
    "granary_of_highmere": [("enc_company", "winter"), ("enc_courier", "winter")],
    "bring_the_winter": [("enc_rift", "cinders"), ("enc_shrine", "winter")],
    "pit_below": [("enc_rift", "cinders"), ("enc_champion", "stones")],
    "breaking_the_lockstone": [("enc_lockstone", "stones"), ("enc_shrine", "cinders")],
    "red_sky_throne": [("enc_hall", "stones"), ("enc_shrine", "cinders")],
}

# Each chapter names story anchors and actual interactive sites. Guards are
# explicit: dangerous sites remain challenges rather than free late-game prizes.
STORY_SITES = {
    "greyhold_harvest": [("enc_barrows", "outcast_camp")],
    "knight_who_came_back": [("enc_chapel", "pilgrims_rest"), ("enc_barrows", "oathstone")],
    "burning_ford": [("enc_shrine", "bleeding_rift"), ("enc_courier", "pilgrims_rest")],
    "ashes_return": [("enc_barrows", "outcast_camp"), ("enc_pit", "sellsword_gate")],
    "into_the_embers": [("enc_rift", "bleeding_rift"), ("enc_hall", "pyre_citadel")],
    "warm_earth": [("enc_barrows", "outcast_camp"), ("enc_chapel", "pilgrims_rest")],
    "twice_dead": [("enc_chapel", "pilgrims_rest"), ("enc_barrows", "oathstone")],
    "pale_crown": [("enc_barrows", "outcast_camp"), ("enc_rift", "bleeding_rift")],
    "deep_shift": [("enc_echoes", "oathstone"), ("enc_barrows", "outcast_camp")],
    "fallen_hold": [("enc_echoes", "oathstone"), ("enc_rift", "bleeding_rift")],
    "second_lockstone": [("enc_echoes", "oathstone"), ("enc_rift", "pyre_citadel")],
    "axe_line": [("enc_den", "elder_rings"), ("enc_wagon", "outcast_camp")],
    "roots_remember": [("enc_heartroots", "elder_rings"), ("enc_rift", "bleeding_rift")],
    "briar_seal": [("enc_wound", "bleeding_rift"), ("enc_den", "elder_rings")],
    "sun_goes_out": [("enc_column", "outcast_camp"), ("enc_cartographer", "wardens_causeway")],
    "granary_of_highmere": [("enc_company", "sellsword_gate"), ("enc_courier", "wardens_causeway")],
    "bring_the_winter": [("enc_rift", "pyre_citadel"), ("enc_shrine", "pilgrims_rest")],
    "pit_below": [("enc_rift", "bleeding_rift"), ("enc_champion", "outcast_camp")],
    "breaking_the_lockstone": [("enc_lockstone", "oathstone"), ("enc_shrine", "sellsword_gate")],
    "red_sky_throne": [("enc_hall", "oathstone"), ("enc_shrine", "pyre_citadel")],
}
SITE_GUARDS = {"outcast_camp": [["thornwolf", 12]], "elder_rings": [["thornwolf", 12]],
               "bleeding_rift": [["ashscale_basilisk", 8]],
               "sellsword_gate": [["scorchhound", 18]],
               "pyre_citadel": [["cinder_wraith", 12], ["ashscale_basilisk", 10]]}
SITE_RECRUITS = {"outcast_camp": "thornwolf", "sellsword_gate": "scorchhound", "pyre_citadel": "gibbet_knight"}
SITE_OFFSETS = [(4,0),(-4,0),(0,4),(0,-4),(4,3),(-4,3),(4,-3),(-4,-3),
                (6,0),(-6,0),(0,6),(0,-6),(6,3),(-6,3),(6,-3),(-6,-3)]


LANDMARK_PATTERNS = {
    "graves": [(-3,-2,"gravestone"),(-1,-3,"gravestone"),(2,-3,"dead_tree"),(3,-1,"gravestone"),(-3,1,"dead_tree"),(-2,3,"gravestone"),(1,3,"gravestone"),(3,2,"boulders")],
    "cinders": [(-4,-1,"obsidian"),(-2,-3,"boulders"),(1,-4,"obsidian"),(3,-2,"bones"),(4,1,"obsidian"),(2,3,"boulders"),(-1,4,"bones"),(-3,2,"obsidian")],
    "stones": [(-4,-2,"boulders"),(-2,-2,"boulders"),(2,-2,"boulders"),(4,-2,"boulders"),(-4,2,"boulders"),(-2,2,"gravestone"),(2,2,"gravestone"),(4,2,"boulders")],
    "grove": [(-4,-2,"pines"),(-3,-3,"pines"),(-1,-4,"pines"),(2,-3,"pines"),(4,-1,"pines"),(3,3,"pines"),(0,4,"boulders"),(-3,3,"pines")],
    "winter": [(-4,-2,"snow_pine"),(-2,-4,"snow_pine"),(1,-4,"boulders"),(3,-3,"snow_pine"),(4,1,"snow_pine"),(2,4,"snow_pine"),(-1,4,"boulders"),(-4,2,"snow_pine")],
    # Expansion campaign chapters (tools/maps/build_six_eyes_chapters.py, build_drowned_oath_chapters.py).
    "burned": [(-2,-1,"charred_tree"),(-1,-2,"bones"),(1,-2,"charred_tree"),(2,0,"boulders"),(1,2,"charred_tree"),(-2,1,"bones")],
    "shaft": [(-2,-2,"boulders"),(0,-2,"boulders"),(2,-2,"boulders"),(-2,0,"bones"),(2,0,"boulders"),(-2,2,"boulders"),(2,2,"bones")],
    "cairn": [(-2,-2,"frost_boulders"),(0,-3,"frost_boulders"),(2,-2,"frost_boulders"),(-3,0,"bones"),(3,0,"frost_boulders"),(-2,2,"frost_tree"),(2,2,"frost_boulders")],
    "forge": [(-3,-1,"obsidian"),(-2,-3,"boulders"),(2,-3,"obsidian"),(3,0,"boulders"),(2,3,"charred_tree"),(-2,3,"obsidian")],
}


def add_story_landmarks(maps):
    for mid, d in maps.items():
        plans = STORY_LANDMARKS.get(mid, [])
        site_plans = STORY_SITES.get(mid, [])
        if not plans and not site_plans:
            continue
        objects = {o["id"]: o for o in d["objects"]}
        occupied = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]}
        for seg in d.get("roads", []):
            (x0,y0), (x1,y1) = seg["from"], seg["to"]
            occupied.update((x,y) for x in range(min(x0,x1),max(x0,x1)+1)
                            for y in range(min(y0,y1),max(y0,y1)+1))
        pieces = list(d.get("decorations", []))
        deco_occupied = {tuple(p["pos"]) for p in pieces}
        for anchor, theme in plans:
            assert anchor in objects, (mid, anchor)
            x0, y0 = objects[anchor]["pos"]
            for dx, dy, kind in LANDMARK_PATTERNS[theme]:
                x, y = x0 + dx, y0 + dy
                if 0 <= x < d["width"] and 0 <= y < d["height"] and (x,y) not in occupied and d["terrain"][y][x] in PASSABLE:
                    pieces.append({"pos": [x,y], "kind": kind})
                    occupied.add((x,y))
        for index, (anchor, site_id) in enumerate(site_plans):
            assert anchor in objects, (mid, anchor)
            x0, y0 = objects[anchor]["pos"]
            # Keep the encounter visible beside the building and select the
            # first authored offset with open ground, clear of roads/objects.
            for dx, dy in SITE_OFFSETS:
                x, y = x0 + dx, y0 + dy
                if (0 <= x < d["width"] and 0 <= y < d["height"]
                        and (x,y) not in occupied and d["terrain"][y][x] in PASSABLE):
                    site = {"id": "site_story_%s_%d" % (mid, index + 1), "type": "site", "site": site_id, "pos": [x,y]}
                    if site_id in SITE_GUARDS:
                        site["guard"] = SITE_GUARDS[site_id]
                    if site_id in SITE_RECRUITS:
                        site.update({"owner": -1, "creature": SITE_RECRUITS[site_id]})
                    d["objects"].append(site)
                    occupied.add((x,y))
                    # Leave visual breathing room around the larger building.
                    pieces = [p for p in pieces if max(abs(p["pos"][0]-x), abs(p["pos"][1]-y)) > 2]
                    break
            else:
                raise ValueError("No clear location for %s near %s in %s" % (site_id, anchor, mid))
        d["decorations"] = pieces


def build(maps, out, dress=None):
    """Checks every map, prints its terrain and writes it to out (if given).
    dress: map id -> seed for the maps to paint with dress_handmade()."""
    add_story_landmarks(maps)
    for mid in list(maps):
        d = maps[mid]
        try:
            check(d)
        except AssertionError:
            print(mid + " (with x and y indices, to place objects)")
            print("   " + "".join(str(x % 10) for x in range(d["width"])))
            for y, r in enumerate(d["terrain"]):
                print("%2d %s" % (y, r))
            raise
        if dress and mid in dress:
            d.pop("_story_landmarks", None)
            d = maps[mid] = dress_handmade(d, dress[mid])
        print(mid)
        print("\n".join(d["terrain"]))
        if out:
            write(out, mid, d)


# --- Frozen generator maps ---------------------------------------------------
# Builders can start from a generated map instead of a blank grid:
#     d = maplib.freeze("gen:broad_crossing:311", "ll_ch3_embers")
#     ... move towns, add story objects and scenario fields to d ...
#     maplib.write("data/maps", d["id"], d)
#     maplib.preview(d["id"], "/tmp/ll_ch3_embers.png")
# Both call Godot headless (set $GODOT if it is not on PATH). freeze() never
# touches data/maps itself; it returns the same dict that
# tools/maps/freeze_map.gd would write, and write() produces the same bytes.

import os, subprocess, tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _godot(script, *args):
    cmd = [os.environ.get("GODOT", "godot"), "--headless", "--path", REPO, "--script", script, "--", *args]
    run = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    return run.returncode, run.stdout + run.stderr


def freeze(source_id, out_id, name=None):
    """Generated (or any loadable) map id -> standalone map dict with id out_id."""
    with tempfile.TemporaryDirectory() as tmp:
        args = [source_id, out_id, "--dir", tmp] + (["--name", name] if name else [])
        code, log = _godot("res://tools/maps/freeze_map.gd", *args)
        path = os.path.join(tmp, out_id + ".json")
        if code not in (0, 2) or not os.path.exists(path):
            raise RuntimeError("freeze %s failed:\n%s" % (source_id, log))
        with open(path) as f:
            return json.load(f)


def preview(map_ref, png, tile=6):
    """Minimap PNG of a map id or a .json path (see tools/maps/map_preview.gd)."""
    if map_ref.endswith(".json"):
        map_ref = os.path.abspath(map_ref)
    code, log = _godot("res://tools/maps/map_preview.gd", map_ref, os.path.abspath(png), str(tile))
    if code != 0:
        raise RuntimeError("preview %s failed:\n%s" % (map_ref, log))
    return png


# --- Editing frozen maps -----------------------------------------------------
# Helpers for the campaign builders that start from maplib.freeze(): find
# objects, label the generator's zones, retheme terrain, add story landmarks
# and repaint the cosmetic layer afterwards (redress).

from collections import deque


def obj(d, oid):
    """The object (or hero) with this id."""
    for o in d["objects"] + d["heroes"]:
        if o["id"] == oid:
            return o
    raise KeyError(oid)


def objs(d, type_=None, **match):
    """Objects of a type whose fields equal the keyword arguments."""
    return [o for o in d["objects"] if (type_ is None or o["type"] == type_)
            and all(o.get(k) == v for k, v in match.items())]


def set_tile(d, x, y, c):
    row = d["terrain"][y]
    d["terrain"][y] = row[:x] + c + row[x + 1:]


def zone_map(d):
    """(x, y) -> generator zone name, by walking outward from every object
    that names its zone (objects of a zone sit inside it; walls are mountains
    and water, so the walk stays in the zone until it reaches a pass)."""
    w, h = d["width"], d["height"]
    label = {}
    q = deque()
    for o in sorted(d["objects"], key=lambda o: o["id"]):
        if "zone" in o:
            p = tuple(o["pos"])
            if p not in label:
                label[p] = o["zone"]
                q.append(p)
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in label and d["terrain"][ny][nx] in PASSABLE:
                label[(nx, ny)] = label[(x, y)]
                q.append((nx, ny))
    return label


def retheme(d, mapping, where=None):
    """Replaces terrain chars by mapping {old: new} on the tiles where
    where(x, y) is true (every tile without it)."""
    for y in range(d["height"]):
        row = d["terrain"][y]
        d["terrain"][y] = "".join(mapping.get(c, c) if (where is None or where(x, y)) else c for x, c in enumerate(row))


def retheme_zones(d, zones, mapping, labels=None):
    """retheme() on the tiles of the named zones (zone_map labels)."""
    labels = labels if labels is not None else zone_map(d)
    zs = set(zones)
    retheme(d, mapping, lambda x, y: labels.get((x, y)) in zs)


def _road_tiles(d):
    out = set()
    for seg in d.get("roads", []):
        (x0, y0), (x1, y1) = seg["from"], seg["to"]
        out.update((x, y) for x in range(min(x0, x1), max(x0, x1) + 1) for y in range(min(y0, y1), max(y0, y1) + 1))
    return out


def landmark_fits(d, x, y, size=4, margin=1):
    """True if a size x size landmark at (x, y) covers only open land with
    open land, no object, hero or road within margin tiles around it."""
    used = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]} | _road_tiles(d)
    for yy in range(y - margin, y + size + margin):
        for xx in range(x - margin, x + size + margin):
            if not (0 <= xx < d["width"] and 0 <= yy < d["height"]):
                return False
            inside = x <= xx < x + size and y <= yy < y + size
            if (xx, yy) in used or d["terrain"][yy][xx] not in PASSABLE and (inside or margin > 0):
                return False
    return True


def landmark_near(d, x, y, kind, size=4, radius=20):
    """landmark() at the nearest fitting spot to (x, y); returns its top-left."""
    for r in range(radius + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) == r and landmark_fits(d, x + dx, y + dy, size):
                    before = list(d["terrain"])
                    landmark(d, x + dx, y + dy, kind, size)
                    try:
                        check(d)
                        return x + dx, y + dy
                    except AssertionError:
                        d["terrain"] = before
                        d["scenery"].pop()
                        d["_story_landmarks"].pop()
    raise ValueError("no room for %s near %d,%d" % (kind, x, y))


def landmark(d, x, y, kind, size=4):
    """A large scenery set piece with its top-left at (x, y): the footprint
    becomes impassable ground (as the terrain painter does)."""
    assert landmark_fits(d, x, y, size, 0), "%s does not fit at %d,%d" % (kind, x, y)
    for dy in range(size):
        for dx in range(size):
            set_tile(d, x + dx, y + dy, "^")
    d.setdefault("scenery", []).append({"footprint": [size, size], "kind": kind, "pos": [x, y]})
    d.setdefault("_story_landmarks", []).append([x, y])


def clear_area(d, x, y, r, c=None):
    """Removes painted scenery covering the square of radius r around (x, y)
    and, with c, paints its impassable tiles as c (a clearing for a story
    object)."""
    keep = []
    for e in d.get("scenery", []):
        ex, ey = e["pos"]
        fw, fh = e.get("footprint", [1, 1])
        if ex + fw - 1 >= x - r and ex <= x + r and ey + fh - 1 >= y - r and ey <= y + r:
            if fw > 1:
                for dy in range(fh):
                    for dx in range(fw):
                        set_tile(d, ex + dx, ey + dy, c or ".")
            continue
        keep.append(e)
    d["scenery"] = keep
    if c:
        for yy in range(max(0, y - r), min(d["height"], y + r + 1)):
            for xx in range(max(0, x - r), min(d["width"], x + r + 1)):
                if d["terrain"][yy][xx] not in PASSABLE:
                    set_tile(d, xx, yy, c)


def free_tile_near(d, x, y, taken=(), radius=6):
    """The nearest passable tile to (x, y) with no object, hero or road on it."""
    used = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]} | set(taken)
    for r in range(radius + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                nx, ny = x + dx, y + dy
                if 0 <= nx < d["width"] and 0 <= ny < d["height"] and d["terrain"][ny][nx] in PASSABLE and (nx, ny) not in used:
                    return nx, ny
    raise ValueError("no free tile near %d,%d" % (x, y))


def redress(d, seed):
    """Repaints decorations, ground variants and small scenery after terrain
    or object edits (tools/maps/redress_map.gd); landmarks stay. Returns the
    new dict."""
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = os.path.join(tmp, "in.json"), os.path.join(tmp, "out.json")
        with open(src, "w") as f:
            json.dump(d, f)
        code, log = _godot("res://tools/maps/redress_map.gd", src, dst, str(seed))
        if code not in (0, 2) or not os.path.exists(dst):
            raise RuntimeError("redress failed:\n%s" % log)
        if code == 2:
            print(log)
        with open(dst) as f:
            return json.load(f)


def apply_setup(d, setup):
    """The map with a new-game setup applied (tools/maps/apply_setup.gd, i.e.
    GameSetup.apply: slot factions, names, colours, teams, difficulty; towns and
    heroes of a slot that changes faction convert). Hero ids are kept."""
    with tempfile.TemporaryDirectory() as tmp:
        src, cfg, dst = (os.path.join(tmp, n) for n in ("in.json", "setup.json", "out.json"))
        with open(src, "w") as f:
            json.dump(d, f)
        with open(cfg, "w") as f:
            json.dump(setup, f)
        code, log = _godot("res://tools/maps/apply_setup.gd", src, cfg, dst)
        if code != 0 or not os.path.exists(dst):
            raise RuntimeError("apply_setup failed:\n%s" % log)
        with open(dst) as f:
            return json.load(f)

# Factions on frozen maps: random-map slots alternate Concord and Ashen with
# their native ground; a campaign gives a slot its story faction.
NATIVE = {"concord": ".", "ashen": "i", "thornwood": "f", "forge": "r", "hollow": "w", "frostmarch": "s",
          "darkelf": "r", "fishmen": "w"}
CLASSES = {"concord": "knight", "ashen": "warlord", "thornwood": "grovewarden", "forge": "ironmarshal",
           "hollow": "necromancer", "frostmarch": "thane", "darkelf": "de_dreadmarshal", "fishmen": "fm_tidemarshal"}


def zone_info(d, labels=None):
    """zone -> {tiles, base (most common terrain char), center (x, y)}."""
    labels = labels if labels is not None else zone_map(d)
    acc = {}
    for (x, y), z in labels.items():
        a = acc.setdefault(z, {"tiles": 0, "chars": {}, "sx": 0, "sy": 0})
        a["tiles"] += 1
        a["sx"] += x
        a["sy"] += y
        c = d["terrain"][y][x]
        a["chars"][c] = a["chars"].get(c, 0) + 1
    out = {}
    for z, a in sorted(acc.items()):
        base = max(sorted(a["chars"]), key=lambda c: a["chars"][c])
        out[z] = {"tiles": a["tiles"], "base": base, "center": (a["sx"] // a["tiles"], a["sy"] // a["tiles"])}
    return out


def swap_slots(d, a, b):
    """Swaps two player slots' heroes, towns, mines and sites (positions
    stay, owners change), so slot a starts where slot b did."""
    for o in d["objects"] + d["heroes"]:
        if o.get("owner") == a:
            o["owner"] = b
        elif o.get("owner") == b:
            o["owner"] = a
    for h in d["heroes"]:
        if h["id"] in ("hero_p%d" % a, "hero_p%d" % b):
            h["id"] = "hero_p%d" % h["owner"]
    d["heroes"].sort(key=lambda h: (h["owner"], h["id"]))


def set_players(d, specs, colors=None):
    """Players from [(name, faction, human, team?, difficulty?)]; heroes get
    the faction's class, towns their slot's town type."""
    fac = json.load(open(os.path.join(REPO, "data", "factions.json")))["factions"]
    d["players"] = []
    for i, spec in enumerate(specs):
        name, faction, human = spec[:3]
        team = spec[3] if len(spec) > 3 else 0
        diff = spec[4] if len(spec) > 4 else None
        d["players"].append(player(i, name, faction, human=human, color=fac[faction]["color"], difficulty=diff, team=team))
        for o in d["objects"]:
            if o["type"] == "town" and o.get("owner") == i:
                o["town_type"] = faction


def faction_zone(d, zone, faction, labels=None, info=None):
    """The zone's main ground becomes the faction's native terrain."""
    info = info if info is not None else zone_info(d, labels)
    base = info[zone]["base"]
    if base != NATIVE[faction]:
        retheme_zones(d, [zone], {base: NATIVE[faction]}, labels)


def drop(d, oid):
    d["objects"] = [o for o in d["objects"] if o["id"] != oid]
    d["heroes"] = [h for h in d["heroes"] if h["id"] != oid]


def set_hero(d, hid, name, cls, army, owner=None):
    h = obj(d, hid)
    h.update({"name": name, "class": cls, "army": army})
    if owner is not None:
        h["owner"] = owner
    return h


def village(d, vid, x, y, site, stock, guard, name=None):
    o = {"id": vid, "type": "site", "site": site, "pos": [x, y], "owner": -1, "guard": guard, "stock": stock}
    if name:
        o["name"] = name
    d["objects"].append(o)
    return o


def summary(d, labels=None):
    """Prints zones, towns and heroes of a frozen map (for writing builders)."""
    info = zone_info(d, labels)
    print("%s %dx%d" % (d.get("id"), d["width"], d["height"]))
    for z, i in info.items():
        print("  zone %-10s %5d tiles base %s center %s" % (z, i["tiles"], i["base"], i["center"]))
    for o in d["objects"]:
        if o["type"] == "town":
            print("  town %s %s owner %s zone %s %s" % (o["id"], o["pos"], o.get("owner"), o.get("zone"), o.get("town_type")))
    for h in d["heroes"]:
        print("  hero %s %s owner %s" % (h["id"], h["pos"], h["owner"]))


def _creatures():
    out = {}
    folder = os.path.join(REPO, "data", "creatures")
    for name in sorted(os.listdir(folder)):
        if name.endswith(".json"):
            data = json.load(open(os.path.join(folder, name)))
            for cid, c in data.get("creatures", data).items():
                if isinstance(c, dict):
                    out[cid] = c
    return out


CREATURES = _creatures()


def folk(faction, lo=1, hi=8):
    """Base creatures of a faction within the tiers, lowest tier first."""
    return [cid for t, cid in sorted((c["tier"], cid) for cid, c in CREATURES.items()
            if c.get("faction") == faction and "upgrade_of" not in c and lo <= c["tier"] <= hi)]


def faction_army(faction, max_tier, weeks, top=None):
    """An army of the faction's base creatures up to max_tier: about `weeks`
    of each dwelling's growth, a little less for each tier up."""
    out = []
    for cid in folk(faction, 1, max_tier)[-7:] if top is None else folk(faction, 1, max_tier)[-top:]:
        c = CREATURES[cid]
        out.append([cid, max(1, int(round(c["growth"] * weeks * 0.92 ** (c["tier"] - 1))))])
    return out


def gold_of(stacks):
    return sum(CREATURES[c]["cost"].get("gold", 0) * n for c, n in stacks)


def free_spot(d, x, y, clearance=2, radius=12, taken=()):
    """The nearest tile to (x, y) whose square of `clearance` is open land
    with no object, hero or road (room for a town or a site)."""
    used = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]} | _road_tiles(d) | set(taken)
    for r in range(radius + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                cx, cy = x + dx, y + dy
                ok = True
                for yy in range(cy - clearance, cy + clearance + 1):
                    for xx in range(cx - clearance, cx + clearance + 1):
                        if not (0 <= xx < d["width"] and 0 <= yy < d["height"]) or d["terrain"][yy][xx] not in PASSABLE or (xx, yy) in used:
                            ok = False
                if ok:
                    return cx, cy
    raise ValueError("no free spot near %d,%d" % (x, y))


def deco_pattern(d, x, y, theme):
    """Authored decorations of a LANDMARK_PATTERNS theme around (x, y) that
    survive redress()."""
    used = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]} | _road_tiles(d)
    keep = d.setdefault("keep_decorations", [])
    for dx, dy, kind in LANDMARK_PATTERNS[theme]:
        px, py = x + dx, y + dy
        if 0 <= px < d["width"] and 0 <= py < d["height"] and d["terrain"][py][px] in PASSABLE and (px, py) not in used:
            keep.append({"pos": [px, py], "kind": kind})


TERRAIN_COST = {".": 100, "f": 150, "d": 150, "s": 150, "w": 175, "i": 125, "r": 125, "~": 200}


def move_costs(d, x, y):
    """Movement cost from (x, y) to every reachable tile (8 directions,
    diagonals x1.41, roads at 60; guarded objects do not block)."""
    import heapq
    roads = _road_tiles(d)
    w, h = d["width"], d["height"]
    best = {(x, y): 0}
    heap = [(0, x, y)]
    while heap:
        c, cx, cy = heapq.heappop(heap)
        if c > best.get((cx, cy), 1 << 30):
            continue
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = cx + dx, cy + dy
                if (dx or dy) and 0 <= nx < w and 0 <= ny < h:
                    t = d["terrain"][ny][nx]
                    if t not in PASSABLE and (nx, ny) not in roads:
                        continue
                    if dx and dy and (d["terrain"][cy][nx] not in PASSABLE or d["terrain"][ny][cx] not in PASSABLE):
                        continue
                    step = 60 if (nx, ny) in roads else TERRAIN_COST.get(t, 100)
                    nc = c + int(step * (1.41421356 if dx and dy else 1))
                    if nc < best.get((nx, ny), 1 << 30):
                        best[(nx, ny)] = nc
                        heapq.heappush(heap, (nc, nx, ny))
    return best


def edge_entries(d, zone, edge, labels, count=3):
    """Up to `count` open tiles of a zone on the map edge row/column nearest
    to `edge` ("n", "s", "w", "e"), for wave entries."""
    tiles = [p for p, z in labels.items() if z == zone]
    key = {"n": lambda p: p[1], "s": lambda p: -p[1], "w": lambda p: p[0], "e": lambda p: -p[0]}[edge]
    tiles.sort(key=lambda p: (key(p), p))
    used = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]}
    return [list(p) for p in tiles if p not in used][:count]


VILLAGE_SITES = {"fenside_hamlet": (2, 1.0), "ashfield_steading": (1, 1.5)}   # stock_types, stock_weeks (data/sites.json)


def make_townless(d, slot, town_id, faction, gold, garrison, villages=4, share=0.65, seed=1,
                  village_name=None, guard=None):
    """Townless start (map overhaul "T") on a frozen map, like ScenarioTownless
    but authored: the slot's town turns neutral with `garrison`, the slot's
    mines and sites go wild, the slot's first hero walks 1.0-1.6 days from
    the town (as far from the enemy as possible) and `villages` village sites
    0.3-1.4 days around it sell tier 1-3 folk, scaled so `gold` buys `share`
    of the stock. Returns the village objects."""
    import random
    rng = random.Random(seed)
    move = 1500
    town = obj(d, town_id)
    town["owner"] = -1
    town["garrison"] = garrison
    for o in d["objects"]:
        if o["type"] in ("mine", "site") and o.get("owner") == slot:
            o["owner"] = -1
    hero = [h for h in d["heroes"] if h["owner"] == slot][0]
    enemy_towns = [o for o in d["objects"] if o["type"] == "town" and o.get("owner", -1) not in (-1, slot)]
    enemy = move_costs(d, *enemy_towns[0]["pos"])
    from_town = move_costs(d, *town["pos"])
    used = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]} | _road_tiles(d)

    def open_ok(p):
        x, y = p
        if p in used or d["terrain"][y][x] not in PASSABLE:
            return False
        n = sum(1 for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx or dy) and 0 <= x + dx < d["width"]
                and 0 <= y + dy < d["height"] and d["terrain"][y + dy][x + dx] in PASSABLE)
        return n >= 7 and all(max(abs(x - u[0]), abs(y - u[1])) > 1 for u in used if abs(x - u[0]) <= 1 and abs(y - u[1]) <= 1)

    spots = sorted(p for p, c in from_town.items() if move * 1.0 <= c <= move * 1.6 and open_ok(p)
                   and enemy.get(p, 1 << 30) > c)
    spots.sort(key=lambda p: (-enemy.get(p, 1 << 30), p))
    spot = spots[rng.randrange(max(1, len(spots) // 10))]
    hero["pos"] = list(spot)
    used.add(spot)
    from_hero = move_costs(d, *spot)
    cands = sorted(p for p, c in from_hero.items() if move * 0.3 <= c <= move * 1.4 and open_ok(p)
                   and enemy.get(p, 1 << 30) > c and max(abs(p[0] - town["pos"][0]), abs(p[1] - town["pos"][1])) > 3)
    placed = []
    names = sorted(VILLAGE_SITES)
    pool = folk(faction, 1, 3)
    nxt = rng.randrange(len(pool))
    while len(placed) < villages and cands:
        p = cands[rng.randrange(len(cands))]
        cands = [q for q in cands if max(abs(q[0] - p[0]), abs(q[1] - p[1])) > 5]
        sid = names[len(placed) % len(names)]
        types, weeks = VILLAGE_SITES[sid]
        stock = []
        for i in range(min(types, len(pool))):
            c = pool[(nxt + i) % len(pool)]
            stock.append([c, max(1, int(round(CREATURES[c]["growth"] * weeks)))])
        nxt = (nxt + len(stock)) % len(pool)
        g = guard[len(placed) % len(guard)] if guard else [["thornwolf", 6]]
        placed.append(village(d, "village_%d" % (len(placed) + 1), p[0], p[1], sid, stock, g, village_name))
    assert len(placed) == villages, "only %d villages fit" % len(placed)
    have = sum(gold_of(v["stock"]) for v in placed)
    factor = gold / share / have
    for v in placed:
        for pair in v["stock"]:
            pair[1] = max(1, int(round(pair[1] * factor)))
    return placed


CAMPAIGNS_FILE = os.path.join(REPO, "data", "campaigns.json")


def wire_chapters(campaign, chapters, out):
    """Writes the map overhaul's fields of campaign chapters into
    data/campaigns.json: chapters = {chapter id: {map, setup, scenario, ai}}
    (a value of None removes the field). Only when `out` is data/maps, so a
    trial build into another folder leaves the campaigns alone. Story fields
    (text, intro, outro, cast, rewards) are never touched."""
    if not out or os.path.realpath(out) != os.path.realpath(os.path.join(REPO, "data", "maps")):
        return
    with open(CAMPAIGNS_FILE) as f:
        data = json.load(f)
    for ch in data["campaigns"][campaign]["chapters"]:
        for key, value in chapters.get(ch["id"], {}).items():
            assert key in ("map", "setup", "scenario", "ai"), key
            if value is None:
                ch.pop(key, None)
            elif key in ch:
                ch[key] = value
            else:
                # New keys go right after "setup" (or "map"), like the hand-written chapters.
                items = list(ch.items())
                at = max(i for i, (k, _) in enumerate(items) if k in ("map", "setup", "max_tier", "level_cap")) + 1
                items.insert(at, (key, value))
                ch.clear()
                ch.update(items)
    with open(CAMPAIGNS_FILE, "w") as f:
        f.write(json.dumps(data, indent=2) + "\n")


def frozen_chapter(source, mid, name, doc):
    """A campaign chapter map frozen from a generator id, with its own doc."""
    d = freeze(source, mid, name)
    d["_doc"] = doc
    return d


LANDMARK_BY_GROUND = {"i": "landmark_cinder_volcano", "s": "landmark_frozen_cascade", "f": "landmark_elder_grove"}


def match_landmarks(d, keep=()):
    """After a retheme, gives every large landmark the set piece of the ground
    around it (as the terrain painter picks them): cinder volcano on cinder
    wastes, frozen cascade on snow, elder grove in forest, the shattered
    citadel anywhere else. Story landmarks (positions in keep) stay."""
    for e in d.get("scenery", []):
        fw, fh = e.get("footprint", [1, 1])
        if (fw <= 1 and fh <= 1) or list(e["pos"]) in keep:
            continue
        x0, y0 = e["pos"]
        count = {}
        for y in range(y0 - 2, y0 + fh + 2):
            for x in range(x0 - 2, x0 + fw + 2):
                if 0 <= x < d["width"] and 0 <= y < d["height"] and d["terrain"][y][x] in PASSABLE:
                    c = d["terrain"][y][x]
                    count[c] = count.get(c, 0) + 1
        if count:
            ground = max(sorted(count), key=lambda c: count[c])
            e["kind"] = LANDMARK_BY_GROUND.get(ground, "landmark_shattered_citadel")


def open_guarded_prizes(d, labels=None):
    """The guard rule (#135): a pile, artifact or mine next to a neutral army
    is won by fighting that army, so it needs no rock around it. Clears the
    mountain tiles touching such a prize unless the tile is a wall between two
    zones (its open neighbours belong to different zones) or under a landmark.
    Returns how many tiles were opened."""
    labels = labels if labels is not None else zone_map(d)
    armies = {tuple(o["pos"]) for o in d["objects"] if o["type"] == "neutral_army"}
    covered = set()
    for e in d.get("scenery", []):
        fw, fh = e.get("footprint", [1, 1])
        covered.update((e["pos"][0] + dx, e["pos"][1] + dy) for dx in range(fw) for dy in range(fh))
    opened = 0
    for o in d["objects"]:
        if o["type"] not in ("resource", "artifact", "mine"):
            continue
        x, y = o["pos"]
        near = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
        if not any(p in armies for p in near) and "guarded_by" not in o:
            continue
        for tx, ty in near:
            if not (0 < tx < d["width"] - 1 and 0 < ty < d["height"] - 1) or d["terrain"][ty][tx] != "^" or (tx, ty) in covered:
                continue
            zs, chars = set(), {}
            for nx, ny in ((tx + 1, ty), (tx - 1, ty), (tx, ty + 1), (tx, ty - 1)):
                c = d["terrain"][ny][nx]
                if c in PASSABLE:
                    zs.add(labels.get((nx, ny)))
                    chars[c] = chars.get(c, 0) + 1
            if len(zs) == 1 and chars:
                set_tile(d, tx, ty, max(sorted(chars), key=lambda c: chars[c]))
                labels[(tx, ty)] = next(iter(zs))
                opened += 1
    return opened


def finish_chapter(d, seed, out, lead=None):
    """Checks, repaints (redress) and writes a frozen chapter map. lead
    (name, class, army) renames the player's generated hero, which the
    campaign cast replaces, so the file reads like the chapter."""
    if lead:
        h = [h for h in d["heroes"] if h["owner"] == 0][0]
        h.update({"name": lead[0], "class": lead[1], "army": lead[2]})
    match_landmarks(d, d.pop("_story_landmarks", []))
    opened = open_guarded_prizes(d)
    check(d)
    d = redress(d, seed)
    check(d)
    if out:
        write(out, d["id"], d)
    print("%s %dx%d, %d objects, %d rock tiles opened around guarded prizes" % (d["id"], d["width"], d["height"], len(d["objects"]), opened))
    return d


# --- Hand-made maps: new orientation and a painted look ----------------------
# The kept hand-made layouts are drawn as flat single-biome blocks with ruler
# straight walls. rotate() turns one a quarter, dress_handmade() gives it
# wavy biome borders, patches of related ground, ragged rock edges and the
# terrain painter's decoration, keeping layout, objects, heroes and roads.

def rotate(d, turns=1):
    """Turns the map `turns` quarters clockwise: terrain, roads, objects,
    heroes, decorations, scenery (footprints swap) and story landmarks."""
    for _ in range(turns % 4):
        w, h = d["width"], d["height"]
        p = lambda x, y: [h - 1 - y, x]
        d["terrain"] = ["".join(d["terrain"][h - 1 - y][x] for y in range(h)) for x in range(w)]
        d["width"], d["height"] = h, w
        for seg in d.get("roads", []):
            seg["from"], seg["to"] = p(*seg["from"]), p(*seg["to"])
        for o in d["objects"] + d["heroes"] + d.get("decorations", []) + d.get("keep_decorations", []):
            o["pos"] = p(*o["pos"])
        for e in d.get("scenery", []):
            fw, fh = e.get("footprint", [1, 1])
            x, y = e["pos"]
            e["pos"] = [h - y - fh, x]
            if "footprint" in e:
                e["footprint"] = [fh, fw]
        d["_story_landmarks"] = [p(*q) for q in d.get("_story_landmarks", [])]
    return d


def _lattice(seed, x, y):
    v = (x * 374761393 + y * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFF) / 65535.0


def noise(seed, x, y, scale):
    """Smooth value noise in [0, 1], deterministic."""
    fx, fy = x / scale, y / scale
    x0, y0 = int(fx // 1), int(fy // 1)
    tx, ty = fx - x0, fy - y0
    sx, sy = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a, b = _lattice(seed, x0, y0), _lattice(seed, x0 + 1, y0)
    c, e = _lattice(seed, x0, y0 + 1), _lattice(seed, x0 + 1, y0 + 1)
    return (a + (b - a) * sx) + ((c + (e - c) * sx) - (a + (b - a) * sx)) * sy


# Ground that patches each main ground: (patch ground, noise scale, share).
PATCHES = {
    ".": [("f", 6.0, 0.16), ("r", 5.0, 0.07)],
    "f": [(".", 5.0, 0.14), ("w", 6.0, 0.06)],
    "i": [("r", 5.0, 0.15), ("d", 7.0, 0.05)],
    "r": [("i", 6.0, 0.10), (".", 5.0, 0.08)],
    "w": [("f", 5.0, 0.15), (".", 6.0, 0.06)],
    "d": [("r", 5.0, 0.14)],
    "s": [("r", 5.0, 0.12)],
}


def _blocked_near(d, r):
    """Tiles within Chebyshev distance r of an object, hero or road."""
    pts = [tuple(o["pos"]) for o in d["objects"] + d["heroes"]] + list(_road_tiles(d))
    out = set()
    for x, y in pts:
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                out.add((x + dx, y + dy))
    return out


def _covered(d):
    out = set()
    for e in d.get("scenery", []):
        fw, fh = e.get("footprint", [1, 1])
        out.update((e["pos"][0] + dx, e["pos"][1] + dy) for dx in range(-1, fw + 1) for dy in range(-1, fh + 1))
    return out


def roughen(d, seed):
    """Ragged rock edges. Adds rock beside walls where the open ground stays at
    least five tiles wide across (never next to objects, roads or landmarks),
    and cuts single notches into walls at least five tiles thick, so no
    passage opens or closes. Authored decorations keep their open tile.
    Returns (added, cut)."""
    w, h, t = d["width"], d["height"], d["terrain"]
    near, cov = _blocked_near(d, 2), _covered(d)
    near |= {tuple(p["pos"]) for p in d.get("decorations", [])}
    rock = lambda x, y: not (0 <= x < w and 0 <= y < h) or t[y][x] in "^#"
    dirs = ((1, 0), (-1, 0), (0, 1), (0, -1))
    add, cut = [], []
    for y in range(h):
        for x in range(w):
            if (x, y) in near or (x, y) in cov:
                continue
            n = noise(seed, x, y, 3.0)
            c = t[y][x]
            if c in PASSABLE and c != "~" and n > 0.62:
                walls = [dd for dd in dirs if rock(x + dd[0], y + dd[1])]
                if walls and all(not rock(x - dx * k, y - dy * k) for dx, dy in walls for k in range(1, 6)):
                    add.append((x, y))
            elif c == "^" and 0 < x < w - 1 and 0 < y < h - 1 and n < 0.30:
                opens = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx or dy) and not rock(x + dx, y + dy)]
                if not opens:
                    continue
                for dx, dy in dirs:
                    if not rock(x + dx, y + dy) and all(ox * dx + oy * dy > 0 for ox, oy in opens) \
                            and all(rock(x - dx * k, y - dy * k) and 0 < x - dx * k < w - 1 and 0 < y - dy * k < h - 1 for k in range(1, 5)):
                        cut.append((x, y, t[y + dy][x + dx]))
                        break
    # Isolated notches only: a cut tile never touches another cut tile.
    taken, cuts = set(), []
    for x, y, c in cut:
        if any((x + dx, y + dy) in taken for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
            continue
        taken.add((x, y))
        cuts.append((x, y, c))
    rows = [list(r) for r in t]
    for x, y in add:
        rows[y][x] = "^"
    for x, y, c in cuts:
        rows[y][x] = c
    # Added rock must not strand a pocket of open ground: give back the rock
    # beside any tile the first hero can no longer reach.
    added = set(add)
    road = _road_tiles(d)
    while True:
        open_ = lambda x, y: 0 <= x < w and 0 <= y < h and (rows[y][x] in PASSABLE or (x, y) in road)
        start = tuple(d["heroes"][0]["pos"])
        reach, todo = {start}, [start]
        while todo:
            x, y = todo.pop()
            for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if q not in reach and open_(*q):
                    reach.add(q); todo.append(q)
        back = {q for y in range(h) for x in range(w) if open_(x, y) and (x, y) not in reach
                for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if q in added}
        if not back:
            break
        for x, y in back:
            rows[y][x] = t[y][x]
            added.discard((x, y))
    d["terrain"] = ["".join(r) for r in rows]
    return len(added), len(cuts)


def patchwork(d, seed, warp=3.0):
    """Wavy borders between grounds (each open tile takes the ground of a
    tile up to `warp` tiles away along a smooth noise field) and patches of
    related ground (PATCHES). Rock, water and fords stay; tiles under objects
    keep their ground."""
    w, h, t = d["width"], d["height"], d["terrain"]
    keep = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]}
    rows = [list(r) for r in t]
    ground = lambda c: c in PASSABLE and c != "~"
    for y in range(h):
        for x in range(w):
            if not ground(t[y][x]) or (x, y) in keep:
                continue
            sx = x + round((noise(seed + 11, x, y, 7.0) - 0.5) * 2 * warp)
            sy = y + round((noise(seed + 23, x, y, 7.0) - 0.5) * 2 * warp)
            c = t[sy][sx] if 0 <= sx < w and 0 <= sy < h and ground(t[sy][sx]) else t[y][x]
            for i, (patch, scale, share) in enumerate(PATCHES.get(c, [])):
                if noise(seed + 101 * (i + 1), x, y, scale) > 1.0 - share * 1.6:
                    c = patch
                    break
            rows[y][x] = c
    d["terrain"] = ["".join(r) for r in rows]


def dress_handmade(d, seed):
    """Paints a kept hand-made map (see the section header) and returns the
    redressed dict. The authored decorations stay."""
    added, cut = roughen(d, seed)
    patchwork(d, seed)
    check(d)
    d["keep_decorations"] = d.get("decorations", [])
    d = redress(d, seed)
    check(d)
    print("%s dressed: %d rock tiles added, %d notches cut" % (d["id"], added, cut))
    return d
