# Crowns of Caern factions and creature roster

## The world of Caern

Caern is the world shared by the eight rival powers. Its ruined strongholds, haunted forests, frozen frontiers and burning wastes are home to peoples with competing claims to dominion. No single crown rules them all.

The game title **Crowns of Caern** refers to these rival claims. Caern names the whole world, not one kingdom or faction.

Status: first full roster (2026-11). Eight playable factions with eight creature tiers each, every creature with an
upgraded form, and 32 wild creatures that belong to no faction. All names, lore and designs are original.
Data lives in `data/creatures/<faction>.json`, `data/factions.json` and `data/abilities.json`; this document
explains the intent behind the numbers. The roster tables at the end are generated from the data.

The Umbral Court fields swift infantry, cave riders, veil casters and dragons; its native terrain is rough.
The Abyssal Shoal combines shell-armoured troops, harpoons, tide magic and sea beasts; its native terrain is swamp.
The Umbral Court strikes first and breaks easily: its creatures have about 12% fewer hit points, +1 attack,
-1 defense and +1 initiative compared with the units they were adapted from. The Abyssal Shoal outlasts:
about 12% more hit points, +1 defense, -1 attack and -1 initiative. Both were then priced into the roster
(see *Balance method*).

## Design rules

1. **Variety without a dominant faction.** Factions differ in *how* they win (role mix, terrain, abilities,
   economy curve), not in how much they get for their money. Every creature is priced so that, at equal value
   and inside a mixed army, it wins about half its fights against the other factions' creatures of the same
   tier (see *Balance method*). The tests hold this line.
2. **Economy curves.** Each faction has a curve in `factions.json`:
   - **early** (Ashen Host, Frostmarch Clans): cheap tier 1-3 creatures, gold-only low tiers, high growth, few
     rare resources. Their tier 1-3 creatures are priced ~4 points of win rate better than par, their tier 6-8
     creatures ~4 points worse. Strong first two weeks, weaker top end.
   - **steady** (Aldmere Concord, Hollow Dominion, Thornwood Covenant, Umbral Court, Abyssal Shoal): priced at par across all tiers.
   - **late** (Sunken Forge): expensive, sturdy low tiers (~4 points below par) and the strongest top tiers
     (~4 points above), gated behind ore and three rare resources. A slow start that pays off in week 3+.
   Each faction also lists `key_resources`: creature costs may only use gold, wood, ore and those (validated),
   which steers what mines each faction fights for. Town building costs (towns workstream) follow the same curve.
3. **Role mixes define identity.** Some factions lack whole roles on purpose: Thornwood has no cavalry but
   four ranged tiers, the Forge and the Frostmarch have no flyers, the Frostmarch has no archers at all (only a
   shaman), the Hollow Dominion has no living morale. Each gap has an answer elsewhere in its roster.
4. **Upgrades: a small bonus at tier 1, a game changer at the top.** Each base creature has exactly one upgrade
   (`upgrade` / `upgrade_of`): about +12% hit points, +1 attack and defense (+2 at tier 6+), slightly more
   damage and +1 initiative, plus a new ability. The ability's weight scales with tier:
   - tiers 1-2: one minor trait (first strike, a 35-40% second strike, light poison, armour piercing);
   - tiers 3-5: a trait that changes how the unit is used (taunt, life drain, sunder, an army-wide aura, fear);
   - tiers 6-7: strong combinations (splash plus stun, first strike plus stun, regeneration plus riposte);
   - tier 8: two or three abilities that reshape a battle (double volleys with stun, first strike with armour
     shredding and an army-wide aura, splash with life drain and fear, splash with armour shredding).
   Upgrades are priced like everything else, so an upgraded stack is worth its premium, never a free win.
5. **Terrain affinity matters but never decides alone.** Every faction has one native terrain
   (+1 attack) and one hostile terrain (-1 attack); single creatures add small
   per-terrain bonuses. Desert is nobody's native or hostile terrain, so it is the neutral ground for balance.
6. **Every ability does something.** Abilities are data (`data/abilities.json`): an id plus parameters. The
   engine rejects unknown ids and parameters at validation, and each ability has a behavioural test.

## The six factions

Hero classes (three per faction) live in `data/hero_classes.json` and are designed in the hero workstream;
they key their synergies off the creature tags and roles described here. Planned classes: Concord Knight,
Ranger, Oracle; Ashen Warlock, Warlord, Tormentor; Hollow Necromancer, Gravewarden, Blightcaller; Thornwood
Grovewarden, Huntmaster, Thornspeaker; Forge Artificer, Ironmarshal, Runesmith; Frostmarch Thane, Reaver,
Frostcaller.

### The Aldmere Concord (humans) `concord`
Scarred, heavily armoured veterans of a dying feudal league. **Curve:** steady. **Native:** grassland.
**Hostile:** cinder wastes. **Key resources:** crystal, gems.
**Role mix:** the reference combined-arms army: braced pikes, shield wall, longbows, heavy lancers, lantern
priests, one flyer, one construct and, at tier 8, the Iron Margrave, a warlord-knight on a barded destrier.
**Plays as:** the anvil. Pikes and shields pin the enemy, lancers hit pinned enemies from the flank, healers
and inspire keep morale up. **Upgrade highlight:** the Iron Sovereign strikes first, strips 4 defense per blow
and gives every stack +2 attack; the Citadel Colossus (tier 7) taunts, ripostes and shields the army.

