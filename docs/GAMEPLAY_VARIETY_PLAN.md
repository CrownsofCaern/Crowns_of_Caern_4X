# Gameplay variety update

Agreed direction, 2026-11-08. Implementation completed 2026-11-09; verification
results are in [the delivery report](reports/GAMEPLAY_VARIETY_VERIFICATION.md).
This is an incremental update to the existing headless,
seeded engine. Campaigns and free play share scenario systems; authored stories
choose their events and geography, while procedural scenarios generate variations.

## Player experience

- Campaign missions have distinct goals: reach a labyrinth's centre by the end of
  day 21; defend a castle and two towns; recover a guarded relic to win an ally.
- Survival balances preparation at home against expeditions that earn troops,
  information, allies, or time. Begin with a finite final siege and later offer
  endless continuation.
- Ordinary conquest maps also become less predictable. Geography and route choices
  must vary, not merely the placement of decorations, treasure, or terrain patches.
- Optional objectives change the war: seal a shortcut, suppress a siege camp, earn
  weekly reinforcements, or reveal an approaching commander.

## Map generation policies

Expose two clearly described choices in free-game setup:

| Policy | Guarantees | Allowed variation |
| --- | --- | --- |
| Fair | Comparable starting economy, access costs, safety, expansion opportunities, and distances to rivals | Several graph families; varied connections, loops, chokepoints, terrain and reward locations within measured tolerances |
| Adventure | Valid starts, usable economy, reachable required content and viable objectives | Unequal regions, irregular starts, uneven resources and rewards, contested windfalls, alternate routes and stronger regional identities |

Fair is the future competitive/ranked candidate; this update does not imply that a
ranking or matchmaking service exists. Preserve current template IDs. Version new
layout recipes rather than silently replacing existing geography. The habitat
correction deliberately updates newly generated armies while retaining placement
and value budgets. Save snapshots retain the actual geography and scenario definition.

Separate four concepts: game mode (conquest/survival/expedition), generation policy
(fair/adventure), layout family, and difficulty. Adventure is not a difficulty
level. Campaigns may use explicit authored scenario validation rather than either
free-play policy. Basic structural validation always runs; competitive fairness
checks must not reject deliberate story asymmetry.

Layout families to explore:

1. Branching frontiers: multiple expansion directions, no mandatory central hub.
2. Ringlands: several routes around a central obstacle; contested cross-connections.
3. Divided marches: rivers or mountain chains with a variable number of crossings.
4. Broken basins: irregular regions joined by narrow passes, with occasional bypasses.
5. Rich heartland: competing approaches to valuable central territory, with outer routes.
6. Expedition labyrinth: branching chambers, optional loops, shortcuts, and a goal region.

Choose a valid strategic graph first, then embed it into geography. The present
Voronoi generator requires connected zones to physically touch: arbitrary new
connections cannot simply be added to its connection list. Use spatially valid
adjacency selection, or a corridor-carving layout strategy with its own validation.
Fair starts need comparable opportunity, not necessarily mirrored shapes.

## Terrain-appropriate monsters

Most generated neutral armies should match the actual terrain where they stand.
Start with an 85% local-pool selection chance, using faction-native terrain and
positive creature terrain affinities, with outsiders retained for variety. Both
stacks of a local army use the local pool. Keep army value budgets and shared
mirrored compositions on matching terrain; terrain bonuses still need combat balance
review. Apply this after placement, including mine/site guards, without moving map
content. Keep authored story armies and town garrisons unchanged. Rivers and bridges
use their combat terrain as the initial fallback; explicit habitat metadata can
later distinguish road bands, aquatic creatures, ruins and regional ecology.

## Shared scenario architecture

Keep rules in RefCounted classes and content in validated JSON. GameSession is the
command boundary. All random choices use GameRng and stable ordering.

- Scenario rules: explicit participant, required objectives, failure conditions,
  inclusive deadlines, and progress. Suppress ordinary conquest victory while a
  scenario is active; allow explicit townless expedition participants.
- Quest system: persistent quest givers, player-level progress, hero-carried hand-in
  items, exactly-once rewards. Keep required relics distinct from interchangeable
  equipment IDs; reserve quest inventory capacity or use dedicated quest items.
