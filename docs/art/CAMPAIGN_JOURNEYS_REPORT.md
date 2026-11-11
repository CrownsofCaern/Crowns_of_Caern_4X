# Campaign journey artwork and selector — developer handoff

**Campaign** now opens an interactive regional journey painting instead of six scrolling chapter lists. Every original campaign has a separate painting with ten mission stops. Chapter victories route through this view before the next briefing, so the existing animated leading hero travels between destinations.

## Content and preservation

Six paintings follow the approved original regional style: The Last Light, The Pale Inheritance, The Unsealing, The Briar Oath, The Shuttered Halls and The Ashwinter. Towns, ruins, forests, passes, frozen fens and underground destinations follow the actual mission texts. Cutaway areas distinguish the known barrows, Forge halls and Ashen pits from the surface. They do not reveal the reserved dark-elf DLC realm.

The 60 existing chapter IDs and their shared-world location identities remain authoritative. Regional screen positions are deliberately composed rather than to scale. Revisited Elderwold stumps remain nearby in one painted area; marker spacing is adjusted for selection. No authored gameplay map coordinates or campaign definitions change.

The original 1536 × 1024 outputs, exact prompts, story snapshot, reference conditioning and hashes are archived under `assets/source/batches/campaign-journeys-001/`. The approved first world painting is the style reference. The schematic empire atlas remains the geographic overview and is not reused as six backgrounds.

## Runtime integration

- `CampaignJourneyScreen` reads the existing `Campaign.chapter_list` states and shows the selected mission's real story, caps and veteran summary. The top picker selects a campaign; stops are clickable, focusable buttons with tooltips.
- `CampaignJourneyMap` renders the painting, completed/current/future routes, dashed underground legs and existing hero idle/move clips. Hero travel is presentation only; motion can be disabled. Mouse-wheel/button zoom and touch/mouse dragging keep positions attached to the painting. Phone layouts initially frame the current stop; larger views show the whole painting.
- Completed and locked stops can be inspected but cannot launch. Current-chapter begin/resume/play and confirmed start-over emit the existing `(campaign_id, fresh)` signal. Save formats, unlock rules, hero carryover and active-game restoration are unchanged.
- `MainMenu` replaces the old chapter-list panel with the full-screen journey view. `AdventureScreen` opens that view from the victory button, while defeats retain direct retry. The actual chapter briefing and its separate story painting are preserved.

## Existing pipeline

The six assets are entries in `campaign_illustrations.json` with usage `journey`, exported by the existing `pipeline.py illustrations` command into `assets/illustrations/journeys/` and the generated `assets/campaign_art.json`. The sources retain their original pixels and dimensions. No sprite-atlas reduction or palette quantisation is applied.

The same pipeline now records the supplied journey conditioning and local story snapshot during staging, rather than recording old Last Light defaults. Validation rejects drift between journey nodes and actual chapter order. The illustration contact-sheet command separates journey art from briefing art. Inventory records resolve each campaign's actual faction instead of hard-coding Concord and preserve journey provenance and review status.

## Review and reproduction

[Contact sheet and actual Godot captures](production/campaign-journeys/README.md) show all six campaigns, hero travel, locked preview, completion, portrait and phone zoom. The capture script creates in-memory progress fixtures and never writes player saves.

```sh
python3 tools/assets/pipeline.py illustrations
python3 tools/assets/pipeline.py inventory
./run_tests.sh campaign_journeys
xvfb-run -a godot --path . --audio-driver Dummy --rendering-driver opengl3 --script res://tools/campaign_journey_review.gd
```

Coverage includes all real chapter/location bindings, read-only previews, lock enforcement, finished campaigns, active-save/fresh/restart signal contracts, zoom coordinates, source pixel preservation, six distinct sources and prompt/reference provenance. Final validation results are recorded below after the production batch is complete.

## Final local results

- 68 campaign-focused Godot checks passed, including campaign progress, real chapter bindings and journey integration.
- 24 UI widget checks and four menu/branding checks passed.
- `./run_tests.sh campaign_journeys` passed: six focused journey checks, all 63 Python asset checks and fresh-build consistency.
- Asset validation passed. All six runtime paintings match source RGB pixels and dimensions; exact prompt hashes and six distinct source hashes are verified.
- The actual Godot menu was captured for all six campaigns plus travel, locked preview, completion, portrait and phone zoom. No player saves were written by the review tool.

The broader gameplay suite is left to CI; these changes do not alter headless gameplay rules or save formats.
