"""Builds the hand-made maps of the Abyssal Shoal campaign "The Drowned Oath":
tablets_of_sarranth (chapter 1, the swamp coast where the Shoal lives) and
who_was_cold_first (chapter 10, one against two: the Shoal against the clans and
the Concord in the snow). The other chapters are generated maps (see
data/campaigns.json).

Edit the layouts here, then regenerate:  python3 tools/maps/build_drowned_oath_maps.py data/maps
and run ./run_tests.sh dlc_campaigns. The script runs the same quick
reachability check as the other builders.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
maps = {}

COLORS.setdefault("darkelf", "#b48ce0")
COLORS.setdefault("fishmen", "#5cc9bd")
SHOAL = player(0, "Ilo's Shoal", "fishmen", human=True)

# ------------------------------------------------- chapter 1: the tablets of sarranth
# The drowned coast: tidal swamp between two fish-folk reefs. Ilo's shoal keeps
# the western shore, Chief Gorrok Bluntjaw's reef lies east across a brackish
# lagoon; the drowned vault with the tablets is on the sandbar between them.
g = Grid(24, 16, 'w')
g.rect(0, 0, 23, 0, '#'); g.rect(0, 15, 23, 15, '#')      # open sea north and south
g.rect(0, 1, 23, 1, 'w')
g.blob(12, 8, 2.4, '#'); g.rect(1, 8, 22, 8, 'w')          # the lagoon and its sandbar
g.blob(6, 3, 1.4, '.'); g.blob(18, 12, 1.4, '.')           # dry hummocks
g.blob(12, 3, 1.1, 'f'); g.blob(12, 13, 1.1, 'f')          # mangrove thickets
g.blob(5, 12, 0.3, '^'); g.blob(18, 4, 0.3, '^')           # sea-stacks
maps["tablets_of_sarranth"] = {
    "_doc": "The Drowned Oath chapter 1. Hand-made (tools/maps/build_drowned_oath_maps.py). The drowned coast: tidal swamp between two fish-folk reefs. Ilo's shoal in the west, Chief Gorrok Bluntjaw's reef in the east across a brackish lagoon, the drowned vault with the tablets of Sarranth on the sandbar between them. Both sides are Abyssal and capped at tier 2.",
    "id": "tablets_of_sarranth", "name": "The Tablets of Sarranth", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(2, 8), (21, 8)]) + roads([(6, 8), (6, 4)]) + roads([(17, 8), (17, 12)]),
    "players": [SHOAL, player(1, "Gorrok's Reef", "fishmen", color="#3a7a8a")],
    "heroes": [
        hero("hero_ilo", "Ilo Who Reads", "fm_deep_oracle", 0, 3, 8, [["fm_brine_spear", 22], ["fm_hookcaster", 8]]),
        hero("hero_thunn", "Thunn Reefbreaker", "fm_tidemarshal", 0, 3, 9, [["fm_brine_spear", 20], ["fm_hookcaster", 6]]),
        hero("hero_gorrok", "Chief Gorrok Bluntjaw", "fm_tidemarshal", 1, 20, 8, [["fm_brine_spear", 28], ["fm_hookcaster", 9]]),
    ],
    "objects": [
        town("town_west_reef", 2, 8, "fishmen", "The Reading Reef", 0, ["fm_hall", "fm_tavern", "fm_palisade", "fm_dw1", "fm_dw2"], [["fm_brine_spear", 12]]),
        town("town_gorrok", 21, 8, "fishmen", "Bluntjaw Reef", 1, ["fm_hall", "fm_palisade", "fm_dw1", "fm_dw2"], [["fm_brine_spear", 14], ["fm_hookcaster", 4]]),
        mine("mine_wood", 6, 3, "wood"), mine("mine_ore", 4, 12, "ore"),
        mine("mine_crystal", 18, 12, "crystal", [["bog_lurker", 4]]),
        mine("mine_gems", 19, 3, "gems", [["marsh_hag", 5]]),
        res("res_gold_1", 7, 6, "gold", 500), res("res_gold_2", 11, 11, "gold", 750), res("res_gold_3", 17, 10, "gold", 1000),
        res("res_wood_1", 2, 13, "wood", 5), res("res_ore_1", 8, 2, "ore", 5), res("res_crystal_1", 14, 5, "crystal", 3),
        res("res_gems_1", 21, 13, "gems", 2),
        army("neutral_sandbar", 12, 8, "Gorrok's spears on the sandbar", [["fm_brine_spear", 18]]),
        army("neutral_north_thicket", 12, 4, "Things in the mangroves", [["moss_creeper", 12]]),
        army("neutral_south_thicket", 12, 12, "Marsh rats", [["plague_rats", 14]]),
        army("neutral_hummock", 16, 2, "Carrion flock", [["carrion_flock", 8]]),
        enc("enc_chapel", 10, 8, "drowned_chapel"), enc("enc_cartographer", 9, 13, "blind_cartographer"),
        art("art_waders", 1, 3, "marsh_waders"), art("art_lantern", 22, 12, "lantern_of_the_lost"),
    ],
}

# ------------------------------------------------- chapter 10: who was cold first
# One against two. The Shoal comes up the Whaleroad river from the south-west in
# the Forgewarm Harness. Kettlehall holds the snowfield in the north-east; the
# Concord under Wren holds the Hall of the Endless Feast and the fords in the
# south-east. Each is its own allied computer player at the easy difficulty.
g = Grid(34, 26, 's')
g.rect(0, 14, 11, 25, 'w'); g.rect(0, 20, 16, 25, 'w')    # the rivermouth marsh (the Shoal's ground)
g.rect(12, 9, 12, 25, '~'); g.rect(12, 9, 33, 9, '~')     # the Whaleroad river, then its northern bend
g.rect(12, 16, 12, 17, 's'); g.rect(22, 9, 23, 9, 's')    # two fords
g.rect(13, 10, 33, 25, 'r')                               # the Concord's frozen downs south of the bend
g.rect(13, 22, 33, 25, '.')                               # the Feast-Hall's farmland
g.blob(6, 5, 1.5, '^'); g.blob(20, 4, 1.4, '^'); g.blob(29, 3, 1.2, '^')
g.blob(18, 14, 1.4, '^'); g.blob(27, 17, 1.2, '^')
g.blob(4, 11, 1.2, 'f'); g.blob(24, 20, 1.4, 'f')
g.rect(0, 0, 33, 0, '^'); g.rect(0, 25, 33, 25, '^')
maps["who_was_cold_first"] = {
    "_doc": "The Drowned Oath chapter 10, one against two. Hand-made (tools/maps/build_drowned_oath_maps.py). The Shoal comes up the Whaleroad river from the rivermouth marsh in the south-west. Kettlehall holds the snowfield in the north-east, the Concord under Aldous Wren holds the Hall of the Endless Feast on the frozen downs in the south-east. The clans and the Concord are allied computer players (team 1) at the easy difficulty (one against two). The Shoal needs the Forgewarm Harness on the snow.",
    "id": "who_was_cold_first", "name": "Who Was Cold First", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(3, 17), (12, 17), (20, 17), (29, 17), (29, 22)]) + roads([(20, 17), (20, 10), (22, 10), (22, 5), (29, 5)]),
    "players": [SHOAL, player(1, "Clan Kettleborn", "frostmarch", difficulty="easy", team=1), player(2, "The Hall of the Endless Feast", "concord", difficulty="easy", team=1)],
    "heroes": [
        hero("hero_ilo", "Ilo Who Reads", "fm_deep_oracle", 0, 4, 17,
             [["fm_brine_spear", 90], ["fm_hookcaster", 36], ["fm_shellback", 22], ["fm_mire_crab", 12], ["fm_lantern_acolyte", 6],
              ["fm_tide_mauler", 4], ["fm_coil_serpent", 2], ["fm_trench_titan", 1]]),
        hero("hero_thunn", "Thunn Reefbreaker", "fm_tidemarshal", 0, 4, 16,
             [["fm_brine_spear", 60], ["fm_hookcaster", 24], ["fm_shellback", 14], ["fm_mire_crab", 6], ["fm_tide_mauler", 2]]),
        hero("hero_sael", "Sael Hookhand", "fm_reef_hunter", 0, 4, 18,
             [["fm_brine_spear", 44], ["fm_hookcaster", 18], ["fm_lantern_acolyte", 6], ["fm_coil_serpent", 1]]),
        hero("hero_ulvra", "Ulvra Kettleborn", "thane", 1, 28, 5,
             [["clan_raider", 90], ["rimefang_hound", 34], ["oathless_berserker", 22], ["tusk_rider", 12], ["frost_shaman", 8], ["rimeback_aurochs", 4],
              ["cairn_giant", 1], ["winter_wyrm", 1]]),
        hero("hero_iska", "Seer Iska Rime", "frostcaller", 1, 27, 4,
             [["clan_raider", 50], ["rimefang_hound", 20], ["frost_shaman", 8], ["cairn_giant", 1]]),
        hero("hero_wren", "Aldous Wren", "knight", 2, 28, 22,
             [["pike_militia", 70], ["longbowman", 26], ["shieldwarden", 16], ["lancer", 10], ["lightbearer", 5], ["sunhawk_rider", 3],
              ["bastion_colossus", 1]]),
    ],
    "objects": [
        town("town_rivermouth", 3, 17, "fishmen", "The Rivermouth Camp", 0,
             ["fm_hall", "fm_court", "fm_tavern", "fm_market", "fm_palisade", "fm_keep", "fm_dw1", "fm_dw2", "fm_dw3", "fm_dw4", "fm_dw5", "fm_dw6",
              "fm_up1", "fm_up2"], [["fm_brine_spear", 40], ["fm_hookcaster", 16]]),
        town("town_kettlehall", 30, 5, "frostmarch", "Kettlehall", 1,
             ["r_hall", "r_court", "r_market", "r_fort1", "r_fort2", "r_dw1", "r_dw2", "r_dw3", "r_dw4", "r_dw5", "r_dw6"],
             [["clan_raider", 50], ["rimefang_hound", 20], ["oathless_berserker", 12]]),
        town("town_feast_hall", 30, 22, "concord", "The Hall of the Endless Feast", 2,
             ["c_hall", "c_market", "c_palisade", "c_keep", "c_dw1", "c_dw2", "c_dw3", "c_dw4", "c_dw5"],
             [["pike_militia", 40], ["longbowman", 10]]),
        town("town_whaleroad", 16, 4, "frostmarch", "Whaleroad Steading", -1, ["r_hall", "r_fort1", "r_dw1", "r_dw2"],
             [["clan_raider", 40], ["rimefang_hound", 14]]),
        mine("mine_wood", 3, 22, "wood"), mine("mine_ore", 8, 15, "ore"),
        mine("mine_crystal", 9, 3, "crystal", [["frost_drake", 4]]), mine("mine_gems", 16, 23, "gems", [["hill_troll", 8]]),
        mine("mine_gold", 20, 13, "gold", [["rime_wight", 12]]), mine("mine_sulfur", 25, 12, "sulfur"), mine("mine_mercury", 25, 2, "mercury"),
        res("res_gold_1", 8, 20, "gold", 1000), res("res_gold_2", 15, 12, "gold", 1500), res("res_gold_3", 23, 15, "gold", 2000),
        res("res_wood_1", 1, 23, "wood", 8), res("res_ore_1", 1, 2, "ore", 8), res("res_crystal_1", 32, 1, "crystal", 4),
        res("res_gems_1", 10, 8, "gems", 4), res("res_sulfur_1", 32, 13, "sulfur", 4), res("res_mercury_1", 22, 2, "mercury", 4),
        army("neutral_ford_south", 13, 17, "Clan watch at the ford", [["clan_raider", 60]]),
        army("neutral_ford_north", 22, 8, "Wolves on the ice", [["thornwolf", 30]]),
        army("neutral_downs", 24, 17, "Harpies of the downs", [["shrieking_harpy", 18]]),
        army("neutral_snow", 12, 5, "Rime wights", [["rime_wight", 14]]),
        enc("enc_cairn", 23, 4, "barrow_field"), enc("enc_column", 9, 12, "dispossessed_column"), enc("enc_toll", 26, 20, "brigand_toll"),
        art("art_boots", 1, 16, "rimetread_boots"), art("art_standard", 32, 17, "standard_of_the_hold"), art("art_bow", 17, 20, "longwatch_bow"),
    ],
}


# The layouts above are drawn on small grids; the maps are played larger, like
# the other campaign maps. See maplib.enlarge.
enlarge(maps, {"tablets_of_sarranth": 2.5, "who_was_cold_first": 2.7})

# Map overhaul (Nov 9): both maps get the painted look of the other kept
# layouts (maplib.dress_handmade). The Tablets, which played straight west to
# east, is turned so Ilo's shoal keeps the southern shore and Gorrok's reef
# lies north across the lagoon.
rotate(maps["tablets_of_sarranth"], 3)
maps["tablets_of_sarranth"]["_doc"] = maps["tablets_of_sarranth"]["_doc"].replace(
    "Ilo's shoal in the west, Chief Gorrok Bluntjaw's reef in the east across a brackish lagoon",
    "Ilo's shoal in the south, Chief Gorrok Bluntjaw's reef in the north across a brackish lagoon")

build(maps, OUT, {"tablets_of_sarranth": 91, "who_was_cold_first": 95})
