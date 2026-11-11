# Ultimate buildings: completion of PR #75

The ultimate-building artwork is now bound to the current game's **eight playable factions**. The original six 350px building exports are preserved. Two missing buildings are newly generated: the Umbral Court's **Eclipse Sanctum** and the Abyssal Shoal's **Abyssal Throne**. Each has its own town plot and artwork; neither reuses the treasury image.

[Eight-building comparison and Godot captures](production/ultimate-buildings/README.md).

## Gameplay audit

Current main already implements ultimate construction, prerequisites, payment, faction-wide bonuses, campaign tier limits, ownership/capture changes, duplicate suppression, AI valuation and battle/replay propagation. This PR preserves those rules and balance rather than introducing a second implementation. Each ultimate requires its faction's tier-8 dwelling and treasury and costs 30,000 gold plus the existing material costs, subject to existing building discounts.

The two concrete gaps were visual: the DLC factions' town scenes aliased their ultimate to the treasury, and `UltimateCreatureArt` had no dark-elf or fish-men material. Both are fixed. The Eclipse treatment uses restrained amethyst veil highlights; the Tidal treatment uses cyan caustics. They use the same existing sprite/animation material path as the six original factions, retain source alpha, leave count labels untouched and are removed from fallen figures. No creature IDs, gameplay stats, save fields or progression rules are changed.

The DLC town synchronizer also preserves the dedicated ultimate assets and plots when the pack is re-staged. Both retain the ordinary treasury as a separate visible building. Existing tests are updated from 17 to 18 visible plots accordingly. Source-registry coverage is validated against the actual `ultimate` buildings in `data/buildings.json`.

## Source and pipeline completion

`assets/specs/ultimate_buildings.json` now covers all eight actual building IDs, including the previously omitted Concord entry, with full-resolution original paths/hashes, prepared-output hashes, native dimensions, names and effect names from current gameplay data.

The earlier six reviewed native exports are retained as immutable `reviewed-export.png` inputs beside their high-resolution originals. This preserves their exact colours and transparent smoke across Pillow versions instead of silently resampling them. The original Concord prompt was not recorded; the registry explicitly states that it is unavailable rather than inventing provenance. The other inherited prompts remain archived.

The two new high-resolution originals, exact prompts, conditioning references and hashes are under `assets/source/batches/ultimate-buildings-003/`. Their reproducible recipe clears faint alpha below 64, crops visible bounds and fits the long side to 350px with Lanczos; no palette quantization is applied. Original generated PNGs remain unmodified.

`pipeline.py stage-ultimate` is now the standard preparation entry point. The earlier batch export script delegates to it. Normal town-layer builds, checks, validation and inventory cover the outputs. The importer refuses to replace a changed prepared source. Inventory generation now also follows existing `same_as` aliases correctly, fixing a crash exposed by the newer town content and recording the real runtime path of reused artwork. Eight full-source records are included separately from runtime town-layer records.

## Verification

The real Godot review constructs all eight ultimates through `GameSession.build`, checks exact gold payment and active faction bonuses, and captures town scenes before and after construction. It then renders normal/ultimate creature pairs through the actual `BattleFigure` still, movement and attack paths. Nineteen screenshots accompany the native contact sheet. The newly generated buildings and both DLC towns were visually inspected at export and actual UI scale; original-faction towns and creature material comparisons were also reviewed.

All 61 Python asset tests and 14 focused Godot ultimate tests pass through `./run_tests.sh ultimate`, including a fresh-build check. Asset validation passes separately. Focused tests cover unique art for every actual ultimate, all eight materials, DLC combat/replay propagation and removal of glow from fallen figures, deterministic source reproduction, registry coverage, re-staging stability and inventory aliases. The existing ultimate tests cover construction, restrictions, ownership, non-stacking, AI behavior and balance. Final results are recorded in the production metadata and PR. Local Godot is 4.6.3; pinned-version CI remains the broader integration gate.

```sh
python tools/assets/pipeline.py stage-ultimate
python tools/assets/pipeline.py build
python tools/assets/pipeline.py validate
python tools/assets/pipeline.py inventory
python tools/ultimate_art_review.py
./run_tests.sh ultimate
godot --path . --audio-driver Dummy --rendering-driver opengl3 --script res://tools/ultimate_visual_review.gd
```

The final command needs a graphical session. These are engine-reviewed art candidates; this report does not imply new human artistic approval. The common world-map proposal and future campaign journey UI are separate workstreams.
