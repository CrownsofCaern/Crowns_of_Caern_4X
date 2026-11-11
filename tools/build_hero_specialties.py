#!/usr/bin/env python3
"""Writes data/hero_specialties.json: one personal specialty per named hero.

The specialties are written here as compact templates so their numbers stay
consistent across the eight factions; the JSON file is the game's source of
truth and this script only regenerates it. Run from the repository root:

    python3 tools/build_hero_specialties.py
"""
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CREATURES = {}
for path in sorted(glob.glob(os.path.join(ROOT, "data", "creatures", "*.json"))):
    with open(path) as f:
        CREATURES.update(json.load(f)["creatures"])


def plural(n, word):
    return "%d %s" % (n, word if n == 1 else word + "s")


def line(cid):
    """A creature line specialist: the creature and its upgrade fight better.
    Low tiers get more (they make up most of an early army), high tiers less."""
    c = CREATURES[cid]
    up = CREATURES[c["upgrade"]]["name"]
    tier = int(c["tier"])
    if tier <= 3:
        start, every = 2, 3
    elif tier <= 6:
        start, every = 1, 4
    else:
        start, every = 1, 5
    return {
        "mods": {"creature_attack": {cid: start}, "creature_defense": {cid: start}},
        "growth": {"every": every, "mods": {"creature_attack": {cid: 1}, "creature_defense": {cid: 1}}, "max": 4},
        "text": "%s and %s stacks gain +%d attack and +%d defense, +1 more each every %d levels (up to +%d)."
        % (c["name"], up, start, start, every, start + 4),
        "creature": cid,
    }


def pct(key, start, step, cap_steps, what, sign="+"):
    total = start + step * cap_steps
    return {
        "mods": {key: start},
        "growth": {"every": 1, "mods": {key: step}, "max": cap_steps},
        "text": "%s %s%d%%, %s%d%% per level (up to %s%d%%)." % (
            what, sign, round(start * 100), sign, round(step * 100), sign, round(total * 100)),
    }


def income(res, start, every, label):
    return {
        "mods": {"income": {res: start}},
        "growth": {"every": every, "mods": {"income": {res: 1 if res != "gold" else 100}}, "max": 3},
        "text": "+%s a day, +%s more every %d levels." % (
            ("%d %s" % (start, label)), ("%d" % (1 if res != "gold" else 100)), every),
    }


def flat(mods, text):
    return {"mods": mods, "text": text}


def formation(spec, fid, bonus, label):
    spec = dict(spec)
    spec["formations"] = {fid: {"unlock": True, "bonus_pct": bonus}}
    spec["text"] = spec["text"] + " Knows the %s formation from the first day; it works %d%% better." % (label, round(bonus * 100))
    return spec


def art(start=0.10, step=0.03):
    return pct("art_power_pct", start, step, 10, "Battle art strength")


# id: (faction, name, spec, [heroes]). Heroes are matched by their exact name;
# a hero not named here gets a specialty of its faction (see HeroSpecialties).
S = {}


def add(sid, faction, name, spec, heroes=()):
    assert sid not in S, sid
    e = {"name": name, "faction": faction}
    e.update(spec)
    e["heroes"] = list(heroes)
    S[sid] = e


# ---------------------------------------------------------------- concord --
add("pike_wall", "concord", "Pike Wall", line("pike_militia"), ["Maud Ferrow"])
add("grey_fletching", "concord", "Grey Fletching", line("longbowman"), ["Corwen Ashby"])
add("lantern_liturgy", "concord", "Lantern Liturgy",
    flat({"art_uses": 1, "art_power_pct": 0.05}, "Uses the battle art one extra round; it is 5% stronger."), ["Isolde Varr"])
add("lancer_captain", "concord", "Lancer Captain", line("lancer"), ["Brannoc Hale"])
add("hedge_paths", "concord", "Hedge Paths",
    {"mods": {"movement_pct": 0.05, "vision": 1}, "growth": {"every": 3, "mods": {"movement_pct": 0.02}, "max": 5},
     "text": "+1 vision and +5% movement, +2% more every 3 levels (up to +15%)."}, ["Edda Thornwick"])
