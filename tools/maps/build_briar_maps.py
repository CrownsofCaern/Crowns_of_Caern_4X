"""Builds the maps of the Thornwood campaign "The Briar Oath".

Hand-made: axe_line (chapter 1), roots_remember (chapter 6) and briar_seal
(chapter 10, one against two). The other chapters (map overhaul phase 3)
start from frozen random-map layouts (maplib.freeze) and are tuned below;
their scenario rules (survival, townless, 2v2, betrayal) live in the chapter's
"scenario" in data/campaigns.json, which this script writes (map fields only).

Edit the layouts here, then regenerate:  python3 tools/maps/build_briar_maps.py data/maps
(needs Godot: $GODOT or godot on PATH) and run ./run_tests.sh faction_campaigns.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
maps = {}

COVENANT = player(0, "The Thornwood Covenant", "thornwood", human=True)

# ------------------------------------------------- chapter 1: the axe line
# The last grove in the west, the Concord's logging camp in the east, and
# between them the stumps the axes have already left. A slow river runs down the
# middle with a bridge on the road. Tier 2 for both sides.
g = Grid(24, 16, '.')
g.rect(0, 1, 8, 14, 'f')                  # the last grove
g.blob(15, 4, 2.0, 'r'); g.blob(16, 12, 2.0, 'r')     # stump fields
g.rect(11, 1, 11, 14, '~')                # the Thornbrook
g.blob(5, 3, 1.0, '^'); g.blob(4, 12, 1.0, '^'); g.blob(20, 2, 1.0, '^'); g.blob(20, 13, 1.0, '^')
g.rect(0, 0, 23, 0, '^'); g.rect(0, 15, 23, 15, '^')
maps["axe_line"] = {
    "_doc": "The Briar Oath chapter 1. Hand-made (tools/maps/build_briar_maps.py). The Covenant's last grove in the west, the Concord logging camp of Axeford in the east, stump fields and the Thornbrook between. Both sides are capped at tier 2.",
    "id": "axe_line", "name": "The Axe Line", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(2, 8), (21, 8)]) + roads([(15, 8), (15, 2)]),
    "players": [COVENANT, player(1, "Axeford Timber Company", "concord")],
    "heroes": [
        hero("hero_cerrid", "Cerrid Ashbark", "grovewarden", 0, 3, 8, [["thorn_skulker", 30], ["barkhide_warden", 10]]),
        hero("hero_neve", "Neve Hollowreed", "huntmaster", 0, 3, 9, [["thorn_skulker", 16], ["barkhide_warden", 6]]),
        hero("hero_tallow", "Foreman Hugh Tallow", "knight", 1, 20, 8, [["pike_militia", 26], ["longbowman", 8]]),
    ],
    "objects": [
        town("town_heartgrove", 2, 8, "thornwood", "Heartgrove", 0, ["t_hall", "t_tavern", "t_fort1", "t_dw1", "t_dw2"], [["thorn_skulker", 12]]),
        town("town_axeford", 21, 8, "concord", "Axeford", 1, ["c_hall", "c_palisade", "c_dw1", "c_dw2"], [["pike_militia", 14], ["longbowman", 4]]),
        mine("mine_wood", 5, 6, "wood"), mine("mine_ore", 6, 11, "ore"),
        mine("mine_gems", 18, 4, "gems", [["road_cutthroat", 8]]),
        res("res_gold_1", 7, 7, "gold", 500), res("res_gold_2", 10, 10, "gold", 750), res("res_gold_3", 14, 13, "gold", 1000),
        res("res_wood_1", 2, 2, "wood", 5), res("res_ore_1", 9, 4, "ore", 5), res("res_crystal_1", 13, 3, "crystal", 2),
        res("res_gold_4", 21, 12, "gold", 750),
        army("neutral_bridge", 11, 8, "Company guards on the bridge", [["deserter_crossbows", 6], ["road_cutthroat", 6]]),
        army("neutral_wolves", 7, 2, "Starving wolves", [["thornwolf", 8]]),
        army("neutral_stumps", 16, 11, "Moss creepers in the stumps", [["moss_creeper", 16]]),
        enc("enc_den", 4, 14, "thornwolf_den"), enc("enc_wagon", 17, 7, "overturned_wagon"),
        art("art_cloak", 1, 13, "pilgrims_cloak"), art("art_bow", 22, 2, "longwatch_bow"),
    ],
}

# ---------------------------------------------- chapter 6: what the roots remember
# The dead Heartroots in a ring of rock in the middle of the felled forest. The
# Covenant's Mossgate in the west, the first Ashen scouts' scorch camp in the
# east, already burning the ground around it. Tier 5 for both sides.
g = Grid(28, 20, 'r')                     # the felled forest: stumps
g.rect(0, 1, 8, 18, 'f')                  # what is left standing
g.blob(14, 10, 3.0, '.')                  # the Heartroots' clearing
g.rect(11, 6, 17, 6, '^'); g.rect(11, 14, 17, 14, '^'); g.rect(11, 7, 11, 8, '^'); g.rect(17, 12, 17, 13, '^')
g.rect(21, 1, 27, 18, 'i')                # scorched ground
g.blob(23, 4, 1.2, '^'); g.blob(24, 15, 1.2, '^'); g.blob(6, 4, 1.0, '^'); g.blob(5, 16, 1.0, '^')
g.rect(0, 0, 27, 0, '^'); g.rect(0, 19, 27, 19, '^')
maps["roots_remember"] = {
    "_doc": "The Briar Oath chapter 6. Hand-made (tools/maps/build_briar_maps.py). The dead Heartroots in a ring of rock in the felled Elderwold, the Covenant's Mossgate in the west and the first Ashen scouts' scorch camp in the east. Both sides are capped at tier 5.",
    "id": "roots_remember", "name": "What the Roots Remember", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(2, 10), (25, 10)]),
    "players": [COVENANT, player(1, "The Scorch Scouts", "ashen")],
    "heroes": [
        hero("hero_cerrid", "Cerrid Ashbark", "grovewarden", 0, 3, 10,
             [["thorn_skulker", 50], ["barkhide_warden", 20], ["briar_huntress", 12], ["rootbinder", 6], ["gloomwing_strix", 3]]),
        hero("hero_neve", "Neve Hollowreed", "huntmaster", 0, 3, 11, [["thorn_skulker", 30], ["barkhide_warden", 12], ["briar_huntress", 6]]),
        hero("hero_brakka", "Old Mother Brakka", "thornspeaker", 0, 3, 9, [["thorn_skulker", 26], ["barkhide_warden", 10], ["gloomwing_strix", 2]]),
        hero("hero_garsh", "Garsh Emberclaw", "warlord", 1, 24, 10,
             [["cinderling", 60], ["scorchhound", 22], ["brimstone_hurler", 12], ["flayer", 6], ["ash_witch", 3]]),
    ],
    "objects": [
        town("town_mossgate", 2, 10, "thornwood", "Mossgate", 0,
             ["t_hall", "t_tavern", "t_market", "t_fort1", "t_fort2", "t_dw1", "t_dw2", "t_dw3", "t_dw4"], [["thorn_skulker", 20]]),
        town("town_scorch_camp", 25, 10, "ashen", "The Scorch Camp", 1,
             ["a_hall", "a_den", "a_market", "a_trench", "a_dw1", "a_dw2", "a_dw3", "a_dw4", "a_dw5"],
             [["cinderling", 30], ["scorchhound", 10], ["brimstone_hurler", 6]]),
        enc("enc_heartroots", 14, 10, "hall_of_echoes"),
        mine("mine_wood", 5, 7, "wood"), mine("mine_ore", 6, 13, "ore"),
        mine("mine_crystal", 14, 3, "crystal", [["gloom_panther", 10]]),
        mine("mine_gems", 14, 17, "gems", [["venom_wyvern", 2]]),
        mine("mine_sulfur", 23, 7, "sulfur"), mine("mine_mercury", 23, 13, "mercury"),
        res("res_gold_1", 7, 9, "gold", 750), res("res_gold_2", 10, 4, "gold", 1000), res("res_gold_3", 19, 16, "gold", 1500),
        res("res_wood_1", 1, 2, "wood", 6), res("res_ore_1", 2, 17, "ore", 5), res("res_gems_1", 12, 11, "gems", 3),
        res("res_crystal_1", 16, 9, "crystal", 3), res("res_sulfur_1", 26, 2, "sulfur", 3),
        army("neutral_clearing_east", 18, 10, "Cinder wraiths at the roots", [["cinder_wraith", 6]]),
        army("neutral_north", 10, 2, "Gloom panthers", [["gloom_panther", 8]]),
        army("neutral_south", 10, 17, "Thornwolves", [["thornwolf", 20]]),
        enc("enc_den", 3, 4, "thornwolf_den"), enc("enc_rift", 22, 17, "ember_rift"),
        art("art_crown", 15, 9, "crown_of_thorns"), art("art_buckler", 26, 17, "splintered_buckler"),
    ],
}

# ---------------------------------------------- chapter 10: the briar seal
# One against two. The Covenant comes from the burned forest in the west. The
# Wound lies in the middle of the east side behind a ring of black rock, its lip
# open to the west. Two Ashen broods hold a town each, north and south of it.
g = Grid(34, 26, 'r')
g.rect(0, 1, 9, 24, 'f')                  # the burned forest's living edge
g.blob(25, 13, 4.0, 'i')                  # the lip of the Wound
g.rect(22, 8, 30, 8, '^'); g.rect(22, 18, 30, 18, '^'); g.rect(30, 9, 30, 17, '^')   # the black rock ring, open west
g.rect(21, 1, 33, 7, 'i'); g.rect(21, 19, 33, 24, 'i')    # the broods' ground
g.rect(31, 9, 33, 17, '^')
g.blob(15, 5, 1.5, '^'); g.blob(15, 21, 1.5, '^'); g.blob(6, 4, 1.0, '^'); g.blob(6, 22, 1.0, '^')
g.rect(0, 0, 33, 0, '^'); g.rect(0, 25, 33, 25, '^')
maps["briar_seal"] = {
    "_doc": "The Briar Oath chapter 10, one against two. Hand-made (tools/maps/build_briar_maps.py). The Covenant comes out of the burned forest in the west; the lip of the Wound lies behind a ring of black rock in the east, where the Wyrdthorn must be planted, and two Ashen broods hold a town each north and south of it. The broods are allied computer players (team 1), at the easy difficulty (one against two).",
    "id": "briar_seal", "name": "The Briar Seal", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(3, 13), (27, 13)]) + roads([(18, 13), (18, 4), (29, 4)]) + roads([(18, 13), (18, 22), (29, 22)]),
    "players": [COVENANT, player(1, "The Kindling Brood", "ashen", difficulty="easy", team=1), player(2, "The Ember Brood", "ashen", color="#d0782c", difficulty="easy", team=1)],
    "heroes": [
        hero("hero_cerrid", "Cerrid Ashbark", "grovewarden", 0, 4, 13,
             [["thorn_skulker", 90], ["barkhide_warden", 36], ["briar_huntress", 22], ["rootbinder", 12], ["gloomwing_strix", 8],
              ["spore_lobber", 4], ["rootbound_ancient", 2], ["wyrdthorn_mother", 1]]),
        hero("hero_neve", "Neve Hollowreed", "huntmaster", 0, 4, 12,
             [["thorn_skulker", 50], ["barkhide_warden", 20], ["briar_huntress", 14], ["gloomwing_strix", 4], ["spore_lobber", 2]]),
        hero("hero_brakka", "Old Mother Brakka", "thornspeaker", 0, 4, 14,
             [["thorn_skulker", 44], ["barkhide_warden", 18], ["rootbinder", 8], ["rootbound_ancient", 1]]),
        hero("hero_ithra", "Ithra Sootveil", "warlock", 1, 28, 4,
             [["cinderling", 90], ["scorchhound", 34], ["brimstone_hurler", 22], ["flayer", 12], ["ash_witch", 8], ["gorgewing", 4],
              ["pyre_titan", 1], ["cinder_maw", 1]]),
        hero("hero_morvath", "Morvath the Kindler", "tormentor", 2, 28, 22,
             [["cinderling", 70], ["scorchhound", 26], ["brimstone_hurler", 16], ["flayer", 10], ["ash_witch", 6], ["gorgewing", 3],
              ["pyre_titan", 1]]),
    ],
    "objects": [
        town("town_last_grove", 3, 13, "thornwood", "The Last Grove", 0,
             ["t_hall", "t_court", "t_tavern", "t_market", "t_fort1", "t_fort2", "t_dw1", "t_dw2", "t_dw3", "t_dw4", "t_dw5", "t_dw6",
              "t_up1", "t_up2"], [["thorn_skulker", 40], ["barkhide_warden", 16]]),
        town("town_kindling_pit", 30, 4, "ashen", "The Kindling Pit", 1,
             ["a_hall", "a_den", "a_market", "a_trench", "a_wall", "a_dw1", "a_dw2", "a_dw3", "a_dw4", "a_dw5", "a_dw6"],
             [["cinderling", 50], ["scorchhound", 20], ["brimstone_hurler", 12]]),
        town("town_ember_pit", 30, 22, "ashen", "The Ember Pit", 2,
             ["a_hall", "a_market", "a_trench", "a_dw1", "a_dw2", "a_dw3", "a_dw4", "a_dw5"],
             [["cinderling", 40], ["brimstone_hurler", 10]]),
        enc("enc_wound", 27, 13, "ember_rift"),
        mine("mine_wood", 6, 8, "wood"), mine("mine_ore", 6, 18, "ore"),
        mine("mine_crystal", 13, 3, "crystal", [["gloom_panther", 14]]),
        mine("mine_gems", 13, 23, "gems", [["venom_wyvern", 4]]),
        mine("mine_gold", 20, 11, "gold", [["cinder_wraith", 10]]), mine("mine_sulfur", 24, 5, "sulfur"), mine("mine_mercury", 24, 21, "mercury"),
        res("res_gold_1", 8, 10, "gold", 1000), res("res_gold_2", 12, 16, "gold", 1500), res("res_gold_3", 19, 8, "gold", 2000),
        res("res_wood_1", 2, 3, "wood", 8), res("res_ore_1", 2, 22, "ore", 8), res("res_crystal_1", 17, 18, "crystal", 4),
        res("res_gems_1", 11, 7, "gems", 4), res("res_sulfur_1", 32, 1, "sulfur", 4), res("res_mercury_1", 32, 24, "mercury", 4),
        army("neutral_road", 14, 13, "Ash-blind refugees", [["lost_pilgrims", 50]]),
        army("neutral_lip", 22, 13, "Basilisks at the lip", [["ashscale_basilisk", 10]]),
        army("neutral_north", 18, 2, "Cinder wraiths", [["cinder_wraith", 10]]),
        army("neutral_south", 18, 24, "Tomb scarabs", [["tomb_scarabs", 24]]),
        enc("enc_den", 8, 22, "thornwolf_den"), enc("enc_shrine", 20, 15, "ashen_saint_shrine"), enc("enc_column", 11, 4, "dispossessed_column"),
        art("art_crown", 1, 1, "crown_of_thorns"), art("art_hornwall", 26, 10, "hornwall_targe"), art("art_compass", 21, 24, "wayfarers_compass"),
    ],
}


# The layouts above are drawn on small grids; the maps are played larger
# (playtests, Nov 7: the campaign maps felt small, twice). See maplib.enlarge.
# Map overhaul (Nov 9): the finale is rebuilt bigger, like the other late chapters.
enlarge(maps, {"axe_line": 2.5, "roots_remember": 2.65, "briar_seal": 3.2})

# Map overhaul (Nov 9): the kept layouts get a new look (maplib.dress_handmade:
# wavy biome borders, ground patches, ragged rock, painted decoration), and the
# Heartroots map, which played straight west to east, is turned so the Covenant
# comes down from the north.
rotate(maps["roots_remember"], 1)
maps["roots_remember"]["_doc"] = maps["roots_remember"]["_doc"].replace("Mossgate in the west and the first Ashen scouts' scorch camp in the east", "Mossgate in the north and the first Ashen scouts' scorch camp in the south")


build(maps, OUT, {"axe_line": 61, "roots_remember": 66, "briar_seal": 70})


# =============================================================================
# Frozen-layout chapters (map overhaul phase 3). Each starts from a random-map
# layout picked from contact sheets; slot 0 is the player.

def chapter(source, mid, name, doc):
    return frozen_chapter(source, mid, name, doc)


def finish(d, seed):
    return finish_chapter(d, seed, OUT, ("Cerrid Ashbark", "grovewarden", [["thorn_skulker", 20], ["barkhide_warden", 10]]))


def to_slot(d, src, dst):
    """Hands slot src's towns, mines and sites to slot dst; its heroes leave."""
    for o in d["objects"]:
        if o.get("owner") == src:
            o["owner"] = dst
    d["heroes"] = [h for h in d["heroes"] if h["owner"] != src]


