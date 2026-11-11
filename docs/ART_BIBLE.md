# Crowns of Caern art bible

Reference image: [`art/art_direction_reference.png`](art/art_direction_reference.png) (art direction, 2026-11-06).
It shows mood, density and UI framing. It is a target for *feel*, not a sheet to copy: every final asset must be
our own design, and nothing may echo Heroes of Might and Magic III creatures, towns, heraldry or UI layouts.

## Pillars

1. **Dark gothic fantasy, not cartoon horror.** Oppressive environments, ruined settlements, blood-red skies,
   ominous low-key lighting with warm firelight and cold moonlight as the two accent temperatures.
2. **Slightly pixelated, strongly outlined, highly readable.** Pixel-art rendering at a modest resolution with a
   dark (not pure black) outline on every sprite. Outlines serve readability; they must never make creatures cute.
3. **Detailed but legible at game zoom.** A creature must be identifiable by silhouette alone at 48–64 px.
4. **Coherence over spectacle.** One palette, one light direction (top-left), one outline weight per asset class.

## Factions

| Faction | Identity | Shapes & materials | Palette accents |
|---|---|---|---|
| Humans (The Aldmere Concord) | Hardened, scarred veterans in heavy, dented plate; grim, not heroic-shiny | Rectangular shields, tall pikes, layered plate, worn tabards, stone citadels with slate roofs | Steel grey, deep navy, tarnished gold, candle orange |
| Demons (The Ashen Host) | Monstrous, brutal, distinctly inhuman: wrong proportions, horns, exposed musculature, cracked magma skin | Jagged spikes, asymmetric silhouettes, obsidian and chain, lava seams | Charcoal black, ember orange, blood red, sulfur yellow |
| Undead (planned) | Genuinely horrifying: decaying bodies, unnatural anatomy, too many joints, ghost-green rot light | Thin elongated limbs, ragged cloth, exposed bone, bent spires | Bone ivory, bruise purple, sickly green |
| Wilds (neutrals) | Feral, territorial, believable fauna twisted by the land | Organic, low and wide | Moss, bark, stone |

## Adventure map

- Top-down-ish 3/4 view, terrain readable at a glance; each terrain type has a distinct value and hue range so
  movement cost is visible without hovering.
- Terrain transitions are blended (autotile / terrain sets), never hard grid seams.
- Fog of war is a dark smoky shroud with soft edges.
- Roads are worn dirt or cobble, rivers glint; infernal regions glow from below.

## UI

- Dark wood/iron panels with tarnished brass borders, parchment-coloured text, serif display font for titles.
- Numbers (resources, stack counts, losses) always high-contrast; losses in red, gains in gold/green.
- UI frames must stay original: no reuse of known game UI layouts or ornaments.

## Production rules

- Every asset has a spec entry (id, size, palette, pose, outline weight) in `assets/specs/` before generation.
- AI-generated images are post-processed: background removal, palette quantisation to the faction palette,
  resize to target grid with nearest-neighbour, outline pass, then validation (size, transparency, palette).
- Pipeline and formats: [`tools/assets/README.md`](../tools/assets/README.md). Native grids: map tiles 40 px,
  creatures and heroes 64 px, towns 96×80, decorations 48×64, all drawn 1:1 on the map. Resource pickups and the
  chest are 32 px, mines 64×56, encounter sites 64×64, also 1:1 (sheet: `docs/art/objects_64.png`).
  Creatures: grim proportions, no chibi heads; demons asymmetric and inhuman (no big round eyes or mouths);
  humans in dented, scarred plate. Reference sheet: `docs/art/creatures_64.png`. One master palette (`assets/specs/palette.json`), 1 px outline `#120d0b`.
- The first set (2026-11) is hand-authored pixel art, all on the master palette: every creature (each upgrade
  has its own drawing, sheets `docs/art/upgrades_64.png` and `docs/art/upgrades_t1_5_64.png`), map decorations
  and UI frames (`docs/art/deco_ui_64.png`). Ground tiles, fog and roads are hand-drawn too (`assets/specs/pixel/terrain/`); only the transition cut-outs and fog edge alpha are computed from them. AI-generated replacements go through the same post-processing and validation; regenerate a
  whole faction at once so a set stays coherent.
