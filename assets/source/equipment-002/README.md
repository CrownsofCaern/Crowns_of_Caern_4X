# Equipment expansion 002

112 original weapon and gear artwork designs for Crowns of Cinder (generated under the Crowns of Caern working title), generated with the built-in ChatGPT image generator on 2026-11-10. Each design is a separate generation using the existing artifact painting as a style reference; these are not recoloured copies.

The catalog contains 28 minor, 28 major, 28 relic and 28 legendary designs. Across those qualities it includes 32 weapons, 16 armor pieces, 12 helms, 12 shields, 12 pairs of boots, 16 charms and 12 banners. Each quality has its own contact sheet; `contact-sheet.jpg` shows all designs at 128 px and `contact-sheet-64.jpg` shows the inventory exports at native size.

Legendary items use distinct geometry plus concentrated elemental highlights: emerald poison, orange fire, cyan frost, blue lightning, violet void/starlight, crimson blood and amber sunlight. Weathered dark metal, tarnished brass, leather and cloth preserve the existing art direction. Relics use subtler magical accents; minor equipment stays utilitarian.

## Files and rebuilding

- Full-resolution transparent original paintings: this directory, one named PNG per item.
- Authoritative design specification and exact prompt set: `assets/specs/batches/equipment-002.json`.
- Delivery manifest, image hashes, export paths and validation counts: `manifest.json` and `validation.json` in this directory.
- Centered, outlined transparent exports: `assets/equipment/expansion_002/64/` and `assets/equipment/expansion_002/128/`.
- Rebuild with `python3 tools/assets/build_equipment_expansion.py` using Python with Pillow and numpy. The builder rejects missing sources, duplicate IDs, IDs already used by the current gameplay artifacts, exact duplicate paintings and missing transparency. It uses the existing sprite postprocessor and retains generated material colors and elemental highlights.

This is an artwork library. The designs have no gameplay stats and are not added to random loot tables or equipped by heroes. `legendary` is an art quality in this catalog; the existing gameplay rarity enum remains unchanged. The complete native-size contact sheet and the legendary review sheet were visually inspected after export. All 112 sources passed transparency and uniqueness checks; all 224 exports passed size, RGBA and binary-alpha checks. The existing artifact builder unit test passed. In-engine review remains part of future gameplay integration.
