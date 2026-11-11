# Full-roster movement and attack animation — first production pass

Crowns of Cinder, 2026-11-07. Branch: `art/production-128`.

## Delivery

All 128 actual creature IDs now have a movement clip and an attack clip: 96
faction creatures, including every upgrade, plus 32 neutrals. This is 256
creature clips. Four movement poses and three attack poses per creature were
generated against snapshots of the approved sprites; attacks end on the exact
original rest image. The mounted knight has four additional gait poses.
The batch contains 900 newly drawn poses, preserved in 33 high-resolution sheets.

Every faction and both neutral review pages have native-scale movement and
attack GIFs/contact sheets. Godot screenshots show all 128 creatures, a battle
vignette, an actual knight route and a live recorded battle with movement,
attacks, projectiles and the final result.

These are **animation candidates**, not a claim that every limb and every
transition has received final artistic approval. The first pass is deliberately
coarse: four-frame movement and a short preparation/contact/recovery attack.

## Horse correction

The old riding effect deformed and lifted the entire still sprite while its
legs stayed fixed. It is removed for every hero. The knight now uses drawn
alternating leg poses while its existing route tween moves the sprite.
Torso registration prevents the rider sliding as the support hoof changes.
The rider's scale and banner position remain constant; the exact approved idle
sprite and anchor return at the end of the route. Other hero classes currently
use their original still art during translation; they need their own gait clips.

## Pipeline and quality controls

`assets/specs/creature_animations.json` specifies the real roster, references,
source files, hashes, alpha floor and layout. The ordinary build/check/validate/
inventory commands include animation outputs. No separate generation pipeline
or replacement creature roster is introduced.

The originals, exact generation prompts, references and provenance sidecars are
archived in `assets/source/batches/creature-animation-001/` and `hero-gait-001/`.
Registration uses the torso during walking and one canonical per-unit scale.
Transparent row/column gutters are found adaptively, with bent seams where
weapons project between neighbouring frames. This preserves full weapons and
staff tops that fixed grid cuts would truncate. The 320x256 action canvas and
(160,207) anchor provide room for long weapons and lowered wings without
shrinking the figure or changing its logical map footprint.

RGB is not palette-quantized. Sub-64 alpha is cleared in processed frames to
remove faint matte rectangles while preserving the original high-resolution
sources. Visual review caught matte backgrounds in Hollow's final group and a
neutral group. Hollow's sheet was refined with reference-conditioned background
removal; its initial sheet/metadata remain in `revisions/`. The alpha processing
removes the remaining faint matte from both batches. Updated contact sheets were
checked after processing. Final structural QC reports no known clipping or
touching-silhouette warnings across the 129 animated units.

## Integration with the lead developer

Main gained `BattleViewer`, `BattleFigure` and `CreatureAnims` while this artwork
was being produced. Those changes, zoom/touch support and the newly approved UI
symbols were merged and preserved. The live battle player now reads atlas clips
through its existing `CreatureAnims` interface. `UnitAnimation` supplies the
lower-level atlas lookup also used by map heroes and the review tools.

Legacy 128px horizontal strips still override generated clips. Atlas playback
uses explicit anchors and per-frame duration weights; impact occurs at the
authored marker rather than an assumed frame number. Drawn movement/attacks do
not receive extra whole-body squash. Dead figures stop moving and use the
existing darkened still appearance. Damage, survivors, movement rules and combat
simulation are unchanged.

Movement loops in 600ms; creature attacks play once in 600ms with impact at
180ms. The knight gait loops in 320ms. Battle playback speed continues to scale
both sprite animation and the viewer's presentation clock.

## Verification

39 Python asset tests pass, including complete roster coverage, distinct/nonempty
frames, stable knight registration, weapon-preserving gutters and matte removal.
Asset validation and reproducible build checks pass; new animation PNGs and the
manifest are compared byte-for-byte. Approved upstream UI exports are retained. Godot tests cover all 256
creature clips, attack timing, anchors, fallback and the live-player integration;
the existing battle-replay and UI suites also pass: 5 animation, 9 replay,
21 UI-widget and 3 living-world tests, 38 focused Godot tests in total.

Real OpenGL Godot checks observed the knight gait during its actual route tween
and verified restoration of the original idle sprite. A complete live battle
played with drawn movement and attack clips; its final stack counts exactly
matched `BattleReplay.final_counts()`. The harness prints `HERO_GAIT_REVIEW_OK`
and `LIVE_ANIMATED_REPLAY_OK`. Local engine: Godot 4.6.3; CI supplies the pinned
engine and broader checks. Existing test/screenshot exit cleanup warnings remain.

To reproduce previews, run `python3 tools/animation_review.py`. Under an X
display, run `tools/animation_review.gd`, `tools/hero_gait_review.gd` and
`tools/live_animation_review.gd` with Godot. The runtime tools modify only their
temporary review games and do not change saved campaign progress.

## Next polish

Review gait rhythm, limb consistency, attack readability and transitions on each
faction GIF before marking clips artistically approved. More in-between poses,
hit/death clips, creature-specific projectile artwork and the other 17 mounted
hero-class gaits remain. Five faction town scenes and broader landscape
composition remain on the earlier art backlog.
