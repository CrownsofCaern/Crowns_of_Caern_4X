# Asset pipeline

Map-editor expansion art has an additive catalog in `assets/specs/map_scenery.json`.
Run `python3 tools/assets/build_map_scenery.py` to export its 20 textures and
placement manifest to `assets/map_scenery/`, with a native-size review sheet in
`docs/art/production/map-expansion-001-contact.png`. Original built-in image_gen
sources are preserved in `assets/source/map-expansion-001/`; exact prompts live
in the spec. These candidates are not yet registered in the live editor or
terrain renderer. See `docs/art/MAP_EXPANSION_REPORT.md` for placement details.

Python 3 + Pillow + numpy (rembg optional). Everything the game loads is built from `assets/specs/`:

```
assets/specs/          the source of truth
  palette.json         master palette; its keys double as the charmap for pixel sprites
  style.json           shared prompt text for AI generation (mirrors docs/ART_BIBLE.md)
  creatures.json       one spec per creature in data/creatures.json
  objects.json         heroes, resource pickups, chest, towns, mine
  ui.json              nine-slice frames (panel, buttons, slot, divider)
  terrain.json         tileset: ground, transition priority/fringe, decorations, fog, roads
  pixel/**.txt         hand-authored pixel grids (one char per pixel, '.' transparent)
  pixel/deco/<kind>_<v>.txt  hand-drawn map decorations (48x64, bottom-aligned); procedural only as fallback
  pixel/terrain/*.txt  hand-drawn ground tiles (<ground>_<v>, 40x40, wrap-seamless), fog_<v>, road_<mask>, bridge_<mask>
  pixel/ui/*.txt       hand-drawn UI frames (nine-slice; edges and centre tile, so keep their patterns periodic)
assets/source/generated/<id>.png   raw AI (or any external) images; used instead of the spec source when present
assets/build/          per-sprite output for review (ignored by Godot)
assets/atlases/        what the game loads: units, objects, ui, terrain, deco
assets/manifest.json   rects, anchors, nine-slice margins, terrain layout (read by src/ui/art.gd)
```

## Commands

```sh
python3 tools/assets/pipeline.py build      # build + validate + godot --import
python3 tools/assets/pipeline.py validate   # sizes, hard alpha, palette, naming, coverage of game data
python3 tools/assets/pipeline.py check      # committed output == fresh build, compared by pixels (run by ./run_tests.sh)
python3 tools/assets/pipeline.py prompts    # assets/source/prompts.md: the full prompt for every asset
python3 tools/assets/pipeline.py generate --provider openai [--only creature_flayer] [--force]
python3 -m unittest discover -s tools/assets/tests
```

## Stages

1. **Spec.** Every asset has an entry (id, size, palette, outline, anchor, atlas, prompt, source) before it exists.
   Ids are snake_case and prefixed by kind (`creature_<data id>`, `resource_<data id>`, `town_<faction>`, `ui_*`).
2. **Source.** In order of preference: a raw image in `assets/source/generated/<id>.png`; else the spec's
   `source`: `pixel` (hand-authored grid) or `procedural` (deterministic drawer in `procedural.py`).
3. **Generation hook.** `generate` builds the prompt (style preamble + category + spec prompt + constraints)
   and asks a provider for a 1024 px image. Built in: OpenAI Images (`OPENAI_API_KEY`, model `gpt-image-1`,
   override with `REIGNEM_IMAGE_MODEL`). Any other service works by saving its output into
   `assets/source/generated/` under the asset id.
4. **Post-process** (generated sources): background removal (`rembg` if installed, else border flood fill,
   which is exact for the flat magenta backdrop the prompts ask for) → crop → fit into the target grid
   (box downscale, anchored bottom-centre) → hard alpha → quantise to the master palette → outline pass →
   export scale (nearest neighbour).
5. **Validate**: size, hard 0/255 alpha, transparent background (sprites) or opaque (tiles, frames), every pixel
   on the palette, unique snake_case ids, and coverage: every creature, resource and terrain in `data/` has art.
