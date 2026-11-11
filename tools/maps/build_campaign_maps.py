"""Builds the hand-made Ashen chapter maps of The Last Light (chapters 8-10, once the Ember Chronicle) (burning_ford, ashes_return, into_the_embers).

Edit the layouts here, then regenerate:  python3 tools/maps/build_campaign_maps.py data/maps
and run ./run_tests.sh campaign_maps (validity, enemies, escalating difficulty).
"""
import json, sys, math
OUT = sys.argv[1]

class Grid:
    def __init__(s, w, h, fill='.'):
        s.w, s.h = w, h
        s.g = [[fill]*w for _ in range(h)]
    def set(s, x, y, c):
        if 0 <= x < s.w and 0 <= y < s.h: s.g[y][x] = c
    def rect(s, x0, y0, x1, y1, c):
        for y in range(y0, y1+1):
            for x in range(x0, x1+1): s.set(x, y, c)
    def blob(s, cx, cy, r, c, squash=1.0):
        for y in range(s.h):
            for x in range(s.w):
                if ((x-cx)**2 + ((y-cy)*squash)**2) <= r*r + r*0.6: s.set(x, y, c)
    def path(s, pts, c):
        for (x0,y0),(x1,y1) in zip(pts, pts[1:]):
            n = max(abs(x1-x0), abs(y1-y0))
            px, py = x0, y0
            for i in range(n+1):
                x = round(x0 + (x1-x0)*i/max(n,1)); y = round(y0 + (y1-y0)*i/max(n,1))
                if x != px and y != py: s.set(x, py, c)  # keep 4-connected
                s.set(x, y, c); px, py = x, y
    def rows(s): return ["".join(r) for r in s.g]

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
def ashen(name="The Ashen Host"): return {"id": 1, "name": name, "faction": "ashen", "color": "#b8402c", "is_human": False}
def wren(x, y, army): return {"id": "hero_wren", "name": "Aldous Wren", "class": "knight", "owner": 0, "pos": [x, y], "army": army}
def maelis(x, y, army): return {"id": "hero_maelis", "name": "Maelis Thorne", "class": "ranger", "owner": 0, "pos": [x, y], "army": army}
WREN_ARMY = [["pike_militia", 24], ["longbowman", 14], ["shieldwarden", 6], ["lancer", 3]]
MAELIS_ARMY = [["longbowman", 12], ["pike_militia", 10]]

maps = {}

