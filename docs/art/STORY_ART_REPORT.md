# Places, terrain and The Last Light artwork

Branch: art/production-128. Follow-up PR #49. Builds on merged PR #46.

The new map batch contains all 13 existing encounters, all seven resource buildings,
and eight story landmarks: Lockstone, Saint Orrin's Rest, Elderwold stumps, Fenwick
dike, Barrow Camp, Cindermaw gate, Pyrehold and the Wound. Existing IDs and gameplay
footprints are preserved. New landmarks are atlas assets for the level developer;
they do not invent gameplay behavior or automatically place themselves on maps.

There are 16 new terrain sources: four lake-water variants, four river variants,
and two each for grass, swamp, rough ground and forest. The builder prefers these
explicit variants over older single sources and blends their borders to shared
samples, including joins between different variants. Terrain IDs, transitions,
road masks, bridge behavior and movement rules remain compatible.

One 1536x1024 illustration is generated and exported for each of the ten Last Light chapters.
Story authority is PR #45 at a9f18611546bebce9f1edad3cd9bb7cc398a0246.
Its campaign JSON is preserved in the last-light-story-001 batch as a snapshot.
Both chapter intros and outros inform assets/specs/campaign_illustrations.json.
The old Ember Chronicle maps are chapters 8-10, not a separate duplicate story.
The contact-sheet review caught Edda appearing before she joins in chapter 3.
Chapters 1 and 2 were refined to remove her and the blue lantern; their initial
versions and metadata are preserved under the story batch's revisions directory.
PR #45 has since merged upstream; this branch is synchronized with that main
revision. This delivery adds no gameplay changes of its own.

Raw sheets, plans and exact prompts are archived in assets/source/batches.
Generated crops and illustration originals have provenance sidecars and hashes.
Full-resolution illustrations are exported under assets/illustrations/last_light
and indexed by campaign, chapter and usage in assets/campaign_art.json.
They are never sprite-atlased, palette-reduced or downsampled. The lead developer
can connect that manifest to PR #45's briefing UI without changing campaign text.

The existing pipeline now includes stage-illustration and illustrations commands.
Its ordinary build and check also export and compare the campaign images.
Updated inventory and native/contact overview images are in assets/inventory.json
and docs/art/production. The campaign overview is a review aid only.

New art remains pending visual review. Local checks cover build reproducibility,
sprite dimensions/alpha/coverage, cross-variant terrain borders and preservation
of illustration resolution. Broader tests are delegated to CI as requested.
Character continuity, owner flags, terrain repetition and actual Godot views still
need visual review; no completed engine screenshot pass is claimed.

Delivery totals: 28 map sprites, 16 terrain source variants and 10 full-resolution
chapter illustrations. Campaign lookup: assets/campaign_art.json. Chapter overview:
docs/art/production/last-light-illustrations-contact.jpg. Native atlas river review:
docs/art/production/water-river-native-review.png. Broad tests remain delegated to CI.
