# Map editor

Choose **Map Editor** on the title screen to author terrain, roads, scenery,
objects, heroes and player slots. Maps can be saved as drafts before every start
is ready. Saved playable maps appear in New Game with a **Custom** prefix.
Import/export and recovery drafts are still to come. Generated maps can be frozen into bundled maps in dev mode (see below).

## Validate and play

Use **Validate map** to check player settings, ownership, army/content definitions,
starting heroes/towns and connectivity. Conquest maps need at least one human,
distinct player colours, opposing sides when there are multiple players, and a
starting hero and town for each player. Validation checks launchability rather than
balance; asymmetric starts are allowed. Incomplete drafts remain saveable.

Choose a **Playtest seed**, then **Playtest** to play the current unsaved draft.
**Return to Editor** restores the same draft, camera, selection and undo history.
Playtest save/load slots are temporary and removed on return; ordinary saves and
campaign progress are separate. Repeating a seed starts the same authored game.

Save a valid map to offer it in New Game. Authored names, colours, hero classes,
armies and explicit empty garrisons are retained by default. Changing a starting
faction or hero class applies the corresponding setup changes. Custom-game saves
embed the actual map and still load after its source file is changed or removed.

## Create, open and save

- **New** creates a map with a name, dimensions and starting terrain. Each side
  can be 4–256 tiles; dimensions are fixed after creation.
- **Open** lists saved local maps and bundled maps. Ordinary bundled maps open as
  unsaved local copies. Scenario maps and unsupported object types open read-only.
- **Save** writes the current local map. An asterisk beside its name means there
  are unsaved changes.
- **Save As** creates and opens an independent copy with a chosen name and file ID.
  It starts a new undo history. Replacing an existing file requires confirmation.

Maps are stored in `user://maps/`, inside Godot's per-user data directory for Crowns
of Cinder. This is separate from the game's bundled maps and normal saved games.
Malformed files in that folder appear as unreadable entries without hiding other
maps. Failed writes retain the previous file and keep the document marked unsaved.

Leaving, replacing a dirty map or closing the window asks whether to discard it.
Choose **Keep editing** to cancel, then save if needed. Confirming discard on exit
abandons that draft. A clean saved map stays open when returning to the editor.

## Draw the map

Choose a tool in the left panel:

| Tool | Action |
| --- | --- |
| Terrain brush | Paint the selected terrain with a square brush, 1–15 tiles wide. |
| Rectangle fill | Drag between opposite corners to fill a rectangle with terrain. |
| Road brush | Paint connected road tiles, including bridges over water. |
| Erase roads | Remove roads and bridges; the underlying terrain remains. |
| Decoration | Place a registered scenery kind. |
| Erase decoration | Remove authored scenery and suppress automatic scenery on the tile. |
| Place object / hero | Open the content palette and place one entity per click. |
| Move selected | Choose a destination for the selected entity. |
| Duplicate selected | Place an independent copy at a destination. |
| Inspect | Select a tile without changing it. |

Fast drags fill the intermediate tiles. One complete drag is one undo action.
Roads and scenery do not replace the terrain underneath them. Decoration suppression
is stored as an empty decoration kind so it survives saving and reopening.

Terrain choices come from the game's content registry; scenery kinds come from
the built terrain manifest. Registered additions appear when the palette refreshes
on opening the editor. New content still needs the normal definitions and asset
pipeline; dropping an unregistered image into a folder is insufficient.

## Players and starting armies

Choose **Players…** in the right panel. Add up to eight players and set their
names, factions, Human/Computer controllers, colours, computer difficulty and teams.
Team 0 means no team. **Apply players** commits the whole setup as one undo action.

Changing a faction preserves existing towns, hero classes and armies. Removing a
player who owns entities is blocked: first use entity Properties to reassign those
entities, or delete them. Remaining player IDs and ownership references are renumbered
together. Removing an unowned player never silently deletes other map content.

Add players before placing heroes, since every hero needs an owner. New heroes get
their class faction's ordinary starting army; edit it through **Properties…**.

## Place and edit entities

Choose **Objects & heroes**, select a content type and search for the item you want.
The palette includes towns, heroes, mines, resource piles, neutral armies, encounters,
artifacts and sites. Choose **Place for** where ownership applies, then click a tile.
Registered content additions appear without adding palette entries in code.

Placement requires an unoccupied, passable tile. A hero may share its own player's
town tile; the inspector's entity picker lets you select either occupant. A road
or bridge can make otherwise impassable terrain usable.

In **Inspect**, select a tile and choose its entity in the right-hand picker:

- **Properties…** edits the name, position and supported ownership/content fields.
  Heroes expose class and army; towns expose type, buildings and garrison; mines
  expose resource and guards; piles expose resource and quantity; encounters and
  artifacts expose their registered definitions. Dwellings expose creature, initial
  recruits and guards. The fields adapt when changing a site's kind.
- Army, garrison and guard editors support up to ten creature/count pairs. Search
  by creature name or faction, add/remove rows and set whole-number counts. Editing
  a class or player faction does not replace an existing authored army.
- **Move** selects a destination without changing identity. Position fields in
  Properties provide another way to move an entity.
- **Duplicate** copies properties to a new entity ID at the destination. The
  original remains unchanged.
