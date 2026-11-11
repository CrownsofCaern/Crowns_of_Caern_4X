# Integrated map editor plan

Implementation plan, 2026-11-09. Terrain, entity and player editing are available; the complete
first-release scope is still in progress. Follow [DESIGN.md](DESIGN.md)
and reuse the game's art and UI styling from [ART_BIBLE.md](ART_BIBLE.md).

The document/history/repository foundation, title-screen entry, terrain/road/scenery
tools, object/hero authoring and player setup are in place. See [implementation progress](MAP_EDITOR_IMPLEMENTATION.md)
for verification and remaining work, and the [editor guide](MAP_EDITOR.md) for controls.

## Prerequisite: gameplay variety update

Build the editor **after** [GAMEPLAY_VARIETY_PLAN.md](GAMEPLAY_VARIETY_PLAN.md),
against its delivered scenario, generation, UI and save contracts. That plan now
marks implementation complete (2026-11-09); recheck the actual code and verification
baseline at editor kickoff rather than assuming every check is green. Its linked
delivery report was not present in this checkout during this review.

The baseline includes ordinary Fair/Adventure generation, layout families,
terrain-appropriate neutral armies, authored/generated survival and labyrinth
scenarios, objectives and deadlines, quests and dedicated quest items, invasion
waves and orders, independent allies, strategic gates and scenario save state.
Reuse these systems; the editor must not introduce parallel mission rules.

Keep these concepts separate throughout the document model, creation dialog,
map browser and validation:

| Concept | Editor treatment |
| --- | --- |
| Game mode | Preserve the engine's actual mode IDs, including conquest and the delivered survival/defence/endless/labyrinth variants. Use labels from the current setup UI rather than inventing a second taxonomy. |
| Generation policy | Fair or Adventure describes generation guarantees, not difficulty. An edited map is authored and has no inherited fairness certification. |
| Layout family | A generator choice/provenance field, independent of mode and policy. |
| Difficulty | A playtest/setup choice. Invasion strength must use the existing explicit scaling rules. |

The first editor release remains conquest authoring. Scenario maps/recipes are
recognised and previewable read-only until the scenario-authoring phase below.
Do not offer an unsupported scenario as a blank conquest copy, drop its rules,
or allow geometry edits that can silently break its scripted roles.

## Goal and first-release scope

Add a **Map Editor** entry to the title screen. A player can create a blank map,
copy a bundled map, or generate a map from a template and seed; edit it visually;
save it locally; and play it through the normal game systems.

The first release targets desktop mouse and keyboard and standard conquest maps.
It includes:

- Terrain painting with single-tile and larger square brushes, rectangle fill,
  terrain sampling, and an optional grid.
- Road painting/erasing and cosmetic decoration placement/erasing.
- Placement, selection, movement, duplication and deletion of towns, heroes,
  mines, resource piles, neutral armies, encounters, artifacts and standard sites.
- Property editing for the supported objects, including ownership, faction/town
  type, hero class, army stacks, guards, resources and amounts where applicable.
- Player slots, map name, dimensions at creation, undo/redo, save/load, import/export,
  validation, recovery drafts and playtesting.

Defer quest, gate and scripted scenario authoring, campaign construction, custom
asset imports, online sharing, collaborative editing, arbitrary map resizing and
mobile editing. Expose those object types only when their related rules can be
edited safely. Maps with unsupported scenario features should open read-only with
an explanation in the first release; copying them must not silently strip content.
New conquest content within supported types should be discovered from `GameData`
and the built asset manifest when the editor opens. Adding a registered terrain,
decoration, creature or site must not require a hard-coded palette entry. New
behaviour/object types still need validation and an appropriate inspector.

## Existing foundations and constraints

