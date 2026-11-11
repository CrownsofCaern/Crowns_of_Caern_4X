"""Helpers for rebuilding campaign chapters from frozen generator maps (map
overhaul phase 3), on top of maplib's frozen-map helpers (obj, objs, redress,
landmark_near...). A builder starts from a frozen map (start), repaints its zones
as the story's places (repaint, biome), sets players, towns and heroes, re-rolls
the neutral guards for the new ground (reguard) and writes it re-dressed (finish).
Everything here is deterministic.

Zones: a frozen map keeps the generator's zone list (editor_source.generator.zones,
with anchors) and every generated object carries its zone id. zone_grid() gives
each tile the zone of the nearest anchor, which is exact enough for repainting,
since zones are separated by walls.
"""
import math
import maplib
from maplib import PASSABLE, COLORS, obj

FACTION_UNITS = {
    "concord": ["pike_militia", "longbowman", "shieldwarden", "lancer", "lightbearer", "sunhawk_rider", "bastion_colossus", "iron_margrave"],
    "hollow": ["shambler", "marrow_archer", "gravecrawler", "wailing_shade", "corpse_weaver", "gibbet_knight", "charnel_hulk", "rotwing_leviathan"],
    "forge": ["forge_thrall", "rivet_crossbowman", "anvil_guard", "slag_golem", "cinder_engineer", "ironhoof_charger", "thunder_bombard", "molten_engine"],
    "thornwood": ["thorn_skulker", "barkhide_warden", "briar_huntress", "rootbinder", "gloomwing_strix", "spore_lobber", "rootbound_ancient", "wyrdthorn_mother"],
    "frostmarch": ["clan_raider", "rimefang_hound", "oathless_berserker", "tusk_rider", "frost_shaman", "rimeback_aurochs", "cairn_giant", "winter_wyrm"],
    "ashen": ["cinderling", "scorchhound", "brimstone_hurler", "flayer", "ash_witch", "gorgewing", "pyre_titan", "cinder_maw"],
}
PREFIX = {"concord": "c", "hollow": "h", "forge": "f", "thornwood": "t", "frostmarch": "r", "ashen": "a"}
CLASS = {"concord": "knight", "hollow": "necromancer", "forge": "artificer", "thornwood": "grovewarden",
         "frostmarch": "thane", "ashen": "warlord"}


def gen(d):
    return d["editor_source"]["generator"]


def zone_list(d):
    """The generator's zones; a frozen scenario map has no generator block, so
    its zones are rebuilt from the zone tags of its objects (anchor = the zone's
    town, else the centroid of its objects)."""
    if "generator" in d.get("editor_source", {}):
        return gen(d)["zones"]
    out = {}
    for o in d["objects"]:
        z = o.get("zone")
        if z and z != "townless":
            out.setdefault(z, []).append(o)
    zs = []
    for z in sorted(out):
        towns = [o for o in out[z] if o["type"] == "town"]
        pts = [o["pos"] for o in (towns or out[z])]
        zs.append({"id": z, "anchor": [round(sum(p[0] for p in pts) / len(pts)), round(sum(p[1] for p in pts) / len(pts))]})
    return zs


def zones(d):
    return {z["id"]: z for z in zone_list(d)}


def zone_grid(d):
    """[y][x] -> zone id of the nearest zone anchor."""
    zs = zone_list(d)
    out = []
    for y in range(d["height"]):
        row = []
        for x in range(d["width"]):
            best = min(zs, key=lambda z: ((z["anchor"][0] - x) ** 2 + (z["anchor"][1] - y) ** 2, z["id"]))
            row.append(best["id"])
        out.append(row)
    return out


def repaint(d, plan, default=None):
    """Repaints passable ground per zone. plan: zone id -> biome(...) (default for
    zones not listed). In each zone the most common ground becomes the biome's
    main terrain, the listed (old, new) pairs map the zone's other grounds and
    anything else also becomes the main terrain. Walls (^ #) and fords (~) never change."""
    grid = zone_grid(d)
    rows = [list(r) for r in d["terrain"]]
    counts = {}
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c not in "^#~":
                counts.setdefault(grid[y][x], {}).setdefault(c, 0)
                counts[grid[y][x]][c] += 1
    dominant = {z: max(sorted(cs), key=lambda c: cs[c]) for z, cs in counts.items()}
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c in "^#~":
                continue
            z = grid[y][x]
            b = plan.get(z, default)
            if not b:
                continue
            r[x] = b["main"] if c == dominant[z] else b["others"].get(c, b["main"])
    d["terrain"] = ["".join(r) for r in rows]


