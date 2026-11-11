# Reference image prompts for the remaining 3D units

Status: **Final, Nov 10 11:52.** All round-2 batches have reported. The Frostmarch and Forge riders are fine (the missing legs were a camera crop) and need no image.

## How to use this

1. In ChatGPT (or any image generator), paste **one unit block** per image. Each block is complete on its own: the shared style rules are already inside.
2. **Attach the unit's drawn sprite** with the prompt, so the model keeps the look and only changes the pose. The sprites are in your clone at
   `assets/source/generated/creature_<id>.png`.
3. Save each result as `<id>.png` (for example `tusk_rider.png`), at least 1024 px, and put them in `3d-ref/<id>.png`.
4. Before you keep an image, check the five things Tripo needs (from round 1 and 2):
   - the whole body is in frame, feet or tail tip included;
   - the pose is upright and open: limbs apart, gaps between arms and body, between the legs, between wings and body;
   - the weapon is held clear of the body, in the **right** hand (shield on the left arm);
   - nothing hangs over the legs (no long cape, robe, fur or banner cloth);
   - plain flat background, no smoke, sparks, breath or magic effects floating loose.

Effects that float free (smoke plumes, breath, sparks, spell glows) get fused into the mesh as solid lumps. Riders are not on this list: their missing legs were a camera crop, fixed in the bake.

Glow *on* the body (eyes, cracks, furnace ports) is fine.

## Units that need an image

| # | id | Unit | Why it needs one | Rig |
|---|---|---|---|---|
| 1 | winter_wyrm | Winter Wyrm (Frostmarch) | sprite is coiled | serpentine |
| 2 | winter_wyrm_ancient | Ancient Winter Wyrm (Frostmarch) | coiled, breath effect | serpentine |
| 3 | furnace_golem | Furnace Golem (Forge) | rig twisted twice: no head, arms on body | biped |
| 4 | de_knifedancer | Knifedancer (Darkelf) | crouched pose | biped (dual-blade class later) |
| 5 | de_blood_scythe | Blood Scythe (Darkelf) | crouched pose | biped (dual-blade class later) |
| 6 | fm_coil_serpent | Coil Serpent (Fishmen) | coiled | serpentine |
| 7 | fm_storm_leviathan | Storm Leviathan (Fishmen) | coiled | serpentine |
| 8 | fm_barnacle_bulwark | Barnacle Bulwark (Fishmen) | rig broken: shield hides the legs | biped |
| 9 | wailing_shade | Wailing Shade (Hollow) | legless, needs a float class | biped (float class later) |
| 10 | dirge_shade | Dirge Shade (Hollow) | legless, needs a float class | biped (float class later) |
| 11 | crag_slinger | Crag Slinger (wild) | crouched | biped |
| 12 | road_cutthroat | Road Cutthroat (wild) | crouched | biped |
| 13 | marsh_hag | Marsh Hag (wild) | hunched, robe over legs | biped |
| 14 | rime_wight | Rime Wight (wild) | hunched | biped |
| 15 | cinder_wraith | Cinder Wraith (wild) | floating, no legs | biped (float class later) |
| 16 | hill_giant | Hill Giant (wild) | small cropped sprite made a fur hump | biped |
| 17 | moss_creeper | Moss Creeper (wild) | shapeless mat | serpentine |
| 18 | bog_serpent | Bog Serpent (wild) | coiled | serpentine |
| 19 | dune_wurm | Dune Wurm (wild) | coiled, half in sand | serpentine |
| 20 | primordial_wyrm | Primordial Wyrm (wild) | coiled body, folded wings | avian |
| 21 | ancient_dragon | Ancient Dragon, Karzhaloth (boss) | coiled body, folded wings | avian |

Optional retries (the current model works but is weak):

| id | Unit | Problem |
|---|---|---|
| forge_thrall | Forge Thrall (Forge) | attack smears: the coat is skinned to the left arm |
| fm_abyss_sovereign | Abyss Sovereign (Fishmen) | robe makes the rig tumble |
| ashscale_basilisk | Ashscale Basilisk (wild) | tail renders as a slab |
| cinderling | Cinderling (Ashen) | spindly crawler, rig mislabels the spine; stays drawn until it gets its own rig |
| rootbinder_elder | Rootbinder Elder (Thornwood) | root ring around the robe tears in the clips |
| molten_engine, worldforge_engine | Forge tier 8 | never converted (skip list); possible as a walking brute without its crew |

