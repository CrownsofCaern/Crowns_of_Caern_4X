# Tier 2 canine redesign

Built-in image_gen, 2026-11-09. User direction: Scorchhound must look more different from Cinderling; keep the approved final tier.

Scorchhound now has one wolf-like head, pointed ears, a long muzzle, high shoulders, deep ribcage, tucked waist, canine hocks, dog paws and a local fiery neck mane. Hellmaw Hound keeps two distinct heads on one heavier canine body. This replaces the previous low, spiny, claw-armed silhouette that resembled the Cinderlings.

Exact prompts: `prompt-still.txt`, `prompt-A.txt`, `prompt-B.txt`. Raw built-in sources: `source.png`, `hounds-A-source.png`, `hounds-B-source.png`. Animation A contains 3 idle poses and 4 walking poses; B contains 6 attack poses. Reference stills are rendered through the normal sprite pipeline.

`prepare.py` composes the new hound rows beneath the original, unresampled Cinderling rows and records reviewed hashes in the animation specs. It also composes the legacy 4-walk/3-attack fallback using the same new hounds. Run with the asset-pipeline Python dependencies, then run the ordinary pipeline build. Historical source sheets and references stay preserved.

Validation: five animation tests, five idle-pipeline tests and seven battle FX tests pass. Source extraction and registration report zero warnings. Broader baseline asset validation still reports the previously documented campaign-journey and DLC prepared-export failures.

Scope check against the previous push: all 337 non-hound clips remain pixel-for-pixel identical, including both Cinderlings and the approved tier 8 pair. Tier 8 source files and static runtime sprites are byte-for-byte unchanged. Godot reports `ASHEN_ANIMATIONS_OK: 16 creatures, 48 runtime clips`.
