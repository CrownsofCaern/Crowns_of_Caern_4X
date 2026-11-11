# Reference image prompts: the last 20 units without a 3D model

Same procedure as PROMPTS.md: paste one block per image into ChatGPT, attach the unit's drawn sprite
(`assets/source/generated/creature_<id>.png` in your clone), save as `<id>.png` (at least 1024 px)
and upload it. The sprite shows a group; the 3D battle shows several single figures, so each image is
**one individual**.

## The 20 units and what each needs

| Group | Units | Image needed | Tripo credits (est.) |
|---|---|---|---|
| A. Modelled and animated, held back for pose fixes | forge_thrall, fm_brine_spear, fm_abyss_sovereign, thorn_skulker, thorn_stalker | No (optional retries for forge_thrall and abyss_sovereign are in PROMPTS.md) | 0 (retries ~70 each) |
| B. Modelled, never rigged (spiders, crabs, beetle) | de_silk_stalker, de_widow_matriarch, fm_mire_crab, fm_siege_carapace, dune_scuttler | No | ~25 each for a rig, ~125 |
| C. New: people | deserter_crossbows, lost_pilgrims | Yes, below | ~70 each, ~140 |
| D. New: engines (no rig; recoil and roll are animated in code) | doom_bombard, thunder_bombard, molten_engine, worldforge_engine | Yes (bombards below; engines in PROMPTS.md) | ~40 each, ~160 (~70 if the engines walk) |
| E. New: small swarm creatures, shown as many little figures | carrion_flock, corpse_light, plague_rats, tomb_scarabs | Yes, below | ~50 each, ~200 |

Total is about **650 credits** for everything, or about 300 for groups C and D only.

## C. People

### deserter_crossbows
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright, NOT crouched: feet apart at shoulder width, legs straight and clearly separated, both arms held down and about 35 degrees away from the torso with a clear gap between each arm and the body. The right hand holds a heavy crossbow by its stock, pointing down and out to the side, clear of the leg.

Subject: Deserter Crossbowman, a hard-bitten human soldier gone outlaw: a torn hood, a stained padded gambeson with a cut-off army tabard, a short brown cloak ending at the waist, a bolt quiver on the hip, wrapped shins and worn boots. Colours: mud brown, faded grey cloth, dull steel.
```

### lost_pilgrims
```
Clean 3D-model reference image for a dark fantasy game unit. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright, slightly stooped but NOT hunched: feet apart at shoulder width, legs clearly separated, both arms held down and away from the torso with a clear gap. The right hand holds a tall gnarled walking staff vertically at its side, not touching the body.

Subject: Lost Pilgrim, a gaunt hollow-eyed human wanderer in a patched hooded robe that ends above the knees, rope belt with a small reliquary, bandaged hands, ragged leggings and sandals. Colours: dirty bone white, ash grey, faded violet.
```

## D. Engines

### doom_bombard
```
Clean 3D-model reference image for a dark fantasy siege engine. One object only, whole engine with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, fire or sparks. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

View: three-quarter side view, barrel pointing right and slightly up. No crew.

Subject: Doom Bombard, a massive short-barrelled mortar of riveted dark iron on a heavy wooden carriage with two big spoked wheels, brass gears and a winch on the side, a stack of iron cannonballs on the carriage. The barrel mouth glows faintly orange inside. Colours: dark iron, oak brown, brass, orange glow.
```

### thunder_bombard
```
Clean 3D-model reference image for a dark fantasy siege engine. One object only, whole engine with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, fire or sparks. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

View: three-quarter side view, barrel pointing right and slightly up. No crew.

Subject: Thunder Bombard, a long-barrelled cannon of dark iron with brass bands on a wooden carriage with two spoked wheels, a gear wheel for aiming and a few iron cannonballs on the carriage. Colours: dark iron, oak brown, brass.
```

## E. Swarm creatures

### carrion_flock
```
Clean 3D-model reference image for a dark fantasy game creature. One bird only, full body with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: side view, facing right, wings spread wide and held out straight from the body (clear gap between wings and body), legs tucked, beak slightly open.

Subject: Carrion Crow, a large ragged black crow with tattered wing feathers, a bare grey neck patch and pale eyes. Colours: black, dark grey, bone.
```

### corpse_light
```
Clean 3D-model reference image for a dark fantasy game creature. One creature only, whole body with a small margin. Plain flat dark grey background, no ground, no shadow, no text, no scenery, no loose particles or smoke. Even soft lighting, clean readable shapes. Square image, 1024 x 1024.

Pose: front view, floating upright.

Subject: Corpse Light, a small ghostly wisp shaped as a solid, smooth teardrop of pale green spirit-stuff with a faint skull face in its head and a short tapering tail below. No loose wisps around it. Colours: pale sickly green, glowing white-green core.
```

### plague_rats
```
Clean 3D-model reference image for a dark fantasy game creature. One rat only, full body with a small margin, tail tip included. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: strict side view (profile), facing right, standing on four legs clearly apart, tail stretched straight out behind and not touching the ground.

Subject: Plague Rat, a big diseased sewer rat with patchy fur, sores and a scarred snout. Colours: dirty pink-grey, brown fur, yellow teeth.
```

### tomb_scarabs
```
Clean 3D-model reference image for a dark fantasy game creature. One beetle only, full body with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no particles. Even soft lighting, matte painted look, clean readable shapes. Wide image, 1536 x 1024.

Pose: three-quarter side view, facing right, standing on six legs spread wide and clearly apart, wing cases closed.

Subject: Tomb Scarab, a dog-sized beetle with a ridged bronze-black shell, horned head and serrated mandibles. Colours: bronze black, dusty brown, dull gold edges.
```

## Referenced walking engine prompts

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
