# Third-party assets of the 3D battlefield

All are CC0 (public domain); no attribution is required, it is kept for our records.

| Files | Source | Licence |
|---|---|---|
| `assets/terrain3d/ground037_*`, `assets/terrain3d/rock023_*` | ambientCG Ground037 and Rock023, as packed (albedo+height, normal+roughness) in the Terrain3D demo (github.com/TokisanGames/Terrain3D) | CC0 1.0 (https://docs.ambientcg.com/license/) |
| `assets/nature/*.glb` | Quaternius "Ultimate Stylized Nature" pack, via github.com/walterpalladino/godot-quaternius-ultimate-stylized-nature; converted to 512 px textures with darker tints | CC0 1.0 |

The 3D unit models in `assets/units3d/` are the project's own (Tripo models from our reference art,
exported by `tools/assets/export_live_units.gd`). The animation clips of 105 of them (the humanoid units
whose spec clips are `*_mx_*.glb`) are retargeted from Adobe Mixamo animations: usable in the game under
Adobe's Mixamo terms, not covered by the MIT licence, and not to be extracted or redistributed on their own.
See [CREDITS.md](../CREDITS.md).
