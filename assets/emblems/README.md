# Detailed faction heraldry

`factions_detailed.png` is the original approved direction sheet recovered from
`codex/fishmen-dark-elves`, previously archived at
`assets/source/faction_emblem_concepts/approved-direction.png`.

The source is preserved without resampling. The eight `.tres` AtlasTexture resources expose each
cell through `Art.faction_emblem()`; UI controls scale it with linear filtering. Faction
pickers use a separate 28-pixel Lanczos thumbnail so dropdown rows remain compact.
The dark background belongs to the approved artwork.

Reading order: Concord, Ashen, Hollow, Thornwood; Forge, Frostmarch, Umbral Court,
Abyssal Shoal. All eight emblems map to the existing playable factions.
