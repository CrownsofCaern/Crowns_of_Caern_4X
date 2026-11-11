# Credits and third-party notices

Crowns of Caern is made by the Crowns of Caern contributors. The project's own work is released under the
MIT licence in [LICENSE](LICENSE). The material below comes from third parties and keeps its own licence or
terms; the MIT licence does not apply to it.

Detailed per-file records: [assets/LICENSES_3D.md](assets/LICENSES_3D.md) (3D battlefield assets) and
[assets/audio/LICENSES.md](assets/audio/LICENSES.md) (audio).

## Engine

**Godot Engine** 4.5, https://godotengine.org. MIT licence, Copyright (c) 2014-present Godot Engine
contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

The engine is not part of this repository. Any exported build of the game contains the engine and must ship
Godot's licence notice and the notices of the third-party libraries compiled into it (FreeType, ENet, mbedTLS
and others). The full text is in Godot's `COPYRIGHT.txt` and `LICENSE.txt`, at
https://godotengine.org/license, and is available at run time from `Engine.get_license_text()` and
`Engine.get_copyright_info()`.

## Fonts

| Font | Files | Copyright | Licence |
|---|---|---|---|
| Cinzel | `assets/fonts/Cinzel.ttf` | Copyright 2020 The Cinzel Project Authors (https://github.com/NDISCOVER/Cinzel) | SIL Open Font License 1.1, full text in `assets/fonts/Cinzel-OFL.txt` |
| Lora | `assets/fonts/Lora.ttf` | Copyright 2011 The Lora Project Authors (https://github.com/cyrealtype/Lora-Cyrillic), Reserved Font Name "Lora" | SIL Open Font License 1.1, full text in `assets/fonts/Lora-OFL.txt` |

The OFL texts must stay next to the fonts, including in exported builds' distribution. A modified Lora may not
be called "Lora".

## Textures and 3D scenery (CC0)

No attribution is required for CC0 material; it is listed for the record.

| Files | Source | Licence |
|---|---|---|
| `assets/terrain3d/ground037_*`, `assets/terrain3d/rock023_*` | ambientCG, Ground037 and Rock023 (https://ambientcg.com), as packed in the Terrain3D demo (https://github.com/TokisanGames/Terrain3D) | CC0 1.0 |
| `assets/nature/*.glb` | Quaternius, "Ultimate Stylized Nature" (https://quaternius.com), via https://github.com/walterpalladino/godot-quaternius-ultimate-stylized-nature; textures reduced and retinted | CC0 1.0 |

## Character animation (Adobe Mixamo)

The animation clips of the humanoid 3D battle units in `assets/units3d/*.glb` (105 of the 166 files; the
units whose clips in `assets/specs/creature_models.json` point at `*_mx_*.glb`) were retargeted from Adobe
Mixamo animations (https://www.mixamo.com) onto the project's own models, then cut and resampled. The sprite
frames rendered from them (in `assets/atlases/`) are derived from the same clips.

Mixamo animations are used under Adobe's terms for Mixamo, which allow their use in games and other projects
but not their redistribution as standalone animation files. **They are not covered by the MIT licence.** You
may use them as part of this game, but you may not extract the animation data from these files and reuse or
redistribute it on its own. The original Mixamo FBX files are not in this repository; the tools that
retarget them (`tools/assets/mixamo_set.py`, `tools/assets/retarget_mixamo.gd`) expect you to download your
own copies from Mixamo.

## Generated artwork and models

These were produced for the project with generative tools and are treated as the project's own work under
the MIT licence. Records of each file's prompt, source and hashes are kept beside it (for example
`assets/source/generated/*.json`, `assets/inventory.json`, `3d-ref/prompts.json`).

| Material | Tool |
|---|---|
| 2D artwork: creatures, heroes, towns, terrain, map scenery, illustrations, menus, emblems, icons and their source sheets (`assets/source/`, `assets/atlases/` and the folders built from them) | OpenAI image generation (ChatGPT image_gen) |
| 3D unit meshes, textures and rigs (`assets/units3d/`, built from `assets/source/models/`) | Tripo AI (https://www.tripo3d.ai), from the project's own reference art (`3d-ref/`) |
| A few UI icons (`provider: "project owner"` in their records) | Made by the project |

## Audio

Every sound and music file under `assets/audio/` is synthesized from code by `tools/audio/synth.py`. No
samples or third-party recordings are used; it is the project's own work under the MIT licence.

## Build-time tools

These are used by the asset and audio pipelines on a developer's machine. None of them is shipped with the
game or included in this repository.

| Tool | Use | Licence |
|---|---|---|
| Pillow | image processing (`tools/`) | MIT-CMU (HPND) |
| NumPy | audio synthesis, image processing | BSD 3-Clause |
| rembg (optional, with the U²-Net model) | background removal of generated art | MIT; U²-Net weights Apache 2.0 |
| FFmpeg with libvorbis | encoding OGG Vorbis | LGPL/GPL (FFmpeg), BSD (libvorbis); only the encoded output is kept |