### The Ashen Host (demons) `ashen`
Monstrous, brutal and distinctly inhuman: slag-spawn, skinless hounds, hook-armed flayers, burning titans.
**Curve:** early. **Native:** cinder wastes. **Hostile:** snowfield. **Key resources:** sulfur, mercury.
**Role mix:** fast, fragile melee and one flyer; only one true ranged unit (plus the witch). Many units are
relentless (no retaliation) or burn; at tier 8 the Cinder Maw, a crawling furnace-mouth. **Plays as:** the
hammer that must win before it runs out of bodies. **Upgrade highlight:** the Maw of Ruin swallows two stacks
at once, heals on what it devours and terrifies; the Pyre Sovereign (tier 7) rises again from its ashes.

### The Hollow Dominion (undead) `hollow`
Genuinely horrifying dead: bloated shamblers, many-jointed gravecrawlers, a flying carcass. **Curve:** steady.
**Native:** swamp. **Hostile:** grassland. **Key resources:** mercury, gems.
**Role mix:** slow infantry, one archer, one fast crawler, two flyers, a raiser of the dead, heavy abominations.
Every unit is **mindless**: morale is always zero, so no leadership bonus but also no faltering and immunity to
fear. **Plays as:** attrition. Corpse weavers sew fallen undead back into the line, upper tiers drain life and
regenerate. **Upgrade highlight:** the Rotwing Sovereign drains 40% of its damage and costs the enemy 2 morale.

### The Thornwood Covenant (forest) `thornwood`
Gaunt, bark-skinned hunters, druids and walking trees of the deep wood. **Curve:** steady.
**Native:** forest. **Hostile:** cinder wastes. **Key resources:** wood, gems.
**Role mix:** **mostly ranged** (four of eight tiers shoot, including the tier 8 Wyrdthorn Mother) behind
regenerating wardens and taunting ancients; one flyer; **no cavalry**. **Plays as:** a fortress of bows. Weak
if cavalry and flyers reach the back line, devastating if the treeline holds. **Upgrade highlight:** the
Wyrdthorn Matriarch fires two volleys a turn, each with a chance to pin the target in thorns (stun).

### The Sunken Forge (deep folk and constructs) `forge`
Soot-black smith-clans from under the mountains and the riveted constructs they build. **Curve:** late.
**Native:** rocky highland. **Hostile:** swamp. **Key resources:** mercury, crystal, sulfur (and lots of ore).
**Role mix:** slow, armoured infantry with shield walls, crossbows, golems, clockwork boar cavalry, a siege
bombard; **no flyers**. **Plays as:** slow start, unstoppable end. Low tiers are pricey and only average, the
top three tiers are the best in the game per value but need rare resources. **Upgrade highlight:** the
Worldforge Engine's blows hit two stacks, strip 4 defense per hit and ignore 30% of armour.