| Existing code | What we can reuse / what needs changing |
| --- | --- |
| `src/world/adventure_map.gd` | JSON-backed terrain, roads, decorations and objects. `static_definition()` deliberately excludes objects and is not a complete editor export. |
| `src/ui/map_view.gd` | Terrain transitions, sprites and tile input. Currently depends on `GameSession`, fog, players and runtime heroes; needs a document preview path. |
| `src/ui/map_camera.gd` | Camera and zoom calculations. Reuse for the editor viewport. |
| `src/world/generation/map_validator.gd` | Structure, placement, connectivity and generated-start checks. Harden malformed-input handling before using it for imported files. |
| `src/world/generation/map_generator.gd` | Seeded starting points for editable maps. Generated metadata needs an explicit policy once a map is hand-edited. |
| `src/world/generation/map_topology.gd` | Reuse delivered layout families; the editor need not implement its own geography generator. |
| `src/world/generation/scenario_generator.gd`, `data/scenario_recipes.json` | Discover scenario recipes separately from ordinary templates. First-release preview is read-only; later authoring must preserve bound semantic roles. |
| `src/game/scenario_rules.gd`, `src/game/scenario_quests.gd`, `src/game/wave_director.gd` | Reuse objective, quest, gate interaction, wave and order contracts; definitions and runtime progress must remain separate. |
| `src/core/game_data.gd` | Loads maps by ID from bundled data or a generator. Add custom-map resolution. |
| `src/game/game_setup.gd` | Discovers bundled maps for the menu. Include saved custom maps. |
| `src/game/game_session.gd` | Starts a game from a map ID. Extract a shared initialization path accepting an in-memory definition for playtesting. |
| `src/core/game_state.gd` | Current saves already embed static map data and runtime objects/heroes. Verify custom-map games load without the original editor file. |
| `src/ui/main_menu.gd`, `src/ui/adventure_screen.gd` | Integrate editor entry, game launch and return from playtest. |

## Architecture decisions

1. **A map document is the source of truth.** Add a headless `MapDocument` under
   `src/editor/`, containing the authored definition, revision/dirty state and
   editing operations. Keep camera, selection and brush settings in the UI.
   Never use a live game's mutable state as the editable source.
2. **Undo records user actions.** Add a headless command history. One paint drag is
   one command, storing changed cells before/after; placement, deletion, movement
   and property edits are commands too. Track the saved revision so undoing to it
   clears the dirty indicator. Bound history memory.
3. **Drafts may be incomplete.** A map with no players or heroes must still render
   and save as a draft. Full gameplay validity is required to playtest or offer it
   in New Game. Editing does not invoke turn progression or gameplay normalization.
4. **Share rendering, not game initialization.** Introduce a small presentation
   model for map terrain, objects, hero visuals and owner colours. Adapt `MapView`
   to accept game and document sources, extracting shared drawing helpers where
   useful. Editor mode shows the entire map without fog or movement commands.
5. **Keep runtime and authored fields separate.** Export full authored definitions
   from the document, preserving optional and unrecognised fields on safe round trips.
   Unsupported behaviours require read-only handling, not silent field removal.
   Preserve authored scenario definitions, quest links, initial gate state, wave
   schedules and orders. Do not write runtime fog, movement, recruit stock, quest
   completion, carried quest inventory, spawned-wave flags or daily state into the
   authored map. Never derive an editable source from a progressed save.
6. **Local content lives in `user://maps/`.** Add a `MapRepository` for discovery,
   parsing, saving and custom IDs such as `custom:<id>`. Keep bundled `res://data/maps`
   read-only. Imports receive a local identity; duplication creates a new identity.
   Use safe filenames independent of display names and temporary-file replacement
   so interrupted writes preserve the previous valid file.
7. **Preserve existing JSON compatibility.** Reuse the map definition schema and
   put editor-only metadata in a documented optional field or separate draft file.
   Introduce map format versioning if required, with validation/migration. Only
   bump `GameState.SAVE_VERSION` if the saved-game schema actually changes.
8. **Generated maps become authored copies.** Preserve template/seed as provenance,
   including recipe version, layout family and original policy. Audit consumers
   before separating provenance/zone data from active generation-validation metadata;
   do not blindly delete metadata needed elsewhere. The copy receives an authored
   identity and cannot retain a Fair guarantee after manual edits. An optional
   explicit fairness analysis can follow later. Generation's habitat pass runs when
   generating, not every time an edited map opens: placed armies and guards remain
   exactly as authored, including deliberate non-native creatures.
9. **References are part of the document contract.** Provide a shared reference
   index for hero, town, player, object, quest, gate and wave IDs before adding
   scenario editing. Remapping a copied map's file identity must not rename all
   internal IDs. Later entity renames/deletions must update known references as one
   undoable action or report/block the change. Unknown reference-bearing features
   require read-only handling.

## Milestones and acceptance criteria

### 1. Document model, history and file contract

- Implement new/load/copy/export operations, unique entity IDs, terrain and road
  edits, object/hero edits and player configuration.
- Record the supported post-variety schema/capabilities. Round-trip scenario
  fixtures without loss through the parser/serializer even when editing is disabled.