add("shield_of_greyhold", "concord", "Shield of Greyhold", line("shieldwarden"), ["Aldous Wren"])
add("deadeye", "concord", "Deadeye", pct("ranged_damage_pct", 0.04, 0.01, 8, "Ranged damage"), ["Maelis Thorne"])
add("seers_ledger", "concord", "Seer's Ledger",
    {"mods": {"xp_pct": 0.05, "scout_cost_pct": 0.25}, "growth": {"every": 2, "mods": {"xp_pct": 0.01}, "max": 5},
     "text": "+5% experience (+1% every 2 levels) and scouting costs 25% less."}, ["Edda Vey"])
add("abbey_mercy", "concord", "Abbey Mercy", pct("recover_pct", 0.04, 0.01, 8, "Fallen creatures that rise after a victory"),
    ["Abbess Maud Lorne"])
add("sunhawk_eyrie", "concord", "Sunhawk Eyrie", line("sunhawk_rider"), ["Brother Tamsin Hale"])
add("castellans_wall", "concord", "Castellan's Wall", formation(
    {"mods": {"role_defense": {"infantry": 1}, "shot_resist_pct": 0.05},
     "text": "Infantry gain +1 defense and the army takes 5% less damage from shots."}, "shield_wall", 0.25, "Shield Wall"),
    ["Castellan Odo Brack", "Odo Brack"])
add("iron_vow", "concord", "Iron Vow", line("iron_margrave"), ["Sir Piers Ashcombe"])
add("colossus_wright", "concord", "Colossus Wright", line("bastion_colossus"))
add("dawn_choir", "concord", "Dawn Choir", line("lightbearer"))

# ------------------------------------------------------------------ ashen --
add("flayers_due", "ashen", "Flayer's Due", line("flayer"), ["Vhorr the Flayed"])
add("coiled_venom", "ashen", "Coiled Venom", art(), ["Sezra Coil"])
add("houndmaster", "ashen", "Houndmaster", line("scorchhound"), ["Ulmagh Duskmaw"])
add("cinder_horde", "ashen", "Cinder Horde", line("cinderling"), ["Karth Emberlash"])
add("cinder_veil", "ashen", "Cinder Veil", pct("shot_resist_pct", 0.05, 0.01, 10, "Damage taken from shots", "-"),
    ["Ysolt Cinderveil"])
add("ashborn_warband", "ashen", "Ashborn Warband", pct("melee_damage_pct", 0.04, 0.01, 8, "Melee damage"), ["Skarn Ashborn"])
add("brimstone_battery", "ashen", "Brimstone Battery", line("brimstone_hurler"), ["Ithra Sootveil"])
add("pyre_lord", "ashen", "Pyre Lord", line("pyre_titan"), ["Morvath the Kindler"])
add("spoils_of_burning", "ashen", "Spoils of Burning",
    {"mods": {"spoils_pct": 0.1}, "growth": {"every": 1, "mods": {"spoils_pct": 0.02}, "max": 10},
     "text": "Victories pay 0.1 gold per experience, +0.02 per level (up to 0.3)."}, ["Garsh Emberclaw"])
add("gorgewing_roost", "ashen", "Gorgewing Roost", line("gorgewing"), ["Gaul Cindermouth"])
add("ninefang_rush", "ashen", "Ninefang Rush", formation(
    {"mods": {"initiative": 1}, "text": "The army gains +1 initiative."}, "wedge", 0.25, "Wedge"), ["Hrakka Ninefang"])
add("sulfur_tithe", "ashen", "Sulfur Tithe", income("sulfur", 1, 5, "sulfur"), ["Moloq Grieve"])
add("twice_eaten", "ashen", "Twice-Eaten", pct("recover_pct", 0.04, 0.01, 8, "Fallen creatures that rise after a victory"),
    ["Vrask the Twice-Eaten"])
add("witch_coven", "ashen", "Witch Coven", line("ash_witch"))
add("maw_keeper", "ashen", "Maw Keeper", line("cinder_maw"))

