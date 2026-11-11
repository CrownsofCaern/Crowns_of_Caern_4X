# Level 5 veteran animation sources

64 creatures across eight factions. Each of the 16 sheets contains four rows of creatures and seven columns: four movement poses, attack wind-up, impact/release, recovery. Names and tier order are recorded in `plan.json`. The ids refer to the improved creature being evolved, not new gameplay creature definitions.

Generated with built-in image_gen from the approved shimmer concept sheets. Prompts are saved per sheet. Original sources are retained; the plan selects revised sources where transparency or mount anatomy needed correction. Source hashes protect the selected inputs.

Stage using Pillow and NumPy with the current asset pipeline:

```sh
python tools/assets/prepare_veteran_animations.py
```

An older checkout can pass `--pipeline-root /path/to/current/checkout` to use the current pipeline's frame extraction and registration. Output is under `assets/build/veteran_animations/`: two transparent 320×256 four-frame strips per creature, a manifest with timing and attack-impact events, eight animated faction GIF previews, and a self-contained `preview.html` viewer with faction/action selection and pause controls. The attack strip's fourth frame is the approved resting pose; movement loops.

The pack is active at veteran level 5. VeteranVisual selects its portraits and action clips using the improved creature id, while base and level 3 forms retain their existing animations. The form is earned through experience and cannot be recruited from a town. Battle results and replay records carry veteran levels so playback selects the same form. Wild creatures without faction artwork retain their original appearance.