Not listed on purpose: swarms (Plague Rats, Carrion Flock, Tomb Scarabs, Lost Pilgrims, Deserter Crossbows), Corpse Light, the two bombards (crewed cannons), and the spiders and crabs (their models are clean; they need a many-legged rig, not a new image). Harpy and Wyvern also stay out: their models are fine and the wing problem is in the rig, which the pipeline thread is fixing.

---

## Frostmarch

### 1. winter_wyrm
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body, the whole length in frame with a small margin, tail tip included. Plain flat light grey background, no ground, no shadow, no text, no scenery, no snow, breath or particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: side view, facing right. The body is NOT coiled: it lies stretched out along the ground in one long shallow S-curve, about six times longer than it is tall, with no part of the body crossing, touching or overlapping another part. The front third rises gently so the head is held forward at shoulder height, jaws slightly open. The tail tapers to a point at the far left.

Subject: Winter Wyrm, a huge wingless and limbless ice serpent that bores through glaciers. Pale blue-white overlapping scales, a ridge of short frost-crystal spikes along the spine (short, so the silhouette stays clean), a long horned reptile head with icy fangs. Colours: frost white, pale ice blue, grey-blue shadows.
```

### 2. winter_wyrm_ancient
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body, the whole length in frame with a small margin, tail tip included. Plain flat light grey background, no ground, no shadow, no text, no scenery, no snow, breath or particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: side view, facing right. The body is NOT coiled: it lies stretched out along the ground in one long shallow S-curve, about six times longer than it is tall, with no part of the body crossing, touching or overlapping another part. The front third rises gently so the head is held forward at shoulder height, jaws open, but no breath coming out. The tail tapers to a point at the far left.

Subject: Ancient Winter Wyrm, an older and larger wingless, limbless ice serpent. Thick armour of jagged glacier-blue ice crystal plates along its back, a crown of ice horns, a heavy jaw with long icy fangs, a faint cold-blue glow inside the open mouth. Crystal plates stay close to the body, no long loose shards. Colours: glacier blue, frost white, deep ice blue.
```

## Forge

### 3. furnace_golem
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks or flames floating free. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body, hands as open fists.

Subject: Furnace Golem, a towering walking furnace of riveted bronze-brown iron plates. It must have a clear distinct head: a small armoured helm-like head sitting between the shoulders, with a glowing slit visor. A round furnace grate in the chest glows orange, and glowing orange seams show at the joints. Two short chimney stacks rise from the back of the shoulders (behind the head, not above the arms). Thick armoured arms and legs with plated knees and big fists. Colours: dark iron, tarnished brass rivets, rust brown, orange furnace glow.
```

## Darkelf

### 4. de_knifedancer
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright and tall, NOT crouched: feet apart at shoulder width, legs straight and clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. A curved dagger in each hand, blades pointing down and outward, away from the legs.

Subject: Knifedancer, an athletic slender dark elf assassin with long pale silver-white hair tied back, a violet cloth mask over the lower face, fitted black leather and dark lacquered armour, a short violet sash at the waist that ends above the knees. Colours: black, deep violet, purple accents, pale grey skin, silver blades.
```

### 5. de_blood_scythe
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright and tall, NOT crouched: feet apart at shoulder width, legs straight and clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. A long curved sickle blade in each hand, blades pointing down and outward, away from the legs.

Subject: Blood Scythe, an elite dark elf assassin with long pale silver-white hair, a severe silver death mask, layered spiked black shoulder armour, fitted dark lacquered armour with violet trim, short violet cloth strips at the waist ending above the knees. Colours: black, deep violet, silver mask and blades, dark red edge on the blades.
```

## Fishmen

### 6. fm_coil_serpent
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body, the whole length in frame with a small margin, tail tip included. Plain flat light grey background, no ground, no water, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: side view, facing right. The body is NOT coiled: it lies stretched out along the ground in one long shallow S-curve, about five times longer than it is tall, with no part of the body crossing, touching or overlapping another part. The two clawed forelimbs are planted on the ground under the raised front of the body, apart from each other. Head held forward, jaws slightly open. The finned tail tapers out at the far left.

Subject: Coil Serpent, an amphibious sea serpent with broad toothy jaws, webbed dorsal fins along the back, two clawed forelimbs and a long scaly body. Colours: dark sea green and teal scales, pale cream belly, coral-pink fin membranes.
```