def biome(main, others=()):
    """A zone repaint: the zone's most common ground becomes `main`; (old, new)
    pairs keep some texture from its other grounds; the rest becomes `main`."""
    return {"main": main, "others": dict(others)}


def objects_in(d, zone, kind=None):
    return [o for o in d["objects"] if o.get("zone") == zone and (kind is None or o["type"] == kind)]



def drop(d, pred):
    """Removes objects matching pred, and the guards of objects that go (guarded_by)."""
    gone = {o["id"] for o in d["objects"] if pred(o)}
    guards = {o.get("guarded_by") for o in d["objects"] if o["id"] in gone}
    d["objects"] = [o for o in d["objects"] if o["id"] not in gone and o["id"] not in guards]
    for o in d["objects"]:
        if o.get("guarded_by") in gone:
            o.pop("guarded_by")


def set_players(d, players):
    d["players"] = players


AUTHORED = set()   # object ids whose armies a builder set by hand (reguard leaves them)


def keep(o):
    AUTHORED.add(o["id"])
    return o


def town_set(t, faction, name, owner, built=None, garrison=None):
    keep(t)
    t["town_type"] = faction
    t["name"] = name
    t["owner"] = owner
    if built is not None:
        t["built"] = built
    else:
        t.pop("built", None)
    if garrison is not None:
        t["garrison"] = garrison
    elif owner >= 0:
        t.pop("garrison", None)


def buildings(faction, dwellings, extra=()):
    p = PREFIX[faction]
    return ["%s_hall" % p, "%s_tavern" % p if faction != "ashen" else "a_den"] + ["%s_dw%d" % (p, i) for i in range(1, dwellings + 1)] + ["%s_%s" % (p, e) for e in extra]


def troops(faction, counts):
    """counts: one number per tier from 1 -> [[creature, n], ...] (zeros skipped)."""
    return [[FACTION_UNITS[faction][i], n] for i, n in enumerate(counts) if n > 0]


def hero_set(h, hid, name, cls, owner, army_pairs):
    h.update({"id": hid, "name": name, "class": cls, "owner": owner, "army": army_pairs})


def occupied(d):
    s = {tuple(o["pos"]) for o in d["objects"]} | {tuple(h["pos"]) for h in d["heroes"]}
    for e in d.get("scenery", []):
        fw, fh = e.get("footprint", [1, 1])
        for dy in range(fh):
            for dx in range(fw):
                s.add((e["pos"][0] + dx, e["pos"][1] + dy))
    return s


def road_tiles(d):
    out = set()
    for seg in d.get("roads", []):
        (x0, y0), (x1, y1) = seg["from"], seg["to"]
        if x0 == x1 or y0 == y1:
            out.update((x, y) for x in range(min(x0, x1), max(x0, x1) + 1) for y in range(min(y0, y1), max(y0, y1) + 1))
        else:
            out.add((x0, y0)); out.add((x1, y1))
    return out


def passable(d, x, y):
    return 0 <= x < d["width"] and 0 <= y < d["height"] and d["terrain"][y][x] in PASSABLE


def free_near(d, x, y, min_dist=0, avoid_roads=True, margin=1, zone=None, grid=None):
    """The nearest passable, empty tile to (x, y), at least min_dist away, with
    no object within `margin` tiles (Chebyshev); optional zone restriction."""
    occ = occupied(d)
    roads = road_tiles(d) if avoid_roads else set()
    best = None
    for r in range(0, max(d["width"], d["height"])):
        for yy in range(y - r, y + r + 1):
            for xx in range(x - r, x + r + 1):
                if max(abs(xx - x), abs(yy - y)) != r:
                    continue
                if math.hypot(xx - x, yy - y) < min_dist or not passable(d, xx, yy):
                    continue
                if (xx, yy) in roads or (zone and grid and grid[yy][xx] != zone):
                    continue
                if any((xx + dx, yy + dy) in occ for dx in range(-margin, margin + 1) for dy in range(-margin, margin + 1)):
                    continue
                cand = (math.hypot(xx - x, yy - y), yy, xx)
                if best is None or cand < best:
                    best = cand
        if best is not None:
            return [best[2], best[1]]
    raise ValueError("no free tile near %s" % ((x, y),))


