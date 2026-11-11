# Artwork coverage audit

Snapshot: 2026-11-07; campaign illustrations updated 2026-11-10. Coverage means artwork is wired into the game, not that it has passed in-engine visual review.

## Town scenes

Concord has a layered town scene covering its 30 buildings. Ashen (30 buildings), Hollow, Thornwood, Forge and Frostmarch (29 each) have no layered town scene. All six factions do have adventure-map town sprites; those are separate from the interactive town scenes. The missing scenes require faction-specific backgrounds, individual transparent building layers and slot layouts for their actual building rosters.

## Campaign illustrations

Every campaign chapter has a briefing illustration: 91 in total, ten for each of the eight ten-chapter campaigns and three for The Long Watch. Each of the eight ten-chapter campaigns also has a painted journey map. The Long Watch has no journey painting and uses the journey screen's fallback stops. All are listed in `assets/campaign_art.json` and remain `pending_visual_review`.

Where they came from:

| Campaign | Chapter 1 | Chapters 2-10 | Journey map |
|---|---|---|---|
| The Last Light | `last-light-story-001` | `last-light-story-001` | `campaign-journeys-001` |
| Pale Inheritance, Unsealing, Briar Oath, Shuttered Halls, Ashwinter | The project owner's concept library | `new-campaigns-001` | `campaign-journeys-001` |
| The Long Watch | `new-campaigns-001` (all three chapters) | | none |
| The Six Eyes, The Drowned Oath | faction foundation paintings | `dlc-campaign-art-001` (PR #174) | `dlc-campaign-art-001` |

The `new-campaigns-001` batch also holds alternative chapter 1 paintings for the five base campaigns. Those are not exported: the concept-library openings stay in the game.

## Hero equipment

All 42 artifacts use generic slot icons rather than individual item artwork. The generated UI concept sheet from the previous discussion has not been integrated; it needs separate production assets and implementation before it can replace the current icons.

## Map decorations

Forest, rough ground, graves, snow pines, swamp trees and obsidian have five distinct atlas variants each after this change. Bones and mountain peaks still reuse two generated designs across five cells. Decoration placement is deterministic and decorative; it does not alter terrain rules.