# ------------------------------------------------------ chapter 2: smoke (L)
# Same size as before (87x87), new layout: corner to corner. The Covenant in
# the south-east, Sir Piers Ashcombe's fire-camp in the north-west.
d = chapter("gen:random_xl_2p_normal_normal_diagonal:2", "tw_smoke", "Smoke on the Wind",
            "The Briar Oath chapter 2 (L). Frozen from gen:random_xl_2p_normal_normal_diagonal:2 and tuned in tools/maps/build_briar_maps.py: the Covenant's wood in the south-east, Sir Piers Ashcombe's fire-camp in the north-west, the high road across the heart and long loops round the far corners.")
labels = zone_map(d)
faction_zone(d, "start_0", "thornwood", labels)
faction_zone(d, "start_1", "concord", labels)
set_players(d, [("The Thornwood Covenant", "thornwood", True), ("Ashcombe's Fire-Camp", "concord", False)])
set_hero(d, "hero_p1", "Sir Piers Ashcombe", "knight", faction_army("concord", 3, 2.0))
obj(d, "town_start_0")["name"] = "Hollowmere"
fire = obj(d, "town_start_1")
fire.update({"id": "town_fire_camp", "name": "The Fire-Camp"})
deco_pattern(d, fire["pos"][0] + 4, fire["pos"][1] + 3, "cinders")
finish(d, 1187)


