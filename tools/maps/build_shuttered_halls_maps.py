"""Builds the maps of the Forge campaign "The Shuttered Halls".

Hand-made: deep_shift (chapter 1) and fallen_hold (chapter 6). The other eight
chapters (map overhaul phase 3) start from frozen generator maps and are
hand-tuned below with tools/maps/frozen_chapters.py: slots and factions, terrain
per zone, town names, story landmarks and the scenario of the chapter (stored in
the map file). The builder also points the chapters in data/campaigns.json at
their maps (map and setup only; story text and casts stay as they are).

Regenerate:  GODOT=<godot 4.5.1> python3 tools/maps/build_shuttered_halls_maps.py data/maps [map ids...]
(with ids, only those frozen chapters are rebuilt), then run ./run_tests.sh faction_campaigns.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
maps = {}

FORGE = player(0, "The Sunken Forge", "forge", human=True)

# ------------------------------------------------- chapter 1: deep shift
# Under the mountain. Stonevow Hold in the west, the lowest shafts in the east
# where the dead have dug in. Galleries of rough ground cut through solid rock,
# three levels joined by two stairs. Tier 2 for both sides.
g = Grid(24, 16, '^')
g.rect(1, 2, 22, 3, 'r'); g.rect(1, 7, 22, 8, 'r'); g.rect(1, 12, 22, 13, 'r')   # three galleries
g.rect(1, 2, 5, 13, 'r')                  # the hold's great stair
g.rect(18, 2, 22, 13, 'r')                # the shafts
g.rect(11, 4, 12, 6, 'r'); g.rect(8, 9, 9, 11, 'r'); g.rect(15, 9, 16, 11, 'r')    # cross-cuts
g.blob(3, 8, 1.2, '.'); g.blob(20, 8, 1.2, 'w')
maps["deep_shift"] = {
    "_doc": "The Shuttered Halls chapter 1. Hand-made (tools/maps/build_shuttered_halls_maps.py). Under the mountain: Stonevow Hold's great stair in the west, three mine galleries, and the lowest shafts in the east where the dead have dug in. Both sides are capped at tier 2.",
    "id": "deep_shift", "name": "Deep Shift", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(2, 8), (21, 8)]),
    "players": [FORGE, player(1, "The Risen Shafts", "hollow")],
    "heroes": [
        hero("hero_gunnra", "Gunnra Sootmantle", "runesmith", 0, 3, 8, [["forge_thrall", 26], ["rivet_crossbowman", 10]]),
        hero("hero_dask", "Dask Vell", "ironmarshal", 0, 3, 7, [["forge_thrall", 16], ["rivet_crossbowman", 6]]),
        hero("hero_lisk", "Abbot Lisk", "necromancer", 1, 20, 7, [["shambler", 30], ["marrow_archer", 8]]),
    ],
    "objects": [
        town("town_stonevow", 2, 8, "forge", "Stonevow Hold", 0, ["f_hall", "f_tavern", "f_fort1", "f_dw1", "f_dw2"], [["forge_thrall", 12]]),
        town("town_lower_shafts", 21, 8, "hollow", "The Lower Shafts", 1, ["h_hall", "h_fort1", "h_dw1", "h_dw2"], [["shambler", 16], ["marrow_archer", 4]]),
        mine("mine_ore", 4, 3, "ore"), mine("mine_wood", 4, 12, "wood"),
        mine("mine_crystal", 14, 2, "crystal", [["cave_stalker", 3]]),
        res("res_gold_1", 7, 2, "gold", 500), res("res_gold_2", 10, 13, "gold", 750), res("res_gold_3", 16, 7, "gold", 1000),
        res("res_ore_1", 9, 8, "ore", 5), res("res_wood_1", 2, 13, "wood", 5), res("res_mercury_1", 12, 5, "mercury", 3),
        res("res_gems_1", 21, 13, "gems", 2),
        army("neutral_middle", 12, 8, "Shambling miners", [["shambler", 16]]),
        army("neutral_upper", 17, 3, "Tomb scarabs", [["tomb_scarabs", 8]]),
        army("neutral_lower", 17, 12, "Plague rats", [["plague_rats", 14]]),
        enc("enc_echoes", 9, 3, "hall_of_echoes"), enc("enc_barrows", 15, 13, "barrow_field"),
        art("art_boots", 1, 2, "hobnailed_boots"), art("art_hauberk", 22, 2, "riveted_hauberk"),
    ],
}

# ---------------------------------------------- chapter 6: the fallen hold
# Kharrak Hold, a Forge town, has fallen to the Host and its gates stand open.
# The Forge comes down the valley from the north-west; Master Tobbin Greave holds
# out in his workshop in the south-west. The Ashen have their own camp at the
# Wound's mouth in the east. Tier 5 for both sides.
g = Grid(28, 20, 'r')
g.rect(0, 1, 3, 18, '^'); g.rect(24, 1, 27, 18, 'i')
g.rect(4, 1, 23, 2, '^'); g.rect(4, 17, 23, 18, '^')
g.blob(14, 10, 2.5, '.')                  # the hold's forecourt
g.rect(10, 5, 18, 5, '^'); g.rect(10, 15, 18, 15, '^')
g.rect(10, 6, 10, 8, '^'); g.rect(18, 12, 18, 14, '^')
g.rect(24, 8, 27, 12, 'i')
g.blob(7, 13, 1.0, '^'); g.blob(21, 7, 1.0, '^')
g.rect(0, 0, 27, 0, '^'); g.rect(0, 19, 27, 19, '^')
g.set(4, 4, 'r'); g.rect(4, 3, 9, 4, 'r')
maps["fallen_hold"] = {
    "_doc": "The Shuttered Halls chapter 6. Hand-made (tools/maps/build_shuttered_halls_maps.py). Kharrak Hold has fallen to the Ashen and stands in the middle of the valley; the Forge comes from the north-west, Master Tobbin Greave holds his workshop in the south-west and the Host has a camp at the Wound's mouth in the east. Both sides are capped at tier 5.",
    "id": "fallen_hold", "name": "The Fallen Hold", "width": g.w, "height": g.h, "terrain": g.rows(),
    "roads": roads([(5, 4), (5, 10), (25, 10)]) + roads([(5, 10), (5, 15)]),
    "players": [FORGE, player(1, "The Host at Kharrak", "ashen")],
    "heroes": [
        hero("hero_gunnra", "Gunnra Sootmantle", "runesmith", 0, 6, 4,
             [["forge_thrall", 44], ["rivet_crossbowman", 20], ["anvil_guard", 10], ["slag_golem", 4], ["cinder_engineer", 2]]),
        hero("hero_dask", "Dask Vell", "ironmarshal", 0, 7, 4, [["forge_thrall", 30], ["rivet_crossbowman", 12], ["anvil_guard", 6]]),
        hero("hero_tobbin", "Master Tobbin Greave", "artificer", 0, 6, 15, [["forge_thrall", 20], ["rivet_crossbowman", 10], ["cinder_engineer", 2]]),
        hero("hero_garsh", "Garsh Emberclaw", "warlord", 1, 16, 10,
             [["cinderling", 64], ["scorchhound", 24], ["brimstone_hurler", 12], ["flayer", 6], ["ash_witch", 3]]),
    ],
    "objects": [
        town("town_gate_watch", 5, 4, "forge", "The Gate Watch", 0, ["f_hall", "f_tavern", "f_market", "f_fort1", "f_dw1", "f_dw2", "f_dw3"],
             [["forge_thrall", 20]]),
        town("town_greaves_workshop", 5, 15, "forge", "Greave's Workshop", 0, ["f_hall", "f_market", "f_dw1", "f_dw2", "f_dw5"], [["forge_thrall", 12]]),
        town("town_kharrak", 14, 10, "forge", "Kharrak Hold", 1,
             ["f_hall", "f_tavern", "f_market", "f_fort1", "f_fort2", "f_dw1", "f_dw2", "f_dw3", "f_dw4"],
             [["cinderling", 30], ["scorchhound", 12], ["brimstone_hurler", 6]]),
        town("town_wound_camp", 25, 10, "ashen", "The Wound Camp", 1,
             ["a_hall", "a_den", "a_trench", "a_dw1", "a_dw2", "a_dw3"], [["cinderling", 24], ["scorchhound", 8]]),
        mine("mine_ore", 8, 7, "ore"), mine("mine_wood", 9, 13, "wood"),
        mine("mine_gold", 14, 3, "gold", [["ruin_sentinel", 4]]), mine("mine_crystal", 14, 16, "crystal", [["cave_stalker", 6]]),
        mine("mine_sulfur", 22, 4, "sulfur"), mine("mine_gems", 22, 15, "gems"),
        res("res_gold_1", 9, 10, "gold", 750), res("res_gold_2", 12, 4, "gold", 1000), res("res_gold_3", 20, 12, "gold", 1500),
        res("res_ore_1", 4, 8, "ore", 6), res("res_wood_1", 4, 12, "wood", 6), res("res_mercury_1", 12, 16, "mercury", 3),
        res("res_crystal_1", 19, 3, "crystal", 3), res("res_sulfur_1", 26, 2, "sulfur", 3),
        army("neutral_forecourt", 11, 10, "Cinder wraiths in the gate", [["cinder_wraith", 5]]),
        army("neutral_north", 19, 8, "Basilisks", [["ashscale_basilisk", 6]]),
        army("neutral_south", 9, 16, "Cave stalkers", [["cave_stalker", 8]]),
        enc("enc_echoes", 17, 4, "hall_of_echoes"), enc("enc_rift", 21, 16, "ember_rift"),
        art("art_wardstone", 20, 10, "wardstone_mail"), art("art_seal", 4, 3, "quartermasters_seal"),
    ],
}

# The layouts above are drawn on small grids; the maps are played larger
# (playtests, Nov 7: the campaign maps felt small, twice). See maplib.enlarge.
enlarge(maps, {"deep_shift": 2.5, "fallen_hold": 3.4})

# Chapter 1 story piece: the uncut stair, a run of rough-hewn steps going down
# down the bottom of the shafts to the unbroken rock (decoration only).
maps["deep_shift"]["decorations"] = [{"pos": [x, y], "kind": k} for x, y, k in [
    (55, 29, "boulders"), (56, 30, "obsidian"), (55, 31, "boulders"), (56, 32, "obsidian"), (55, 33, "boulders"), (56, 34, "obsidian")]]


# Map overhaul: the kept maps no longer run west to east, and get the terrain
# painter's patches and decoration instead of flat single-biome ground.
import frozen_chapters as fc
fc.rotate(maps["deep_shift"], clockwise=True)      # Stonevow in the north, the shafts below
fc.rotate(maps["fallen_hold"], clockwise=False)    # the Forge comes up from the south-west

ONLY = sys.argv[2:]
if not ONLY:
    build(maps, OUT)
    if OUT:
        for mid, seed, plan in [("deep_shift", 1301, [("r", "d", 0.14), ("r", "w", 0.06)]),
                                ("fallen_hold", 1306, [("r", "d", 0.12), ("r", "i", 0.06), (".", "r", 0.2)])]:
            write(OUT, mid, fc.repaint_kept(maps[mid], seed, plan))


# ------------------------------------------------------------- frozen chapters
from frozen_chapters import army_of, scale

BUILDER = "tools/maps/build_shuttered_halls_maps.py"
HUMAN = {"type": "human", "faction": "forge", "name": "The Sunken Forge"}
ROCK = [(fc.EVERYWHERE, fc.TO_ORE), (fc.nearer(0), fc.TO_ROCK)]


def ashen(name, **kw):
    return dict({"type": "computer", "faction": "ashen", "name": name}, **kw)


def _iron_market(d, labels):
    # The raiders hold the market town in the middle as well as their hall:
    # the clan turns when either falls.
    heart = fc.obj(d, "town_heart")
    heart["owner"] = 1
    d["scenario"] = {
        "name": "Iron for Bread", "player": 0,
        "briefing": "Clan Whaleroad trades bread for Forge iron and marches with you against the Kettleborn Raiders. Keep the clan in the field; it will not stay true for ever.",
        "objectives": [
            {"id": "whaleroad_holds", "type": "ally_survives", "player": 2, "until_betrayal": True,
             "text": "Keep Clan Whaleroad in the field."},
            {"id": "break_them", "type": "conquer", "after_betrayal": True,
             "text": "Break the Kettleborn Raiders and Clan Whaleroad."}],
        "betrayal": {"player": 2, "joins": 1,
                     "trigger": {"day": 16, "towns_taken": {"towns": ["town_start_1", "town_heart"], "count": 1}},
                     "text": "Whaleroad remembers who was cold first.",
                     "reinforcements": [["oathless_berserker", 12], ["tusk_rider", 6]]}}


def _heat(d, labels):
    # Survival: the Deepest Hall must hold through day 21 while Garsh's burrowers
    # break through the floor at two holes inside the halls, not at the edge.
    # The hall's own watch holds the gate against the first breach.
    fc.obj(d, "town_start_0")["garrison"] = army_of("forge", [30, 12, 6])
    hall = fc.obj(d, "town_start_0")["pos"]
    garsh = fc.obj(d, "town_start_1")["pos"]
    d["players"].append({"id": 2, "name": "The Burrowing Host", "faction": "ashen", "color": "#d9772b", "is_human": False})
    holes = []
    for zone in ("valley_0", "spoke_0"):
        try:
            p = fc.spot(d, hall, 16, 32, zone=zone, labels=labels, away=holes, margin=2)
        except ValueError:
            p = fc.spot(d, hall, 16, 32, labels=labels, away=holes, margin=2,
                        prefer=lambda x, y: (-min([abs(x - q[0]) + abs(y - q[1]) for q in holes] or [0]), y, x))
        holes.append(tuple(p))
    fc.landmark_near(d, holes[0][0] + 2, holes[0][1] + 2, "landmark_cinder_volcano")
    names = ["the Cinder Hole", "the Deep Breach"]
    armies = [[30, 10], [40, 14, 8], [50, 18, 12, 5], [60, 22, 16, 8, 4], [80, 28, 20, 10, 6]]
    leaders = ["Burrow-Scout Ktha", "Tunnel-Mother Vey", "The Slag Gnawer", "Firecrawler Oss", "The Last Burrower"]
    d["scenario"] = {
        "name": "The Heat Below", "mode": "survival", "player": 0,
        "briefing": "The floor of the Deepest Hall is cracking. Hold the hall until the masons seal it after day 22.",
        "protected_towns": ["town_start_0"], "invasion_players": [2], "max_active_invaders": 3,
        "wave_strength": {"easy": 0.75, "normal": 1.0, "hard": 1.25},
        "objectives": [{"id": "hold", "type": "survive", "through_day": 22, "text": "Hold the Deepest Hall through day 22."}],
        "waves": [fc.wave(i, 5 + 4 * i, holes[i % 2], "town_start_0", leaders[i], "warlord",
                          army_of("ashen", armies[i]), names[i % 2]) for i in range(5)]}
    del garsh


def _wardens_keep(d, labels):
    stock = [scale(army_of("forge", c), 3.0) for c in ([22, 0, 6], [0, 9, 0], [18, 6, 0], [0, 0, 7])]
    fc.make_townless(d, labels, stock, guard=[["cave_stalker", 6]],
                     garrison=scale(army_of("ashen", [40, 14, 9, 4, 2, 1]), 1.9))
    keep = fc.obj(d, "town_start_1")["pos"]
    fc.landmark_near(d, keep[0] + 4, keep[1] + 4, "landmark_shattered_citadel")
    d["scenario"] = {
        "name": "The Wardens' Keep", "player": 0, "townless_players": [0],
        "briefing": "No hall stands behind you. Raise companies at the old watch-posts, take back Karn Watch if you can, and march on the Wardens' Keep.",
        "objectives": [{"id": "keep", "type": "control_towns", "towns": ["town_start_1"], "text": "Take the Wardens' Keep."}]}


def _engine(d, labels):
    d["scenario"] = {
        "name": "The Engine", "player": 0,
        "briefing": "Wren's Concord column marches beside the Forge to pay its debt. Bring both Ashen hosts down and keep the column alive.",
        "objectives": [
            {"id": "break_hosts", "type": "conquer", "text": "Break Morvath's host and Vrask's brood."},
            {"id": "column_lives", "type": "ally_survives", "player": 2, "text": "Wren's Column must survive."}]}


def _worldforge(d, labels):
    fc.place_heroes(d, [
        {"id": "hero_gunnra", "name": "Gunnra Sootmantle", "class": "runesmith", "owner": 0, "army": [["forge_thrall", 80], ["rivet_crossbowman", 36], ["anvil_guard", 20], ["slag_golem", 10], ["cinder_engineer", 6], ["ironhoof_charger", 4], ["thunder_bombard", 2], ["molten_engine", 1]]},
        {"id": "hero_dask", "name": "Dask Vell", "class": "ironmarshal", "owner": 0, "army": [["forge_thrall", 50], ["rivet_crossbowman", 20], ["anvil_guard", 12], ["ironhoof_charger", 3]]},
        {"id": "hero_tobbin", "name": "Master Tobbin Greave", "class": "artificer", "owner": 0, "army": [["forge_thrall", 40], ["rivet_crossbowman", 18], ["slag_golem", 6], ["cinder_engineer", 4], ["thunder_bombard", 1]]},
        {"id": "hero_skarn", "name": "Skarn Ashborn", "class": "warlord", "owner": 1, "army": [["cinderling", 90], ["scorchhound", 34], ["brimstone_hurler", 22], ["flayer", 12], ["ash_witch", 8], ["gorgewing", 4], ["pyre_titan", 1], ["cinder_maw", 1]]},
        {"id": "hero_ysmay", "name": "Ysmay Vane", "class": "necromancer", "owner": 2, "army": [["shambler", 100], ["marrow_archer", 40], ["gravecrawler", 18], ["wailing_shade", 10], ["corpse_weaver", 6], ["gibbet_knight", 4], ["charnel_hulk", 1]]}])
    for slot in (1, 2):
        p = fc.obj(d, "town_start_%d" % slot)["pos"]
        fc.landmark_near(d, p[0] + 5, p[1] + 5, ["landmark_cinder_volcano", "landmark_shattered_citadel"][slot - 1])


CLOSED = {"type": "closed", "faction": "forge"}

CHAPTERS = [
    {"id": "fg_bones", "name": "Bones in the Seams", "chapter": "fg_bones",
     "source": "gen:random_xl_2p_normal_normal_tree:13", "dress_seed": 1302,
     "doc": "The Shuttered Halls chapter 2 (layout L): the seams below Stonevow, branching galleries with deep dead ends; Abbot Lisk's dead hold the far shafts.",
     "players": [HUMAN, {"type": "computer", "faction": "hollow", "name": "The Dead of the Seams"}],
     "themes": ROCK + [(fc.nearer(1), fc.TO_DEAD)],
     "towns": {"town_start_0": "Stonevow Hold", "town_start_1": "The Lower Shafts"}},
    {"id": "fg_debtors", "name": "The Debtors' Gate", "chapter": "fg_debtors",
     "source": "gen:random_xl_3p_normal_normal_hub:4", "dress_seed": 1303,
     "doc": "The Shuttered Halls chapter 3 (conquest): Wren's Concord camps at the gates of the Forge; the third realm of the map is a neutral hold.",
     "players": [HUMAN, {"type": "computer", "faction": "concord", "name": "Wren's Creditors"}, CLOSED],
     "themes": ROCK + [(fc.nearer(1), fc.TO_GREEN)],
     "towns": {"town_start_0": "Stonevow Gate", "town_start_1": "The Toll Camp", "town_start_2": "Copperdeep", "town_heart": "Tollhall"}},
    {"id": "fg_iron_bread", "name": "Iron for Bread", "chapter": "fg_iron_bread",
     "source": "gen:random_xl_3p_normal_normal_ring:2", "dress_seed": 1304,
     "doc": "The Shuttered Halls chapter 4 (betrayal): high passes, snow on rock. Clan Whaleroad (slot 2) marches with the Forge against the Kettleborn Raiders (slot 1) and turns on day 16 or when a raider town falls.",
     "players": [dict(HUMAN, team=1), {"type": "computer", "faction": "frostmarch", "name": "The Kettleborn Raiders", "team": 2},
                 {"type": "computer", "faction": "frostmarch", "name": "Clan Whaleroad", "team": 1}],
     "themes": [(fc.EVERYWHERE, fc.TO_HIGH_SNOW), (fc.nearer(0), {"s": "r", "f": "r"})],
     "towns": {"town_start_0": "Stonevow High Gate", "town_start_1": "Kettle Hall", "town_start_2": "Whaleroad Steading", "town_heart": "The Iron Market"},
     "edit": _iron_market},
    {"id": "fg_heat", "name": "The Heat Below", "chapter": "fg_heat",
     "source": "gen:random_xl_2p_normal_normal_hub:5", "dress_seed": 1305,
     "doc": "The Shuttered Halls chapter 5 (survival): hold the Deepest Hall through day 22; Ashen burrowers break through two holes inside the halls (invasion slot 2) while Garsh's burrow (slot 1) fights on.",
     "players": [HUMAN, ashen("Garsh's Burrow")],
     "themes": ROCK + [(fc.nearer(1), fc.TO_ASH), (["valley"], {"d": "i"})],
     "towns": {"town_start_0": "The Deepest Hall", "town_start_1": "The Burrow"},
     "edit": _heat},
    {"id": "fg_wardens_keep", "name": "The Wardens' Keep", "chapter": "fg_wardens_keep",
     "source": "gen:random_xl_3p_normal_normal_ring:5", "dress_seed": 1307,
     "doc": "The Shuttered Halls chapter 7 (townless start): the expedition starts with no town; Forge watch-posts (villages) sell companies; Ithra's Ashen hold the Wardens' Keep by the broken Lockstone.",
     "players": [HUMAN, ashen("Ithra's Host"), CLOSED],
     "themes": ROCK + [(fc.nearer(1), fc.TO_ASH)],
     "towns": {"town_start_0": "Karn Watch", "town_start_1": "The Wardens' Keep", "town_start_2": "Old Lockwatch"},
     "edit": _wardens_keep},
    {"id": "fg_ore_ember", "name": "Ore and Ember", "chapter": "fg_ore_ember",
     "source": "gen:random_xl_3p_normal_normal_hub:9", "dress_seed": 1308,
     "doc": "The Shuttered Halls chapter 8 (conquest): the ore roads, rock and cinder; Vrask the Twice-Eaten holds the pits; the third realm is a neutral hold.",
     "players": [HUMAN, ashen("Vrask's Pits"), CLOSED],
     "themes": [(fc.EVERYWHERE, fc.TO_ORE), (fc.nearer(1), fc.TO_ASH)],
     "towns": {"town_start_0": "The Ore Gate", "town_start_1": "Vrask's Pit", "town_start_2": "Slagford", "town_heart": "Emberroad Fort"}},
    {"id": "fg_engine", "name": "The Engine", "chapter": "fg_engine",
     "source": "gen:random_xl_4p_normal_normal_ring:3", "dress_seed": 1309, "order": {1: 2, 2: 1},
     "doc": "The Shuttered Halls chapter 9 (2v2): the Forge and Wren's Concord column (slot 2) against Morvath's host (slot 1) and Vrask's brood (slot 3); snow outside the gates.",
     "players": [dict(HUMAN, team=1), ashen("Morvath's Host", team=2),
                 {"type": "computer", "faction": "concord", "name": "Wren's Column", "team": 1}, ashen("Vrask's Brood", team=2)],
     "themes": [(fc.EVERYWHERE, fc.TO_SNOW), (fc.nearer(0), fc.TO_ROCK), (fc.nearer(1), fc.TO_ASH), (fc.nearer(3), fc.TO_ASH)],
     "towns": {"town_start_0": "The Forge Gate", "town_start_1": "Morvath's Camp", "town_start_2": "Wren's Column", "town_start_3": "The Brood Pits", "town_heart": "Engine Hall"},
     "edit": _engine},
    {"id": "second_lockstone", "name": "The Second Lockstone", "chapter": "fg_second_lockstone",
     "source": "gen:random_xl_3p_normal_normal_ring:7", "dress_seed": 1310,
     "doc": "The Shuttered Halls chapter 10, one against two: the Worldforge, where the new seal is cast, besieged by the Ashen Host and the drowned Hollow dead, allied computer players (team 1) at the easy difficulty.",
     "players": [HUMAN, ashen("The Besieging Host", team=1, difficulty="easy"),
                 {"type": "computer", "faction": "hollow", "name": "The Drowned Dead", "team": 1, "difficulty": "easy"}],
     "themes": ROCK + [(fc.nearer(1), fc.TO_ASH), (fc.nearer(2), fc.TO_DEAD)],
     "towns": {"town_start_0": "The Worldforge", "town_start_1": "The Siege Camp", "town_start_2": "The Drowned Shafts", "town_heart": "Kharrak Gate"},
     "edit": _worldforge},
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
        fc.update_campaign("shuttered_halls", done)


build_frozen(OUT)
