# Crowns of Caern: Phase 0 design and architecture

Status: Phase 0 complete, first vertical slice implemented, Phase 2 economy and towns implemented (2026-11-06).
Scope reference: the original project brief (sections 1–17). Art direction: [ART_BIBLE.md](ART_BIBLE.md).

## 1. Assessment of the project and stack

Crowns of Caern (working title Reignem) is an original fantasy turn-based strategy game in the classic adventure-map genre: heroes explore,
gather, build towns and lead armies, with **automatic, deterministic-under-seed combat** instead of a tactical
battlefield, richer terrain and army synergies, and **campaign-long hero progression**.

The setting is **Caern**, the world shared by the eight rival powers; see [FACTIONS.md](FACTIONS.md).

**Engine choice: Godot 4.5 (GDScript). Confirmed.**

| | Godot 4 | Phaser 3 | Unity |
|---|---|---|---|
| 2D tile maps, autotiling, A* | Built in (TileMapLayer, terrain sets, AStarGrid2D) | TileMap via Tiled, A* via plugin | Tilemap built in, A* via package |
| Headless tests / simulation | `--headless --script`, no editor needed | Node runner for logic only | Batchmode, heavy |
| Desktop export | Native, small binaries | Needs Electron/Tauri wrapper | Native |
| Web / mobile | Web (WASM) and mobile exports | Best-in-class web | Good, heavier |
| AI-agent friendliness | Text scenes/resources, plain-text scripts, one 100 MB binary, MIT | Plain JS, very agent friendly | Binary assets, licence fees, slow CLI |
| Licence | MIT | MIT | Proprietary |

Phaser would only win if web were the primary target; Unity adds weight and licence risk for no 2D gain.
Godot gives a text-only project that an agent can build, test and screenshot entirely from the command line
(verified in this repo: tests run headless; screenshots run under Xvfb with the OpenGL renderer).

## 2. Architecture

Principle: **rules are plain `RefCounted` classes that never touch nodes**; the UI is a thin view that calls
commands and redraws. Everything a test, the AI or a balance tool needs runs headless.

```
data/                 JSON definitions (terrain, resources, factions, creatures, classes, skills, combat tuning, maps)
src/core/             GameRng (seedable), GameData (registry + validation), GameState (serializable state)
src/world/            AdventureMap (grid + objects), Pathfinder (AStarGrid2D), FogOfWar
src/heroes/           Hero (attributes, skills, XP/levels, serialization)
src/armies/           Army (7 stable slots)
src/economy/          ResourceBank, Town (building tree, dwellings, growth, recruitment), Economy (income, market, validation)
src/combat/           CombatUnit, CombatSimulator, CombatPredictor
src/game/             GameSession: command layer (move, attack, end turn, save/load) + signals
src/audio/            AudioCatalog + AudioSettings (data, no nodes), AudioManager (autoload "Audio", plays)
src/ui/               AdventureScreen controller, MapView (TileMapLayers), Hud, BattlePanels, UiStyle, Art, TerrainTiles
src/ui/               AdventureScreen controller, MapView (TileMapLayers), Hud (+ Minimap), HeroScreen, TownScreen,
                      ArmyExchange/ArmySlot, BattlePanels (+ BattleVignette), UiStyle, Art, TerrainTiles
assets/               specs (source of truth), atlases + manifest.json (built), see tools/assets/README.md
scenes/main.tscn      Entry scene
tests/                Headless runner + unit/statistical tests
tools/                balance_report.gd, screenshot.gd (smoke test with real renderer), assets/ (art pipeline)
docs/                 This document, art bible
```

Dependency direction: `ui -> game -> (world, heroes, armies, economy, combat) -> core`. Nothing below `ui`
references nodes; nothing below `game` knows about `GameState`. Combat receives a plain **BattleSetup**
dictionary, never a Hero or Army, so the same engine serves real battles, Monte Carlo forecasts, balance
tools and a future tactical mode.

Key decisions:

- **No autoloads for rules.** `GameData` is injected (with a lazy default) so tests can build variants.
- **Own PRNG.** `GameRng` is xorshift32 with explicit 32-bit masking, identical across platforms and engine
  versions. (Bug found by the tests: methods named `randf()` inside the class silently resolved to Godot's
  global unseeded function; they are now `next_float()` / `next_int()`.)
- **JSON over `.tres` for content.** Diff-friendly, editable by agents and external tools, validated at load
  (`GameData.validate()` is a test). Godot Resources can wrap these later for editor tooling.
- **Map objects are dictionaries with a `type`.** New object kinds (mines, shrines, encounters) are data plus a
  handler in GameSession, no class hierarchy.
- **Saves are versioned JSON** (`GameState.SAVE_VERSION`, `validate_save()`); static terrain is reloaded from
  the map definition, mutable state comes from the save; RNG state is saved so a loaded game continues
  identically (tested).

## 3. Libraries and existing components

| Need | Choice | Status / licence |
|---|---|---|
| Tile maps & transitions | Godot `TileMapLayer` (built in); one blend layer per terrain with 46 pre-rendered transition shapes (our own mask maths, unit-tested, instead of the editor terrain solver) | Engine, MIT. In use. |
| A* | Godot `AStarGrid2D` with per-cell weight = terrain cost | Engine, MIT. In use. |
| Fog of war | Own `FogOfWar` byte mask (≈40 lines); rendering via shroud overlay | No library needed. |
| Procedural maps | Own zone-graph generator (template → zones → connections → fill), see section 5a. Gaea (MIT) was not needed: terrain noise is a few lines of seeded value noise on `GameRng`. | Implemented (`src/world/generation`). |
| Save/load | Godot `JSON` + `FileAccess` | Engine. In use. |
| UI | Godot Control nodes + Theme | Engine. In use. |
| State management | Command layer (`GameSession`) + signals | Own, minimal. |
| Testing | **GUT 9.x** (MIT) is the intended framework. The build sandbox could not download it, so `tests/test_case.gd` is a 60-line GUT-compatible runner (same assert names). Migration = add `addons/gut`, change `extends`. | Own for now. |
| Asset pipeline | `tools/assets/` (Python: Pillow HPND, numpy BSD; rembg MIT optional): spec → source (pixel / procedural / AI) → background removal → fit → palette → outline → validate → atlas + `assets/manifest.json` → Godot import. Game side: `Art` (manifest, `AtlasTexture`, nine-slice), `TerrainTiles`. | In use. AI generation needs `OPENAI_API_KEY`. |

| Audio | Godot `AudioStreamPlayer` + buses (built in); OGG Vorbis. Sounds and music are synthesized by `tools/audio/synth.py` (numpy + ffmpeg/libvorbis at build time only), so they are original and project-owned; see section 5e and `assets/audio/LICENSES.md`. | In use. |

All additions must be MIT/BSD/Apache/zlib or similar; no GPL code in the shipped game.

## 4. Data models

**Creature** (`data/creatures/<faction>.json`, merged with legacy `data/creatures.json`): `name, faction, tier (1-8), role (infantry|ranged|cavalry|flyer|support|heavy),
hp, attack, defense, damage[min,max], speed, initiative, growth, cost{resource:amount}, morale, tags[],
abilities[{id, params}], terrain{terrain_id:{attack, defense, initiative, speed}}`. Formation is derived
from role (front / flank / back / support). Optional `desc`; upgrades pair `upgrade` (base) with `upgrade_of`.
Six factions x 8 tiers, each with an upgrade, plus 32 wild creatures: see [FACTIONS.md](FACTIONS.md).

Abilities are data (`data/abilities.json`: id, params with defaults, description; 29 in total). Core rules
live in `CombatSimulator`, the rest in `AbilityEffects` hooks; validation rejects unknown ids and parameters.

