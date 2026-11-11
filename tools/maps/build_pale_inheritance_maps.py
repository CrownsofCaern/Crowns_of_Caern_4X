"""Builds the hand-made maps of the Hollow campaign "The Pale Inheritance":
warm_earth (chapter 1), twice_dead (chapter 5) and pale_crown (chapter 10, one
against two). The other chapters are generated maps (see data/campaigns.json).

Edit the layouts here, then regenerate:  python3 tools/maps/build_pale_inheritance_maps.py data/maps
and run ./run_tests.sh faction_campaigns. The script runs the same quick
reachability check as the other builders.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
maps = {}

COURT = player(0, "The Regent's Court", "hollow", human=True)

# ------------------------------------------------- chapter 1: the warm earth
# Sallowmere on its dry mound in the south-west fen, Cairnholt on its barrow
# hill in the north-east (redrawn Nov 9 for the map overhaul: same size, new
# layout). The causeway bends north between them; a drowned channel and a
# line of barrow mounds each leave one gap on it, and a second way round the
# mounds runs through the southern fen. The barrow-lord of Cairnholt is a
# normal computer player, but his town is small and the cap is tier 2 for both.
g = Grid(24, 16, 'w')
g.rect(0, 0, 23, 0, '^'); g.rect(0, 15, 23, 15, '^')
g.blob(4, 11, 3.0, '.')                   # Sallowmere's dry mound
g.blob(19, 4, 3.0, 'r')                   # Cairnholt's barrow hill
g.rect(1, 11, 12, 12, '.'); g.rect(11, 3, 12, 12, '.'); g.rect(11, 3, 22, 4, '.')   # the causeway
g.blob(5, 3, 1.5, 'f'); g.blob(18, 11, 1.5, 'f')
g.rect(7, 1, 7, 10, '#'); g.rect(7, 13, 7, 14, '#')       # drowned channel
g.rect(16, 1, 16, 2, '^'); g.rect(16, 5, 16, 13, '^')     # barrow mounds
maps["warm_earth"] = {
    "_doc": "The Pale Inheritance chapter 1. Hand-made (tools/maps/build_pale_inheritance_maps.py). Ysmay Vane's Sallowmere in the south-western fen against Cairnholt, a barrow-lord's hill in the north-east who will not kneel. Both sides are Hollow and capped at tier 2.",
    "id": "warm_earth", "name": "The Warm Earth", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(2, 12), (12, 12), (12, 4), (21, 4)]) + roads([(4, 12), (4, 8)]) + roads([(9, 12), (9, 14)]),
    "players": [COURT, player(1, "Cairnholt", "hollow", color="#7a5a8a")],
    "heroes": [
        hero("hero_ysmay", "Ysmay Vane", "necromancer", 0, 3, 12, [["shambler", 30], ["marrow_archer", 10]]),
        hero("hero_orrin", "Sir Orrin Wren", "gravewarden", 0, 3, 11, [["shambler", 18], ["marrow_archer", 6]]),
        hero("hero_vathek", "Vathek the Unbowed", "gravewarden", 1, 19, 4, [["shambler", 24], ["marrow_archer", 8]]),
    ],
    "objects": [
        town("town_sallowmere", 2, 12, "hollow", "Sallowmere", 0, ["h_hall", "h_tavern", "h_fort1", "h_dw1", "h_dw2"], [["shambler", 12]]),
        town("town_cairnholt", 21, 4, "hollow", "Cairnholt", 1, ["h_hall", "h_fort1", "h_dw1", "h_dw2"], [["shambler", 14], ["marrow_archer", 4]]),
        mine("mine_wood", 4, 8, "wood"), mine("mine_ore", 9, 14, "ore"),
        mine("mine_mercury", 20, 9, "mercury", [["marsh_hag", 5]]),
        res("res_gold_1", 6, 10, "gold", 500), res("res_gold_2", 10, 8, "gold", 750), res("res_gold_3", 18, 12, "gold", 1000),
        res("res_wood_1", 2, 9, "wood", 5), res("res_ore_1", 5, 5, "ore", 5), res("res_mercury_1", 14, 6, "mercury", 3),
        res("res_gems_1", 21, 13, "gems", 2),
        army("neutral_channel", 7, 12, "Drowned in the channel", [["shambler", 14]]),
        army("neutral_gap", 16, 4, "Carrion on the mounds", [["carrion_flock", 10]]),
        army("neutral_wisps", 13, 14, "Fen lights", [["corpse_light", 8]]),
        enc("enc_barrows", 14, 10, "barrow_field"), enc("enc_chapel", 3, 2, "drowned_chapel"),
        art("art_coif", 9, 2, "bonewright_coif"), art("art_hourglass", 22, 11, "hourglass_of_marrow"),
    ],
}

# ------------------------------------------------- chapter 5: twice dead
# The other side of The Last Light chapter 4. Orrin has fallen and his body lies
# in Greyhold. The Regent's fens in the west, the flooded dike with one crossing,
# Fenwick on the south road and Greyhold behind its hills in the east.
g = Grid(28, 20, '.')
g.rect(0, 0, 27, 0, '^'); g.rect(0, 19, 27, 19, '^')
g.rect(0, 1, 10, 18, 'w')                 # the fens
g.blob(3, 10, 2.2, '.')                   # Saint Orrin's Rest
g.rect(11, 1, 11, 8, '#'); g.rect(11, 12, 11, 18, '#')    # the flooded dike
g.blob(16, 4, 2.0, 'f'); g.blob(17, 15, 2.2, 'f'); g.blob(22, 3, 1.5, 'f')
g.rect(20, 7, 20, 8, '^'); g.rect(20, 12, 20, 13, '^')    # Greyhold's hills
g.blob(25, 16, 1.2, '^')
maps["twice_dead"] = {
    "_doc": "The Pale Inheritance chapter 5. Hand-made (tools/maps/build_pale_inheritance_maps.py). The Last Light chapter 4 from the other side: Orrin has fallen and his body lies in Greyhold. Ysmay and Corvin cross the dike from Saint Orrin's Rest, through Fenwick, to Greyhold. Both sides are capped at tier 5.",
    "id": "twice_dead", "name": "Twice Dead", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(2, 10), (25, 10)]) + roads([(14, 10), (14, 15)]) + roads([(2, 10), (2, 4)]),
    "players": [COURT, player(1, "Aldmere Concord", "concord")],
    "heroes": [
        hero("hero_ysmay", "Ysmay Vane", "necromancer", 0, 3, 10,
             [["shambler", 50], ["marrow_archer", 22], ["gravecrawler", 10], ["wailing_shade", 6], ["corpse_weaver", 4]]),
        hero("hero_corvin", "Father Corvin Mire", "blightcaller", 0, 3, 11, [["shambler", 30], ["marrow_archer", 12], ["gravecrawler", 5]]),
        hero("hero_wren", "Aldous Wren", "knight", 1, 23, 10,
             [["pike_militia", 40], ["longbowman", 22], ["shieldwarden", 10], ["lancer", 6], ["lightbearer", 3]]),
        hero("hero_maelis", "Maelis Thorne", "ranger", 1, 14, 14, [["longbowman", 16], ["pike_militia", 14], ["lancer", 2]]),
    ],
    "objects": [
        town("town_orrins_rest", 2, 10, "hollow", "Saint Orrin's Rest", 0,
             ["h_hall", "h_tavern", "h_market", "h_fort1", "h_fort2", "h_dw1", "h_dw2", "h_dw3", "h_dw4"], [["shambler", 20]]),
        town("town_fenwick", 14, 15, "concord", "Fenwick", 1, ["c_hall", "c_palisade", "c_dw1", "c_dw2", "c_dw3"],
             [["pike_militia", 20], ["longbowman", 8]]),
        town("town_greyhold", 25, 10, "concord", "Greyhold", 1,
             ["c_hall", "c_tavern", "c_market", "c_palisade", "c_keep", "c_dw1", "c_dw2", "c_dw3", "c_dw4", "c_dw5"],
             [["pike_militia", 30], ["longbowman", 14], ["shieldwarden", 8]]),
        mine("mine_wood", 5, 4, "wood"), mine("mine_ore", 5, 16, "ore"),
        mine("mine_mercury", 8, 13, "mercury", [["bog_lurker", 6]]),
        mine("mine_gold", 17, 2, "gold", [["hill_troll", 4]]),
        mine("mine_crystal", 22, 17, "crystal", [["deserter_crossbows", 10]]), mine("mine_gems", 24, 4, "gems"),
        res("res_gold_1", 6, 8, "gold", 750), res("res_gold_2", 13, 6, "gold", 1000), res("res_gold_3", 26, 14, "gold", 1500),
        res("res_wood_1", 1, 2, "wood", 6), res("res_ore_1", 9, 17, "ore", 5), res("res_mercury_1", 7, 3, "mercury", 3),
        res("res_crystal_1", 18, 11, "crystal", 3), res("res_gems_1", 23, 17, "gems", 3),
        army("neutral_dike", 11, 10, "The dike watch", [["deserter_crossbows", 12], ["road_cutthroat", 10]]),
        army("neutral_pilgrims", 18, 10, "Lantern pilgrims", [["lost_pilgrims", 30]]),
        enc("enc_chapel", 7, 7, "drowned_chapel"), enc("enc_courier", 19, 5, "dying_courier"), enc("enc_barrows", 4, 17, "barrow_field"),
        art("art_visor", 9, 2, "gravewatch_visor"), art("art_brigandine", 16, 17, "ossuary_brigandine"),
        art("art_pennant", 26, 2, "tattered_pennant"),
    ],
}

# ------------------------------------------------- chapter 10: the pale crown
# One against two. The Regent's mound in the west; the Barrow Below in the
# middle, broken ground behind a drowned channel with three gaps; the burning
# tunnels in the east, where two Ashen broods hold a town each on either side
# of a cinder ridge. The broods are separate players, so they also fight each other.
g = Grid(34, 26, 'w')
g.rect(0, 0, 33, 0, '^'); g.rect(0, 25, 33, 25, '^')
g.blob(4, 13, 3.5, '.')                   # the crowning mound
g.rect(12, 1, 21, 24, 'r')                # the Barrow Below
g.blob(16, 7, 2.0, '^'); g.blob(17, 18, 2.0, '^')         # collapsed vaults
g.rect(22, 1, 33, 24, 'i')                # the burning tunnels
g.rect(25, 11, 33, 14, '^')               # the cinder ridge between the broods
g.rect(11, 1, 11, 24, '#')                # the drowned channel
for y in (5, 12, 13, 20):
    g.set(11, y, 'w')
maps["pale_crown"] = {
    "_doc": "The Pale Inheritance chapter 10, one against two. Hand-made (tools/maps/build_pale_inheritance_maps.py). Ysmay's mound in the west, the Barrow Below in the middle and two Ashen broods in the burning tunnels in the east: Skarn Ashborn's Burrow-Host in the north, Ithra Sootveil's brood in the south. The broods are allied computer players (team 1), at the easy difficulty (one against two).",
    "id": "pale_crown", "name": "The Pale Crown", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(3, 13), (23, 13)]) + roads([(23, 13), (23, 5), (30, 5)]) + roads([(23, 13), (23, 20), (30, 20)]),
    "players": [COURT, player(1, "The Burrow-Host", "ashen", difficulty="easy", team=1), player(2, "The Sootveil Brood", "ashen", color="#d0782c", difficulty="easy", team=1)],
    "heroes": [
        hero("hero_ysmay", "Ysmay Vane", "necromancer", 0, 4, 13,
             [["shambler", 90], ["marrow_archer", 40], ["gravecrawler", 20], ["wailing_shade", 12], ["corpse_weaver", 8],
              ["gibbet_knight", 4], ["charnel_hulk", 2]]),
        hero("hero_orrin", "Sir Orrin Wren", "gravewarden", 0, 4, 12,
             [["shambler", 50], ["marrow_archer", 20], ["gravecrawler", 10], ["gibbet_knight", 4]]),
        hero("hero_corvin", "Father Corvin Mire", "blightcaller", 0, 4, 14,
             [["shambler", 40], ["marrow_archer", 18], ["wailing_shade", 6], ["corpse_weaver", 6]]),
        hero("hero_skarn", "Skarn Ashborn", "warlord", 1, 28, 5,
             [["cinderling", 80], ["scorchhound", 30], ["brimstone_hurler", 20], ["flayer", 12], ["ash_witch", 6],
              ["gorgewing", 4], ["pyre_titan", 1], ["cinder_maw", 1]]),
        hero("hero_ithra", "Ithra Sootveil", "warlock", 2, 28, 20,
             [["cinderling", 60], ["scorchhound", 20], ["brimstone_hurler", 16], ["ash_witch", 8], ["gorgewing", 3]]),
    ],
    "objects": [
        town("town_sallowmere", 3, 13, "hollow", "Sallowmere", 0,
             ["h_hall", "h_court", "h_tavern", "h_market", "h_fort1", "h_fort2", "h_dw1", "h_dw2", "h_dw3", "h_dw4", "h_dw5", "h_dw6",
              "h_up1", "h_up2"], [["shambler", 40], ["marrow_archer", 16]]),
        town("town_barrow_gate", 16, 13, "hollow", "The Barrow Gate", -1, ["h_hall", "h_fort1", "h_dw1", "h_dw2", "h_dw3"],
             [["cinderling", 40], ["scorchhound", 12]]),
        town("town_burrow_mouth", 30, 5, "ashen", "The Burrow-Mouth", 1,
             ["a_hall", "a_den", "a_market", "a_trench", "a_wall", "a_dw1", "a_dw2", "a_dw3", "a_dw4", "a_dw5", "a_dw6"],
             [["cinderling", 50], ["scorchhound", 20], ["brimstone_hurler", 12]]),
        town("town_sootpit", 30, 20, "ashen", "The Sootpit", 2,
             ["a_hall", "a_market", "a_trench", "a_dw1", "a_dw2", "a_dw3", "a_dw4", "a_dw5"],
             [["cinderling", 40], ["brimstone_hurler", 10]]),
        mine("mine_wood", 6, 4, "wood"), mine("mine_ore", 6, 21, "ore"),
        mine("mine_mercury", 14, 3, "mercury", [["tomb_scarabs", 16]]),
        mine("mine_sulfur", 19, 22, "sulfur", [["ashscale_basilisk", 6]]),
        mine("mine_gold", 14, 22, "gold", [["barrow_revenant", 6]]),
        mine("mine_crystal", 26, 9, "crystal"), mine("mine_gems", 26, 16, "gems"),
        res("res_gold_1", 7, 10, "gold", 1000), res("res_gold_2", 13, 15, "gold", 1500), res("res_gold_3", 20, 10, "gold", 2000),
        res("res_wood_1", 2, 3, "wood", 8), res("res_ore_1", 2, 22, "ore", 8), res("res_mercury_1", 9, 18, "mercury", 4),
        res("res_sulfur_1", 24, 2, "sulfur", 4), res("res_crystal_1", 19, 2, "crystal", 4), res("res_gems_1", 32, 23, "gems", 4),
        army("neutral_gap_north", 11, 5, "Burrower sappers", [["tomb_scarabs", 20]]),
        army("neutral_gap_mid", 11, 13, "The drowned host", [["barrow_revenant", 10]]),
        army("neutral_gap_south", 11, 20, "Cinder wraiths", [["cinder_wraith", 8]]),
        army("neutral_tunnel_north", 23, 9, "Basilisks in the vents", [["ashscale_basilisk", 10]]),
        army("neutral_tunnel_south", 23, 17, "Cinder wraiths", [["cinder_wraith", 10]]),
        enc("enc_barrows", 8, 8, "barrow_field"), enc("enc_rift", 19, 4, "ember_rift"),
        enc("enc_champion", 24, 22, "ash_pit_champion"), enc("enc_echoes", 14, 16, "hall_of_echoes"),
        art("art_crowcrest", 3, 5, "crowcrest_helm"), art("art_shroud", 21, 12, "shroud_of_ash"),
        art("art_sceptre", 32, 9, "sceptre_of_the_pyre"),
    ],
}


# The layouts above are drawn on small grids; the maps are played larger
# (playtests, Nov 7: the campaign maps felt small, twice). See maplib.enlarge.
enlarge(maps, {"warm_earth": 2.5, "twice_dead": 2.65, "pale_crown": 2.7})


# Map overhaul (Nov 9): same layouts, with patches of neighbouring ground over
# the flat single-biome blocks and the terrain painter's dressing (after build()).
import rebuild as rb
for _mid, _seed in (("warm_earth", 1), ("twice_dead", 5), ("pale_crown", 10)):
    rb.texture(maps[_mid], _seed)
build(maps, OUT)
if OUT:
    for _mid, _seed in (("warm_earth", 1), ("twice_dead", 5), ("pale_crown", 10)):
        rb.dress_hand_made(OUT, _mid, _seed)


# ============================================================================
# Chapters rebuilt from frozen generator maps (map overhaul phase 3, Nov 9).
# Each starts from a generated layout (seed picked from a contact sheet), gets
# the story's ground, towns, heroes and landmarks, and is written re-dressed.
# Needs Godot (set $GODOT); story text and casts live in data/campaigns.json,
# chapter scenarios are collected in SCENARIOS (see update_campaign below).
# ============================================================================
from rebuild import *

NEUTRAL = ["wilds"]
SCENARIOS = {}
FEN = biome("w", [("f", "f"), ("r", "r"), (".", "."), ("d", "r"), ("s", "w"), ("i", "r")])
DEEP = biome("r", [("i", "i"), ("w", "w"), ("f", "r"), (".", "r"), ("d", "i"), ("s", "r")])
COURT_ARMY = [["shambler", 34], ["marrow_archer", 12], ["gravecrawler", 4]]


def ph_barrow_lords():
    """Chapter 2, The Barrow Lords (L). A branching fen: the Court in Cairnholt
    in the west, Morrow of the Deep Fen and the barrow-lords' seat in the east,
    dead-end barrow valleys off every branch."""
    d = start("gen:random_xl_2p_normal_normal_tree:1", "ph_barrow_lords", "The Barrow Lords",
              "The Pale Inheritance chapter 2. Branching fen valleys: the Regent's court in Cairnholt in the west, the barrow-lords behind Morrow of the Deep Fen in the east.")
    repaint(d, {"start_0": biome("w", [("f", "f"), (".", "r")]), "start_1": biome("w", [("r", "r"), ("f", "f"), ("i", "r")]),
                "heart": biome("r", [("w", "w"), ("d", "w")])}, default=FEN)
    d["players"] = [player(0, "The Regent's Court", "hollow", human=True), player(1, "The Barrow-Lords", "hollow", color="#7a5a8a")]
    town_set(obj(d, "town_start_0"), "hollow", "Cairnholt", 0, buildings("hollow", 2, ["fort1"]), [["shambler", 12]])
    town_set(obj(d, "town_start_1"), "hollow", "Deepfen Barrow", 1, buildings("hollow", 3, ["fort1"]), [["shambler", 18], ["marrow_archer", 6]])
    for t in objs(d, "town", owner=-1):
        town_set(t, "hollow", "Barrowmere", -1, ["h_hall", "h_dw1", "h_dw2"], [["barrow_revenant", 6], ["corpse_light", 12]])
    hero_set(obj(d, "hero_p0"), "hero_p0", "Ysmay Vane", "necromancer", 0, COURT_ARMY)
    hero_set(obj(d, "hero_p1"), "hero_p1", "Morrow of the Deep Fen", "gravewarden", 1, troops("hollow", [40, 14, 6]))
    for t in [obj(d, "town_start_1")] + objs(d, "town", owner=-1):
        x, y = t["pos"]
        ring(d, x, y, 5, ["gravestone", "dead_tree", "gravestone", "boulders"])
    finish(OUT, d, 1, NEUTRAL + ["hollow"])


def ph_living_shore():
    """Chapter 3, The Living Shore (A, 2v2). A four-realm ring on the Concord
    coast: the Court in the south, the Drowned Choir (allied Hollow) in the
    west, Brother Tamsin Hale's Fenwick in the north and the Shore Levies on
    the eastern coast, a beach and reed pools on the sea."""
    d = start("gen:random_l_4p_normal_normal_ring:3", "ph_living_shore", "The Living Shore",
              "The Pale Inheritance chapter 3 (2 against 2). The Concord's coastal marches: the Court and the Drowned Choir against Fenwick and the Shore Levies, with the sea on the eastern edge.")
    z = place_slots(d, {0: "s", 1: "n", 2: "w", 3: "e"})
    farms = biome(".", [("f", "f"), ("r", "r"), ("w", "w"), ("s", "."), ("i", "."), ("d", ".")])
    repaint(d, {z[0]: FEN, z[2]: biome("w", [("f", "f"), ("r", "r")]), z[1]: biome(".", [("f", "f"), ("r", "r")]),
                z[3]: biome(".", [("f", "f"), ("w", "w")])}, default=farms)
    coast(d, "e", sea=2, beach=4)
    d["players"] = [player(0, "The Regent's Court", "hollow", human=True, team=1),
                    player(1, "Fenwick", "concord", team=2),
                    player(2, "The Drowned Choir", "hollow", team=1, color="#4a7a8a"),
                    player(3, "The Shore Levies", "concord", team=2, color="#7aa0d0")]
    town_set(zone_town(d, z[0]), "hollow", "Sallowgate", 0, buildings("hollow", 3, ["fort1", "market"]), [["shambler", 16]])
    town_set(zone_town(d, z[2]), "hollow", "The Sunken Chapel", 2, buildings("hollow", 3), [["shambler", 20], ["marrow_archer", 6]])
    town_set(zone_town(d, z[1]), "concord", "Fenwick", 1, buildings("concord", 3, ["fort1"]), [["pike_militia", 20], ["longbowman", 8]])
    town_set(zone_town(d, z[3]), "concord", "Saltmarch", 3, buildings("concord", 3, ["market"]), [["pike_militia", 18], ["longbowman", 10]])
    for t in objs(d, "town", owner=-1):
        town_set(t, "concord", "Millbridge", -1, ["c_hall", "c_dw1", "c_dw2", "c_dw3"], [["pike_militia", 40], ["longbowman", 20], ["shieldwarden", 8]])
    hero_set(obj(d, "hero_p0"), "hero_p0", "Ysmay Vane", "necromancer", 0, COURT_ARMY)
    hero_set(obj(d, "hero_p1"), "hero_p1", "Brother Tamsin Hale", "oracle", 1, troops("concord", [36, 18, 8]))
    hero_set(obj(d, "hero_p2"), "hero_p2", "The Drowned Cantor", "necromancer", 2, troops("hollow", [40, 14, 6]))
    hero_set(obj(d, "hero_p3"), "hero_p3", "Captain Ilse Marrow", "knight", 3, troops("concord", [30, 16, 8]))
    W, H = d["width"], d["height"]
    for y in range(8, H - 8, 14):
        scenery_near(d, W - 8, y, ["scenery_reed_pool", "scenery_weeping_willow"], 1)
    SCENARIOS["ph_living_shore"] = {
        "name": "The Living Shore", "mode": "alliance", "player": 0,
        "objectives": [
            {"id": "choir", "type": "ally_survives", "player": 2, "text": "Keep the Drowned Choir in the field."},
            {"id": "conquer", "type": "conquer", "text": "Drive Fenwick and the Shore Levies out of the marches."}]}
    finish(OUT, d, 3, NEUTRAL + ["concord"])


def ph_rot():
    """Chapter 4, The Rot (T). The townless recipe: the Court marches north with
    no town between the fen and the Elderwold. Charnel hamlets sell Hollow folk,
    the druids hold the Charnel House, and Grovewarden Cerrid Ashbark's camp
    stands in the north-east. Burned strips run across the fen's edge."""
    d = start("scenario:townless_v1:5", "ph_rot", "The Rot",
              "The Pale Inheritance chapter 4 (townless start). The court marches north without a town: free the charnel hamlets, take the Charnel House from the druids, then burn out Cerrid Ashbark's camp.")
    d.pop("scenario")
    repaint(d, {"start_0": FEN, "wild_0": FEN, "flank_0": biome("w", [("f", "f"), (".", ".")]), "heart": biome("f", [("w", "w"), (".", ".")]),
                "flank_1": biome("f", [(".", "."), ("w", "w")]), "wild_1": biome("f", [(".", ".")]), "start_1": biome("f", [(".", "."), ("r", "r")])})
    unseal_pockets(d)   # twin_marches seals its treasure pockets; guards hold prizes since #135
    burn_strips(d, 9, 14, 4)
    d["players"] = [player(0, "The Regent's Court", "hollow", human=True), player(1, "The Thornwood Covenant", "thornwood")]
    town_set(obj(d, "town_start_0"), "hollow", "The Charnel House", -1, ["h_hall", "h_dw1", "h_dw2", "h_dw3"],
             [["thorn_skulker", 36], ["barkhide_warden", 40], ["briar_huntress", 12], ["rootbinder", 6]])
    town_set(obj(d, "town_start_1"), "thornwood", "Ashbark Camp", 1, buildings("thornwood", 4, ["fort1"]), [["thorn_skulker", 24], ["barkhide_warden", 14]])
    for t, name in zip(sorted(objs(d, "town", owner=-1), key=lambda o: o["id"]), ("Briarwatch", "Rotmere", "Elderfall")):
        if t["id"] != "town_start_0":
            town_set(t, "thornwood", name, -1, ["t_hall", "t_dw1", "t_dw2"], [["thornwolf", 14], ["moss_creeper", 20]])
    stocks = [[["shambler", 34], ["marrow_archer", 10]], [["gravecrawler", 8], ["shambler", 20]],
              [["marrow_archer", 16]], [["gravecrawler", 7], ["marrow_archer", 8]]]
    for i, o in enumerate(sorted((o for o in d["objects"] if o.get("zone") == "townless" and o["type"] == "site"), key=lambda o: o["id"])):
        keep(o)["site"] = "ashfield_steading"
        o["stock"] = stocks[i % len(stocks)]
        o["guard"] = [["thornwolf", 6]] if i % 2 else [["moss_creeper", 16]]
    hero_set(obj(d, "hero_p0"), "hero_p0", "Ysmay Vane", "necromancer", 0, [["shambler", 42], ["marrow_archer", 16], ["gravecrawler", 8], ["wailing_shade", 3]])
    hero_set(obj(d, "hero_p1"), "hero_p1", "Cerrid Ashbark", "grovewarden", 1, troops("thornwood", [40, 16, 10, 4]))
    # The carvings Corvin finds: a ring of elder stumps round the elder rings, between the start and the Charnel House.
    hx, hy = obj(d, "hero_p0")["pos"]
    tx, ty = obj(d, "town_start_0")["pos"]
    p = free_near(d, (hx + tx) // 2, (hy + ty) // 2, margin=2)
    keep(village(d, "site_carved_stumps", p, "elder_rings", None, [["moss_creeper", 18]]))
    obj(d, "site_carved_stumps").pop("stock")
    ring(d, p[0], p[1], 3, ["charred_tree", "dead_tree"])
    ring(d, p[0], p[1], 5, ["charred_tree", "dead_tree", "bones"])
    finish(OUT, d, 5, NEUTRAL + ["thornwood"])


def ph_lantern_siege():
    """Chapter 6, The Lantern Siege (B, betrayal). A three-realm ring: the Court
    in the south, the Fenwick Levies (a knight who surrendered, allied for now)
    beside the Court, Abbess Maud Lorne's temple-fortress on its hill in the north,
    with standing lamps on its approach. The levies turn when a Court hero comes
    within 6 tiles of the temple."""
    d = start("gen:random_xl_3p_normal_normal_ring:3", "ph_lantern_siege", "The Lantern Siege",
              "The Pale Inheritance chapter 6 (betrayal). The Court and the Fenwick Levies march on the Lantern Temples; the levies turn back to the light at the temple's foot.")
    z = place_slots(d, {0: "s", 1: "n", 2: "w"})
    repaint(d, {z[0]: FEN, z[1]: biome("r", [(".", "."), ("f", "f"), ("i", "r"), ("d", "r")]), z[2]: biome(".", [("f", "f"), ("w", "w")])},
            default=biome(".", [("f", "f"), ("r", "r"), ("w", "w"), ("d", "."), ("s", "."), ("i", "r")]))
    d["players"] = [player(0, "The Regent's Court", "hollow", human=True, team=1),
                    player(1, "The Lantern Temples", "concord", team=2, color="#e0c060"),
                    player(2, "The Fenwick Levies", "concord", team=1, color="#7aa0d0")]
    temple = zone_town(d, z[1])
    town_set(zone_town(d, z[0]), "hollow", "Sallowgate", 0, buildings("hollow", 5, ["fort1", "market"]), [["shambler", 30], ["marrow_archer", 10]])
    town_set(temple, "concord", "The Lantern Fortress", 1, buildings("concord", 5, ["fort1", "fort2", "fort3", "market"]),
             [["pike_militia", 40], ["longbowman", 24], ["shieldwarden", 12], ["lightbearer", 6]])
    town_set(zone_town(d, z[2]), "concord", "Fenwick", 2, buildings("concord", 3), [["pike_militia", 24], ["longbowman", 10]])
    for t in objs(d, "town", owner=-1):
        town_set(t, "concord", "Lampwick", -1, ["c_hall", "c_dw1", "c_dw2", "c_dw3", "c_dw4"], [["pike_militia", 50], ["longbowman", 24], ["lancer", 8]])
    hero_set(obj(d, "hero_p0"), "hero_p0", "Ysmay Vane", "necromancer", 0, [["shambler", 50], ["marrow_archer", 22], ["gravecrawler", 10], ["wailing_shade", 6]])
    hero_set(obj(d, "hero_p1"), "hero_p1", "Abbess Maud Lorne", "oracle", 1, troops("concord", [60, 30, 16, 8, 6]))
    hero_set(obj(d, "hero_p2"), "hero_p2", "Sir Garran of Fenwick", "knight", 2, troops("concord", [40, 18, 10, 4]))
    # The temple on its hill: rough ground and standing lamps along the roads in.
    tx, ty = temple["pos"]
    rows = [list(r) for r in d["terrain"]]
    for y in range(ty - 6, ty + 7):
        for x in range(tx - 6, tx + 7):
            if 0 <= x < d["width"] and 0 <= y < d["height"] and rows[y][x] in ".fwds":
                rows[y][x] = "r"
    d["terrain"] = ["".join(r) for r in rows]
    roads_near = sorted((p for p in road_tiles(d) if 4 <= math.hypot(p[0] - tx, p[1] - ty) <= 14), key=lambda p: (math.hypot(p[0] - tx, p[1] - ty), p))
    lamps = 0
    for (x, y) in roads_near[::3]:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if lamps < 8 and scenery(d, x + dx, y + dy, "scenery_oath_stones"):
                lamps += 1
                break
    SCENARIOS["ph_lantern_siege"] = {
        "name": "The Lantern Siege", "mode": "betrayal", "player": 0,
        "betrayal": {"player": 2, "joins": 1, "trigger": {"reach": {"pos": temple["pos"], "radius": 6}},
                     "text": "The lanterns call the living home.", "reinforcements": troops("concord", [30, 16, 8, 4])},
        "objectives": [
            {"id": "levies", "type": "ally_survives", "player": 2, "until_betrayal": True, "text": "Keep the Fenwick Levies with the Court."},
            {"id": "temple", "type": "control_towns", "towns": [temple["id"]], "text": "Take the Lantern Fortress."},
            {"id": "conquer", "type": "conquer", "text": "Put out every lantern."}]}
    finish(OUT, d, 3, NEUTRAL + ["concord"])


def ph_deep_barrows():
    """Chapter 7, The Deep Barrows (C). The Barrow Below: a three-realm ring of
    tunnels and burial halls. The Court comes down in the west; Garsh
    Emberclaw's burrowers hold two warrens dug in from the east."""
    d = start("gen:random_xl_3p_normal_normal_ring:7", "ph_deep_barrows", "The Deep Barrows",
              "The Pale Inheritance chapter 7. The Barrow Below: the Court in the western halls, Garsh Emberclaw's Ashen burrowers in two warrens dug in from the east.")
    z = place_slots(d, {0: "w", 1: "e", 2: "n"})
    repaint(d, {z[0]: biome("w", [("r", "r"), ("f", "w"), (".", "r")]), z[1]: biome("i", [("r", "r"), ("d", "i")]),
                z[2]: biome("i", [("r", "r"), ("w", "r")])}, default=DEEP)
    d["players"] = [player(0, "The Regent's Court", "hollow", human=True), player(1, "Emberclaw's Burrowers", "ashen")]
    town_set(zone_town(d, z[0]), "hollow", "The Bone Gate", 0, buildings("hollow", 6, ["fort1", "market"]), [["shambler", 30], ["marrow_archer", 12]])
    town_set(zone_town(d, z[1]), "ashen", "Emberclaw Warren", 1, buildings("ashen", 6, ["fort1", "fort2"]), [["cinderling", 40], ["scorchhound", 16]])
    town_set(zone_town(d, z[2]), "ashen", "The Scored Halls", 1, buildings("ashen", 4, ["fort1"]), [["cinderling", 36], ["brimstone_hurler", 10]])
    d["heroes"] = [h for h in d["heroes"] if h["owner"] != 2]
    for t in objs(d, "town", owner=-1):
        town_set(t, "hollow", "The Ossuary", -1, ["h_hall", "h_dw1", "h_dw2", "h_dw3", "h_dw4"], [["barrow_revenant", 14], ["cinder_wraith", 8]])
    hero_set(obj(d, "hero_p0"), "hero_p0", "Ysmay Vane", "necromancer", 0, [["shambler", 60], ["marrow_archer", 26], ["gravecrawler", 12], ["wailing_shade", 8]])
    hero_set(obj(d, "hero_p1"), "hero_p1", "Garsh Emberclaw", "warlord", 1, troops("ashen", [70, 30, 18, 10, 6, 2]))
    for zone in sorted(zones(d)):
        ax, ay = zones(d)[zone]["anchor"]
        scatter(d, ax, ay, 7, ["bones", "obsidian", "gravestone", "boulders"], every=6)
    finish(OUT, d, 7, NEUTRAL + ["ashen", "hollow"])


def ph_hungry_fire():
    """Chapter 8, The Hungry Fire (S, survival). Three tomb towns of the Court
    in the western Barrow Below must stand through day 28 while Morvath the
    Kindler holds the eastern tunnels and sends waves of burners west."""
    d = start("gen:random_xl_3p_normal_normal_ring:6", "ph_hungry_fire", "The Hungry Fire",
              "The Pale Inheritance chapter 8 (survival). Hold the three tombs of the Barrow Below through day 28 against Morvath the Kindler's fires from the east tunnels.")
    z = place_slots(d, {0: "w", 1: "e", 2: "s"})
    repaint(d, {z[0]: biome("w", [("r", "r"), (".", "r")]), z[2]: biome("r", [("w", "w"), ("i", "r")]), z[1]: biome("i", [("r", "r")])}, default=DEEP)
    d["players"] = [player(0, "The Regent's Court", "hollow", human=True), player(1, "Morvath's Kindlers", "ashen"),
                    player(2, "The Burning Host", "ashen", color="#e06a2a")]
    tombs = [zone_town(d, z[0]), zone_town(d, z[2])]
    town_set(tombs[0], "hollow", "The Regent's Tomb", 0, buildings("hollow", 7, ["fort1", "fort2", "market"]), [["shambler", 40], ["marrow_archer", 16]])
    town_set(tombs[1], "hollow", "The Tomb of Kings", 0, buildings("hollow", 4, ["fort1"]), [["shambler", 30], ["gravecrawler", 8]])
    rest = sorted(objs(d, "town", owner=-1), key=lambda t: math.hypot(t["pos"][0] - tombs[0]["pos"][0], t["pos"][1] - tombs[0]["pos"][1]))
    third = rest[0]
    town_set(third, "hollow", "The Weeping Tomb", 0, buildings("hollow", 3, ["fort1"]), [["shambler", 30], ["marrow_archer", 10]])
    tombs.append(third)
    for t in rest[1:]:
        town_set(t, "ashen", "The Kindling Pit", -1, ["a_hall", "a_dw1", "a_dw2", "a_dw3"], [["cinder_wraith", 12], ["ashscale_basilisk", 10]])
    town_set(zone_town(d, z[1]), "ashen", "Morvath's Furnace", 1, buildings("ashen", 7, ["fort1", "fort2"]), [["cinderling", 50], ["scorchhound", 20]])
    d["heroes"] = [h for h in d["heroes"] if h["owner"] != 2]
    hero_set(obj(d, "hero_p0"), "hero_p0", "Ysmay Vane", "necromancer", 0, [["shambler", 70], ["marrow_archer", 30], ["gravecrawler", 14], ["wailing_shade", 10]])
    hero_set(obj(d, "hero_p1"), "hero_p1", "Morvath the Kindler", "tormentor", 1, troops("ashen", [80, 34, 20, 12, 8, 4, 1]))
    grid = zone_grid(d)
    east = sorted((zid for zid in zones(d) if zones(d)[zid]["anchor"][0] > d["width"] * 0.55 and zid != z[1]), key=lambda k: zones(d)[k]["anchor"][1])
    waves = []
    plan = [(6, [60, 24, 10, 4]), (11, [70, 30, 14, 6, 3]), (16, [80, 34, 16, 8, 4, 2]), (21, [90, 40, 20, 10, 6, 3]),
            (26, [100, 44, 24, 12, 8, 4, 1])]
    for i, (day, counts) in enumerate(plan):
        zone = east[i % len(east)]
        ax, ay = zones(d)[zone]["anchor"]
        p = free_near(d, ax, ay, margin=1, zone=zone, grid=grid)
        target = tombs[i % 3]["id"]
        waves.append({"id": "fire_wave_%d" % i, "day": day, "warning_days": 3, "owner": 2, "spawn": p, "entry_tiles": [p],
                      "entry_name": "the east tunnels", "target": target, "targets": [t["id"] for t in tombs], "order": "assault",
                      "hero": {"id": "fire_commander_%d" % i, "name": ["Ember Burrower", "Pyre Warden", "Soot Captain", "Cinder Abbot", "The Last Kindling"][i],
                               "class": "tormentor", "army": troops("ashen", counts)}})
    for t in tombs:
        x, y = t["pos"]
        ring(d, x, y, 4, ["gravestone", "bones", "gravestone"])
    SCENARIOS["ph_hungry_fire"] = {
        "name": "The Hungry Fire", "mode": "survival", "player": 0, "castle": tombs[0]["id"],
        "protected_towns": [t["id"] for t in tombs], "invasion_players": [2], "max_active_invaders": 3, "waves": waves,
        "wave_strength": {"easy": 0.75, "normal": 1.0, "hard": 1.25},
        "objectives": [
            {"id": "hold", "type": "survive", "through_day": 28, "text": "Hold the three tombs through day 28."},
            {"id": "fires", "type": "clear_waves", "optional": True, "text": "Put out every fire Morvath sends."}]}
    finish(OUT, d, 6, NEUTRAL + ["ashen"])


def ph_leviathan():
    """Chapter 9, The Leviathan Mire (C). The deep: the Court in the west with the
    Leviathan Mire (a swamp, reed pools and willows) beside its town, Skarn
    Ashborn with two towns in the east."""
    d = start("gen:random_xl_3p_normal_normal_ring:10", "ph_leviathan", "The Leviathan Mire",
              "The Pale Inheritance chapter 9. The Barrow Below: the Court and the drowned Leviathan Mire in the west, Skarn Ashborn's two strongholds in the east.")
    z = place_slots(d, {0: "w", 1: "e", 2: "n"})
    repaint(d, {z[0]: biome("w", [("r", "r"), (".", "w")]), z[1]: biome("i", [("r", "r"), ("d", "i")]), z[2]: biome("i", [("r", "r")])}, default=DEEP)
    d["players"] = [player(0, "The Regent's Court", "hollow", human=True), player(1, "The Burrow-Host", "ashen")]
    home = zone_town(d, z[0])
    town_set(home, "hollow", "The Mire Gate", 0, buildings("hollow", 7, ["fort1", "fort2", "market"]), [["shambler", 40], ["marrow_archer", 16]])
    town_set(zone_town(d, z[1]), "ashen", "Skarn's Forge-Pit", 1, buildings("ashen", 8, ["fort1", "fort2", "fort3"]), [["cinderling", 60], ["scorchhound", 24], ["flayer", 8]])
    town_set(zone_town(d, z[2]), "ashen", "The Ember Deep", 1, buildings("ashen", 6, ["fort1", "fort2"]), [["cinderling", 50], ["brimstone_hurler", 14]])
    d["heroes"] = [h for h in d["heroes"] if h["owner"] != 2]
    for t in objs(d, "town", owner=-1):
        town_set(t, "hollow", "The Drowned Ossuary", -1, ["h_hall", "h_dw1", "h_dw2", "h_dw3", "h_dw4", "h_dw5"], [["bog_serpent", 6], ["barrow_revenant", 16]])
    hero_set(obj(d, "hero_p0"), "hero_p0", "Ysmay Vane", "necromancer", 0, [["shambler", 80], ["marrow_archer", 34], ["gravecrawler", 16], ["wailing_shade", 10]])
    hero_set(obj(d, "hero_p1"), "hero_p1", "Skarn Ashborn", "warlord", 1, troops("ashen", [100, 40, 24, 14, 10, 6, 2]))
    # The Leviathan Mire: a swamp blob beside the Court's town, ringed with reeds and willows.
    hx, hy = home["pos"]
    cx, cy = free_near(d, hx + 7, hy + 5, margin=2)
    rows = [list(r) for r in d["terrain"]]
    for y in range(cy - 5, cy + 6):
        for x in range(cx - 6, cx + 7):
            if 0 <= x < d["width"] and 0 <= y < d["height"] and rows[y][x] in ".fdsir" and ((x - cx) / 6) ** 2 + ((y - cy) / 5) ** 2 <= 1:
                rows[y][x] = "w"
    d["terrain"] = ["".join(r) for r in rows]
    scenery_near(d, cx, cy, ["scenery_reed_pool", "scenery_weeping_willow", "scenery_reed_pool"], 6)
    ring(d, cx, cy, 6, ["bones", "dead_tree", "bones"], count=16)
    finish(OUT, d, 10, NEUTRAL + ["ashen", "hollow"])


SCENARIOS["ph_rot"] = {
    "name": "The Rot", "mode": "townless", "player": 0, "townless_players": [0],
    "objectives": [
        {"id": "charnel", "type": "control_towns", "towns": ["town_start_0"], "text": "Take the Charnel House from the druids."},
        {"id": "conquer", "type": "conquer", "text": "Burn out Cerrid Ashbark's camp."}]}

if OUT:
    built = (ph_barrow_lords, ph_living_shore, ph_rot, ph_lantern_siege, ph_deep_barrows, ph_hungry_fire, ph_leviathan)
    for build_chapter in built:
        build_chapter()
    update_campaign("pale_inheritance", {f.__name__: {"map": f.__name__, "scenario": SCENARIOS.get(f.__name__)} for f in built})