6. **Atlas + manifest**: deterministic shelf packing; terrain is a fixed grid (see below).
7. **Godot import**: `build` runs `godot --headless --import`. Pixel art is drawn with nearest filtering by the
   nodes that use it (`MapView`, `UiStyle.icon`), so import defaults are fine.

## Terrain tileset

`terrain.png` has one row per terrain (sorted by priority), then fog, then roads. Columns: 4 ground variants,
then four sets of 46 feathered transition overlays (one per distinct neighbour shape: 8 neighbours, corners only count when neither
adjacent edge does). In game, every cell gets its ground tile, then each different neighboring terrain is
drawn on its own `TileMapLayer`, with a ragged, softly blended edge. Both sides contribute half at their shared boundary, with rounded
corners. A stable per-cell hash selects a fringe variant; their profiles meet at
tile edges. Connected 12×12 ground fields use a periodic-plus-smooth correction to wrap without blurred edge
strips. Eight sparse, deterministic detail overlays add small-scale material marks beneath the terrain blends.
`terrain_edges.png` contains pair-specific, horizontally periodic materials for grass/water cliffs,
desert/water beaches, and dry grass/desert margins. Their 8-neighbor contours round corners, and their
world-coordinate phases shift gradually between shorelines. Each dedicated contour fills the neighboring
terrain up to the edge, replacing the general diffuse blend for that pair. Other pairs retain the general blend.
Fog uses the same 46 shapes with stepped, dithered alpha. Roads use a 4-bit connection mask; roads over
river or water use the bridge column. Decorations (pines, peaks, dead trees, obsidian, rocks, bones,
graves) are 48×64 outlined sprites in `deco.png`, hand-drawn in `assets/specs/pixel/deco/<kind>_<variant>.txt`
(the procedural drawer is only a fallback for a missing file), placed by a stable per-cell hash and y-sorted
with objects and heroes. Each kind has `deco_variants` (10) cells: its `deco_drawings` (5) distinct drawings,
then the same mirrored, then shade-shifted when a kind has fewer drawings (`build.deco_variant`).
`deco_derived` in terrain.json adds kinds recoloured from another kind's drawings (`build.recolor_deco`:
hue, saturation, value, tint, frost), e.g. autumn pines or frost trees. Generated maps place
decorations themselves (data/terrain_painting.json).

## Swapping in generated art

Individual artifact inventory images are sourced from `assets/source/artifacts-001/`,
with source filenames and prompts recorded in that directory's `manifest.json`.
The normal build creates centered 64×64
textures in `assets/artifacts/`; every ID in `data/artifacts.json` must have a
source image. The hero equipment and pack slots use those textures for occupied
slots and retain the generic slot icon as a fallback.

Faction UI materials use ui_panel_<faction> entries in ui.json and the archived
faction-ui-001 source sheet. Opaque generated UI sources retain their full canvas
and frame during processing. Cursor entries use the deterministic UI cursor drawer
in crowns_of_cinder_assets/ui_art.py, native 40x40 dimensions and a 2,2 hotspot exported in
the manifest. Run preview_cursors.py to rebuild the cursor contact sheet.

Campaign scenes are specified in `assets/specs/campaign_illustrations.json`.
`pipeline.py stage-illustration --id <id> --source <image.png>` preserves the raw
image and records story/prompt provenance. `pipeline.py illustrations` exports
full-resolution textures into `assets/illustrations/<campaign>/`, writes the
chapter lookup in `assets/campaign_art.json` and creates a review contact sheet.
Every chapter of every campaign now has a painting (see `docs/artwork-audit.md`
for coverage and the batch each one came from). The prompts and story snapshot for
chapters 2-10 of the five base campaigns, and for The Long Watch, are in
`assets/source/batches/new-campaigns-001/`.
The ordinary build/check commands include these exports. Illustrations are not
palette-reduced, sprite-atlased or downsampled.

