# Map editor implementation progress

2026-11-09. Tracks delivery of [MAP_EDITOR_PLAN.md](MAP_EDITOR_PLAN.md).

## Custom-map launch and playtest slice

Added `MapPlayability` launch checks, safe custom-ID loading and discovery of valid
saved maps in New Game. Drafts and malformed files stay out of the playable list.
Custom setup preserves authored names, arbitrary colours, hero classes/counts and
armies; explicitly empty garrisons stay empty. Missing files fail without replacing
the current game. Save snapshots remain independent of source-map files.

`GameSession.new_game_from_definition` shares the ordinary initialization path.
Editor playtests run in a separate game controller, keeping the draft, undo history,
camera and prior game intact. Autosave/manual save/load use a temporary directory,
cleaned on return. Playtest menus cannot start campaigns or replace the test with
another game. Window close returns to the draft and checks unsaved changes.

Eleven custom-map tests and a scene integration test pass. Scene checks cover actual
movement, save/load isolation, repeatable seeded restarts, return/window-close flow,
custom-map setup/Begin, missing files, and save loading after source deletion.
Headless and OpenGL smoke checks pass. The full suite ran 701 tests with the same
nine known gameplay failures (435.2 seconds); final garrison/save-label refinements
also pass focused checks. The art pipeline remains skipped for missing Pillow/numpy.
The earlier terrain scene smoke now redirects its autosave into its test directory.

## Entity and player authoring slice

The screen now supports placement, movement, duplication, deletion and property
editing for ordinary map objects and heroes. **Objects & heroes** exposes a
searchable, illustrated palette populated from the content registry. Owned types
offer player selection; heroes require a player. Inspecting a tile with a town and
friendly hero offers both through an entity picker. Scenario maps remain read-only.

`MapAuthoring` supplies headless defaults and validated commands. It rejects occupied
or impassable placement, invalid content IDs/counts/owners and unsafe guard deletion.
A hero may share its own town. New heroes use their class faction's starting army;
copying or editing an existing hero never rerolls it. Move preserves identity;
duplicate assigns a fresh ID. Unexposed metadata survives property edits.

`MapEntityDialog` provides type-specific fields, built-building selection, army/
garrison/guard stacks, quantities, guard links and dwelling recruits. `MapArmyEditor`
filters registered creatures and supports ten stacks without runtime army merging.
Invalid edits stay in the modal and do not partially update the document. Unknown
creatures and malformed stack data require explicit correction rather than silent
removal. Changing site kinds adapts the available controls and removes obsolete
dwelling fields. Player and entity dialogs use the existing dark/brass theme.

`MapPlayersDialog` stages up to eight players, with names, faction, controller,
colour, difficulty and team. Applying changes normalizes slot IDs and remaps all
owned objects/heroes in one undo action. Removing an owned slot is blocked until
entities are explicitly reassigned or deleted. Faction edits preserve existing town
types, hero classes and armies. Unknown per-player fields are retained.

Draft structural checks now reject malformed player IDs, owner types, colours and
other fields needed by the UI. This remains separate from complete gameplay
validation. A lifecycle fix also keeps `MapView` presentation nodes owned before its
first binding, avoiding orphaned nodes when entering the editor from the title screen.

### Entity/player verification

- Twelve headless command tests pass, including default placement for every
  registered entry, collisions, own-town sharing, property preservation, malformed
  stacks, guard references, player remapping/removal, invalid drafts and read-only
  scenario protection.
- A new scene integration test drives the actual palette, canvas, property/player
  dialogs, army edits, moves, duplication, deletion, undo/redo, guard unlinking,
  dwelling kind changes, dynamic content discovery and local file round trips.
  Its authored fixture also passes the shared `MapValidator`.
- All 43 editor tests pass in focused checks. The existing terrain scene check and
  all 17 document tests continue to pass. The scene smoke passes headless and with
  OpenGL; screenshots cover the player dialog, hero properties and entity canvas.
- Full run: 689 tests, 680 passed and the same 9 known gameplay failures (449.5
  seconds). This run overlaps the final refinements; the latest extra malformed-
  shape test and refined dialog paths pass in focused checks. There are no script
  errors. The known failure list is recorded below.
- The runner still skips the art pipeline because its Python lacks Pillow/numpy;
  full-suite cleanup warnings remain. No asset definitions or artwork were changed.

```sh
godot --headless --path . --script res://tools/editor_entities_check.gd
godot --path . --script res://tools/editor_entities_check.gd -- /tmp/reignem-entities
./run_tests.sh test_map_authoring
```

