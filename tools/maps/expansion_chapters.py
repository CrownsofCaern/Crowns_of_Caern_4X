"""Helpers shared by the expansion campaign chapter builders
(build_six_eyes_chapters.py, build_drowned_oath_chapters.py): the story's
chapter setup as map players, and spots along a road for story decoration."""
import json, math, os

from maplib import CAMPAIGNS_FILE, _road_tiles, set_players


def story_setup(campaign, chapter_id, teams=None, extra=()):
    """The chapter's setup players from data/campaigns.json (names and factions
    are the story's), with teams set when given and extra slots appended."""
    with open(CAMPAIGNS_FILE) as f:
        data = json.load(f)
    ch = [c for c in data["campaigns"][campaign]["chapters"] if c["id"] == chapter_id][0]
    added = {p["name"] for p in extra}   # a rebuild finds them in the setup it wrote last time
    players = [dict(p) for p in ch["setup"]["players"] if p["name"] not in added] + [dict(p) for p in extra]
    for i, t in enumerate(teams or []):
        if t:
            players[i]["team"] = t
        else:
            players[i].pop("team", None)
    return {"players": players}


def apply_setup(d, setup):
    """Map players from a setup (names, factions, teams, difficulty)."""
    set_players(d, [(p["name"], p["faction"], p["type"] == "human", p.get("team", 0), p.get("difficulty"))
                    for p in setup["players"]])


def road_points(d, a, b, n):
    """n road tiles spread between points a and b (by their projection on the
    line a-b, from 25% to 75%), near that line."""
    (ax, ay), (bx, by) = a, b
    L2 = float((bx - ax) ** 2 + (by - ay) ** 2) or 1.0
    cands = []
    for x, y in sorted(_road_tiles(d)):
        t = ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / L2
        if 0.2 <= t <= 0.8:
            px, py = ax + t * (bx - ax), ay + t * (by - ay)
            dist = math.hypot(x - px, y - py)
            if dist <= 12:
                cands.append((t, dist, x, y))
    out = []
    for k in range(n):
        target = 0.25 + 0.5 * k / max(1, n - 1)
        best = min(cands, key=lambda c: (abs(c[0] - target) + c[1] / 40.0, c[2], c[3]))
        out.append((best[2], best[3]))
    return out


def coast(d, side, sea=3, beach=3):
    """Turns one map edge ("n", "s", "w", "e") into sea (`sea` rows of deep
    water) behind a sandy beach; objects on the new sea step onto the beach
    and roads into it end at the shore."""
    from maplib import set_tile, free_tile_near
    w, h = d["width"], d["height"]
    depth = {"n": lambda x, y: y, "s": lambda x, y: h - 1 - y, "w": lambda x, y: x, "e": lambda x, y: w - 1 - x}[side]
    for y in range(h):
        for x in range(w):
            k = depth(x, y)
            if k < sea:
                set_tile(d, x, y, "#")
            elif k < sea + beach and d["terrain"][y][x] in ".fswir":
                set_tile(d, x, y, "d")
    for o in d["objects"] + d["heroes"]:
        x, y = o["pos"]
        if d["terrain"][y][x] == "#":
            o["pos"] = list(free_tile_near(d, x, y, radius=sea + beach + 3))
    keep = []
    for seg in d.get("roads", []):
        (x0, y0), (x1, y1) = seg["from"], seg["to"]
        if d["terrain"][y0][x0] != "#" and d["terrain"][y1][x1] != "#":
            keep.append(seg)
    d["roads"] = keep


def lagoon(d, x, y, r=1.8):
    """A small pool of deep water (a reef lagoon) centred on (x, y): the nearest
    spot with room for it. Returns the centre."""
    from maplib import free_spot, set_tile
    cx, cy = free_spot(d, x, y, clearance=int(r) + 1, radius=20)
    for yy in range(cy - 3, cy + 4):
        for xx in range(cx - 3, cx + 4):
            if (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r:
                set_tile(d, xx, yy, "#")
    return cx, cy


def add_town(d, tid, near, faction, name, owner, built, garrison=None):
    """A new town at the nearest open spot to `near`."""
    from maplib import free_spot, town
    x, y = free_spot(d, near[0], near[1], clearance=2, radius=20)
    t = town(tid, x, y, faction, name, owner, built, garrison)
    d["objects"].append(t)
    return t


def wave(wid, day, owner, entries, entry_name, target, targets, hero_id, hero_name, cls, army, warning=3):
    """One invasion wave (ScenarioWaves, tw_hunters style)."""
    return {"id": wid, "day": day, "warning_days": warning, "owner": owner, "spawn": entries[0], "entry_tiles": entries,
            "entry_name": entry_name, "target": target, "targets": targets, "order": "assault",
            "hero": {"id": hero_id, "name": hero_name, "class": cls, "army": army}}
