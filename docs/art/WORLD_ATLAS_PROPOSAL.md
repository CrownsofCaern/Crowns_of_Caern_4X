# Shared world atlas and regional campaign direction

**Production follow-up:** the six regional journey paintings and interactive campaign selector are now integrated. See the [campaign journey handoff](CAMPAIGN_JOURNEYS_REPORT.md). The atlas revision history below records the earlier planning phase.

The user approved the **geography and painterly regional style** on 2026-11-08, then requested a much larger, more schematic full-world map. The first painting is retained as the campaign-art benchmark. It is superseded as the full-world view by an expanded empire atlas.

[Expanded labelled world atlas](production/world-atlas/world-geography-proposal.png)

## Two distinct scales

The world atlas shows **empires**, with broad hinterlands, numerous settlements, mountain chains, forest domains, river basins and ocean reserves. Six schematic spheres of influence are drawn separately from the source. These are illustrative territorial extents, not new canonical political borders. At least six additional cartographic settlements per faction communicate that campaign towns are only a few places in extensive realms. These unnamed settlements do not create campaign chapters, gameplay towns or new lore names.

Campaign maps will instead be **regional half-map, half-painting journeys**, using the approved first painting's closer, atmospheric style. They cover parts of this world and need not be to scale. Towns, ruins, forests, passes and other destinations should be large enough to be individually recognisable and appropriate to each mission. Routes may bend or compress distances for readability while preserving the identity and directional relationships of shared places. Underground missions require a clearly distinguished inset or layer.

The schematic world atlas must not simply be reused as six campaign backgrounds. The existing six route images are geographic indexes for production, not the final campaign paintings.

## Preserved geography

The existing campaign definitions in `data/campaigns.json` remain authoritative:

- Frostmarch and its ancient glacier lie north of the Concord's northern grain lands.
- The Sunken Forge's western mountains connect to the marches through the mountain gates; the northern Iron Pass links the clans' approach.
- The Concord's cultivated marches occupy the centre. Highmere is an eastern fortress; Greyhold stands farther south.
- The Last Grove survives in western Elderwold. The felled forest and Heartroots lie east of it.
- Sallowmere's fens lie south of the marches and touch the forest. The Barrow Below is underground.
- Greyhold's eastern ford lies between the town and the Wound. The Wound's western approach includes the Lockstone; its ring has two passes toward Cindermaw/Pyrehold.

All sixty chapters retain their actual IDs, order and named shared places. The expanded atlas compresses the earlier regional coordinate system into a smaller part of the world through a recorded affine planning transform. Original regional positions remain alongside world positions in `assets/specs/world_atlas.json`. This preserves geographical relationships; it is not a claim of pixel-perfect projection between generated paintings.

## Empires and expansion room

Each of the six factions now has a schematic influence polygon, label position and six unnamed hinterland settlements in the atlas specification, in addition to its named campaign places. Small settlement symbols and subtly coloured outlines are review overlays, leaving the full-resolution painting reusable without labels.

The eastern/southeastern ocean reserves a substantial continental shelf for **Atlantis** and the fish men. The dark elves retain a separate **deep underground layer** under western mountains and forest, with only sealed surface gateways. Their realm remains distinct from Forge galleries, Hollow barrows and Ashen pits. Western reaches and northern islands preserve further expansion space. These are reserves, not newly authored DLC campaigns.

## Production handoff

The source of the expanded world atlas, exact generation prompt and provenance are archived at `assets/source/batches/world-atlas-002/`. The first source remains unchanged at `assets/source/batches/world-atlas-001/`, with its original provenance.

`tools/world_atlas_review.gd` reproduces the labelled atlas and six geographic route indexes in Godot. Tests cover all sixty chapter mappings, shared crossings, directional constraints, preservation of the regional coordinate relationships, multiple settlements per empire and ocean reserves.

The [chapter/location table](production/world-atlas/chapter-locations.csv) retains actual gameplay-map IDs and surface/underground layers. No gameplay maps, campaign progress, rosters or saved data are changed by this atlas work.

The next production phase is six individual regional paintings and the interactive campaign selector: completed/current/locked stops, descriptive chapter panel and a little hero travelling along authored paths. Continue/restart behaviour, chapter restrictions, touch targets and saved progress must remain authoritative. Geography and regional style are approved; those six final paintings and the production UI have **not** been delivered by this atlas revision.

## Revision verification

- Godot geography checks: three tests pass, covering all sixty existing chapter bindings, shared places, directional constraints, empire context and the recorded coordinate transform.
- Godot review: expanded overview plus all six geographic route indexes rendered and inspected; landmark label collisions corrected, and underground gateway markers aligned with the painted cave entrances.
- Source integrity: source, exact prompt and approved regional-reference hashes verified. The first source is unchanged; the expanded source is retained at its original 1536 × 1024 resolution without resampling or quantisation.
- Asset validation passes. The initial broad reproducibility test ran out of local disk while creating two temporary asset builds. Only regenerable `.ctex` import-cache files from earlier art worktrees were cleared; no source or game files were removed.
- Final `./run_tests.sh world_atlas`: three Godot tests and all 61 Python asset tests pass; committed build output is up to date after the disk-space cleanup.