def ring(d, cx, cy, radius, kinds, count=None):
    """Authored decorations in a ring around (cx, cy) on open, empty ground."""
    occ = occupied(d) | road_tiles(d)
    have = {tuple(p["pos"]) for p in d.get("decorations", [])}
    n = count or max(6, int(2 * math.pi * radius))
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = round(cx + radius * math.cos(a)), round(cy + radius * math.sin(a))
        if passable(d, x, y) and (x, y) not in occ and (x, y) not in have:
            have.add((x, y))
            out.append({"pos": [x, y], "kind": kinds[i % len(kinds)]})
    d.setdefault("decorations", []).extend(out)
    return out


def scatter(d, cx, cy, radius, kinds, every=3):
    """Authored decorations on a loose grid inside a disc (every `every` tiles)."""
    occ = occupied(d) | road_tiles(d)
    have = {tuple(p["pos"]) for p in d.get("decorations", [])}
    k = 0
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            if (x * 7 + y * 3) % every or math.hypot(x - cx, y - cy) > radius:
                continue
            if passable(d, x, y) and (x, y) not in occ and (x, y) not in have:
                have.add((x, y))
                d.setdefault("decorations", []).append({"pos": [x, y], "kind": kinds[k % len(kinds)]})
                k += 1


STORY_SCENERY = []   # single-tile scenery a builder placed (kept through redress)


def scenery(d, x, y, kind):
    """A single-tile scenery piece from the map scenery library at (x, y), if free."""
    if passable(d, x, y) and (x, y) not in occupied(d) and (x, y) not in road_tiles(d):
        e = {"footprint": [1, 1], "kind": kind, "pos": [x, y]}
        d.setdefault("scenery", []).append(e)
        STORY_SCENERY.append(e)
        return True
    return False


