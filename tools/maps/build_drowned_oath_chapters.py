"""Builds the generated chapters of the Abyssal Shoal expansion campaign
"The Drowned Oath" (chapters 2-9; the hand-made chapter 1 and finale are in
tools/maps/build_drowned_oath_maps.py).

Each chapter starts from a random-map layout frozen with maplib.freeze and is
tuned below: story ground, factions, towns, landmarks, villages, waves. The
chapter's "map", "setup" and "scenario" fields in data/campaigns.json are
written by wire_chapters (story fields, cast and rewards are never touched).
Slot convention (story thread): 1 = main enemy, 2 = ally, 3 = second enemy.

Cold (hostile snow for the Shoal, #137): chapters 2-6 keep snow off the
Shoal's roads (chapter 5 shows the first snow on the far edge only); the
Forgewarm Harness is the chapter 6 reward, so chapters 7-9 may be snowy, but
the Shoal still starts and finds its first towns off the snow.

Edit here, then regenerate:  python3 tools/maps/build_drowned_oath_chapters.py data/maps
(needs Godot: $GODOT or godot on PATH) and run ./run_tests.sh dlc_campaigns.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *
from expansion_chapters import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
ONLY = set(sys.argv[2:])
CAMPAIGN = "drowned_oath"
ILO = ("Ilo Who Reads", "fm_deep_oracle", [["fm_brine_spear", 30], ["fm_hookcaster", 12]])
WIRING = {}
# The Rivermouth's hall for the townless chapter 9 (tools/scenario_probe.gd townless_chapter).
DO_CAIRN_GARRISON = [["clan_raider", 120], ["rimefang_hound", 60], ["oathless_berserker", 30], ["tusk_rider", 14], ["frost_shaman", 6]]


def wanted(mid):
    return not ONLY or mid in ONLY


def finish(d, seed):
    patchwork(d, seed)   # wavy borders between the rethemed grounds, patches of related ground
    return finish_chapter(d, seed, OUT, ILO)


def town_in(d, owner):
    return [o for o in d["objects"] if o["type"] == "town" and o.get("owner") == owner]


# ------------------------------------------------- chapter 2: one shoal (L)
# Swamp and water (55x55, close to the 60x40 chapter 1): Ilo's Shoal in the
# southern marsh, Urrh's Shoal in the north, two reef lagoons between them.
MID = "do_one_shoal"
if wanted(MID):
    d = frozen_chapter("gen:random_s_2p_normal_normal_lanes:13", MID, "One Shoal",
        "The Drowned Oath chapter 2 (L). Frozen from gen:random_s_2p_normal_normal_lanes:13 and tuned in tools/maps/build_drowned_oath_chapters.py: swamp and sandbars; Ilo's Shoal in the south, Urrh's Shoal in the north, two reef lagoons between them.")
    labels = zone_map(d)
    retheme(d, {".": "w", "f": "w", "s": "d", "r": "d", "i": "w"})
    info = zone_info(d, labels)
    reefs = [lagoon(d, *info[z]["center"]) for z in ("lane_b_0", "lane_b_1")]
    for rx, ry in reefs:
        deco_pattern(d, rx, ry, "stones")
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    obj(d, "town_start_0")["name"] = "Ilo's Mudhall"
    obj(d, "town_start_1").update({"id": "town_urrhs_shoal", "name": "Urrh's Shoal"})
    obj(d, "town_heart").update({"name": "The Middle Reef", "town_type": "fishmen"})
    set_hero(d, "hero_p1", "Urrh the Fat", "fm_tidemarshal", faction_army("fishmen", 3, 2.0))
    finish(d, 8101)
    WIRING[MID] = {"map": MID, "setup": setup}

# ---------------------------------------------------- chapter 3: landfall (C)
# The Living Shore: the sea along the west edge, swamp inland and grass beyond;
# the Shoal lands in the south, Emberclaw's stragglers hold a scorched patch in
# the north. A drowned chapel stands on the shore near the landing.
MID = "do_landfall"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_2p_normal_normal_lanes:13", MID, "Landfall",
        "The Drowned Oath chapter 3 (C). Frozen from gen:random_xl_2p_normal_normal_lanes:13 and tuned in tools/maps/build_drowned_oath_chapters.py: the Living Shore; the sea along the west edge, swamp inland and grass beyond; the Shoal lands in the south, Emberclaw's stragglers hold a scorched patch in the north; a drowned chapel (the shattered citadel set piece) on the shore near the landing.")
    labels = zone_map(d)
    retheme(d, {"f": ".", "s": ".", "d": ".", "r": ".", "i": "w"})
    retheme(d, {".": "w"}, lambda x, y: x < 30)
    retheme_zones(d, ["start_0"], {".": "w"}, labels)
    retheme_zones(d, ["start_1"], {".": "i", "w": "i"}, labels)
    coast(d, "w")
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    obj(d, "town_start_0")["name"] = "The Landing"
    obj(d, "town_start_1").update({"id": "town_emberclaw_camp", "name": "Emberclaw's Camp"})
    obj(d, "town_heart").update({"name": "Shorehold", "town_type": "concord"})
    set_hero(d, "hero_p1", "Garsh Emberclaw", "warlord", faction_army("ashen", 3, 2.5))
    hx, hy = obj(d, "town_start_0")["pos"]
    landmark_near(d, 10, hy - 6, "landmark_shattered_citadel")
    finish(d, 8209)
    WIRING[MID] = {"map": MID, "setup": setup}

# ------------------------------------------------- chapter 4: the last brood (A)
# 2v2 on the Barrow Roads: the Shoal (north-west) and Greyhold's Lances (north-
# east) against Vrask's and Cindermouth's broods in the south on burned ground.
MID = "do_last_brood"
if wanted(MID):
    d = frozen_chapter("gen:random_l_4p_normal_normal_hub:13", MID, "The Last Brood",
        "The Drowned Oath chapter 4 (A, 2v2). Frozen from gen:random_l_4p_normal_normal_hub:13 and tuned in tools/maps/build_drowned_oath_chapters.py: the Barrow Roads, swamp and grass with barrows; the Shoal (north-west) and Greyhold's Lances (north-east) against two Ashen broods in the south on burned ground.")
    swap_slots(d, 2, 3)
    labels = zone_map(d)
    retheme(d, {"f": "w", "d": ".", "s": ".", "r": ".", "i": "."})
    zone_of = {o["owner"]: o["zone"] for o in d["objects"] if o["type"] == "town" and o.get("owner", -1) >= 0}
    retheme_zones(d, [zone_of[0]], {".": "w"}, labels)
    retheme_zones(d, [zone_of[1], zone_of[3]], {".": "i", "w": "i"}, labels)
    retheme_zones(d, [zone_of[2]], {"w": "."}, labels)
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    names = {0: "The Shoal's Camp", 1: "Vrask's Pit", 2: "Greyhold's Lance-Camp", 3: "Cindermouth"}
    for o in d["objects"]:
        if o["type"] == "town" and o.get("owner", -1) in names:
            o["name"] = names[o["owner"]]
    set_hero(d, "hero_p1", "Vrask the Twice-Eaten", "warlord", faction_army("ashen", 4, 2.5))
    set_hero(d, "hero_p2", "Aldous Wren", "knight", faction_army("concord", 4, 2.5))
    set_hero(d, "hero_p3", "Gaul Cindermouth", "warlord", faction_army("ashen", 4, 2.5))
    info = zone_info(d, labels)
    for z in ("heart", "spoke_0", "spoke_1", "spoke_2", "spoke_3"):
        deco_pattern(d, *info[z]["center"], "graves")
    finish(d, 8311)
    WIRING[MID] = {"map": MID, "setup": setup, "scenario": {
        "name": "The Last Brood", "player": 0, "objectives": [
            {"id": "conquer", "type": "conquer", "text": "Burn out the last two broods"},
            {"id": "wren", "type": "ally_survives", "player": 2, "text": "Greyhold's Lances must not fall"}]}}

# ---------------------------------------------- chapter 5: the price of iron (C)
# The Forge's outer holds in rough mountains. The Shoal comes up a marsh valley
# in the north-east; Kharrak's outer gate stands in the south-west, and beyond it,
# on the far west and south edges, lies the first snow.
MID = "do_price_of_iron"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_2p_normal_normal_hub:13", MID, "The Price of Iron",
        "The Drowned Oath chapter 5 (C). Frozen from gen:random_xl_2p_normal_normal_hub:13 and tuned in tools/maps/build_drowned_oath_chapters.py: the Forge's outer holds in rough mountains; the Shoal in a marsh valley in the north-east, Kharrak's outer gate in the south-west, the first snow on the far west and south edges.")
    labels = zone_map(d)
    retheme(d, {".": "r", "f": "r", "s": "r", "d": "r", "i": "r", "w": "r"})
    retheme_zones(d, ["start_0"], {"r": "w"}, labels)
    retheme(d, {"r": "s"}, lambda x, y: x < 1 + 5 * noise(8419, x, y, 6.0) or y > 85 - 5 * noise(8420, x, y, 6.0))
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    gate = obj(d, "town_start_1")
    gate.update({"id": "town_kharrak_gate", "name": "Kharrak's Outer Gate"})
    obj(d, "town_start_0")["name"] = "The Shoal's Camp"
    obj(d, "town_heart").update({"name": "Ironstair", "town_type": "forge"})
    set_hero(d, "hero_p1", "Dask Ironhand", "ironmarshal", faction_army("forge", 5, 3.0))
    deco_pattern(d, gate["pos"][0] + 5, gate["pos"][1] - 4, "forge")
    finish(d, 8419)
    WIRING[MID] = {"map": MID, "setup": setup}

# ---------------------------------------------- chapter 6: three weeks (S)
# Survival: the Shoal holds the two furnace-holds it took (north) through day 21
# while Kharrak Hold (south) and its hammer-columns counter-attack up the trunk
# road and over both flanks. Rough ground; the forges smoke beside both holds.
MID = "do_three_weeks"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_2p_normal_normal_tree:14", MID, "Three Weeks",
        "The Drowned Oath chapter 6 (S, survival). Frozen from gen:random_xl_2p_normal_normal_tree:14 and tuned in tools/maps/build_drowned_oath_chapters.py: rough ground; the Shoal holds the two furnace-holds in the north through day 21 while Kharrak Hold in the south and its hammer-columns (waves) counter-attack.")
    labels = zone_map(d)
    retheme(d, {".": "r", "f": "r", "s": "r", "d": "r", "i": "r"})
    extra = [{"type": "computer", "faction": "forge", "name": "Kharrak's Hammer-Columns", "team": 2}]
    setup = story_setup(CAMPAIGN, MID, teams=[1, 2], extra=extra)
    apply_setup(d, setup)
    north = obj(d, "town_start_0")
    north.update({"id": "town_furnace_north", "name": "Upper Furnace"})
    south = obj(d, "town_trunk_0")
    south.update({"id": "town_furnace_south", "name": "Lower Furnace", "owner": 0, "town_type": "forge",
                  "built": ["f_hall", "f_fort1", "f_dw1", "f_dw2", "f_dw3"]})
    south.pop("garrison", None)
    obj(d, "town_start_1").update({"id": "town_kharrak_hold", "name": "Kharrak Hold"})
    obj(d, "town_trunk_1").update({"name": "Slagmouth", "town_type": "forge"})
    north["town_type"] = "forge"
    set_hero(d, "hero_p1", "Gunnra Sootmantle", "runesmith", faction_army("forge", 5, 3.0))
    for t in (north, south):
        deco_pattern(d, t["pos"][0] + 4, t["pos"][1] + 1, "forge")
    HOLDS = ["town_furnace_north", "town_furnace_south"]
    entries = {z: edge_entries(d, z, e, labels) for z, e in (("branch_a_0", "e"), ("branch_b_0", "w"), ("deep_0", "e"), ("deep_1", "w"))}
    finish(d, 8521)
    WAVES = []
    for i, (day, zone, target, army) in enumerate([
            (5, "deep_0", "town_furnace_south", [["forge_thrall", 40], ["rivet_crossbowman", 18], ["anvil_guard", 8]]),
            (9, "deep_1", "town_furnace_south", [["forge_thrall", 50], ["rivet_crossbowman", 24], ["anvil_guard", 12], ["slag_golem", 4]]),
            (13, "branch_a_0", "town_furnace_north", [["rivet_crossbowman", 30], ["anvil_guard", 16], ["slag_golem", 7], ["cinder_engineer", 3]]),
            (17, "branch_b_0", "town_furnace_north", [["forge_thrall", 60], ["anvil_guard", 18], ["slag_golem", 8], ["cinder_engineer", 4]]),
            (20, "deep_0", "town_furnace_south", [["forge_thrall", 70], ["rivet_crossbowman", 34], ["anvil_guard", 20], ["slag_golem", 10], ["cinder_engineer", 5]])]):
        WAVES.append(wave("hammer_wave_%d" % i, day, 2, entries[zone], "the side passes", target, [target] + [h for h in HOLDS if h != target],
                          "hammer_column_%d" % i, ["Bellows-Captain", "Slag-Warden", "Rivet-Marshal", "Anvil-Thane", "The Last Column"][i],
                          "ironmarshal", army))
    WIRING[MID] = {"map": MID, "setup": setup, "scenario": {
        "name": "Three Weeks", "player": 0, "protected_towns": HOLDS, "invasion_players": [2], "max_active_invaders": 3,
        "random_events": False, "wave_strength": {"easy": 0.75, "normal": 1.0, "hard": 1.25},
        "objectives": [
            {"id": "holds", "type": "survive", "through_day": 21, "text": "Hold both furnace-holds through day 21"},
            {"id": "waves", "type": "clear_waves", "optional": True, "text": "Break every hammer-column Kharrak sends"}],
        "waves": WAVES}}

# ------------------------------------------------- chapter 7: the cold road (C)
# The Iron Pass: from the Shoal's camp in the rough north down the pass and onto
# the snow, where Clan Grimfell's hall stands in the south. The Shoal's start and
# the first town (the pass fort in the middle) stay off the snow.
MID = "do_cold_road"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_2p_normal_normal_tree:11", MID, "The Cold Road",
        "The Drowned Oath chapter 7 (C). Frozen from gen:random_xl_2p_normal_normal_tree:11 and tuned in tools/maps/build_drowned_oath_chapters.py: the Iron Pass; the Shoal's camp in the rough north, the pass fort in the middle, the snow from there south to Clan Grimfell's hall.")
    labels = zone_map(d)
    retheme(d, {".": "r", "f": "r", "d": "r", "i": "r"})
    retheme_zones(d, ["start_0"], {"r": "w"}, labels)
    retheme(d, {"r": "s", "w": "s", ".": "s"}, lambda x, y: y > 48 + 8 * noise(8627, x, y, 7.0))
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    obj(d, "town_start_0")["name"] = "The Shoal's Camp"
    obj(d, "town_start_1").update({"id": "town_grimfell_hall", "name": "Grimfell Clan-Hall"})
    obj(d, "town_heart").update({"name": "The Pass Fort", "town_type": "forge"})
    set_hero(d, "hero_p1", "Hrodna Grimfell", "thane", faction_army("frostmarch", 6, 3.5))
    finish(d, 8627)
    WIRING[MID] = {"map": MID, "setup": setup}

# --------------------------------------------------- chapter 8: who pays (B)
# Snow. The Shoal (north) marches with Greyhold's Lances (south-east) on Clan
# Whaleroad, whose two clan halls stand in the west across the river. When the
# Shoal takes the second hall, Wren turns.
MID = "do_who_pays"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_3p_normal_normal_ring:11", MID, "Who Pays",
        "The Drowned Oath chapter 8 (B, betrayal). Frozen from gen:random_xl_3p_normal_normal_ring:11 and tuned in tools/maps/build_drowned_oath_chapters.py: snow and rivers; the Shoal in the north and its ally Greyhold's Lances in the south-east against Clan Whaleroad's two clan halls in the west. Taking the second hall turns the Lances.")
    labels = zone_map(d)
    retheme(d, {".": "s", "f": "s", "d": "s", "r": "s", "i": "s"})
    retheme_zones(d, ["start_0"], {"s": "w"}, labels)
    retheme_zones(d, ["start_2"], {"s": "."}, labels)
    setup = story_setup(CAMPAIGN, MID, teams=[1, 2, 1])
    apply_setup(d, setup)
    obj(d, "town_start_0")["name"] = "The Shoal's Camp"
    obj(d, "town_start_1").update({"id": "town_whaleroad_hall", "name": "Whaleroad Hall"})
    obj(d, "town_start_2")["name"] = "Greyhold's Lance-Camp"
    info = zone_info(d, labels)
    add_town(d, "town_orms_longhall", info["flank_0"]["center"], "frostmarch", "Orm's Longhall", 1,
             ["r_hall", "r_fort1", "r_dw1", "r_dw2", "r_dw3", "r_dw4"], [["clan_raider", 40], ["rimefang_hound", 16], ["oathless_berserker", 8]])
    set_hero(d, "hero_p1", "Orm Whaleroad", "thane", faction_army("frostmarch", 7, 4.0))
    set_hero(d, "hero_p2", "Aldous Wren", "knight", faction_army("concord", 7, 3.0))
    finish(d, 8731)
    WIRING[MID] = {"map": MID, "setup": setup, "scenario": {
        "name": "Who Pays", "player": 0,
        "betrayal": {"player": 2, "joins": 1, "trigger": {"towns_taken": {"towns": ["town_whaleroad_hall", "town_orms_longhall"], "count": 2, "by": 0}},
            "text": "I am sorry. You were owed too. I only had enough for one.",
            "reinforcements": [["shieldwarden", 20], ["lancer", 10], ["lightbearer", 6], ["sunhawk_rider", 3]]},
        "objectives": [
            {"id": "lances", "type": "ally_survives", "player": 2, "until_betrayal": True, "text": "Keep Greyhold's Lances with you"},
            {"id": "halls", "type": "control_towns", "towns": ["town_whaleroad_hall", "town_orms_longhall"], "text": "Take both clan halls"},
            {"id": "conquer", "type": "conquer", "text": "Break Clan Whaleroad, and whoever stands with it"}]}}

# --------------------------------------------------------- chapter 9: the cairn (T)
# No town: the Shoal comes ashore at the river mouth in the north-west, where
# its rivermouth camps (villages) sell Shoal folk; the hall there is held by the
# clans. The glacier runs south-east to the cairn at its far end, past
# Whaleroad's camp. Ilo must reach the cairn.
MID = "do_cairn"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_2p_normal_normal_diagonal:14", MID, "The Cairn",
        "The Drowned Oath chapter 9 (T, townless start). Frozen from gen:random_xl_2p_normal_normal_diagonal:14 and tuned in tools/maps/build_drowned_oath_chapters.py: the Shoal starts without a town at the river mouth in the north-west, with rivermouth camps (villages) on swamp and grass; the glacier runs south-east past Clan Whaleroad's camp to the cairn (frozen cascade set piece) at its far end, which Ilo must reach.")
    labels = zone_map(d)
    retheme(d, {".": "s", "f": "s", "d": "s", "r": "s", "i": "s", "w": "s"})
    retheme_zones(d, ["start_0"], {"s": "w"}, labels)
    retheme_zones(d, ["march_0", "back_0"], {"s": "."}, labels)
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    mouth = obj(d, "town_start_0")
    mouth.update({"id": "town_rivermouth", "name": "The Rivermouth Hall", "town_type": "fishmen"})
    camp = obj(d, "town_start_1")
    camp.update({"id": "town_whaleroad_camp", "name": "Whaleroad's Ice-Camp"})
    obj(d, "town_route_0").update({"name": "Saltmere", "town_type": "frostmarch"})
    obj(d, "town_route_1").update({"name": "Rimewatch", "town_type": "frostmarch"})
    set_hero(d, "hero_p1", "Seer Iska Rime", "frostcaller", faction_army("frostmarch", 8, 4.5))
    cx, cy = camp["pos"]
    CAIRN_LM = landmark_near(d, cx + 6, cy + 6, "landmark_frozen_cascade")
    deco_pattern(d, CAIRN_LM[0] - 2, CAIRN_LM[1] + 2, "cairn")
    CAIRN = free_tile_near(d, CAIRN_LM[0] - 1, CAIRN_LM[1] + 1, radius=4)
    print("do_cairn cairn", CAIRN)
    # Tuned with tools/scenario_probe.gd townless_chapter campaign:drowned_oath:8 town_rivermouth:
    # Ilo alone wins 41%, the best army the gold (12500) buys 100% (39% losses).
    make_townless(d, 0, "town_rivermouth", "fishmen", 12500, DO_CAIRN_GARRISON, villages=4, seed=9,
                  guard=[[["rime_wight", 10]], [["thornwolf", 14]], [["rime_wight", 12]], [["road_cutthroat", 16]]])
    finish(d, 8839)
    WIRING[MID] = {"map": MID, "setup": setup, "scenario": {
        "name": "The Cairn", "player": 0, "townless_players": [0], "required_heroes": ["hero_ilo"], "objectives": [
            {"id": "take_town", "type": "control_towns", "towns": ["town_rivermouth"], "optional": True, "text": "Take back the Rivermouth Hall"},
            {"id": "cairn", "type": "reach", "hero": "hero_ilo", "pos": list(CAIRN), "text": "Bring Ilo to the cairn at the glacier's end"}]}}


wire_chapters(CAMPAIGN, WIRING, OUT)