### The Frostmarch Clans (northern raiders) `frostmarch`
Fur-cloaked raiders, berserkers and shaggy war-beasts from the frozen north. **Curve:** early.
**Native:** snowfield. **Hostile:** cinder wastes. **Key resources:** crystal (barely any).
**Role mix:** cheap, numerous infantry, three cavalry tiers, giants and a wyrm; **no archers and no flyers**
(only the frost shaman hexes from range). Almost everything costs gold only and grows fast. **Plays as:** rush.
Swamp the map in week one, trade bodies efficiently, win before the late factions come online.
**Trait:** the war-band rides out two strong: a Frostmarch player starts a standard game with two heroes (the
second is the clan tavern's next hero with its tavern army), every other faction with one (`starting_heroes`).
**Upgrade highlight:** the Ancient Winter Wyrm's freezing breath engulfs two stacks, stuns, and frightens.

## Map mechanics

Each faction also plays differently on the adventure map (`data/faction_mechanics.json`; rules in
`src/game/faction_mechanics.gd`, details in DESIGN.md "Living maps"): the Concord levies recruits from its
mines (Levy of the Shires), the Ashen Host plunders what it captures (Brand and Plunder), the Hollow Dominion
raises the slain (Grave Harvest), the Thornwood walks its forests (Wildwalk), the Sunken Forge travels the
deep roads between its holdings (Deep Roads), the Frostmarch rides on after a victory (Feast of Victory), the
Umbral Court watches through spies (Whisper Web) and the Abyssal Shoal rides the water (Tidebound).

## Ultimate buildings

Each town has one very expensive late building (category `ultimate`, needs the tier 8 dwelling and the
treasury) that upgrades every creature of that faction in its owner's armies. Numbers are tuned so a late army
with it wins about 70-85% of equal-gold fights against the same army without it.

| Faction | Building | Upgrade | Effect |
|---|---|---|---|
| Concord | Reliquary of Holy Arms | Holy Weapons | +2 attack, +1 morale, blows ignore 20% of defense |
| Ashen Host | Brand-Pit of the Abyss | Hellbrand | +10% damage, wounds burn for 15% more next round |
| Hollow Dominion | The Undying Choir | Deathless Hunger | +10% hit points, drains 20% of damage dealt |
| Thornwood | Heart of the Mother Tree | Thornblood | +2 defense, +15% ranged damage |
| Sunken Forge | The Deep King's Anvil | Runeplate | +2 defense, +10% hit points, -10% damage from shots |
| Frostmarch | Hall of the Endless Feast | Wintersblood | +2 attack, +1 initiative, +5% damage a round (max +20%), morale never below 0 |

## Wild creatures

The 32 wild creatures (faction `wilds`, no town, no upgrades) guard mines, treasure and passes. They span all
eight tiers and every terrain, with terrain affinities that make them dangerous at home (dune scuttlers and
the dune wurm in desert, bog lurkers and serpents in swamp, wights in snow, cinder wraiths in the wastes).
They reuse the same ability vocabulary so a player learns one rule set, and they are priced on the same
scale so map generation and rewards can value them by cost.

## Abilities

| Ability | Parameters | Effect |
|---|---|---|
| Ranged (`ranged`) | - | Shoots from the back line from round 1; weak when forced into melee. |
| Flying (`flying`) | - | Reaches the enemy in round 1 and prefers to dive on the back line. In the air between strikes: ground melee without reach cannot attack it until it lands to strike. |
| Reach (`reach`) | - | Long spears, great size or a long tail: can strike flyers in the air. |
| Charge (`charge`) | bonus=0.3 | First melee attack of the battle deals +bonus damage. |
| Brace (`brace`) | - | Negates an incoming charge and retaliates harder against it. |
| Shield Wall (`shield_wall`) | ranged_reduction=0.3 | Takes less damage from shots. |
| Guardian (`guardian`) | screen=0.1 | Makes it harder for enemy flankers to slip past the front line. |
| Heal (`heal`) | per_creature=5 | Restores hit points to the most wounded ally (only allies with tag, if set), raising fallen creatures. |
| Inspire (`inspire`) | morale=1 | +morale to the whole army (strongest source counts). |
| Relentless (`relentless`) | - | Targets cannot retaliate. |
| Curse (`curse`) | damage_mult=0.8 | Shot targets deal reduced damage for the rest of the round. |
| Unwavering (`unwavering`) | - | Morale can never drop below zero. |
| Mindless (`mindless`) | - | Morale is always exactly zero: never surges, never falters, immune to fear. |
| First Strike (`first_strike`) | - | When attacked in melee, retaliates before the attacker's blow lands. |
| Riposte (`riposte`) | - | Retaliates against every melee attack, not just the first each round. |
| Double Strike (`double_strike`) | mult=0.5 | Each attack or shot is followed by a second one at mult damage (no extra retaliation). |
| Splash (`splash`) | fraction=0.3 | Each attack or shot also hits a second enemy stack for fraction of the damage. |
| Cleave (`cleave`) | targets=1, fraction=0.5 | Each melee blow sweeps on into up to targets other stacks within reach for fraction of the damage. |
| Breath (`breath`) | fraction=0.5 | Each attack rolls past its target into a stack behind it (archers and supporters first) for fraction of the damage. |
| Poison (`poison`) | fraction=0.25 | fraction of damage dealt is dealt again at the start of the next round, ignoring defense. |
| Life Drain (`life_drain`) | fraction=0.25 | Heals itself for fraction of damage dealt, raising its own fallen. |
| Regenerate (`regenerate`) | amount=10 | Restores amount hit points at the start of each round (never above the top creature's maximum). |
| Stun (`stun`) | chance=0.15 | Each hit has chance to make the target lose its next action. |
| Evasion (`evasion`) | chance=0.2 | chance to avoid an incoming attack or shot entirely. |
| Sunder (`sunder`) | amount=2, cap=6 | Each hit permanently lowers the target's defense by amount (at most cap in total). |
| Armor Pierce (`armor_pierce`) | fraction=0.3 | Ignores fraction of the target's defense. |
| Momentum (`momentum`) | per_round=0.05, cap=0.3 | +per_round damage for every round after the first (up to cap). |
| Taunt (`taunt`) | chance=0.3 | Enemy melee attackers are drawn onto this stack with this chance. |
| Fear (`fear`) | morale=1 | -morale to the whole enemy army (strongest source counts; mindless units are immune). |
| Aura (`aura`) | attack=0, defense=0, initiative=0 | Every allied stack (including itself) gains these stats. Auras of the same stat do not stack; the strongest counts. |
| Rebirth (`rebirth`) | fraction=0.5 | Once per battle, when destroyed, fraction of its starting number rises again. |
| Skirmisher (`skirmisher`) | - | Ranged unit that fights at full strength when engaged in melee. |

## Balance method

Concord and Ashen tiers 1-7 and the three core wild creatures (thornwolf, bog lurker, crag slinger) are tuned by
the combat workstream against `tests/unit/test_combat_balance.gd`. They are fixed *anchors*: every other price
is set relative to them, which also pins each tier's price level.

`tools/roster_report.gd` prices the roster:

- Every creature is valued in gold: wood and ore count 100 each, rare resources 250 each.
- *Efficiency* of a creature = its average win rate against every other creature of the same tier and kind
  (base or upgraded) at equal value, both sides fielding the creature plus an identical plain-infantry escort,
  on neutral desert, alternating attacker and defender. 50% is par; the target moves ±4 points with the
  faction's economy curve.
- `calibrate` iterates price changes until efficiency is near target, then rewrites the gold part of each cost
  (rare resource requirements are design decisions and stay fixed). Anchors never move.
- `factions` then plays whole equal-value armies against each other (early game: tiers 1-4 at 12,000; late game:
  tiers 1-8 at 90,000) and nudges each faction's non-anchor prices until no faction dominates. Whole armies
  carry synergies duels miss (an all-ranged line behind taunting trees, an army-wide aura). The `report` mode also prints faction
  parity matrices (equal-value full armies, early and late game) and upgrade value (upgraded vs base at equal
  value).
- The combat workstream's `tools/fair_cost.gd` and `tests/unit/test_combat_balance.gd` give an independent
  check; both must agree before costs change.

```sh
godot --headless --path . --script res://tools/roster_report.gd -- calibrate 8 80
godot --headless --path . --script res://tools/roster_report.gd -- factions 4 60 0.25
godot --headless --path . --script res://tools/roster_report.gd -- report 100 res://reports/roster_report.md
```

Current result after the eight-faction pass (100 fights per pairing, average win rate against the other
seven factions; `roster_report.gd -- parity <max tier> <budget> 100`):

| Faction | Early (tiers 1-4, 12,000) | Mid (tiers 1-6, 8,000 / 10,000 / 12,000) | Late (tiers 1-8, 90,000) |
|---|---|---|---|
| Aldmere Concord | 37% | 35% / 36% / 32% | 39% |
| Ashen Host | 37% | 73% / 29% / 40% | 34% |
| Hollow Dominion | 49% | 43% / 65% / 51% | 45% |
| Thornwood Covenant | 57% | 41% / 37% / 56% | 59% |
| Sunken Forge | 53% | 56% / 28% / 71% | 54% |
| Frostmarch Clans | 55% | 61% / 72% / 57% | 54% |
| Umbral Court | 62% | 53% / 66% / 43% | 58% |
| Abyssal Shoal | 50% | 38% / 67% / 49% | 57% |

Single seeds and budgets swing widely, so the pass tuned against three independent seed sets and every budget
from 8,000 to 12,000: averaged that way, every faction sits between 40% and 62% in every phase. The two new
factions came in far apart (Umbral Court 65% late because its tier 8 drake cost less than its tier 7 guard;
Abyssal Shoal 21-42% and 28% late), so their prices were recalibrated with
`roster_report.gd -- calibrate 6 60 only=darkelf,fishmen` and `-- factions 5 60 0.5 only=darkelf,fishmen`,
which keep every other creature fixed, followed by small hand nudges: Hollow tiers 1-6 dearer and tiers 7-8
cheaper, Thornwood tiers 7-8 dearer, Frostmarch's shaman and aurochs dearer.

`tests/unit/test_roster_balance.gd` keeps all eight factions' averages between 25% and 75% in the early and late
phases, and between 35% and 65% in the mid phase averaged over five budgets (8,000 to 12,000). It also checks that upgrades
are fairly priced on average.

**Small armies are noisy.** At 8,000-12,000 gold a tier 5-6 stack holds one or two creatures, so a few gold
of price or budget decides whether a stack has 1 or 2 creatures, and single matchups swing by 20-30 points.
Judge a faction by a spread of budgets, never one point. The Thornwood Covenant was the one faction low across
the spread (35-45% for tiers 1-6 in the combat workstream's balanced army) and high late (about 60%): ranged
lines grow stronger with army size, so it was weak small and strong big. After PR #23 its line got cheaper
(Barkhide Warden 95 to 80) and its archers and top tiers dearer (Briar Huntress 245 to 265, Gloomwing Strix 635
to 690, Rootbound Ancient 1685 to 1850, Wyrdthorn Mother 3200 to 3500). Thornwood keeps its four ranged tiers
and no cavalry, but now sits at about 42-51% for tiers 1-6 at 8,000-12,000 (balanced army) and 46-57% in the
other phases.

Known limits: auto-combat is steep (a 10% edge wins most fights), so parity is a band, not a point; a few
exotic units (rebirth, taunt) are hard to price in small stacks; and economy-curve effects only show fully once
towns price their buildings by the same curves. The measured parity above does not yet show the intended
curves (the Forge is strong early, the Frostmarch strong late): the curve targets move single-creature prices
by only ±4 points, and the army-level pass flattens them. The real early/late difference comes from building
costs, growth and rare-resource gating, which the towns workstream sets per curve.

## Roster

Columns: tier, unit, role, hit points, attack/defense, damage, speed/initiative, growth, cost, abilities.
Upgrades follow their base in *italics*.

### The Aldmere Concord

| T | Unit | Role | HP | Att/Def | Dmg | Spd/Ini | Grw | Cost | Abilities |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Pike Militia** | infantry | 10 | 4/6 | 1-3 | 4/4 | 14 | 85 | reach, brace |
| 1 | *Pike Veteran* | infantry | 11 | 5/7 | 1-4 | 4/5 | 14 | 105 | reach, brace, first_strike |
| 2 | **Longbowman** | ranged | 10 | 6/3 | 2-4 | 4/6 | 9 | 130 | ranged |
| 2 | *Warbow Sergeant* | ranged | 11 | 7/4 | 2-5 | 4/7 | 9 | 210 | ranged, double_strike(0.4) |
| 3 | **Shieldwarden** | infantry | 30 | 6/12 | 3-6 | 4/4 | 6 | 230 | shield_wall(0.35), guardian(0.15) |
| 3 | *Bulwark Sworn* | infantry | 34 | 7/13 | 3-7 | 4/5 | 6 | 325 | shield_wall(0.35), guardian(0.15), taunt(0.35) |
| 4 | **Lancer** | cavalry | 35 | 11/8 | 5-9 | 8/8 | 4 | 400 | charge(0.4) |
| 4 | *Oathbound Lancer* | cavalry | 39 | 12/9 | 6-10 | 8/9 | 4 | 620 | charge(0.4), sunder(2, 6) |
| 5 | **Lightbearer** | support | 30 | 8/8 | 3-6 | 5/7 | 3 | 450 + 1 crystal | heal(6), inspire(1) |
| 5 | *Dawn Confessor* | support | 34 | 9/9 | 3-7 | 5/8 | 3 | 500 + 1 crystal | heal(6), inspire(1), aura(1) |
| 6 | **Sunhawk Rider** | flyer | 60 | 14/11 | 10-16 | 10/10 | 2 | 950 | flying |
| 6 | *Sunhawk Paladin* | flyer | 67 | 16/13 | 11-18 | 10/11 | 2 | 1045 | flying, first_strike, stun(0.2) |
| 7 | **Bastion Colossus** | heavy | 160 | 18/17 | 20-32 | 5/5 | 1 | 2700 + 2 gems | reach, unwavering |
| 7 | *Citadel Colossus* | heavy | 179 | 20/19 | 22-35 | 5/6 | 1 | 2975 + 2 gems | reach, unwavering, taunt(0.5), riposte, aura(2, 1) |
| 8 | **Iron Margrave** | cavalry | 180 | 23/18 | 29-46 | 8/8 | 1 | 2335 + 2 crystal + 2 gems | charge(0.5) |
| 8 | *Iron Sovereign* | cavalry | 202 | 25/20 | 32-51 | 8/9 | 1 | 2960 + 2 crystal + 2 gems | charge(0.5), first_strike, sunder(4, 12), aura(2) |

### The Ashen Host

| T | Unit | Role | HP | Att/Def | Dmg | Spd/Ini | Grw | Cost | Abilities |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Cinderling** | infantry | 7 | 5/3 | 1-3 | 6/7 | 16 | 70 | - |
| 1 | *Seared Cinderling* | infantry | 8 | 6/4 | 1-4 | 6/8 | 16 | 80 | poison(0.2) |
| 2 | **Scorchhound** | cavalry | 18 | 8/5 | 2-5 | 8/9 | 8 | 145 | charge(0.3) |
| 2 | *Hellmaw Hound* | cavalry | 20 | 9/6 | 2-6 | 8/10 | 8 | 180 | charge(0.3), double_strike(0.4) |
| 3 | **Brimstone Hurler** | ranged | 14 | 8/4 | 3-5 | 4/5 | 6 | 230 | ranged |
| 3 | *Brimstone Bombardier* | ranged | 16 | 9/5 | 3-6 | 4/6 | 6 | 255 | ranged, splash(0.3) |
| 4 | **Flayer** | infantry | 40 | 11/9 | 5-8 | 6/7 | 4 | 410 | relentless |
| 4 | *Exalted Flayer* | infantry | 45 | 12/10 | 6-9 | 6/8 | 4 | 705 | relentless, life_drain(0.25) |
| 5 | **Ash Witch** | support | 28 | 9/7 | 4-6 | 5/8 | 3 | 460 + 1 mercury | ranged, curse(0.75) |
| 5 | *Ash Matriarch* | support | 31 | 10/8 | 4-7 | 5/9 | 3 | 510 + 1 mercury | ranged, curse(0.75), fear(1) |
| 6 | **Gorgewing** | flyer | 60 | 16/9 | 9-15 | 11/11 | 2 | 880 | flying |
| 6 | *Gorgewing Matron* | flyer | 67 | 18/11 | 10-16 | 11/12 | 2 | 970 | flying, breath(0.4), fear(1) |
| 7 | **Pyre Titan** | heavy | 175 | 18/16 | 22-36 | 6/5 | 1 | 2900 + 2 sulfur | reach, unwavering |
| 7 | *Pyre Sovereign* | heavy | 196 | 20/18 | 24-40 | 6/6 | 1 | 4490 + 2 sulfur | reach, unwavering, rebirth(0.5), splash(0.4) |
| 8 | **Cinder Maw** | heavy | 239 | 21/23 | 29-47 | 5/4 | 1 | 2400 + 3 sulfur + 2 mercury | reach, relentless, unwavering |
| 8 | *Maw of Ruin* | heavy | 268 | 23/25 | 32-52 | 5/5 | 1 | 4715 + 3 sulfur + 2 mercury | reach, relentless, unwavering, splash(0.6), life_drain(0.3), fear(2) |

### The Hollow Dominion

| T | Unit | Role | HP | Att/Def | Dmg | Spd/Ini | Grw | Cost | Abilities |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Shambler** | infantry | 9 | 4/4 | 1-3 | 3/3 | 14 | 65 | mindless |
| 1 | *Rotting Shambler* | infantry | 10 | 5/5 | 1-4 | 3/4 | 14 | 85 | mindless, poison(0.2) |
| 2 | **Marrow Archer** | ranged | 10 | 6/4 | 2-4 | 4/6 | 9 | 145 | ranged, mindless |
| 2 | *Marrow Deadeye* | ranged | 11 | 7/5 | 2-5 | 4/7 | 9 | 200 | ranged, mindless, armor_pierce(0.3) |
| 3 | **Gravecrawler** | cavalry | 24 | 8/6 | 3-7 | 8/8 | 7 | 240 | mindless |
| 3 | *Gravecrawler Brood* | cavalry | 27 | 9/7 | 3-8 | 8/9 | 7 | 330 | mindless, stun(0.15) |
| 4 | **Wailing Shade** | flyer | 31 | 10/8 | 5-8 | 9/9 | 5 | 215 + 1 mercury | flying, mindless, evasion(0.2) |
| 4 | *Dirge Shade* | flyer | 35 | 11/9 | 6-9 | 9/10 | 5 | 335 + 1 mercury | flying, mindless, evasion(0.2), fear(1) |
| 5 | **Corpse Weaver** | support | 37 | 9/10 | 5-8 | 5/7 | 4 | 220 + 1 mercury | heal(8, undead), mindless |
| 5 | *Charnel Weaver* | support | 41 | 10/11 | 6-9 | 5/8 | 4 | 480 + 1 mercury | heal(8, undead), mindless, aura(1) |
| 6 | **Gibbet Knight** | heavy | 86 | 14/15 | 11-16 | 4/4 | 3 | 765 + 1 gems | mindless |
| 6 | *Gibbet Lord* | heavy | 96 | 16/17 | 12-18 | 4/5 | 3 | 1110 + 1 gems | mindless, life_drain(0.3) |
| 7 | **Charnel Hulk** | heavy | 130 | 17/18 | 16-26 | 4/4 | 2 | 2090 + 2 mercury | reach, mindless, regenerate(40) |
| 7 | *Charnel Behemoth* | heavy | 146 | 19/20 | 18-29 | 4/5 | 2 | 2305 + 2 mercury | reach, mindless, regenerate(40), cleave(0.4) |
| 8 | **Rotwing Leviathan** | flyer | 162 | 23/18 | 26-42 | 9/9 | 1 | 1705 + 3 mercury + 2 gems | flying, mindless |
| 8 | *Rotwing Sovereign* | flyer | 181 | 25/20 | 29-46 | 9/10 | 1 | 2350 + 3 mercury + 2 gems | flying, mindless, life_drain(0.4), fear(2) |

### The Thornwood Covenant

| T | Unit | Role | HP | Att/Def | Dmg | Spd/Ini | Grw | Cost | Abilities |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Thorn Skulker** | ranged | 6 | 4/3 | 1-3 | 4/6 | 14 | 130 | ranged |
| 1 | *Thorn Stalker* | ranged | 7 | 5/4 | 1-4 | 4/7 | 14 | 165 | ranged, poison(0.25) |
| 2 | **Barkhide Warden** | infantry | 14 | 6/6 | 2-4 | 4/5 | 9 | 80 | guardian(0.1) |
| 2 | *Barkhide Sentinel* | infantry | 16 | 7/7 | 2-5 | 4/6 | 9 | 125 | guardian(0.1), regenerate(6) |
| 3 | **Briar Huntress** | ranged | 16 | 7/5 | 3-5 | 4/6 | 7 | 265 | ranged |
| 3 | *Briar Deadshot* | ranged | 18 | 8/6 | 3-6 | 4/7 | 7 | 375 | ranged, double_strike(0.5) |
| 4 | **Rootbinder** | support | 27 | 8/8 | 4-6 | 5/7 | 5 | 270 + 1 wood | heal(7) |
| 4 | *Rootbinder Elder* | support | 30 | 9/9 | 4-7 | 5/8 | 5 | 345 + 1 wood | heal(7), aura(1) |
| 5 | **Gloomwing Strix** | flyer | 41 | 12/10 | 7-11 | 9/9 | 4 | 690 + 1 gems | flying |
| 5 | *Gloomwing Shrike* | flyer | 46 | 13/11 | 8-12 | 9/10 | 4 | 1450 + 1 gems | flying, first_strike, evasion(0.15) |
| 6 | **Spore Lobber** | ranged | 48 | 14/9 | 9-14 | 4/6 | 3 | 1100 + 2 wood | ranged, splash(0.25) |
| 6 | *Plague Lobber* | ranged | 54 | 16/11 | 10-15 | 4/7 | 3 | 1465 + 2 wood | ranged, splash(0.25), poison(0.3) |
| 7 | **Rootbound Ancient** | heavy | 134 | 17/18 | 17-27 | 3/3 | 2 | 1850 + 3 wood + 1 gems | reach, guardian(0.2), taunt(0.3) |
| 7 | *Rootbound Patriarch* | heavy | 150 | 19/20 | 19-30 | 3/4 | 2 | 3815 + 3 wood + 1 gems | reach, guardian(0.2), taunt(0.3), riposte, regenerate(50) |
| 8 | **Wyrdthorn Mother** | ranged | 150 | 21/14 | 24-39 | 4/6 | 1 | 3500 + 3 wood + 3 gems | ranged |
| 8 | *Wyrdthorn Matriarch* | ranged | 168 | 23/16 | 26-43 | 4/7 | 1 | 4800 + 3 wood + 3 gems | ranged, double_strike(0.7), stun(0.2) |

### The Sunken Forge

| T | Unit | Role | HP | Att/Def | Dmg | Spd/Ini | Grw | Cost | Abilities |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Forge Thrall** | infantry | 9 | 4/4 | 1-3 | 4/4 | 14 | 65 | - |
| 1 | *Ironclad Thrall* | infantry | 10 | 5/5 | 1-4 | 4/5 | 14 | 75 | shield_wall(0.2) |
| 2 | **Rivet Crossbowman** | ranged | 11 | 6/4 | 2-4 | 4/6 | 9 | 130 | ranged |
| 2 | *Rivet Arbalist* | ranged | 12 | 7/5 | 2-5 | 4/7 | 9 | 180 | ranged, armor_pierce(0.3) |
| 3 | **Anvil Guard** | infantry | 25 | 7/8 | 3-6 | 4/5 | 7 | 90 + 1 ore | shield_wall(0.3) |
| 3 | *Anvil Sworn* | infantry | 28 | 8/9 | 3-7 | 4/6 | 7 | 140 + 1 ore | shield_wall(0.3), riposte |
| 4 | **Slag Golem** | heavy | 46 | 9/10 | 6-9 | 4/4 | 5 | 200 + 2 ore | mindless |
| 4 | *Furnace Golem* | heavy | 52 | 10/11 | 7-10 | 4/5 | 5 | 310 + 2 ore | mindless, taunt(0.35) |
| 5 | **Cinder Engineer** | support | 39 | 9/10 | 5-8 | 5/7 | 4 | 445 + 1 mercury | heal(8) |
| 5 | *Master Engineer* | support | 44 | 10/11 | 6-9 | 5/8 | 4 | 770 + 1 mercury | heal(8), aura(1) |
| 6 | **Ironhoof Charger** | cavalry | 73 | 15/12 | 12-18 | 8/8 | 3 | 820 + 2 ore + 1 mercury | charge(0.35) |
| 6 | *Ironhoof Warboar* | cavalry | 82 | 17/14 | 13-20 | 8/9 | 3 | 1195 + 2 ore + 1 mercury | charge(0.35), sunder(3, 9) |
| 7 | **Thunder Bombard** | ranged | 77 | 17/11 | 15-24 | 3/4 | 2 | 1460 + 2 ore + 2 sulfur | ranged, splash(0.4) |
| 7 | *Doom Bombard* | ranged | 86 | 19/13 | 16-26 | 3/5 | 2 | 1610 + 2 ore + 2 sulfur | ranged, splash(0.4), stun(0.25) |
| 8 | **Molten Engine** | heavy | 257 | 21/23 | 31-51 | 4/4 | 1 | 3450 + 4 ore + 2 mercury + 2 crystal | reach, mindless, unwavering |
| 8 | *Worldforge Engine* | heavy | 288 | 23/25 | 34-56 | 4/5 | 1 | 4240 + 4 ore + 2 mercury + 2 crystal | reach, mindless, unwavering, cleave(0.6), sunder(4, 12), armor_pierce(0.3) |

### The Frostmarch Clans

| T | Unit | Role | HP | Att/Def | Dmg | Spd/Ini | Grw | Cost | Abilities |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Clan Raider** | infantry | 8 | 4/4 | 1-3 | 6/6 | 16 | 65 | - |
| 1 | *Blooded Raider* | infantry | 9 | 5/5 | 1-4 | 6/7 | 16 | 75 | momentum(0.04, 0.2) |
| 2 | **Rimefang Hound** | cavalry | 14 | 7/4 | 2-4 | 8/8 | 11 | 115 | charge(0.25) |
| 2 | *Rimefang Packleader* | cavalry | 16 | 8/5 | 2-5 | 8/9 | 11 | 165 | charge(0.25), double_strike(0.35) |
| 3 | **Oathless Berserker** | infantry | 22 | 7/4 | 3-5 | 6/7 | 7 | 205 | relentless |
| 3 | *Bloodfrenzy Berserker* | infantry | 25 | 8/5 | 3-6 | 6/8 | 7 | 280 | relentless, life_drain(0.2) |
| 4 | **Tusk Rider** | cavalry | 32 | 10/8 | 5-8 | 8/8 | 5 | 355 | charge(0.35) |
| 4 | *Tusk Chieftain* | cavalry | 36 | 11/9 | 6-9 | 8/9 | 5 | 525 | charge(0.35), sunder(2, 6) |
| 5 | **Frost Shaman** | support | 35 | 9/10 | 5-7 | 5/7 | 4 | 595 | ranged, curse(0.8) |
| 5 | *Storm Shaman* | support | 39 | 10/11 | 6-8 | 5/8 | 4 | 1030 | ranged, curse(0.8), stun(0.15), aura(1) |
| 6 | **Rimeback Aurochs** | cavalry | 75 | 15/12 | 10-16 | 8/8 | 3 | 1030 | charge(0.4) |
| 6 | *Rimeback Stampede* | cavalry | 84 | 17/14 | 11-18 | 8/9 | 3 | 1295 | charge(0.4), cleave(0.4) |
| 7 | **Cairn Giant** | heavy | 124 | 17/18 | 16-25 | 4/4 | 2 | 1815 + 1 ore | reach, regenerate(20) |
| 7 | *Cairn Warlord* | heavy | 139 | 19/20 | 18-28 | 4/5 | 2 | 2010 + 1 ore | reach, regenerate(20), stun(0.2), cleave(0.3) |
| 8 | **Winter Wyrm** | heavy | 222 | 21/23 | 27-44 | 6/6 | 1 | 3170 + 2 crystal | reach, unwavering |
| 8 | *Ancient Winter Wyrm* | heavy | 249 | 23/25 | 30-48 | 6/7 | 1 | 3500 + 2 crystal | reach, unwavering, breath(0.6), stun(0.25), fear(1) |

### Untamed Wilds

| T | Unit | Role | HP | Att/Def | Dmg | Spd/Ini | Grw | Cost | Abilities |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Dune Scuttler** | cavalry | 9 | 4/4 | 1-3 | 8/8 | 14 | 80 | - |
| 1 | **Lost Pilgrims** | infantry | 8 | 3/2 | 1-3 | 5/5 | 20 | 65 | - |
| 1 | **Moss Creeper** | infantry | 9 | 4/4 | 1-3 | 3/3 | 14 | 75 | regenerate(3) |
| 1 | **Plague Rats** | infantry | 6 | 4/4 | 1-3 | 6/7 | 14 | 80 | poison(0.25) |
| 2 | **Carrion Flock** | flyer | 11 | 7/4 | 2-4 | 9/9 | 9 | 125 | flying, evasion(0.15) |
| 2 | **Corpse Light** | flyer | 9 | 7/4 | 2-4 | 9/9 | 9 | 135 | flying, evasion(0.3), mindless |
| 2 | **Crag Slinger** | ranged | 9 | 6/3 | 2-4 | 5/6 | 8 | 125 | ranged |
| 2 | **Road Cutthroat** | infantry | 15 | 6/6 | 2-4 | 5/5 | 9 | 130 | relentless |
| 2 | **Thornwolf** | cavalry | 20 | 8/5 | 3-6 | 9/9 | 6 | 190 | charge(0.25) |
| 3 | **Deserter Crossbows** | ranged | 17 | 7/5 | 3-5 | 4/6 | 7 | 240 | ranged |
| 3 | **Gloom Panther** | cavalry | 24 | 8/6 | 3-7 | 8/8 | 7 | 270 | evasion(0.2) |
| 3 | **Marsh Hag** | support | 19 | 6/6 | 2-4 | 5/7 | 7 | 220 | ranged, curse(0.8) |
| 3 | **Rime Wight** | infantry | 24 | 7/8 | 3-6 | 5/5 | 7 | 205 | mindless, life_drain(0.15) |
| 3 | **Sand Reaver** | cavalry | 24 | 8/6 | 3-7 | 8/8 | 7 | 255 | charge(0.3) |
| 3 | **Shrieking Harpy** | flyer | 22 | 8/6 | 3-6 | 9/9 | 7 | 300 | flying, relentless |
| 3 | **Tomb Scarabs** | infantry | 24 | 7/9 | 3-6 | 5/5 | 7 | 225 | poison(0.2) |
| 4 | **Ashscale Basilisk** | infantry | 34 | 9/10 | 5-8 | 5/5 | 5 | 340 | stun(0.2) |
| 4 | **Bog Lurker** | infantry | 45 | 10/12 | 4-8 | 3/3 | 3 | 380 | - |
| 4 | **Cave Stalker** | infantry | 34 | 9/10 | 5-8 | 5/5 | 5 | 360 | first_strike |
| 4 | **Salt Witch** | support | 27 | 8/8 | 4-6 | 5/7 | 5 | 360 | heal(7) |
| 4 | **Steppe Centaur** | ranged | 28 | 9/6 | 4-7 | 8/8 | 5 | 485 | ranged, skirmisher |
| 5 | **Barrow Revenant** | infantry | 46 | 11/12 | 7-11 | 5/5 | 4 | 590 | mindless, fear(1) |
| 5 | **Cinder Wraith** | flyer | 41 | 12/10 | 7-11 | 9/9 | 4 | 710 | flying, poison(0.3), mindless |
| 5 | **Hill Troll** | heavy | 60 | 11/13 | 8-12 | 4/4 | 4 | 1055 | regenerate(25) |
| 5 | **Ogre Mauler** | infantry | 55 | 11/12 | 7-11 | 5/5 | 4 | 695 | cleave(0.3) |
| 5 | **Ruin Sentinel** | heavy | 60 | 11/13 | 8-12 | 3/3 | 4 | 790 | mindless, shield_wall(0.4) |
| 6 | **Bog Serpent** | heavy | 86 | 14/15 | 11-16 | 4/4 | 3 | 1085 | riposte |
| 6 | **Frost Drake** | flyer | 59 | 15/12 | 10-15 | 9/9 | 3 | 905 | flying, breath(0.3) |
| 6 | **Venom Wyvern** | flyer | 59 | 15/12 | 10-15 | 9/9 | 3 | 1010 | flying, poison(0.35) |
| 7 | **Dune Wurm** | heavy | 130 | 17/18 | 16-26 | 4/4 | 2 | 1825 | reach, splash(0.4) |
| 7 | **Hill Giant** | heavy | 130 | 17/18 | 16-26 | 4/4 | 2 | 1840 | reach, sunder(3, 9) |
| 8 | **Primordial Wyrm** | flyer | 162 | 23/18 | 26-42 | 9/9 | 1 | 3375 | flying, breath(0.5), fear(1) |