### 7. fm_storm_leviathan
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body, the whole length in frame with a small margin, tail tip included. Plain flat light grey background, no ground, no water, no shadow, no text, no scenery, no lightning or particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: side view, facing right. The body is NOT coiled: it lies stretched out along the ground in one long shallow S-curve, about five times longer than it is tall, with no part of the body crossing, touching or overlapping another part. The two clawed forelimbs are planted on the ground under the raised front of the body, apart from each other. Head held forward, jaws open. The finned tail tapers out at the far left.

Subject: Storm Leviathan, a massive royal sea serpent: crown of ivory spines on the head, armoured scale ridges along the back, short coral growths on the shoulders, a cyan glow inside the throat, two clawed forelimbs. Colours: deep teal and dark green scales, ivory spines, coral red, cyan glow.
```

### 8. fm_barnacle_bulwark
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright: feet apart at shoulder width, legs straight and clearly separated and fully visible. Left arm holds a large shell shield out to the side, away from the body, so the shield does NOT cover the torso or legs. Right arm hangs down about 35 degrees from the body holding a bronze hooked cleaver pointing down, clear of the leg.

Subject: Barnacle Bulwark, a stocky armoured fish man with a wide toothy fish head and fin crest, hulking barnacle-encrusted shell armour on the shoulders and chest, a big oval ribbed shell shield, webbed clawed feet. Small coral growths on the back. Colours: sea green skin, bone and cream shell, coral red, bronze.
```

## Hollow

The shades have no legs in the sprites. For the rigger they need two leg-like trails, so the prompts below split the robe into two separate tails. A float animation class is still needed in the pipeline.

### 9. wailing_shade
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no mist, smoke or particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right, hovering upright just above the ground. Head and shoulders upright, both arms held out and down about 40 degrees from the torso with a clear gap between each arm and the body, long bony fingers spread. Below the waist the tattered robe splits into two separate long trailing tails, like two legs, slightly apart and not touching each other.

Subject: Wailing Shade, the ghost of a grieving woman: a deep hood over a dark gaunt face, a tattered shroud of dusky violet fading to moss green at the ragged edges, skeletal grey hands. The rags stay close to the body, no long loose streamers. Colours: dusky violet, grey-green, bone grey.
```

### 10. dirge_shade
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no mist, smoke or particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right, hovering upright just above the ground. Head and shoulders upright, both arms held out and down about 40 degrees from the torso with a clear gap between each arm and the body, long bony fingers spread. Below the waist the tattered robe splits into two separate long trailing tails, like two legs, slightly apart and not touching each other.

Subject: Dirge Shade, a larger mourning spirit: a deep hood crowned with a thorny iron ring halo fixed to the back of the hood, small iron funeral bells hanging from the shoulders on short chains, a tattered shroud of violet and moss green. The rags stay close to the body, no long loose streamers. Colours: violet, moss green, rusted iron, bone grey.
```

## Wild creatures

### 11. crag_slinger
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright, NOT crouched: feet apart at shoulder width, legs straight and clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. The right hand holds a leather sling hanging down with a stone in its pouch, clear of the leg.

Subject: Crag Slinger, a wiry, gaunt hill-folk ambusher with a ragged hood, patched hide tunic in rock-grey and moss tones ending above the knee, a stone pouch on the belt, wrapped forearms and worn boots. Colours: stone grey, mossy green, dirty brown leather.
```

### 12. road_cutthroat
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright, NOT crouched: feet apart at shoulder width, legs straight and clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. The right hand holds a long knife or short sword pointing down and outward, clear of the leg.

Subject: Road Cutthroat, a scarred human deserter turned highway murderer: a ragged dark red hood and short shoulder cape ending at the waist, a stained leather jerkin over old mail, belts and pouches, worn trousers and boots, a stubbled hard face. Colours: dried-blood red, dark brown leather, dull grey mail.
```

### 13. marsh_hag
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright, NOT hunched: feet apart at shoulder width, legs straight and clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. The right hand holds a gnarled crooked staff vertically at her side, the staff not touching her body. Her ragged skirt ends at the knee so both shins and bare feet show.

Subject: Marsh Hag, a gaunt crone of the reed marshes: long matted grey hair, sickly grey-green skin, a cursing open mouth, a ragged layered shawl of moss and dark violet rags, a small bundle of cattail reeds tied on her back, a little skull charm on the belt and small skulls hanging from the staff head. Colours: muddy violet, moss green, grey skin, brown wood.
```

### 14. rime_wight
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no mist or particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright, NOT hunched: feet apart at shoulder width, legs straight and clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body, long clawed fingers spread.

Subject: Rime Wight, a frozen corpse that walks the mountain passes: gaunt skeletal body with shrunken frost-white skin over the ribs, a hooded rag of frozen grey cloth on the head and shoulders, icicles and frost crust on the limbs (short, close to the body), an open screaming skull-like face with pale blue glowing eyes. Colours: frost white, pale blue-grey, bone.
```

