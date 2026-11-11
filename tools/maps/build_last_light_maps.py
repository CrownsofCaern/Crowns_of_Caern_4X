"""Builds the hand-made maps of the Concord campaign "The Last Light" that are new
(greyhold_harvest, the tutorial, and knight_who_came_back). Chapters 8 and 10 reuse
burning_ford and into_the_embers (tools/maps/build_campaign_maps.py); the other
chapters are generated maps (see data/campaigns.json).

Edit the layouts here, then regenerate:  python3 tools/maps/build_last_light_maps.py data/maps
and run ./run_tests.sh last_light. The script also runs a quick reachability check
(4-connected, passable tiles) so a broken layout fails before Godot sees it.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
maps = {}

# ------------------------------------------------- chapter 1: the tutorial
# Greyhold's harvest fields in the south-west, the barrow fen in the north-east
# (redrawn Nov 9 for the map overhaul: same size, new layout; drawn with the fen
# in the west and mirrored below, so the story's "graves east of Greyhold" holds). Everything a first
# game needs sits on or near the one road that bends north into the fen: two
# free mines on short side roads, piles, an encounter, a lone armor piece and a
# single weak pack to fight before the barrow-camp. The Hollow side is passive
# and does not build or recruit (campaigns.json), so the player learns at their
# own pace.
g = Grid(22, 14)
g.rect(21, 0, 21, 13, '^'); g.rect(0, 13, 21, 13, '^'); g.rect(10, 0, 21, 0, '^')
g.blob(16, 4, 1.6, 'f'); g.blob(5, 11, 1.4, 'f'); g.set(20, 1, 'f'); g.set(1, 12, 'f')
g.rect(0, 0, 8, 7, 'w')                  # the barrow fen
g.blob(13, 6, 1.0, 'r'); g.blob(8, 10, 1.0, 'r')
g.set(9, 1, '^'); g.set(9, 7, '^'); g.rect(4, 5, 5, 5, '^'); g.rect(4, 0, 5, 0, '^')
g.rect(1, 2, 8, 3, '.')                  # dry causeway to the camp
t1_roads = roads([(20, 11), (11, 11), (11, 3), (2, 3)]) + roads([(17, 11), (17, 8)]) + roads([(14, 11), (14, 9)])
maps["greyhold_harvest"] = {
    "_doc": "The Last Light chapter 1, the tutorial. Hand-made (tools/maps/build_last_light_maps.py). Greyhold's fields in the south-west, a Hollow barrow-camp in the fen to the north-east, one road bending between them. Very easy: the Hollow player is passive and neither builds nor recruits.",
    "id": "greyhold_harvest", "name": "Greyhold Harvest", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": t1_roads,
    "players": [CONCORD, hollow("The Restless Dead")],
    "heroes": [
        hero("hero_wren", "Aldous Wren", "knight", 0, 19, 11, [["pike_militia", 22], ["longbowman", 10]]),
        hero("hero_sexton", "Sexton Grue", "gravewarden", 1, 3, 3, [["shambler", 9]]),
    ],
    "objects": [
        town("town_greyhold", 20, 11, "concord", "Greyhold", 0, ["c_hall", "c_tavern", "c_dw1"], [["pike_militia", 10]]),
        town("town_barrowcamp", 1, 3, "hollow", "Barrow Camp", 1, ["h_hall", "h_dw1"], [["shambler", 6]]),
        mine("mine_wood", 17, 8, "wood"), mine("mine_ore", 14, 9, "ore"),
        res("res_gold_1", 18, 12, "gold", 500), res("res_wood_1", 15, 12, "wood", 5), res("res_ore_1", 12, 8, "ore", 5),
        res("res_gold_2", 10, 5, "gold", 750), res("res_gems_1", 20, 2, "gems", 2), res("res_crystal_1", 2, 11, "crystal", 2),
        res("res_gold_3", 6, 1, "gold", 1000),
        army("neutral_rats", 13, 11, "Plague rats in the grain", [["plague_rats", 8]]),
        army("neutral_barrow", 9, 3, "Risen from the barrows", [["shambler", 6]]),
        enc("enc_barrows", 6, 6, "barrow_field"), enc("enc_wagon", 16, 10, "overturned_wagon"),
        art("art_sallet", 7, 9, "dented_sallet"),
    ],
}



def mirror_x(d):
    """The map mirrored left to right (terrain, roads, objects, heroes, decorations)."""
    w = d["width"]
    d["terrain"] = [r[::-1] for r in d["terrain"]]
    for seg in d["roads"]:
        seg["from"][0] = w - 1 - seg["from"][0]
        seg["to"][0] = w - 1 - seg["to"][0]
    for o in d["objects"] + d["heroes"] + d.get("decorations", []):
        o["pos"][0] = w - 1 - o["pos"][0]


mirror_x(maps["greyhold_harvest"])

# --------------------------------- chapter 4: the knight who came back
# Wren's march into the southern fens. Two Hollow towns: Sallowgate on the
# causeway and the old chapel-fort of Saint Orrin's Rest where the dead knight
# waits. A neutral Concord town to retake on the way. Tier 4 is the Concord's
# cap here; Orrin rides at the head of two gibbet knights (tier 6).
g = Grid(30, 22)
g.rect(0, 0, 29, 0, '^'); g.rect(0, 21, 29, 21, '^')
g.blob(4, 4, 2.5, 'f'); g.blob(3, 17, 2.0, 'f'); g.blob(9, 10, 1.4, 'f')
g.rect(12, 1, 29, 20, 'w')                       # the fens
g.blob(16, 5, 2.2, '.'); g.blob(17, 16, 2.2, '.'); g.blob(25, 10, 3.0, '.')
g.rect(12, 2, 12, 9, '#'); g.rect(12, 11, 12, 19, '#')   # flooded dikes, three crossings
g.rect(20, 1, 20, 9, '^'); g.rect(20, 12, 20, 20, '^')   # barrow ridges, one gap on the road
g.rect(21, 7, 23, 7, '^'); g.rect(21, 14, 23, 14, '^')
g.blob(7, 18, 0.9, '^'); g.blob(8, 2, 0.8, '^')
k_roads = roads([(2, 10), (25, 10)]) + roads([(16, 10), (16, 5)]) + roads([(16, 10), (16, 16)]) + roads([(2, 10), (2, 4)])
maps["knight_who_came_back"] = {
    "_doc": "The Last Light chapter 4. Hand-made (tools/maps/build_last_light_maps.py). The fens south of Greyhold: Sallowgate on the causeway, Saint Orrin's Rest beyond the barrow ridges, a lost Concord town to retake. Sir Orrin Wren, a hundred years dead, leads the Hollow with tier 6 gibbet knights while the Concord is capped at tier 4.",
    "id": "knight_who_came_back", "name": "The Knight Who Came Back", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": k_roads,
    "players": [CONCORD, hollow()],
    "heroes": [
        hero("hero_wren", "Aldous Wren", "knight", 0, 3, 10, [["pike_militia", 28], ["longbowman", 16], ["shieldwarden", 8], ["lancer", 3]]),
        hero("hero_maelis", "Maelis Thorne", "ranger", 0, 3, 11, [["longbowman", 14], ["pike_militia", 12]]),
        hero("hero_edda", "Edda Vey", "oracle", 0, 2, 11, [["pike_militia", 14], ["shieldwarden", 4]]),
        hero("hero_orrin", "Sir Orrin Wren", "gravewarden", 1, 24, 10,
             [["shambler", 40], ["marrow_archer", 18], ["gravecrawler", 10], ["wailing_shade", 4], ["gibbet_knight", 2]]),
        hero("hero_corvin", "Father Corvin Mire", "blightcaller", 1, 17, 5, [["shambler", 26], ["marrow_archer", 10], ["gravecrawler", 4]]),
    ],
    "objects": [
        town("town_greyhold", 2, 10, "concord", "Greyhold", 0, ["c_hall", "c_tavern", "c_market", "c_dw1", "c_dw2", "c_dw3", "c_palisade"],
             [["pike_militia", 20], ["longbowman", 8]]),
        town("town_fenwick", 6, 16, "concord", "Fenwick", -1, ["c_hall", "c_dw1", "c_dw2"], [["shambler", 30], ["marrow_archer", 10]]),
        town("town_sallowgate", 16, 16, "hollow", "Sallowgate", 1, ["h_hall", "h_tavern", "h_dw1", "h_dw2", "h_dw3", "h_fort1"],
             [["shambler", 24], ["marrow_archer", 8]]),
        town("town_orrins_rest", 26, 10, "hollow", "Saint Orrin's Rest", 1,
             ["h_hall", "h_tavern", "h_dw1", "h_dw2", "h_dw3", "h_dw4", "h_fort1", "h_fort2"],
             [["shambler", 30], ["marrow_archer", 12], ["gravecrawler", 6]]),
        mine("mine_wood", 5, 7, "wood"), mine("mine_ore", 1, 14, "ore"),
        mine("mine_crystal", 9, 3, "crystal", [["thornwolf", 12]]),
        mine("mine_gems", 9, 19, "gems", [["marsh_hag", 8]]),
        mine("mine_gold", 16, 2, "gold", [["bog_lurker", 7], ["corpse_light", 12]]),
        mine("mine_mercury", 24, 4, "mercury"), mine("mine_ore_east", 24, 17, "ore"),
        res("res_gold_1", 6, 12, "gold", 750), res("res_wood_1", 1, 2, "wood", 6), res("res_ore_1", 8, 13, "ore", 5),
        res("res_gold_2", 14, 9, "gold", 1000), res("res_gems_1", 18, 19, "gems", 3), res("res_crystal_1", 15, 13, "crystal", 3),
        res("res_gold_3", 27, 2, "gold", 1500), res("res_mercury_1", 27, 18, "mercury", 3),
        army("neutral_dike_north", 12, 1, "Drowned watch", [["shambler", 30], ["corpse_light", 10]]),
        army("neutral_dike_mid", 12, 10, "The causeway dead", [["shambler", 36], ["marrow_archer", 10]]),
        army("neutral_dike_south", 12, 20, "Bog lurkers", [["bog_lurker", 9]]),
        army("neutral_ridge_north", 20, 10, "Barrow revenants", [["barrow_revenant", 5], ["corpse_light", 12]]),
        army("neutral_ridge_south", 20, 11, "Barrow revenants", [["barrow_revenant", 5], ["marsh_hag", 6]]),
        enc("enc_chapel", 9, 16, "drowned_chapel"), enc("enc_barrows", 22, 2, "barrow_field"),
        enc("enc_refugees", 6, 9, "dispossessed_column"), enc("enc_courier", 18, 12, "dying_courier"),
        art("art_lantern", 4, 2, "lantern_of_the_lost"), art("art_visor", 27, 15, "gravewatch_visor"),
        art("art_waders", 10, 7, "marsh_waders"), art("art_coif", 17, 8, "bonewright_coif"),
    ],
}


# The layouts above are drawn on small grids; the maps are played larger
# (playtest, Nov 7: the campaign maps felt small). See maplib.enlarge.
enlarge(maps, {"greyhold_harvest": 2.3, "knight_who_came_back": 2.35})


# Deliberate landmarks using the same decoration atlas as the overworld:
# a broken barrow ring beside the tutorial's causeway, and the drowned
# graves around Orrin's Rest. These are cosmetic and never block movement.
maps["greyhold_harvest"]["decorations"] = [
    {"pos": [p[0], p[1]], "kind": k} for p, k in (([25, 5], "gravestone"), ([23, 4], "gravestone"), ([27, 6], "dead_tree"),
                                                    ([21, 6], "gravestone"), ([22, 8], "boulders"), ([28, 8], "dead_tree"), ([26, 9], "gravestone"))]
maps["knight_who_came_back"]["decorations"] = [
    {"pos": [30, 3], "kind": "dead_tree"}, {"pos": [31, 6], "kind": "gravestone"},
    {"pos": [33, 6], "kind": "gravestone"}, {"pos": [34, 4], "kind": "dead_tree"},
    {"pos": [35, 6], "kind": "boulders"}, {"pos": [29, 5], "kind": "gravestone"}]


# Move the hand-placed landmark plans from the earlier 1.4x drawing to
# the enlarged chapter layouts. Keep the art off roads and occupied tiles.
for mid, factor in (("greyhold_harvest", 2.3), ("knight_who_came_back", 2.35)):
    d = maps[mid]
    occupied = {tuple(o["pos"]) for o in d["objects"] + d["heroes"]}
    road_tiles = set()
    for seg in d.get("roads", []):
        (x0, y0), (x1, y1) = seg["from"], seg["to"]
        road_tiles.update((x, y) for x in range(min(x0, x1), max(x0, x1) + 1)
                          for y in range(min(y0, y1), max(y0, y1) + 1))
    pieces = []
    for piece in d["decorations"]:
        x, y = (round(c * factor / 1.4) for c in piece["pos"])
        if (x, y) not in occupied and (x, y) not in road_tiles and d["terrain"][y][x] in PASSABLE:
            pieces.append({"pos": [x, y], "kind": piece["kind"]})
    d["decorations"] = pieces


# Map overhaul (Nov 9): same layouts, but the flat single-biome blocks get
# patches of their neighbouring ground and the terrain painter dresses the maps
# (after build(), which writes them).
import rebuild as rb
rb.texture(maps["greyhold_harvest"], 1)
rb.texture(maps["knight_who_came_back"], 4)
build(maps, OUT)
if OUT:
    rb.dress_hand_made(OUT, "greyhold_harvest", 1)
    rb.dress_hand_made(OUT, "knight_who_came_back", 4)


# ============================================================================
# Chapters rebuilt from frozen generator maps (map overhaul phase 3, Nov 9).
# Each starts from a generated layout (seed picked from a contact sheet), gets
# the story's ground, towns, heroes and landmarks, and is written dressed.
# Needs Godot (set $GODOT); story text and casts live in data/campaigns.json.
# ============================================================================
from rebuild import *
import rebuild

NEUTRAL = ["wilds"]


def ll_barrow_roads():
    """Chapter 2, The Barrow Roads (L). Lanes layout: Greyhold's fields in the
    north, Sexton Grue's grave-town in the south; the dead march north up three
    roads through barrow country."""
    d = start("gen:random_xl_2p_normal_normal_lanes:4", "ll_barrow_roads", "The Barrow Roads",
              "The Last Light chapter 2. Greyhold's fields in the north, Sexton Grue's grave-town in the barrow fens to the south, three roads between them.")
    north = biome(".", [("f", "f"), ("r", "f")])
    fen = biome("w", [("f", "f"), (".", "r"), ("d", "r")])
    repaint(d, {
        "start_0": north, "valley_0": biome("f", [(".", ".")]), "lane_a_0": biome(".", [("w", "w"), ("f", "f")]),
        "lane_b_0": biome("f", [(".", "."), ("r", "r")]), "march_0": biome(".", [("d", "r"), ("f", "f")]),
        "march_1": biome("r", [("d", "."), ("f", "f")]), "heart": biome("r", [("i", "r"), ("d", "w"), (".", ".")]),
        "start_1": fen, "valley_1": biome("w", [("f", "f")]), "lane_a_1": biome("w", [(".", "r")]), "lane_b_1": biome("r", [("w", "w"), ("s", "w")]),
    })
    set_players(d, [player(0, "Aldmere Concord", "concord", human=True), player(1, "The Restless Dead", "hollow")])
    town_set(obj(d, "town_start_0"), "concord", "Greyhold", 0, buildings("concord", 2, ["fort1"]), [["pike_militia", 12]])
    town_set(obj(d, "town_start_1"), "hollow", "Grue's Yard", 1, buildings("hollow", 2, ["fort1"]), [["shambler", 16], ["marrow_archer", 4]])
    town_set(obj(d, "town_heart"), "concord", "Barrowcross", -1, ["c_hall", "c_dw1", "c_dw2"],
             [["shambler", 40], ["marrow_archer", 18], ["gravecrawler", 8]])
    h0, h1 = d["heroes"]
    hero_set(h0, "hero_p0", "Aldous Wren", "knight", 0, [["pike_militia", 24], ["longbowman", 12], ["shieldwarden", 4]])
    hero_set(h1, "hero_p1", "Sexton Grue", "gravewarden", 1, [["shambler", 34], ["marrow_archer", 12], ["gravecrawler", 4]])
    # The columns: lines of grave markers along the southern roads.
    tx, ty = obj(d, "town_start_1")["pos"]
    for x, y in [(tx - 6, ty - 6), (tx + 6, ty - 6), (tx, ty - 12), (tx - 14, ty - 8), (tx + 14, ty - 8)]:
        scatter(d, x, y, 3, ["gravestone", "dead_tree", "gravestone", "bones"], every=2)
    ring(d, *obj(d, "town_heart")["pos"], 5, ["gravestone", "boulders", "gravestone", "dead_tree"])
    finish(OUT, d, 4, NEUTRAL + ["hollow"])
    return d


def ll_lanterns():
    """Chapter 3, Lanterns in the Fen (T). The townless recipe on twin_marches:
    Wren's column starts on the western causeway with no town, four fen hamlets
    sell Concord folk, Fenlight (the old start town) is held by the dead, and
    Father Corvin Mire's Hollow town sits on the Fen Road in the north-east."""
    d = start("scenario:townless_v1:1", "ll_lanterns", "Lanterns in the Fen",
              "The Last Light chapter 3 (townless start). Wren's column is cut off in the fen without a town: free the fen hamlets, buy their folk, take Fenlight from the dead, then march on Father Corvin Mire's town on the Fen Road.")
    d.pop("scenario")   # the chapter's scenario lives in data/campaigns.json
    repaint(d, {
        "start_0": biome("w", [(".", "."), ("f", "f")]), "wild_0": biome("w", [("f", "f"), (".", "r")]),
        "flank_0": biome("w", [(".", "."), ("f", "f"), ("r", "r")]), "heart": biome("w", [("r", "r"), ("f", "f")]),
        "wild_1": biome("f", [("w", "w"), ("r", "r")]), "flank_1": biome(".", [("w", "w"), ("f", "f")]),
        "start_1": biome("w", [("r", "r"), ("f", "f")]),
    })
    unseal_pockets(d)   # twin_marches seals its treasure pockets; guards hold prizes since #135
    set_players(d, [player(0, "Aldmere Concord", "concord", human=True), player(1, "The Fen Road", "hollow")])
    town_set(obj(d, "town_start_0"), "concord", "Fenlight", -1, ["c_hall", "c_dw1", "c_dw2", "c_dw3"],
             [["shambler", 54], ["marrow_archer", 20], ["gravecrawler", 10]])
    town_set(obj(d, "town_start_1"), "hollow", "Mirehold", 1, buildings("hollow", 3, ["fort1", "market"]), [["shambler", 20], ["marrow_archer", 6]])
    town_set(obj(d, "town_flank_0"), "hollow", "Sedgewater", -1, ["h_hall", "h_dw1", "h_dw2"], [["bog_lurker", 12], ["corpse_light", 14]])
    town_set(obj(d, "town_flank_1"), "concord", "Reedholm", -1, ["c_hall", "c_dw1", "c_dw2"], [["marsh_hag", 14], ["corpse_light", 12]])
    town_set(obj(d, "town_heart"), "concord", "Lantern Hill", -1, ["c_hall", "c_dw1", "c_dw2", "c_dw3", "c_fort1"],
             [["barrow_revenant", 10], ["marsh_hag", 12]])
    # Four fen hamlets with Concord tier 1-3 folk (one-off stocks, about 11k gold in all).
    stocks = [[["pike_militia", 30], ["longbowman", 12]], [["shieldwarden", 12], ["pike_militia", 14]],
              [["longbowman", 22]], [["shieldwarden", 10], ["longbowman", 10]]]
    for i, o in enumerate(sorted((o for o in d["objects"] if o.get("zone") == "townless" and o["type"] == "site"), key=lambda o: o["id"])):
        keep(o)["site"] = "fenside_hamlet"
        o["stock"] = stocks[i % len(stocks)]
        o["guard"] = [["bog_lurker", 4]] if i % 2 else [["corpse_light", 12]]
    h0, h1 = d["heroes"]
    hero_set(h0, "hero_p0", "Aldous Wren", "knight", 0, [["pike_militia", 28], ["longbowman", 14], ["shieldwarden", 6]])
    hero_set(h1, "hero_p1", "Father Corvin Mire", "blightcaller", 1, [["shambler", 46], ["marrow_archer", 18], ["gravecrawler", 8]])
    # Edda's lamp: a chapel on the causeway east of the start, reed pools and dead trees around it.
    hx, hy = h0["pos"]
    p = free_near(d, hx + 5, hy - 2, margin=1)
    d["objects"].append({"id": "site_lantern_chapel", "type": "site", "site": "pilgrims_rest", "pos": p})
    ring(d, p[0], p[1], 3, ["gravestone", "dead_tree", "gravestone", "boulders"])
    scenery_near(d, hx + 4, hy + 4, ["scenery_reed_pool", "scenery_weeping_willow"], 4)
    tx, ty = obj(d, "town_start_1")["pos"]
    scenery_near(d, tx - 8, ty + 6, ["scenery_reed_pool", "scenery_weeping_willow"], 3)
    finish(OUT, d, 1, NEUTRAL + ["hollow"])
    return d


