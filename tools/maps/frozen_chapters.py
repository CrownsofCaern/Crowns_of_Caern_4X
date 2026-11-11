"""Shared steps of the campaign builders that start from a frozen generator map
(map overhaul phase 3): freeze, reorder and set up the player slots, retheme the
terrain per zone, name the towns, place story pieces and scenario objects, then
repaint the cosmetic layer. Used by build_shuttered_halls_maps.py and
build_ashwinter_maps.py; needs Godot (maplib.freeze/apply_setup/redress, $GODOT).

A chapter is described by a dict and built with chapter(spec):
    id, name, source (gen:<template>:<seed>), doc,
    order: optional slot permutation (old slot -> new slot), e.g. so that an ally
           sits next to the player on a ring,
    players: setup players (GameSetup options: type, faction, name, team, difficulty),
    themes: [(zone prefixes or where(d, labels, x, y), terrain mapping)] applied in
            order; the prefix "" matches every labelled tile, EVERYWHERE every tile,
    towns: {town id: name},
    neutral_towns: {town id: (faction, garrison counts per tier)} for unowned towns,
    edit: optional callable(d, labels) for the story pieces,
    dress_seed: seed of the decoration pass.
"""
import json, os
from collections import deque

from maplib import (patchwork, roughen, PASSABLE, COLORS, freeze, apply_setup, redress, zone_map, retheme, objs, obj,
                    free_tile_near, landmark_near, check, _road_tiles)

# Terrain chars: . grass, f forest, d desert, s snow, w swamp, i infernal, r rough,
# ~ river ford, ^ mountain, # water.
TO_ROCK = {".": "r", "d": "r", "s": "r", "f": "r"}            # Forge halls and galleries
TO_ORE = {".": "r", "f": "d", "s": "r"}                       # ore country: rock and slag
TO_SNOW = {".": "s", "d": "s", "i": "r"}                      # Frostmarch: snow on rock, forest stays
TO_HIGH_SNOW = {".": "s", "d": "s", "f": "s", "w": "s", "i": "r"}   # high passes and glacier
TO_FROZEN_FEN = {".": "s", "d": "s", "f": "w", "i": "r", "r": "s"}  # snow over swamp
TO_ASH = {".": "i", "f": "r", "d": "i", "s": "r", "w": "r"}   # the Host's cinder wastes
TO_ASH_ON_SNOW = {".": "i", "s": "i", "d": "i", "f": "r", "w": "r"}   # the Host burning into the snow
TO_DEAD = {".": "w", "d": "w", "s": "w", "i": "r"}            # the dead's fens
TO_GREEN = {"s": ".", "i": "r", "d": "."}                     # Concord farmland
TO_WOOD = {".": "f", "d": "f", "i": "r"}                      # Thornwood
TO_SNOW_WOOD = {".": "s", "d": "s", "i": "r", "w": "f"}       # snow in a forest

TEAM_COLORS = ["#c75c2a", "#7fb0d0", "#8c6bb8", "#4f8a3c"]   # second slot of the same faction


def color_for(faction, used):
    c = COLORS.get(faction, "#888888")
    if c in used:
        c = next(x for x in TEAM_COLORS if x not in used)
    used.add(c)
    return c


def permute(d, order):
    """Moves slot old -> order[old]: owners, hero ids hero_p<old> and start-town ids follow."""
    def new(o):
        return order.get(o, o)
    for h in d["heroes"]:
        h["owner"] = new(int(h["owner"]))
        if h["id"].startswith("hero_p"):
            h["id"] = "hero_p%d" % new(int(h["id"][6:]))
    for o in d["objects"]:
        if int(o.get("owner", -1)) >= 0:
            o["owner"] = new(int(o["owner"]))
        if o["id"].startswith("town_start_"):
            o["id"] = "tmp_" + o["id"]
    for o in d["objects"]:
        if o["id"].startswith("tmp_town_start_"):
            o["id"] = "town_start_%d" % new(int(o["id"][len("tmp_town_start_"):]))
    d["heroes"].sort(key=lambda h: h["id"])


