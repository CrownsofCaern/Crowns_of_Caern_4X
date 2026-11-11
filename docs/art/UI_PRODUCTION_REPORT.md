# Faction interface and contextual cursors

The live game now uses six faction UI materials: Concord navy/steel/brass,
Ashen blood-red iron, Hollow charcoal with neon grave green, Thornwood bark/moss,
Forge soot/bronze/furnace orange, and Frostmarch cold leather/iron/ice blue.
Palette definitions are in assets/specs/faction_ui.json. Six panel textures are
generated from the archived faction-ui-001 sheet through the existing pipeline.
Nine-slicing preserves the corner ornaments; the quiet material centre stretches
without repeating decorations or introducing obvious texture tiles across text.

UiStyle keeps one live Theme resource and updates already-created controls when
the active human player's faction changes. This covers new games, loaded sessions,
campaign starts and hot-seat handovers. HUD bars, buttons, focus indicators,
tooltips, dialogs, portrait backdrops, slots and menu glow use the faction palette.
Warning/success colours, artifact rarity, resource icons and player banner colours
retain their meaning. Accent-on-panel contrast is tested for all six palettes;
progress text has a dark outline so bright green/orange fills remain readable.

Nine 40x40 iron-and-brass cursor assets are built deterministically from structured
specs: default, movement, town entry, attack, pickup/capture, encounter, hero
selection, blocked route and wait. Every cursor has the same 2,2 hotspot.
AdventureCursor reads session state without issuing game commands. It caches the
hover decision and invalidates it for state/selection/camera changes, respects GUI
and modal ownership, and resets custom cursors on exit. It checks fog before hidden
terrain, heroes, guards or objects. Owned mines do not look like unclaimed pickups.
Clicking the selected hero's current friendly town now opens it consistently with
the town cursor, without requiring movement points.

Production sources, prompts and per-panel provenance are preserved. Cursor source
is tools/assets/crowns_of_cinder_assets/ui_art.py, with parameters and hotspots in ui.json.
Opaque UI post-processing preserves the complete frame instead of flood-removing
the border. Legacy pixel artwork remains intact. Updated outputs are in the UI
atlas/manifest; build, validate and check remain the reproducible workflow.

Validation completed:

- 17 existing Godot UI-widget tests and five new faction/cursor tests pass.
- All 30 Python asset-pipeline tests pass, including opaque-frame preservation.
- Live OpenGL Godot renders cover HUD and hero screens for every faction, plus
  Hollow-to-Ashen hot-seat privacy/theme checks. Fourteen game screenshots and a
  native/enlarged cursor contact sheet are in docs/art/production/ui/.
- Asset validation, deterministic build checks and whitespace checks are run
  before delivery. Wider gameplay/campaign testing remains with CI.

Reproduce screenshots with tools/ui_screenshots.gd under an X11 display and the
OpenGL renderer. That review helper is separate from the game flow. Panel sources,
native contact sheets and the full screenshot set are committed for review.
