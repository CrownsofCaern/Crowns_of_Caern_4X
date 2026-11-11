# Expansion campaign artwork

Based on online main at `e135476`. Existing journey paintings were introduced by PR #109; PR #147 identified missing journey paintings for the two expansion campaigns.

Added only missing production art:

- **The Six Eyes:** `assets/illustrations/journeys/six_eyes.png`, ten chapter destinations linked to the shared world atlas, and chapter illustrations 2–10 in `assets/illustrations/six_eyes/`.
- **The Drowned Oath:** `assets/illustrations/journeys/drowned_oath.png`, ten chapter destinations linked to the shared world atlas, and chapter illustrations 2–10 in `assets/illustrations/drowned_oath/`.

All six existing journey definitions, source paintings and runtime paintings, and both expansion opening illustrations, are unchanged byte for byte. The short Long Watch scenario campaign retains its existing fallback presentation. No new campaign UI is introduced: the expansion maps use the current interactive journey screen, chapter markers, progress, travel animation and zoom.

Full-resolution 1536 × 1024 PNGs were generated with the built-in image tool. The approved world-map painting conditioned the two maps; the existing Last Light illustration conditioned chapter art. Prompts, story snapshot, source hashes and generation metadata are in `assets/source/batches/dlc-campaign-art-001/`. Two draft corrections preserve their original images and revision prompts. Chapter markers are game overlays, not baked into the paintings. Review images and contact sheets are in `docs/art/production/dlc-campaign-art/`.

Validation:

- Eight Godot campaign journey tests passed, including both expansion maps, all 20 chapter illustrations, shared-world location bindings, locked previews and the Long Watch fallback.
- Twenty-four UI widget tests passed.
- Full Python asset suite: 80 of 82 passed. The two failures are the pre-existing dark-elf and fish-men ultimate-town export checks, also present in the baseline validation comparison.
- Both Python journey tests passed: source/export pixel equality, prompt/source hashes and chapter-order validation.
- Dedicated illustration validation passed.
- Native Godot captures reviewed for both maps, both locked-final-chapter previews and a phone layout. The review script uses in-memory progress fixtures and does not write saves.
- Existing-art preservation audit passed; `git diff --check` passed.
- Broad asset validation still reports 32 unrelated existing problems (missing encounter sprites and stale ultimate-town exports). A comparison against unchanged main's artwork manifests found the same problems and no new issues; completing the expansion journey catalog removes its missing-journey error.

Reproduce the export with `python3 assets/source/batches/dlc-campaign-art-001/integrate.py`; use `godot --path . --rendering-method gl_compatibility --script res://tools/dlc_campaign_art_review.gd` for the captures. The exporter preserves the full image resolution and uses the established campaign illustration pipeline.