Explicit `terrain_<id>_<variant>.png` sources take priority over a single
`terrain_<id>.png`. All variants share opposite border samples and a small blend
band so different variants also meet at their outer pixel rows.

Production batches on `art/production-128` use `assets/source/batches/<batch>/plan.json`
and `prompt.txt`, with the original generation retained as `source.png`.
Stage a new planned batch with `python3 tools/assets/stage_batch.py <batch> <source.png>`.
This refuses source replacement, preserves disconnected swarms/effects, writes
per-asset provenance and updates existing sprite specs. It is a mechanical import,
not visual approval. Review source boundaries and native contact sheets before
accepting an asset; use `pipeline.py batch-contact --batch <batch>`.

Generated hero/creature sources use 128px native sprites and map scale 0.5.
Towns use 192x160 and map scale 0.5, with flag anchors scaled proportionally.
`generated_palette: preserve` retains generated material ramps while legacy grids
remain on the master palette. Terrain sources `terrain_<id>.png` feed the existing
40px terrain/transition layout; the build creates four shifted variants and pairs
opposite edge samples. Generated `deco_<kind>_<variant>.png` replace decoration
cells at their existing 48x64 footprint. Missing variants reuse the original two drawings.
Ground and decoration sources are optional: missing sources retain their existing
pixel drawings. Ground, road and transition readability still needs in-engine review.

Raw sources are excluded from Godot import with `assets/source/.gdignore`; only
built atlases are loaded by the game. `pipeline.py inventory` records generation
and review states separately. User design approval does not imply engine QC.

Generate (or drop in) `assets/source/generated/creature_flayer.png`, run `build`, look at
`assets/build/creature/creature_flayer.png`, commit the raw image and the rebuilt atlases. Delete the raw image
to fall back to the hand-authored sprite. Keep generated sets coherent: regenerate a whole faction at once.

UI symbols: `assets/source/batches/symbols-001/source.png` is the project owner's 3x3 symbol sheet (already transparent).
Its cells are cropped, untouched, into `assets/source/generated/ui_icon_<name>.png` (day, town, hero, attack,
armor, defense, move, charm, banner; crops in `layout.json`). They build at 48x48, export scale 1, with
`generated_palette: preserve` and no added outline. UI code shows them smaller with linear filtering
(`UiStyle.icon`, `UiStyle.button_icon`, `ArtifactSlot`); power, knowledge, xp and pack are still the 16 px grids.

## Faction town scenes

`assets/specs/town_scenes.json` gives every faction a background, slots (feet position and size in background
pixels) and building art. Slots must name every building ID of the faction exactly once; art may still be
missing for some IDs, and the town view then shows a name plaque on that site once it is built. An asset entry
`{"same_as": "<id>"}` reuses another building's art (upgraded dwellings reuse their base dwelling).
Concept building sheets (3x3 cells on transparency) are cut by `crowns_of_cinder_assets/town_sheets.py`: it drops the
generator's red halo and loose specks, never repaints, and writes `assets/source/generated/town_<faction>_<id>.png`
from a batch `layout.json` (see `assets/source/batches/thornwood-town-001/`). Render every faction's town view
with `xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/town_scene_review.gd -- /tmp/towns`.

# Optional expansion faction artwork

`assets/specs/dlc_factions.json` declares the Umbral Court and Abyssal Shoal
visual rosters, stable IDs and town-layer contracts. This is an optional art
pack and does not activate gameplay factions or attach campaign stories.

After restoring the archived source sheets,
`python tools/assets/pipeline.py stage-dlc` reproduces the crops with the
existing animation gutter extractor.
Normal `build`, `check`, `validate` and `inventory` commands include these assets.
`stage-dlc --batch darkelf-creatures` stages one source batch. Hash guards reject
changed original sheets or replacement of established art.

Static exports use separate DLC atlases bounded to 2048×2048; creature and hero
clips use the existing animation manifest and runtime. Town layers use the
existing town manifest. Run `python tools/dlc_art_review.py` for native-scale
review sheets and GIFs. See [the handoff](../../docs/art/DLC_FACTIONS_REPORT.md)
for coverage, Godot captures and the separate gameplay integration work.