The scene check uses and removes a per-process test maps directory. It does not
modify the player's saved maps or ordinary game saves.

## Terrain editor slice

The title screen now offers **Map Editor**. `MapEditorScreen` provides New/Open,
Save/Save As, names, undo/redo, unsaved-change prompts and a tile inspector. Existing
games are suspended behind a separate canvas and remain available through Resume.
Window close uses the same discard guard and restores the normal close policy when
leaving the editor. See [the user guide](MAP_EDITOR.md) for controls and limitations.

`MapEditorViewport` owns the clipped canvas, pan/zoom, optional grid, selection and
brush/rectangle previews. Painting supports terrain, roads/bridges and registered
decoration kinds, including explicit suppression of automatic scenery. Mouse drags
interpolate intermediate cells and group changes into one undo action; Escape rolls
back the current stroke. Painting is blocked outside the canvas and during modal
dialogs. Missing players/heroes do not prevent editing or saving a draft.

Palettes read the terrain registry and built decoration manifest when opening.
Copied maps show authored objects/heroes without gameplay initialization or army
normalization. Scenario-bearing maps remain read-only, with inspection and camera
controls available. Save As opens an independent saved copy with fresh undo history.

The renderer's existing per-cell logic is now shared by full builds and incremental
preview updates. Ground, transition, scenery, roads, high-resolution roads/barriers
and infernal glows are updated in place. Terrain changes include the eight-tile
barrier-biome search radius plus neighbouring transitions; road/scenery changes
update their neighbours. Existing sprites are retained during terrain changes.

### Terrain editor verification

- Five brush-geometry tests cover fast drags in all directions, clipped square
  brushes, rectangle orientation and size bounds.
- `test_map_editor_ui` runs `tools/editor_ui_check.gd` in an isolated headless scene.
  It checks title-screen entry, pointer strokes, grouped undo/redo, rectangles,
  bridges/erasing, scenery suppression, sampling, pan/zoom, modal/canvas boundaries,
  save/reopen/Save As, overwrite cancellation, Escape cancellation, dirty exits,
  window-close guarding, scenario preservation and an existing game's isolation.
- Incremental atlas cells match fresh full builds, including occupied hero tiles,
  barrier-biome changes and glow counts. Terrain edits retain their layer instances.
- The scene smoke passes with headless and OpenGL renderers. Title and editor
  screenshots were inspected at 1280 × 800 and 1024 × 720.
- The original 17 document tests and 20 shared asset/terrain tests also pass.
- Full-suite comparison: 676 tests, 667 passed and the same 9 known gameplay
  failures (581.8 seconds); the failure list is recorded below. No script errors.
  The subsequently added scene-integration unit test also passes separately after
  the final game-suspension/window-close checks. Together with the foundation and
  brush tests, all 30 editor tests pass.
- Asset pipeline checks remain skipped by the runner because its Python lacks
  Pillow/numpy. Existing full-suite cleanup warnings remain; this work changes no art.

Run the scene checks / capture screenshots:

```sh
godot --headless --path . --script res://tools/editor_ui_check.gd
godot --path . --script res://tools/editor_ui_check.gd -- /tmp/reignem-editor-ui
```

The smoke uses a per-process temporary maps directory and removes its files. It
does not write to the player's normal maps or saved games. It uses bounded execution
and can also be run through `./run_tests.sh test_map_editor_ui`.

## Foundation slice

The initial slice delivered the headless document and repository plus a shared-
renderer spike. It has since been extended by the terrain editor described above.

### Document and editing

`src/editor/map_document.gd` owns a deep copy of the complete authored definition.
It supports blank drafts, independent copies, terrain/road edits, decoration lists,
player lists, object/hero insertion and updates, deletion, names and unique IDs.
Moving or changing entity properties uses the same reversible entity update.

Undo/redo groups a drag or multi-step operation into one action. Terrain changes
store cell deltas; repeated changes to one cell are combined within an action.
Cancellation restores the original values. Saved revision tracking survives undo,
redo and branching, and history is capped at 8 MiB. Entity-list edits currently
store before/after lists; finer entity deltas can follow if profiling justifies them.

Draft checks reject malformed grids, invalid dimensions/coordinates, duplicate IDs,
unknown terrain and non-terminating road shapes before map construction. Dimensions
have a defensive ceiling of 256 per side; the largest bundled maps currently use
71 columns and 52 rows. Final UI size presets and performance targets remain part
of viewport work. Draft placement diagnostics report impassable tiles and collisions,
with the existing exception for a hero sharing its owner's town.