# ---------------------------------------------------------------- chapter 1
g = Grid(26, 18)
g.rect(0, 0, 25, 0, '^'); g.rect(0, 17, 25, 17, '^')
g.rect(0, 1, 4, 3, 's'); g.set(5, 1, 's'); g.set(0, 4, 's')
g.blob(3, 13, 2.6, 'w'); g.rect(0, 14, 2, 16, 'w')
g.blob(7, 4, 2, 'f'); g.blob(8, 13, 1.6, 'f')
g.rect(5, 6, 6, 6, '^')
# the river: deep water with three crossings
g.rect(12, 1, 13, 16, '#')
for y in (4, 9, 14): g.rect(12, y, 13, y, '~')
g.blob(16, 4, 1.8, 'r'); g.blob(16, 14, 1.8, 'r')
g.rect(18, 1, 25, 16, 'i'); g.blob(19, 9, 2.2, 'r', 1.4)
g.rect(17, 6, 17, 6, '^'); g.rect(17, 12, 17, 12, '^')
g.rect(21, 3, 22, 3, '^'); g.rect(21, 15, 22, 15, '^')
g.rect(0, 0, 25, 0, '^'); g.rect(0, 17, 25, 17, '^')
ch1_roads = roads([(1, 9), (23, 9)]) + roads([(6, 9), (6, 3)])
maps["burning_ford"] = {
    "_doc": "The Last Light chapter 8. Hand-made. The Concord holds the west bank; an Ashen vanguard has thrown up a camp just across the river. Deep water leaves three fords; the bridge on the road is the short way. Easy: one small enemy army and an unwalled camp.",
    "id": "burning_ford", "name": "The Burning Ford", "width": g.w, "height": g.h, "terrain": g.rows(), "roads": ch1_roads,
    "players": [CONCORD, ashen("Ashen Vanguard")],
    "heroes": [wren(2, 9, WREN_ARMY), maelis(3, 10, MAELIS_ARMY),
               {"id": "hero_skarn", "name": "Skarn Ashborn", "class": "warlord", "owner": 1, "pos": [22, 9],
                "army": [["cinderling", 22], ["scorchhound", 6], ["brimstone_hurler", 4]]}],
    "objects": [
        town("town_greyhold", 1, 9, "concord", "Greyhold", 0),
        town("town_ashgate", 23, 9, "ashen", "Ashgate Camp", 1),
        mine("mine_wood", 3, 5, "wood"), mine("mine_ore", 4, 12, "ore"),
        mine("mine_ore_east", 21, 13, "ore"), mine("mine_sulfur", 21, 5, "sulfur"),
        mine("mine_crystal", 9, 2, "crystal", [["thornwolf", 8]]),
        mine("mine_gold", 16, 2, "gold", [["crag_slinger", 18], ["thornwolf", 6]]),
        res("res_gold_1", 5, 8, "gold", 750), res("res_wood_1", 8, 7, "wood", 6), res("res_ore_1", 9, 11, "ore", 5),
        res("res_gems_1", 2, 15, "gems", 3), res("res_gold_2", 15, 11, "gold", 500), res("res_mercury_1", 16, 15, "mercury", 3),
        res("res_gold_3", 24, 2, "gold", 1000),
        army("neutral_ford_north", 11, 4, "Thornwolf pack", [["thornwolf", 10]]),
        army("neutral_ford_south", 11, 14, "Bog lurkers", [["bog_lurker", 5]]),
        army("neutral_outriders", 18, 12, "Ashen outriders", [["scorchhound", 8]]),
        enc("enc_wagon", 7, 10, "overturned_wagon"), enc("enc_courier", 9, 15, "dying_courier"),
        enc("enc_cartographer", 2, 2, "blind_cartographer"), enc("enc_shrine", 20, 16, "ashen_saint_shrine"),
        art("art_pennant", 10, 2, "tattered_pennant"), art("art_falchion", 24, 15, "notched_falchion"),
        # armor drops: one piece near each side's start, one more in the contested middle
        art("art_sallet_west", 7, 5, "dented_sallet"), art("art_sallet_east", 21, 14, "dented_sallet"),
        art("art_boots_mid", 14, 15, "hobnailed_boots"),
    ],
}

# ---------------------------------------------------------------- chapter 2
g = Grid(30, 22)
g.rect(0, 0, 29, 0, '^'); g.rect(0, 21, 29, 21, '^')
g.rect(0, 1, 5, 4, 's'); g.blob(2, 7, 1.8, 's')
g.blob(5, 11, 2.3, 'f'); g.blob(3, 19, 2.3, 'w')
g.rect(8, 5, 9, 7, '^'); g.rect(7, 15, 8, 15, '^')
# the same river, now wider, with a ruined bridge in the north and fords south
g.rect(11, 1, 12, 20, '#')
for y in (4, 12, 17): g.rect(11, y, 12, y, '~')
# eastern wastes: rough foothills, then the burning lands
g.rect(13, 1, 29, 20, 'r')
g.rect(17, 1, 29, 20, 'i')
g.blob(15, 18, 2, 'd'); g.blob(21, 11, 2.4, 'd', 1.3)
# a mountain ridge splits the wastes; two passes
g.rect(19, 1, 19, 20, '^'); g.set(19, 6, 'i'); g.set(19, 15, 'i')
g.rect(24, 9, 27, 9, '^'); g.rect(24, 13, 26, 13, '^')
g.blob(14, 8, 1.4, 'f')
ch2_roads = roads([(2, 16), (10, 16), (10, 12), (18, 12), (18, 15), (24, 15)]) + roads([(2, 16), (2, 10)]) \
    + roads([(18, 6), (26, 6), (26, 5)]) + roads([(18, 12), (18, 6)])