# Idle, walk and attack sheets (second animation pass)

`assets/specs/creature_idle_animations.json` mirrors the move/attack groups with two sheets per group: A (7 columns:
3 idle poses, then a 4-pose walk) and B (6 columns: anticipation, wind-up, main hit in column 3, a follow-up blow or
follow-through, recovery). `python3 tools/assets/generate_idle_sheets.py` writes the prompts, generates sheets through
the OpenAI image API (`OPENAI_API_KEY`, `api.openai.com` allowed), `import`s sheets made by hand in ChatGPT (it finds
the group by comparing with the stills and tells A from B by the column count), renders review boards and GIFs, and
`approve` records both sheets' hashes. `pipeline.py build` then cuts them like the move/attack sheets into
`animation_idle_<group>_a/_b.png` and replaces the unit's move and attack clips and adds an idle loop. Groups
without both sheets approved change nothing. The ChatGPT task file the project owner pastes is generated from the same prompts.

# Battle clips baked from 3D models

Units can take their battle clips (idle, move, attack, death) from a rigged 3D model instead of the drawn sheets;
the map, town and still sprites keep the drawn art. `assets/specs/creature_models.json` lists the units
(`crowns_of_cinder_assets/model_animations.py`).

1. Make the model. The cheapest route is the Tripo website: upload the creature's painting, rig it, add idle,
   walk, one attack and a death animation, export **GLB**. `python3 tools/assets/tripo.py` does the same through
   the API (`TRIPO_API_KEY`, `api.tripo3d.ai` allowed) and records every task so nothing is paid twice.
2. `python3 tools/assets/bake_models.py import <id> <file.glb> [...]` copies the GLB(s) to
   `assets/source/models/<id>/` and maps clips to actions by name (`--map attack=Bite` overrides).