def scenery_near(d, x, y, kinds, n, min_dist=1):
    placed = 0
    for i in range(n * 4):
        if placed >= n:
            break
        p = free_near(d, x + (i % 3 - 1) * (2 + i), y + ((i // 3) % 3 - 1) * (2 + i), min_dist=min_dist, margin=1)
        if scenery(d, p[0], p[1], kinds[placed % len(kinds)]):
            placed += 1


def village(d, oid, pos, site, stock, guard=None, name=None):
    o = keep({"id": oid, "type": "site", "site": site, "pos": pos, "stock": stock})
    if guard:
        o["guard"] = guard
    if name:
        o["name"] = name
    d["objects"].append(o)
    return o


def scale_army(pairs, f):
    return [[c, max(1, round(n * f))] for c, n in pairs]


# --- Guards that fit the repainted ground ------------------------------------
import glob, json, os, zlib

_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CREATURES = {}
for _f in sorted(glob.glob(os.path.join(_ROOT, "data", "creatures", "*.json"))):
    CREATURES.update({k: v for k, v in json.load(open(_f))["creatures"].items() if isinstance(v, dict)})
with open(os.path.join(_ROOT, "data", "factions.json")) as _f:
    _FACTIONS = json.load(_f)
    _FACTIONS = _FACTIONS.get("factions", _FACTIONS)
TERRAIN_ID = {".": "grass", "f": "forest", "d": "desert", "s": "snow", "w": "swamp", "i": "infernal", "r": "rough", "~": "grass"}


def value(cid):
    """MapGenerator.creature_value: gold plus 250 per unit of any other resource."""
    return max(1, sum(n if r == "gold" else n * 250 for r, n in CREATURES[cid]["cost"].items()))


def native(cid, terrain):
    c = CREATURES[cid]
    if terrain in _FACTIONS.get(c["faction"], {}).get("native_terrain", []):
        return True
    return any(float(a) > 0 for a in c.get("terrain", {}).get(terrain, {}).values())


def _pick(cands, key):
    return sorted(cands)[zlib.crc32(key.encode()) % len(cands)]


def reroll(stacks, terrain, factions, key):
    """The same army value in creatures of `factions` (plus "wilds") native to
    `terrain`, tier for tier (falling back to the nearest tier, then to any
    terrain). Base creatures only."""
    out = []
    for i, (cid, n) in enumerate(stacks):
        tier = CREATURES[cid]["tier"]
        pool = [k for k, c in CREATURES.items() if c["faction"] in factions and "upgrade_of" not in c]
        best = None
        for cands in ([k for k in pool if native(k, terrain)], pool):
            for dt in (0, 1, -1, 2, -2):
                tier_c = [k for k in cands if CREATURES[k]["tier"] == tier + dt]
                if tier_c:
                    best = _pick(tier_c, "%s/%d" % (key, i))
                    break
            if best:
                break
        count = max(1, round(n * value(cid) / value(best)))
        merged = next((s for s in out if s[0] == best), None)
        if merged:
            merged[1] += count
        else:
            out.append([best, count])
    return out


def reguard(d, factions, skip=()):
    """Re-rolls every neutral army, mine/site guard and neutral town garrison to
    creatures native to the ground they stand on (see reroll). Names follow."""
    for o in d["objects"]:
        if o["id"] in skip or o["id"] in AUTHORED:
            continue
        x, y = o["pos"]
        terrain = TERRAIN_ID.get(d["terrain"][y][x], "grass")
        if o["type"] == "neutral_army":
            o["stacks"] = reroll(o["stacks"], terrain, factions, o["id"])
            c = CREATURES[o["stacks"][0][0]]
            o["name"] = "%s %s" % (c["name"], {"infantry": "warband", "ranged": "skirmishers", "cavalry": "riders",
                                               "flyer": "flight", "support": "coven", "heavy": "brute"}.get(c.get("role"), "band"))
        elif o["type"] in ("mine", "site") and o.get("guard"):
            o["guard"] = reroll(o["guard"], terrain, factions, o["id"])
        elif o["type"] == "town" and o.get("owner", -1) < 0 and o.get("garrison"):
            o["garrison"] = reroll(o["garrison"], terrain, factions, o["id"])


def start(source, out_id, name, doc):
    """A frozen generator map, renamed and documented, with the generator's
    painted decorations and small scenery removed (finish() repaints them)."""
    AUTHORED.clear()
    STORY_SCENERY.clear()
    d = maplib.freeze(source, out_id, name)
    d["decorations"] = []
    d["scenery"] = [e for e in d.get("scenery", []) if e.get("footprint", [1, 1]) != [1, 1]]
    d.pop("surface", None)
    d["_doc"] = doc + " Frozen from %s and rebuilt by a builder script (see editor_source)." % source
    return d


LANDMARK_BIOME = {"landmark_frozen_cascade": "s", "landmark_cinder_volcano": "i", "landmark_elder_grove": "f"}


def fit_landmarks(d):
    """Generator landmarks follow their zone's old biome; after a repaint a
    frozen cascade may stand in a fen. Swap each for the one that fits the ground
    around it now (the shattered citadel fits anywhere)."""
    for e in d.get("scenery", []):
        if e["kind"] not in LANDMARK_BIOME and e["kind"] != "landmark_shattered_citadel":
            continue
        (x0, y0), (fw, fh) = e["pos"], e["footprint"]
        around = {}
        for y in range(y0 - 2, y0 + fh + 2):
            for x in range(x0 - 2, x0 + fw + 2):
                if 0 <= x < d["width"] and 0 <= y < d["height"] and d["terrain"][y][x] in ".fdswir":
                    around[d["terrain"][y][x]] = around.get(d["terrain"][y][x], 0) + 1
        ground = max(sorted(around), key=lambda c: around[c]) if around else "^"
        if LANDMARK_BIOME.get(e["kind"]) != ground:
            e["kind"] = next((k for k, b in LANDMARK_BIOME.items() if b == ground), "landmark_shattered_citadel")


def finish(out, d, seed, factions):
    """Re-rolls guards to the new ground, fits landmarks, checks reachability,
    repaints the cosmetic layer (maplib.redress keeps the story decorations and
    landmarks; the story's single-tile scenery is put back on top) and writes
    the map. Returns the final dict."""
    reguard(d, factions)
    fit_landmarks(d)
    maplib.check(d)
    d["keep_decorations"] = d.pop("decorations", [])
    d["scenery"] = [e for e in d.get("scenery", []) if e not in STORY_SCENERY]
    d = maplib.redress(d, seed)
    if STORY_SCENERY:
        taken = {tuple(e["pos"]) for e in STORY_SCENERY}
        d["decorations"] = [p for p in d["decorations"] if tuple(p["pos"]) not in taken]
        d["scenery"] = d.get("scenery", []) + STORY_SCENERY
    if out:
        maplib.write(out, d["id"], d)
    return d


def remap_slots(d, mapping):
    """Moves player slots around the map: mapping {old player id: new id}
    re-owns towns, mines, sites and heroes and renames hero_p<old> to hero_p<new>,
    so a start zone can belong to another slot (e.g. put an ally beside the player)."""
    for o in d["objects"] + d["heroes"]:
        if o.get("owner", -1) in mapping:
            o["owner"] = mapping[o["owner"]]
    for h in d["heroes"]:
        if h["id"].startswith("hero_p") and h["id"][6:].isdigit() and int(h["id"][6:]) in mapping:
            h["id"] = "hero_p%d" % mapping[int(h["id"][6:])]
    d["heroes"].sort(key=lambda h: (h["owner"], h["id"]))
    for z in gen(d)["zones"] if "generator" in d.get("editor_source", {}) else []:
        if z.get("player") in mapping:
            z["player"] = mapping[z["player"]]


def landmark_on_mountains(d, x, y, kind, size=4):
    """A large scenery set piece (footprint size x size) on the nearest block of
    mountains to (x, y). Returns its top-left corner."""
    occ = occupied(d)
    best = None
    for yy in range(d["height"] - size + 1):
        for xx in range(d["width"] - size + 1):
            if all(d["terrain"][yy + j][xx + i] == "^" and (xx + i, yy + j) not in occ for i in range(size) for j in range(size)):
                dist = math.hypot(xx + size / 2 - x, yy + size / 2 - y)
                if best is None or dist < best[0]:
                    best = (dist, xx, yy)
    if best is None:
        raise ValueError("no mountain block for %s" % kind)
    d.setdefault("scenery", []).append({"footprint": [size, size], "kind": kind, "pos": [best[1], best[2]]})
    return [best[1], best[2]]


DIRS = {"n": (0, -1), "s": (0, 1), "e": (1, 0), "w": (-1, 0), "ne": (0.7, -0.7), "nw": (-0.7, -0.7), "se": (0.7, 0.7), "sw": (-0.7, 0.7)}


def place_slots(d, wanted):
    """Moves player slots to the start zones that lie in the wanted directions
    from the map centre: wanted = {slot: "n" | "se" | ...}, assigned in slot
    order (see remap_slots). Returns {slot: start zone id}."""
    cx, cy = d["width"] / 2, d["height"] / 2
    starts = {z["player"]: z for z in gen(d)["zones"] if "player" in z}
    free = dict(starts)
    chosen = {}
    for slot in sorted(wanted):
        dx, dy = DIRS[wanted[slot]]
        old = max(sorted(free), key=lambda p: ((free[p]["anchor"][0] - cx) * dx + (free[p]["anchor"][1] - cy) * dy))
        chosen[old] = slot
        del free[old]
    for old, z in free.items():
        chosen[old] = old
    out = {chosen[old]: starts[old]["id"] for old in chosen}
    remap_slots(d, chosen)
    return out


def zone_town(d, zone):
    return next(o for o in d["objects"] if o["type"] == "town" and o.get("zone") == zone)


def coast(d, side="e", sea=2, beach=4):
    """Turns one map edge into sea (`sea` columns of deep water) behind a sandy
    beach (`beach` columns of desert on passable ground). Objects on the new sea
    move onto the beach."""
    w, h = d["width"], d["height"]
    rows = [list(r) for r in d["terrain"]]
    for y in range(h):
        for k in range(sea + beach):
            x = w - 1 - k if side == "e" else k
            if k < sea:
                rows[y][x] = "#"
            elif rows[y][x] in ".fswir":
                rows[y][x] = "d"
    d["terrain"] = ["".join(r) for r in rows]
    for o in d["objects"] + d["heroes"]:
        x, y = o["pos"]
        if rows[y][x] == "#":
            o["pos"] = free_near(d, x - sea - 1 if side == "e" else x + sea + 1, y, margin=0)
    d["roads"] = [s for s in d["roads"] if rows[s["from"][1]][s["from"][0]] != "#" and rows[s["to"][1]][s["to"][0]] != "#"]


def burn_strips(d, n, length, seed):
    """Burned strips (cinder ground) across passable land: n straight strips."""
    import random
    rnd = random.Random(seed)
    rows = [list(r) for r in d["terrain"]]
    occ = occupied(d)
    for _ in range(n):
        x, y = rnd.randrange(d["width"]), rnd.randrange(d["height"])
        dx, dy = rnd.choice([(1, 0), (0, 1), (1, 1), (1, -1)])
        for i in range(length):
            for wdt in (0, 1):
                xx, yy = x + dx * i + (wdt if dy else 0), y + dy * i + (0 if dy else wdt)
                if 0 <= xx < d["width"] and 0 <= yy < d["height"] and rows[yy][xx] in ".fwr":
                    rows[yy][xx] = "i"
    d["terrain"] = ["".join(r) for r in rows]


def update_campaign(campaign, chapters):
    """Points chapters of data/campaigns.json at their rebuilt maps. chapters:
    {chapter id: {"map": map id, "scenario": dict or None}}. The map file
    carries the players (factions, teams, colours); the chapter's "setup" names
    them again, since GameSetup gives unnamed slots their faction's name;
    "scenario" is replaced (None removes it). Story text and casts stay untouched.
    The file is written back in its own layout (json indent 2), so the diff is
    only these fields."""
    path = os.path.join(_ROOT, "data", "campaigns.json")
    with open(path) as f:
        data = json.load(f)
    for ch in data["campaigns"][campaign]["chapters"]:
        if ch["id"] not in chapters:
            continue
        spec = chapters[ch["id"]]
        ch["map"] = spec["map"]
        with open(os.path.join(_ROOT, "data", "maps", spec["map"] + ".json")) as f:
            slots = json.load(f)["players"]
        ch["setup"] = {"players": [{"type": "human" if p["is_human"] else "computer", "faction": p["faction"], "name": p["name"]}
                                   for p in slots]}
        if spec.get("scenario"):
            ch["scenario"] = spec["scenario"]
        else:
            ch.pop("scenario", None)
    with open(path, "w") as f:
        f.write(json.dumps(data, indent=2) + "\n")


def unseal_pockets(d, max_pocket=60):
    """Opens the walled treasure pockets of a sealed generator map (named
    templates before guard_pockets "open"): since #135 a prize next to its guard,
    or named by guarded_by, can't be taken before the guard falls, so the walls
    around the pocket only clutter the map. A pocket is the ground a guarded
    prize reaches without crossing its guard; its wall tiles become ground again
    when they lie inside the pocket's zone and touch no other zone, so zone
    borders and passes stay. Returns the number of pockets opened."""
    grid = zone_grid(d)
    w, h = d["width"], d["height"]
    rows = [list(r) for r in d["terrain"]]
    pos = {o["id"]: tuple(o["pos"]) for o in d["objects"]}
    opened = 0
    for o in d["objects"]:
        g = o.get("guarded_by")
        if not g or g not in pos or o["type"] not in ("resource", "artifact", "mine", "site"):
            continue
        start, block = tuple(o["pos"]), pos[g]
        seen, todo = {start}, [start]
        while todo and len(seen) <= max_pocket:
            x, y = todo.pop()
            for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if q not in seen and q != block and 0 <= q[0] < w and 0 <= q[1] < h and rows[q[1]][q[0]] in PASSABLE:
                    seen.add(q)
                    todo.append(q)
        if len(seen) > max_pocket:
            continue
        zone = grid[start[1]][start[0]]
        ground = rows[start[1]][start[0]] if rows[start[1]][start[0]] in ".fdswir" else "."
        changed = False
        for x, y in list(seen) + [block]:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    tx, ty = x + dx, y + dy
                    if not (0 < tx < w - 1 and 0 < ty < h - 1) or rows[ty][tx] != "^" or grid[ty][tx] != zone:
                        continue
                    if any(grid[ty + j][tx + i] != zone for i in (-1, 0, 1) for j in (-1, 0, 1)):
                        continue
                    rows[ty][tx] = ground
                    changed = True
        opened += changed
    d["terrain"] = ["".join(r) for r in rows]
    return opened


# --- Hand-made maps: texture and dress ---------------------------------------

def _noise(seed, cell):
    """Smooth value noise in [0, 1): bilinear between hashed lattice points."""
    def lattice(i, j):
        return (zlib.crc32(("%d:%d:%d" % (seed, i, j)).encode()) % 10007) / 10007.0

    def at(x, y):
        gx, gy = x / cell, y / cell
        i, j = int(math.floor(gx)), int(math.floor(gy))
        fx, fy = gx - i, gy - j
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = lattice(i, j) * (1 - fx) + lattice(i + 1, j) * fx
        b = lattice(i, j + 1) * (1 - fx) + lattice(i + 1, j + 1) * fx
        return a * (1 - fy) + b * fy
    return at


TEXTURE = {".": ["f", "r"], "f": [".", "w"], "w": ["f", "."], "i": ["r", "d"], "r": [".", "i"], "d": ["r", "i"], "s": ["r", "f"]}


def texture(d, seed, coverage=0.24, cell=6, keep=()):
    """Breaks up large single-biome blocks of a hand-drawn map: noise patches
    of each biome's usual neighbours (TEXTURE) over about `coverage` of its
    open tiles. Walls, water, fords, roads and object tiles keep their ground;
    every patch stays passable, so routes and reachability do not change."""
    n1, n2 = _noise(seed, cell), _noise(seed + 7, cell + 3)
    fixed = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]} | road_tiles(d) | set(keep)
    rows = [list(r) for r in d["terrain"]]
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c not in TEXTURE or (x, y) in fixed:
                continue
            if n1(x, y) > 1.0 - coverage * 1.6:
                r[x] = TEXTURE[c][0 if n2(x, y) < 0.6 else 1]
    d["terrain"] = ["".join(r) for r in rows]


def dress_hand_made(out, mid, seed):
    """Re-dresses a written hand-made map file with the terrain painter
    (maplib.redress), keeping its authored decorations and story sites."""
    path = os.path.join(out, mid + ".json")
    with open(path) as f:
        d = json.load(f)
    d["keep_decorations"] = [p for p in d.get("decorations", []) if "variant" not in p]
    d = maplib.redress(d, seed)
    maplib.write(out, mid, d)


def river_across(d, width=2, fords=None):
    """Deep water across the map between the first two players' starts
    (perpendicular to the line joining their towns), with a ford (~) wherever
    a road crosses it plus `fords` extra crossings. Returns the water tiles."""
    towns = {o["owner"]: o["pos"] for o in d["objects"] if o["type"] == "town" and o.get("owner", -1) in (0, 1)}
    (x0, y0), (x1, y1) = towns[0], towns[1]
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    L = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / L, (y1 - y0) / L
    roads = road_tiles(d)
    occ = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]}
    rows = [list(r) for r in d["terrain"]]
    band = []
    for y in range(d["height"]):
        for x in range(d["width"]):
            if abs((x - cx) * ux + (y - cy) * uy) <= width / 2 and rows[y][x] in ".fdswir":
                band.append((x, y))
    for x, y in band:
        rows[y][x] = "~" if (x, y) in roads or (x, y) in occ else "#"
    # Extra fords spread along the river, then any crossing the reachability needs.
    band.sort(key=lambda p: (p[0] - cx) * -uy + (p[1] - cy) * ux)
    for k in range(fords or 0):
        bx, by = band[(k + 1) * len(band) // ((fords or 0) + 1)]
        for x, y in band:
            if abs((x - bx) * -uy + (y - by) * ux) <= 1.0:
                rows[y][x] = "~"
    # Any ground the river cut off gets a ford of its own, nearest the cut-off part.
    roads = road_tiles(d)
    ok = lambda x, y: 0 <= x < d["width"] and 0 <= y < d["height"] and (rows[y][x] in PASSABLE or (x, y) in roads)
    in_band = set(band)
    while True:
        start = tuple(d["heroes"][0]["pos"])
        reach, todo = {start}, [start]
        while todo:
            x, y = todo.pop()
            for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if q not in reach and ok(*q):
                    reach.add(q); todo.append(q)
        cut = [(x, y) for y in range(d["height"]) for x in range(d["width"]) if ok(x, y) and (x, y) not in reach]
        if not cut:
            break
        cut_set = set(cut)
        cands = [p for p in band if rows[p[1]][p[0]] == "#"
                 and any((p[0] + dx, p[1] + dy) in reach for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2))
                 and any((p[0] + dx, p[1] + dy) in cut_set for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2))]
        if not cands:
            raise ValueError("river_across: %d tiles cut off and no crossing found" % len(cut))
        fx, fy = cut[0]
        bx, by = min(cands, key=lambda p: (abs(p[0] - fx) + abs(p[1] - fy), p))
        for x, y in band:
            if abs(x - bx) <= 1 and abs(y - by) <= 1:
                rows[y][x] = "~"
    d["terrain"] = ["".join(r) for r in rows]
    return band