# ----------------------------------------------------------------- hollow --
add("gallows_choir", "hollow", "Gallows Choir", line("shambler"), ["Morwen Gallowglass"])
add("bone_bulwark", "hollow", "Bone Bulwark", formation(
    {"mods": {"role_defense": {"heavy": 1}, "morale": 1}, "text": "+1 morale and heavy troops gain +1 defense."},
    "reserve", 0.25, "Reserve"), ["Brother Sallow"])
add("blight_bloom", "hollow", "Blight Bloom", art(), ["Ysra the Blighted"])
add("marrow_quivers", "hollow", "Marrow Quivers", line("marrow_archer"), ["Corvane Ashgrave"])
add("mire_wight", "hollow", "Mire-Wight",
    {"mods": {"terrain_move_pct": {"swamp": 0.5}, "role_attack": {"cavalry": 1}},
     "text": "Swamp costs half the extra movement and cavalry gain +1 attack."}, ["Hesk Mirewight"])
add("barrow_queen", "hollow", "Barrow Queen", pct("recover_pct", 0.05, 0.01, 8, "Fallen creatures that rise after a victory"),
    ["Ysmay Vane", "Ysmay of the Barrows"])
add("gibbet_oath", "hollow", "Gibbet Oath", line("gibbet_knight"), ["Sir Orrin Wren"])
add("weavers_loom", "hollow", "Weaver's Loom", line("corpse_weaver"), ["Father Corvin Mire"])
add("charnel_tithe", "hollow", "Charnel Tithe", income("mercury", 1, 5, "mercury"), ["Abbot Lisk"])
add("crawler_brood", "hollow", "Crawler Brood", line("gravecrawler"), ["Sexton Grue"])
add("deep_fen_shades", "hollow", "Deep Fen Shades", line("wailing_shade"), ["Morrow of the Deep Fen", "Morrow"])
add("unbowed", "hollow", "Unbowed", pct("veteran_xp_pct", 0.08, 0.02, 8, "Veteran experience for the army"),
    ["Vathek the Unbowed"])
add("hulk_stitcher", "hollow", "Hulk Stitcher", line("charnel_hulk"))
add("rotwing_rider", "hollow", "Rotwing Rider", line("rotwing_leviathan"))

# -------------------------------------------------------------- thornwood --
add("barkmantle", "thornwood", "Barkmantle", line("barkhide_warden"), ["Elowen Barkmantle"])
add("greythorn_screen", "thornwood", "Greythorn Screen", formation(
    {"mods": {"ranged_damage_pct": 0.05}, "text": "+5% ranged damage."}, "skirmish_screen", 0.25, "Skirmish Screen"),
    ["Tavish Greythorn"])
add("wyrdroot", "thornwood", "Wyrdroot", line("wyrdthorn_mother"), ["Sylle Wyrdroot"])
add("skulker_kin", "thornwood", "Skulker Kin", line("thorn_skulker"), ["Orrin Mossveil"])
add("briarsong", "thornwood", "Briarsong", art(), ["Maeve Briarsong"])
add("ashbark_roots", "thornwood", "Ashbark Roots", line("rootbinder"), ["Cerrid Ashbark"])
add("hollowreed_huntress", "thornwood", "Hollowreed Huntress", line("briar_huntress"), ["Neve Hollowreed"])
add("old_mothers_tithe", "thornwood", "Old Mother's Tithe",
    {"mods": {"income": {"wood": 1, "gems": 1}}, "growth": {"every": 6, "mods": {"income": {"gems": 1}}, "max": 2},
     "text": "+1 wood and +1 gems a day, +1 gems more every 6 levels."}, ["Old Mother Brakka"])
add("thornhide", "thornwood", "Thornhide", line("rootbound_ancient"), ["Brakka Thornhide"])
add("greyhart_lore", "thornwood", "Greyhart Lore", pct("xp_pct", 0.06, 0.01, 8, "Experience"), ["Elder Greyhart"])
add("strix_eyrie", "thornwood", "Strix Eyrie", line("gloomwing_strix"))
add("spore_brewer", "thornwood", "Spore Brewer", line("spore_lobber"))