maps["ashes_return"] = {
    "_doc": "The Last Light chapter 9. Hand-made. The Ashen Host returns across the same wastes with two war-leaders, a fortified camp in the south and the burning town of Cinderfall beyond the ridge. Medium: two enemy heroes about as strong as yours, two enemy towns, guarded passes.",
    "id": "ashes_return", "name": "Ashes Return", "width": g.w, "height": g.h, "terrain": g.rows(), "roads": ch2_roads,
    "players": [CONCORD, ashen()],
    "heroes": [wren(3, 16, WREN_ARMY), maelis(2, 15, MAELIS_ARMY),
               {"id": "hero_skarn", "name": "Skarn Ashborn", "class": "warlord", "owner": 1, "pos": [23, 15],
                "army": [["cinderling", 28], ["scorchhound", 8], ["brimstone_hurler", 7], ["flayer", 2]]},
               {"id": "hero_ithra", "name": "Ithra Sootveil", "class": "warlock", "owner": 1, "pos": [26, 7],
                "army": [["cinderling", 18], ["brimstone_hurler", 6], ["ash_witch", 1]]}],
    "objects": [
        town("town_greyhold", 2, 16, "concord", "Greyhold", 0, ["c_hall", "c_tavern", "c_dw1", "c_dw2", "c_palisade"],
             [["pike_militia", 16]]),
        town("town_ashgate", 24, 15, "ashen", "Ashgate Camp", 1, ["a_hall", "a_den", "a_dw1", "a_trench"], [["cinderling", 12]]),
        town("town_cinderfall", 26, 5, "ashen", "Cinderfall", 1, ["a_hall", "a_den", "a_dw1", "a_dw2", "a_dw3", "a_trench", "a_market"],
             [["cinderling", 16], ["brimstone_hurler", 4]]),
        town("town_saltmere", 7, 3, "concord", "Saltmere", -1, ["c_hall", "c_tavern", "c_dw1", "c_dw2"],
             [["pike_militia", 18], ["longbowman", 8]]),
        mine("mine_wood", 4, 13, "wood"), mine("mine_ore", 6, 18, "ore"),
        mine("mine_gems", 3, 2, "gems", [["thornwolf", 10]]),
        mine("mine_crystal", 9, 9, "crystal", [["crag_slinger", 20]]),
        mine("mine_gold", 15, 14, "gold", [["crag_slinger", 22], ["thornwolf", 10]]),
        mine("mine_ore_east", 22, 18, "ore"), mine("mine_sulfur", 27, 11, "sulfur"),
        mine("mine_mercury", 22, 3, "mercury", [["scorchhound", 10]]),
        res("res_gold_1", 6, 15, "gold", 750), res("res_wood_1", 1, 11, "wood", 6), res("res_ore_1", 8, 19, "ore", 5),
        res("res_gold_2", 9, 2, "gold", 1000), res("res_crystal_1", 14, 10, "crystal", 3), res("res_gold_3", 16, 19, "gold", 750),
        res("res_sulfur_1", 21, 9, "sulfur", 3), res("res_gold_4", 28, 19, "gold", 1500),
        army("neutral_bridge", 10, 4, "Bridge wardens", [["crag_slinger", 24], ["thornwolf", 8]]),
        army("neutral_ford", 10, 12, "Thornwolf pack", [["thornwolf", 16]]),
        army("neutral_south_ford", 10, 17, "Bog lurkers", [["bog_lurker", 9]]),
        army("neutral_pass_north", 19, 6, "Ashen pickets", [["cinderling", 30], ["brimstone_hurler", 8]]),
        army("neutral_pass_south", 19, 15, "Ashen pickets", [["cinderling", 26], ["scorchhound", 8]]),
        enc("enc_refugees", 7, 12, "dispossessed_column"), enc("enc_chapel", 4, 19, "drowned_chapel"),
        enc("enc_sellswords", 14, 6, "free_company_camp"), enc("enc_barrows", 16, 17, "barrow_field"),
        enc("enc_pit", 23, 11, "ash_pit_champion"),
        art("art_compass", 1, 6, "wayfarers_compass"), art("art_hauberk", 13, 19, "riveted_hauberk"),
        art("art_dice", 28, 2, "bone_dice"),
        # armor drops: one piece per side, one behind the southern fords
        art("art_gambeson_west", 8, 13, "padded_gambeson"), art("art_gambeson_east", 21, 10, "padded_gambeson"),
        art("art_pavise_mid", 13, 16, "vigil_pavise"),
    ],
}

