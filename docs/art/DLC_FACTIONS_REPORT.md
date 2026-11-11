# Standalone faction art packs — 2026-11-07

The Umbral Court (dark elves) and Abyssal Shoal (fish men) now have complete first-pass visual packs. They are optional expansion artwork with no links to the main campaign story. The user authorized both new factions; because neither had repository definitions, their original names, stable IDs, visual roster and upgrade relationships are declared in `assets/specs/dlc_factions.json` rather than replacing existing creatures.

Branch: `art/dlc-factions`. Quality: **rendered candidates awaiting artistic review**, not final human approval.

## Delivered

| Content | Per faction | Total |
|---|---:|---:|
| Creature sprites, eight tiers with base and upgrade | 16 | 32 |
| Creature movement clips, four drawn poses each | 16 | 32 |
| Creature attack clips, three drawn poses plus original rest | 16 | 32 |
| Hero-class sprites and four-pose mounted movement clips | 3 | 6 |
| Individual town building layers | 30 | 60 |
| Adventure-map town progression sprites | 4 | 8 |
| High-resolution town foundations | 1 | 2 |
| Crest, relic icon, ability icon and cursor artwork | 4 | 8 |
| Obelisk, portal and shrine map props | 3 | 6 |

There are **120 distinct static atlas sprites plus two full-resolution foundations**, 70 new animation clips and **248 newly drawn action poses** (224 creature poses and 24 hero poses). Twenty original generation sheets/paintings are preserved with exact prompts and conditioning metadata. The four-frame attack clip includes the existing original still as recovery/rest; it is not counted as a fourth newly drawn attack pose.

The Court uses ash-grey faces, angular black and silver armour, violet cloth, cave-lizard mounts, spiders and obsidian dragons. The Shoal uses gilled predatory faces, teal scales, pearl shell, corroded bronze, coral and restrained cyan light, with crab mounts, serpents and an angler titan. Buildings follow these same materials. The eight base/upgrade pairs and three hero classes for each faction are listed in the [review index](production/dlc-factions/README.md).

## Existing pipeline integration

- `specs.load_sprite_specs` includes the optional pack's structured asset specs. Rendering, palette preservation, transparency, outlines, sizing, anchors and export all use the existing sprite pipeline.
- Static exports are separated into six compact DLC atlases, so existing base-game units, objects and UI keep their atlas coordinates and textures. Each new static atlas fits within 2048×2048. The largest is 1800×1286; unit atlases are 1936×259. Existing animation entries, QC records and atlas records were compared and remain equal.
- `animations.build` accepts the pack's declared art roster without registering it as gameplay data. The animation manifest explicitly lists optional creature IDs; the runtime art auditor accepts these only when a corresponding still sprite is built. This avoids treating an intentionally inactive DLC roster as unknown creatures while retaining checks for mistyped IDs. Ten new reference-conditioned animation sheets use the existing adaptive gutters, registration, 320×256 action canvases and explicit foot anchor `(160,207)`. The native references remain 128×128; the padded action canvas preserves weapon reach rather than enlarging the figures.
- `town_scenes.build` validates DLC building IDs against the optional art manifest. Each faction has 17 compositing slots and 30 building variants, covering civic progression, walls, eight base/upgrade dwellings and seven economy/support sites. Real `TownScene` resolves constructed variants and replaces lower stages.
- Existing runtime lookup contracts work: `creature_<id>`, `hero_<class_id>`, `town_darkelf`, `town_fishmen`, plus three earlier map-town stages for each. Default map towns include ownership flag anchors and map scale 0.5.
- Faction interface palettes are available through `UiStyle.palette("darkelf")` and `UiStyle.palette("fishmen")`. The new ornamental cursor is supplied as artwork; no global cursor behavior is changed by this art pack.
- The existing build/check/validate/inventory commands cover the exports. `stage-dlc` reproduces the isolated crops using the same adaptive transparent gutters as creature animation extraction. Sources are hash-guarded; established artwork cannot be silently overwritten.

## Validation and review evidence

The merged-main Python asset suite passes all 49 tests. The final optional-roster metadata change also passes all five focused DLC Python tests. All 26 focused Godot tests pass: five DLC, five animation, five faction-UI and eleven replay/battalion tests. Fresh-build check and asset validation pass. Final counts and engine results are recorded in the batch's `production.json` and the PR. The latest battle battalion/stance changes, campaign opening paintings, menu artwork and artifact sprites from main are preserved. Local engine version is 4.6.3; pinned-version and broader gameplay checks remain with CI.

A real Godot 4.6.3 OpenGL review loads all 32 creatures through `BattleFigure`, verifies both actions are present, renders walking and attacks, and checks that attacks recover to idle. It renders all six hero gait poses through `UnitAnimation`, and uses the actual `TownScene` renderer for four construction states per faction. Twenty-two engine screenshots accompany native-scale contact sheets and six looping animation previews. The source contact sheet, native creatures, attack contact sheets and fully built town renders were visually inspected for silhouette, palette continuity, weapon isolation, transparency and layering. Final animation extraction/registration reports no clipping or touching-silhouette warnings.

Reproduction:

```sh
python tools/assets/pipeline.py stage-dlc
python tools/assets/pipeline.py build
python tools/assets/pipeline.py check
python tools/assets/pipeline.py validate
python tools/assets/pipeline.py inventory
python tools/dlc_art_review.py
godot --headless --path . --script res://tests/run_tests.gd -- dlc_art
godot --path . --audio-driver Dummy --rendering-driver opengl3 --script res://tools/dlc_visual_screenshots.gd
```

The last command requires a graphical session. GIF previews are review derivatives; original source PNGs and runtime sprite colours are preserved without palette quantization. Generation is not deterministic; post-processing and exports are reproducible from the archived PNGs and metadata.

## Gameplay handoff

**These are art-complete candidate packs, not playable faction implementations.** `activation` is explicitly `art_only_optional_pack`; `story_links` and faction `campaigns` remain empty. No `data/` files, simulator, existing campaign, faction-selection menu or game balance were changed. The isolated render harness adds temporary town definitions only to its private `GameData` instance, never to the live game.

To activate them later, the gameplay developer must provide faction economics/native terrain, creature stats and abilities, hero progression and starting armies, building costs/prerequisites/recruitment IDs, and an optional-content/skirmish activation path. The declared art IDs and town-slot hierarchy are the integration contract. No DLC payment or entitlement system is implied by this art manifest.

The delivered action set is movement and attack. Dedicated idle, hit, death, ranged projectile and spell-effect animations remain separate work, as for the existing six factions. Buildings are static layers. Four poses are a first-pass gait; fine limb continuity and timing remain artistic-review items, particularly multi-legged mounts and serpents. Additional independent expansion campaigns, campaign illustrations, terrain sets and music were not authored in this batch.

[Review all assets, loops and Godot screenshots](production/dlc-factions/README.md).