**Faction**: `name, adjective, color, native_terrain[], hostile_terrain[], tags[], economy{curve, key_resources}, roster`.
**Terrain**: `name, char, color, move_cost, passable, vision_mod, combat_terrain`; roads overlay with their own cost.
**Hero class** (`data/hero_classes.json`, three per faction): `name, faction, text, attack/defense/power/knowledge,
growth{attr: weight}, skills{}, skill_weights{}, trait{name, text, mods, per_level?}, art{name, kind, base,
per_power, text}`. See section 5c.
**Skill** (`data/skills.json`): `name, group, levels[3]{text, mods}`. **Artifact** (`data/artifacts.json`):
`name, slot (weapon|helm|armor|shield|boots|charm|banner), rarity, value, mods, text`; `pack_size`,
`drop_slots[]`, `sets{id: {name, pieces[], bonuses[{pieces, mods, text}]}}`. **Campaign**
(`data/campaigns.json`): `name, faction, text, heroes[], carry{keep_worn?, max_artifacts}, chapters[{id, name, map,
level_cap, max_tier?, ai?, setup?, cast?, text, intro?, outro?, start_resources?, rewards[{type: xp|artifact}],
take_artifacts?[], scenario?}]`. Eight campaigns: six faction stories plus the expansions `six_eyes` (Umbral Court) and
`drowned_oath` (Abyssal Shoal). The story bible (world, timeline, cast, every campaign's beats, the editorial rules) is
`docs/STORY.md`; change the story there first, then the data.
**Hero** (runtime/save): `id, name, class, faction, owner, pos, level, xp, attack, defense, power, knowledge,
skills{id:level}, skill_points, movement_left, army[10 slots], alive, marks[], equipment{slot: artifact}, pack[],
level_cap`. Campaign persistence = `Hero.campaign_dict()` (everything but position, movement, army, owner).
**Encounter** (`data/encounters.json`, rules in `src/game/encounter_system.gd`): `name, text, choices[{text,
requires, cost{resource|movement}, check{chance, per_attr, per_skill, mods[{when, add}]}, success/failure{text,
effects[]}, leave}]`. Conditions: `class, not_class, faction, skill, attr, army_tag, army_role, min_creatures,
terrain` (of the encounter tile), `mark, no_mark` (persistent hero marks = campaign state), `min_level, min_week,
any[]`. Effects: `resources, xp, recruit, casualties, movement, skill_point, mark, reveal, ambush` (an ambush
places a neutral army on the tile and hands over to the normal forecast/attack flow). Creature counts grow with
`per_week`. Success chances are clamped to 5–95% and shown to the player before choosing; rolls use the game RNG.
Marks are declared in the same file and every mark must be read by some condition (tested).
**Map**: `id, width, height, terrain[rows], roads[segments], players[], heroes[], objects[{id, type, pos, ...}]`.
**Town type** (`data/buildings.json`, one per faction): `name, starting_buildings[], hire{cost, army, heroes[]},
buildings{id: {name, category, cost, requires[], effects[], description}}`. Effects: `income{resources}`,
`dwelling{creature}`, `growth{creature, amount}`, `growth_pct{pct}`, `defense{amount}`, `tavern`, `market`,
`build_discount{resources}`, `battle_spoils{gold_per_xp}`, `dwelling_upgrade{creature}`, `army_upgrade{name, stats, abilities}`
(the faction's ultimate building, see below). `economy` holds builds per day, hero cap, market values
and rates, and mine defaults. All validated by `Economy.validate()`.
**Town** (map object, saved with the map): `id, type:"town", pos, name, town_type, owner (-1 neutral), built[],
last_build_day, available{creature: count}, garrison[10 slots]`. **Mine**: `id, type:"mine", pos, resource, owner,
amount?, guard?[[creature, count]]`.
Generator additions (optional on any object): `zone` (generator zone id), `guarded_by` (id of the neutral army
holding a treasure pocket), and on neutral armies `value` and `role` (gate|guard|wander). Generated maps also carry
`generator {version, template, seed, zones[], connections[{a, b, gate[], guard}]}` for AI and tools.
**Map template** (`data/map_templates.json`): zones `{id, profile, player?, group, mirror?, anchor, size}`,
connections `{a, b, width, guard, road, group}`, zone profiles (terrain, town, garrison, mines, piles,
treasures, encounters, wanderers by distance band and guard level), guard values, distance bands, per-faction
start settings.
**GameState**: `version, map_id, day, current_player, seed, rng_state, battles_fought, players[{resources,
fog}], heroes{}, objects{}`.
**BattleSetup**: `{seed, terrain, sides:[{name, hero:{attack, defense, power, skills}|null, stacks:[{slot,
creature, count}]}]}`. **BattleResult**: `winner, outcome, rounds, sides[{stacks[{start, end, lost, kills}],
hp_start, hp_end, notes[]}], stats, hp_killed, log[], summary[]`.

## 5. Combat model (implemented)

Rounds (max 15). Each round every living stack acts in order of initiative + seeded jitter (0–2). All tuning
values live in `data/combat_config.json` and are validated by `GameData.validate_combat_config()`.

- **Opening volley:** before round 1 every ranged stack fires one volley. Volleys are aimed
  and rolled simultaneously, so neither side profits from resolution order.
- **Approach:** melee units reach the enemy in round 1/2/3/4 depending on speed (≥8/≥6/≥4/less); flyers in
  round 1. Ranged units keep shooting each round, so slow armies eat volleys.
- **Frontline protection:** while the enemy has front units (infantry/heavy), melee attackers can only target
  front and flank units. Cavalry may slip past (20%, 40% if its own front holds the line); flyers prefer the
  backline (70%). Enemy Tactics skill and `guardian` units reduce these chances. A unit that slips through
  *locks* onto its target.

- **Flyers in the air:** a flyer lifts off at the start of each of its actions and only lands when it strikes
  in melee. While it is in the air (holding back, or before its first dive), ground melee cannot target it;
  shots, other flyers and `reach` units (pikes, giants, colossi, wyrms) can. Ground troops with nothing in
  reach wait ("Out of reach"). Retaliation against a flyer's strike always works, because it has landed.
- **Role matchups:** `role_matchups` in the config adds damage by attacker role against target role: cavalry
  +10% against ranged and support (riding down archers), ranged +15% against flyers.
- **Multi-target attacks:** `splash` hits any second stack; `cleave` sweeps into other stacks within melee
  reach (never past the front line); `breath` rolls past its target into a stack behind it, archers and
  supporters first.

- **Battle orders** (`data/tactics.json`, `BattleOrders`): a hero gives a stance (Balanced, Hold the line,
  All-out attack) and a focus (Free fighting, Hunt the archers, Guard the archers, Strike the strongest, Finish
  the wounded). Options open with hero level; each Tactics skill level opens them `tactics_skill_discount`
  levels sooner. Effects only shift stats, approach timing, bypass chances and targeting weights, so the
  defaults reproduce the plain model draw for draw. Orders are saved per hero (`Hero.orders`, save v13), set
  on the battle forecast (`GameSession.set_hero_orders`) and used when the hero defends too; computer heroes
  pick theirs from both armies' make-up (`BattleOrders.choose`; not on easy or passive).
- **War council** (save v22): before the fight a hero also sets a **formation**, an **art timing** and a
  **standing retreat order** (`Hero.orders` kinds `formation`, `art`, `retreat`; `GameSession.set_battle_orders`;
  the forecast's second "Deploy" row). Battles stay one click: nothing is chosen during the fight.
  - Formations: Battle line (default), Shield wall (+front defense, archers take less from shots, harder to
    slip past, slower advance), Spearhead wedge (advance a round sooner, every stack's first melee blow +30%,
    thinner sides), Skirmish screen (stronger opening volley, enemy melee arrives a round later, easier to slip
    past), Crescent (blows on enemies held by the line +25%, flankers slip past more, thinner centre) and Held
    reserve (the strongest melee stack waits out of reach until round 3 and enters with +2 attack and +2
    morale, at once if it is the last one standing). Each lists hero `classes` that know it by heart (open from
    level 1, drilled) and a `skill` (Shieldcraft, Onslaught, Archery, Tactics, Leadership) that opens it sooner
    and drills it; every class knows one. Drill (`formation_drill`: class 30%, 15% per skill level, plus a
    specialty's `formations.<id>.bonus_pct`, capped at 100%) scales the formation's benefits, never its
    drawbacks or timings. A hero specialty may also unlock a formation (`formations.<id>.unlock`);
    `Hero.commander()` hands level, class, skills and specialty to the gates.
  - Art timing: At once, When the lines meet (from round 2, +25%; Sorcery opens it sooner) or When the line
    bends (once the army has lost 30%, +50%).
  - Retreat: Fight to the last, Fall back at half strength or Fall back when broken (25%). After a round in
    which the army is down to that share, the battle ends as a loss, the rear guard (20%/25% of every surviving
    stack) is cut down and the hero escapes with the rest: an attacker stays where it stood with no movement
    left, a defending hero in the open flees to its home or another town (`flee_destination`). A hero defending
    a town, or with nowhere to go, fights to the last (`can_withdraw` on a battle side). Results carry
    `withdrew` (the side, or -1) and the outcomes `attacker_retreated` / `defender_retreated`.
  - The AI picks a formation by fit (`BattleOrders.formation_scores`, plus its drill; tuned with
    `tools/formation_probe.gd`), looses its art at once (holding it lost the hard AI its lead, since most of
    its fights end in a round or two) and keeps fighting to the last.

Army synergy comes from roles, targeting and protection rather than flat percentage bonuses:

- **Pinning (the anvil):** the first melee stack to reach a target pins it. A pinned stack keeps fighting its
  pinner until the pinner falls, so a front line holds enemy stacks away from its archers. Pinned ranged
  stacks fight back point-blank at ×0.85.
- **Flank attacks (the hammer):** cavalry or flyers striking an enemy pinned by one of their side's front-line
  stacks (infantry or heavy) get no retaliation and ignore `brace`. It takes an anvil of a different role, so
  splitting cavalry into several stacks gains nothing.
- **Targeting:** front units prefer enemies nobody holds yet (to pin them); flank units prefer pinned enemies
  (×3 weight); ranged prefer pinned enemies (×1.5) and other ranged (×1.3).
- **Cavalry and flyer holding:** cavalry with an unspent charge, and flyers, wait (up to round 4) until one of
  their own front-line stacks (infantry or heavy) holds an enemy melee stack, then strike it in the flank
  instead of taking its full answer alone. They never wait to ride down ranged or support stacks
  (`flyers_hold_for_the_line`). This is what lets a mixed army beat a few huge tier-7 creatures.
- **Support holding:** melee-less support stacks heal and stay behind the line until an ally has pinned
  someone. A support stack without fighting allies fights (and does not spend its turns healing itself).
- **Stand and shoot:** an unpinned ranged stack fires at the first enemy that closes in, before the blow
  lands (uses its retaliation for the round).
- **Frontage and wrap-around:** in melee a stack can only bring `target creatures × target HP per creature /
  own HP per creature` creatures to bear against one target (min 3). The rest wrap around and strike other
  reachable enemy stacks (up to 9) in the same action. A volley (the opening volley too) that wipes out its
  target carries on into the next stack, and the next, until its damage is spent. How a unit is split into stacks therefore does not decide fights: a big stack spreads its weight
  instead of wasting it, and several small stacks gain no free hits.
- **Retaliation pool:** each round a stack may strike back at every melee attacker, but each answer uses only
  the creatures facing that attacker, minus those the blow just killed, and in total no more than the stack's
  size per round. No retaliation against `relentless` attackers or flank attacks. `brace` negates a charge and
  retaliates ×1.5.

Resolution:

- **Damage:** genre attack/defence curve (+3%/point up to ×3, −2%/point down to ×0.3) on summed rolls,
  times modifiers: charge, archery, shield wall, curse.
- **Fortune of war:** each side rolls one triangular multiplier per battle (±20%) on all damage it deals. This
  keeps a 10% stronger army a clear favourite without making it a certain winner.
- **Morale:** ±4% per point for an extra action / a skipped action; from leadership, faction cohesion (one
  faction +1, three or more −1) and support auras.
- **Terrain:** faction native (+1 attack) and hostile (−1 attack) terrain, plus per-creature terrain
  affinities (e.g. Bog Lurker +3/+3/+3 speed in swamp).
- **Cold attrition** (adventure map, `src/game/cold_attrition.gd`): at the start of each day a hero standing on a
  `cold_attrition_terrains` tile (snow) loses `cold_attrition_pct` (10%, rounded up, never below 1) of every stack
  whose faction lists that terrain as hostile. Heroes in towns, town garrisons and heroes with
  `ignore_hostile_terrain` (Forgewarm Harness at two pieces, Rime Shroud, Pathfinding) are spared; the owner gets a
  news line. Rule `cold_attrition`: on in campaigns unless a chapter sets `cold_attrition: false`, off in skirmish
  (game_rules default).
- **Heal:** support stacks heal the most wounded ally, reviving fallen creatures up to the starting count.

**Balance goals** (statistical tests in `tests/unit/test_combat_balance.gd`; numbers in
`tools/balance_report.gd`; scenarios in `src/combat/balance_scenarios.gd`): an army with equal gold in each
tier 1–6 creature beats every single-creature doom stack of equal gold (>50% each, >70% on average; tier-7
stacks 55–95%, a real threat but beatable); balanced factions are 45–70% at home and 28–55% away (Concord vs Ashen, the widest swing); balanced factions are 35–65% on neutral ground; same-tier
creatures added to a shared neutral core are 25–75%; splitting one unit into several stacks is neutral (40–65%
averaged over who attacks; ties in initiative favour the defender, so each direction alone can drift); mass
ranged loses to equal-gold cavalry but averages
8–45%. To price a new creature, run `tools/fair_cost.gd`, which finds the gold cost at which it breaks even
against the rest of the roster. All these tools price creatures at their full value: wood and ore count 100
gold, rare resources 250 (`BalanceScenarios.RESOURCE_VALUE`, the same table as `tools/roster_report.gd`).

**Prediction:** 200 simulations with seeds derived from a fixed salt and the battle counter, never from the
real battle seed (which is drawn from the game RNG only when the player commits). Output: win probability,
label (Overwhelming / Strong / Favorable / Even / Unfavorable / Severe), expected and 10th–90th percentile
losses per stack. Cost ≈ 70–130 ms per forecast.

Tactical-mode readiness: units, modifiers and damage are already independent of the round loop; a tactical
mode would replace `_run_round`/targeting with player/AI choices on a hex grid and reuse `_damage`, abilities,
terrain and setup/result formats.

## 5a. Procedural maps (implemented)

`MapGenerator.generate(data, template, seed)` returns a map definition in the normal map format; the id
`gen:<template>:<seed>` makes `GameData.load_map` regenerate it (`godot --path . -- --map=gen:twin_marches:7`,
or "Random map" in the HUD). New saves store each map’s terrain, roads and authored decorations, so later map changes do not alter a saved game.
Older saves of redrawn story maps use their preserved original layouts; older generated saves without a snapshot
still regenerate from the id. The fixed generated layouts range from 70×70 duels to 200×200 six-player maps. Pipeline:

1. **Zones** (`ZoneLayout`): weighted Voronoi (power diagram) around jittered template anchors, sampled
   through a smooth warp field for organic borders. With `symmetry: rotate180` seeds and warp are
   point-symmetric, so mirrored zones get mirrored shapes. Fragments merge into neighbours.
2. **Walls and passes**: each zone tile touching a lower-numbered zone becomes mountain (one-tile walls that
   neither orthogonal nor diagonal moves can cross). Each connection carves a pass of `width` tiles near the
   midpoint between the zones: the **chokepoints**, held by a gate guard of the connection's level.
3. **Terrain**: zone base terrain (start zones use the owner's native terrain), then the **terrain
   painter** (`TerrainPainter`, `data/terrain_painting.json`): 1-2 secondary biomes per zone as noise
   patches with dithered, smoothed edges (an exact share per zone; a template group, and all player
   starts of a profile, share one plan), biome bleed around passes, rivers from wall to wall and lakes
   that never cut a zone apart, with soft shores, and landmarks from the map scenery library
   (`assets/map_scenery`: volcano, frozen cascade, elder grove, shattered citadel) as impassable 4x4 set
   pieces in open zones; rotate180 templates are painted point-symmetrically.
   Then roads (cheapest path town → pass → town) and obstacle blobs that are only kept if the zone stays
   connected. After everything is placed, `TerrainPainter.dress` adds single-tile scenery pieces (willow,
   reed pool, oath stones, broken cart), ground-variant patches (`surface`: moss heath, autumn loam,
   salt flat, cooled lava, drawn feathered over the ground) and `decorate` scatters decorations from weighted
   per-biome pools, clustered by noise with clearings, clear of roads, towns and objects, and never the
   same kind and variant on neighbouring tiles. Such maps carry `"decor": "painted"`, so the map view
   draws only the map's own decorations on land (mountains and water keep the view's scenery); maps
   without the flag keep the view's hash-based scenery. `decorate` works on any map definition, so
   frozen or hand-made maps can use it too. `tools/terrain_report.gd` measures biome mix and decoration
   variety.
4. **Content** from the zone profile, rolled **once per zone group** so mirrored starts get identical
   mines, piles, treasure and guard strengths. Items go into movement-cost **distance bands** from the zone's
   town (near/mid/far), and a mirrored zone places each item at about the same distance as its twin.
   Guarded mines carry their own `guard` stacks (they block paths, see 5b); guarded treasure sits in a
   **pocket** sealed with rock with a neutral army on the only open side. Neutral towns get a garrison.
   Encounters from `data/encounters.json` are the exploration rewards; mirrored zones get the same ones.
   Each start gets free wood and ore mines near the town and a mine of the rare resource its faction's
   creatures need most. Neutral armies are built to a gold-equivalent value, preferring creatures at home
   on the local terrain.
   **Guarded hoards** (the profile's `hoards`, rules in `hoard_rules`) are the density fill: one per
   `per_tiles` open zone tiles (clamped to min/max), so big campaign zones get more. Each is a resource cache
   or an armour piece in a sealed pocket behind a neutral army. The profile picks set guard level and band:
   start zones get light/weak guards near the town, wild and flank zones medium/strong, the heart
   strong/deadly. Guards vary by ±`guard_spread`; resource prizes are worth `value_ratio` of the rolled
   guard. Mirrored zones get identical hoards. Placed after armour and sites from their own random stream;
   the objects and their guards carry `hoard: true`. The strategic AI counts a guarded cache's resources in
   the guard's value, as it already did for guarded armour.
   **Scattered piles** (the profile's `scatter`, rules in `scatter_rules`) add unguarded resource piles at
   the same rate per zone tile, so large zones are not emptier than small ones; mirrored zones get the same
   piles at about the same distance (objects carry `scatter: true`). A template's `guard_scale` multiplies
   every neutral army's value and its `treasure_scale` the number of hoards and scattered piles.
5. **Validation** (`MapValidator`, also usable on hand-made maps): structure, no overlaps, every object and
   passable tile reachable, each player reaches own town and unguarded start content without a fight and
   cannot reach an enemy without one, and fairness (identical start content, mine distances, distance to
   the enemy within 35%). A rejected attempt is retried with a derived seed, still deterministic.

`tools/mapgen_preview.gd` prints ASCII maps and fairness metrics and can write PNG overviews.
Templates: `twin_marches` (50×50, 7 zones) and `crossing` (48×34, 3 zones); the campaigns' generated chapters use the larger `broad_crossing` (70×48, 7 zones: backwaters and neutral flank towns added) and `great_marches` (68×68, 9 zones: twin_marches plus wild corners beyond the flanks). All four were doubled in area on Nov 7 (playtests: maps too small); generator v3.

**Random maps** (`RandomMapTemplate`, `LayoutFamilies`, settings in `random_maps` of map_templates.json): the
new-game screen's "Random map" builds a template from options kept in its name,
`random_<size>_<players>p_<monsters>_<treasure>[_<family>]` (map id `gen:random_l_4p_normal_rich:<seed>`), so loading
and saves work like any generated map. 2 to 6 players (Small holds 4). Map overhaul step 1 (Nov 9, generator v7, after the terrain painter took v6):
- **Layout families** (zone graphs in `layout_families.gd`): `ring` (starts round a contested heart, flank zones
  between neighbours, optional rings by size: wild backwaters, approaches, outer edges), `hub` (each start reaches
  the heart down its own spoke, a side valley per start, neighbours only meet in the heart), `archipelago` (the ring
  cut into islands by thick lakes; the heart is reached over the flank islands), and two-player `diagonal` (corner
  to corner through the heart, loops round the far corners), `lanes` (two edges, three roads, contested marches on
  the outer lanes) and `tree` (trunk, branches and deep dead-end valleys, one contact in the heart). Without a family
  in the name the seed picks one that fits the player count, by weight.
- **Per-seed variety:** the seed turns and mirrors the graph into one of 8 orientations and jitters every anchor
  (`anchor_jitter`), so neither the direction of play nor the town tiles repeat. Even player counts stay
  point-symmetric (twins mirror each other in every orientation).
- **Passes and walls:** unguarded passes are `pass_width` (2-4) tiles wide; guarded passes stay one tile, because the
  guard is the chokepoint (there is no zone of control). A family's `walls` make each border a ridge or a lake
  (`water` chance, mirrored borders match) and thicken walls by `thick` [lo, hi] tiles per side along a noise field,
  keeping the ground round every pass open (`ZoneLayout._dress_walls`; wall tiles carry `wall_kind`).
- **Room and towns:** each size sets `player_tiles` (Small 1500 to Huge 3800 per player, about 1.75x the old maps);
  the side follows from the players. One start town per player plus 0-2 neutral towns (`neutral_towns.weights`,
  scaled with the players, at most one per player), placed in the zone groups with the best contest value (as far from
  one start as from the others); zones carry `town`/`garrison` overrides of their profile.
- **Optional zones** (`optional: true`) roll a profile from `optional_profiles`: `valley` (treasure valley), `mineland`
  (cluster of guarded mines), `ruins` (`site_picks` sites of its own plus encounters) or a plain `wild` backwater.
- **Quality gates:** `tools/mapgen_quality.gd` reports validity, size, start-to-start cost spread, town tile spread,
  directions of play, pass widths, optional share, neutral towns and lake share per family and renders contact sheets;
  `tests/unit/test_map_layouts.gd` fails if a family plays in one direction or puts its towns on fixed tiles.
Named templates (`twin_marches`, `broad_crossing`, `great_marches`, the fair/adventure recipes) are unchanged, so
campaign chapters built on them keep their layouts. Armor drops (`armor_drops` in
map_templates.json, see 5f) are placed last from their own random stream, so they never reshuffle the rest of
a map. Not yet: underground level.

## 5b. Towns and economy (Phase 2, implemented)

- **Daily cycle:** at the start of each day every player gets the income of their towns (hall chain, resource
  yards) and mines. **Weekly cycle:** on day 1 of each week every dwelling adds its weekly growth to the town's
  pool; unrecruited creatures accumulate. A newly built dwelling starts with one week of creatures.
- **Starting heroes:** a standard game (a skirmish from the new-game menu, setup `standard_start`) gives each
  player `game_rules.starting_heroes` (1) heroes: the map's first heroes for that player are kept, a player
  short of heroes gets its faction's next tavern hero next to its first hero. A faction may set its own count
  (`factions.json` `starting_heroes`; the Frostmarch starts with 2). Campaigns and maps started without a
  setup keep the heroes the map places. Starting heroes of a standard game lead tier 1-2 creatures only
  (`game_rules.starting_army_max_tier`); higher stacks the map gives them are dropped.
- **Building tree:** 21 buildings per faction in five groups (civic, fortifications, dwellings, dwelling
  improvements, faction special). Prerequisites form a DAG (validated). One building per town per day.
- **Tradeoffs:** a month of base income covers well under half of either tree. Fortifications add garrison
  defense and +25% growth each, so walls compete with dwellings and the income chain. Humans build in timber,
  crystal and gems; demons in ore, brimstone and quicksilver (tested). Specials: Masons' Lodge (−30% timber and
  ore on later buildings in that town) and Trophy Pit (gold equal to XP after every victory).
- **Recruitment:** from the town's pool into the visiting hero, or the garrison if no hero is in town. Whole
  stacks move between garrison and hero; a hero keeps at least one stack.
- **Mines and towns on the map:** stepping on an unguarded mine or town captures it. Guarded mines and garrisoned
  foreign towns are fought like neutral armies (forecast, battle, capture on victory); the town's fortifications
  act as a defending "hero" with a defense bonus. Guarded objects block paths through them.
- **Six town types** (concord, ashen, hollow, thornwood, forge, frostmarch), 29–30 buildings each, including one
  upgrade building per creature (category `upgrade`). Dwelling and upgrade costs follow the faction's
  `economy.curve`: early factions pay ~70% for tier 1–3 dwellings and ~130% for tier 6–8, late factions the
  reverse (~130% / ~85%) and get +30% growth per wall level instead of +25% (early: +20%).
- **Upgrades:** a creature def may name `"upgrade"`; the upgraded def carries `"upgrade_of"` (same faction and
  tier). A `dwelling_upgrade{creature: base}` building (which must require the base dwelling) lets the town
  recruit the upgrade from the base's shared pool and convert whole stacks in the garrison or visiting hero for
  the per-resource cost difference (`upgrade_options`, `can_upgrade_stack`, `upgrade_stack`).
- **Ultimate buildings:** each faction has one `ultimate`-category building with an `army_upgrade` effect (Concord
  Reliquary of Holy Arms, Ashen Brand-Pit of the Abyss, Hollow Undying Choir, Thornwood Heart of the Mother Tree,
  Forge Deep King's Anvil, Frostmarch Hall of the Endless Feast). It needs the tier 8 dwelling and the treasury and
  costs 30,000 gold plus rare resources. Every creature of the town's faction in the owner's armies and garrisons
  then fights upgraded (`Economy.army_upgrades`; battle sides carry them as `upgrades`, `ArmyUpgrade.apply`
  adds stats, damage multipliers and abilities; a stronger copy of an ability the creature already has wins).
  Copies do not stack. It counts as tier 8 for a chapter's `max_tier`. Target: a late army with it beats the
  same army without it about 70-85% of the time, and loses to one with 30% more gold (tested). Upgraded sprites
  wear the faction's ultimate shader (`assets/effects/`).
- **Tavern:** hires the next hero of the town type's pool (2500 gold, small starting army), up to 8 heroes.
- **Market:** trades any resource for any other; one market trades at 40%, each extra market +8% (max 70%), and a
  round trip always loses value.
- **Defeat:** see 5d (game flow).
- **Commands** (all on `GameSession`, return `{ok, reason}` or a reason string): `build_options`, `can_build`,
  `build`, `recruit_options`, `max_recruitable`, `recruit`, `move_stack`, `hire_offer`, `can_hire_hero`,
  `hire_hero`, `trade_quote`, `trade`, `daily_income`, `towns_of`, `mines_of`, `visiting_hero`, `is_guarded`.
- **Saves:** version 3. Older saves migrate in a chain: v1 -> v2 adds the map's towns and mines, v2 -> v3 adds
  the map's encounters (on free tiles) and gives heroes empty marks.
- **Not yet:** tavern hero pools for the four new towns (their hero classes don't exist yet, so `heroes` is empty), magic research (no spell
  system yet).

## 5c. Strategic AI (implemented)

`src/ai/strategic_ai.gd` (`StrategicAI`) plays one player's turn through `GameSession` commands only (it reads
state, never writes it), so it cannot do anything a human could not. Rule-based and utility-driven:

- **Towns first:** build the affordable building with the best value per gold (income × 10 days, a dwelling's
  weekly troops, growth, walls (worth far more when the town is threatened), tavern, market, +300 per building it
  unlocks). If a much better building only lacks a non-gold resource and a market can supply it, buy it first.
  Hire a hero while the player has fewer than `min(3, 1 + towns)` and keeps 1500 gold in reserve. A player
  with no hero hires before anything else, without the reserve, and saves gold for it (no builds or recruits).
- **Heroes, one by one:** an `AiDistanceField` (Dijkstra with the pathfinder's exact step costs; blocked tiles
  are reachable only as destinations) gives the travel cost to every tile at once. Every *explored* target is
  scored `value / (1 + days away)`: resource piles (market value), mines (12 days of income), towns (9000 + 10
  days of income; ×1.4 if taken from a rival), neutral armies (0.6 × their troop value), own towns worth a visit
  (troops to recruit or collect), and the best unexplored frontier tile (35 gold per tile revealed). The AI knows
  only what its fog of war shows.
- **Fights via the forecast:** guarded targets that pass a cheap strength pre-filter are forecast (48
  simulations, cached per turn, at most 4 per decision). The AI attacks only at ≥ 80% win probability and
  ≤ 45% expected losses, and the target's utility becomes `(value × win% − expected losses in gold) / (1 + days)`.
  A *decisive* siege (a rival's last town with no hero of theirs outside it) needs only the win probability.
- **Defense:** an enemy hero that can reach an own town within one day with a stronger army than the garrison
  (walls count, a hero standing in the town does not) *threatens* it. A hero in that town leaves all but its
  weakest stack as garrison if that makes the town hold, and stays. If hero and garrison together have a fair
  chance (≥ 60% of the threat), the main hero guards the town: it takes no fight except against an enemy hero
  it can reach today, and ends its turn in the town. Towns hire only after the heroes moved, so a fresh hire
  does not block the tile. If the town is lost either way, the hero saves itself. Within two days the town is
  *in danger*: a hero picking up the garrison leaves enough behind to hold.
- **Not getting caught:** a hero does not end its turn where a stronger visible enemy hero could reach it
  tomorrow (after this fight's expected losses), except in its own town or a town it takes today. An enemy
  hero out of sight is assumed to be as strong as all our troops and possibly back in any known enemy town.
  A town is taken only if no stronger enemy hero could retake it from the hero tomorrow (walls count), unless
  taking it ends the rival (`guarded_captures`).
- **Sorties:** a hero standing in a town in danger with an enemy hero within today's walk takes up the whole
  garrison and attacks if the forecast allows; otherwise the troops go back (`sorties`). Without this, strong
  garrisons idled while the enemy picked off every fresh hire leaving the town.
- **Invasions:** the AI reads the scenario news like a player: a warned wave (its day and army,
  `WaveDirector.scaled_army`) or an invader on the map whose order targets an own town puts that town in danger
  (the garrison stays) and threatens it once the main hero needs the remaining days to get home
  (`reads_invasions`). Waves not yet announced stay unknown. The Shuttered Halls survival chapter, lost on day
  14 in AI-only games before, now holds.
- **Chasing:** an enemy hero out of today's reach is worth `chase_rate` (0.5) of its value, since it moves.
- **Forecast screening:** with `screen_width` above 1 (very hard: 2), the top `screen_width ×
  forecasts_per_decision` guarded targets first get a quick forecast with a quarter of the simulations; fights
  clearly below the bar (`screen_margin`) are dropped, so the full forecasts go to the fights that might be taken
  (a best-arm bandit step).
- **Encounters and skills:** each encounter choice is valued by its expected effects (success chance × effects,
  resources at market value, XP, recruits, casualties, ambush risk against the hero's strength, minus its cost); the
  AI walks to encounters worth it, takes the best choice, fights an ambush only if the forecast allows, and spends
  skill points through `learn_skill` by `skill_priority`.
- **One main army:** the strongest hero collects the garrisons; secondary heroes drop their troops in towns and
  scout and gather.
- **Deterministic and stateless:** no memory between turns and no RNG draws (forecasts use the predictor's salted
  seeds), so the same seed replays the same game and a loaded game plays on identically (tested).
- **Settings:** `StrategicAI.new(session, player, {overrides})` (thresholds and valuations in
  `DEFAULT_SETTINGS`), the hook for difficulty levels and personalities.
- **Difficulty levels** (save version 9): every player has a `difficulty` from `data/ai_difficulty.json`
  (`passive`, `easy`, `normal`, `hard`, `very_hard`; default `normal`), chosen per computer slot in the new-game setup or by a
  campaign chapter's `setup.players[i].difficulty`. A level overrides `StrategicAI` settings (passive: never
  targets the player; easy: surer fights, fewer heroes; hard: riskier fights, more heroes, higher value on rival
  towns and heroes; very hard: as hard plus 10 forecasts per decision with screening, three-day danger horizon,
  up to five heroes) and scales the computer player's daily income by `income_percent` (easy 85, hard 125, very
  hard 150; humans always 100). Scenario `wave_strength` presets without a `very_hard` entry use 1.2 × `hard`.
  `tools/ai_ladder.gd` plays two levels (or tunings) against each other with seats swapped. Settings merge in the order defaults, level, `GameState.rules.ai`, constructor overrides.
- **Running it:** the adventure screen runs computer players right after the human ends the turn
  (`StrategicAI.play_ai_turns`). `data/maps/twin_marches.json` is a mirror-symmetric two-player duel map (human
  Concord vs. AI Ashen Host; `godot --path . -- --map=twin_marches`). `tools/ai_match.gd` plays AI against AI
  headless and prints a daily summary.
- **Measured:** 20–450 ms per AI turn on the duel map. In AI-vs-AI runs both sides take their mines, fight
  neutrals, build every day and recruit; by week 6 one side usually holds all three towns.
- **Hero battles and sieges:** visible enemy heroes in the open are targets worth 0.6 × their troops plus
  `hero_kill_value` (×1.4 rival bonus); a town defended by a hero counts the hero's army and defense in its
  strength and is worth `hero_kill_value` more. Both go through the same forecast gate.
- **Measured:** with hero battles and the town-loss timer, AI-vs-AI games end: twin_marches seed 1 on day 27,
  Mournfield (four computer players) on days 49–51 for seeds 1–3 (tested on twin_marches).
- **Known limits:** the AI does not yet plan multi-turn routes or coordinate several heroes on one target.

## 5d. Game flow (implemented)

From launch to the end of a game. Rules are headless (`src/game/game_setup.gd`, `victory_rules.gd`,
`save_slots.gd`); the UI (`MainMenu`, `SaveLoadDialog`, `TurnCurtain`, `GameOverDialog`, all driven by
`AdventureScreen`) only calls them.

- **New game:** a Mode picker (conquest, townless start, survival, three strongholds, endless survival,
  expedition; `GameSetup.MODES`) and `GameSetup.available_maps(data, mode)`: the mode's random entry first
  (`GameSetup.random_entry`: size, players, layout family or Any, teams for conquest (contiguous blocks of
  slots), monsters and treasure, see 5a; a mission plays `ScenarioGenerator.current_recipe` on the random
  template, 2-4 players, `scenario:<recipe>:<template>:<seed>`; the expedition takes no options), then the
  curated seeds of that mode (`random_maps.curated` in map_templates.json: a named template and seed that always
  play the same map; the menu seed then only seeds the game), and for conquest the player's editor maps. Story
  and campaign maps, the hand-written templates and legacy recipes are not listed but stay loadable;
  `GameSetup.map_entry(data, map_id)` builds a setup entry for any id, and `GameSetup.map_id_for` is the one
  place menu ids are built. Each map player slot is Human, Computer or Closed and picks any
  faction with a town type. `GameSetup.apply` rewrites the map definition: closed slots disappear (players are
  renumbered, their heroes leave, their towns turn neutral with a garrison of twice the tavern army, their
  mines turn neutral); a slot that changes faction gets that town type (starting buildings, garrison converted)
  and heroes from that faction's tavern pool (the tavern will not offer them again), with armies converted stack
  by stack to the same tier at equal value. `GameSession.new_game(data, map_id, seed, setup)`.
- **Hot-seat and computer players:** after each turn the computer players move (`StrategicAI.play_ai_turns`);
  with two or more humans a curtain hides the map until the next player begins, so nobody sees another's fog.
  The autosave slot is written at the start of every human turn.
- **Hero battles:** an enemy hero may be the destination of a move; `move_hero` returns `battle` = that hero's
  id (or the town's id if the hero stands in its own town). `battle_target(id)` resolves an id to
  `{kind: hero|town|mine|neutral_army…, pos, object, hero}`; `battle_setup`, `preview_battle` and `attack` take
  either kind of id. The loser's army is gone and the hero falls (`alive = false`); the winner takes the tile
  (and an enemy mine under it). The defending hero earns XP from what it killed; beating a hero gives
  `hero_defeat_xp_bonus` (+25%) extra XP.
- **Sieges:** a hero in its own town defends together with the garrison: its stats plus the walls' defense
  apply to the whole side; garrison stacks fight with slots offset by `GARRISON_SLOT_OFFSET` (7) so casualties
  split back into hero army and garrison. A town with a defending hero is guarded even without a garrison.
- **Victory and defeat** (`VictoryRules`, run after battles, captures and turn changes): a player with neither
  living heroes nor towns is out at once; a player with heroes but no town has `town_loss_grace_days` (7) new
  days to take one, with a warning each day, else is out (heroes fall, mines turn neutral). With two or more
  players the last one standing wins ("conquest"); if every human is out while computer players remain, the
  game is lost ("defeat"); computer-only games play to the last player. On a single-player map, holding every
  town wins ("domination"). `GameState` keeps `winner` and `end_reason`; `game_result()` gives the end screen's
  title, text and standings.
- **Teams and alliances:** each setup slot (and a campaign chapter's `setup.players[i]`) may carry `team`
  (0 = alone, 1..`GameSetup.MAX_TEAMS` = allied with the same team; a setup with everyone on one team is
  refused). `GameState.allied(a, b)` is the one rule: allies' heroes are no battle targets and block the way,
  their towns cannot be entered or captured (`is_allied_town`), their mines are not taken, `attack` refuses
  allied targets (`can_fight`), `town_threats` ignores allied heroes, and a hero's sight reveals the fog of
  every living ally. `send_resources(to_player, bundle)` moves resources from the current player to a living
  ally at once (town screen, "Couriers to allies"). An alliance wins together once no rival is left
  (`VictoryRules`: `winner` is its first surviving player, `game_result().winners` lists the whole team and
  `human_won` is true if any of them is human). The strategic AI skips allied heroes, towns and mines. Teams
  are saved per player (save version 11; older saves have none).
- **Save slots:** `SaveSlots` writes `user://saves/slot_<n>.json` (6 slots from `game_rules.json`, plus
  `auto`), each a normal save with a `meta` block (map, day, player to move, time) for the menu.
- **Saves:** version 5 adds `winner`, `end_reason` and per-player `days_without_town` / `eliminated_day`;
  older saves default to no winner and fresh timers.
- **Maps:** `mournfield` (30×22) is a hand-made four-player map: four mirrored quadrants around a walled
  neutral town, guarded passes between neighbours; close slots for two or three players.
- **Retreat:** a hero's standing retreat order (see 5, War council) lets it escape a lost battle with its
  survivors; a hero defending a town always fights to the last.
- **Not yet:** surrender (paying to leave with the whole army), trading troops with allies, computer allies
  sending resources, map-specific victory conditions, a campaign layer.

## 5e. Sound and music (implemented)

- **Data:** `data/audio.json` maps sound events to files (variants play round-robin, an optional
  `pitch_variation` follows a fixed golden-ratio sequence, so there is no randomness), terrains (plus `road`) to
  footstep events, resources to pickup events, and music contexts to tracks (`town:<faction>` overrides `town`,
  so a new faction needs no audio work until it gets its own theme). `AudioCatalog.validate()` checks files,
  buses, every event and context the code uses (`REQUIRED_EVENTS`, `REQUIRED_MUSIC`) and that named terrains,
  resources and factions exist (tested in `test_audio.gd`).
- **Playback:** `AudioManager` is the autoload `Audio`; game code only calls its static helpers
  (`AudioManager.play("build")`, `play_step`, `play_pickup`, `set_music("town", faction)`, `play_stinger`), which
  are no-ops without a running manager, so rules and tools never depend on it. Buses: Master ← Music ← MusicBed
  (loops, crossfaded on two players and ducked under stingers), Master ← SFX, Master ← UI. Every `BaseButton`
  that enters the tree clicks (`set_meta("silent", true)` opts out).
- **Off by default headless:** the manager plays nothing under `--headless` or with the user argument `--mute`.
- **Settings:** per-bus volume and mute in `user://settings.cfg` (`AudioSettings`), edited in the title menu's
  Sound dialog; M mutes on the map.
- **Hooks:** UI clicks and dialogs, footsteps by terrain as the hero walks, pickups and captures on the tile
  where they happen, build/recruit/upgrade/hire/trade (error knock on failure), battle forecast, battle start,
  victory/defeat stingers, encounters, level-up, turn bell and the weekly toll, towns and heroes lost during the
  computer turns, end-of-game stinger. Music: menu, map, town by faction.
- **Faction colour and takes:** events listed in `faction_sounds` (turn and week bells, build, recruit, upgrade,
  hire, capture, battle start, level-up) have one take per faction (`sfx/faction/<event>_<faction>.ogg`: a soft
  three-note motif in the faction's voice, a quiet texture and its room), and the victory stinger has
  `battle_victory:<faction>`. `AudioManager.set_faction()` is called with the player at the controls at each human
  turn. The busiest sounds have two to four takes that rotate.
- **Music:** `files` in a music entry lists alternatives that play one after another (the map has three themes);
  re-entering a context starts the next one. `AudioManager.begin_battle_music()` / `end_battle_music()` wrap the
  battle viewer, which also plays soft fight sounds (`battle_hit`, `battle_shot`, at most one every 0.12 s), war
  drums every other round and, rarely, a distant horn.
- **Content:** about 140 effects (with takes and faction colours), menu, three map themes, battle, three town
  loops and the stingers, all rendered by `python3 tools/audio/synth.py build` (deterministic; about 6.5 MB).
  The target soundscape is calm and warm (between a cosy sandbox game and dark European RPGs), never harsh.
  Instruments carry overtone layers (`CTX["rich"]`); tracks made before them render with `rich=False` so they
  keep their sound. They are placeholders made from code: replace any file with a CC0 or commissioned recording
  of the same name, and log it in `assets/audio/LICENSES.md`.

## 5g. Interface (implemented)

The screens follow the art reference (`docs/art/art_direction_reference.png`): dark wood and iron frames from the
asset pipeline, brass titles, parchment text, pixel art at integer scales. All of it lives in `src/ui` and only
reads state or calls `GameSession` commands.

- **Adventure HUD:** resource bar (gains flash green, spending red; tooltips give daily income), calendar badge,
  minimap in the side panel (terrain, fog, towns and mines in owner colours, heroes, the visible area; click or
  drag to look elsewhere), hero roster, hero card (portrait, class, attack/defense/power/knowledge icons,
  experience and movement bars, seven army slots), command buttons, and a message bar under the map (log and
  the hovered tile).
- **Hero screen (`H`):** large portrait, attributes (with artifact and class bonuses), equipment (one slot per
  artifact slot type, rim in the rarity colour; click to take off), the pack (click to wear; Shift+click hands an
  artifact to an adjacent hero), the class with its trait and battle art, skills, renown and army management. **Army management**
  (`ArmyExchange`, also in the town screen): pick a stack, then click a slot; an empty slot or the same creature
  takes it, a different creature swaps; `Split` or Shift+click moves a chosen number. The rule is
  `GameSession.transfer_stack(from, slot, to, slot, count)` between a hero, the garrison of the town the hero
  stands in (`garrison:<town id>`), or an adjacent hero; a hero always keeps one creature.
- **Battle forecast and report:** a battlefield picture band (the battle terrain's own tiles under a red sky, both
  armies facing each other, the fallen as dark shapes), a verdict with a win-chance meter, portraits with
  expected or actual losses, experience, and the narrative and modifiers behind "Battle details".
- **Resource bar tooltips:** each resource's tooltip gives the stock, the daily total and its sources
  (`GameSession.income_breakdown`): every town, each kind of mine ("2× Ore Pit +4"), heroes with an income bonus,
  and the difficulty and omen percentages.
- **Hover card:** pointing at anything on an explored tile shows a floating card (`MapTip`) saying what it is
  and what it does (`MapTipInfo.describe`): towns (type, owner, walls, income, who stands in it), mines (daily
  output, owner), resource piles, artifacts (slot, rarity, effect), encounters (flavour and choices), rare
  buildings (what a visit gives, or that the selected hero already had it), and heroes (class and level; your own
  also show movement left). Plain ground shows no card; the terrain stays in the bottom bar.
- **Enemy intel and scouting:** pointing at a hostile army on an explored tile (neutral army, guarded mine,
  garrisoned or defended town, enemy hero) shows a floating card (`MapTip`) with rough troop sizes ("A pack
  of", the `UiStyle.COUNT_BANDS`) and a worded verdict for the selected hero (`CombatPredictor.LABELS`, from a quick
  forecast of `combat_config.hover_simulations` runs). **S** (or "Send scout" in the forecast) sends a scout:
  `GameSession.scout()` spends `game_rules.scout_movement` movement (Scouting cuts it by a third, two thirds, then
  entirely, mod `scout_cost_pct`) and needs the target within vision radius + `scout_range_bonus` (4) tiles. A scouted
  target shows exact counts, the exact win chance and expected losses for the rest of the day (reports are kept per
  player in `players[].scouted` and cleared each new day; a hero defending a town is scouted as the town). Until
  then the forecast shows only the verdict. **Hard mode** (a new-game setup checkbox, `rules.hide_odds`) never shows
  odds or encounter success chances; scouts still count the enemy exactly. The rules side is
  `GameSession.intel()`, `hostile_target_at()`, `can_scout()`, `odds_shown()`.
- **Town screen:** town picture with the owner's colour, buildings with resource-icon costs (red when short),
  dwellings as portrait rows, garrison and visiting hero exchange, upgrades, tavern, market. `<` / `>`, a town
  list and `Tab` / `Shift+Tab` switch to the player's other towns without leaving the screen. Armies and
  garrisons hold 10 stacks (two rows of five in the town screen, one row in the hero screen).
- **Tooltips and motion:** themed tooltips (creature stats and abilities everywhere a creature is shown); panels
  fade in over 0.14 s; no other animation besides hero movement. Shortcuts are listed in the README.

## 5f. Heroes, skills, artifacts and campaigns (Phase 4, implemented)

- **One modifier interface.** Skills (per level), class traits and worn artifacts all express their effect as
  a `mods` dictionary with the keys in `HeroModifiers.KEYS` (validated; summed and capped by
  `Hero.modifiers()`). Consumers: combat (`HeroBattleEffects`, via `Hero.combat_profile()["mods"]`), movement
  (`Hero.max_movement`, `Hero.move_cost_mods` -> `Pathfinder.step_costs`), vision, economy
  (`GameSession.daily_income`, `recruit_price`), XP (`Hero.xp_with_bonus`) and battle aftermath (`recover_pct`,
  `spoils_pct` in `GameSession.attack`). A test perturbs every key and checks that something observable changes,
  so no skill, trait or artifact can be a placeholder.
- **Keys:** primaries; `morale, enemy_morale, morale_floor, initiative, combined_arms_roles, ranged_damage_pct,
  melee_damage_pct, shot_resist_pct, screen, role_attack{role}, role_defense{role}, faction_attack,
  faction_defense, ignore_hostile_terrain, native_bonus, art_power_pct, art_uses`; `recover_pct, spoils_pct`;
  `movement_pct, rough_ground_pct, terrain_move_pct{terrain}, vision`; `income{resource}, recruit_discount_pct,
  xp_pct`; `creature_attack{creature}, creature_defense{creature}` (keyed by the base creature of a line; the
  upgrade gets the bonus too).
- **Personal specialties** (`data/hero_specialties.json`, `HeroSpecialties`): every hero has one on top of the
  class trait, so two heroes of one class still play differently. 102 specialties, 11-15 per faction; the 40
  tavern heroes each have their own, and recurring campaign heroes are listed by exact name (aliases such as
  "Odo Brack" / "Castellan Odo Brack" share one). Any other hero gets a specialty of its faction picked by a
  stable checksum of its name. Because it follows from name and faction, nothing is saved. Kinds: creature-line
  specialists (+attack/+defense to one line, more for low tiers, growing every 3-5 levels), percentage
  specialists (ranged/melee damage, shot resistance, recovery, experience, art strength; +1-3% per level, capped),
  income, movement and formation specialists. `growth: {every, mods, max}` adds its mods once per `every` levels.
  `formations: {id: {unlock, bonus_pct}}` is read by `BattleOrders` (pre-battle formations): the formation is
  open from level 1 and works `bonus_pct` better. Shown on the hero screen, HUD tooltip, level-up dialog and the
  tavern offer. The AI values specialty lines when it gathers troops (`StrategicAI.specialty_factor`); battle
  forecasts include every specialty through `combat_profile()`. Regenerate the file with
  `python3 tools/build_hero_specialties.py`.
- **15 skills** in five groups: command (Leadership, Drill), war (Archery, Onslaught, Tactics, Shieldcraft),
  travel (Logistics, Wayfinding, Scouting, Fieldcraft), arcane (Sorcery, Gravecalling, Lore), rule
  (Stewardship, Quartermaster). Three levels each; offers are drawn from the class's `skill_weights` only.
- **18 classes**, three per faction, each with a trait and a battle art: Concord Knight / Ranger / Oracle,
  Ashen Warlock / Warlord / Tormentor, Hollow Necromancer / Gravewarden / Blightcaller, Thornwood Grovewarden /
  Huntmaster / Thornspeaker, Forge Artificer / Ironmarshal / Runesmith, Frostmarch Thane / Reaver /
  Frostcaller. Level-ups add +1 primary following the class `growth` weights (deterministic cycle).
- **Power and Knowledge** drive the **battle art**, used automatically at the start of a round: strength =
  (base + per_power × Power) × (1 + Sorcery), used on 1 + Knowledge/2 rounds (max 5). Kinds: strike (most
  dangerous enemy stack), storm (every enemy stack), mend (heal and revive the most wounded stack), rally
  (+morale this round), hex (target deals less damage this round, cap 60%), ward (army takes less damage this
  round, cap 50%). Arts draw no random numbers, so hero-less battles replay identically.
- **Artifacts:** 42 in seven slots (weapon, helm, armor, shield, boots, charm, banner) plus a pack of 8. Only
  worn artifacts count. Picked up from map objects (`type: "artifact"`), granted by encounters (`artifact`
  effect) or campaign rewards; `equip_artifact`, `unequip_artifact` and `give_artifact` (adjacent heroes) on
  GameSession.
- **Armor progression:** the helm, armor, shield and boots slots (`drop_slots`) hold 23 mostly defensive pieces
  that each map scatters: every generated map puts the same minor piece behind the same weak guard at the same
  distance in each start zone, plus 1-3 extra pieces in the open zones (centre favoured), rarer ones behind
  stronger guards (`armor_drops` in map_templates.json). Hand-made and campaign maps place theirs by hand
  (one per player plus extras). Three 3-piece sets (`sets`) add bonuses at 2 and 3 worn pieces
  (`Hero.active_set_bonuses`); The Last Light's Ashen chapters (8-10) together hold the whole Long Road Harness.
  Gear persists only in campaigns: with `carry.keep_worn` veterans keep everything they wear plus up to
  `max_artifacts` from the pack. Skirmish maps always start empty-handed (design decision, Nov 2026).
- **AI and artifacts:** `StrategicAI.artifact_value` prices a piece by its gain over what the hero wears in
  that slot (a little if it can only be carried, nothing with a full pack) and adds it to the guard that holds
  it; `equip_best` wears the most valuable piece per slot after every pickup.
- **Slow XP:** thresholds unchanged (1000, 2500, 4500, 7500...). Clearing the whole slice map is worth about
  1600 XP: one or two levels for a new hero, at most one for a level-6 veteran (tested).
- **Campaigns** (`Campaign`, `src/game/campaign.gd`): chapters are maps. The campaign's heroes are matched by
  id to each chapter map's heroes and keep level, XP, primaries, skills, unspent points, marks and their
  artifacts (with `carry.keep_worn` everything worn plus up to `carry.max_artifacts` from the pack, otherwise
  `carry.max_artifacts` in all; player's choice first, otherwise the most valuable). Each chapter has a rising
  `level_cap`: XP keeps accruing and pays out when a later chapter raises the cap. A lost chapter changes
  nothing and can be replayed. Campaign saves are versioned (`CAMPAIGN_VERSION`) and can embed the game in
  progress. The first full campaign is "The Last Light" (below); the old three-chapter Ember Chronicle is its chapters 8-10.
  The title screen's Campaign panel lists the chapters and continues from `user://saves/campaign_<id>.json`
  (written every human turn); a chapter opens behind a briefing and its end screen offers the next chapter.
  Each chapter's game also carries its campaign record (`GameState.campaign`, save version 7), so a chapter
  saved to any slot still advances the campaign when won.
- **Chapter rules** (save version 8): a chapter's `max_tier` and `ai` become the game's `GameState.rules`.
  `max_tier` is copied onto every town (`tier_cap`): dwellings, upgrades and growth buildings above it cannot
  be built ("unlocks in a later chapter"), and prebuilt ones stand idle. It must not fall from chapter to
  chapter. `ai` overrides `StrategicAI` settings for every computer player; `passive` (never targets the
  player's heroes, towns or mines), `builds` and `recruits` exist for tutorial opponents. `intro` and `outro`
  are the chapter's briefing story and victory text. A chapter illustration listed in `assets/campaign_art.json`
  (campaign, chapter, usage "briefing"; exported by the art pipeline) is shown beside the briefing text
  (`CampaignArt`, `ChapterDialog`), also when a chapter in progress is resumed. The campaign list shows the
  next chapter's picture (the last one once won) beside each campaign, and the victory screen shows the won
  chapter's picture. Every chapter has one today; a chapter without one would show text only.
- **Generated chapters:** a chapter's map may be a generated id (`gen:<template>:<seed>`). Its `setup` picks
  faction and human/computer per slot (`GameSetup`), and its `cast` places the veterans: a cast hero with
  `replaces` takes over a generated hero's tile (that hero leaves, also when the setup changed its slot's faction and so its id), the others stand on the nearest free tile
  to their owner's first hero (`GameSession._place_cast`).
- **The Last Light** (`last_light`, Concord): ten chapters, the first of six faction campaigns (story bible:
  `docs/STORY.md`). Chapter 1 (`greyhold_harvest`) is the tutorial against a passive opponent that neither
  builds nor recruits; chapters 4 (`knight_who_came_back`), 8 (`burning_ford`), 9 (`ashes_return`) and 10
  (`into_the_embers`) are hand-made (`tools/maps/build_last_light_maps.py`, `tools/maps/build_campaign_maps.py`), the rest generated.
  Units unlock by tier: 2, 3, 3, 4, 5, 5, 6, 7, 8, 8. Sister Edda Vey (Oracle) joins in chapter 3.
- **The Pale Inheritance** (`pale_inheritance`, Hollow): the same tier schedule from the side of the dead. Ysmay
  Vane (Necromancer) leads; Sir Orrin Wren (Gravewarden) is absent in chapter 5, where his body lies in Greyhold,
  and Father Corvin Mire (Blightcaller) joins in chapter 3. Chapters 1 (`warm_earth`), 5 (`twice_dead`, The Last
  Light chapter 4 from the other side) and 10 (`pale_crown`) are hand-made (`tools/maps/build_pale_inheritance_maps.py`,
  helpers in `tools/maps/maplib.py`). Hand-made campaign maps are laid out on small grids and drawn 1.6-2.1x larger
  by `maplib.enlarge` (every tile becomes a block, so passes and reachability keep their shape; one-tile
  corridors stay one tile wide so their guards cannot be bypassed; extra piles fill the new ground). `pale_crown` is one against two: two Ashen players who also fight each other.
  Enemy leaders of generated chapters are cast heroes with `owner: 1` and `replaces: "hero_p1"`.
- **The Unsealing** (`unsealing`, Ashen): Skarn Ashborn (Warlord) leads; Ithra Sootveil (Warlock) joins in chapter 2,
  Morvath the Kindler (Tormentor) in chapter 5. Chapters 1 (`pit_below`), 5 (`breaking_the_lockstone`) and 10
  (`red_sky_throne`) are hand-made (`tools/maps/build_unsealing_maps.py`). `red_sky_throne` is one against three:
  Highmere (Concord), a Thornwood war-grove and a Forge hold, each its own computer player.
- **The Briar Oath** (`briar_oath`, Thornwood): Cerrid Ashbark (Grovewarden) and Neve Hollowreed (Huntmaster); Old
  Mother Brakka (Thornspeaker) joins in chapter 5. Hand-made: `axe_line`, `roots_remember` (chapter 6) and `briar_seal`
  (one against two Ashen broods) via `tools/maps/build_briar_maps.py`.
- **The Shuttered Halls** (`shuttered_halls`, Forge): Gunnra Sootmantle (Runesmith) and Dask Vell (Ironmarshal); Master
  Tobbin Greave (Artificer) joins in chapter 6. Hand-made: `deep_shift`, `fallen_hold` (chapter 6) and `second_lockstone`
  (one against the Ashen Host and the Hollow dead) via `tools/maps/build_shuttered_halls_maps.py`.
- **The Ashwinter** (`ashwinter`, Frostmarch): Ulvra Kettleborn (Thane) and Bjarr Coldhand (Reaver); Seer Iska Rime
  (Frostcaller) joins in chapter 3. Hand-made: `sun_goes_out`, `granary_of_highmere` (chapter 5) and `bring_the_winter`
  (one against two Ashen broods) via `tools/maps/build_ashwinter_maps.py`.
- **Several enemies:** every faction finale after The Last Light is one against two or three. The enemies are
  allied computer players (`players[i].team` = 1 on the map: they never fight each other, share sight and win
  together) and play at the `easy` difficulty (`players[i].difficulty`); `MapValidator` checks both fields.
- Tests: `tests/unit/test_faction_campaigns.gd` checks every faction campaign after The Last Light from one table
  (enemies per chapter, veterans per chapter, hand-made maps).
- **Saves:** version 6 adds equipment, pack and level cap to heroes and artifact objects to maps (v5 saves get
  the map's artifacts on free tiles and empty-handed heroes).
- **Not yet:** artifact icons per piece (slots show their slot icon and a rarity rim).

## 5h. Rare map buildings and random events (implemented)

**Sites** (`data/sites.json`, rules in `src/game/map_sites.gd`, map object `{type: "site", site, guard?, owner?,
creature?, available?, visitors[]}`): eight landmarks, each drawn with one of PR #49's `place_*` sprites.
A site may carry a `guard` (fought once like a guarded mine; the visit follows the victory). Kinds:

| Site | Kind | Effect | Guard |
| --- | --- | --- | --- |
| Outcast Camp | dwelling | recruit a tier 1-3 creature of another banner (wilds included), weekly pool | weak |
| Pyre Citadel | dwelling | recruit a tier 5-6 creature of a town faction | strong |
| Sellsword Gate | dwelling, rotating | a new tier 2-4 company each week, the old pool is lost | medium |
| Oathstone | attribute | +1 Defense, once per hero | none |
| Bleeding Rift | attribute | +1 Attack, +1 Power, once per hero | medium |
| Pilgrims' Rest | boon | +1 morale, +10% fallen recovered, 7 days | none |
| Wardens' Causeway | boon | +20% movement, +1 vision, 7 days | none |
| Elder Rings | lore | +1200 XP, once per hero | weak |

Dwelling sites are captured by stepping on them (an owner pennant is drawn) and recruited from by a hero
standing on them (`site_info`, `site_recruit`; the site dialog opens when a move ends there). A chapter's
`max_tier` also caps site recruits. Boons live on the hero (`Hero.boons [{source, name, until_day, mods}]`,
summed into `modifiers()` and dropped when a later day starts). **Generator**: `sites` in map_templates.json
puts one identical non-dwelling site in every start zone (same distance) and 2-3 picks in the open zones; a
pick goes into every zone of its zone group with the same guard and creature, so mirrored zones stay fair
(own RNG stream, like the armour drops). **AI**: `StrategicAI.site_value` (dwellings: weekly troops x
`site_capture_weeks`, or the affordable pool at a held one; others: the data `ai` value or XP), and it
recruits on arrival.

**Events** (`data/events.json`, `src/game/world_events.gd`): from day 8, each new week draws one omen (12, by
weight; a quiet week is the most likely) that holds for everyone: growth +50% / -25% or double for one rolled
tier, hero boons for the week (+1 attack, -1 morale, -15% / +10% movement), income -25% gold or +50% other
resources, the same rare-resource windfall for all, or neutral armies +20%. Each day every player has a 12%
chance of a fortune of their own (resources, a fire in the stores, XP, a short morale blessing, deserters of
their faction joining a hero). Rolls use the game RNG before weekly growth. Omen and fortunes reach a human as
"news" (`take_news`) when they are next to move; the HUD shows the omen beside the date. The rule
`random_events: false` (game_rules.json, or a campaign chapter's `random_events`) turns them off; the Last
Light tutorial does. Saves: version 10 (`omen`, player `news`, hero `boons`, site objects).

## 5i. Live battle view (implemented)

Battles are still resolved instantly by `CombatSimulator`; watching is optional and never changes the outcome.
The recorded log names each stack by side and slot and carries the counts after every event, so
`BattleReplay` (headless, `src/combat/battle_replay.gd`) can retell it as simple steps: melee (walk to the
target, strike, stay for the answer), answer (retaliation in place), shot (strike plus projectile), effect and
notice pop-ups, and round markers. `BattleViewer` (`src/ui/battle_viewer.gd`) plays the steps with
`BattleFigure`s as a clash (the only view): attackers on the left, defenders on the right, deployed by formation
(front line nearest the middle, flankers on the wings, support behind, the ranged line at the back). Speed 1x/2x/4x is
remembered; Skip or Esc jumps to the end. The forecast has a "Watch the battle" checkbox (remembered in
`user://settings.cfg`, off by default) and the report has a "Watch the battle" button for a replay.

Each stack is a small battalion (`BattleFigure`): about one figure per 260 hit points of a creature, at most 9
and never more than the creature count, so a horde fills a block and a giant stands alone. Every figure walks on
its own (own start, pace, easing). Each round, a stack splits its figures into one group per enemy it trades
melee blows with, and the groups pair off one to one; locked fighters keep swinging and stepping between the
logged blows. The figures that fall are the ones struck, thrown away from the blow, and they stay on the field
with gore by creature tags (`BattleGore`: blood, bone dust, sparks, embers, sap, ichor, ice, wisps). An atlas
`death` clip plays instead of the coded fall when a creature has one. Pop-ups show creatures lost per blow.
Battle orders and formations show on the field: each side's orders and each battalion's formation are announced
at deployment, a coloured ring under each figure marks its side, and the lines march so they meet in the round
the log says they first fight (the meeting line shifts towards a side that holds while the other attacks all
out). Army formations change the deployment (`BattleViewer.deployment`): a shield wall stands as one long,
shallow, shoulder-to-shoulder wall with the archers close behind; a wedge forms an arrowhead (the middle
battalion leads, each front block is a point, the riders follow behind the point); a skirmish screen puts the
archers ahead of the line and pulls them back behind it once the march starts; a crescent holds its centre back
and sweeps its wings forward; a held reserve waits far behind its army and marches in on the round it enters.
A side that falls back walks off to its own edge of the field. `tools/clash_review.gd` records a review video
with Godot's movie writer.

Creature animations are optional strips in `assets/animations/<id>/<id>_move.png` and `_attack.png` (128x128
frames, facing right; see `assets/animations/README.md`). `CreatureAnims` loads them; a creature without them
uses its still sprite with a placeholder stride and lunge.

## 6. First playable milestone (this slice) and the next one

Slice (done): see README "What works". Next milestone, **Phase 1 completion + Phase 2 start**:

1. Hero selection and multiple heroes per player; zone of control around neutral armies.
2. Mines (daily income), map pickups with choices (treasure chest: gold or XP).
3. One town per faction: building tree (data), one build per day, dwellings, weekly growth, recruitment UI.
4. ~~Army management (split/merge/swap between hero and garrison).~~ Done (`transfer_stack`, hero screen).
5. Level-up skill choice dialog (data and `Hero.learn_skill` exist).
6. ~~Real tileset and creature sprites from the asset pipeline (art bible).~~ Done; next: AI-generated
   replacements per faction, town screen art, battle-report portraits.

## 7. Design decisions and risks

| # | Decision / risk | Mitigation |
|---|---|---|
| 1 | **Balance of an auto-resolver is the core risk.** Outcomes are steep in army strength, so small cost changes swing win rates. Doom stacks now lose to balanced armies through pinning, flank attacks and frontage; see section 5 for the goals and their tests. | `tools/balance_report.gd`, `tools/fair_cost.gd` and statistical tests; re-run both when adding creatures. |
| 2 | Same-tier parity is measured inside a shared core army (pure 1v1 stacks are dominated by role counters). | Keep `test_same_tier_creatures_near_parity` green; tune data only. |
| 3 | Pure ranged vs equal-gold cavalry: 0–42% depending on the pair, about 20% on average (was 0%). Hurlers vs Lancers stays near 0: light archers against heavy lancers. | Opening volley, stand-and-shoot, point-blank fire at ×0.85. |
| 4 | Slow progression could feel unrewarding. XP = 0.5 × enemy HP destroyed; thresholds 1000/2500/4500… | Configurable; playtest per map. |
| 5 | Determinism across versions. | Own PRNG, golden tests; never iterate unordered state in combat. |
| 6 | Copyright distance from the genre's best-known game. | Original names/lore/art only; art bible rules; mechanics only as inspiration. |
| 7 | AI quality. | Utility AI on top of the forecast; AI only ever uses GameSession commands. |
| 8 | GUT not yet vendored. | Swap when network allows; runner is assert-compatible. |
| 9 | Art consistency of AI-generated assets. | Spec → generate → quantise → outline → validate pipeline. |

## 8. Prioritized implementation checklist

1. [x] Project skeleton, data registry with validation, seedable RNG
2. [x] Map, terrain costs, roads, A*, fog of war, movement, pickups, turns/days/weeks
3. [x] Combat engine, forecast, battle report, XP, save/load
4. [x] Headless tests (53), balance report, screenshot smoke test
5. [ ] Combat balance pass (risks 1–3)
6. [x] Mines + towns + building tree + recruitment + weekly growth (Phase 2)
7. [~] Level-up dialog (seeded weighted offers from class skill_weights, points can be banked) and multiple
   heroes with selection (roster, click, Tab; heroes block each other) done; army management (split, merge,
   swap between hero, garrison and adjacent heroes: `GameSession.transfer_stack`) done
8. [x] Encounters framework (choice events) + 13 encounter types, persistent hero marks (save version 3)
9. [x] Strategic AI opponent (explore, capture, recruit, fight via forecast, defend towns)
10. [x] Procedural map generator (zone templates)
11. [x] Asset pipeline + first coherent art set per art bible (hand-authored/procedural; AI generation hook ready)
12. [~] Main menu, new-game setup, save slots, victory/defeat, hero battles, sieges, hot-seat, end screen done
    (5d); campaign layer (hero carry-over, level caps, kept artifacts, campaign saves), 18 hero classes, 15 skills,
    24 artifacts and battle arts done (5f); campaign menu open
13. [x] Six factions with 8 tiers + upgrades, 32 wild creatures, 18 new abilities (docs/FACTIONS.md)
15. [ ] GUT migration
16. [x] Rare map buildings (8 sites) and random events (weekly omens, daily fortunes), see 5h
14. [x] Audio system: buses, persisted volumes, data-driven events, procedural placeholder sounds and music (5e)

### Enemy turn encounters

Human players receive a saved, once-per-hero warning the first time a hostile hero enters explored ground, including during computer movement. An incoming computer attack pauses for a defense forecast and the usual watch option. A defending hero can flee to its home town, or another held town if home is unavailable; the attacked town cannot be the destination. Fleeing is disabled when no safe held town has room. The hero keeps equipment and progression but leaves its entire army behind, loses the rest of its movement, and its abandoned side deals 50% less damage for that battle. Survivors of the abandoned hero army do not rejoin the hero. A town's separate garrison remains subject to normal siege casualties.

### Road traders

New maps may contain one persistent, unguarded **Road Trader**, an ordinary
`site` with kind `trader`. On a small 70×70 map the chance is 50%; for area A,
`chance = 1 - 0.5^(A / 4900)` (75% at twice that area). Generated maps put the
shop in reachable neutral territory after other content, using its own seeded
RNG stream. Authored maps roll once when starting a new game. Existing saves
never gain a trader retroactively.

`data/sites.json` defines the stock: one random minor, major and relic artifact
at their listed gold values, plus three Wayfarer's Charts at 750 gold each.
Each chart immediately uncovers up to 40 distinct previously unexplored random
tiles, sharing those discoveries with allies. There is no charge if the whole
map is explored. Purchased artifacts follow normal auto-equip/pack rules.
`GameSession.trader_info`, `trader_buy_error`, and `trader_buy` handle the UI and
atomic purchases. A trader's `stock` array holds `{kind, artifact?, tiles?, price,
remaining}`; it persists in save version 16 without restocking. Older saves
remain supported.

The illustrated shop opens through normal map visits, and clicking a selected
hero already standing at the trader reopens it. Charts stay above the scrollable
artifact list. The interface shows item artwork, descriptions, gold, quantities,
and reasons a purchase is unavailable. Original art prompts and provenance are
in `assets/source/traders-001/manifest.json`; sprite specs are in
`assets/specs/objects.json`, and the shop illustration spec is in
`assets/specs/trader_art.json`. Use `tools/trader_preview.gd` for renderer QA.


## Gameplay variety update (2026-11-09)

The existing headless command boundary now also serves mission objectives, invasions,
quests and strategic gates. Content remains JSON; no scene scripts define game rules.

- `ScenarioRules` reads `GameState.rules.scenario`, evaluates required objectives and
  losses, and records visits along movement paths. Reach, current town ownership,
  hero defeat, survival through an inclusive day, clearing invasions, and endless
  survival are supported. Scenario victory replaces ordinary conquest for that game.
- `WaveDirector` snapshots warning/spawn progress and explicit assault/raid/defend/escort
  orders in `GameState.scenario_runtime`. Reserved invasion slots survive between
  waves; dormant ally slots activate only when earned. Armies spawn in declared entry
  bands and queue when every entry is blocked. Orders use normal session commands,
  fight obstructing heroes, and replan around sealed gates. Allies defend adjacent
  to another player's town rather than occupying its gate.
- `ScenarioQuests` keeps persistent conversations and hero-carried quest inventory,
  validates hand-ins, grants rewards once, activates alliances and merges explored
  terrain, and schedules weekly reinforcement support. Fallen carriers drop their
  relics. Captured support sites restore scouting, suppress future armies, supply
  volunteers, or seal a tunnel. Weekly deliveries are idempotent.
- `AdventureMap` indexes gate objects for constant-time passability checks. A closed
  gate overrides a road. Sealing checks both invasion reachability and continued
  access to mission locations before committing, then refreshes player pathfinding.
- `MapTopology` chooses physically available borders after zone partitioning. Fair
  edge groups preserve rotational opportunity; Adventure groups can differ. New
  versioned templates use branching or ring graphs; three-to-six-realm Adventure
  templates use asymmetric regional rolls. Classic template IDs remain intact.
- `MapValidator` always checks structural connectivity and start safety. Fair maps
  retain signature/value/distance tolerances; Adventure maps require viable basic
  income instead of equal starts. Quest references and scenario definitions are
  checked with map and content registries when available.
- `ScenarioGenerator` loads versioned `data/scenario_recipes.json` recipes via
  `scenario:<recipe>:<seed>`. Siege variants stretch an authored strategic skeleton,
  bind support roles, vary commanders/compositions and arrival days, and offer
  survival, multi-town defence and endless continuation. Expedition generation uses
  a connected maze, verifies actual weighted movement cost, then offers a stronger
  shortcut guardian, lighter road guardians, survey rooms and volunteers. The
  deadline reserves at least five days beyond basic travel.

Save version 17 snapshots runtime orders, inventory, warnings and support alongside
objective progress and the scenario definition. Old saves default to empty scenario
state. Saved terrain and objects load without regenerating changed recipes.
Generator version 5 records policy, layout family and recipe version. Final-tile
habitat selection uses an isolated RNG stream and retains value/placement budgets.

`ScenarioDialog` and the HUD read session summaries and invoke commands for actions;
New Game exposes separate mode, generation policy, faction/class and difficulty
choices. Fixed scenario roles cannot be closed or turned into opponents by setup.
Faction conversion retains starting recruitment tiers and fortifications.

The original campaigns keep their authored objectives. `long_watch` is a new
three-chapter campaign demonstrating the shared systems. Balance is an initial pass;
scripted playthroughs and headed UI checks are recorded in the gameplay verification
report, with the pre-existing regression failures kept separate.

## Map overhaul scenario mechanics (2026-11-09)

Building blocks for the campaign scenario types of the map overhaul (townless start,
2v2 with an AI ally, gated missions, betrayal). All rules are headless and data driven.

- **Villages** (`data/sites.json` kind `village`, `MapSites`): a guarded site with a
  one-off `stock` of at most two `[creature, count]` stacks. The first player to free it
  keeps it for good and recruits from it like a dwelling (`site_recruit(..., creature)`);
  it never refills. Authored villages without a stock get `stock_types` creatures of the
  site's pool from the object id. The random generator never places villages.
- **Townless recipe** (`scenario_recipes.json` mode `townless`, `ScenarioTownless`): any
  generator template; the scenario player keeps one hero, its start town turns neutral at
  `town_days` from the hero, and 3-5 villages selling the player's tier 1-3 folk sit at
  `village_days`. Stocks are scaled so the starting gold buys `stock_share` of them; the
  town garrison is tuned with combat forecasts so the starting army alone wins at most
  `town_win[1]` and the best affordable army wins every forecast fight. Measurements are
  stored in `scenario.townless`.
- **Objectives** (`ScenarioRules`): new types `conquer` (every rival out) and
  `ally_survives {player, until_betrayal?}` (losing that ally loses the scenario). Any
  objective may carry `unlock_day`, `optional` (not needed to win) or `after_betrayal`
  (hidden and incomplete until the betrayal). Mission sites (`scenario_site`) take
  `unlock_day` too. 2v2 chapters use the existing `setup.players[i]` fields (faction,
  hero_class, difficulty, team) plus `ally_survives`.
- **Week-one rule** (`ScenarioGating.week_one_problems(session)`): lists optional goals
  (mission sites, quest relics, optional reach/town objectives) that a starting hero can
  reach within 7 days of movement and whose guard its starting army beats (forecast >= 50%;
  unbeatable guards on the way block the road). Mission recipes and campaign builders
  should return no problems.
- **Betrayal** (`ScenarioBetrayal`, scenario `betrayal`): `{player, joins, trigger: {day |
  towns_lost | reach {pos, radius} | towns_taken {towns, count?, by?}}, text?, reinforcements?}`.
  `towns_lost: P` fires once P holds no town at all; `towns_taken` fires once player `by`
  (default the scenario player) and its allies hold `count` (default all) of the listed towns,
  e.g. "when the second granary falls", or with `by` = the enemy and the player's own towns,
  "when the player loses a town". When a trigger fires (checked
  every new day and in every `VictoryRules.update`), the traitor takes the joined player's
  team, optional reinforcements join its first town, and the scenario player gets the news.
  Save version 20 records `scenario_runtime.betrayal = {day}`.
- **Probes** (`tools/scenario_probe.gd`): `townless` (200 seeded fights per seed against the
  targets), `match` (AI-only runs of a map, scenario or `campaign:<id>:<chapter>`, with an
  optional passive player for "ally without help" checks) and `gating` (the week-one rule).

## Free mode and mission recipes v2 (2026-11-09)

Phase 2 of the map overhaul: the free-mode list offers the random map (size, players,
teams, layout family, monsters, treasure and scenario type) plus curated seeds, and the
mission recipes run on the map generator.

- **Ids**: `scenario:<recipe>:<seed>` or `scenario:<recipe>:<template>:<seed>`; the
  template (a hand-written or `random_...` generator template) replaces the recipe's own,
  so random-map options apply to missions (`ScenarioGenerator.make_id/parse_id`).
  `current_recipe(mode)` is what menus offer; recipes with `"legacy": true` (the v1
  sieges stretched from Last Watch, and the 1-tile maze) stay loadable for old saves and
  ids but are not listed. `players(recipe, template)` gives the setup slots without
  generating.
- **Sieges** (`ScenarioSiege`, survival/defence/endless v2): recipe `template` and
  `waves: [[day, strength]]` (strength = wave value / the defender's two starting
  heroes). The first start becomes a developed castle (dwellings to tier 3, a market, one
  fortification, a garrison) with `hero_watch` and `hero_scout`; other starts turn
  neutral and garrisoned; the nearest unprotected town becomes the potential ally, won
  with a relic quest. Defence protects the castle and the two nearest towns. Two entries
  sit in the zones farthest from kept towns within five days' march. Mission sites are
  gated for week one: the forge and the envoy open on day 8-10; the watchtower, the siege
  camp and the relic keeper get guards that the combined starting army (both heroes and
  the garrison) beats under 40% of the time, grown from half its value in 10% steps;
  `scenario.siege.guards` records that and the forecast for the same army plus three
  weeks of castle growth (`later_win`).
- **Maze** (`ScenarioMaze`, labyrinth v2): cells on a three-tile pitch (two-tile
  corridors), three 2x2-cell halls, biome rings around the centre and stone/water walls.
  The only one-tile openings are guarded: sentinels narrow doorways on the safe route,
  and a keeper holds the shortcut. Dead ends hold the survey chamber, volunteers, guarded
  armour and supplies; mission sites within a week's march open on day 8-10.
- **Long Watch** keeps its hand-made first chapter, now gated (forge, watch and envoy open
  in week two; camp and relic keeper outfight the combined starting army), and moves its
  later chapters to `scenario:defence_v2:19` and `scenario:labyrinth_v2:37`.
- **Probe**: `tools/scenario_probe.gd -- recipes [seeds] [out.md]` runs the week-one rule
  over seeds 1..N of every offered recipe and reports when each optional goal opens.

### Army veteran progression (active)

Every stack accompanying a hero earns that hero's awarded experience, including experience bonuses. Veteran Training is a learnable command skill that adds 10/20/30% stack XP. Cumulative thresholds for levels 1–5 are 0, 1,500, 5,000, 13,000 and 35,000. Level 2 grants +1 attack/defense; level 3 promotes to the existing improved creature (including its abilities); level 4 adds another +1 attack/defense. Level 5 is the Ascendant form: +20% health and damage (rounded up) and another +2 attack/defense, with dedicated portraits and movement/attack animations for all 64 faction creatures. Wild creatures retain their existing appearance. These bonuses stack with hero and faction-building effects.

Improved creatures recruited or upgraded at a town start at level 3. Only the same creature at the same veteran level can merge, with count-weighted average XP; splits and swaps preserve progress. The hero Units tab and army badges show level and progress. Save version 17 adds veteran XP; older saves initialize base units at level 1 and improved units at level 3. The thresholds and minor rank bonuses are implemented in Army; runtime visuals use the separately staged veteran animation pack, keyed by improved creature id rather than a recruitable creature id.

## Living maps (2026-11-09)

Design decision after the roadmap: battles stay quick, and the depth goes into the map. This update roughly
triples the map content and gives every faction one adventure-map mechanic.

**Faction map mechanics** (`data/faction_mechanics.json`, `src/game/faction_mechanics.gd`). One per town
faction, validated (every town faction has exactly one, no two share one). Player-wide ones follow the
player's faction, hero ones the hero's own faction. Nothing new is saved: markers are hero boons.

| Faction | Mechanic | Rule | Hook |
| --- | --- | --- | --- |
| Concord | Levy of the Shires | each week every town gains 2 tier-1 recruits per mine held (max 12) | `_weekly_growth` |
| Ashen Host | Brand and Plunder | capturing a mine pays 4 days of its output; a rival's town 3 days of income | `_capture` |
| Hollow | Grave Harvest | after a won battle, 10% of the slain living enemies' hit points rise as Shamblers | `attack` |
| Thornwood | Wildwalk | forest costs 90% less extra movement, swamp 50% (hero mods, capped like other cuts) | `Hero.modifiers` |
| Sunken Forge | Deep Roads | a hero by an own mine or in an own town travels to any other; needs half a day's movement, spends the rest | `deep_road` command, hero screen Spells tab |
| Frostmarch | Feast of Victory | the first won battle of a day gives back 33% of a day's movement | `attack` |
| Umbral Court | Whisper Web | own mines and sites see 5 tiles every day; each week starts with the land around every enemy hero revealed | `_start_new_day` |
| Abyssal Shoal | Tidebound | a hero starting the day on swamp/ford or next to water/ford moves 25% farther that day | `_start_new_day` |

The faction picker tooltip and the hero screen name the mechanic. **AI**: `faction_capture_bonus` (plunder
and levy raise mine and town values), `harvest_value` (Hollow values neutral armies by the Shamblers they
would raise), `_take_deep_road` (a Forge hero with most of its movement left tunnels when that saves more
than a day) and deep-road returns in `_teleport_to_defend`. Wildwalk, Tidebound, Feast and Whisper Web need
no decisions.

**Encounters**: 13 → 41. The 28 new ones (`data/encounters.json`) give every faction at least one choice of
its own, add three marks (Grove-Sworn, Grove-Breaker, Tide-Sworn) and three effects: `boon {mods, days}`,
`mana {amount}`, `veteran_xp {amount}`. An encounter may name a `sprite` (existing encounter or landmark
art, validated against the manifest; default `encounter_<id>`). The generator draws from 21 low-risk and 20
high-risk encounters and places about twice as many per map (2 per start, wild, flank and valley zone, 3 in
the centre and ruins, 1 in minelands).

**Ascension encounters** (2026-11-10): two high-risk encounters raise one random stack of the
hero's army straight to veteran level 5 with the `ascend {}` effect. The pick is uniform over the stacks
still below level 5 (drawn from the game's GameRng); a base creature is promoted to its improved form on the
way, as at level 3. A choice with `ascend` is unavailable while every stack is already at level 5.
*The Ember Crucible* (paid rites, or a power/faction check that costs 15% casualties on failure) and the
*Barrow of the Last Rank* (a night watch checked on Tactics and marks, with a revenant ambush on failure, or
a gold-and-crystal tithe). The AI values `ascend` as the average stack-value gain over the eligible stacks.
Generator VERSION 12 (the high-risk pool is now 22).

**Sites**: 12 → 19, with three new kinds: `watchtower` (Watch-Fire Ruin: reveals 13 tiles, once per player
and its allies), `drill` (Old Muster Field: 1500 veteran XP for every stack, once per hero) and `mana_well`
(Wellspring of the Wound: refills mana, once per hero per week; `drawn {hero: week}` on the object). Also
Lamplighters' Ossuary (+1 Knowledge), Smoulder Anvil (+1 attack and defense for 7 days), Drowned Archive
(1500 XP) and Beastmasters' Kraal (tier 2-5 dwelling). Start zones can now get the new kinds, and the open
zones 3-5 extra sites. All reuse landmark sprites.

**Cobolt trading posts** (site kind `cobolt`, `MapCobolts`, save version 23): neutral trading houses of a
non-playable five-tier people. Each post sells one recruit type, one artefact and one resource exchange (40%
below one market), restocks weekly to a cap, and keeps a concealed garrison that scouting never fully reveals.
Robbing commits the player to local hostility; a won robbery pays a fixed cache and leaves a permanent ruin.
Generated maps place 1-3 posts in neutral zones and authored maps get one at new game. The AI buys recruits
there from day 8 (`cobolt_from_day`; week-one shopping let duels snowball into early capital rushes), never
forecasts the hidden guard and never robs. Details: `docs/design/COBOLTS_IMPLEMENTATION.md`.

**Map-wide omens** (`data/events.json`): the Grey Cough (plague: each day living stacks lose 3%, rounded
down, never the army's last creature; undead and constructs are spared; growth -10%), Something Walks (a
roaming horror, `src/game/roaming_threats.gd`: one of four wild packs, scaled by week, rises at least 10
tiles from any town and walks 7 tiles a day toward the nearest held town; at an undefended town it takes
1500 gold and half the recruits, then leaves; beating it pays 2500 gold and 3 gems, which the AI values),
Hunters' Moon (+0.25 gold per XP for beating neutral armies), the Ember Fair (+20% gold) and the Long Night
(-1 vision). Roamers are ordinary neutral armies with `roamer`, `steps`, `bounty` and `ravage` keys.

Generator VERSION 11. No save version change: every new field lives on map objects or hero boons and has a
default.
