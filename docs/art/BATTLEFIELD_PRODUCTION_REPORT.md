# Terrain battlefield delivery — 2026-11-07

Live fights, forecasts and battle reports now use painted scenery selected from the encounter's actual map tile. There are 17 original scenes at 1536×1024: two variants each for grass, forest, desert, snow, swamp, infernal and rough; one each for river, mountain and water. Grassland borders, elderwood clearings, ruined observatories, frozen passes, sunken abbeys and volcanic rifts give the common terrain types distinct places without obstructing the fighting area.

Branch: `art/production-128`. Integrated on current main including the merged animation and map-size changes. These are engine-reviewed candidates, awaiting artistic approval.

## Integration

`GameSession` attaches presentation-only `visual_terrain` and `visual_seed` to previews and resolved battles. The seed hashes map ID and encounter position, so the same location keeps its scene across forecast, playback and report. Selection never advances the game random stream. A river can therefore show a ford while retaining existing grass combat modifiers. Simulator inputs affecting damage, combat seeds, passability and results are unchanged. Water and mountain artwork covers existing terrain IDs for special/future encounters; this delivery adds no naval or mountain movement rules. Old results without these fields use their stored combat terrain and seed.

`BattlefieldArt` selects the manifest entry; `BattlefieldBackdrop` draws it behind `BattleVignette` with independent linear filtering. Creatures retain their pixel filtering and original scale. Horizon-aware aspect-preserving crops fill wide forecasts and tall screens without stretching or blank edges. Missing scenery falls back to the existing sky and ground rendering. No battlefield-sized images are put into sprite atlases; each scene is a standalone texture loaded for the active view.

## Sources and reproducibility

- Structured specification: `assets/specs/battlefields.json`.
- Original PNGs, exact prompts, reference/source hashes and per-image metadata: `assets/source/batches/battlefields-001/`.
- Runtime textures and manifest: `assets/battlefields/`.
- Existing build/check/validate/inventory commands now cover these scenes; runtime PNGs are exact byte copies of the original generation output, with no downsampling or palette reduction.
- The first scene references the approved Concord town foundation; subsequent scenes reference the first battlefield to preserve composition, light direction and painted texture. Sources and exports remain 1536×1024.
- `assets/inventory.json` includes all 17 scenes with generation, quality and provenance fields. Quality status is `rendered_candidate`, not human-approved.

## Validation

Two new Python tests pass: complete terrain coverage and byte-identical exports from a fresh build. Five new Godot tests pass: coverage, stable variants/fallback, aspect/horizon crop geometry across wide and portrait sizes, unchanged RNG/simulation, and consistent river context through preview and resolution. Existing replay (9) and UI widget (21) tests pass: 35 focused Godot tests total. Pipeline check and validation pass.

A real Godot 4.6.3 OpenGL run rendered all 17 variants with twenty stacks at the existing figure scale, plus all 17 compact forecast crops. Visual inspection checked the contact sheets, full-size volcanic scene and compact forest forecast for layering, horizon placement, readability and background artifacts. A complete live river fight kept the same scene and ended with exact recorded survivor counts. The existing harness reports resource-cleanup warnings on shutdown; render assertions pass. Broad pinned-version checks are left to CI.

## Review material and remaining opportunities

[All scenes, screenshots and forecast crops](production/battlefields/README.md), [source contact sheet](production/battlefields/contact.jpg), [live contact sheet](production/battlefields/live-contact.jpg) and [completed river fight](production/battlefields/river-playback-result.png).

These are static painted backgrounds. Weather, drifting fog/embers, dedicated siege/town battlefields and campaign-specific scenery can build on this foundation. They are not claimed as part of this delivery.