- Define placement rules: map bounds, occupied tiles, and the existing exception
  allowing a hero to share its owner's town tile. Invalid gameplay placement may
  remain a visible draft error; malformed document structures must be rejected.
- Implement grouped undo/redo, saved-revision tracking and repository round trips.
- Decide supported dimensions and brush limits based on current map sizes and
  renderer performance; reject invalid dimensions before allocating grids.

**Done when:** headless tests cover full-definition round trips, independent copies,
unique IDs, undo/redo across brush and property edits, dirty state and failed saves.

### 2. Editor viewport and title-screen entry

- Add `src/ui/editor/map_editor_screen.gd` and supporting controls.
- Build a central map viewport, tool palette, selection inspector and status bar;
  reuse existing UI styling, art, camera math and map drawing.
- Add full-map visibility, grid toggle, hover coordinates, selection outlines and
  brush previews. Route pointer input so panels never paint the map underneath.
- Support pan/zoom and documents without players, heroes or valid starts.

**Done when:** a blank map and a copied map render correctly; pan/zoom and selection
work; opening/exiting the editor leaves normal gameplay rendering and input intact.

### 3. Terrain, roads and decorations

- Implement brush drags, rectangle fill, terrain sampling and erasing overlays.
- Interpolate between pointer samples so fast drags do not leave holes.
- Rebuild affected terrain transitions and road visuals, including neighbouring
  tiles, rather than rebuilding the entire world for every pointer event.
- Treat roads as per-cell edits internally and serialize valid segments; preserve
  their existing bridge/passability behaviour.

**Done when:** a player can draw a river, bridge and connected road, undo/redo the
strokes, then save/reopen with identical terrain and overlays. Painting is responsive
on the largest supported size, including at viewport edges and different zooms.

### 4. Objects, heroes and player setup

- Build searchable palettes from `GameData`, with valid authored defaults.
- Discover registered additions on opening/reopening the editor, using manifest
  sprites and readable fallback visuals. Test an added content definition without
  changing palette code; raw image files alone are not registered content.
- Add type-specific inspectors; constrain creature, faction, class, building,
  encounter, artifact and site choices to known IDs.
- Support stack counts, guards, garrisons, names, ownership and other supported
  authored properties. Decoration placement remains cosmetic.
- Define how removing/reassigning player slots affects owned entities; report
  references that need fixing instead of silently deleting content.
- Preserve authored army choices; optionally suggest native creatures from the
  existing habitat rules without automatically replacing stacks or rerolling guards.

**Done when:** two players, owned towns, starting heroes and armies, guarded mines,
treasure and neutral enemies can be authored without editing JSON. Undo restores
entities and their properties exactly.

### 5. Validation, persistence and custom-map discovery

- Add defensive shape/type checks before existing validators or map constructors
  index fields. Cover road segments that could otherwise fail to terminate, invalid
  positions, negative dimensions, duplicate IDs and bad references.
- Separate draft structural errors, gameplay errors and advisory balance warnings.
  Show actionable messages and select/centre the relevant tile or entity where possible.
- Use the delivered validation policies: basic authored-map validity always applies;
  Fair tolerances are not mandatory for asymmetric authored maps. Scenario validation
  remains delegated to the shared scenario systems, even for read-only previews.
- Add Save/Save As, draft status, import/export, unsaved-change prompts and recovery
  drafts. Recovery must not overwrite the last explicit save.
- Show playable custom maps in New Game with their player slots and preview;
  invalid drafts stay available in the editor. A bad file must not break discovery
  of other maps. Handle duplicate names and missing files clearly.

**Done when:** custom maps work in an exported desktop build; drafts survive restart;
malformed imports fail with useful messages; bundled maps remain unchanged; valid
maps appear in New Game and use the existing faction/player setup rules.

### 6. Playtest and return to editing

- Extract `GameSession.new_game_from_definition(...)` or an equivalent shared factory;
  retain the existing ID-based entry point by delegating to it.
- Validate and deep-copy the current document to start a playtest without requiring
  a permanent map save. Use a fixed/editable seed and preserve authored starting
  armies and heroes by default rather than silently applying standard-start replacement.
- Suspend the document and return to the same selection, camera and undo history
  on exit. Playtest actions must never mutate the document.
- Isolate playtest autosaves from ordinary game saves and campaign progress.
- Preserve the post-variety factory behaviour, including scenario rules, reserved
  invasion/dormant players and setup restrictions, when extracting initialization.
  Add regression tests using delivered scenario fixtures even though scenario
  editing/playtesting from the editor is deferred in the first release.

