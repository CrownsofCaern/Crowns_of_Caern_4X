# Resource and material artwork — 2026-11-07

All seven adventure-map resources now use detailed pickups matching the approved dark fantasy object artwork: gold, timber, iron ore, quicksilver, brimstone, blood-red crystal and cyan gems. The treasure chest is upgraded in the same style. Seven separate HUD/cost icons use fewer, larger representative pieces so they remain clear at small sizes.

Branch: `art/resource-pickups`. Status: **rendered candidates awaiting artistic review**.

## Artwork and integration

- Eight native 96×96 map sprites retain the existing `resource_<id>` and `object_chest` IDs. Map scale is 0.5, giving a 48px footprint with bottom-centre anchor `(48,95)`; the former pickups were 32px. Map positions, interaction cells, resource quantities and save keys are unchanged.
- Seven native 48×48 `ui_resource_<id>` icons render in the existing 32px HUD and 24px cost displays. `Art.resource_icon()` prefers these icons and retains the original map-sprite fallback if an icon is unavailable. HUD layouts and callers are unchanged.
- Resource icons and pickups share the existing objects atlas. The approved UI atlas and unrelated artwork are preserved. The manifest is rebuilt so all atlas regions remain correct after packing.
- Gold stays warm and metallic; ore is cold iron grey with rust; brimstone is matte ochre; crystal is tall and blood red; gems are low and cyan; quicksilver is contained silver, visibly distinct from a potion. Logs retain bark and clear cut ends. All use the same isometric view, upper-left lighting and dark outlines as the mine benchmark.

## Sources and pipeline

Two unmodified 1774×887 original generation sheets, exact prompts, benchmark hashes, explicit extraction bounds and previous sprite snapshots are archived under `assets/source/batches/resource-pickups-001/`. The approved `resource-places-001/source.png` mine sheet is the conditioning reference. The two source sheets produce fifteen distinct finished assets.

Imports use the existing `pipeline.py import-sheet`, followed by the standard sprite build, validation and inventory commands. The importer now records provenance for `keep_components` batches too, fixing the prior early-return omission. An optional alpha floor removes faint matte below 64 while retaining disconnected coins and mineral pieces. Normal finishing fits each sprite, preserves its colours, makes hard alpha edges and adds the established outline. Original sources retain all detail; no master-palette quantization is applied to production sprites. The new UI icons also have centred legacy pixel fallbacks, consistent with the existing UI source rules.

The change adds no resource IDs, game rules, prices or collection behavior. The latest merged terrain transitions and six-faction town artwork are included and preserved.

## Review and validation

[Before/after and scale contact sheet](production/resource-pickups/contact.png).

Real Godot OpenGL screenshots:

- [Map and resource HUD](production/resource-pickups/map-and-resource-hud-godot.png).
- [Zoomed-out map](production/resource-pickups/map-zoomed-out-godot.png).
- [Town recruitment costs](production/resource-pickups/town-and-resource-costs-godot.png).
- [Building resource costs](production/resource-pickups/building-resource-costs-godot.png).

The capture harness places a temporary review row of all pickups in a real `MapView` and opens the real HUD/town interfaces. It never writes map definitions or saves. Visual inspection covers colour separation, transparent edges, anchors, actual map scale, 24/32px icon readability and town costs.

All 53 Python asset tests pass on the merged branch, including coverage, immutable source hashes and preservation/provenance of disconnected pile pieces. All 27 focused Godot tests pass: three resource-art tests covering dedicated icon selection, dimensions/anchors and missing-icon fallback, plus 24 UI widget tests. Fresh-build check and asset validation pass. Four real-engine captures were reviewed. Final results are recorded in the batch's `production.json` and the PR. Local Godot is 4.6.3; broader pinned-version checks remain with CI.

Reproduce from committed sources:

```sh
python tools/assets/pipeline.py build
python tools/assets/pipeline.py check
python tools/assets/pipeline.py validate
python tools/assets/pipeline.py inventory
python tools/resource_art_review.py
godot --headless --path . --script res://tests/run_tests.gd -- resource_art
godot --path . --audio-driver Dummy --rendering-driver opengl3 --script res://tools/resource_visual_screenshots.gd
```

The last command needs a graphical session. The archived `map/` and `icons/` directories each contain `source.png`, `prompt.txt` and `layout.json` for the existing import-sheet command; re-importing is best done in a scratch checkout because the importer deliberately refuses to overwrite existing crops.