def ll_doors():
    """Chapter 5, Doors of Stone (A, 2v2). A four-realm ring in the Forge
    mountains: Wren in the north, Tobbin Greave's workshop (allied Forge) in the
    east, Dask Vell's Border Wardens in the west and the Stonevow Gate, the
    Mountain Gate itself, in the far south."""
    d = start("gen:random_l_4p_normal_normal_ring:6", "ll_doors", "Doors of Stone",
              "The Last Light chapter 5 (2 against 2). Rocky passes under the Forge mountains: the Concord and Greave's Workshop against the Border Wardens and the Stonevow Gate, the Mountain Gate itself, deepest in the south.")
    # Ring order N, E, S, W: the ally beside the player in the east, the gate opposite.
    remap_slots(d, {1: 2, 2: 3, 3: 1})
    rock = biome("r", [("f", "f"), (".", "."), ("w", "."), ("d", "d"), ("s", "s")])
    repaint(d, {
        "start_0": biome(".", [("f", "f"), ("r", "r")]), "wild_0": biome("f", [(".", ".")]),
        "start_1": biome("r", [("i", "r"), (".", "d"), ("f", "f")]), "start_2": biome("r", [(".", "."), ("f", "f")]),
        "start_3": biome("r", [("i", "i"), (".", "d")]), "heart": biome("r", [("d", "d"), ("i", "i"), ("f", "r")]),
        "approach_0": biome("f", [("r", "r")]),
    }, default=rock)
    set_players(d, [player(0, "Aldmere Concord", "concord", human=True, team=1),
                    player(1, "The Border Wardens", "forge", team=2, color="#8a5a2e"),
                    player(2, "Greave's Workshop", "forge", team=1, color="#c79a2e"),
                    player(3, "The Stonevow Gate", "forge", team=2, color="#6e4a3a")])
    town_set(obj(d, "town_start_0"), "concord", "Wren's Camp", 0, buildings("concord", 3, ["fort1", "market"]), [["pike_militia", 16]])
    town_set(obj(d, "town_start_1"), "forge", "Greave's Workshop", 2, buildings("forge", 3, ["market"]), [["forge_thrall", 14], ["anvil_guard", 6]])
    town_set(obj(d, "town_start_3"), "forge", "Wardenhall", 1, buildings("forge", 4, ["fort1"]), [["forge_thrall", 20], ["rivet_crossbowman", 8]])
    town_set(obj(d, "town_start_2"), "forge", "The Mountain Gate", 3, buildings("forge", 5, ["fort1", "fort2", "market"]),
             [["forge_thrall", 30], ["rivet_crossbowman", 12], ["anvil_guard", 10], ["slag_golem", 4]])
    town_set(obj(d, "town_heart"), "forge", "Oreway", -1, ["f_hall", "f_dw1", "f_dw2", "f_dw3"],
             [["forge_thrall", 50], ["rivet_crossbowman", 20], ["anvil_guard", 14]])
    by = {h["id"]: h for h in d["heroes"]}
    hero_set(by["hero_p0"], "hero_p0", "Aldous Wren", "knight", 0, [["pike_militia", 30], ["longbowman", 16], ["shieldwarden", 8], ["lancer", 4]])
    hero_set(by["hero_p1"], "hero_p1", "Dask Vell", "ironmarshal", 1, troops("forge", [40, 18, 12, 6, 2]))
    hero_set(by["hero_p2"], "hero_p2", "Tobbin Greave", "artificer", 2, troops("forge", [24, 12, 8, 3]))
    hero_set(by["hero_p3"], "hero_p3", "Bruna Kell", "ironmarshal", 3, troops("forge", [44, 20, 14, 8, 3]))
    gx, gy = obj(d, "town_start_2")["pos"]
    landmark_on_mountains(d, gx, gy, "landmark_shattered_citadel")
    # Ore roads: the mines on the roads to the gate dig ore.
    for o in d["objects"]:
        if o["type"] == "mine" and o.get("zone") in ("flank_1", "flank_2", "heart") and o["resource"] in ("wood", "mercury", "sulfur"):
            o["resource"] = "ore"
    scatter(d, gx, gy - 8, 3, ["boulders", "peaks", "boulders"], every=2)
    finish(OUT, d, 6, NEUTRAL + ["forge"])
    return d


