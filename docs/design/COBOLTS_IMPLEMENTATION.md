# Cobolt gameplay implementation

Implemented 2026-11-09, following [the approved design](COBOLTS.md).

## Player behavior

- Neutral, non-playable cobolts have five recruit tiers and three commercial post levels.
- Arriving at a post opens its shop without fighting. Each post has one recruit type, one artefact, and one directional resource exchange.
- The resource exchange costs exactly 60% of the equivalent **one-market** input under the current economy. Eight-unit output bundles avoid rounding drift for all non-gold resource pairs. This checkout contains no separate trade-camp rule; the UI names the baseline explicitly.
- Recruitment uses normal creature prices. Artefacts use normal artefact values. Recruits and exchanges refill to a cap weekly; artefacts never refill.
- Unscouted posts disclose no military strength. Scouts reveal coarse visible-patrol observations and roles, with reserves unknown. Master scouts still cannot reveal exact numbers or odds. Reports expire daily and are player-local.
- Robbery requires an explicit confirmation. Commitment makes that player locally hostile immediately. Defeat or withdrawal leaves the post available to other players and retains surviving guards.
- Victory grants a fixed gold cache and the unsold artefact, then permanently closes the post to everyone. Bought artefacts cannot duplicate as loot. Full-pack artefacts drop nearby, or remain recoverable at the post if no drop tile exists.

## Integration

`MapCobolts` handles persistent initialization, restock, reports, access policy and validation. `GameSession` handles commands, masked intel and battle resolution. Existing movement, battle simulation, scouting costs/range and daily scouting lifetime remain shared systems.

Generated maps place one to three posts in neutral zones on an independent random stream; authored maps receive one reachable independently seeded post at new game if they have none. Existing saves do not acquire new posts when loaded. New saves use version 23 and preserve stock, guards, hostility, loot and ruins.

The map editor offers all three sites and validates their persistent stock. AI heroes can value and hire public stock from day 8 (`StrategicAI` setting `cobolt_from_day`); they do not forecast secret armies or attempt robbery in this first pass. Allowing week-one purchases tripled early capital losses in AI duels on twin_marches (9 of 40 seeds ended before day 12, against 3 without cobolts). Ordinary random guards and dwelling pools exclude cobolts so the new roster remains tied to the trading houses.

## Art and verification

Eight concept-matched production still sprites are included for five creatures and three posts. They match the existing detailed, outlined painterly pixel art, top-left lighting and desaturated material colors. Unit sprites use the existing 128px native grid at 0.5 scale; posts use 160×144 at 0.5 scale. Exact built-in imagegen prompts, references and source provenance are retained. Animation states and a dedicated ruin drawing remain future production work. A plundered post currently uses a darkened map sprite and explicit ruin text.

Real-renderer QA is reproducible with:

```sh
godot --path . --rendering-method gl_compatibility --script res://tools/cobolt_preview.gd -- /absolute/output/path
```

The preview exercises actual map arrival and shop buttons, resource purchase, scouting, cancellation of robbery, and the plundered state. Captures are in `docs/art/production/cobolts/`.

Focused headless coverage includes offer pricing, atomic failed purchases, recruitment, artefacts, hidden guard payloads, master scouting, daily/player-local reports, stock caps, save/load, old saves, victory and defeat, duplicate-loot prevention, full-pack loot recovery, map generation, stock validation, AI secrecy/hiring and panel construction.

Verification results:

- 11 focused cobolt tests pass; real-renderer visit/purchase/scout/cancel/plunder assertions pass.
- 40 Python asset tests pass; `pipeline.py check` reports “build output up to date”; `git diff --check` is clean.
- The full game run executed 710 tests and initially reported 18 failures. After fixing cobolt initialization/sprite issues and updating tests for intentional new behavior, all 18 affected cases were rerun individually. Nine now pass; the remaining nine reproduce in an isolated clean checkout of HEAD (`dc467ab`) and are pre-existing. The full suite was not rerun a second time.
- The two fixed-map AI balance benchmarks explicitly remove randomly spawned cobolt posts to retain their controlled, mirrored economy. Dedicated cobolt tests retain posts and verify AI public-stock valuation, hiring and refusal to forecast concealed armies. Ecology coverage excludes trading-house escorts, which intentionally travel across biomes.

Pre-existing failing cases verified on clean HEAD: `test_save_keeps_equipment_and_migrates_v5`, `test_version_1_save_gains_towns_and_mines`, `test_skill_offers_follow_class`, `test_version_one_save_migrates_and_round_trips`, `test_version_two_save_migrates_and_round_trips`, `test_migration_skips_encounters_on_occupied_tiles`, `test_save_stores_generated_terrain`, `test_upgrade_garrison_stack_for_cost_difference`, and `test_upgrade_hero_stack_merges_with_existing_upgrades`.

PR integration: rebased onto main at `5d88803`; save version advanced to 23 (main's war council took 22). Validation below records the original development base separately from the integrated PR checks.

Integrated PR verification on main `5d88803`: 11 cobolt tests and 76 related scouting/trader/site/data/scenario tests pass; renderer QA passes with the production stills and bounded shop header. Native style review is in `docs/art/production/cobolt-style-contact.png`. The 71-test Python run exposed pending-animation schema assumptions; those cases now pass after declaring pending move/attack and idle groups, preserving reference hashes and scoping DLC completeness to DLC units. The three remaining Python failures concern the unchanged campaign journeys and darkelf/fishmen ultimate exports. Full integrated game suite was not rerun.

Final integration also includes main `e98452e` (new AI forecasts, story boss art and idle plans). The optional simulation-count forecast argument and existing story/DLC animation groups are preserved. After that merge, the scoped runner passes all 11 cobolt tests, four affected animation/provenance checks pass, and real-renderer QA completes with the production artwork.
