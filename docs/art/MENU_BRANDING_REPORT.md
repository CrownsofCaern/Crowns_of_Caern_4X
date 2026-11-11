# Crowns of Caern — current branding

On 2026-11-10 the title changed to **Crowns of Caern**, and Caern became the name of the world (see ../FACTIONS.md). The README and main menu share the updated wordmark. Godot uses the new title for its user directory. Startup copies existing saves and settings from `Crowns of Cinder` first, then `Reignem`, without overwriting destination files or deleting originals.

The replacement wordmark was edited with the built-in image generator. Its exact prompt, PNG and provenance are in `assets/source/batches/caern-menu-001/`. The source is 2172×724 RGBA with genuine transparency; `assets/menus/menu_wordmark.png` is a byte-for-byte export.

Validation for this rename: five save-migration tests and four menu-branding tests passed, and the Python menu export reproducibility test passed. The main menu was rendered in Godot and visually checked: [preview](caern-main-menu.png). The full gameplay suite was not rerun for this branding change.

The following is the historical report for the original artwork batch. Its project-name and validation notes describe that batch, not the current configuration.

---

# Crowns of Cinder — menu art and branding

> Historical production report. The project now uses Crowns of Cinder as its Godot name; `LegacyUserData` migrates the former Reignem user directory.

The user selected **Crowns of Cinder** as the game title on 2026-11-07.
The repository and internal project/save identity remain Reignem so existing saves,
campaign progress and audio settings stay in their current user directory.
The visible game title and window title use Crowns of Cinder.

Six original high-resolution assets are included: title panorama, campaign war map,
new-game/settings war room, save/load archive, a standalone cracked-crown emblem,
and the Crowns of Cinder wordmark. Backgrounds reserve quiet central space for
readable controls. Their source dimensions and SHA-256 values are specified in
assets/specs/menu_art.json. Raw PNGs, prompts and provenance are preserved.
Game exports are exact byte copies under assets/menus; logos are alpha-cropped at
runtime without changing their high-resolution sources.

MainMenu switches background art between home, setup and campaign screens.
The logo header compacts on inner menus so the existing chapter scroller remains
usable. Save/load uses the archive; audio/settings uses the war room.
Existing faction panel themes and gameplay flow remain intact.
MenuArt provides a plain-text title fallback if logo textures are unavailable.

The existing asset build exports the menu manifest/images and its check command
compares them with a fresh build. The application icon uses the new emblem.
The project config/name remains Reignem intentionally to preserve the save path.

The execution workspace became unavailable during this batch. Artwork was
generated and inspected, PNG dimensions/hashes checked in orchestration, and
source/integration changes committed through GitHub's Git-data API. The SHA-256
implementation was checked against the standard abc test vector.
**The menu code has not been run in Godot locally.** CI and a follow-up rendered
review must validate layout, imported logo alpha, aspect ratios and scene loading.
Earlier faction UI screenshots/check results are in UI_PRODUCTION_REPORT.md.

New automated checks cover menu routing, header compaction, resource loading, save identity and byte-preserving exports. These checks are added for CI but were not executed in the unavailable workspace. Rare-site cursors now use the encounter action for unguarded sites introduced upstream.
