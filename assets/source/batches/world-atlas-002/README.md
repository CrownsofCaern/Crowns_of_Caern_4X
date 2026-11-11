# Expanded empire atlas

Requested after the user approved the first painting's geography and regional art style. This batch expands the full world and changes its visual scale to schematic cartography; the previous source remains the style reference for individual campaign paintings.

The full-resolution generated source is unmodified. Labels, schematic influence boundaries, unnamed settlement marks and geographic route indexes are separate Godot review overlays. `source.json` records provenance and hashes; `assets/specs/world_atlas.json` records the shared geography, empire extents, preserved regional positions and campaign presentation direction.

Reproduce review captures with:

```sh
xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/world_atlas_review.gd
```

This batch does not contain final campaign paintings or change the production selector.