- Wave director: authored schedule first, later seeded army budgets and compositions;
  warning lead time, safe spawn locations, queued blocked spawns, maximum active
  forces, and saved commander orders. No invisible scaling to the current army.
- Commander behaviour: attack a named stronghold, raid an economy, escort, or defend.
  Reuse normal commands and combat; do not rely on ordinary loot utility to create
  an invasion. Explicitly support invasion players between waves without eliminating
  them or accidentally declaring conquest victory.
- Strategic gates: persistent open/closed state understood by all pathfinding
  and UI. Closing a road must override the existing rule that roads make tiles passable.
- Scenario generator: bind semantic roles (castle, ally town, relic guardian,
  shortcut, invasion entry) before terrain/content filling. Required guardians must
  genuinely gate their reward; the ordinary generator's adjacent-guard fallback is
  insufficient for a mandatory quest.

Evaluate objectives after completed commands and at day boundaries. Track visits
along movement paths. Define precedence: mandatory losses take priority over
success; reach goals are latched; ownership goals describe current ownership;
"survive through day N" completes on the transition to day N+1. Defeat and victory
screens must explain the scenario outcome. Snapshot definitions and progress in
versioned saves; old games retain standard conquest rules.

## Delivery milestones

### 1. Objective foundation — first implementation

- [x] Write this plan, including ordinary map variety and generation policies.
- [x] Add validated reach, control-town, defeat-hero, and survival objectives.
- [x] Add protected towns, required heroes, inclusive deadlines and explicit townless exemptions.
- [x] Integrate campaign chapter definitions, movement/battle/turn checks and result text.
- [x] Save definitions/progress with migration for existing saves.
- [x] Verify last-day completion, defeat precedence, current ownership, campaign wiring,
      old saves, and ordinary conquest behaviour.

This is engine infrastructure. Existing story chapters keep their current objectives
until individually redesigned and playtested.

### 1a. Habitat correction — included in first implementation

- [x] Select mostly native armies using their final tile terrain.
- [x] Preserve guard budgets, reproducibility, map placement and authored armies.
- [x] Verify native frequency, secondary stacks, terrain coverage and save stability.

### 2. Geographic variety for ordinary games

- [x] Introduce explicit validation policies and versioned generator recipes.
- [x] Keep existing recipes as Fair; add two materially different layout families first.
- [x] Add Adventure variants with independently rolled regional content and irregular starts.
- [x] Expose policy and layout in setup with seed reproducibility and clear descriptions.
- [x] Validate many fixed seeds; measure route multiplicity, choke distribution, travel
  time, expansion access and economy. Fair checks retain competitive tolerances;
  Adventure checks enforce viability rather than equal starts.
- [x] Acceptance: seeds vary strategic connectivity as well as appearance; old IDs remain stable.

### 3. First authored survival mission

- [x] One castle, two invasion corridors, escalating named commanders, announced waves,
  and a finite final siege. Final victory requires clearing surviving invasion armies.
- [x] Add orders and invasion-player lifecycle before wave generation.
- [x] Add objective progress and wave warnings to the HUD, plus map markers and readable
  loss reasons. Existing gameplay UI receives scenario summaries through GameSession.
- [x] Acceptance: attackers pursue assigned objectives, spawns cannot strand forces, saving
  between warning/spawn/attack preserves the schedule, no victory between waves.

### 4. Expeditions that change the siege

- [x] Add persistent relic-for-alliance quest; first reward can be direct town ownership
  or scheduled reinforcements, followed by autonomous allied defence.
- [x] Add capturable nest with explicit "seal tunnel" action and an alternate invasion route.
- [x] Acceptance: rewards fire once, transfer of the quest item works, sealing adds a
  measurable delay, all required locations remain reachable, AI adapts its route.

### 5. Generated survival and timed labyrinth

- [x] Extract proven mission structures into seeded scenario recipes.
- [x] Labyrinth: safe long route, dangerous short route, optional information and supplies.
- [x] Check travel budgets using actual movement rules; reserve time for battles and
  meaningful detours. Reachability alone does not prove a deadline is achievable.