def chapter(spec):
    d = freeze(spec["source"], spec["id"], spec["name"])
    if spec.get("order"):
        permute(d, spec["order"])
    used = set()
    players = []
    for p in spec["players"]:
        p = dict(p)
        p.setdefault("color", color_for(p["faction"], used))
        used.add(p["color"])
        players.append(p)
    d = apply_setup(d, {"players": players})
    labels = zone_map(d)
    for zones, mapping in spec.get("themes", []):
        if callable(zones):
            retheme(d, mapping, lambda x, y: zones(d, labels, x, y))
        else:
            zs = tuple(zones)
            retheme(d, mapping, lambda x, y: labels.get((x, y), "").startswith(zs))
    for tid, (faction, tiers) in spec.get("neutral_towns", {}).items():
        t = obj(d, tid)
        t["town_type"] = faction
        t["garrison"] = army_of(faction, tiers)
    ids = {o["id"] for o in d["objects"]}
    for tid, name in spec.get("towns", {}).items():
        if tid in ids:   # a heart town is rolled by the seed: name it if it is there
            obj(d, tid)["name"] = name
    if spec.get("edit"):
        spec["edit"](d, labels)
    # Wavy biome borders and ground patches: a theme painted per zone otherwise
    # ends in straight wedges across the map.
    patchwork(d, spec.get("dress_seed", 1), spec.get("warp", 6.0))
    d = redress(d, spec.get("dress_seed", 1))
    d["_doc"] = spec["doc"] + " Built from the frozen generator map %s by %s." % (spec["source"], spec.get("builder", "tools/maps"))
    check(d)
    return d


def heart(d):
    """The heart town's tile, or the middle of the map if the seed rolled none."""
    for o in d["objects"]:
        if o["id"] == "town_heart":
            return o["pos"]
    return [d["width"] // 2, d["height"] // 2]


def EVERYWHERE(d, labels, x, y):
    return True


def nearer(slot):
    """where(): tiles closer (straight line) to slot's start town than to any other start town."""
    def where(d, labels, x, y):
        starts = {int(o["id"][11:]): o["pos"] for o in d["objects"] if o["id"].startswith("town_start_")}
        best = min(starts, key=lambda k: ((starts[k][0] - x) ** 2 + (starts[k][1] - y) ** 2, k))
        return best == slot
    return where


def border(a, b, width):
    """where(): tiles about equally far from start towns a and b (a band `width` wide
    where their two halves meet)."""
    def where(d, labels, x, y):
        pa, pb = obj(d, "town_start_%d" % a)["pos"], obj(d, "town_start_%d" % b)["pos"]
        da = ((pa[0] - x) ** 2 + (pa[1] - y) ** 2) ** 0.5
        db = ((pb[0] - x) ** 2 + (pb[1] - y) ** 2) ** 0.5
        return abs(da - db) <= width
    return where


# ---------------------------------------------------------------- geometry --

def walkable(d):
    road = _road_tiles(d)
    w, h = d["width"], d["height"]
    return lambda x, y: 0 <= x < w and 0 <= y < h and (d["terrain"][y][x] in PASSABLE or (x, y) in road)


def steps_from(d, start, blocked=()):
    """Tile -> steps (4-neighbour walk over passable ground and roads)."""
    ok = walkable(d)
    blocked = set(blocked)
    dist = {tuple(start): 0}
    q = deque([tuple(start)])
    while q:
        x, y = q.popleft()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if n not in dist and ok(*n) and n not in blocked:
                dist[n] = dist[(x, y)] + 1
                q.append(n)
    return dist


def used_tiles(d):
    return {tuple(o["pos"]) for o in d["objects"] + d["heroes"]} | _road_tiles(d)


def spot(d, near, lo, hi, zone=None, labels=None, away=(), margin=2, prefer=None):
    """A free passable tile lo..hi steps from near (inside the zone prefix if given),
    at least margin tiles from every object and from the tiles in away.
    prefer(x, y) -> sort key (default: closest to the middle of the band)."""
    dist = steps_from(d, near)
    taken = used_tiles(d) | set(away)
    cands = []
    for p, s in dist.items():
        if not (lo <= s <= hi) or d["terrain"][p[1]][p[0]] not in PASSABLE:
            continue
        if zone and not (labels or {}).get(p, "").startswith(zone):
            continue
        if any(max(abs(p[0] - q[0]), abs(p[1] - q[1])) <= margin for q in taken):
            continue
        cands.append(p)
    if not cands:
        raise ValueError("no spot %d-%d steps from %s" % (lo, hi, near))
    key = prefer or (lambda x, y: (abs(dist[(x, y)] - (lo + hi) / 2), y, x))
    cands.sort(key=lambda p: key(*p))
    return list(cands[0])


def remove(d, ids):
    ids = set(ids)
    d["objects"] = [o for o in d["objects"] if o["id"] not in ids]
    d["heroes"] = [h for h in d["heroes"] if h["id"] not in ids]


def clear_near(d, pos, r, types=("neutral_army", "resource", "artifact")):
    """Removes loose objects within r tiles of pos (to make room for a story piece)."""
    gone = [o["id"] for o in d["objects"] if o["type"] in types
            and max(abs(o["pos"][0] - pos[0]), abs(o["pos"][1] - pos[1])) <= r]
    remove(d, gone)


# ----------------------------------------------------------------- campaign --

CAMPAIGNS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "campaigns.json")
CHAPTER_KEYS = ("map", "setup", "ai", "random_events")