**Done when:** an unsaved valid map can be played, exited, edited and played again.
A saved custom-map game still loads after the source map is edited or removed.

### 7. Release verification and documentation

- Add headless tests for commands, file handling, validation, custom discovery,
  session creation and save independence using the existing test runner.
- Add renderer/input smoke checks and capture editor screenshots; visually inspect
  terrain transitions, sprites, inspectors, overlays and different window sizes.
- Exercise the complete flow: create → paint → place → validate → save → restart →
  New Game → save/load game; separately verify playtest → return and crash recovery.
- Run `./run_tests.sh`, check an exported desktop build, and document controls,
  file locations, import/export, draft errors and first-release limitations.
- Capture the gameplay-variety regression baseline before editor changes. Cover
  ordinary Fair/Adventure maps, seeded recipes, authored armies, survival lifecycle,
  quests, gate/pathfinding behaviour and scenario save snapshots. Record unrelated
  baseline failures separately rather than changing concurrent gameplay/artwork work.

**Done when:** the complete flow and editor tests pass, and no new regression
appears against the recorded baseline in normal maps, procedural generation,
campaigns or existing save loading. Report any remaining baseline failures explicitly.

## Follow-on: scenario authoring on the delivered engine

This is a separate phase after the conquest editor, not a prerequisite for shipping
it. Establish the preservation/reference contracts above now so this phase extends
the same document, inspector, validation and playtest systems.

1. **Objectives and participants.** Add inspectors for the engine's explicit
   objective vocabulary, inclusive deadlines, protected towns, required heroes,
   townless participants, invasion players and dormant allies. Pick references from
   the map rather than typing IDs. Preserve AND semantics, latched reach goals,
   current-ownership goals, failure precedence and survival day boundaries.
2. **Quests, sites and gates.** Add scenario-site and dedicated quest-item palettes,
   guard/reward links, once-only rewards, allied support and gate initial state.
   Render closed gates over roads correctly; path previews must use the same
   passability rules as gameplay. Reference-aware edits include quest hand-ins,
   protected entities, suppressible invasion sites and alternate routes.
3. **Waves and commander orders.** Add schedule/entry overlays and inspectors for
   warnings, entry bands, target IDs, army composition, explicit orders, active-force
   limits and supported endless-wave settings. Validate spawn-to-target routes and
   referenced players. Use the engine's queued-spawn and scaling behaviour unchanged.
4. **Generated scenario copies.** Instantiate current recipes with a seed into a
   complete authored snapshot, preserving semantic roles, recipe provenance and
   explicit armies. Do not edit generator algorithms or regenerate geometry on save.
   Show stale travel-budget metrics after geometry edits; recalculate using actual
   movement costs and flag that battles/detours require playtesting. Reachability
   alone does not establish a viable deadline or a genuinely guarded mandatory relic.
5. **Scenario playtest and save checks.** Run existing HUD/objective/quest screens
   through the shared session factory; restart from a clean definition each time.
   Test last-day success, loss precedence, survival through day N, final-wave clearing,
   no victory between waves, blocked entries, exactly-once quest rewards, independent
   ally support, closed gates over roads and mid-scenario save/load. Verify the
   source document and undo history remain untouched.

**Done when:** an authored survival mission and a timed labyrinth can be created or
copied, edited, validated, saved and playtested without JSON edits; scenario definitions
round-trip and saved progress remains independent of later source-map changes.
Campaign/chapter assembly and a general scripting language remain outside this phase.

## Delivery order and checkpoints

First confirm the gameplay variety update and its regression baseline. Then implement
milestones in order, with a small renderer spike during milestone 1 to
confirm the presentation interface before committing to it. Ship reviewable slices:

1. **Foundation:** document/history/repository tests and a blank-map rendering spike.
2. **Usable drawing tool:** title-screen entry, viewport, terrain/road/decorations,
   save/reopen and undo. This is an internal prototype, not the finished editor.
3. **Playable authoring:** objects, players, robust validation, custom-map discovery
   and isolated playtest/return.
4. **Release:** recovery, import/export polish, regression checks and documentation.

The largest uncertainties are renderer decoupling, malformed-input handling in
validators, and editor/playtest screen lifecycle. Reassess effort after the foundation
slice; the earlier “several days” estimate applies to a prototype, while the complete
first-release scope is a multi-week effort depending on polish and findings.