# ---------------------------------------------------- chapter 3: the ambush (C)
# Maelis Thorne's column holds the south and a fort in the east; the Covenant
# waits in the north-western wood.
d = chapter("gen:random_l_3p_normal_normal_hub:1", "tw_ambush", "The Ambush",
            "The Briar Oath chapter 3 (C). Frozen from gen:random_l_3p_normal_normal_hub:1 and tuned in tools/maps/build_briar_maps.py: the Covenant in the north-west, Maelis Thorne's column in the south with a fort in the east, three spokes into a thornwood heart.")
labels = zone_map(d)
faction_zone(d, "start_0", "thornwood", labels)
faction_zone(d, "start_1", "concord", labels)
retheme_zones(d, ["heart"], {"i": "f"}, labels)
to_slot(d, 2, 1)
set_players(d, [("The Thornwood Covenant", "thornwood", True), ("Thorne's Column", "concord", False)])
set_hero(d, "hero_p1", "Maelis Thorne", "ranger", faction_army("concord", 3, 2.5))
obj(d, "town_start_0")["name"] = "Bramblecourt"
obj(d, "town_start_1")["name"] = "The Column's Camp"
obj(d, "town_start_2")["name"] = "Fort Ashcombe"
finish(d, 1931)


# ---------------------------------------------------- chapter 4: the hunters (S)
# Survival: the Covenant's three living groves (its towns) must all stand
# through day 24. Hrodna Grimfell's starving clans hold the north and send waves
# down the three lanes from the northern edge. Snow lies on the northern wood.
d = chapter("gen:random_xl_2p_normal_normal_lanes:1", "tw_hunters", "The Hunters",
            "The Briar Oath chapter 4 (S, survival). Frozen from gen:random_xl_2p_normal_normal_lanes:1 and tuned in tools/maps/build_briar_maps.py: three living groves (the Covenant's towns) in the south, the Frostmarch clans in the snowy north, invasion waves from the northern edge down the three lanes.")