- **Delete** removes the selected entity. Undo restores it and its properties.

Each placement, move, duplicate, deletion and complete property edit is one undo
action. Invalid edits leave the document unchanged. Entity IDs are shown for
reference and remain immutable in the property editor; unexposed fields are preserved.

**Guarded by** links an object to a separate neutral army. Deleting that army is
blocked until linked objects are explicitly unlinked. A mine/site's own guard stacks
are edited separately. Scenario objects, quests, waves and gates remain read-only.

## Controls

| Input | Action |
| --- | --- |
| Left-click / drag | Inspect or use the selected tool. |
| Right- or middle-drag | Pan. |
| Mouse wheel, zoom buttons | Zoom around the pointer or view centre. |
| Trackpad pan / pinch | Pan / step zoom. |
| Alt-click | Sample terrain without painting. |
| Esc during a stroke | Cancel the entire stroke. |
| Esc while placing/moving/duplicating | Return to Inspect without changing the map. |
| Esc otherwise | Return to the title screen, checking for unsaved changes. |
| Ctrl/Cmd+Z | Undo. |
| Ctrl/Cmd+Shift+Z or Ctrl/Cmd+Y | Redo. |
| Ctrl/Cmd+S | Save. |
| Ctrl/Cmd+Shift+S | Save As. |

Enable **Show grid** for tile boundaries. Click a tile to see its coordinates,
terrain, road and existing objects/heroes in the right panel. The inspector displays
authored entities without running a game or automatically changing armies. **Check placement**
reports overlapping entities and impassable positions; it is not yet full gameplay
validation. Opening and closing the editor preserves any game available via Resume.

## Dev mode: bundled maps, frozen generator maps and previews

For building the game's own maps (campaign chapters, curated free maps), start the
game from a source checkout with dev mode on:

```sh
godot --path . -- --maps-dev
```

Dev mode needs that flag and an editor build of Godot, so exported games never have
it. In dev mode:

- **Open** lists bundled maps as *Bundled (in place)*. They open as the real
  `data/maps/<id>.json` file, fully editable, including scenario maps and object
  types the editor has no tools for yet. **Save** writes the file back.
  Scenario data, objectives, quests, teams, `_doc` and any key the editor does not
  know are kept exactly as they were; saving an untouched map reproduces the file
  byte for byte (the layout of `tools/maps/maplib.py`'s `write()`).
- **Save As** on a bundled map writes a new bundled map (`<id>_copy` by default).
- **Open → Or freeze a map id** turns a generated map such as
  `gen:broad_crossing:311`, a random map (`gen:random_m_4p_normal_normal:5`) or a
  mission (`scenario:survival_v1:3`) into a new bundled map. It opens unsaved;
  **Save** writes `data/maps/<new id>.json`.
- **Validate map** runs the full map validator (`MapValidator`) instead of the
  custom-map launch checks.

Objects of types without editing tools (scenario sites, quest items, gates) can be
inspected and deleted but not moved yet. Deleting an object that an objective names
shows up in **Validate map**.

A builder script in `tools/maps` that rewrites a map file replaces editor changes to
it. Once a map has been hand-tuned in the editor, change it in the editor or make the
builder start from the saved file.

### Command-line tools

```sh
# Freeze a generated map into data/maps/<out_id>.json (deterministic; --force replaces an edited file)
godot --headless --path . --script res://tools/maps/freeze_map.gd -- gen:broad_crossing:311 ll_ch3 \
    [--name "The Ember Road"] [--dir res://data/maps] [--preview /tmp/ll_ch3.png] [--force]
# Minimap PNG of a map id or a .json file, or of every bundled map
godot --headless --path . --script res://tools/maps/map_preview.gd -- ll_ch3 /tmp/ll_ch3.png [tile_px]
godot --headless --path . --script res://tools/maps/map_preview.gd -- --all /tmp/map-previews
```

The frozen file drops the generator's `generator` block (it would switch on
generator fairness checks) and records where it came from in `editor_source`
(`map_id` and the generator snapshot: template, seed, version, zones, connections).
Python builders can do the same with `maplib.freeze(source_id, out_id)`, which
returns the map as a dict, and `maplib.preview(map_ref, png)`; `maplib.write()`
then writes the identical file layout. Both call Godot headless (`$GODOT` if it is
not on `PATH`).

Campaign builders that edit a frozen map use the helpers at the end of
`maplib.py`: `obj`/`objs` find objects, `zone_map` labels every open tile with
the generator zone it belongs to, `retheme`/`retheme_zones` swap terrain
characters (a Forge start zone on rough ground instead of the slot's default
grass), `landmark`/`landmark_near` add a 4x4 story set piece from the map
scenery library without stranding any tile, and `redress(d, seed)` repaints
decorations, ground variants and small scenery for the edited terrain
(`tools/maps/redress_map.gd`; large landmarks stay). `tools/scenario_probe.gd`
mode `townless_chapter <game> <town>` checks the townless targets on such a
map or on a campaign chapter.

Preview legend: terrain colours and roads; towns are large squares and heroes
diamonds in their owner's colour (neutral grey); mines gold, piles teal, neutral
armies red, encounters orange, sites violet, artifacts pink, scenario sites, quest
items and gates hollow white; scenario reach targets get a yellow frame.
