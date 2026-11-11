"""Builds the hand-made maps of the Umbral Court campaign "The Six Eyes":
below_the_sky (chapter 1, underground) and the_nightgate (chapter 10, hero-only
finale against the ancient dragon). The other chapters are generated maps (see
data/campaigns.json).

Edit the layouts here, then regenerate:  python3 tools/maps/build_six_eyes_maps.py data/maps
and run ./run_tests.sh dlc_campaigns. The finale is drawn at full size (no
enlarge) because its scenario objectives name tiles.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
maps = {}

COLORS["darkelf"] = "#b48ce0"
COLORS["fishmen"] = "#5cc9bd"
WARDENS = player(0, "The Nightgate Wardens", "darkelf", human=True)

# ------------------------------------------------- chapter 1: below the sky
# The Court's cavern: the Wardens' hold on the western terrace, House Draal's
# enclave on the eastern one, the tithe-caverns (mines) between them around an
# underground lake. Both sides are Umbral and capped at tier 2.
g = Grid(24, 16, 'r')
g.blob(12, 2, 1.0, 'i'); g.blob(12, 14, 1.0, 'i')         # vents from the deep
g.rect(0, 0, 23, 0, '^'); g.rect(0, 15, 23, 15, '^')
g.blob(12, 8, 2.6, '#')                                   # the black lake
g.rect(1, 8, 22, 8, 'r')                                  # the causeway across it
g.blob(6, 3, 0.3, '^'); g.blob(17, 3, 0.3, '^'); g.blob(6, 13, 0.3, '^'); g.blob(17, 13, 0.3, '^')   # pillars
g.rect(9, 1, 9, 5, '^'); g.rect(9, 11, 9, 14, '^')        # the Wardens' wall, one gap north and south
g.rect(15, 1, 15, 4, '^'); g.rect(15, 12, 15, 14, '^')    # Draal's wall
maps["below_the_sky"] = {
    "_doc": "The Six Eyes chapter 1. Hand-made (tools/maps/build_six_eyes_maps.py). The Umbral Court's cavern: the Nightgate Wardens' hold on the western terrace, House Draal's enclave in the east, the tithe-caverns between them around a black lake with one causeway. Both sides are Umbral and capped at tier 2.",
    "id": "below_the_sky", "name": "Below the Sky", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(2, 8), (21, 8)]) + roads([(5, 8), (5, 4)]) + roads([(5, 8), (5, 12)]),
    "players": [WARDENS, player(1, "House Draal", "darkelf", color="#7a5a8a")],
    "heroes": [
        hero("hero_serane", "Serane Nhalvor", "de_dreadmarshal", 0, 3, 8, [["de_gloam_spear", 28], ["de_shardbow", 9]]),
        hero("hero_ulmarra", "Matriarch Ulmarra", "de_veilseer", 0, 3, 9, [["de_gloam_spear", 16], ["de_shardbow", 6]]),
        hero("hero_sareth", "Sareth Draal", "de_dreadmarshal", 1, 20, 8, [["de_gloam_spear", 26], ["de_shardbow", 8]]),
    ],
    "objects": [
        town("town_wardens_hold", 2, 8, "darkelf", "The Wardens' Hold", 0, ["de_hall", "de_tavern", "de_palisade", "de_dw1", "de_dw2"], [["de_gloam_spear", 12]]),
        town("town_draal", 21, 8, "darkelf", "Draal's Terrace", 1, ["de_hall", "de_palisade", "de_dw1", "de_dw2"], [["de_gloam_spear", 14], ["de_shardbow", 4]]),
        mine("mine_wood", 5, 4, "wood"), mine("mine_ore", 5, 12, "ore"),
        mine("mine_crystal", 18, 3, "crystal", [["cave_stalker", 4]]),
        mine("mine_gems", 18, 13, "gems", [["gloom_panther", 5]]),
        res("res_gold_1", 7, 6, "gold", 500), res("res_gold_2", 11, 11, "gold", 750), res("res_gold_3", 17, 11, "gold", 1000),
        res("res_wood_1", 4, 11, "wood", 5), res("res_ore_1", 7, 3, "ore", 5), res("res_crystal_1", 13, 5, "crystal", 3),
        res("res_gems_1", 20, 13, "gems", 2),
        army("neutral_causeway", 9, 8, "Draal's spears on the causeway", [["de_gloam_spear", 16]]),
        army("neutral_north_gap", 9, 6, "Scuttlers in the north gap", [["tomb_scarabs", 10]]),
        army("neutral_south_gap", 9, 10, "Rats in the south gap", [["plague_rats", 14]]),
        army("neutral_vent", 12, 13, "Things from the vent", [["moss_creeper", 10]]),
        enc("enc_echoes", 12, 4, "hall_of_echoes"), enc("enc_cartographer", 11, 12, "blind_cartographer"),
        art("art_sallet", 4, 2, "dented_sallet"), art("art_buckler", 19, 12, "splintered_buckler"),
    ],
}

# ------------------------------------------------- chapter 10: the nightgate
# Hero-only. Serane and Rhuvel climb down the Long Stair into the Nightgate
# cavern with no town: three chambers joined by one-tile passes. House
# Vexmire's gate-hold sits in the middle chamber with Matriarch Ulmarra; the
# Nightgate itself is a one-tile pass at the east end, and Karzhaloth stands in
# it. Two villages of Court folk who kept faith sell the only reinforcements.
W, H = 64, 44
g = Grid(W, H, '^')
g.blob(11, 22, 8.0, 'r')                                   # the landing chamber (west)
g.blob(32, 22, 11.0, 'r')                                  # the gate-hold chamber (middle)
g.blob(53, 22, 7.0, 'r')                                   # the gate chamber (east)
g.rect(18, 22, 22, 22, 'r')                                # pass west -> middle (one tile wide)
g.rect(42, 22, 47, 22, 'r')                                # pass middle -> east
g.blob(32, 8, 3.5, 'r'); g.rect(32, 11, 32, 12, 'r')       # north alcove (village)
g.blob(32, 36, 3.5, 'r'); g.rect(32, 32, 32, 33, 'r')      # south alcove (village)
g.blob(32, 22, 3.0, '#')                                   # the well in the middle chamber
g.rect(28, 22, 36, 22, 'r')                                # a causeway over the well
g.blob(56, 22, 2.5, 'i'); g.rect(59, 22, 61, 22, 'i')      # the gate's threshold burns
g.blob(8, 16, 1.2, 'i'); g.blob(10, 29, 1.2, 'i')
GATE = (61, 22)
maps["the_nightgate"] = {
    "_doc": "The Six Eyes chapter 10, the finale. Hand-made (tools/maps/build_six_eyes_maps.py), drawn at full size because the scenario names tiles. Hero-only: the Wardens have no town (scenario townless_players). Three cavern chambers joined by one-tile passes; House Vexmire's gate-hold in the middle with Matriarch Ulmarra; the Nightgate at the east end with Karzhaloth, the ancient dragon, standing in it. Objectives: defeat Ulmarra and reach the gate with Serane.",
    "id": "the_nightgate", "name": "The Nightgate", "width": W, "height": H, "terrain": g.rows(),
    "roads": roads([(6, 22), (60, 22)]),
    "players": [WARDENS, player(1, "House Vexmire", "darkelf", color="#5a3a6a", difficulty="normal")],
    "heroes": [
        hero("hero_serane", "Serane Nhalvor", "de_dreadmarshal", 0, 6, 22,
             [["de_gloam_spear", 140], ["de_shardbow", 60], ["de_knifedancer", 36], ["de_cave_lancer", 24], ["de_veil_adept", 16],
              ["de_silk_stalker", 10], ["de_obsidian_guard", 6], ["de_gloam_drake", 4]]),
        hero("hero_rhuvel", "Rhuvel Askai", "de_nightstalker", 0, 6, 23,
             [["de_shardbow", 50], ["de_knifedancer", 24], ["de_cave_lancer", 14], ["de_veil_adept", 10], ["de_silk_stalker", 6], ["de_gloam_drake", 2]]),
        hero("hero_ulmarra", "Matriarch Ulmarra", "de_veilseer", 1, 35, 18,
             [["de_gloam_spear", 90], ["de_shardbow", 40], ["de_knifedancer", 24], ["de_cave_lancer", 14], ["de_veil_adept", 14],
              ["de_silk_stalker", 8], ["de_obsidian_guard", 4], ["de_gloam_drake", 3]]),
    ],
    "objects": [
        town("town_gate_hold", 34, 19, "darkelf", "The Gate-Hold", 1,
             ["de_hall", "de_court", "de_market", "de_palisade", "de_keep", "de_bastion", "de_dw1", "de_dw2", "de_dw3", "de_dw4", "de_dw5", "de_dw6", "de_dw7",
              "de_up1", "de_up2", "de_up3"], [["de_gloam_spear", 60], ["de_shardbow", 24], ["de_obsidian_guard", 3]]),
        {"id": "site_faithful_north", "type": "site", "site": "fenside_hamlet", "pos": [32, 7], "guard": [["de_knifedancer", 12]],
         "stock": [["de_knifedancer", 30], ["de_cave_lancer", 12]]},
        {"id": "site_faithful_south", "type": "site", "site": "ashfield_steading", "pos": [32, 37], "guard": [["de_shardbow", 20]],
         "stock": [["de_silk_stalker", 8], ["de_obsidian_guard", 3]]},
        mine("mine_gold_w", 11, 16, "gold"), mine("mine_gold_e", 52, 27, "gold", [["de_cave_lancer", 10]]),
        mine("mine_crystal", 10, 28, "crystal"), mine("mine_gems", 37, 27, "gems", [["de_veil_adept", 8]]),
        res("res_gold_1", 14, 20, "gold", 2500), res("res_gold_2", 26, 18, "gold", 3000), res("res_gold_3", 38, 25, "gold", 3000),
        res("res_gold_4", 52, 18, "gold", 4000), res("res_gold_5", 27, 27, "gold", 2000),
        res("res_crystal_1", 15, 25, "crystal", 6), res("res_gems_1", 30, 14, "gems", 5), res("res_gems_2", 54, 26, "gems", 6),
        army("neutral_first_pass", 20, 22, "Vexmire's gate-wards", [["de_obsidian_guard", 10], ["de_gloam_spear", 60]]),
        army("neutral_second_pass", 44, 22, "The Eyeless Guard", [["de_onyx_executioner", 8], ["de_blood_scythe", 30], ["de_mirror_witch", 10]]),
        army("neutral_drakes", 50, 17, "Drakes of the gate", [["de_gloam_drake", 6]]),
        army("neutral_dragon", 59, 22, "Karzhaloth, the Ancient Dragon", [["ancient_dragon", 1]]),
        army("neutral_well", 32, 18, "Things from the well", [["cave_stalker", 24]]),
        enc("enc_echoes", 9, 19, "hall_of_echoes"), enc("enc_rift", 55, 25, "ember_rift"),
        art("art_crown", 53, 19, "crown_of_thorns"), art("art_visor", 12, 27, "gravewatch_visor"),
    ],
    "scenario": {
        "name": "The Nightgate", "player": 0, "townless_players": [0],
        "briefing": "There is no town below the stair and no way back up it. Break House Vexmire's gate-hold, kill the Matriarch, and reach the Nightgate before Karzhaloth is fully awake.",
        "objectives": [
            {"id": "ulmarra", "type": "defeat_hero", "hero": "hero_ulmarra", "text": "Defeat Matriarch Ulmarra."},
            {"id": "gate", "type": "reach", "hero": "hero_serane", "pos": list(GATE), "text": "Reach the Nightgate with Serane. Karzhaloth stands in it."},
        ],
    },
}

enlarge(maps, {"below_the_sky": 2.5})

# Map overhaul (Nov 9): the hand-made maps get the painted look of the other
# kept layouts (maplib.dress_handmade: wavy biome borders, ground patches,
# ragged rock, painted decoration). Below the Sky, which played straight west to
# east, is turned so the Wardens hold the north terrace and House Draal the
# south; the Nightgate keeps its orientation because its scenario names tiles.
rotate(maps["below_the_sky"], 1)
maps["below_the_sky"]["_doc"] = maps["below_the_sky"]["_doc"].replace(
    "the Nightgate Wardens' hold on the western terrace, House Draal's enclave in the east",
    "the Nightgate Wardens' hold on the northern terrace, House Draal's enclave in the south")

build(maps, OUT, {"below_the_sky": 81, "the_nightgate": 85})