labels = zone_map(d)
retheme_zones(d, ["heart"], {"i": "f"}, labels)
retheme(d, {".": "s", "w": "s"}, lambda x, y: y < 40)
faction_zone(d, "start_0", "thornwood", labels)
faction_zone(d, "start_1", "frostmarch", labels)
set_players(d, [("The Thornwood Covenant", "thornwood", True, 1), ("Clan Grimfell", "frostmarch", False, 2),
                ("The Starving Clans", "frostmarch", False, 2)])
set_hero(d, "hero_p1", "Hrodna Grimfell", "thane", faction_army("frostmarch", 4, 2.5))
home = obj(d, "town_start_0")
home.update({"id": "town_grove_heart", "name": "The Heart Grove"})
obj(d, "town_start_1")["name"] = "Grimfell's Fire"
obj(d, "town_heart")["name"] = "Midmarch"
info = zone_info(d, labels)
GROVES = ["town_grove_heart"]
for zone, gid, gname in (("lane_a_0", "town_grove_west", "The West Grove"), ("lane_b_0", "town_grove_east", "The East Grove")):
    x, y = free_spot(d, *info[zone]["center"], clearance=2)
    d["objects"].append(town(gid, x, y, "thornwood", gname, 0, ["t_hall", "t_fort1", "t_dw1", "t_dw2"],
                             [["thorn_skulker", 30], ["barkhide_warden", 18], ["briar_huntress", 8]]))
    deco_pattern(d, x, y, "grove")
    GROVES.append(gid)
