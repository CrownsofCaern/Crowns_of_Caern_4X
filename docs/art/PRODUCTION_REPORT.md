Latest resource and material delivery: [RESOURCE_ART_REPORT.md](RESOURCE_ART_REPORT.md).

Latest standalone expansion art delivery: [DLC_FACTIONS_REPORT.md](DLC_FACTIONS_REPORT.md).

Latest terrain battlefield delivery: [BATTLEFIELD_PRODUCTION_REPORT.md](BATTLEFIELD_PRODUCTION_REPORT.md).

Latest full-roster animation delivery: [ANIMATION_PRODUCTION_REPORT.md](ANIMATION_PRODUCTION_REPORT.md).

Latest landscape and town delivery: [LIVING_WORLD_REPORT.md](LIVING_WORLD_REPORT.md).

# Expanded visual production delivery — 2026-11-07

Latest interface delivery: see [UI_PRODUCTION_REPORT.md](UI_PRODUCTION_REPORT.md)
for six live faction themes, nine contextual cursors, checks and Godot screenshots.

Newer delivery: see [STORY_ART_REPORT.md](STORY_ART_REPORT.md) and PR #49 for
28 special-location sprites, 16 terrain variants and ten Last Light illustrations.

This checkpoint supersedes the historical notes below.

Branch: `art/production-128`; follow-up draft PR #46. The earlier faction PR #41 has been merged. All six faction creature sheets (96 designs) are now user-approved, with engine QC tracked separately.

## Newly generated and integrated

- 32 neutral creature sprites, using every actual ID in `data/creatures/wilds.json`.
- 18 mounted hero-class sprites, three classes per faction, using existing class IDs.
- Six town map sprites, preserving the existing town IDs and faction architecture.
- 16 landscape decoration drawings: two variants each of pines, snowy pines, dead trees, peaks, boulders, bones, graves and obsidian. These supply the existing four decoration cells through variant reuse.
- Ten ground texture sources, feeding four derived variants per terrain and the existing 46-shape transition system.

This is 82 new source assets, in addition to the 96 faction creature assets. All are imported into the existing atlases/manifests. Creature/hero art is 128px native with the prior 64px map footprint; towns are 192x160 with the prior 96x80 footprint. Terrain and decoration grids retain their existing gameplay dimensions.

## Sources and reproducibility

Each batch in `assets/source/batches/` includes its plan, exact generation prompt and unmodified source sheet. Per-asset raw crops and JSON sidecars include SHA-256, crop bounds, conditioning references, native size and review status. Towns also retain an unused alternate cleanup source and its prompt; the original imported source already produces clean hard-alpha silhouettes at native scale.

`stage_batch.py` extends the existing production pipeline for planned grids and refuses overwriting existing generated assets. It preserves disconnected swarms, buildings and smoke. Ground and decoration sources feed `build_terrain`, preserving the existing terrain masks, roads, fog and y-sorting. `assets/source/.gdignore` prevents raw production images from being imported into the game.

The inventory and native contact sheets are updated under `assets/inventory.json` and `docs/art/production/`. The six faction approvals are recorded in `assets/source/reviews.json`; new neutral, hero, town and landscape candidates remain pending review.

## Validation and next work

Local asset validation and whitespace checks pass. Broader CI tests are left to the online suite as requested. No gameplay logic changes were made. No completed Godot screenshot pass is claimed.

Review sprite/grid boundaries, group silhouettes, weapons, mounted anatomy, owner flags and texture repetition at normal game zoom. Ground tiles pair their opposite edge samples, but adjacency between different derived variants still needs visual review. Town-screen panoramas/building progression, mines/resources/encounter refreshes, artifact/ability/UI icons and final in-engine screenshots remain outstanding. The town delivery here upgrades map sprites and the existing town preview, not a new panoramic town-screen implementation.

---

# Current production checkpoint — 2026-11-07

This section supersedes the initial checkpoint retained below.