### 15. cinder_wraith
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, embers or particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right, hovering upright just above the ground. Head and shoulders upright, both arms held out and down about 40 degrees from the torso with a clear gap between each arm and the body, clawed charred fingers spread. Below the waist the burnt robe splits into two separate long trailing tails, like two legs, slightly apart and not touching each other.

Subject: Cinder Wraith, the ghost of someone burned alive: a deep charred hood with two glowing orange eyes, a tattered robe of ash-grey and soot-black cloth with glowing orange ember edges, a faint orange glow through the ribs. Glow stays on the body; no loose smoke or flying embers. Colours: soot black, ash grey, ember orange.
```

### 16. hill_giant
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright: feet apart at shoulder width, legs straight and clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. The right hand holds a huge spiked wooden club hanging down and out to the side, the club head next to the right foot and not touching the leg. Left hand empty.

Subject: Hill Giant, a huge brutish giant with a wild tangled brown beard and hair, a heavy brow, a broad bare chest, crude hide wrappings round the waist and legs, a belt hung with small skulls. Any fur on the shoulders is short and lies flat (no big fur cape or hump on the back). Colours: weathered tan skin, brown fur and hide, bone, dark wood club with iron spikes.
```

### 17. moss_creeper
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: side view, facing right. A long low creature lying stretched along the ground in a gentle shallow curve, about four times longer than it is tall, no part folded over another. The front end is a blunt raised head with a mouth ringed by small root tendrils; the back end tapers to a narrow tail.

Subject: Moss Creeper, a crawling slug-shaped mound of living moss and tangled roots, with short hanging moss strands on its sides and a few small pale mushrooms growing on its back. Colours: moss green, yellow-green, dark brown roots, cream mushrooms.
```

### 18. bog_serpent
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body, the whole length in frame with a small margin, tail tip included. Plain flat light grey background, no ground, no water, no grass, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: side view, facing right. The body is NOT coiled: it lies stretched out along the ground in one long shallow S-curve, about six times longer than it is tall, with no part of the body crossing, touching or overlapping another part. The front third rises gently so the head is held forward, jaws open showing fangs. The tail tapers to a point at the far left.

Subject: Bog Serpent, a huge legless marsh snake with dull olive and brown scales, ridges of short spines along the back, strands of hanging moss and a few small fungi on its back, a pale banded belly. Colours: olive green, mud brown, pale yellow belly.
```

### 19. dune_wurm
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body, the whole length in frame with a small margin, tail end included. Plain flat light grey background, no sand, no ground, no shadow, no text, no scenery, no dust or particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: side view, facing right. The whole worm is visible above ground, NOT buried and NOT coiled: it lies stretched out along the ground in one long shallow S-curve, about six times longer than it is tall, with no part crossing or overlapping another. The front end rises gently, and the round mouth faces right, open, ringed with rows of hooked teeth. The back end tapers to a blunt tail at the far left.

Subject: Dune Wurm, a limbless sand worm the length of a caravan, with armoured overlapping segment plates and short backward-pointing spikes along the back. Colours: sand beige, pale ochre, dark brown between the plates, dark red inside the mouth.
```

### 20. primordial_wyrm
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body with a small margin, wing tips and tail tip included. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: three-quarter side view, facing right. Standing on four legs, legs straight and clearly apart. Both wings fully spread, raised up and out to the sides, the wing membranes not touching the body, the head or each other. The neck raised forward, head level, jaws slightly open. The tail stretched straight out behind, not curled and not crossing the legs.

Subject: Primordial Wyrm, an immeasurably old dragon: weathered grey-brown spiked scales, a long horned head with a crown of swept-back horns and spines, ragged leathery wings with torn edges, a spiked tail. Spikes are short so the silhouette stays clean. Colours: ash grey-brown, dull bronze, bone horns, dusky purple wing membranes.
```

### 21. ancient_dragon
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body with a small margin, wing tips and tail tip included. Plain flat light grey background, no ground, no shadow, no text, no scenery, no ash, smoke or particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: three-quarter side view, facing right. Standing on four legs, legs straight and clearly apart. Both wings fully spread, raised up and out to the sides, the wing membranes not touching the body, the head or each other. The neck raised forward, head level, jaws half open. The tail stretched straight out behind, not curled and not crossing the legs.

