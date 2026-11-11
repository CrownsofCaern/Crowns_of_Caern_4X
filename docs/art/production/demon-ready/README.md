# Ashen Host runtime artwork

- 16 creatures, each with an idle loop, four-pose walk and six-pose attack plus recovery (48 clips).
- Cinder Maw and Maw of Ruin are remade with long split skulls, needle fangs, hooked forelimbs and jagged red-black carapaces. Static roster art and all action poses use the new designs.
- Hound history: the current base-tier hounds were already pushed in ff42d41. Alternate hounds are in the pushed level-five veteran concepts (6a2c1a8), rather than a lost base-tier replacement. The subsequent hound remake now gives the tier 2 pair a distinct tall canine silhouette with matching idle, walk and bite clips; one head for Scorchhound, two for Hellmaw Hound. See `assets/source/batches/ashen-hounds-remake-001/`.
- Source art and exact prompts: `assets/source/batches/ashen-maw-remake-001/`; earlier animation sources: `assets/source/batches/ashen-idle-review-001/`.

## Verification

Godot rendering tool: `godot --path . --audio-driver Dummy --script res://tools/demon_animation_review.gd`. Result: `ASHEN_ANIMATIONS_OK: 16 creatures, 48 runtime clips`. Screenshots here show actual runtime sampling. All animation frames pass nonempty/distinct/bounds checks and source registration reports zero warnings. Five animation tests, five idle pipeline tests and seven battle FX tests pass.

The complete repository checks also exercise unrelated existing work. On this baseline, campaign journeys omit `long_watch`; the two DLC ultimate-building prepared exports fail validation; existing PNG encodings differ from the local encoder; and terrain outputs differ from the current terrain spec. Those files and pixel-identical generated outputs were preserved, rather than folding unrelated asset changes into this update.