def update_campaign(cid, chapters):
    """Sets the map-side fields (map, setup.players, ai, random_events) of the named
    chapters in data/campaigns.json; story text and casts are left alone.
    chapters: {chapter id: {field: value}} (value None removes the field)."""
    with open(CAMPAIGNS) as f:
        data = json.load(f)
    for ch in data["campaigns"][cid]["chapters"]:
        for key, value in chapters.get(ch["id"], {}).items():
            assert key in CHAPTER_KEYS, key
            if key == "setup":
                setup = ch.get("setup", {})
                setup["players"] = value
                value = setup
            if value is None:
                ch.pop(key, None)
            else:
                ch[key] = value
    with open(CAMPAIGNS, "w") as f:
        f.write(json.dumps(data, indent=2) + "\n")


def setup_players(spec):
    """The chapter's setup players for campaigns.json: the slot roles of the map."""
    return [{k: v for k, v in p.items() if k in ("type", "faction", "name")} for p in spec["players"] if p["type"] != "closed"]


# ---------------------------------------------------------------- scenarios --

BASE = {  # base creatures by tier, tiers 1-8
    "forge": ["forge_thrall", "rivet_crossbowman", "anvil_guard", "slag_golem", "cinder_engineer", "ironhoof_charger", "thunder_bombard", "molten_engine"],
    "frostmarch": ["clan_raider", "rimefang_hound", "oathless_berserker", "tusk_rider", "frost_shaman", "rimeback_aurochs", "cairn_giant", "winter_wyrm"],
    "ashen": ["cinderling", "scorchhound", "brimstone_hurler", "flayer", "ash_witch", "gorgewing", "pyre_titan", "cinder_maw"],
    "hollow": ["shambler", "marrow_archer", "gravecrawler", "wailing_shade", "corpse_weaver", "gibbet_knight", "charnel_hulk", "rotwing_leviathan"],
    "thornwood": ["thorn_skulker", "barkhide_warden", "briar_huntress", "rootbinder", "gloomwing_strix", "spore_lobber", "rootbound_ancient", "wyrdthorn_mother"],
    "concord": ["pike_militia", "longbowman", "shieldwarden", "lancer", "lightbearer", "sunhawk_rider", "bastion_colossus", "iron_margrave"],
}
VILLAGE_SITES = ["fenside_hamlet", "ashfield_steading"]


def army_of(faction, counts):
    """[[creature, n]] for counts per tier (index 0 = tier 1), zero counts left out."""
    return [[BASE[faction][t], n] for t, n in enumerate(counts) if n > 0]


def scale(pairs, f):
    return [[c, max(1, int(round(n * f)))] for c, n in pairs]


def make_townless(d, labels, stocks, guard, garrison, hero_steps=(12, 18), village_steps=(4, 11)):
    """Scenario T on slot 0: its start town turns neutral with this garrison, its mines
    and dwellings go back to the wild, the first hero walks hero_steps away inside the
    start zone (the other slot-0 heroes are cast next to it), and one village per
    entry of stocks ([[creature, n], ...]) stands village_steps from the hero, each
    behind this guard. Returns the village ids."""
    town = obj(d, "town_start_0")
    town["owner"] = -1
    town["garrison"] = garrison
    for o in d["objects"]:
        if o["type"] in ("mine", "site") and int(o.get("owner", -1)) == 0:
            o["owner"] = -1
    lead = obj(d, "hero_p0")
    lead["pos"] = spot(d, town["pos"], hero_steps[0], hero_steps[1], zone="start_0", labels=labels, margin=2,
                       prefer=lambda x, y: (-abs(x - town["pos"][0]) - abs(y - town["pos"][1]), y, x))
    clear_near(d, lead["pos"], 2)
    ids = []
    away = []
    for i, stock in enumerate(stocks):
        p = spot(d, lead["pos"], village_steps[0], village_steps[1], zone="start_0", labels=labels, away=away, margin=2,
                 prefer=lambda x, y, i=i: ((x * 7 + y * 13 + i * 29) % 17, y, x))
        away.append(tuple(p))
        vid = "village_%d" % (i + 1)
        d["objects"].append({"id": vid, "type": "site", "site": VILLAGE_SITES[i % 2], "pos": p, "owner": -1,
                             "stock": stock, "guard": guard})
        ids.append(vid)
    return ids


