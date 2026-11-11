# Living town screens

All eight faction town screens now run an eight-second cosmetic loop while visible.
The existing background and building artwork stays in place. Built building layers
receive light flicker and, where configured, chimney smoke, sparks or magic motes,
and localized banner motion. Frostmarch has falling snow; Fishmen have bubbles;
the other towns have sparse drifting motes in their faction palette.

The scene owns one clock, updated at 24 frames per second. Hidden town views stop
updating. Effects do not change game state, saves, construction rules or click targets.
Only constructed buildings receive their configured effects. Each building's effects
follow its position, scale and depth when the scene is resized or upgraded.

## Configuration

`assets/specs/town_ambience.json` supplies faction colors, particle styles and
normalized anchors against building source filenames. `smoke` and `motes` are
arrays of `[x, y]` points; `banner` is `[x, y, width, height]`. The shader only
ripples the configured fabric region, and uses existing bright colored pixels for
light flicker. The runtime town manifest and source PNGs are unchanged.

Implementation: `src/ui/town_scene.gd`, `src/ui/town_building_loop.gd`, and
`assets/shaders/town_life.gdshader`.

## Review and validation

Run `GODOT=/path/to/Godot ./run_tests.sh town_` for the town regression checks.
`test_town_ambience.gd` checks profile coverage, valid art anchors, exact phase wrap,
and input transparency of the animated layers.

Render all factions with a native Godot renderer:

```sh
Godot --path . --resolution 960x640 --rendering-method gl_compatibility \
  --script res://tools/town_loop_review.gd -- /tmp/town-loops
```

Each faction produces 25 frames at one-third-second intervals. Frame 24 is the
repeated eight-second boundary: compare it with frame 00 for exact seam validation.
Use frames 00–23 for looping previews; runtime motion runs at 24 fps.

Validation on 2026-11-10: 41 town-related tests passed. Native OpenGL rendering
completed for all eight factions without shader or script errors. In every town,
the rendered frame at eight seconds matched frame zero exactly, and intermediate
frames contained motion. The test runner
reported shutdown resource warnings and skipped Python asset checks
because its default Python lacks Pillow/numpy. No generated atlases were changed.