ENTRIES = {z: edge_entries(d, z, "n", labels) for z in ("lane_b_1", "start_1", "lane_a_1")}
finish(d, 2657)
HUNTERS_WAVES = []
for i, (day, zone, target, army) in enumerate([
        (6, "lane_b_1", "town_grove_west", [["clan_raider", 22], ["rimefang_hound", 8]]),
        (10, "lane_a_1", "town_grove_east", [["clan_raider", 28], ["rimefang_hound", 12], ["oathless_berserker", 5]]),
        (14, "start_1", "town_grove_heart", [["clan_raider", 34], ["rimefang_hound", 16], ["oathless_berserker", 9], ["tusk_rider", 3]]),
        (18, "lane_b_1", "town_grove_west", [["rimefang_hound", 26], ["oathless_berserker", 16], ["tusk_rider", 8]]),
        (18, "lane_a_1", "town_grove_east", [["clan_raider", 50], ["oathless_berserker", 14], ["tusk_rider", 6]]),
        (22, "start_1", "town_grove_heart", [["clan_raider", 60], ["rimefang_hound", 30], ["oathless_berserker", 20], ["tusk_rider", 10]])]):
    HUNTERS_WAVES.append({"id": "hunters_wave_%d" % i, "day": day, "warning_days": 3, "owner": 2,
        "spawn": ENTRIES[zone][0], "entry_tiles": ENTRIES[zone], "entry_name": "the northern edge",
        "target": target, "targets": [target, "town_grove_heart"], "order": "assault",
        "hero": {"id": "hunters_chief_%d" % i, "name": ["Hungry Raider", "Winter Hound-Master", "Starving Jarl", "Bone-Gnawer", "Snow-Eater", "The Last Hunt"][i],
                 "class": "reaver", "army": army}})