- Same branch: `art/production-128`, draft PR #41.
- Reconciled main through `b83db94`; merge commit `3832faa` preserves all latest hand-drawn pixel sources, including upgrades, neutrals, heroes and terrain. The earlier description of recolour-only upgrades and open PR #19 is historical.
- 96 generated creature candidates staged: all six factions, 16 each. User approved Concord examples, Ashen output and the entire Hollow design sheet; final native-size and engine review remains pending for all batches.
- All six sheets archived under `assets/source/batches/`; individual crops and provenance under `assets/source/generated/`. Original sheets are never overwritten.
- `stage_faction.py` extends the existing pipeline with conservative isolated-component bounds; it refuses irregular sheets for manual review. Extraction removes disconnected fragments, so verify effects such as smoke in final QC.
- Rebuilt atlas and manifest; asset validation and 27 Python pipeline tests pass at this checkpoint.
- All six faction sheets generated and staged. Thornwood, Forge and Frostmarch await user design review. Neutral refresh and noncreature assets remain outstanding.
- No completed Godot screenshot pass yet. Do not mark production complete or merge until engine-scale checks and review are finished.

---

# Art production handoff — 2026-11-07

Branch: `art/production-128`. Baseline: `6b775836bece412cd99a41af577a032cf2cd4317`.

## Current delivery (work in progress)

First Concord batch: 16 independently drawn sprites, eight base/upgrade pairs,
using the actual IDs in `data/creatures/concord.json`. User approved the three
examples in `production/concord-direction-preview.png` in the conversation.
That approval establishes the direction; it does not mean all 16 final sprites
have passed in-engine review.

Original generated sheet is preserved in
`assets/source/batches/concord-001/source.png`. Each cropped source has a JSON
sidecar with provenance, SHA-256, reviewed bounds and a per-asset prompt. The
per-asset prompts are reconstructed from structured specs; the original sheet
used a composite 4x4 arrangement. This is reproducible processing metadata,
not a promise of deterministic image generation.

`assets/inventory.json` tracks every existing sprite spec, automatic creature
fallback and terrain definition. Its quality states remain conservative until
review is complete. Existing missing art and recolour upgrades are not marked
complete merely because they have atlas entries.

## Integration

Only art, asset tooling, specs and built outputs change. No gameplay code changes.
Concord uses native 128x128 sources with `map_scale: 0.5`, preserving the existing
64px map footprint. The existing atlas builder imports all 16 sprites and writes
anchors and rectangles. Generated Concord art opts into `generated_palette:
"preserve"`; legacy artwork retains master-palette validation. Hard alpha and
outline processing remain active.

The new commands extend the existing pipeline:

```sh
python3 tools/assets/pipeline.py import-sheet --batch assets/source/batches/concord-001
python3 tools/assets/pipeline.py build
python3 tools/assets/pipeline.py contact-sheet --faction concord
python3 tools/assets/pipeline.py inventory
```

Import refuses to overwrite existing sources by default. `--force` was used only
to correct this branch's own initial grid extraction. Reviewed per-sprite bounds
and connected-component isolation fix neighboring fragments and wing/banner
clipping found in the first contact sheet. Full source sheets are never changed.

## Checks and remaining gates

- Asset validation passes for dimensions, alpha, atlas coverage and applicable palettes.
- Final native contact sheet: `production/concord-contact.png` (128px and 64px pairs).
- Godot import was attempted but emitted sandbox/socket and editor-settings errors;
  this is not an in-engine visual pass. Screenshots and full tests remain pending.
- Check all 16 for anatomy, especially bow strings, horse limbs and bird riders.
- Verify overview UI, combat portraits and normal map zoom before merge.
- Add tests for color-preservation opt-in and batch isolation before marking tooling ready.

## Coordination and outstanding scope

Main still documented 64px when inspected. User-supplied benchmark v0.2 recommends
128px and the user approved the new Concord examples. These changes are isolated
on the art branch for the lead developer to review against ongoing pipeline work.
Do not merge over newer pipeline or approved artwork without reconciliation.

Open PR #19 already authors 29 neutral creatures
and Concord/Ashen tier-8 pixel sources. It has not been merged or overwritten.
Open PR #9 contains hero-class/artifact data that must be reconciled before
producing variants. No messages were sent to the developer.

Remaining: in-engine approval of Concord, the other five factions and their
independent upgrades, neutral refresh, hero variants, town map and town-screen
progression, objects, terrain/transitions and artifact/ability/UI icon work.
This report is a progress handoff, not a claim that the full commission is done.