3. `python3 tools/assets/bake_models.py render <id> --review /tmp/bake` renders every clip with
   `tools/assets/render_model.gd` (Godot, `GODOT=`; xvfb-run without a display; run `godot --import` once on a
   fresh checkout) and reduces it to pixel art: one scale per unit (rest pose as tall as the drawn still, or
   `view.height_px`), feet on the battle anchor, box downscale, master palette, 1 px outline. It writes
   `assets/source/models/<id>/<id>_bake.png` (one action per row, 320x256 cells) plus a review board and GIFs.
   Tune `view` (`yaw_degrees`, `pitch_degrees`, `shift_x`, light energies) and each clip's `frames`, `ms`,
   `start`/`end` and the attack's `impact_frame`, then render again.
   Weapons: image-to-3D meshes are welded, so a pike or spear is skinned to the arm and legs and bends in every
   clip. `python3 tools/assets/split_weapon.py <id>` cuts the pole out of the unit's clip GLBs (in place: keep
   the downloads) and records `weapon` in the spec; the renderer then holds a clean rigid pole in the hand bone.
   A clip with `"pose": "pole_thrust"` (use the idle GLB and clip) ignores the clip's motion and poses a
   two-handed pike thrust on the shared human skeleton (draw back, lunge, hold, recover) with arm IK on the pole,
   so polearm units need no paid attack animation. In the death clip the pole leaves the hand and topples flat
   beside the body. A unit's `throw` (`bone`, `sphere` [x, y, z, r] in mesh space, `release`, `speed`) cuts a
   welded missile (a boulder) out of the mesh, carries it in that hand and lets it fly from the attack at `release`;
   the `thrower` class pairs it with Mixamo's Goalkeeper Overhand Throw. `"pose": "quad_lunge"` does the same for Tripo's quadruped rig
   (crouch, leap with the forelegs reaching, bite, recover), since Tripo only offers a quadruped walk. Flyers
   (Tripo's avian rig, no presets) use `"pose": "wing_hover"` (a looping wing beat, for idle and move; set
   `"loop": true`) and `"pose": "wing_dive"` (rear up, swoop, bite) on the rigged GLB with `"clip": ""`.
   More poses: `quad_charge` (a mount and rider rigged as one quadruped rear up, then crash forward),
   `bow_draw` (side-on draw to the cheek and loose; `"hand_turn": -90` stands a welded bow upright), `cast`
   (staff up, then thrust at the enemy) and `throw` (overhead wind-up, hurl), the last three over the idle GLB.
   `"amount"` scales the quadruped poses for long or heavy bodies. `"in_place": true` on a clip cancels root
   motion that walks the unit out of its cell.
   Rigid weapons: `python3 tools/assets/rigid_weapon.py show|apply <id>` keeps a welded sword, staff, lantern or
   shield in the mesh but re-skins it 100% to one bone, so it moves as one piece. Regions go in the unit's
   `rigid` list in bind space: `{"bone": "mixamorig:RightHand", "auto": true}` finds the longest thin straight
   piece through the hand (blade, staff) and records it as a `capsule`; `capsule`, `box` and `slab` (an upright
   shield, a polyline seen from above, grown over the connected sheet) mark the rest by hand; `{"drop": true,
   "box": ...}` deletes stray geometry. `show` draws the model from three sides on a grid, coloured by bone, to
   read coordinates off. A unit's `hold` list (`bone`, `axis`, `clips`) keeps a staff or lantern pointing the
   way it does in the model during those clips, however the clip turns the hand.
   Class animations: `python3 tools/assets/mixamo_set.py <id> <class> --fbx-dir DIR` retargets shared Mixamo
   clips (FBX, Without Skin) onto the unit with `tools/assets/retarget_mixamo.gd`, writes
   `<id>_mx_<action>.glb` per action and points the spec at them (`mixamo_set.py classes` lists the classes:
   sword_shield, spear, bow, caster, caster_2h, thrower, brute, heavy, club). `--clip ACTION=FBX@START-END`
   swaps one action's clip for variation; `--mirror` plays every clip left-right mirrored, for units whose
   weapon Tripo rigged to the left hand (the swing then uses the weapon arm). Mounts and riders: a unit
   `lance` (`capsule` [grip, tip, r] in mesh space, optional `aim`, `level_degrees`, `head_radius`) cuts a
   welded lance into a rigid piece on the spine that couches level in `quad_charge`/`quad_lunge`; the pose
   `quad_idle` gives beasts an idle; beasts are framed over their whole first clip; a unit `wings`
   [boneA, boneB] names a flyer's wing roots when `wing_hover` can't find them. The target is first matched to Mixamo's T-pose
   bone by bone, so every retargeted unit faces +Z (yaw 45 shows it facing the enemy), and weapons from
   `rigid_weapon.py` are turned to sit in the hand the way Mixamo's clips expect.
4. `python3 tools/assets/bake_models.py approve <id>` records the sheet hash; `pipeline.py build` then slices it
   into `animation_model_<id>`. GPU renders are not byte-identical, so the approved sheet is the committed
   source; GLBs are git-ignored (keep them in the project files) and only needed to render again.

## Equipment artwork expansion 002

The artwork-only catalog in `assets/specs/batches/equipment-002.json` defines 112
new inventory designs: 28 each of minor, major, relic and legendary quality.
Original transparent paintings, exact prompts, validation results and contact
sheets are documented in [`assets/source/equipment-002/README.md`](../../assets/source/equipment-002/README.md).
Run `python3 tools/assets/build_equipment_expansion.py` (Pillow and NumPy) to
rebuild centered 64 px and 128 px sprites in `assets/equipment/expansion_002/`
and the review sheets. Elemental highlight colors are preserved. Every design is
also a hero artifact in `data/artifacts.json` (legendaries are relics; the poison,
fire, frost and lightning legendaries form four sets), so the artifact build
(`crowns_of_cinder_assets/artifacts.py`) exports their icons to `assets/artifacts/`
from these sources too.