# --------------------------------------------------- chapter 5: the fen's edge (T)
# Out of the deep wood with no town. The Covenant comes down from the northern
# forest past forest hamlets (villages) to Mossgate, an empty grove-town; a
# burned strip of cinder and ash runs between the wood and the Hollow's fens in
# the south (Ysmay) and the west.
d = chapter("gen:random_l_3p_normal_normal_ring:2", "tw_fens_edge", "The Fen's Edge",
            "The Briar Oath chapter 5 (T, townless start). Frozen from gen:random_l_3p_normal_normal_ring:2 and tuned in tools/maps/build_briar_maps.py: the Covenant starts without a town in the northern wood with forest hamlets (villages) around it; Mossgate, a neutral grove-town, is the first prize; a burned strip divides the wood from the Hollow's fens in the south and west.")
labels = zone_map(d)
retheme(d, {".": "f"}, lambda x, y: y < 36)
retheme(d, {".": "i", "f": "i", "r": "d", "s": "d", "w": "i"}, lambda x, y: 38 <= y <= 46)
retheme(d, {".": "w", "s": "w"}, lambda x, y: y > 48)
faction_zone(d, "start_1", "hollow", labels)
faction_zone(d, "start_2", "hollow", labels)
to_slot(d, 2, 1)
set_players(d, [("The Thornwood Covenant", "thornwood", True), ("The Hollow Dominion", "hollow", False)])
set_hero(d, "hero_p1", "Ysmay of the Barrows", "necromancer", faction_army("hollow", 5, 3.0))
obj(d, "town_start_1")["name"] = "Fenmarrow"
obj(d, "town_start_2")["name"] = "The Drowned Chapel"
moss = obj(d, "town_start_0")
moss.update({"id": "town_mossgate", "name": "Mossgate", "town_type": "thornwood"})
# Tuned with tools/scenario_probe.gd townless_chapter campaign:briar_oath:4 town_mossgate:
# Cerrid alone wins 20%, the best army the gold buys 100% (29% losses).
TW_FENS_GARRISON = [["shambler", 60], ["marrow_archer", 36], ["gravecrawler", 17], ["wailing_shade", 7]]
make_townless(d, 0, "town_mossgate", "thornwood", 7500 + 2500, TW_FENS_GARRISON, villages=4, seed=5,
              guard=[[["carrion_flock", 10]], [["road_cutthroat", 10]], [["carrion_flock", 12]], [["thornwolf", 8]]])
finish(d, 3301)