Subject: Karzhaloth, the ancient dragon under the world, a colossal boss: obsidian-black scales cracked with dim ember-orange seams, wings like torn black silk veined with faint violet-grey light, a long low skull with six empty eye sockets sealed with tarnished silver plates, broken silver chain shackles on the forelegs (short chain ends only). Menace and weight. Colours: obsidian black, ember orange seams, violet-grey, tarnished silver.
```

## Optional retries

### forge_thrall
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright: feet apart at shoulder width, legs straight and clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. The RIGHT hand holds an iron mining pick hanging down and out to the side, the pick head next to the right foot and not touching the leg. Left hand empty.

Subject: Forge Thrall, a stocky bearded dwarf-like deep-clan miner with a riveted leather cap and brass goggles pushed up, a short sleeveless riveted leather work coat that ends above the knee and does not cover the arms, bare muscular forearms with leather bracers, a tool belt with a few keys, heavy boots. Colours: dark brown leather, rust, tarnished brass, grey beard.
```

### fm_abyss_sovereign
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright, NOT hunched: feet apart at shoulder width, legs straight and clearly separated and fully visible, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. The right hand holds a tall coral-headed sceptre vertically at its side, not touching the body. The robe ends above the knees.

Subject: Abyss Sovereign, a towering bipedal deep-sea angler king: huge toothy angler jaws, a glowing cyan lure on a stalk over the head, an enormous shell crown, corroded bronze armour, short coral growths on the back, two massive clawed arms. Colours: dark teal and green skin, bronze, bone shell, coral red, cyan lure glow.
```

### ashscale_basilisk
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body with a small margin, tail tip included. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: strict side view (profile), facing right. Standing on four legs, legs straight and clearly apart. Head held forward, jaws slightly open. The long tail is stretched straight out behind and slightly raised, thin and round, tapering to a point, not touching the ground or the hind legs.

Subject: Ashscale Basilisk, a large lizard-like reptile with ash-grey armoured scales, a ridge of short spines along the back and tail, a heavy horned head and clawed feet. Colours: ash grey, charcoal, pale bone spines, dull yellow eyes.
```

### cinderling
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, full body with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no sparks or particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: strict side view (profile), facing right. Standing on four legs, legs straight and clearly apart, body level, head forward, a short tail straight behind.

Subject: Cinderling, a small gaunt imp-like fire creature with a spiky ridged back, thin clawed limbs, a narrow fanged head, cracked dark red skin with glowing molten orange cracks. Colours: dark red, charcoal, molten orange glow.
```

### molten_engine
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke or sparks. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright on two thick armoured legs, feet apart, legs clearly separated. Two arms held down and away from the body with a clear gap: the right arm is a riveted crane arm holding a glowing crucible on a short chain, the left arm a thick piston arm with a clamp hand. No crew riding on it.

Subject: Molten Engine, a walking foundry of riveted dark iron and brass plates, with a glowing furnace door in the chest, short chimney stacks on its back (no smoke), and a small armoured head housing between the shoulders. Colours: dark iron, tarnished brass, orange glow.
```

### worldforge_engine
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke or sparks. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright on two thick armoured legs, feet apart, legs clearly separated. Two arms held down and away from the body with a clear gap: the right arm ends in a huge glowing forge hammer head, the left arm a thick piston arm with a clamp hand. No crew riding on it.

Subject: Worldforge Engine, a bigger walking foundry: heavier riveted dark iron plates with brass trim, a large glowing furnace door in the chest, short chimney stacks on its back (no smoke), a small armoured head housing between the shoulders, and dark banners as short plates on the hips. Colours: dark iron, brass gold, orange glow.
```

## Thornwood

All 16 Thornwood units modeled cleanly from their sprites. Only one would benefit from a new image.

### rootbinder_elder (optional)
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright: feet apart at shoulder width, legs clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. The right hand holds a tall gnarled root staff with a glowing green orb in its twisted head, vertical at his side, not touching the body. The robe ends at the ankles and both feet are visible. No ring of roots on the ground around him.

Subject: Rootbinder Elder, an old forest druid with a long grey beard, a deep hood, a crown of small bare branches, and a layered robe of moss, leaves and bark strips with a few small shelf mushrooms. Colours: moss green, bark brown, grey beard, glowing yellow-green orb.
```