Unknown fields are preserved. Scenario-bearing maps and unsupported object types
are read-only; this includes the delivered gameplay-variety content. Generated
copies preserve the full original generator snapshot under `editor_source`, keeping
internal IDs while dropping the active top-level Fair validation contract. The
current source audit found only `MapValidator` consumes that top-level metadata.
Authored armies are never rerolled by opening or editing a document.

### Local files

`src/editor/map_repository.gd` defaults to `user://maps/`. Local definitions use
`custom:<id>` and safe filenames. Save writes and flushes a temporary file before
replacing the destination. A failed write leaves the saved revision and previous
file intact. Open transactions cannot be saved. Imports can be inspected without
changing their identity; explicit adoption/import UI is still pending.

File parsing is bounded to 8 MiB and returns errors to the caller. Discovery sorts
files and reports bad files individually. Drafts can be saved without players or
heroes. Repository results do not claim gameplay validity; New Game discovery will
apply the stronger validators in its integration milestone.

### Renderer spike

`MapView.bind_terrain_preview(...)` draws an `AdventureMap` snapshot without creating
a `GameSession`. It shares the normal ground, transition, road/bridge, barrier and
decoration drawing. Switching back to a game restores the normal binding; switching
to preview disconnects the old session and clears its visual objects.

The initial path drew static terrain only; the current editor adds object/hero
presentation, selection overlays and incremental redraws. The document itself has
no rendering dependency.

Run the smoke tool with a real renderer to capture the blank and painted drafts:

```sh
godot --path . --script res://tools/editor_document_preview.gd -- /tmp/reignem-editor-foundation.png
```

Or run its assertions without a window:

```sh
godot --headless --path . --script res://tools/editor_document_preview.gd
```

The smoke checks cover playerless blank rendering, complete ground coverage, no
fog, road bridges, grouped undo/redo and game/preview binding transitions. The
rendered preview was visually inspected at 1280 × 800.

A separate headless boundary probe on this Apple M2 painted all 65,536 cells of a
256 × 256 draft in about 216 ms. Its 7,864,328-byte history action remained undoable
within the 8 MiB limit. Building the complete forest terrain preview took about
1.7 seconds. This confirms the defensive size ceiling can render, but also supports
the plan to update affected tiles rather than rebuild the whole map on pointer moves.
These are local smoke measurements, not cross-device performance guarantees.

## Foundation verification (initial slice)

- Document tests: 17 passed, including all bundled-map round trips, scenario
  preservation, new registered terrain, placement diagnostics and history limits.
- Repository tests: 7 passed, including overwriting an existing file, failed writes,
  dirty state, malformed files, filename identity and path traversal rejection.
- Shared art/terrain tests: 20 passed.
- Script loading: 1 passed; every script under `src/` and `tools/` parses.
- Headless and OpenGL renderer smoke checks passed.
- Full regression run: 671 tests, 662 passed and 9 failed (548.9 seconds). All
  24 editor tests pass in that run. Script loading passes without script errors.
- Asset pipeline tests were skipped by `run_tests.sh` because the selected Python
  environment lacks Pillow/numpy. No asset sources or generated artwork were changed
  by this slice. The existing ObjectDB/resource cleanup warnings remain in the full run.

The initial full run observed the same nine gameplay failures listed below. It also
scanned new editor scripts while this slice was being written and the process still
had its initial class registry; the clean run no longer has that script-loading
failure. Other work is active in this checkout, so this comparison records the
observed baseline rather than claiming an isolated clean-tree run.

| Test | Observed existing mismatch |
| --- | --- |
| `test_artifacts_campaign:test_save_keeps_equipment_and_migrates_v5` | Legacy map artifact migration |
| `test_economy:test_version_1_save_gains_towns_and_mines` | Legacy map town/mine migration |
| `test_hero:test_skill_offers_follow_class` | Skill-offer expectation |
| `test_hero_management:test_version_one_save_migrates_and_round_trips` | Legacy encounters/towns |
| `test_hero_management:test_version_two_save_migrates_and_round_trips` | Legacy encounters |
| `test_hero_management:test_migration_skips_encounters_on_occupied_tiles` | Legacy encounter migration |
| `test_mapgen:test_save_stores_generated_terrain` | Expects authored maps not to embed terrain; current saves do |
| `test_upgrades:test_upgrade_garrison_stack_for_cost_difference` | Expected stack omits veteran XP |
| `test_upgrades:test_upgrade_hero_stack_merges_with_existing_upgrades` | Veteran stack merge expectation |

## Next slice

Add generated-map starting points, import/export, recovery drafts and exported-build
release verification. Scenario authoring remains a separate later phase.
