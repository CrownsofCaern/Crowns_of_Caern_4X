# Battle animations

Optional per-creature animations for the live battle view (`BattleViewer`).
A creature without files here uses its still sprite with placeholder motion,
so animations can be added one creature at a time.

The generated roster is indexed by `assets/animations.json` and built through
`tools/assets/pipeline.py`. `CreatureAnims` loads those clips through
`UnitAnimation` when no individually authored strip exists. All 128 creature
IDs have movement and attack candidates. Original sheets, reference snapshots,
prompts and hashes are under `assets/source/batches/creature-animation-001/`.

Atlas frames use a transparent 320x256 canvas with anchor (160,207). The painted
figure retains its approved native scale; the extra space keeps thrusting pikes,
spell effects and lowered wings from being cropped. `BattleFigure` updates its
offset as the animation changes and keeps the battlefield foot position fixed.
Movement loops in four 150ms frames. Attacks play once: 180ms preparation,
120ms contact, 180ms recovery, 120ms original rest. The impact marker is at 180ms.
`SpriteFrames` duration weights and the viewer's playback speed preserve this
timing. The atlas frames are never reduced to fit the legacy 128px strip format.

The following format remains supported for separately authored overrides.
An existing strip takes priority over the generated clip and retains the original
10fps timing and 128px anchor. Game rules and recorded outcomes do not depend on
which artwork is selected. Review assets are in `docs/art/production/animations/`.

## Optional strip override format

- Path: `assets/animations/<creature_id>/<creature_id>_move.png` and
  `assets/animations/<creature_id>/<creature_id>_attack.png`
  (e.g. `assets/animations/thornwolf/thornwolf_attack.png`). The creature id is the
  key in `data/creatures/*.json`; upgrades have their own id and their own folder.
- One horizontal strip of square 128x128 frames, transparent background, no gaps.
  The frame count is the width divided by 128.
- Draw the creature facing right, feet at the bottom centre (pixel 64,127),
  the same footprint and scale as its still sprite. Enemies are mirrored in code.
- `move` loops while the stack walks (suggested 4 frames). `attack` plays once
  (suggested 4 to 6 frames); the blow lands on the second-to-last frame.
- Playback is 10 frames per second at 1x speed.
- Ranged creatures: `attack` is the shooting pose; the game draws the projectile.

No build step is needed for override strips: the game loads these files directly. `tests/unit/test_battle_replay.gd`
fails if a folder is not a creature id, a file is misnamed, or a strip is not
128 px high and a multiple of 128 px wide.