# Chapter scenarios that need map positions (reach goals, wave entries) are
# collected here and written into data/campaigns.json by update_campaign().
SCENARIOS = {}


def ll_stumps():
    """Chapter 6, The Stumps of Elderwold (S, mission). A three-realm ring turned
    into the felled forest: Wren starts in the west and must reach the eastern
    edge by day 24. Neve Hollowreed holds the two Covenant groves (north and
    south-east, optional from day 8); Thornwood ambushes come out of the tree
    lines. The Heartroots, a ring of dead stumps, lie in the middle; one living
    grove stands near the goal."""
    d = start("gen:random_xl_3p_normal_normal_ring:2", "ll_stumps", "The Stumps of Elderwold",
              "The Last Light chapter 6 (mission). The felled Elderwold: cross from the western camp to the eastern edge by day 24 while Neve Hollowreed's archers raid from the groves.")
    stumps = biome(".", [("f", "f"), ("r", "r"), ("w", "w"), ("d", "r"), ("s", "r")])
    repaint(d, {
        "start_0": biome(".", [("f", "f"), ("r", "r")]), "start_1": biome("f", [("i", "f"), (".", "."), ("r", "r")]),
        "start_2": biome("f", [(".", "."), ("w", "w")]), "wild_1": biome("f", [(".", ".")]), "wild_2": biome("f", [("w", "w")]),
        "approach_0": biome("w", [("f", "f"), (".", ".")]), "approach_1": biome("f", [("w", "w")]), "approach_2": biome("f", [("w", "w")]),
        "outer_1": biome("f", [(".", "."), ("w", "w"), ("s", "r")]),
    }, default=stumps)
    set_players(d, [player(0, "Aldmere Concord", "concord", human=True),
                    player(1, "The Covenant Groves", "thornwood"),
                    player(2, "The Elderwold Ambush", "thornwood", color="#2f5a2a")])
    town_set(obj(d, "town_start_0"), "concord", "Stumpfield Camp", 0, buildings("concord", 3, ["fort1"]), [["pike_militia", 20], ["longbowman", 8]])
    town_set(obj(d, "town_start_1"), "thornwood", "Hollowreed Grove", 1, buildings("thornwood", 4, ["fort1"]), [["thorn_skulker", 24], ["barkhide_warden", 12]])
    town_set(obj(d, "town_start_2"), "thornwood", "Covenant Grove", 1, buildings("thornwood", 3), [["thorn_skulker", 30], ["barkhide_warden", 14], ["briar_huntress", 6]])
    # The Heartroots: the middle town gives way to a ring of dead stumps around the elder rings.
    hx, hy = obj(d, "town_heart")["pos"]
    drop(d, lambda o: o["id"] == "town_heart")
    keep(village(d, "site_heartroots", [hx, hy], "elder_rings", None, [["rootbinder", 10], ["thornwolf", 14]]))
    obj(d, "site_heartroots").pop("stock")
    d["heroes"] = [h for h in d["heroes"] if h["owner"] != 2]
    by = {h["id"]: h for h in d["heroes"]}
    hero_set(by["hero_p0"], "hero_p0", "Aldous Wren", "knight", 0, [["pike_militia", 34], ["longbowman", 18], ["shieldwarden", 8], ["lancer", 6]])
    hero_set(by["hero_p1"], "hero_p1", "Neve Hollowreed", "huntmaster", 1, troops("thornwood", [40, 20, 14, 8, 3]))
    for r, k in ((5, ["charred_tree", "dead_tree"]), (7, ["dead_tree", "charred_tree", "bones"])):
        ring(d, hx, hy, r, k)
    for z in ("flank_0", "flank_1", "flank_2", "heart", "outer_0", "outer_2"):
        ax, ay = zones(d)[z]["anchor"]
        scatter(d, ax, ay, 9, ["charred_tree", "dead_tree", "charred_tree", "boulders"], every=5)
    # The goal: the easternmost open tile of the eastern wilds.
    grid = zone_grid(d)
    W = d["width"]
    goal = min(([x, y] for y in range(d["height"]) for x in range(W - 4, W) if passable(d, x, y) and grid[y][x] == "outer_1"),
               key=lambda p: (-p[0], abs(p[1] - zones(d)["outer_1"]["anchor"][1])))
    landmark_on_mountains(d, goal[0] - 4, goal[1], "landmark_elder_grove")
    for o in d["objects"]:
        if o["type"] == "site" and o.get("zone") in ("flank_0", "flank_1", "flank_2") and o["site"] in ("oathstone", "wardens_causeway"):
            o["site"] = "elder_rings"
    # Ambushes from the tree lines along the crossing: spawn on open ground in the named zones.
    waves = []
    for i, (zone, day, counts) in enumerate((("approach_0", 5, [30, 14, 6]), ("flank_2", 10, [36, 18, 10, 4]),
                                             ("approach_2", 15, [40, 20, 12, 6, 2]), ("flank_1", 20, [44, 24, 14, 8, 4]))):
        ax, ay = zones(d)[zone]["anchor"]
        p = free_near(d, ax, ay, margin=1, zone=zone, grid=grid)
        waves.append({"id": "stumps_ambush_%d" % i, "day": day, "warning_days": 2, "owner": 2, "spawn": p, "entry_tiles": [p],
                      "entry_name": "the tree line", "target": "town_start_0", "order": "raid",
                      "hero": {"id": "stumps_ambusher_%d" % i, "name": ["Briar Stalker", "Thorn Warden", "Root Huntress", "Elder Avenger"][i],
                               "class": "huntmaster", "army": troops("thornwood", counts)}})
    SCENARIOS["ll_stumps"] = {
        "name": "The Stumps of Elderwold", "mode": "mission", "player": 0, "deadline_day": 24,
        "required_heroes": ["hero_wren"], "invasion_players": [2], "max_active_invaders": 3, "waves": waves,
        "objectives": [
            {"id": "cross", "type": "reach", "hero": "hero_wren", "pos": goal,
             "text": "Bring Aldous Wren to the living grove at the eastern edge of the stumps by day 24."},
            {"id": "groves", "type": "control_towns", "towns": ["town_start_1", "town_start_2"], "optional": True, "unlock_day": 8,
             "text": "Take the Covenant groves of Neve Hollowreed."}]}
    finish(OUT, d, 2, NEUTRAL + ["thornwood"])
    return d


