"""Builds the maps of the Ashen campaign "The Unsealing".

Hand-made: pit_below (chapter 1), breaking_the_lockstone (chapter 5) and
red_sky_throne (chapter 10, one against three). The other chapters (map
overhaul phase 3) start from frozen random-map layouts (maplib.freeze) and are
tuned below: factions and their ground, story towns and heroes, landmarks,
villages; their scenario rules (mission, 2v2, townless, betrayal) live in the
chapter's "scenario" in data/campaigns.json.

Edit the layouts here, then regenerate:  python3 tools/maps/build_unsealing_maps.py data/maps
(needs Godot: $GODOT or godot on PATH) and run ./run_tests.sh faction_campaigns.
The frozen sources are fixed by MapGenerator.VERSION; the written files in
data/maps are the maps the game plays.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
maps = {}

HOST = player(0, "Skarn's Brood", "ashen", human=True)

# ------------------------------------------------- chapter 1: the pit below
# Inside the Wound. Skarn's pit in the west, the Gnawing Brood's in the east (turned
# a quarter when built: south and north),
# rock walls between them with two passages. Tier 2 for both.
g = Grid(24, 16, 'i')
g.rect(0, 0, 23, 0, '^'); g.rect(0, 15, 23, 15, '^')
g.blob(3, 8, 2.5, 'r'); g.blob(20, 8, 2.5, 'r')
g.rect(11, 1, 12, 5, '^'); g.rect(11, 7, 12, 10, '^'); g.rect(11, 12, 12, 14, '^')   # passages at y 6 and 11
g.blob(7, 3, 1.2, '^'); g.blob(16, 12, 1.2, '^')
maps["pit_below"] = {
    "_doc": "The Unsealing chapter 1. Hand-made (tools/maps/build_unsealing_maps.py). Inside the Wound: Skarn's pit in the west, the Gnawing Brood's in the east, a rock wall with two passages between them. Both sides are Ashen and capped at tier 2.",
    "id": "pit_below", "name": "The Pit Below", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(2, 8), (2, 6), (21, 6), (21, 8)]),
    "players": [HOST, player(1, "The Gnawing Brood", "ashen", color="#8a3a5a")],
    "heroes": [
        hero("hero_skarn", "Skarn Ashborn", "warlord", 0, 3, 8, [["cinderling", 30], ["scorchhound", 8]]),
        hero("hero_vrask", "Vrask Gutmaw", "warlord", 1, 20, 8, [["cinderling", 26], ["scorchhound", 7]]),
    ],
    "objects": [
        town("town_skarns_pit", 2, 8, "ashen", "Skarn's Pit", 0, ["a_hall", "a_den", "a_trench", "a_dw1", "a_dw2"], [["cinderling", 14]]),
        town("town_gnawing_pit", 21, 8, "ashen", "The Gnawing Pit", 1, ["a_hall", "a_trench", "a_dw1", "a_dw2"], [["cinderling", 14], ["scorchhound", 3]]),
        mine("mine_ore", 5, 3, "ore"), mine("mine_sulfur", 5, 12, "sulfur"),
        mine("mine_wood", 18, 3, "wood", [["tomb_scarabs", 6]]),
        res("res_gold_1", 7, 6, "gold", 500), res("res_gold_2", 9, 11, "gold", 750), res("res_gold_3", 15, 9, "gold", 1000),
        res("res_ore_1", 4, 13, "ore", 5), res("res_sulfur_1", 9, 2, "sulfur", 3), res("res_wood_1", 14, 3, "wood", 5),
        res("res_gems_1", 20, 13, "gems", 2),
        army("neutral_north_pass", 12, 6, "Pit scavengers", [["carrion_flock", 10]]),
        army("neutral_south_pass", 12, 11, "Starving cinderlings", [["cinderling", 16]]),
        enc("enc_rift", 8, 9, "ember_rift"), enc("enc_champion", 16, 5, "ash_pit_champion"),
        art("art_falchion", 2, 2, "notched_falchion"), art("art_shroud", 21, 13, "shroud_of_ash"),
    ],
}

# --------------------------------------------- chapter 5: breaking the lockstone
# The Host comes up out of the Wound in the south. The Lockstone stands in a ring
# of rock in the middle; lantern-priests hold the Lantern Watch beside it and
# Brightwater further north. Tier 5 for both sides.
g = Grid(28, 22, '.')
g.rect(0, 0, 27, 0, '^'); g.rect(0, 21, 27, 21, '^')
g.rect(0, 15, 27, 20, 'i')                # the mouth of the Wound
g.rect(1, 14, 26, 14, 'r')
g.blob(13, 9, 3.0, 'r')                    # the stone's broken ground
g.rect(10, 6, 16, 6, '^'); g.rect(10, 12, 12, 12, '^'); g.rect(14, 12, 16, 12, '^')   # the ring, open south and at the sides
g.rect(10, 7, 10, 8, '^'); g.rect(16, 7, 16, 8, '^')
g.blob(4, 5, 2.0, 'f'); g.blob(22, 4, 2.0, 'f'); g.blob(23, 11, 1.5, 'f')
g.rect(5, 12, 7, 12, '^'); g.rect(19, 12, 21, 12, '^')
maps["breaking_the_lockstone"] = {
    "_doc": "The Unsealing chapter 5. Hand-made (tools/maps/build_unsealing_maps.py). The Host comes up out of the Wound in the south; the Lockstone stands in a ring of rock in the middle, the lantern-priests' Lantern Watch beside it and Brightwater to the north. Both sides are capped at tier 5.",
    "id": "breaking_the_lockstone", "name": "Breaking the Lockstone", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(13, 18), (13, 13)]) + roads([(13, 11), (13, 10)]) + roads([(17, 9), (24, 9), (24, 3), (13, 3)]),
    "players": [HOST, player(1, "The Lantern Temples", "concord")],
    "heroes": [
        hero("hero_skarn", "Skarn Ashborn", "warlord", 0, 12, 18,
             [["cinderling", 60], ["scorchhound", 22], ["brimstone_hurler", 12], ["flayer", 6], ["ash_witch", 3]]),
        hero("hero_ithra", "Ithra Sootveil", "warlock", 0, 14, 18, [["cinderling", 34], ["scorchhound", 12], ["brimstone_hurler", 8]]),
        hero("hero_morvath", "Morvath the Kindler", "tormentor", 0, 13, 19, [["cinderling", 30], ["scorchhound", 10], ["ash_witch", 2]]),
        hero("hero_maud", "Abbess Maud Lorne", "oracle", 1, 14, 9,
             [["pike_militia", 40], ["longbowman", 20], ["shieldwarden", 10], ["lancer", 4], ["lightbearer", 6]]),
        hero("hero_tamsin", "Brother Tamsin Hale", "knight", 1, 13, 4, [["pike_militia", 30], ["longbowman", 14], ["lancer", 4]]),
    ],
    "objects": [
        town("town_wound_mouth", 13, 18, "ashen", "The Wound-Mouth", 0,
             ["a_hall", "a_den", "a_market", "a_trench", "a_wall", "a_dw1", "a_dw2", "a_dw3", "a_dw4"], [["cinderling", 20]]),
        town("town_lantern_watch", 18, 9, "concord", "The Lantern Watch", 1,
             ["c_hall", "c_tavern", "c_market", "c_palisade", "c_dw1", "c_dw2", "c_dw3", "c_dw5"],
             [["pike_militia", 24], ["longbowman", 12], ["lightbearer", 3]]),
        town("town_brightwater", 13, 2, "concord", "Brightwater", 1, ["c_hall", "c_palisade", "c_keep", "c_dw1", "c_dw2", "c_dw3", "c_dw4"],
             [["pike_militia", 30], ["longbowman", 12], ["shieldwarden", 6]]),
        enc("enc_lockstone", 13, 8, "ember_rift"),
        mine("mine_sulfur", 3, 18, "sulfur"), mine("mine_ore", 24, 18, "ore"),
        mine("mine_wood", 4, 8, "wood", [["thornwolf", 14]]),
        mine("mine_crystal", 22, 6, "crystal", [["deserter_crossbows", 12]]),
        mine("mine_gold", 2, 2, "gold", [["hill_troll", 4]]), mine("mine_gems", 25, 13, "gems"),
        res("res_gold_1", 8, 16, "gold", 1000), res("res_gold_2", 19, 16, "gold", 1000), res("res_gold_3", 7, 9, "gold", 1500),
        res("res_ore_1", 22, 19, "ore", 6), res("res_sulfur_1", 5, 19, "sulfur", 4), res("res_wood_1", 20, 2, "wood", 6),
        res("res_crystal_1", 9, 4, "crystal", 3), res("res_gems_1", 26, 7, "gems", 3),
        army("neutral_ring", 13, 12, "Lockstone pilgrims", [["lost_pilgrims", 40]]),
        army("neutral_west", 6, 13, "Deserters at the rim", [["deserter_crossbows", 14], ["road_cutthroat", 12]]),
        army("neutral_east", 20, 13, "Crag slingers", [["crag_slinger", 18]]),
        enc("enc_shrine", 3, 11, "ashen_saint_shrine"), enc("enc_column", 23, 15, "dispossessed_column"),
        art("art_glaive", 1, 16, "bleeding_glaive"), art("art_banner", 25, 2, "flayed_banner"), art("art_cuirass", 9, 7, "emberforged_cuirass"),
    ],
}

# ---------------------------------------------- chapter 10: the red sky throne
# One against three. Drawn with the Host in the west; the built map is turned a
# quarter (below), so the Host comes up from the south. Highmere, the Concord's
# eastern fortress, stands in the middle of the far side; a Thornwood war-grove
# holds the forest on one flank and a Forge hold the mountains on the other.
# Two roads leave the Ash Camp, over the guarded fords on either side, and
# gaps in Highmere's ridges open it to the grove and the hold as well as the
# front. The three enemies are allies (team 1).
g = Grid(36, 28, '.')
g.rect(0, 0, 35, 0, '^'); g.rect(0, 27, 35, 27, '^')
g.rect(0, 1, 6, 26, 'i')                  # the ash road out of the Wound
g.blob(27, 5, 5.0, 'f')                   # the war-grove
g.blob(27, 22, 5.0, 'r')                  # the Forge hold's slopes
g.rect(22, 12, 35, 12, '^'); g.rect(22, 16, 35, 16, '^')    # Highmere's ridges, open to the west
g.rect(35, 13, 35, 15, '.')
g.rect(24, 12, 25, 12, '.'); g.rect(24, 16, 25, 16, '.')    # flank gaps into Highmere's approach
g.rect(13, 1, 13, 5, '~'); g.rect(13, 9, 13, 18, '~'); g.rect(13, 22, 13, 26, '~')   # the Pale River, three fords
g.blob(30, 24, 1.5, '^'); g.blob(32, 20, 1.0, '^'); g.blob(31, 2, 1.0, '^')
g.rect(0, 0, 35, 0, '^'); g.rect(0, 27, 35, 27, '^')   # the blobs reach the edge
maps["red_sky_throne"] = {
    "_doc": "The Unsealing chapter 10, one against three. Hand-made (tools/maps/build_unsealing_maps.py). The Host comes from the south across the Pale River by two roads and three fords; Highmere, the Concord's eastern fortress, holds the middle of the north side behind ridges with a front and two flank gaps, a Thornwood war-grove the north-west and a Forge hold the north-east. The three are allied computer players (team 1), at the easy difficulty.",
    "id": "red_sky_throne", "name": "The Red Sky Throne", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(3, 14), (11, 14), (11, 7), (16, 7)]) + roads([(11, 14), (11, 20), (16, 20)]) + roads([(16, 14), (33, 14)])
             + roads([(16, 14), (16, 6), (27, 6)]) + roads([(16, 14), (16, 21), (27, 21)]),
    "players": [HOST, player(1, "Highmere", "concord", difficulty="easy", team=1), player(2, "The Thornwood Covenant", "thornwood", difficulty="easy", team=1),
                player(3, "The Sunken Forge", "forge", difficulty="easy", team=1)],
    "heroes": [
        hero("hero_skarn", "Skarn Ashborn", "warlord", 0, 4, 14,
             [["cinderling", 100], ["scorchhound", 40], ["brimstone_hurler", 26], ["flayer", 16], ["ash_witch", 8], ["gorgewing", 5],
              ["pyre_titan", 2], ["cinder_maw", 1]]),
        hero("hero_ithra", "Ithra Sootveil", "warlock", 0, 4, 13,
             [["cinderling", 60], ["scorchhound", 24], ["brimstone_hurler", 16], ["ash_witch", 6], ["gorgewing", 3]]),
        hero("hero_morvath", "Morvath the Kindler", "tormentor", 0, 4, 15,
             [["cinderling", 60], ["scorchhound", 20], ["flayer", 10], ["ash_witch", 4], ["pyre_titan", 1]]),
        hero("hero_wren", "Aldous Wren", "knight", 1, 31, 14,
             [["pike_militia", 70], ["longbowman", 34], ["shieldwarden", 16], ["lancer", 10], ["lightbearer", 6], ["sunhawk_rider", 3],
              ["bastion_colossus", 1]]),
        hero("hero_cerrid", "Cerrid Ashbark", "grovewarden", 2, 26, 6,
             [["thorn_skulker", 60], ["barkhide_warden", 24], ["briar_huntress", 16], ["rootbinder", 8], ["gloomwing_strix", 5],
              ["spore_lobber", 3], ["rootbound_ancient", 1]]),
        hero("hero_bruna", "Bruna Kell", "ironmarshal", 3, 26, 21,
             [["forge_thrall", 50], ["rivet_crossbowman", 24], ["anvil_guard", 14], ["slag_golem", 6], ["cinder_engineer", 4],
              ["ironhoof_charger", 3], ["thunder_bombard", 1]]),
    ],
    "objects": [
        town("town_ash_camp", 3, 14, "ashen", "The Ash Camp", 0,
             ["a_hall", "a_den", "a_market", "a_trench", "a_wall", "a_tithe", "a_dw1", "a_dw2", "a_dw3", "a_dw4", "a_dw5", "a_dw6"],
             [["cinderling", 40], ["scorchhound", 12]]),
        town("town_highmere", 33, 14, "concord", "Highmere", 1,
             ["c_hall", "c_court", "c_tavern", "c_market", "c_palisade", "c_keep", "c_dw1", "c_dw2", "c_dw3", "c_dw4", "c_dw5", "c_dw6"],
             [["pike_militia", 40], ["longbowman", 20], ["shieldwarden", 10], ["lancer", 4]]),
        town("town_war_grove", 28, 6, "thornwood", "The War-Grove", 2,
             ["t_hall", "t_tavern", "t_market", "t_fort1", "t_fort2", "t_dw1", "t_dw2", "t_dw3", "t_dw4", "t_dw5"],
             [["thorn_skulker", 30], ["barkhide_warden", 12], ["briar_huntress", 6]]),
        town("town_stonevow", 28, 21, "forge", "Stonevow Hold", 3,
             ["f_hall", "f_tavern", "f_market", "f_fort1", "f_fort2", "f_dw1", "f_dw2", "f_dw3", "f_dw4", "f_dw5"],
             [["forge_thrall", 30], ["rivet_crossbowman", 12], ["anvil_guard", 6]]),
        town("town_ferrybridge", 18, 14, "concord", "Ferrybridge", -1, ["c_hall", "c_palisade", "c_dw1", "c_dw2"],
             [["pike_militia", 40], ["longbowman", 16]]),
        mine("mine_sulfur", 2, 4, "sulfur"), mine("mine_ore", 2, 24, "ore"),
        mine("mine_wood", 9, 8, "wood"), mine("mine_mercury", 9, 20, "mercury"),
        mine("mine_gold", 19, 3, "gold", [["hill_giant", 2]]), mine("mine_crystal", 19, 25, "crystal", [["ogre_mauler", 8]]),
        mine("mine_gems", 23, 9, "gems", [["venom_wyvern", 4]]), mine("mine_gold_south", 23, 19, "gold", [["ruin_sentinel", 8]]),
        res("res_gold_1", 8, 11, "gold", 1500), res("res_gold_2", 10, 17, "gold", 1500), res("res_gold_3", 20, 10, "gold", 2000),
        res("res_gold_4", 20, 18, "gold", 2000), res("res_sulfur_1", 5, 2, "sulfur", 5), res("res_ore_1", 5, 25, "ore", 8),
        res("res_wood_1", 11, 3, "wood", 8), res("res_mercury_1", 11, 24, "mercury", 4), res("res_crystal_1", 26, 13, "crystal", 4),
        res("res_gems_1", 26, 15, "gems", 4),
        army("neutral_ford_north", 13, 7, "Refugees at the ford", [["lost_pilgrims", 60]]),
        army("neutral_ford_mid", 13, 20, "Deserters at the ford", [["deserter_crossbows", 20], ["road_cutthroat", 20]]),
        army("neutral_ford_road", 14, 14, "Ferrybridge pickets", [["steppe_centaur", 10]]),
        enc("enc_shrine", 7, 6, "ashen_saint_shrine"), enc("enc_hall", 21, 14, "hall_of_echoes"),
        enc("enc_company", 17, 9, "free_company_camp"), enc("enc_column", 17, 23, "dispossessed_column"),
        art("art_oriflamme", 1, 1, "warhost_oriflamme"), art("art_tower", 34, 13, "gatewardens_tower"),
        art("art_greathelm", 20, 6, "greathelm_of_dread"),
    ],
}


# The layouts above are drawn on small grids; the maps are played larger
# (playtests, Nov 7: the campaign maps felt small, twice). See maplib.enlarge.
# Map overhaul (Nov 9): the finale is rebuilt bigger, like the other late chapters.
enlarge(maps, {"pit_below": 2.5, "breaking_the_lockstone": 2.65, "red_sky_throne": 3.2})

# Map overhaul (Nov 9): the kept layouts get a new look (maplib.dress_handmade:
# wavy biome borders, ground patches, ragged rock, painted decoration), and the
# pit and the finale, which played straight west to east, are turned so the
# Host climbs north.
rotate(maps["pit_below"], 3)
rotate(maps["red_sky_throne"], 3)
maps["pit_below"]["_doc"] = maps["pit_below"]["_doc"].replace("Skarn's pit in the west, the Gnawing Brood's in the east", "Skarn's pit in the south, the Gnawing Brood's in the north")


build(maps, OUT, {"pit_below": 41, "breaking_the_lockstone": 45, "red_sky_throne": 50})


# =============================================================================
# Frozen-layout chapters (map overhaul phase 3). Each starts from a random-map
# layout picked from contact sheets of ~20 seeds; slot 0 is the player.

def chapter(source, mid, name, doc):
    return frozen_chapter(source, mid, name, doc)


def finish(d, seed):
    return finish_chapter(d, seed, OUT, ("Skarn Ashborn", "warlord", [["cinderling", 30], ["scorchhound", 10]]))


# ------------------------------------------------- chapter 2: the brood war (L)
# Same size as before (87x87), new layout: branching valleys, Skarn's pit at the
# top, Hrakka Ninefang's brood at the bottom, the two meet only in the heart.
d = chapter("gen:random_xl_2p_normal_normal_tree:3", "un_brood_war", "The Brood War",
            "The Unsealing chapter 2 (L). Frozen from gen:random_xl_2p_normal_normal_tree:3 and tuned in tools/maps/build_unsealing_maps.py: Skarn's pit in the north, Hrakka Ninefang's brood in the south, branching valleys with deep dead ends between them.")
labels = zone_map(d)
faction_zone(d, "start_0", "ashen", labels)
set_players(d, [("Skarn's Brood", "ashen", True), ("Hrakka's Brood", "ashen", False)])
set_hero(d, "hero_p1", "Hrakka Ninefang", "warlord", faction_army("ashen", 3, 2.0))
obj(d, "town_start_0")["name"] = "The Gnawing Pit"
obj(d, "town_start_1")["name"] = "Ninefang Hollow"
finish(d, 2741)


# ---------------------------------------------- chapter 3: the wardens' keep (S)
# Underground: rough rock and cinder seams. The Host comes down from the north;
# the Wardens' Keep (Forge) holds the south end. Ithra must reach the crack under
# the keep's wall before the wardens brick it up, then the keep must fall.
d = chapter("gen:random_xl_2p_normal_normal_lanes:4", "un_wardens_keep", "The Wardens' Keep",
            "The Unsealing chapter 3 (S, mission). Frozen from gen:random_xl_2p_normal_normal_lanes:4 and tuned in tools/maps/build_unsealing_maps.py: underground rock and cinder seams, the Host in the north, the Forge's Wardens' Keep in the south with the crack under its wall (scenario reach target) and the Lockstone's underside beside it.")
labels = zone_map(d)
retheme(d, {".": "r", "f": "i", "s": "r", "d": "r", "w": "i"})
retheme_zones(d, ["start_0"], {"r": "i"}, labels)
retheme_zones(d, ["start_1"], {"i": "r"}, labels)
set_players(d, [("Skarn's Brood", "ashen", True), ("The Wardens", "forge", False)])
set_hero(d, "hero_p1", "Bruna Kell", "ironmarshal", faction_army("forge", 3, 2.5))
keep = obj(d, "town_start_1")
keep.update({"id": "town_wardens_keep", "name": "The Wardens' Keep"})
obj(d, "town_heart").update({"town_type": "forge", "name": "Deepgate"})
obj(d, "town_start_0")["name"] = "The Undercamp"
kx, ky = keep["pos"]
CRACK = free_tile_near(d, kx + 3, ky + 3, radius=4)
landmark_near(d, kx + 6, ky + 5, "landmark_shattered_citadel")
deco_pattern(d, kx + 4, ky + 2, "stones")
print("un_wardens_keep crack", CRACK)
finish(d, 3389)


# ---------------------------------------------- chapter 4: under the barrows (A)
# 2v2 on a four-realm ring: Skarn (south-east) and Hrakka's brood (north-east)
# against the Regent (south-west) and Morrow's Barrow-Lords (north-west). The
# Barrow Below is the neutral town in the heart.
d = chapter("gen:random_l_4p_normal_normal_ring:1", "un_under_barrows", "Under the Barrows",
            "The Unsealing chapter 4 (A, 2v2). Frozen from gen:random_l_4p_normal_normal_ring:1 and tuned in tools/maps/build_unsealing_maps.py: Skarn's Brood (south-east) and Hrakka's Brood (north-east, allied) against the Regent (south-west) and Morrow's Barrow-Lords (north-west); the Barrow Below in the heart.")
labels = zone_map(d)
faction_zone(d, "start_0", "ashen", labels)
faction_zone(d, "start_1", "hollow", labels)
faction_zone(d, "start_2", "hollow", labels)
set_players(d, [("Skarn's Brood", "ashen", True, 1), ("The Regent", "hollow", False, 2),
                ("Morrow's Barrow-Lords", "hollow", False, 2), ("Hrakka's Brood", "ashen", False, 1)])
set_hero(d, "hero_p1", "The Regent's Marshal", "necromancer", faction_army("hollow", 4, 2.5))
set_hero(d, "hero_p2", "Morrow", "gravewarden", faction_army("hollow", 4, 2.0))
set_hero(d, "hero_p3", "Hrakka Ninefang", "warlord", faction_army("ashen", 4, 2.5))
heart = obj(d, "town_heart")
heart.update({"id": "town_barrow_below", "name": "The Barrow Below", "town_type": "hollow"})
deco_pattern(d, heart["pos"][0], heart["pos"][1], "graves")
for z in ("approach_1", "approach_2"):
    cx, cy = zone_info(d, labels)[z]["center"]
    deco_pattern(d, cx, cy, "graves")
finish(d, 4463)


# ------------------------------------------- chapter 6: kindling the elderwold (T)
# Out under the sky with no town. The Host comes out of the stump fields in the
# west; Elderhollow, a Covenant grove-town, stands a day and more away, and the
# brood camps around the Host sell Ashen folk. The Covenant (Cerrid) holds the
# south and the east in the last groves.
d = chapter("gen:random_xl_3p_normal_normal_hub:1", "un_kindling", "Kindling the Elderwold",
            "The Unsealing chapter 6 (T, townless start). Frozen from gen:random_xl_3p_normal_normal_hub:1 and tuned in tools/maps/build_unsealing_maps.py: the Host starts without a town in the western stump fields with brood camps (villages) around it; Elderhollow, a neutral grove-town, is the first prize; the Thornwood Covenant holds the forested south and east.")
labels = zone_map(d)
info = zone_info(d, labels)
retheme(d, {".": "f"}, lambda x, y: labels.get((x, y)) != "start_0")
retheme_zones(d, ["start_0"], {".": "r", "f": "r"}, labels)
faction_zone(d, "start_1", "thornwood", labels)
for o in d["objects"] + d["heroes"]:
    if o.get("owner") == 2:
        o["owner"] = 1
drop(d, "hero_p2")
set_players(d, [("Skarn's Brood", "ashen", True), ("The Thornwood Covenant", "thornwood", False)])
set_hero(d, "hero_p1", "Cerrid Ashbark", "grovewarden", faction_army("thornwood", 5, 3.0))
obj(d, "town_start_1")["name"] = "Mothergrove"
obj(d, "town_start_2").update({"name": "Briarwatch", "town_type": "thornwood"})
elder = obj(d, "town_start_0")
elder.update({"id": "town_elderhollow", "name": "Elderhollow", "town_type": "thornwood"})
for x, y in [(10, 12), (24, 14), (8, 26)]:
    deco_pattern(d, x, y, "grove")
# Tuned with tools/scenario_probe.gd townless_chapter campaign:unsealing:5 town_elderhollow:
# Skarn alone wins 32%, the best army the gold buys 100% (28% losses).
UN_KINDLING_GARRISON = [["thorn_skulker", 42], ["barkhide_warden", 36], ["briar_huntress", 18], ["rootbinder", 8]]
make_townless(d, 0, "town_elderhollow", "ashen", 7500 + 3000, UN_KINDLING_GARRISON, villages=4, seed=6,
              guard=[[["thornwolf", 8]], [["carrion_flock", 10]], [["thornwolf", 10]], [["road_cutthroat", 10]]])
finish(d, 5519)


# --------------------------------------------------------- chapter 7: the ford (C)
# The Ford from the Ashen side: the Host comes from the north; the Pale River
# runs across the heart; the Concord (Wren) holds the south-east and the
# south-west beyond it.
d = chapter("gen:random_xl_3p_normal_normal_hub:2", "un_ford", "The Ford",
            "The Unsealing chapter 7 (C). Frozen from gen:random_xl_3p_normal_normal_hub:2 and tuned in tools/maps/build_unsealing_maps.py: the Host in the north, the river across the heart, the Concord holding two towns south of it.")
swap_slots(d, 0, 1)
for o in d["objects"] + d["heroes"]:
    if o.get("owner") == 2:
        o["owner"] = 1
drop(d, "hero_p2")
set_players(d, [("Skarn's Brood", "ashen", True), ("The Concord", "concord", False)])
set_hero(d, "hero_p1", "Aldous Wren", "knight", faction_army("concord", 6, 3.5))
obj(d, "town_start_1")["name"] = "The Ash Road Camp"
obj(d, "town_start_0")["name"] = "Ferrystead"
obj(d, "town_start_2")["name"] = "Wrenhold"
obj(d, "town_heart").update({"name": "Fordmere", "town_type": "concord"})
finish(d, 6247)


# ---------------------------------------------------- chapter 8: ash and snow (B)
# The Host (west) and Hrakka's brood (south-east) march together into the snow
# against the Frostmarch (north). Snowfields with ash plains between them: the
# Host's hostile ground. Hrakka turns on day 18, or as soon as a town of the
# Host falls (scenario betrayal in data/campaigns.json).
d = chapter("gen:random_xl_3p_normal_normal_ring:2", "un_ash_snow", "Ash on the Snow",
            "The Unsealing chapter 8 (B, betrayal). Frozen from gen:random_xl_3p_normal_normal_ring:2 and tuned in tools/maps/build_unsealing_maps.py: the Host in the west and its ally Hrakka's Brood in the south-east against the Frostmarch in the north, on snowfields broken by ash plains; Hrakka turns on day 18 or when a town of the Host falls.")
labels = zone_map(d)
home = {"start_0", "start_2"}
retheme(d, {".": "s", "r": "d", "w": "s"}, lambda x, y: labels.get((x, y)) not in home)
retheme_zones(d, ["start_1"], {"i": "s"}, labels)
retheme_zones(d, list(home), {".": "i"}, labels)
set_players(d, [("Skarn's Brood", "ashen", True, 1), ("The Frostmarch", "frostmarch", False, 2),
                ("Hrakka's Brood", "ashen", False, 1)])
set_hero(d, "hero_p1", "Ulvra Hrimsdottir", "thane", faction_army("frostmarch", 7, 4.0))
set_hero(d, "hero_p2", "Hrakka Ninefang", "warlord", faction_army("ashen", 6, 3.0))
obj(d, "town_start_0")["name"] = "Cinderfast"
obj(d, "town_start_1")["name"] = "Rimehold"
obj(d, "town_start_2").update({"id": "town_hrakkas_warren", "name": "Hrakka's Warren"})
obj(d, "town_heart").update({"name": "Ashfall", "town_type": "frostmarch"})
finish(d, 6911)


# ----------------------------------------------------------- chapter 9: the maw (C)
# The Cinder Maw's pit smokes in the Host's start (north-east). Castellan Odo
# Brack's relief army holds the west; the Highmere road fort the south.
d = chapter("gen:random_xl_3p_normal_normal_ring:1", "un_maw", "The Cinder Maw",
            "The Unsealing chapter 9 (C). Frozen from gen:random_xl_3p_normal_normal_ring:1 and tuned in tools/maps/build_unsealing_maps.py: the Host in the north-east around the Cinder Maw's pit (a volcano set piece), the Concord relief army in the west and its fort on the Highmere road in the south.")
labels = zone_map(d)
faction_zone(d, "start_0", "ashen", labels)
faction_zone(d, "start_1", "concord", labels)
for o in d["objects"] + d["heroes"]:
    if o.get("owner") == 2:
        o["owner"] = 1
drop(d, "hero_p2")
set_players(d, [("Skarn's Brood", "ashen", True), ("The Relief of Highmere", "concord", False)])
set_hero(d, "hero_p1", "Odo Brack", "knight", faction_army("concord", 8, 4.5))
town0 = obj(d, "town_start_0")
town0["name"] = "The Maw's Lip"
obj(d, "town_start_1")["name"] = "Brack's Muster"
obj(d, "town_start_2").update({"id": "town_highmere_road", "name": "The Highmere Road Fort"})
MAW = landmark_near(d, town0["pos"][0] - 7, town0["pos"][1] - 3, "landmark_cinder_volcano")
deco_pattern(d, MAW[0] + 1, MAW[1] + 5, "cinders")
finish(d, 7603)


# ------------------------------------------------- campaign wiring (map fields)
HOST_SLOT = {"type": "human", "faction": "ashen", "name": "Skarn's Brood"}
wire_chapters("unsealing", {
    "un_brood_war": {"map": "un_brood_war", "setup": {"players": [HOST_SLOT, {"type": "computer", "faction": "ashen", "name": "Hrakka's Brood"}]}},
    "un_wardens_keep": {"map": "un_wardens_keep",
        "setup": {"players": [HOST_SLOT, {"type": "computer", "faction": "forge", "name": "The Wardens"}]},
        "scenario": {"name": "The Wardens' Keep", "player": 0, "deadline_day": 21, "required_heroes": ["hero_ithra"],
            "objectives": [
                {"id": "crack", "type": "reach", "hero": "hero_ithra", "pos": list(CRACK), "text": "Bring Ithra to the crack under the keep's wall"},
                {"id": "keep", "type": "control_towns", "towns": ["town_wardens_keep"], "text": "Take the Wardens' Keep"}]}},
    "un_under_barrows": {"map": "un_under_barrows",
        "setup": {"players": [dict(HOST_SLOT, team=1), {"type": "computer", "faction": "hollow", "name": "The Regent", "team": 2},
                              {"type": "computer", "faction": "hollow", "name": "Morrow's Barrow-Lords", "team": 2},
                              {"type": "computer", "faction": "ashen", "name": "Hrakka's Brood", "team": 1}]},
        "scenario": {"name": "Under the Barrows", "player": 0, "objectives": [
            {"id": "conquer", "type": "conquer", "text": "Drive the Regent and the Barrow-Lords out of the Barrow Below"},
            {"id": "hrakka", "type": "ally_survives", "player": 3, "text": "Hrakka's Brood must not fall"}]}},
    "un_kindling": {"map": "un_kindling",
        "setup": {"players": [HOST_SLOT, {"type": "computer", "faction": "thornwood", "name": "The Thornwood Covenant"}]},
        "scenario": {"name": "Kindling the Elderwold", "player": 0, "townless_players": [0], "objectives": [
            {"id": "take_town", "type": "control_towns", "towns": ["town_elderhollow"], "text": "Take Elderhollow"},
            {"id": "conquer", "type": "conquer", "text": "Burn the Covenant out of its last groves"}]}},
    "un_ford": {"map": "un_ford", "setup": {"players": [HOST_SLOT, {"type": "computer", "faction": "concord", "name": "The Concord"}]}},
    "un_ash_snow": {"map": "un_ash_snow",
        "setup": {"players": [dict(HOST_SLOT, team=1), {"type": "computer", "faction": "frostmarch", "name": "The Frostmarch", "team": 2},
                              {"type": "computer", "faction": "ashen", "name": "Hrakka's Brood", "team": 1}]},
        "scenario": {"name": "Ash on the Snow", "player": 0,
            "betrayal": {"player": 2, "joins": 1, "trigger": {"day": 18, "towns_taken": {"towns": ["town_start_0"], "count": 1, "by": 1}},
                "text": "Snow eats fire. Hrakka's brood goes back to the warm, and takes the Host's name with it.",
                "reinforcements": [["flayer", 12], ["ash_witch", 8], ["gorgewing", 4]]},
            "objectives": [
                {"id": "hrakka", "type": "ally_survives", "player": 2, "until_betrayal": True, "text": "Keep Hrakka's Brood in the field"},
                {"id": "conquer", "type": "conquer", "text": "Break the Frostmarch, and whoever stands with it"}]}},
    "un_maw": {"map": "un_maw", "setup": {"players": [HOST_SLOT, {"type": "computer", "faction": "concord", "name": "The Relief of Highmere"}]}},
}, OUT)