# ---------------------------------------------------------------- chapter 3
g = Grid(34, 24, 'i')
g.rect(0, 0, 33, 0, '^'); g.rect(0, 23, 33, 23, '^')
# the Concord foothold in the south-west: rough highland and the last green
g.rect(0, 12, 11, 22, 'r'); g.blob(3, 18, 3.2, '.'); g.blob(8, 21, 1.6, 'f')
g.blob(2, 13, 1.5, 'f')
# north-west: ash-choked desert, south-east: scorched rock
g.blob(5, 5, 3.6, 'd', 1.2); g.blob(26, 19, 3, 'r')
# the great ridge around Cindermaw, broken by two passes
g.rect(17, 1, 17, 9, '^'); g.rect(17, 9, 33, 9, '^')
g.set(17, 4, 'i'); g.set(21, 9, 'i')
# a lava-crossed river (deep water standing in for fire channels) between foothold and wastes
g.path([(13, 1), (13, 10), (10, 10)], '#'); g.set(13, 6, '~')
g.path([(14, 15), (22, 15)], '#'); g.set(18, 15, '~')
g.rect(29, 12, 31, 12, '^')
g.blob(9, 6, 1.2, '^'); g.blob(22, 4, 1.0, '^'); g.blob(5, 9, 0.8, '^')
ch3_roads = roads([(3, 18), (12, 18), (12, 13), (18, 13), (18, 16), (25, 16)]) + roads([(18, 13), (21, 13), (21, 7), (31, 7), (31, 4)]) \
    + roads([(12, 13), (12, 6), (16, 6), (16, 4), (17, 4)])
maps["into_the_embers"] = {
    "_doc": "The Last Light chapter 10. Hand-made. The Concord carries the war into the Cinder Wastes from a single foothold. Cindermaw, the Ashen capital, sits walled behind a ridge in the north-east with two passes; Pyrehold guards the southern approach. Hard: three enemy war-leaders, a walled and garrisoned capital, a second fortified town and strong guards on both passes.",
    "id": "into_the_embers", "name": "Into the Embers", "width": g.w, "height": g.h, "terrain": g.rows(), "roads": ch3_roads,
    "players": [CONCORD, ashen()],
    "heroes": [wren(4, 18, WREN_ARMY), maelis(3, 19, MAELIS_ARMY),
               {"id": "hero_skarn", "name": "Skarn Ashborn", "class": "warlord", "owner": 1, "pos": [24, 16],
                "army": [["cinderling", 26], ["scorchhound", 8], ["brimstone_hurler", 6], ["flayer", 3]]},
               {"id": "hero_ithra", "name": "Ithra Sootveil", "class": "warlock", "owner": 1, "pos": [30, 5],
                "army": [["cinderling", 14], ["brimstone_hurler", 5], ["ash_witch", 1]]},
               {"id": "hero_morvath", "name": "Morvath the Kindler", "class": "tormentor", "owner": 1, "pos": [8, 4],
                "army": [["cinderling", 20], ["scorchhound", 8]]}],
    "objects": [
        town("town_lastlight", 3, 18, "concord", "Last Light", 0, ["c_hall", "c_tavern", "c_market", "c_dw1", "c_dw2", "c_dw3", "c_dw4", "c_palisade"],
             [["pike_militia", 20], ["longbowman", 8]]),
        town("town_cindermaw", 31, 4, "ashen", "Cindermaw", 1,
             ["a_hall", "a_den", "a_dw1", "a_dw2", "a_trench", "a_wall"],
             [["cinderling", 14], ["flayer", 2]]),
        town("town_pyrehold", 25, 16, "ashen", "Pyrehold", 1, ["a_hall", "a_den", "a_dw1", "a_dw2", "a_trench"],
             [["cinderling", 20], ["brimstone_hurler", 6]]),
        town("town_brandwatch", 6, 13, "concord", "Brandwatch", -1, ["c_hall", "c_dw1", "c_dw2", "c_palisade"],
             [["pike_militia", 24], ["longbowman", 10], ["shieldwarden", 4]]),
        mine("mine_wood", 7, 16, "wood"), mine("mine_ore", 1, 15, "ore"),
        mine("mine_crystal", 9, 21, "crystal", [["crag_slinger", 20]]),
        mine("mine_gems", 11, 12, "gems", [["ashscale_basilisk", 8]]),
        mine("mine_gold", 15, 20, "gold", [["cinder_wraith", 6], ["scorchhound", 12]]),
        mine("mine_sulfur", 3, 8, "sulfur"), mine("mine_ore_east", 29, 19, "ore"),
        mine("mine_mercury", 20, 3, "mercury", [["flayer", 6]]), mine("mine_gold_east", 27, 2, "gold"),
        res("res_gold_1", 6, 20, "gold", 1000), res("res_wood_1", 1, 21, "wood", 6), res("res_ore_1", 9, 14, "ore", 6),
        res("res_gems_1", 14, 17, "gems", 3), res("res_gold_2", 2, 3, "gold", 1500), res("res_sulfur_1", 16, 10, "sulfur", 4),
        res("res_mercury_1", 22, 20, "mercury", 4), res("res_gold_3", 32, 21, "gold", 2000), res("res_gold_4", 26, 11, "gold", 1500),
        army("neutral_ford", 12, 15, "Ashen pickets", [["cinderling", 24], ["brimstone_hurler", 6]]),
        army("neutral_channel", 13, 6, "Channel wardens", [["ashscale_basilisk", 10], ["crag_slinger", 20]]),
        army("neutral_pass_west", 17, 4, "Gate of Cinders", [["cinder_wraith", 7], ["ashscale_basilisk", 10], ["crag_slinger", 24]]),
        army("neutral_pass_south", 21, 9, "Gate of Embers", [["cinder_wraith", 7], ["ashscale_basilisk", 10], ["thornwolf", 14]]),
        army("neutral_wraiths", 30, 15, "Cinder wraiths", [["cinder_wraith", 10]]),
        army("neutral_bridge", 18, 15, "Bridge of Brands", [["scorchhound", 16], ["brimstone_hurler", 8]]),
        enc("enc_courier", 9, 18, "dying_courier"), enc("enc_rift", 23, 21, "ember_rift"), enc("enc_hall", 2, 11, "hall_of_echoes"),
        enc("enc_pit", 27, 14, "ash_pit_champion"), enc("enc_toll", 15, 12, "brigand_toll"),
        art("art_shroud", 31, 20, "shroud_of_ash"), art("art_hourglass", 1, 1, "hourglass_of_marrow"),
        art("art_cloak", 10, 19, "pilgrims_cloak"),
        # armor drops: one piece per side and two in the wastes (with chapter 2's pavise
        # they complete the Long Road Harness)
        art("art_buckler_west", 8, 13, "splintered_buckler"), art("art_buckler_east", 24, 6, "splintered_buckler"),
        art("art_crowcrest_mid", 15, 14, "crowcrest_helm"), art("art_greaves_mid", 14, 8, "outriders_greaves"),
    ],
}

