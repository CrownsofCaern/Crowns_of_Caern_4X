# Audio licences

Every file under `assets/audio/` is listed here with its source and licence. Add a row for any file that does
not come from `tools/audio/synth.py`, and verify the licence (CC0 or similarly permissive, no attribution-only
licence without recording the attribution, never non-commercial or no-derivatives) before committing it.

## Synthesized by this project

All files below are rendered from code by `tools/audio/synth.py` (additive and filtered-noise synthesis,
synthetic convolution reverb). No samples, recordings or third-party sound libraries are used, so they are
original works of the Crowns of Caern project (formerly Reignem) and carry the project's own licence. Build tools: numpy (BSD),
ffmpeg with libvorbis (encoder only; nothing from it is shipped beyond the encoded output).

| Files | Source | Licence |
|---|---|---|
| `sfx/*.ogg`, `sfx/faction/*.ogg` (UI, footsteps, pickups, captures, town actions, battle and fight sounds, turn, encounter, level-up, with extra takes and one take per faction for the coloured events) | `tools/audio/synth.py` | Project-owned (original) |
| `music/*.ogg` (menu, map, map_highlands, map_dusk, battle, town_concord, town_ashen, town_default, battle_victory and its faction versions, battle_defeat) | `tools/audio/synth.py` | Project-owned (original) |

## Third-party audio

None yet.

| File | Author | Source URL | Licence | Verified on |
|---|---|---|---|---|
