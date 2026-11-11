# Ultimate building artwork — historical five-faction source batch

Generated with the built-in imagegen tool, using the existing Concord Reliquary
as the rendering reference and each faction's existing adventure-map town as the
architectural reference. This reuses the established materials, shapes, colours
and perspective rather than defining a new art style.

Each faction folder retains `source.png` at full generated resolution and the
exact `prompt.txt`. `assets/specs/ultimate_buildings.json` records source hashes,
export names and sizes. Run `python3 assets/source/batches/ultimate-buildings-002/export.py`
from any directory to reproduce the five alpha-cropped 350-pixel exports (Pillow
required). Alpha is preserved, including the Frostmarch chimney smoke.

| Building | Final PNG in `assets/source/generated/` |
| --- | --- |
| Brand-Pit of the Abyss | `town_ashen_a_ultimate.png` |
| The Undying Choir | `town_hollow_h_ultimate.png` |
| Heart of the Mother Tree | `town_thornwood_t_ultimate.png` |
| The Deep King's Anvil | `town_forge_f_ultimate.png` |
| Hall of the Endless Feast | `town_frostmarch_r_ultimate.png` |

Concord's earlier `town_concord_c_ultimate.png` remains unchanged. The complete
six-building review sheet is `docs/art/ultimate_buildings.png`.

These layers are now integrated into the eight-faction ultimate-building set.
See `docs/art/ULTIMATE_BUILDINGS_REPORT.md` for current gameplay bindings,
validation and Godot captures. `python tools/assets/pipeline.py stage-ultimate`
is the current preparation command; this batch's `export.py` delegates to it.
The earlier reviewed 350px exports are frozen alongside the originals to
preserve their exact appearance across Pillow versions. The missing external
proposal file was not used: the original descriptions followed the six
building names/effects and faction direction provided in the task.
