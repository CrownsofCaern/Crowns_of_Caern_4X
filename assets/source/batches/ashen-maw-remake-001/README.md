# Ashen tier 8 production remake

Built-in image_gen, 2026-11-09. `source.png` remakes Cinder Maw (left) and Maw of Ruin (right), conditioned on `ashen-001/source.png`: low crawling furnace-mouth predators with split skulls, needle fangs, hooked forelimbs, red sinew, jagged obsidian, recessed sulfur eyes and restrained ember light. Exact animation prompts are `prompt-A.txt` and `prompt-B.txt`.

`ashen-04-reference.png` keeps the existing tier 7 pair and uses the new tier 8 stills. A is 7 columns × 4 rows (3 idle + 4 walk); B is 6 × 4 (anticipation, windup, main hit, follow-through, recoil, recovery). All sources retain generated alpha. Runtime registration uses the repository pipeline, fixed anchors and reviewed source hashes. The legacy fallback sheet is mechanically assembled from A columns 4–7 and B columns 2, 3, 6; no old tier 8 poses remain in that fallback.

The tier 2 hound stills were already pushed in ff42d41 and are present on main. Alternate hounds in the level-five veteran concept sheets were also pushed (6a2c1a8); those are veteran concepts, not replacement base roster sprites. This pass preserves the current one-headed Scorchhound and two-headed Hellmaw Hound and activates their newer individually drawn idle/walk/attack poses.

Groups ashen-01 through ashen-03 use the original pushed `ashen-idle-review-001` sources. Group ashen-04 uses this replacement batch. Historical candidates remain archived. Runtime approval is recorded by source hashes in `creature_idle_animations.json`; inspect `docs/art/production/demon-ready/` and run `tools/demon_animation_review.gd` for native engine rendering.