# ------------------------------------------------------------------ forge --
add("coalbeard_works", "forge", "Coalbeard Works", income("ore", 2, 4, "ore"), ["Durgan Coalbeard"])
add("ironsworn_line", "forge", "Ironsworn Line", formation(
    {"mods": {"role_defense": {"infantry": 1}, "screen": 0.05},
     "text": "Infantry gain +1 defense; enemy flankers find 5% fewer gaps."}, "shield_wall", 0.25, "Shield Wall"),
    ["Hilda Ironsworn"])
add("runeheld", "forge", "Runeheld", art(), ["Brannik Runeheld"])
add("slagheart", "forge", "Slagheart", line("slag_golem"), ["Thora Slagheart"])
add("deep_bellows", "forge", "Deep Bellows", line("molten_engine"), ["Gorm Deepbellow"])
add("sootmantle_bombards", "forge", "Sootmantle Bombards", line("thunder_bombard"), ["Gunnra Sootmantle"])
add("vells_column", "forge", "Vell's Column", line("anvil_guard"), ["Dask Vell"])
add("guild_purse", "forge", "Guild Purse",
    {"mods": {"recruit_discount_pct": 0.04}, "growth": {"every": 3, "mods": {"recruit_discount_pct": 0.01}, "max": 4},
     "text": "Recruits cost 4% less gold, 1% less every 3 levels (up to 8%)."},
    ["Master Tobbin Greave", "Tobbin Greave"])
add("wardens_crossbows", "forge", "Warden's Crossbows", line("rivet_crossbowman"),
    ["Bruna Kell", "Warden-Captain Bruna Kell"])
add("overseers_whip", "forge", "Overseer's Whip", line("forge_thrall"), ["Overseer Halvar Kett"])
add("boar_stables", "forge", "Boar Stables", line("ironhoof_charger"))
add("engineers_guild", "forge", "Engineers' Guild", line("cinder_engineer"))

# ------------------------------------------------------------- frostmarch --
add("ice_tongue", "frostmarch", "Ice-Tongue", pct("melee_damage_pct", 0.04, 0.01, 8, "Melee damage"), ["Ragna Ice-Tongue"])
add("wolfsbane", "frostmarch", "Wolfsbane", line("rimefang_hound"), ["Hrolf Wolfsbane"])
add("paleveil", "frostmarch", "Paleveil", line("frost_shaman"), ["Sigrun Paleveil"])
add("rimebeard_raids", "frostmarch", "Rimebeard Raids",
    {"mods": {"spoils_pct": 0.1, "terrain_move_pct": {"snow": 0.25}}, "growth": {"every": 1, "mods": {"spoils_pct": 0.02}, "max": 10},
     "text": "Victories pay 0.1 gold per experience (+0.02 per level, up to 0.3); snow costs a quarter less extra movement."},
    ["Torvald Rimebeard"])
add("snowmane_charge", "frostmarch", "Snowmane Charge", formation(
    {"mods": {"role_attack": {"cavalry": 1}}, "text": "Cavalry gain +1 attack."}, "wedge", 0.25, "Wedge"), ["Asa Snowmane"])
add("kettleborn_clan", "frostmarch", "Kettleborn Clan", line("clan_raider"), ["Ulvra Kettleborn", "Ulvra Hrimsdottir"])
add("rime_sight", "frostmarch", "Rime Sight", art(), ["Seer Iska Rime"])
add("coldhand", "frostmarch", "Coldhand", line("oathless_berserker"), ["Bjarr Coldhand"])
add("grimfell_tusks", "frostmarch", "Grimfell Tusks", line("tusk_rider"), ["Hrodna Grimfell"])
add("whaleroad", "frostmarch", "Whaleroad", line("cairn_giant"), ["Thane Orm Whaleroad", "Orm Whaleroad"])
add("aurochs_herd", "frostmarch", "Aurochs Herd", line("rimeback_aurochs"))
add("wyrm_caller", "frostmarch", "Wyrm Caller", line("winter_wyrm"))

# ---------------------------------------------------------------- darkelf --
add("soryn_crescent", "darkelf", "Soryn Crescent", formation(
    {"mods": {"role_attack": {"cavalry": 1}, "initiative": 1}, "text": "Cavalry gain +1 attack and the army +1 initiative."},
    "crescent", 0.25, "Crescent"), ["Vael Soryn"])