- [x] Use headless seeded playthroughs and headed UI checks for pacing, casualty recovery,
  faction differences, and expedition value. The existing conquest AI is not a
  reliable solver for quest or survival balance until it understands those objectives.
- [x] Add multi-town defence variants, endless survival and more recipe combinations
  once the finite scenarios provide a stable balance baseline.

## Scope and verification

No combat rewrite, faction expansion, or general scripting language is required.
Extend a small explicit condition/effect vocabulary as playable scenarios demand it.
Run relevant unit tests after each increment and the full suite before delivery.
Record existing unrelated failures without rewriting ongoing artwork or gameplay work.

## First increment: implementation and verification

Implemented in `ScenarioRules`, integrated through `GameSession`, `VictoryRules`,
`Campaign`, and `MapValidator`. Save version 17 adds visit progress and mission runtime; the existing
rules dictionary snapshots the definition. Ordinary games have empty progress.
Campaign chapters or map JSON can now supply a `scenario` dictionary, for example:

```json
{
  "name": "The Road to the Centre",
  "player": 0,
  "deadline_day": 21,
  "required_heroes": ["hero_wren"],
  "townless_players": [0],
  "objectives": [
    {"id": "centre", "type": "reach", "hero": "hero_wren", "pos": [5, 8],
     "text": "Reach the centre before the end of day 21."}
  ]
}
```

Coordinates and hero IDs must refer to the actual map/cast. Protect settlements
with `protected_towns`; combine that with a `survive` objective's `through_day` for
continuous defence. `control_towns` requires current ownership of every listed
`towns` ID; `defeat_hero` names an existing enemy `hero` ID. Objectives are combined
with AND. `GameSession.scenario_objectives()` provides progress summaries for the
future objective UI. Existing campaign missions have not yet been converted.

Generator version 3 applies the habitat pass after content placement, using
`neutral_habitats.native_chance` in `data/map_templates.json`. Selection uses an
isolated deterministic stream and caches equivalent guards by biome, original
composition and budget. Existing saves retain their armies; new generated maps
use the habitat correction, including generated campaign chapters.

Focused verification: 15 scenario tests and 6 habitat tests pass. Coverage includes
full generated-map habitat integration, native frequency with outsiders, both army
stacks, value budgets, save round trips, last-day success, survival boundaries,
protected towns, required heroes, campaign validation, and standard-rule fallback.
The initial full run in the shared workspace included unrelated migration, veteran,
site and UI changes. PR verification uses an isolated checkout of current `main`;
its focused and full regression results are recorded in the delivery report.
Asset pipeline checks are skipped by the repository runner because its Python
environment lacks Pillow/numpy. No artwork was changed by this increment.

## Completed update

All five implementation milestones are delivered. The current engine adds
`MapTopology`, `WaveDirector`, `ScenarioQuests`, `ScenarioGenerator`, and
`ScenarioDialog` to the first increment's objective foundation. Saves now use version
17; generated maps record generator version 5 and their recipe/policy metadata.

The playable content includes The Last Watch, four generated scenario recipes,
The Long Watch campaign, two new ordinary-map layout families in Fair/Adventure
forms, and asymmetric Broken Marches maps for three through six realms. New Game
separates mode, map style, layout, and difficulty. Invasion difficulty changes army
strength explicitly; campaign/faction conversion preserves starting development.

The earned ally sends a commander to defend Northwatch, contributes weekly troops,
and remains an independent realm. Its support stops if its settlement is lost.
Entry bands prevent a single hero from camping the only spawn tile; completely
blocked entries remain queued. Sealing has a measured route delay and retains a
valid alternate path. Quest inventories and commander orders survive save/load.

Verification includes 60 dedicated feature tests, 24 recorded ordinary-map seed
samples plus four multiplayer samples, generated mission validation, six-faction
expedition playthroughs, survival win/loss playthroughs, and rendered setup/HUD/quest
screens. [The verification report](reports/GAMEPLAY_VARIETY_VERIFICATION.md) records
results and environment limitations. Human balancing feedback remains an input for
future tuning; no human playtest results are claimed here.
