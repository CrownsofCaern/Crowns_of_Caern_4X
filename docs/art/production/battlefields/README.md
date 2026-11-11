# Terrain battlefield review

17 original 1536×1024 scenes, rendered in the actual Godot battle viewer at 1280×800 and the forecast band at 1200×160. Engine-reviewed candidates awaiting artistic review.

[Lead developer report](../../BATTLEFIELD_PRODUCTION_REPORT.md) · [Source contact sheet](contact.jpg) · [Live contact sheet](live-contact.jpg)

| Terrain | Scene | Godot live | Forecast |
|---|---|---|---|
| grass | Windward March | [View](grass_windward-live.png) | [View](grass_windward-forecast.png) |
| grass | The Broken Border | [View](grass_border_ruins-live.png) | [View](grass_border_ruins-forecast.png) |
| forest | Blackpine Clearing | [View](forest_blackpine-live.png) | [View](forest_blackpine-forecast.png) |
| forest | Elderwood Hollow | [View](forest_elderwood-live.png) | [View](forest_elderwood-forecast.png) |
| desert | The Bleached Reach | [View](desert_bone_dunes-live.png) | [View](desert_bone_dunes-forecast.png) |
| desert | Fallen Observatory | [View](desert_fallen_observatory-live.png) | [View](desert_fallen_observatory-forecast.png) |
| snow | The Frozen Pass | [View](snow_frozen_pass-live.png) | [View](snow_frozen_pass-forecast.png) |
| snow | White Reach | [View](snow_white_reach-live.png) | [View](snow_white_reach-forecast.png) |
| swamp | Blackfen | [View](swamp_blackfen-live.png) | [View](swamp_blackfen-forecast.png) |
| swamp | Sunken Abbey | [View](swamp_sunken_abbey-live.png) | [View](swamp_sunken_abbey-forecast.png) |
| infernal | Cinder Rift | [View](infernal_cinder_rift-live.png) | [View](infernal_cinder_rift-forecast.png) |
| infernal | Obsidian Wastes | [View](infernal_obsidian_wastes-live.png) | [View](infernal_obsidian_wastes-forecast.png) |
| rough | Storm Highlands | [View](rough_storm_highlands-live.png) | [View](rough_storm_highlands-forecast.png) |
| rough | The Shattered Quarry | [View](rough_shattered_quarry-live.png) | [View](rough_shattered_quarry-forecast.png) |
| river | Stoneford | [View](river_stoneford-live.png) | [View](river_stoneford-forecast.png) |
| water | Storm Shore | [View](water_storm_shore-live.png) | [View](water_storm_shore-forecast.png) |
| mountain | Glacial Pass | [View](mountain_glacial_pass-live.png) | [View](mountain_glacial_pass-forecast.png) |

[Complete river replay result](river-playback-result.png). The scene remains fixed throughout playback; survivor counts are checked against the recorded result.

To repeat engine captures: `godot --path . --audio-driver Dummy --rendering-driver opengl3 --script res://tools/battlefield_review.gd` from a graphical session. Source contact sheet: `PYTHONPATH=tools/assets python -c "from pathlib import Path; from crowns_of_cinder_assets.battlefields import contact_sheet; contact_sheet(Path.cwd())"`.
