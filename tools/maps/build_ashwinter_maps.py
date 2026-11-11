"""Builds the maps of the Frostmarch campaign "The Ashwinter".

Hand-made: sun_goes_out (chapter 1) and granary_of_highmere (chapter 5). The
other eight chapters (map overhaul phase 3) start from frozen generator maps and
are hand-tuned below with tools/maps/frozen_chapters.py: slots and factions,
terrain per zone, town names, story landmarks and the scenario of the chapter
(stored in the map file). The builder also points the chapters in
data/campaigns.json at their maps (map and setup only; story text and casts stay).

Regenerate:  GODOT=<godot 4.5.1> python3 tools/maps/build_ashwinter_maps.py data/maps [map ids...]
(with ids, only those frozen chapters are rebuilt), then run ./run_tests.sh faction_campaigns.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
maps = {}

CLANS = player(0, "Clan Kettleborn", "frostmarch", human=True)

# ------------------------------------------------- chapter 1: the sun goes out
# Red snow on the high steppe. Kettlehall in the west, Grimfell in the east, the
# last herd grazing a frozen lake shore between them. Tier 2 for both sides.
g = Grid(24, 16, 's')
g.rect(0, 0, 23, 0, '^'); g.rect(0, 15, 23, 15, '^')
g.blob(11, 11, 2.2, '#')                  # the frozen-over lake, too thin to cross
g.blob(5, 3, 1.4, '^'); g.blob(18, 3, 1.4, '^'); g.blob(12, 3, 1.0, 'f')
g.blob(3, 12, 1.2, 'f'); g.blob(20, 12, 1.2, 'f')
maps["sun_goes_out"] = {
    "_doc": "The Ashwinter chapter 1. Hand-made (tools/maps/build_ashwinter_maps.py). Red snow on the high steppe: Clan Kettleborn's Kettlehall in the west, Clan Grimfell in the east, the last herd by a frozen lake between them. Both sides are capped at tier 2.",
    "id": "sun_goes_out", "name": "The Sun Goes Out", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(2, 7), (21, 7)]),
    "players": [CLANS, player(1, "Clan Grimfell", "frostmarch", color="#5a7a9a")],
    "heroes": [
        hero("hero_ulvra", "Ulvra Kettleborn", "thane", 0, 3, 7, [["clan_raider", 26], ["rimefang_hound", 8]]),
        hero("hero_bjarr", "Bjarr Coldhand", "reaver", 0, 3, 8, [["clan_raider", 16], ["rimefang_hound", 5]]),
        hero("hero_hrodna", "Hrodna Grimfell", "thane", 1, 20, 7, [["clan_raider", 24], ["rimefang_hound", 7]]),
    ],
    "objects": [
        town("town_kettlehall", 2, 7, "frostmarch", "Kettlehall", 0, ["r_hall", "r_tavern", "r_fort1", "r_dw1", "r_dw2"], [["clan_raider", 12]]),
        town("town_grimfell", 21, 7, "frostmarch", "Grimfell", 1, ["r_hall", "r_fort1", "r_dw1", "r_dw2"], [["clan_raider", 14], ["rimefang_hound", 3]]),
        mine("mine_wood", 3, 11, "wood"), mine("mine_ore", 7, 2, "ore"),
        mine("mine_gems", 16, 2, "gems", [["rime_wight", 4]]),
        res("res_gold_1", 6, 9, "gold", 500), res("res_gold_2", 11, 6, "gold", 750), res("res_gold_3", 15, 13, "gold", 1000),
        res("res_wood_1", 1, 13, "wood", 5), res("res_ore_1", 9, 2, "ore", 5), res("res_crystal_1", 22, 2, "crystal", 2),
        res("res_gold_4", 20, 10, "gold", 500),
        army("neutral_herd", 11, 7, "The last herd's drovers", [["steppe_centaur", 3]]),
        army("neutral_wolves", 7, 13, "Starving wolves", [["thornwolf", 10]]),
        army("neutral_harpies", 16, 9, "Harpies on the ice", [["shrieking_harpy", 6]]),
        enc("enc_column", 13, 4, "dispossessed_column"), enc("enc_cartographer", 8, 11, "blind_cartographer"),
        art("art_boots", 1, 1, "rimetread_boots"), art("art_dice", 22, 13, "bone_dice"),
    ],
}

# ---------------------------------------------- chapter 5: the granary of highmere
# A great raid. The clans come down from the snow in the north-west. Highmere,
# the Concord's richest store-city, sits behind its river in the south-east with
# two outlying granary towns. Tier 5 for both sides.
g = Grid(30, 22, '.')
g.rect(0, 1, 29, 5, 's'); g.rect(0, 1, 9, 20, 's')       # the snowline
g.rect(16, 8, 16, 20, '~'); g.rect(16, 8, 28, 8, '~')     # the Pale River around Highmere
g.blob(22, 3, 1.6, 'f'); g.blob(5, 14, 1.6, 'f'); g.blob(12, 16, 2.0, 'f')
g.blob(10, 9, 1.0, '^'); g.blob(26, 18, 1.2, '^'); g.blob(19, 4, 1.0, '^')
g.rect(0, 0, 29, 0, '^'); g.rect(0, 21, 29, 21, '^')
maps["granary_of_highmere"] = {
    "_doc": "The Ashwinter chapter 5. Hand-made (tools/maps/build_ashwinter_maps.py). The clans come down from the snow in the north-west; Highmere, the Concord's richest store-city, stands behind the Pale River in the south-east, with the granary towns of Harrowby and Millstead outside it. Both sides are capped at tier 5.",
    "id": "granary_of_highmere", "name": "The Granary of Highmere", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(3, 3), (3, 12), (25, 12), (25, 15)]) + roads([(13, 3), (13, 12)]) + roads([(13, 3), (26, 3)]),
    "players": [CLANS, player(1, "Highmere", "concord")],
    "heroes": [
        hero("hero_ulvra", "Ulvra Kettleborn", "thane", 0, 4, 3,
             [["clan_raider", 50], ["rimefang_hound", 20], ["oathless_berserker", 12], ["tusk_rider", 6], ["frost_shaman", 3]]),
        hero("hero_bjarr", "Bjarr Coldhand", "reaver", 0, 4, 4, [["clan_raider", 34], ["rimefang_hound", 14], ["oathless_berserker", 6]]),
        hero("hero_iska", "Seer Iska Rime", "frostcaller", 0, 3, 4, [["clan_raider", 26], ["rimefang_hound", 8], ["frost_shaman", 3]]),
        hero("hero_brack", "Castellan Odo Brack", "knight", 1, 23, 15,
             [["pike_militia", 50], ["longbowman", 24], ["shieldwarden", 12], ["lancer", 6], ["lightbearer", 4]]),
    ],
    "objects": [
        town("town_frostcamp", 3, 3, "frostmarch", "The Frost Camp", 0,
             ["r_hall", "r_tavern", "r_market", "r_fort1", "r_fort2", "r_dw1", "r_dw2", "r_dw3", "r_dw4"], [["clan_raider", 20]]),
        town("town_harrowby", 26, 3, "concord", "Harrowby", 1, ["c_hall", "c_market", "c_palisade", "c_dw1", "c_dw2"],
             [["pike_militia", 24], ["longbowman", 10]]),
        town("town_millstead", 13, 12, "concord", "Millstead", 1, ["c_hall", "c_palisade", "c_dw1", "c_dw2", "c_dw3"],
             [["pike_militia", 24], ["longbowman", 10], ["shieldwarden", 4]]),
        town("town_highmere", 25, 15, "concord", "Highmere", 1,
             ["c_hall", "c_court", "c_tavern", "c_market", "c_palisade", "c_keep", "c_dw1", "c_dw2", "c_dw3", "c_dw4", "c_dw5"],
             [["pike_militia", 40], ["longbowman", 18], ["shieldwarden", 10], ["lancer", 4]]),
        mine("mine_wood", 6, 8, "wood"), mine("mine_ore", 2, 17, "ore"),
        mine("mine_crystal", 8, 18, "crystal", [["frost_drake", 2]]),
        mine("mine_gold", 20, 11, "gold", [["deserter_crossbows", 14]]), mine("mine_gems", 27, 10, "gems"),
        res("res_gold_1", 7, 6, "gold", 750), res("res_gold_2", 12, 7, "gold", 1000), res("res_gold_3", 19, 6, "gold", 1500),
        res("res_gold_4", 22, 18, "gold", 2000), res("res_wood_1", 1, 10, "wood", 6), res("res_ore_1", 14, 18, "ore", 6),
        res("res_crystal_1", 28, 6, "crystal", 3), res("res_gems_1", 20, 15, "gems", 3), res("res_mercury_1", 10, 4, "mercury", 3),
        army("neutral_bridge", 16, 12, "Highmere's bridge guard", [["deserter_crossbows", 16], ["road_cutthroat", 12]]),
        army("neutral_snowline", 9, 12, "Rime wights", [["rime_wight", 12]]),
        army("neutral_north_road", 16, 3, "Hired centaurs", [["steppe_centaur", 8]]),
        enc("enc_company", 11, 14, "free_company_camp"), enc("enc_toll", 20, 3, "brigand_toll"), enc("enc_courier", 6, 11, "dying_courier"),
        art("art_greaves", 1, 19, "outriders_greaves"), art("art_seal", 28, 20, "quartermasters_seal"), art("art_flag", 18, 19, "surveyors_flag"),
    ],
}

# The layouts above are drawn on small grids; the maps are played larger
# (playtests, Nov 7: the campaign maps felt small, twice). See maplib.enlarge.
enlarge(maps, {"sun_goes_out": 2.5, "granary_of_highmere": 3.3})


# Map overhaul: the kept maps no longer run west to east, and get the terrain
# painter's patches and decoration instead of flat single-biome ground.
import frozen_chapters as fc
fc.rotate(maps["sun_goes_out"], clockwise=False)        # the clan comes up from the south
fc.rotate(maps["granary_of_highmere"], clockwise=True)

ONLY = sys.argv[2:]
if not ONLY:
    build(maps, OUT)
    if OUT:
        for mid, seed, plan in [("sun_goes_out", 2301, [("s", "r", 0.14), ("s", "f", 0.08)]),
                                ("granary_of_highmere", 2305, [("s", "r", 0.12), (".", "f", 0.18), (".", "s", 0.16), (".", "w", 0.05)])]:
            write(OUT, mid, fc.repaint_kept(maps[mid], seed, plan))


# ------------------------------------------------------------- frozen chapters
from frozen_chapters import army_of, scale

BUILDER = "tools/maps/build_ashwinter_maps.py"
HUMAN = {"type": "human", "faction": "frostmarch", "name": "Clan Kettleborn"}
CLOSED = {"type": "closed", "faction": "frostmarch"}
SNOW = [(fc.EVERYWHERE, fc.TO_SNOW)]


def ashen(name, **kw):
    return dict({"type": "computer", "faction": "ashen", "name": name}, **kw)


def _rename(d, old, new, name, cls=None):
    h = fc.obj(d, old)
    h["id"], h["name"] = new, name
    if cls:
        h["class"] = cls


def _one_hall(d, labels):
    # The Whaleroad cairn on the glacier by Orm's hall (the fish-folk campaign returns to it).
    p = fc.obj(d, "town_start_1")["pos"]
    fc.landmark_near(d, p[0] + 6, p[1] - 6, "landmark_frozen_cascade")


def _south(d, labels):
    # Greyhold's two granaries stand north of it; Whaleroad goes home once the
    # clans hold both.
    _rename(d, "hero_p2", "hero_orm", "Orm Whaleroad", "thane")
    grey = fc.obj(d, "town_start_1")["pos"]
    placed = []
    for tid, name in (("town_northmere_granary", "Northmere Granary"), ("town_hollin_granary", "Hollin Granary")):
        p = fc.spot(d, grey, 10, 26, labels=labels, margin=3, away=placed,
                    prefer=lambda x, y: (y - abs(x - grey[0]) // 3 + (99 if any(abs(x - q[0]) + abs(y - q[1]) < 12 for q in placed) else 0), x))
        fc.clear_near(d, p, 2)
        placed.append(tuple(p))
        d["objects"].append({"id": tid, "type": "town", "pos": p, "town_type": "concord", "name": name, "owner": 1})
    d["scenario"] = {
        "name": "South for Bread", "player": 0,
        "briefing": "Clan Whaleroad marches south with you for Greyhold's grain. Take the granaries north of Greyhold; mind who stands beside you when the bread is won.",
        "objectives": [
            {"id": "whaleroad_holds", "type": "ally_survives", "player": 2, "until_betrayal": True,
             "text": "Keep Clan Whaleroad in the field."},
            {"id": "granaries", "type": "control_towns", "towns": ["town_northmere_granary", "town_hollin_granary"],
             "text": "Hold both granaries north of Greyhold."},
            {"id": "after", "type": "conquer", "after_betrayal": True, "text": "Drive Greyhold and Clan Whaleroad from the field."}],
        "betrayal": {"player": 2, "joins": 1,
                     "trigger": {"towns_taken": {"towns": ["town_northmere_granary", "town_hollin_granary"], "count": 2}},
                     "text": "Whaleroad has its bread. Whaleroad goes home.",
                     "reinforcements": [["clan_raider", 30], ["oathless_berserker", 8]]}}


def _deer(d, labels):
    _rename(d, "hero_p2", "hero_corvin_mire", "Father Corvin Mire", "necromancer")
    d["scenario"] = {
        "name": "The Clans and the Dead", "player": 0,
        "briefing": "Corvin's dead march with the clans against the Covenant of the old wood. Break both Thornwood hosts and keep the dead in the field.",
        "objectives": [
            {"id": "break_wood", "type": "conquer", "text": "Break Neve's wardens and the Old Wood hunters."},
            {"id": "dead_hold", "type": "ally_survives", "player": 2, "text": "Corvin's Dead must survive."}]}


def _cold_bones(d, labels):
    # Cross the frozen fen from the north camp to the far (south) bank by day 20
    # with Iska; the cairn of the last verse stands on the ice halfway.
    lead = fc.obj(d, "hero_p0")["pos"]
    # Iska comes with the campaign cast; the map names her too so the mission's
    # objectives validate on their own (the cast replaces this entry).
    d["heroes"].append({"id": "hero_iska", "name": "Seer Iska Rime", "class": "frostcaller", "owner": 0,
                        "pos": list(fc.free_tile_near(d, *lead)), "army": [["clan_raider", 20], ["rimefang_hound", 8]]})
    corvin = fc.obj(d, "town_start_1")["pos"]
    bank = fc.spot(d, corvin, 8, 22, zone="start_1", labels=labels, margin=2,
                   prefer=lambda x, y: (-y, abs(x - corvin[0]), x))
    cairn_at = fc.spot(d, fc.obj(d, "town_start_0")["pos"], 26, 40, labels=labels, margin=2,
                       prefer=lambda x, y: (abs(x - d["width"] // 2) + abs(y - d["height"] // 2), y, x))
    fc.clear_near(d, cairn_at, 1)
    d["objects"].append({"id": "site_last_verse", "type": "site", "site": "oathstone", "pos": cairn_at})
    d["scenario"] = {
        "name": "Cold Bones", "player": 0, "deadline_day": 20, "required_heroes": ["hero_iska"],
        "briefing": "The ice will break after day 20. Bring Seer Iska across the frozen fen to the far bank before it does; the dead walk the ice.",
        "objectives": [
            {"id": "far_bank", "type": "reach", "hero": "hero_iska", "pos": bank, "text": "Bring Iska to the far bank by day 20."},
            {"id": "last_verse", "type": "reach", "hero": "hero_iska", "pos": cairn_at, "optional": True, "unlock_day": 8,
             "text": "Read the last verse at the cairn on the ice."}]}


def _source(d, labels):
    stock = [scale(army_of("frostmarch", c), 2.4) for c in ([0, 0, 10], [0, 12, 0], [20, 0, 6], [0, 0, 9])]
    fc.make_townless(d, labels, stock, guard=[["cave_stalker", 6]],
                     garrison=scale(army_of("ashen", [40, 14, 9, 4, 2, 1]), 2.2))
    d["scenario"] = {
        "name": "At the Source", "player": 0, "townless_players": [0],
        "briefing": "No hall stands this far south. Raise the clan steadings, take Frostwatch back and break Ithra's kilns at the Wound's flank.",
        "objectives": [{"id": "kilns", "type": "control_towns", "towns": ["town_start_1"], "text": "Take Ithra's Kilns."}]}


def _wyrm(d, labels):
    p = fc.heart(d)
    fc.landmark_near(d, p[0] + 5, p[1] - 5, "landmark_frozen_cascade")


def _winter(d, labels):
    fc.place_heroes(d, [
        {"id": "hero_ulvra", "name": "Ulvra Kettleborn", "class": "thane", "owner": 0, "army": [["clan_raider", 90], ["rimefang_hound", 36], ["oathless_berserker", 22], ["tusk_rider", 12], ["frost_shaman", 6], ["rimeback_aurochs", 4], ["cairn_giant", 2], ["winter_wyrm", 1]]},
        {"id": "hero_bjarr", "name": "Bjarr Coldhand", "class": "reaver", "owner": 0, "army": [["clan_raider", 60], ["rimefang_hound", 24], ["oathless_berserker", 14], ["tusk_rider", 6], ["rimeback_aurochs", 2]]},
        {"id": "hero_iska", "name": "Seer Iska Rime", "class": "frostcaller", "owner": 0, "army": [["clan_raider", 44], ["rimefang_hound", 18], ["frost_shaman", 6], ["cairn_giant", 1]]},
        {"id": "hero_morvath", "name": "Morvath the Kindler", "class": "tormentor", "owner": 1, "army": [["cinderling", 90], ["scorchhound", 34], ["brimstone_hurler", 22], ["flayer", 12], ["ash_witch", 8], ["gorgewing", 4], ["pyre_titan", 1], ["cinder_maw", 1]]},
        {"id": "hero_vrask", "name": "Vrask the Twice-Eaten", "class": "warlord", "owner": 2, "army": [["cinderling", 70], ["scorchhound", 26], ["brimstone_hurler", 16], ["flayer", 10], ["ash_witch", 5], ["gorgewing", 3], ["pyre_titan", 1]]}])
    p = fc.heart(d)
    fc.landmark_near(d, p[0] + 5, p[1] + 5, "landmark_cinder_volcano")


CHAPTERS = [
    {"id": "fm_one_hall", "name": "One Hall", "chapter": "fm_one_hall",
     "source": "gen:random_xl_2p_normal_normal_diagonal:6", "dress_seed": 2302,
     "doc": "The Ashwinter chapter 2 (layout L): corner to corner across the snow; Thane Orm Whaleroad's hall in the far corner, the clan's cairn on the glacier beside it.",
     "players": [HUMAN, {"type": "computer", "faction": "frostmarch", "name": "Clan Whaleroad"}],
     "themes": SNOW, "towns": {"town_start_0": "Kettleborn Hall", "town_start_1": "Whaleroad Hall", "town_heart": "Thingstead"},
     "edit": _one_hall},
    {"id": "fm_south", "name": "South", "chapter": "fm_south",
     "source": "gen:random_xl_3p_normal_normal_ring:11", "dress_seed": 2303,
     "doc": "The Ashwinter chapter 3 (betrayal): the clans and Clan Whaleroad (slot 2) march south against Greyhold (slot 1); Whaleroad turns when the clans hold both granaries north of Greyhold.",
     "players": [dict(HUMAN, team=1), {"type": "computer", "faction": "concord", "name": "Greyhold", "team": 2},
                 {"type": "computer", "faction": "frostmarch", "name": "Clan Whaleroad", "team": 1}],
     "themes": SNOW + [(fc.nearer(1), fc.TO_GREEN)],
     "towns": {"town_start_0": "Kettleborn March Camp", "town_start_1": "Greyhold", "town_start_2": "Whaleroad Camp"},
     "edit": _south},
    {"id": "fm_iron_pass", "name": "The Iron Pass", "chapter": "fm_iron_pass",
     "source": "gen:random_xl_3p_normal_normal_hub:12", "dress_seed": 2304,
     "doc": "The Ashwinter chapter 4 (conquest): the high pass, snow and rock; Dask Vell's Forge watch holds the gate; the third realm is a neutral clan hold.",
     "players": [HUMAN, {"type": "computer", "faction": "forge", "name": "Vell's Iron Watch"}, CLOSED],
     "themes": [(fc.EVERYWHERE, fc.TO_HIGH_SNOW), (fc.nearer(1), fc.TO_ROCK)],
     "neutral_towns": {"town_start_2": ("frostmarch", [24, 10, 4])},
     "towns": {"town_start_0": "Pass Camp", "town_start_1": "The Iron Gatehold", "town_start_2": "Rimeford", "town_heart": "The Iron Pass"}},
    {"id": "fm_deer", "name": "The Deer and the Dead", "chapter": "fm_deer",
     "source": "gen:random_xl_4p_normal_normal_ring:5", "dress_seed": 2306, "order": {1: 2, 2: 1},
     "doc": "The Ashwinter chapter 6 (2v2): the clans and Corvin's dead (slot 2) against Neve's Thornwood wardens (slot 1) and the Old Wood hunters (slot 3); forest under snow.",
     "players": [dict(HUMAN, team=1), {"type": "computer", "faction": "thornwood", "name": "Neve's Wardens", "team": 2},
                 {"type": "computer", "faction": "hollow", "name": "Corvin's Dead", "team": 1},
                 {"type": "computer", "faction": "thornwood", "name": "The Old Wood Hunters", "team": 2}],
     "themes": [(fc.EVERYWHERE, fc.TO_SNOW_WOOD), (fc.nearer(2), {"s": "w"})],
     "towns": {"town_start_0": "Kettleborn Camp", "town_start_1": "Neve's Grove", "town_start_2": "Corvin's Barrow", "town_start_3": "Hunters' Lodge", "town_heart": "The White Stag"},
     "edit": _deer},
    {"id": "fm_cold_bones", "name": "Cold Bones", "chapter": "fm_cold_bones",
     "source": "gen:random_xl_2p_normal_normal_lanes:4", "dress_seed": 2307,
     "doc": "The Ashwinter chapter 7 (mission): cross the frozen fen north to south with Iska by day 20; the dead (slot 1) hold the far bank; the cairn of the last verse is an optional goal.",
     "players": [HUMAN, {"type": "computer", "faction": "hollow", "name": "The Dead on the Ice"}],
     "themes": [(fc.EVERYWHERE, fc.TO_FROZEN_FEN)],
     "towns": {"town_start_0": "Northbank Camp", "town_start_1": "Corvin's Fen"},
     "edit": _cold_bones},
    {"id": "fm_source", "name": "The Source", "chapter": "fm_source",
     "source": "gen:random_xl_3p_normal_normal_ring:8", "dress_seed": 2308,
     "doc": "The Ashwinter chapter 8 (townless start): no town at the Wound's flank; clan steadings (villages) sell warriors; Ithra's Ashen hold the kilns; a black band where snow meets ash.",
     "players": [HUMAN, ashen("Ithra's Kilns"), CLOSED],
     "themes": SNOW + [(fc.nearer(1), fc.TO_ASH_ON_SNOW), (fc.border(0, 1, 2.5), {"s": "r", "i": "r", ".": "r", "f": "r", "w": "r", "d": "r"})],
     "neutral_towns": {"town_start_2": ("frostmarch", [30, 12, 6, 3])},
     "towns": {"town_start_0": "Frostwatch", "town_start_1": "Ithra's Kilns", "town_start_2": "Ashbank"},
     "edit": _source},
    {"id": "fm_wyrm", "name": "The Wyrm", "chapter": "fm_wyrm",
     "source": "gen:random_xl_3p_normal_normal_hub:7", "dress_seed": 2309,
     "doc": "The Ashwinter chapter 9 (conquest): the Ancient Glacier; Garsh's brood holds the far end; the frozen cascade marks the wyrm's cairn in the heart.",
     "players": [HUMAN, ashen("Garsh's Brood"), CLOSED],
     "themes": [(fc.EVERYWHERE, fc.TO_HIGH_SNOW), (fc.nearer(1), fc.TO_ASH_ON_SNOW)],
     "neutral_towns": {"town_start_2": ("frostmarch", [40, 16, 8, 4, 2])},
     "towns": {"town_start_0": "Glacier Camp", "town_start_1": "The Brood Pits", "town_start_2": "Rimewall", "town_heart": "The Wyrm's Cairn"},
     "edit": _wyrm},
    {"id": "bring_the_winter", "name": "Bring the Winter", "chapter": "fm_bring_winter",
     "source": "gen:random_xl_3p_normal_normal_ring:9", "dress_seed": 2310,
     "doc": "The Ashwinter chapter 10, one against two: the clans march the Ashwinter south to the Wound, held by two Ashen broods, allied computer players (team 1) at the easy difficulty.",
     "players": [HUMAN, ashen("The Wound-Keepers", team=1, difficulty="easy"), ashen("The Deep Broods", team=1, difficulty="easy")],
     "themes": [(fc.EVERYWHERE, fc.TO_ASH), (fc.nearer(0), fc.TO_SNOW)],
     "towns": {"town_start_0": "Last Hearth", "town_start_1": "The Wound's Lip", "town_start_2": "The Deep Broods", "town_heart": "The Wound"},
     "edit": _winter},
]


def build_frozen(out):
    import maplib
    done = {}
    for spec in CHAPTERS:
        if ONLY and spec["id"] not in ONLY:
            continue
        spec["builder"] = BUILDER
        d = fc.chapter(spec)
        if out:
            maplib.write(out, spec["id"], d)
        done[spec["chapter"]] = {"map": spec["id"], "setup": fc.setup_players(spec)}
        print("built", spec["id"], d["width"], "x", d["height"])
    if out and done:
        fc.update_campaign("ashwinter", done)


build_frozen(OUT)
