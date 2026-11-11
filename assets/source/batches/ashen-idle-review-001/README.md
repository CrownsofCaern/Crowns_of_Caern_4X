# Ashen Host idle, walk and attack source sheets

Eight source review candidates: `ashen-01` through `ashen-04`, sheets A and B for each group. Sheet A has three idle and four movement poses (7×4); sheet B has six attack poses (6×4). Every image is a 1536×1024 RGBA PNG generated with the built-in image_gen tool using the supplied four-character reference strip. Exact prompts are in `prompts/`, source strips in `references/`, and the supplied task in `task.md`.

`manifest.json` records hashes, image dimensions, grids, transparency measurements and review notes. Original generated pixels are preserved. RGB colors stored beneath alpha-zero pixels may appear in previews that ignore alpha. The generated alpha contains intermediate values and needs production cleanup.

These are review sources, not approved runtime replacements. Frame continuity needs review for the two-headed hellhound, molten boulder release, hooked forearms, witch staffs, gorgewing wings and jaws, and heavy demon gait. No runtime clips, atlases or approval hashes are changed. Existing production workflow: `assets/specs/creature_idle_animations.json` and `tools/assets/generate_idle_sheets.py`.

Validation: `GODOT=/path/to/Godot ./run_tests.sh test_assets` passed (23 tests, zero failures). Python pipeline checks were skipped by the repository runner because default Python lacks Pillow and NumPy. A separate Pillow environment checks these raw source images for completeness, decoding, 1536×1024 dimensions and alpha transparency.

Runtime integration: ashen-01 through ashen-03 are now activated by reviewed hashes in creature_idle_animations.json. The original ashen-04 candidates are superseded by ashen-maw-remake-001 so the tier 8 redesign retains matching animations.