def ll_red_sky():
    """Chapter 7, Raiders under a Red Sky (B, betrayal). A three-realm ring north
    of Greyhold: the Concord in the south, Coldhand's Raiders in the snowy
    north-west, Clan Grimfell (allied at first) in the north-east. The raiders
    hold two burning granary towns; once the player's side holds both (or on day
    21) Hrodna Grimfell's clan turns and joins the raiders."""
    d = start("gen:random_xl_3p_normal_normal_ring:8", "ll_red_sky", "Raiders under a Red Sky",
              "The Last Light chapter 7 (betrayal). Ash on the northern fields: the Concord and Clan Grimfell against Coldhand's Raiders, who hold two burning granary towns. Grimfell turns when the granaries fall or on day 21.")
    ash = biome(".", [("i", "i"), ("f", "f"), ("r", "r"), ("d", "i"), ("s", "."), ("w", "w")])
    repaint(d, {
        "start_1": biome("s", [("i", "r"), (".", "r"), ("f", "f")]), "outer_1": biome("s", [(".", "r"), ("f", "f")]),
        "start_2": biome("s", [(".", "."), ("f", "f"), ("r", "r")]), "flank_1": biome("r", [("s", "s"), ("f", "f"), (".", ".")]),
        "heart": biome("i", [("r", "r"), (".", "."), ("d", "r")]), "flank_0": biome(".", [("s", "s"), ("i", "i"), ("f", "f")]),
    }, default=ash)
    set_players(d, [player(0, "Aldmere Concord", "concord", human=True, team=1),
                    player(1, "Coldhand's Raiders", "frostmarch", team=2),
                    player(2, "Clan Grimfell", "frostmarch", team=1, color="#c8a85a")])
    town_set(obj(d, "town_start_0"), "concord", "Northgate of Greyhold", 0, buildings("concord", 5, ["fort1", "market"]), [["pike_militia", 24], ["longbowman", 10]])
    town_set(obj(d, "town_start_1"), "frostmarch", "Coldhand's Hall", 1, buildings("frostmarch", 5, ["fort1", "fort2"]), [["clan_raider", 30], ["rimefang_hound", 12]])
    town_set(obj(d, "town_start_2"), "frostmarch", "Grimfell Steading", 2, buildings("frostmarch", 4), [["clan_raider", 20], ["rimefang_hound", 8]])
    town_set(obj(d, "town_outer_0"), "concord", "Westmere Granary", 1, ["c_hall", "c_dw1", "c_dw2", "c_market"], [["clan_raider", 40], ["oathless_berserker", 10]])
    town_set(obj(d, "town_outer_2"), "concord", "Eastmere Granary", 1, ["c_hall", "c_dw1", "c_dw2", "c_market"], [["clan_raider", 36], ["rimefang_hound", 16]])
    town_set(obj(d, "town_outer_1"), "concord", "Highmarch", -1, ["c_hall", "c_dw1", "c_dw2", "c_dw3"], [["frost_drake", 4], ["rime_wight", 20]])
    by = {h["id"]: h for h in d["heroes"]}
    hero_set(by["hero_p0"], "hero_p0", "Aldous Wren", "knight", 0, [["pike_militia", 36], ["longbowman", 20], ["shieldwarden", 10], ["lancer", 6], ["lightbearer", 3]])
    hero_set(by["hero_p1"], "hero_p1", "Bjarr Coldhand", "reaver", 1, troops("frostmarch", [50, 24, 16, 8, 4, 2]))
    hero_set(by["hero_p2"], "hero_p2", "Hrodna Grimfell", "thane", 2, troops("frostmarch", [36, 16, 10, 5, 2]))
    for tid in ("town_outer_0", "town_outer_2"):
        x, y = obj(d, tid)["pos"]
        ring(d, x, y, 4, ["charred_tree", "obsidian", "charred_tree", "bones"])
        ring(d, x, y, 6, ["charred_tree", "dead_tree"], count=14)
    SCENARIOS["ll_red_sky"] = {
        "name": "Raiders under a Red Sky", "mode": "betrayal", "player": 0,
        "betrayal": {"player": 2, "joins": 1, "trigger": {"towns_taken": {"towns": ["town_outer_0", "town_outer_2"], "count": 2}, "day": 21},
                     "text": "The granaries are empty. Hrodna's clan was never full.",
                     "reinforcements": troops("frostmarch", [30, 14, 8, 4])},
        "objectives": [
            {"id": "granaries", "type": "control_towns", "towns": ["town_outer_0", "town_outer_2"], "optional": True,
             "text": "Retake the Westmere and Eastmere granaries."},
            {"id": "grimfell", "type": "ally_survives", "player": 2, "until_betrayal": True, "text": "Keep Clan Grimfell in the field."},
            {"id": "conquer", "type": "conquer", "text": "Drive every raider out of the north."}]}
    finish(OUT, d, 8, NEUTRAL + ["frostmarch"])
    return d


