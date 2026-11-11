# Connected terrain, Concord town construction and subtle sprite motion

First implementation batch for Crowns of Cinder, 2026-11-07.

## Delivered

- Continuous 8x8-cell ground fields across all ten existing terrain IDs. A new
  1254x1254 grass source is preserved; nine other fields reuse approved archived
  terrain sources. Native output is 320x320 per field, split into sixty-four
  40px atlas cells and sampled in spatial order. Only the outer field boundary
  is blended for periodic wrapping; internal cell boundaries are never flattened.
  Existing small variants remain available for transition fringes and fallback.
- Concord town foundation and thirty individual building layers, covering every
  actual ID in `data/buildings.json`, including all eight dwelling upgrades.
  Seventeen fixed slots provide civic/fortification progression, dwelling
  replacements and independent support buildings. Sources, prompts, hashes,
  reviewed extraction bounds and reference conditioning are archived. Two unused
  decorations remain on the original upgrade sheet, outside the building roster.
- A Town view tab showing construction state, alongside the existing Buildings
  tab and recruitment/garrison controls. Buildings and empty sites open the
  corresponding building-list row; selecting a site does not construct it.
  Factions without town-scene art keep the functional building-list view.
  The existing header preview now scales its town sprite to fit its frame.
- Gentle breathing on adventure-map neutral creatures and guards. Mounted heroes
  bob and slightly change posture only while their existing route tween runs.
  Sprite motion leaves world position, ownership flags and gameplay state alone;
  `MapView.motion_enabled = false` restores the static pose. This is a presentation
  switch for future settings integration, not yet a player-facing toggle.

## Validation and review

34 Python asset tests pass, including town roster coverage, alpha validation,
continuous-field reconstruction and exact periodic borders. The asset build,
validation and reproducibility check pass. Three new Godot tests pass for town
layer replacement, neighbouring terrain selection and bounded motion. The 17
existing UI widget tests pass. Whitespace checks pass.

Real Godot 4.6.3 OpenGL renders are in `production/living-world/`: starting,
developing and complete Concord towns, building-list inspection, a Hollow fallback
screen, the adventure map and a 48-frame enlarged sprite-motion review GIF.
The UI widget harness and screenshot process still report resource cleanup
warnings on exit; those runs complete, with no script or rendering errors.
CI supplies the project's pinned Godot version and broader gameplay checks.

The building contact sheet was inspected for clipped roofs, neighbouring sprite
fragments, transparency, camera and faction palette. Reviewed crop bounds were
refined around the eyrie/foundry and keep/wall gutters. All thirty source crops
reproduce from their original sheets and archived bounds. The town screenshots
confirm progression, compact layout and a usable recruitment area at 1280x800.
Inventory quality is `rendered_candidate`, pending user artistic review.

## Reproduce

The ordinary `python3 tools/assets/pipeline.py build` exports terrain and town
layers. `check`, `validate` and `inventory` include the new assets. Town images
are byte-preserving exports at their source crop resolution, outside the small
sprite atlases. The town manifest is `assets/towns/manifest.json`.

To recreate source crops from archived sheets:

```python
from pathlib import Path
from crowns_of_cinder_assets import town_scenes
town_scenes.stage(Path('.'), Path('assets/source/batches/concord-town-001'))
```

Run that with `tools/assets` on Python's import path. It refuses changed source
hashes and changed reviewed outputs. Capture runtime views with
`tools/living_visual_screenshots.gd` under an X display, then run
`python3 tools/living_visual_review.py` for contact sheets and the motion GIF.
The screenshot tool modifies only its temporary in-memory review game.

## Remaining work

Five faction town scenes remain. This batch establishes their manifest, layer,
slot and UI conventions. Terrain now has broader continuity, but a 320px field
still repeats; clustered forest canopies/mountain ridges, terrain-specific shores,
cliffs, better roads and directional/animated rivers remain separate work.

Single-image transforms cannot articulate knees, wings, reins or weapon swings.
The current effect is intentionally small. True walk/attack/death animation needs
additional matched frames or carefully separated parts. Battle cards/vignettes
and hero portraits do not acquire animation in this batch. Unit readability,
accessibility settings and performance on target hardware should guide expansion.