# ------------------------------------------------------ chapter 7: the kindling (A)
# 2v2 on a four-realm hub: the Covenant (north) and Hrodna Grimfell's clan (west,
# allied) against Ithra Sootveil's brood (east) and Garsh Emberclaw's Kindlers (south).
d = chapter("gen:random_l_4p_normal_normal_hub:3", "tw_kindling", "The Kindling",
            "The Briar Oath chapter 7 (A, 2v2). Frozen from gen:random_l_4p_normal_normal_hub:3 and tuned in tools/maps/build_briar_maps.py: the Covenant (north) and Clan Grimfell (west, allied) against Sootveil's Brood (east) and the Kindlers (south).")
labels = zone_map(d)
faction_zone(d, "start_0", "thornwood", labels)
faction_zone(d, "start_2", "ashen", labels)
faction_zone(d, "start_3", "frostmarch", labels)
set_players(d, [("The Thornwood Covenant", "thornwood", True, 1), ("Sootveil's Brood", "ashen", False, 2),
                ("The Kindlers", "ashen", False, 2), ("Clan Grimfell", "frostmarch", False, 1)])
set_hero(d, "hero_p1", "Ithra Sootveil", "warlock", faction_army("ashen", 6, 3.0))
set_hero(d, "hero_p2", "Garsh Emberclaw", "warlord", faction_army("ashen", 6, 2.5))
set_hero(d, "hero_p3", "Hrodna Grimfell", "thane", faction_army("frostmarch", 6, 3.0))
obj(d, "town_start_0")["name"] = "Thornreach"
obj(d, "town_start_1")["name"] = "Sootveil's Pit"
obj(d, "town_start_2")["name"] = "The Kindling Yard"
obj(d, "town_start_3")["name"] = "Grimfell Steading"
finish(d, 4127)


# ---------------------------------------------------- chapter 8: the last grove (C)
# The Last Grove is the Covenant's only town, in a wide valley in the north-west;
# Morvath's Host comes from the south and the east, over the two ridges that
# close the valley (its two passes).
d = chapter("gen:random_xl_3p_normal_normal_hub:5", "tw_last_grove", "The Last Grove",
            "The Briar Oath chapter 8 (C). Frozen from gen:random_xl_3p_normal_normal_hub:5 and tuned in tools/maps/build_briar_maps.py: the Last Grove, the Covenant's only town, in a walled valley in the north-west with two passes; Morvath's Host holds the south and the east.")
labels = zone_map(d)
faction_zone(d, "start_0", "thornwood", labels)
faction_zone(d, "start_2", "ashen", labels)
to_slot(d, 2, 1)
set_players(d, [("The Thornwood Covenant", "thornwood", True), ("Morvath's Host", "ashen", False)])
set_hero(d, "hero_p1", "Morvath the Kindler", "tormentor", faction_army("ashen", 7, 4.0))
grove = obj(d, "town_start_0")
grove.update({"id": "town_last_grove", "name": "The Last Grove"})
landmark_near(d, grove["pos"][0] + 6, grove["pos"][1] - 6, "landmark_elder_grove")
obj(d, "town_start_1")["name"] = "The Burning Camp"
obj(d, "town_start_2")["name"] = "Cinder Ridge"
finish(d, 4789)


# --------------------------------------------------------- chapter 9: the seed (B)
# The Covenant (west) and the Greyhart Circle (north-east) carry the Mother
# east, to the Wound's edge on the eastern rim (a volcano set piece), against
# Garsh's Host in the south. Within 5 tiles of the Wound the circle turns.
d = chapter("gen:random_xl_3p_normal_normal_hub:3", "tw_seed", "The Seed",
            "The Briar Oath chapter 9 (B, betrayal). Frozen from gen:random_xl_3p_normal_normal_hub:3 and tuned in tools/maps/build_briar_maps.py: the Covenant (west) and its ally the Greyhart Circle (north-east) against the Host (south); the Wound's edge on the eastern rim, where the circle turns when a Covenant hero comes within 5 tiles.")
labels = zone_map(d)
faction_zone(d, "start_0", "thornwood", labels)
faction_zone(d, "start_2", "thornwood", labels)
set_players(d, [("The Thornwood Covenant", "thornwood", True, 1), ("The Host", "ashen", False, 2),
                ("The Greyhart Circle", "thornwood", False, 1)])