def wave(i, day, spawn, target, name, cls, army, entry_name, owner=2, warning=3):
    return {"id": "wave_%d" % i, "day": day, "warning_days": warning, "owner": owner, "spawn": list(spawn),
            "entry_tiles": [list(spawn)], "entry_name": entry_name, "target": target, "targets": [target],
            "order": "assault", "hero": {"id": "wave_commander_%d" % i, "name": name, "class": cls, "army": army}}


def place_heroes(d, heroes):
    """Authored heroes for a map that is not cast by its campaign (the finales):
    the first hero of each owner takes the place of hero_p<owner>, the rest stand
    next to it. heroes: [{id, name, class, owner, army}]."""
    first = {}
    for h in heroes:
        h = dict(h)
        owner = int(h["owner"])
        if owner not in first:
            old = obj(d, "hero_p%d" % owner)
            h["pos"] = list(old["pos"])
            remove(d, [old["id"]])
            first[owner] = h["pos"]
        else:
            h["pos"] = list(free_tile_near(d, *first[owner]))
        d["heroes"].append(h)
    d["heroes"].sort(key=lambda h: (h["owner"], h["id"]))


# ------------------------------------------------------- kept hand-made maps --

def rotate(d, clockwise=True):
    """The map turned a quarter: terrain, roads, objects, heroes and decorations."""
    w, h = d["width"], d["height"]
    if clockwise:
        f = lambda x, y: (h - 1 - y, x)
        rows = ["".join(d["terrain"][h - 1 - Y][X] for Y in range(h)) for X in range(w)]
    else:
        f = lambda x, y: (y, w - 1 - x)
        rows = ["".join(d["terrain"][Y][w - 1 - X] for Y in range(h)) for X in range(w)]
    d["terrain"] = rows
    d["width"], d["height"] = h, w
    for o in d["objects"] + d["heroes"] + d.get("decorations", []) + d.get("scenery", []):
        o["pos"] = list(f(*o["pos"]))
    d["roads"] = [{"from": list(f(*s["from"])), "to": list(f(*s["to"]))} for s in d.get("roads", [])]


def _noise(seed, cell):
    import random

    lattice = {}
    def at(i, j):
        if (i, j) not in lattice:
            lattice[(i, j)] = random.Random(seed * 1000003 + i * 7919 + j * 104729).random()
        return lattice[(i, j)]
    def value(x, y):
        fx, fy = x / cell, y / cell
        i, j = int(fx), int(fy)
        tx, ty = fx - i, fy - j
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = at(i, j) * (1 - tx) + at(i + 1, j) * tx
        b = at(i, j + 1) * (1 - tx) + at(i + 1, j + 1) * tx
        return a * (1 - ty) + b * ty
    return value


def patches(d, seed, plan, cell=6, keep_clear=2):
    """Soft secondary-biome patches on a hand-made map, like the terrain painter's
    on generated ones. plan: [(old terrain char, new char, share)]: about share of
    the old ground (by value noise) becomes the new one. Tiles within keep_clear of
    a town, hero or road stay as they are, so starts and roads keep their ground."""
    road = _road_tiles(d)
    clear = set()
    for o in d["objects"] + d["heroes"]:
        r = keep_clear if o.get("type") == "town" or "class" in o else 0
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                clear.add((o["pos"][0] + dx, o["pos"][1] + dy))
    rows = [list(r) for r in d["terrain"]]
    for k, (old, new, share) in enumerate(plan):
        noise = _noise(seed + 31 * k, cell)
        tiles = [(x, y) for y in range(d["height"]) for x in range(d["width"])
                 if rows[y][x] == old and (x, y) not in clear and (x, y) not in road]
        if not tiles:
            continue
        vals = sorted(noise(x, y) for x, y in tiles)
        cut = vals[max(0, int(len(vals) * (1 - share)) - 1)]
        for x, y in tiles:
            if noise(x, y) > cut:
                rows[y][x] = new
    d["terrain"] = ["".join(r) for r in rows]


def repaint_kept(d, seed, plan):
    """patches(), then maplib.dress_handmade: ragged rock edges, wavy borders,
    ground patches and the terrain painter's decoration (authored decorations kept)."""
    patches(d, seed, plan)
    d.pop("decor", None)
    roughen(d, seed)
    patchwork(d, seed, 5.0)   # wider than dress_handmade's 3: the kept maps have big square fields
    check(d)
    d["keep_decorations"] = d.get("decorations", [])
    out = redress(d, seed)
    check(out)
    return out