add("veyl_mirrors", "darkelf", "Veyl Mirrors", art(), ["Nyra Veyl"])
add("ardan_bolts", "darkelf", "Ardan Bolts", line("de_shardbow"), ["Keth Ardan"])
add("draal_spears", "darkelf", "Draal Spears", line("de_gloam_spear"), ["Sareth Draal"])
add("mor_silk", "darkelf", "Mor Silk", line("de_silk_stalker"), ["Ilyra Mor"])
add("nhalvor_riders", "darkelf", "Nhalvor Riders", line("de_cave_lancer"), ["Serane Nhalvor"])
add("askai_knives", "darkelf", "Askai Knives", line("de_knifedancer"), ["Rhuvel Askai"])
add("matriarchs_court", "darkelf", "Matriarch's Court", income("crystal", 1, 5, "crystal"), ["Matriarch Ulmarra"])
add("obsidian_oath", "darkelf", "Obsidian Oath", line("de_obsidian_guard"))
add("drake_tamer", "darkelf", "Drake Tamer", line("de_gloam_drake"))
add("veil_school", "darkelf", "Veil School", line("de_veil_adept"))

# ---------------------------------------------------------------- fishmen --
add("reef_wall", "fishmen", "Reef Wall", formation(
    {"mods": {"role_defense": {"infantry": 1}, "shot_resist_pct": 0.05},
     "text": "Infantry gain +1 defense and the army takes 5% less damage from shots."}, "shield_wall", 0.25, "Shield Wall"),
    ["Thal of the Reef"])
add("deepvoice", "fishmen", "Deepvoice", art(), ["Oru Deepvoice"])
add("brineclaw_hooks", "fishmen", "Brineclaw Hooks", line("fm_hookcaster"), ["Keth Brineclaw"])
add("tideborn_spears", "fishmen", "Tideborn Spears", line("fm_brine_spear"), ["Vesh Tideborn"])
add("trench_lanterns", "fishmen", "Trench Lanterns", line("fm_lantern_acolyte"), ["Mara of the Trench"])
add("reefbreaker", "fishmen", "Reefbreaker", line("fm_tide_mauler"), ["Thunn Reefbreaker"])
add("who_reads", "fishmen", "Who Reads", pct("xp_pct", 0.06, 0.01, 8, "Experience"), ["Ilo Who Reads"])
add("hookhand", "fishmen", "Hookhand", pct("ranged_damage_pct", 0.04, 0.01, 8, "Ranged damage"), ["Sael Hookhand"])
add("brood_mother", "fishmen", "Brood-Mother", line("fm_shellback"), ["Mother Urrh", "Urrh the Fat"])
add("bluntjaw_crabs", "fishmen", "Bluntjaw Crabs", line("fm_mire_crab"), ["Chief Gorrok Bluntjaw"])
add("serpent_singer", "fishmen", "Serpent Singer", line("fm_coil_serpent"))
add("titan_waker", "fishmen", "Titan Waker", line("fm_trench_titan"))

DOC = (
    "Personal hero specialties. Every named hero has one (heroes: exact hero names, also tavern heroes in "
    "buildings.json); a hero not listed anywhere gets one of its faction's specialties, picked by a stable "
    "checksum of its name (HeroSpecialties.for_hero). mods use the hero modifier keys (src/heroes/hero_modifiers.gd). "
    "growth adds its mods once per `every` levels after level 1, at most `max` times. formations: "
    "{formation id: {unlock, bonus_pct}} for the pre-battle formations (BattleOrders). Regenerate with "
    "tools/build_hero_specialties.py."
)

out = {"_doc": DOC, "specialties": {}}
for sid, e in S.items():
    e.pop("creature", None)
    out["specialties"][sid] = e

with open(os.path.join(ROOT, "data", "hero_specialties.json"), "w") as f:
    f.write("{\n  \"_doc\": %s,\n  \"specialties\": {\n" % json.dumps(DOC))
    items = list(out["specialties"].items())
    for i, (sid, e) in enumerate(items):
        f.write("    %s: %s%s\n" % (json.dumps(sid), json.dumps(e), "," if i < len(items) - 1 else ""))
    f.write("  }\n}\n")
print("wrote %d specialties" % len(S))
