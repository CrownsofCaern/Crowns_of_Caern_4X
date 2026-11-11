# Working on Crowns of Caern (guide for coding agents)

Start with `docs/REPOSITORY_GUIDE.md` for the repository map. Read `docs/DESIGN.md` (architecture, data models, combat model, checklist) and `docs/ART_BIBLE.md` for
anything visual. The original project brief is the final reference for scope and priorities.

## Hard rules

- **Original content only.** No names, art, lore, factions, creatures, heraldry or UI layouts from Heroes of
  Might and Magic or any other existing game. Genre mechanics are fine.
- **Rules stay headless.** Code in `src/core`, `src/world`, `src/heroes`, `src/armies`, `src/economy`,
  `src/combat`, `src/game`, `src/ai` must not use Nodes, scenes or `get_tree()`. UI code only calls `GameSession`
  commands and reads state.
- **Determinism.** All gameplay randomness goes through `GameRng` (never `randf()`, `randi()` or
  `RandomNumberGenerator`). Never name a method like a Godot global utility function. Do not iterate in an
  order that depends on hashing or memory addresses.
- **Data-driven.** Content lives in `data/*.json`. New fields need validation in `GameData.validate()`.
  Every skill/ability listed in data must have a real effect.
- **Tests with every feature.** Add tests in `tests/unit/test_*.gd` (methods `test_*`, asserts as in
  `tests/test_case.gd`). Statistical tests use fixed seeds and generous bounds.
- **Saves are versioned.** Changing saved fields means bumping `GameState.SAVE_VERSION` and handling old saves.

## Commands

```sh
./run_tests.sh [filter]                     # must pass before every commit
godot --headless --path . --script res://tools/balance_report.gd -- 300 res://reports/balance_report.md
xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/screenshot.gd -- /tmp/screens
python3 tools/assets/pipeline.py build       # rebuild art after changing assets/specs (see tools/assets/README.md)
python3 tools/audio/synth.py build [name...]  # re-render sounds/music (needs numpy + ffmpeg); see docs/DESIGN.md 5e
```

Art: never edit `assets/atlases/` or `assets/manifest.json` by hand; change `assets/specs/` and rebuild
(`run_tests.sh` fails if they are stale). New creatures, resources or terrains need a spec entry, or validation fails.

Audio: UI code plays sounds only through `AudioManager`'s static helpers with event ids from `data/audio.json`;
new event ids go into `AudioCatalog.REQUIRED_EVENTS`. Any audio file not rendered by `tools/audio/synth.py` must be
CC0 (or similarly permissive), verified, and logged in `assets/audio/LICENSES.md`.

GDScript style: static typing, tabs, `snake_case`, `class_name` for shared types. After adding a new
`class_name`, run `godot --headless --path . --import` once (run_tests.sh does this).
