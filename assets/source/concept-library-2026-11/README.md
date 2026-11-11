# Reignem source art library

Generated 2026-11-07 with the built-in ChatGPT image generator. Original generated images are retained at full resolution. The five campaign opening images have since been integrated into the game; the remaining source material requires production and review.

## Contents

- `towns/`: five empty, faction-specific town foundations, designed for separate building layers.
- `buildings/`: two nine-subject source sheets for each missing town faction. The subjects were prompted from that faction's building roster; the generated cells are concepts, not verified one-to-one matches for building IDs. Inspect boundaries, transparency, silhouettes and naming before extraction.
- `campaigns/`: one full-resolution opening-chapter image and one nine-scene storyboard for each of the five campaigns beyond Last Light. The opening images are used in their first chapter and as campaign covers. The storyboards are reference material for chapters 2–10, not full-resolution individual chapter illustrations.
- `palettes/`: reusable terrain surfaces, adventure locations and hero equipment concepts. Terrain samples are not seamless tiles; the other sheets require extraction and review.

## Generation direction

All images were prompted as original dark medieval fantasy for Reignem: gritty hand-painted, slightly pixelated detail, weathered materials, muted colours, top-left light and clear silhouettes. Foundations use an elevated three-quarter view and open building areas; building sheets request isolated objects on transparent backgrounds. Campaign scenes follow the corresponding chapter introductions in `data/campaigns.json`; storyboards use the remaining chapter situations in reading order. Equipment subjects include a falchion, bow, helm, cuirass, shield, greaves, dice, hourglass and pennant. Location concepts include a watchtower, bridge, shrine, mill, gate, mine, well, standing stones and camp.

## Production work still needed

Building sheets need individual crops, alpha and edge cleanup, identity review, sizing, faction layouts and manifest entries. Some requested buildings remain unrepresented, and generated objects may not precisely match their named prompt. The campaign storyboards are compositional references; create and review full-resolution chapter-specific illustrations for all remaining chapters. Town foundations need story, composition and in-engine review. The opening illustrations are integrated but remain pending visual review. Terrain samples need seamless tile production and transition testing. The campaign opening images are built into the runtime illustration assets; the other sources are not automatically loaded by Godot.
