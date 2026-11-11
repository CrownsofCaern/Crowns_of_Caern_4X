# Ultimate creature treatment

The original six styles are joined by amethyst eclipse highlights for the
dark elves and cyan tidal caustics for the fish men. All eight materials use
the same still/animation path and preserve the source sprite alpha.

Every creature of a faction whose ultimate building (an `army_upgrade` building, e.g. the Concord Reliquary of
Holy Arms) its owner has built fights upgraded, and its sprite shows it. `ultimate_creature.gdshader` reuses the
existing creature image: a subtle faction-coloured highlight, a glowing rim on the sprite's own edge
pixels, and a small animated accent per faction (holy glint, rising embers, deathly pulse, sap veins, kindling
runes, frost twinkles). It keeps the original alpha and dark outline and never rewrites an atlas.
`UltimateCreatureArt.material_for(faction)` returns the (shared) material for each of the eight playable factions;
unknown factions return null.

It is wired in two places: `BattleFigure` (live battle, from the battle result's per-stack `ultimate` field) and
`ArmySlot.with_ultimate()` (army strips in the HUD, hero screen and town, via
`UltimateCreatureArt.faction_if_upgraded`). Never apply it to the count badge or the slot frame; fallen battle
figures drop it.

The shader samples the active texture, so the same material works on still sprites and on the move/attack strips
described in `assets/animations/README.md`.