# The layouts above are drawn on small grids; the maps are played larger
# (playtests, Nov 7: the campaign maps felt small). See maplib.enlarge.
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from maplib import enlarge, check, add_story_landmarks
import rebuild
enlarge(maps, {"burning_ford": 2.5, "ashes_return": 2.65, "into_the_embers": 2.7})
# Map overhaul (Nov 9): the finale keeps its layout but loses its flat
# single-biome blocks (texture) and gets the terrain painter's dressing below.
# burning_ford and ashes_return are no longer campaign chapters (ll_ford and
# ll_ashes, tools/maps/build_last_light_maps.py) and stay as they were.
rebuild.texture(maps["into_the_embers"], 10)
add_story_landmarks(maps)
for d in maps.values():
    check(d)

for mid, d in maps.items():
    with open(f"{OUT}/{mid}.json", "w") as f:
        f.write("{\n")
        keys = list(d.keys())
        for i, k in enumerate(keys):
            v = d[k]
            sep = "," if i < len(keys) - 1 else ""
            if k in ("terrain",):
                f.write(f'  "{k}": [\n' + ",\n".join(f'    "{r}"' for r in v) + f"\n  ]{sep}\n")
            elif k in ("heroes", "objects", "players", "roads"):
                f.write(f'  "{k}": [\n' + ",\n".join("    " + json.dumps(x) for x in v) + f"\n  ]{sep}\n")
            else:
                f.write(f'  "{k}": {json.dumps(v)}{sep}\n')
        f.write("}\n")
    print(mid); print("\n".join(d["terrain"]))
rebuild.dress_hand_made(OUT, "into_the_embers", 10)
