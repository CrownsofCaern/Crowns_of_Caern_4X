# Standalone DLC faction art review

The Umbral Court (dark elves) and Abyssal Shoal (fish men). Native-scale candidates; gameplay activation is separate and the main campaigns are untouched.

[Developer handoff](../../DLC_FACTIONS_REPORT.md) · [Original source overview](source-contact.jpg)

## The Umbral Court

[Creature contact sheet](darkelf-creatures.png) · [All 30 buildings](darkelf-buildings.png) · [Heroes, towns and icons](darkelf-heroes-towns.png)

[Creature movement loop](darkelf-creatures-move.gif) · [Creature attacks](darkelf-creatures-attack.gif) · [Hero movement](darkelf-heroes-move.gif)

| Tier | Base | Upgrade |
|---|---|---|
| 1 | Gloam Spear (`de_gloam_spear`) | Dusk Sentinel (`de_dusk_sentinel`) |
| 2 | Shardbow (`de_shardbow`) | Venom Arbalist (`de_venom_arbalist`) |
| 3 | Knifedancer (`de_knifedancer`) | Blood Scythe (`de_blood_scythe`) |
| 4 | Cave Lancer (`de_cave_lancer`) | Dread Rider (`de_dread_rider`) |
| 5 | Veil Adept (`de_veil_adept`) | Mirror Witch (`de_mirror_witch`) |
| 6 | Silk Stalker (`de_silk_stalker`) | Widow Matriarch (`de_widow_matriarch`) |
| 7 | Obsidian Guard (`de_obsidian_guard`) | Onyx Executioner (`de_onyx_executioner`) |
| 8 | Gloam Drake (`de_gloam_drake`) | Eclipse Dragon (`de_eclipse_dragon`) |

Hero classes: Dreadmarshal (`de_dreadmarshal`), Veilseer (`de_veilseer`), Nightstalker (`de_nightstalker`).

Godot: [idle](darkelf-creatures-idle-godot.png), [walking](darkelf-creatures-move-godot.png), [attacking](darkelf-creatures-attack-godot.png).

Town construction: [stage 1](darkelf-town-stage-1-godot.png), [stage 2](darkelf-town-stage-2-godot.png), [stage 3](darkelf-town-stage-3-godot.png), [stage 4](darkelf-town-stage-4-godot.png).

## The Abyssal Shoal

[Creature contact sheet](fishmen-creatures.png) · [All 30 buildings](fishmen-buildings.png) · [Heroes, towns and icons](fishmen-heroes-towns.png)

[Creature movement loop](fishmen-creatures-move.gif) · [Creature attacks](fishmen-creatures-attack.gif) · [Hero movement](fishmen-heroes-move.gif)

| Tier | Base | Upgrade |
|---|---|---|
| 1 | Brine Spear (`fm_brine_spear`) | Reef Guard (`fm_reef_guard`) |
| 2 | Hookcaster (`fm_hookcaster`) | Abyss Harpooner (`fm_abyss_harpooner`) |
| 3 | Shellback (`fm_shellback`) | Barnacle Bulwark (`fm_barnacle_bulwark`) |
| 4 | Mire Crab (`fm_mire_crab`) | Siege Carapace (`fm_siege_carapace`) |
| 5 | Lantern Acolyte (`fm_lantern_acolyte`) | Drowned Oracle (`fm_drowned_oracle`) |
| 6 | Tide Mauler (`fm_tide_mauler`) | Trench Reaver (`fm_trench_reaver`) |
| 7 | Coil Serpent (`fm_coil_serpent`) | Storm Leviathan (`fm_storm_leviathan`) |
| 8 | Trench Titan (`fm_trench_titan`) | Abyss Sovereign (`fm_abyss_sovereign`) |

Hero classes: Tidemarshal (`fm_tidemarshal`), Deep Oracle (`fm_deep_oracle`), Reef Hunter (`fm_reef_hunter`).

Godot: [idle](fishmen-creatures-idle-godot.png), [walking](fishmen-creatures-move-godot.png), [attacking](fishmen-creatures-attack-godot.png).

Town construction: [stage 1](fishmen-town-stage-1-godot.png), [stage 2](fishmen-town-stage-2-godot.png), [stage 3](fishmen-town-stage-3-godot.png), [stage 4](fishmen-town-stage-4-godot.png).

## Review limits

32 creatures, 64 creature clips, six hero sprites/gaits, 60 building layers, eight map-town stages, two foundations, eight icons/cursor designs and six map props. The 120 static atlas sprites and 248 new action poses preserve high-resolution sources and conditioning references.

Four-frame movement and three-pose attacks plus rest are first-pass animations. More in-between poses, dedicated idle/hit/death clips and projectiles remain separate work. The cursor is artwork without automatic context/hotspot activation. These packs contain no gameplay stats, balance or campaign links.
