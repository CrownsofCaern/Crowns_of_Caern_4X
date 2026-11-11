# Map expansion 001

Twenty additive art assets generated with the built-in image_gen tool on
2026-11-09, conditioned on the project's existing towns and landscape sheets.
The exact final prompt for each asset is in `assets/specs/map_scenery.json`.
Raw outputs and generation provenance live in `assets/source/map-expansion-001/`.
Exported textures and their placement catalog live in `assets/map_scenery/`.

## Contents

| Category | Assets | Export size | Reserved footprint |
| --- | --- | --- | --- |
| Terrain | Moss heath, autumn loam, salt flat, cooled lava | 40x40 | 1x1 |
| Decorations | Weeping willow, reed pool, oath stones, broken cart | 48x64 to 64x64 | 1x1 |
| Small towns | Concord hamlet, frost fishers, Thornwood hamlet, cinder miners | 120x100 | 3x2 |
| Buildings | Wayside abbey, windmill, marsh hermit, border watchtower | 80x80 or 80x96 | 2x2 |
| Landmarks | Cinder volcano, frozen cascade, shattered citadel, elder grove | 160x160 | 4x4 |

## Rebuild and validation

```sh
python3 tools/assets/build_map_scenery.py
```

Requires Pillow and numpy, like the existing asset pipeline. Uses its existing
postprocessor for content fitting, bottom-centre anchoring, hard alpha, and dark
outlines while preserving the generated material colours. Terrain uses the
existing connected-field processor to match opposite edge samples.
The build checks unique IDs, output sizes, alpha, nonempty silhouettes, and
identical opposite terrain borders. It produces a native-size contact sheet at
`docs/art/production/map-expansion-001-contact.png`; terrain is shown repeated 4x4.

## Placement contract

This is an additive art library. These assets are not yet registered in the
live editor palette or terrain renderer. No movement rules, map formats,
existing terrain art, or live atlases are changed. In-engine visual review
is still pending.

The manifest has resource paths, dimensions, pixel anchors, footprints, biome
tags and passability. All landmarks reserve an impassable 4x4 rectangle.
Buildings and towns use their reserved rectangles; art can extend above the
ground footprint and should be depth-sorted from the bottom anchor. Single-tile
scenery can overhang neighbouring tiles visually.

Terrain entries are proposed surface variants of their tagged base biome,
with no additional movement semantics. They tile with themselves; transitions
to existing terrain and variant selection need renderer integration.
Town and dwelling entries are decorative candidates with no recruitment,
ownership or encounter behaviour assigned yet.