set_hero(d, "hero_p1", "Garsh Emberclaw", "warlord", faction_army("ashen", 8, 4.5))
set_hero(d, "hero_p2", "Elder Greyhart", "thornspeaker", faction_army("thornwood", 7, 3.5))
obj(d, "town_start_0")["name"] = "Seedwatch"
obj(d, "town_start_1")["name"] = "The Ember Gate"
obj(d, "town_start_2").update({"id": "town_greyhart", "name": "Greyhart Circle"})
WOUND = landmark_near(d, d["width"] - 8, 60, "landmark_cinder_volcano")
deco_pattern(d, WOUND[0] + 1, WOUND[1] + 1, "cinders")
WOUND_EDGE = free_tile_near(d, WOUND[0] - 2, WOUND[1] + 2, radius=5)
print("tw_seed wound", WOUND, "edge", WOUND_EDGE)
finish(d, 5413)


# ------------------------------------------------- campaign wiring (map fields)
COV_SLOT = {"type": "human", "faction": "thornwood", "name": "The Thornwood Covenant"}
wire_chapters("briar_oath", {
    "tw_smoke": {"map": "tw_smoke", "setup": {"players": [COV_SLOT, {"type": "computer", "faction": "concord", "name": "Ashcombe's Fire-Camp"}]}},
    "tw_ambush": {"map": "tw_ambush", "setup": {"players": [COV_SLOT, {"type": "computer", "faction": "concord", "name": "Thorne's Column"}]}},
    "tw_hunters": {"map": "tw_hunters",
        "setup": {"players": [dict(COV_SLOT, team=1), {"type": "computer", "faction": "frostmarch", "name": "Clan Grimfell", "team": 2},
                              {"type": "computer", "faction": "frostmarch", "name": "The Starving Clans", "team": 2}]},
        "scenario": {"name": "The Hunters", "player": 0, "protected_towns": GROVES, "invasion_players": [2],
            "max_active_invaders": 4, "random_events": False, "wave_strength": {"easy": 0.75, "normal": 1.0, "hard": 1.25},
            "objectives": [
                {"id": "groves", "type": "survive", "through_day": 24, "text": "Keep all three living groves through day 24"},
                {"id": "waves", "type": "clear_waves", "optional": True, "text": "Break every hunting party that comes down from the north"}],
            "waves": HUNTERS_WAVES}},
    "tw_fens_edge": {"map": "tw_fens_edge",
        "setup": {"players": [COV_SLOT, {"type": "computer", "faction": "hollow", "name": "The Hollow Dominion"}]},
        "scenario": {"name": "The Fen's Edge", "player": 0, "townless_players": [0], "objectives": [
            {"id": "take_town", "type": "control_towns", "towns": ["town_mossgate"], "text": "Take Mossgate"},
            {"id": "conquer", "type": "conquer", "text": "Burn the Hollow off the fen's edge"}]}},
    "tw_kindling": {"map": "tw_kindling",
        "setup": {"players": [dict(COV_SLOT, team=1), {"type": "computer", "faction": "ashen", "name": "Sootveil's Brood", "team": 2},
                              {"type": "computer", "faction": "ashen", "name": "The Kindlers", "team": 2},
                              {"type": "computer", "faction": "frostmarch", "name": "Clan Grimfell", "team": 1}]},
        "scenario": {"name": "The Kindling", "player": 0, "objectives": [
            {"id": "conquer", "type": "conquer", "text": "Put out Sootveil's Brood and the Kindlers"},
            {"id": "grimfell", "type": "ally_survives", "player": 3, "text": "Clan Grimfell must not fall"}]}},
    "tw_last_grove": {"map": "tw_last_grove", "setup": {"players": [COV_SLOT, {"type": "computer", "faction": "ashen", "name": "Morvath's Host"}]}},
    "tw_seed": {"map": "tw_seed",
        "setup": {"players": [dict(COV_SLOT, team=1), {"type": "computer", "faction": "ashen", "name": "The Host", "team": 2},
                              {"type": "computer", "faction": "thornwood", "name": "The Greyhart Circle", "team": 1}]},
        "scenario": {"name": "The Seed", "player": 0,
            "betrayal": {"player": 2, "joins": 1, "trigger": {"reach": {"pos": list(WOUND_EDGE), "radius": 5}},
                "text": "We swore never to plant it. We meant it.",
                "reinforcements": [["rootbinder", 14], ["gloomwing_strix", 8], ["spore_lobber", 4]]},
            "objectives": [
                {"id": "greyhart", "type": "ally_survives", "player": 2, "until_betrayal": True, "text": "Keep the Greyhart Circle with you"},
                {"id": "conquer", "type": "conquer", "text": "Clear the way to the Wound"}]}},
}, OUT)
