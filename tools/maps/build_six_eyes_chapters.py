"""Builds the generated chapters of the Umbral Court expansion campaign
"The Six Eyes" (chapters 2-9; the hand-made chapter 1 and finale are in
tools/maps/build_six_eyes_maps.py).

Each chapter starts from a random-map layout frozen with maplib.freeze
(picked from contact sheets of the s/xl 2p, xl 3p and l 4p families) and is
tuned below: story ground, factions, towns, landmarks, villages. The
chapter's "map", "setup" and "scenario" fields in data/campaigns.json are
written by wire_chapters (story fields, cast and rewards are never touched).
Slot convention (story thread): 1 = main enemy, 2 = ally, 3 = second enemy.

Edit here, then regenerate:  python3 tools/maps/build_six_eyes_chapters.py data/maps
(needs Godot: $GODOT or godot on PATH) and run ./run_tests.sh dlc_campaigns.
The frozen sources are fixed by MapGenerator.VERSION; the files in data/maps
are the maps the game plays.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from maplib import *
from expansion_chapters import *

OUT = sys.argv[1] if len(sys.argv) > 1 else None
ONLY = set(sys.argv[2:])
CAMPAIGN = "six_eyes"
SERANE = ("Serane Nhalvor", "de_dreadmarshal", [["de_gloam_spear", 30], ["de_shardbow", 12]])
WIRING = {}
# Kharrak's outer hold for the townless chapter 3 (tools/scenario_probe.gd townless_chapter).
SE_UNDER_SKY_GARRISON = [["forge_thrall", 64], ["rivet_crossbowman", 36], ["anvil_guard", 18]]


def wanted(mid):
    return not ONLY or mid in ONLY


def finish(d, seed):
    patchwork(d, seed)   # wavy borders between the rethemed grounds, patches of related ground
    return finish_chapter(d, seed, OUT, SERANE)


# The Wardens' own ground: dark stone (rough) with the deep's cinder seams.
CAVE = {".": "r", "f": "r", "s": "r", "d": "r", "w": "w", "i": "i"}

# ------------------------------------------------- chapter 2: the long stair (L)
# A cavern map (55x55, close to the old 70x48 crossing and the 60x40 chapter 1)
# climbing from the Wardens' gate in the north-west to a breach with daylight in
# the south-east corner, where Kett's Miners camp on the one band of grass. A
# collapsed working smokes beside their camp.
MID = "se_stair"
if wanted(MID):
    d = frozen_chapter("gen:random_s_2p_normal_normal_diagonal:14", MID, "The Long Stair",
        "The Six Eyes chapter 2 (L). Frozen from gen:random_s_2p_normal_normal_diagonal:14 and tuned in tools/maps/build_six_eyes_chapters.py: a cavern climbing from the Wardens' gate in the north-west to a breach with daylight in the south-east corner, where Kett's Miners camp on the one band of grass beside a collapsed working.")
    retheme(d, CAVE)
    retheme(d, {"r": ".", "d": ".", "w": ".", "i": "."}, lambda x, y: 76 <= x + y <= 84)
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    camp = obj(d, "town_start_1")
    camp.update({"id": "town_kett_camp", "name": "Kett's Breach Camp"})
    obj(d, "town_start_0")["name"] = "The Stair-Foot"
    obj(d, "town_route_0").update({"name": "Gloamwell", "town_type": "darkelf"})
    obj(d, "town_route_1").update({"name": "Kett's Lower Works", "town_type": "forge"})
    set_hero(d, "hero_p1", "Overseer Halvar Kett", "artificer", faction_army("forge", 3, 2.0))
    deco_pattern(d, camp["pos"][0] - 5, camp["pos"][1] - 4, "shaft")
    finish(d, 7103)
    WIRING[MID] = {"map": MID, "setup": setup}

# ---------------------------------------------- chapter 3: under the sky (T)
# Out under the sky with no town. The Wardens come up the northern pass into
# Forge mountains; Stonebarrow, an empty Forge outer hold, is the first prize,
# and the Forge outer steadings (villages) around the Wardens sell Forge folk.
# Kharrak Hold, the one enemy town, holds the south; the Eye is inside it.
MID = "se_under_sky"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_2p_normal_normal_tree:12", MID, "Under the Sky",
        "The Six Eyes chapter 3 (T, townless start). Frozen from gen:random_xl_2p_normal_normal_tree:12 and tuned in tools/maps/build_six_eyes_chapters.py: rough mountain country; the Wardens start without a town in the north with Forge outer steadings (villages) around them; Stonebarrow, an empty Forge hold, is the first prize; Kharrak Hold, the one enemy town, holds the south.")
    retheme(d, {".": "r", "f": "r", "w": "r", "d": "r", "i": "r", "s": "s"})
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    labels = zone_map(d)
    obj(d, "town_start_0").update({"id": "town_stonebarrow", "name": "Stonebarrow", "town_type": "forge"})
    obj(d, "town_start_1").update({"id": "town_kharrak_hold", "name": "Kharrak Hold"})
    obj(d, "town_deep_0").update({"name": "Coldforge", "town_type": "forge"})
    obj(d, "town_deep_1").update({"name": "Hammerdeep", "town_type": "forge"})
    set_hero(d, "hero_p1", "Gunnra Sootmantle", "runesmith", faction_army("forge", 3, 2.5))
    kx, ky = obj(d, "town_kharrak_hold")["pos"]
    deco_pattern(d, kx + 5, ky - 3, "forge")
    # Tuned with tools/scenario_probe.gd townless_chapter campaign:six_eyes:2 town_stonebarrow:
    # Serane alone wins 0%, the best army the gold (9000) buys 100% (36% losses).
    make_townless(d, 0, "town_stonebarrow", "forge", 9000, SE_UNDER_SKY_GARRISON, villages=4, seed=3,
                  guard=[[["crag_slinger", 8]], [["thornwolf", 8]], [["road_cutthroat", 10]], [["crag_slinger", 10]]])
    finish(d, 7211)
    WIRING[MID] = {"map": MID, "setup": setup, "scenario": {
        "name": "Under the Sky", "player": 0, "townless_players": [0], "objectives": [
            {"id": "take_town", "type": "control_towns", "towns": ["town_stonebarrow"], "text": "Take Stonebarrow"},
            {"id": "kharrak", "type": "control_towns", "towns": ["town_kharrak_hold"], "text": "Take Kharrak Hold and the Eye inside it"}]}}

# ------------------------------------------------ chapter 4: the saint's eye (C)
# Greyhold's farmland: the Wardens come from the rock in the north-west; Greyhold
# stands on grass in the south-east with its chapel beside it. Burned hamlets
# line the road the lances took.
MID = "se_saints_eye"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_2p_normal_normal_hub:11", MID, "The Saint's Eye",
        "The Six Eyes chapter 4 (C). Frozen from gen:random_xl_2p_normal_normal_hub:11 and tuned in tools/maps/build_six_eyes_chapters.py: the Wardens in the rocky north-west, Greyhold on grass in the south-east with its chapel (the shattered citadel set piece) beside it, burned hamlets along the road between.")
    labels = zone_map(d)
    retheme(d, {"d": ".", "w": ".", "i": ".", "s": "."})
    retheme_zones(d, ["start_0"], {".": "r", "f": "r"}, labels)
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    grey = obj(d, "town_start_1")
    grey.update({"id": "town_greyhold", "name": "Greyhold"})
    obj(d, "town_start_0")["name"] = "The Wardens' Camp"
    obj(d, "town_heart").update({"name": "Saint's Crossing", "town_type": "concord"})
    set_hero(d, "hero_p1", "Aldous Wren", "knight", faction_army("concord", 4, 2.5))
    gx, gy = grey["pos"]
    landmark_near(d, gx - 7, gy - 5, "landmark_shattered_citadel")
    for p in road_points(d, obj(d, "town_heart")["pos"], grey["pos"], 3):
        deco_pattern(d, p[0] + 2, p[1] + 2, "burned")
    finish(d, 7319)
    WIRING[MID] = {"map": MID, "setup": setup}

# -------------------------------------------- chapter 5: the thorn mirror (B)
# The Wardens (west) march with Greyhold's Lances (north-east) into the
# Thornwood. The Last Grove, the Covenant's capital, stands in the south with the
# Heartroots beside it. When the Wardens take the Grove, Wren's lances wheel.
MID = "se_thorn_mirror"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_3p_normal_normal_hub:11", MID, "The Thorn Mirror",
        "The Six Eyes chapter 5 (B, betrayal). Frozen from gen:random_xl_3p_normal_normal_hub:11 and tuned in tools/maps/build_six_eyes_chapters.py: a forest map; the Wardens in the west and their ally Greyhold's Lances in the north-east against the Thornwood in the south, where the Last Grove stands beside the Heartroots. Taking the Grove turns the Lances.")
    labels = zone_map(d)
    retheme(d, {".": "f", "d": "f", "s": "f", "i": "f", "r": "f"})
    retheme_zones(d, ["start_0"], {"f": "r"}, labels)
    retheme_zones(d, ["start_2"], {"f": "."}, labels)
    setup = story_setup(CAMPAIGN, MID, teams=[1, 2, 1])
    apply_setup(d, setup)
    grove = obj(d, "town_start_1")
    grove.update({"id": "town_last_grove", "name": "The Last Grove"})
    obj(d, "town_start_0")["name"] = "The Wardens' Camp"
    obj(d, "town_start_2")["name"] = "Greyhold's Lance-Camp"
    obj(d, "town_heart").update({"name": "Briarmoot", "town_type": "thornwood"})
    set_hero(d, "hero_p1", "Brakka Thornhide", "grovewarden", faction_army("thornwood", 5, 3.0))
    set_hero(d, "hero_p2", "Aldous Wren", "knight", faction_army("concord", 5, 2.5))
    gx, gy = grove["pos"]
    landmark_near(d, gx + 4, gy - 6, "landmark_elder_grove")
    finish(d, 7427)
    WIRING[MID] = {"map": MID, "setup": setup, "scenario": {
        "name": "The Thorn Mirror", "player": 0,
        "betrayal": {"player": 2, "joins": 1, "trigger": {"towns_taken": {"towns": ["town_last_grove"], "count": 1, "by": 0}},
            "text": "Wren's lances wheel. 'The Eye's grip does not let go all at once,' says Ulmarra. Hold the Grove.",
            "reinforcements": [["shieldwarden", 14], ["lancer", 8], ["lightbearer", 5]]},
        "objectives": [
            {"id": "lances", "type": "ally_survives", "player": 2, "until_betrayal": True, "text": "Keep Greyhold's Lances with you"},
            {"id": "grove", "type": "control_towns", "towns": ["town_last_grove"], "text": "Take the Last Grove, and hold it"},
            {"id": "conquer", "type": "conquer", "text": "Break the Thornwood, and whoever stands with it"}]}}

# ------------------------------------------- chapter 6: the regent's price (A)
# 2v2 in the barrow land: the Wardens (north-east) and the Pale Inheritance
# (Ysmay, south-east) against two Ashen broods in the west on their burned
# patches. Swamp and grass with barrows.
MID = "se_regents_price"
if wanted(MID):
    d = frozen_chapter("gen:random_l_4p_normal_normal_ring:12", MID, "The Regent's Price",
        "The Six Eyes chapter 6 (A, 2v2). Frozen from gen:random_l_4p_normal_normal_ring:12 and tuned in tools/maps/build_six_eyes_chapters.py: barrow land of swamp and grass; the Wardens (north-east) and their ally the Pale Inheritance (south-east) against two Ashen broods (north-west and south-west) on burned ground.")
    swap_slots(d, 2, 3)
    labels = zone_map(d)
    retheme(d, {"f": "w", "d": ".", "s": "w", "r": ".", "i": "."})
    zone_of = {o["owner"]: o["zone"] for o in d["objects"] if o["type"] == "town" and o.get("owner", -1) >= 0}
    retheme_zones(d, [zone_of[0]], {".": "r", "w": "r"}, labels)
    retheme_zones(d, [zone_of[1], zone_of[3]], {".": "i", "w": "i"}, labels)
    retheme_zones(d, [zone_of[2]], {".": "w"}, labels)
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    obj(d, "town_start_0")["name"] = "The Wardens' Camp"
    for o in d["objects"]:
        if o["type"] == "town" and o.get("owner") == 1:
            o["name"] = "Emberclaw's Pit"
        elif o["type"] == "town" and o.get("owner") == 2:
            o["name"] = "Ysmay's Barrow"
        elif o["type"] == "town" and o.get("owner") == 3:
            o["name"] = "Hollowbrand's Pit"
    obj(d, "town_heart").update({"name": "The Regent's Mound", "town_type": "hollow"})
    set_hero(d, "hero_p1", "Garsh Emberclaw", "warlord", faction_army("ashen", 5, 3.0))
    set_hero(d, "hero_p2", "Ysmay of the Barrows", "necromancer", faction_army("hollow", 5, 2.5))
    set_hero(d, "hero_p3", "Grisk Hollowbrand", "warlord", faction_army("ashen", 5, 3.0))
    info = zone_info(d, labels)
    for z in ("heart", "approach_0", "approach_1", "approach_2", "approach_3"):
        deco_pattern(d, *info[z]["center"], "graves")
    finish(d, 7537)
    WIRING[MID] = {"map": MID, "setup": setup, "scenario": {
        "name": "The Regent's Price", "player": 0, "objectives": [
            {"id": "conquer", "type": "conquer", "text": "Burn out both broods"},
            {"id": "ysmay", "type": "ally_survives", "player": 2, "text": "The Pale Inheritance must not fall"}]}}

# --------------------------------------------- chapter 7: under a red sky (C)
# Cinder ground under a red sky: the Wardens come from the south-west, Skarn's
# Cindermaw smokes in the north-east by its volcano. Skarn's town is the only
# objective.
MID = "se_red_sky"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_2p_normal_normal_diagonal:13", MID, "Under a Red Sky",
        "The Six Eyes chapter 7 (C). Frozen from gen:random_xl_2p_normal_normal_diagonal:13 and tuned in tools/maps/build_six_eyes_chapters.py: cinder wastes; the Wardens in the south-west, Skarn's Cindermaw in the north-east beside its volcano. Taking Cindermaw wins the chapter.")
    labels = zone_map(d)
    retheme(d, {".": "i", "f": "i", "w": "i", "s": "d"})
    retheme_zones(d, ["start_0"], {"i": "r"}, labels)
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    maw = obj(d, "town_start_1")
    maw.update({"id": "town_cindermaw", "name": "Cindermaw"})
    obj(d, "town_start_0")["name"] = "The Wardens' Camp"
    obj(d, "town_corner_0").update({"name": "Ashgap", "town_type": "ashen"})
    obj(d, "town_corner_1").update({"name": "Smokewell", "town_type": "ashen"})
    set_hero(d, "hero_p1", "Skarn Ashborn", "warlord", faction_army("ashen", 6, 3.5))
    mx, my = maw["pos"]
    v = landmark_near(d, mx - 8, my + 3, "landmark_cinder_volcano")
    deco_pattern(d, v[0] + 1, v[1] + 5, "cinders")
    finish(d, 7649)
    WIRING[MID] = {"map": MID, "setup": setup, "scenario": {
        "name": "Under a Red Sky", "player": 0, "objectives": [
            {"id": "cindermaw", "type": "control_towns", "towns": ["town_cindermaw"], "text": "Take Cindermaw from Skarn"}]}}

# ---------------------------------------------- chapter 8: the winter's eye (C)
# The Ancient Glacier: the Wardens climb from the rock in the south-west; Kettlehall
# stands on the ice in the north-east beside the frozen cascade and its cairn.
MID = "se_winters_eye"
if wanted(MID):
    d = frozen_chapter("gen:random_xl_2p_normal_normal_ring:12", MID, "The Winter's Eye",
        "The Six Eyes chapter 8 (C). Frozen from gen:random_xl_2p_normal_normal_ring:12 and tuned in tools/maps/build_six_eyes_chapters.py: the Ancient Glacier; the Wardens in the rocky south-west, Kettlehall on the ice in the north-east beside the frozen cascade and its cairn.")
    labels = zone_map(d)
    retheme(d, {".": "s", "f": "s", "w": "s", "d": "s", "i": "r"})
    retheme_zones(d, ["start_0"], {"s": "r"}, labels)
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    kettle = obj(d, "town_start_1")
    kettle.update({"id": "town_kettlehall", "name": "Kettlehall"})
    obj(d, "town_start_0")["name"] = "The Wardens' Camp"
    obj(d, "town_outer_0").update({"name": "Rimegate", "town_type": "frostmarch"})
    obj(d, "town_outer_1").update({"name": "Whitecairn", "town_type": "frostmarch"})
    set_hero(d, "hero_p1", "Ulvra Kettleborn", "thane", faction_army("frostmarch", 7, 4.0))
    kx, ky = kettle["pos"]
    c = landmark_near(d, kx + 4, ky + 4, "landmark_frozen_cascade")
    deco_pattern(d, c[0] - 2, c[1] + 2, "cairn")
    finish(d, 7753)
    WIRING[MID] = {"map": MID, "setup": setup}

# ------------------------------------------------ chapter 9: the long stair (S)
# Survival: the Wardens hold the Stair-Hold at the top of the stair in the
# south-west corner through day 21 while Greyhold (north-west), Kharrak Hold
# (north-east) and Kettlehall (south-east), allied and at the easy difficulty,
# press from three sides. Rough mountain country.
MID = "se_long_stair"
if wanted(MID):
    d = frozen_chapter("gen:random_l_4p_normal_normal_hub:12", MID, "The Long Stair Down",
        "The Six Eyes chapter 9 (S, survival). Frozen from gen:random_l_4p_normal_normal_hub:12 and tuned in tools/maps/build_six_eyes_chapters.py: rough mountain country; the Wardens hold the Stair-Hold in the south-west corner through day 21 while Greyhold (north-west), Kharrak Hold (north-east) and Kettlehall (south-east), allied and easy, press from three sides.")
    labels = zone_map(d)
    retheme(d, {".": "r", "f": "r", "w": "r", "d": "r", "i": "r"})
    retheme_zones(d, ["start_1"], {"r": "."}, labels)
    retheme_zones(d, ["start_3", "valley_2"], {"r": "s"}, labels)
    setup = story_setup(CAMPAIGN, MID)
    apply_setup(d, setup)
    hold = obj(d, "town_start_0")
    hold.update({"id": "town_stair_hold", "name": "The Stair-Hold"})
    obj(d, "town_start_1")["name"] = "Greyhold's Siege Camp"
    obj(d, "town_start_2")["name"] = "Kharrak's Forward Hold"
    obj(d, "town_start_3")["name"] = "Kettlehall's Winter Camp"
    obj(d, "town_heart").update({"name": "The Stair-Head", "town_type": "darkelf"})
    set_hero(d, "hero_p1", "Aldous Wren", "knight", faction_army("concord", 7, 3.5))
    set_hero(d, "hero_p2", "Gunnra Sootmantle", "runesmith", faction_army("forge", 7, 3.5))
    set_hero(d, "hero_p3", "Ulvra Kettleborn", "thane", faction_army("frostmarch", 7, 3.5))
    hx, hy = hold["pos"]
    deco_pattern(d, hx - 5, hy + 4, "stones")
    finish(d, 7867)
    WIRING[MID] = {"map": MID, "setup": setup, "scenario": {
        "name": "The Long Stair", "player": 0, "objectives": [
            {"id": "survive", "type": "survive", "through_day": 21, "text": "Survive until the end of day 21"},
            {"id": "hold", "type": "control_towns", "towns": ["town_stair_hold"], "optional": True, "text": "Hold the Stair-Hold"}]}}


wire_chapters(CAMPAIGN, WIRING, OUT)