def _rename_town(d, old, new):
    obj(d, old)["id"] = new


def _veterans(d, h0, army_wren, army_maelis):
    """Wren and Maelis Thorne, carried over from the earlier chapters, side by side."""
    hero_set(h0, "hero_wren", "Aldous Wren", "knight", 0, army_wren)
    x, y = h0["pos"]
    m = dict(h0)
    m.update({"id": "hero_maelis", "name": "Maelis Thorne", "class": "ranger", "army": army_maelis,
              "pos": free_near(d, x + 1, y + 1, avoid_roads=False, margin=0)})
    d["heroes"].append(m)


def ll_ford():
    """Chapter 8, The Burning Ford (L). A diagonal march: Greyhold in the green
    south-west, Skarn Ashborn's Ashgate Camp in the cinder north-east, and the
    river between them, crossed only at its fords, which the Ashen have set
    burning."""
    d = start("gen:random_xl_2p_normal_normal_diagonal:1", "ll_ford", "The Burning Ford",
              "The Last Light chapter 8. Greyhold's fields in the south-west, Skarn Ashborn's war camp in the cinder north-east, and a river between them that only its burning fords cross.")
    home = biome(".", [("f", "f"), ("r", "r"), ("w", "w"), ("s", "f"), ("d", "."), ("i", "r")])
    cinder = biome("i", [("r", "r"), (".", "i"), ("f", "f"), ("s", "r"), ("d", "r"), ("w", "r")])
    repaint(d, {
        "start_0": home, "route_0": home, "back_0": biome("f", [(".", "."), ("w", "w"), ("s", "f"), ("d", "."), ("i", "r")]),
        "march_0": biome(".", [("f", "f"), ("r", "r"), ("d", "r"), ("s", "."), ("i", "r")]),
        "corner_0": biome("w", [("f", "f"), (".", "."), ("s", "w"), ("d", "r"), ("i", "r")]),
        "heart": biome("r", [(".", "."), ("i", "i"), ("f", "f"), ("s", "r"), ("d", "r")]),
        "start_1": cinder, "route_1": cinder, "back_1": biome("i", [("r", "r"), ("f", "f"), (".", "r"), ("s", "r")]),
        "march_1": biome("r", [("i", "i"), (".", "."), ("f", "f"), ("s", "r"), ("d", "r")]),
        "corner_1": biome("r", [("i", "i"), ("f", "f"), (".", "r"), ("s", "r"), ("d", "i")]),
    })
    river_across(d, width=2, fords=2)
    set_players(d, [player(0, "Aldmere Concord", "concord", human=True), player(1, "Ashen Vanguard", "ashen")])
    _rename_town(d, "town_start_0", "town_greyhold")
    _rename_town(d, "town_start_1", "town_ashgate")
    town_set(obj(d, "town_greyhold"), "concord", "Greyhold", 0, buildings("concord", 4, ["fort1", "market"]), [["pike_militia", 16]])
    town_set(obj(d, "town_ashgate"), "ashen", "Ashgate Camp", 1, buildings("ashen", 3, ["fort1"]), [["cinderling", 14], ["scorchhound", 4]])
    by = {h["id"]: h for h in d["heroes"]}
    _veterans(d, by["hero_p0"], [["pike_militia", 24], ["longbowman", 14], ["shieldwarden", 6], ["lancer", 3]],
              [["longbowman", 12], ["pike_militia", 10]])
    hero_set(by["hero_p1"], "hero_skarn", "Skarn Ashborn", "warlord", 1, [["cinderling", 26], ["scorchhound", 8], ["brimstone_hurler", 5], ["flayer", 1]])
    # The burning fords: charred trees and cinders on both banks of every crossing.
    rows = d["terrain"]
    fords = [(x, y) for y in range(d["height"]) for x in range(d["width"]) if rows[y][x] == "~"]
    done = []
    for x, y in fords:
        if all(abs(x - a) + abs(y - b) > 6 for a, b in done):
            done.append((x, y))
            ring(d, x, y, 3, ["charred_tree", "obsidian", "charred_tree", "bones"], count=6)
    ax, ay = obj(d, "town_ashgate")["pos"]
    ring(d, ax, ay, 5, ["charred_tree", "obsidian", "bones", "charred_tree"])
    finish(OUT, d, 8, NEUTRAL + ["ashen"])
    return d


