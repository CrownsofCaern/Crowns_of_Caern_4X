extends "res://tests/test_case.gd"


func test_every_playable_faction_has_dedicated_ultimate_art_and_material() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/ultimate_buildings.json"))
	var seen := {}
	for asset in registry["assets"]:
		var faction: String = asset["faction"]
		var bid: String = asset["building_id"]
		assert_false(seen.has(faction), faction)
		seen[faction] = true
		assert_eq(data.town_types[faction]["buildings"][bid]["category"], "ultimate")
		var scene := TownScene.scene_for(faction)
		assert_true(scene["assets"].has(bid), faction)
		assert_true(ResourceLoader.exists(scene["assets"][bid]), faction)
		var texture: Texture2D = load(scene["assets"][bid])
		assert_eq(maxf(texture.get_width(),texture.get_height()),350.0,faction)
		var material := UltimateCreatureArt.material_for(faction)
		assert_true(material != null and material.shader != null, faction)
	for faction in data.town_types:
		assert_true(seen.has(faction), faction)


func test_dlc_ultimate_effects_apply_and_survive_the_replay() -> void:
	for faction in ["darkelf","fishmen"]:
		var creature := "de_gloam_spear" if faction == "darkelf" else "fm_brine_spear"
		var effect := BalanceScenarios.new(data).ultimate_of(faction)
		assert_false(effect.is_empty(), faction)
		var left := BalanceScenarios.side([[creature,12]])
		left["upgrades"] = {faction:effect}
		var right := BalanceScenarios.side([["pike_militia",12]])
		var result := CombatSimulator.new(data).simulate(CombatSimulator.make_setup(left,right,"desert",87),true)
		assert_eq(result["sides"][0]["stacks"][0]["ultimate"],effect["name"])
		assert_eq(result["sides"][1]["stacks"][0]["ultimate"], "")
		var replay := BattleReplay.from_result(result)
		assert_eq(replay.stacks[0][0]["ultimate"],effect["name"])
		var figure := BattleFigure.new()
		figure.setup(creature,12,1.0,0.0,true)
		assert_eq(figure.sprite.material,UltimateCreatureArt.material_for(faction))
		figure.set_count(0)
		assert_true(figure.sprite.material == null)
		figure.free()