def ll_ashes():
    """Chapter 9, Ashes Return (L). A three-realm ring turned on its side:
    Greyhold in the south, Ashgate Camp in the north-west and Cinderfall, the
    Ashen stronghold, in the east; free Saltmere sits in the salt marsh at the
    centre, between them."""
    d = start("gen:random_xl_3p_normal_normal_ring:14", "ll_ashes", "Ashes Return",
              "The Last Light chapter 9. The Ashen come back in force: Ashgate Camp in the north-west and Cinderfall in the east against Greyhold in the south, with free Saltmere in the salt marsh between them.")
    home = biome(".", [("f", "f"), ("r", "r"), ("w", "w"), ("s", "f"), ("d", "."), ("i", "r")])
    cinder = biome("i", [("r", "r"), (".", "i"), ("f", "f"), ("s", "r"), ("d", "r"), ("w", "r")])
    burnt = biome("r", [("i", "i"), (".", "."), ("f", "f"), ("s", "r"), ("d", "i"), ("w", "w")])
    repaint(d, {
        "start_0": home, "wild_0": biome("f", [(".", "."), ("w", "w"), ("s", "f"), ("d", "."), ("i", "r")]),
        "approach_0": home, "flank_0": biome(".", [("f", "f"), ("r", "r"), ("s", "."), ("d", "r"), ("i", "r")]),
        "outer_0": biome("f", [(".", "."), ("w", "w"), ("s", "f"), ("d", "r"), ("i", "r")]),
        "outer_2": biome(".", [("f", "f"), ("w", "w"), ("s", "r"), ("d", "."), ("i", "r")]),
        "heart": biome("w", [(".", "."), ("f", "f"), ("r", "r"), ("s", "w"), ("d", "w"), ("i", "r")]),
        "start_1": cinder, "wild_1": burnt, "approach_1": burnt, "start_2": cinder, "wild_2": cinder,
        "approach_2": burnt, "flank_1": burnt, "flank_2": biome("r", [(".", "."), ("f", "f"), ("i", "i"), ("s", "r"), ("d", "r")]),
        "outer_1": biome("i", [("r", "r"), ("f", "f"), (".", "r"), ("s", "r"), ("d", "i")]),
    })
    set_players(d, [player(0, "Aldmere Concord", "concord", human=True), player(1, "The Ashen Host", "ashen")])
    _rename_town(d, "town_start_0", "town_greyhold")
    _rename_town(d, "town_start_1", "town_ashgate")
    _rename_town(d, "town_start_2", "town_cinderfall")
    _rename_town(d, "town_heart", "town_saltmere")
    town_set(obj(d, "town_greyhold"), "concord", "Greyhold", 0, buildings("concord", 5, ["fort1", "fort2", "market"]), [["pike_militia", 16]])
    town_set(obj(d, "town_ashgate"), "ashen", "Ashgate Camp", 1, buildings("ashen", 3, ["fort1"]), [["cinderling", 12]])
    town_set(obj(d, "town_cinderfall"), "ashen", "Cinderfall", 1, buildings("ashen", 4, ["fort1"]), [["cinderling", 14], ["brimstone_hurler", 3]])
    town_set(obj(d, "town_saltmere"), "concord", "Saltmere", -1, ["c_hall", "c_dw1", "c_dw2", "c_market"], [["pike_militia", 18], ["longbowman", 8]])
    by = {h["id"]: h for h in d["heroes"]}
    _veterans(d, by["hero_p0"], [["pike_militia", 24], ["longbowman", 14], ["shieldwarden", 6], ["lancer", 3]],
              [["longbowman", 12], ["pike_militia", 10]])
    hero_set(by["hero_p1"], "hero_ithra", "Ithra Sootveil", "warlock", 1, [["cinderling", 16], ["brimstone_hurler", 5], ["ash_witch", 1]])
    hero_set(by["hero_p2"], "hero_skarn", "Skarn Ashborn", "warlord", 1, [["cinderling", 22], ["scorchhound", 6], ["brimstone_hurler", 6], ["flayer", 2]])
    for tid in ("town_ashgate", "town_cinderfall"):
        x, y = obj(d, tid)["pos"]
        ring(d, x, y, 5, ["charred_tree", "obsidian", "bones", "charred_tree"])
    sx, sy = obj(d, "town_saltmere")["pos"]
    scenery_near(d, sx - 4, sy + 3, ["scenery_reed_pool", "scenery_weeping_willow"], 3)
    finish(OUT, d, 14, NEUTRAL + ["ashen"])
    return d


SCENARIOS["ll_lanterns"] = {
    "name": "Lanterns in the Fen", "mode": "townless", "player": 0, "townless_players": [0],
    "objectives": [
        {"id": "fenlight", "type": "control_towns", "towns": ["town_start_0"], "text": "Take Fenlight from the dead."},
        {"id": "conquer", "type": "conquer", "text": "Drive Father Corvin Mire off the Fen Road."}]}
SCENARIOS["ll_doors"] = {
    "name": "Doors of Stone", "mode": "alliance", "player": 0,
    "objectives": [
        {"id": "greave", "type": "ally_survives", "player": 2, "text": "Keep Tobbin Greave's workshop standing."},
        {"id": "conquer", "type": "conquer", "text": "Break the Border Wardens and take the Mountain Gate."}]}

if OUT:
    ll_barrow_roads()
    ll_lanterns()
    ll_doors()
    ll_stumps()
    ll_red_sky()
    ll_ford()
    ll_ashes()
    update_campaign("last_light", {cid: {"map": cid, "scenario": SCENARIOS.get(cid)}
                                   for cid in ("ll_barrow_roads", "ll_lanterns", "ll_doors", "ll_stumps", "ll_red_sky", "ll_ford", "ll_ashes")})
