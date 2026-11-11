extends "res://tests/test_case.gd"


func _generator(chance: float = 0.85) -> MapGenerator:
	var gen := MapGenerator.new(data)
	gen.config = data.map_templates.duplicate(true)
	gen.config["neutral_habitats"] = {"native_chance": chance}
	gen.rng = GameRng.new(8723)
	return gen


func test_native_armies_fit_every_land_biome_and_keep_budget() -> void:
	var gen := _generator(1.0)
	for biome in ["grass", "forest", "desert", "snow", "swamp", "infernal", "rough"]:
		for budget in [700, 1400, 3800, 8500, 15000]:
			for sample in 20:
				var army := gen._roll_army(budget, biome, 1, true)
				var actual := 0
				for stack in army["stacks"]:
					assert_true(MapGenerator.native_to(data, stack[0], biome), "%s on %s" % [stack[0], biome])
					actual += MapGenerator.creature_value(data.creatures[stack[0]]) * int(stack[1])
				assert_between(float(actual) / budget, 0.8, 1.2, "habitat selection retains the guard budget")


func test_native_majority_with_some_outsiders() -> void:
	var gen := _generator()
	var local := 0
	var outsiders := 0
	for i in 1000:
		var army := gen._roll_army(8500, "desert", 1, true)
		var all_local := true
		for stack in army["stacks"]:
			if not MapGenerator.native_to(data, stack[0], "desert"):
				all_local = false
		if all_local:
			local += 1
		else:
			outsiders += 1
	assert_between(local / 1000.0, 0.80, 0.95)
	assert_gt(outsiders, 30, "outsiders remain possible")


func test_habitat_postpass_uses_actual_tile_and_preserves_placement_rng() -> void:
	var gen := _generator(1.0)
	gen.w = 3
	gen.h = 1
	gen.terrain = PackedStringArray(["forest", "snow", "desert"])
	gen._attempt_seed = 77
	gen.objects = [
		{"id": "a", "type": "neutral_army", "pos": [0, 0], "stacks": [["dune_scuttler", 10]], "value": 1400},
		{"id": "b", "type": "mine", "pos": [1, 0], "guard": [["dune_scuttler", 10]]},
		{"id": "c", "type": "town", "pos": [2, 0], "garrison": [["pike_militia", 10]]}]
	var rng_before := gen.rng.state
	gen._apply_neutral_habitats()
	assert_eq(gen.rng.state, rng_before, "ecology does not consume the geography stream")
	for stack in gen.objects[0]["stacks"]:
		assert_true(MapGenerator.native_to(data, stack[0], "forest"))
	for stack in gen.objects[1]["guard"]:
		assert_true(MapGenerator.native_to(data, stack[0], "snow"))
	assert_eq(gen.objects[0]["pos"], [0, 0])
	assert_eq(gen.objects[0]["value"], 1400)
	assert_eq(gen.objects[2]["garrison"], [["pike_militia", 10]], "towns retain faction garrisons")


func test_equivalent_guards_get_identical_armies_and_seed_is_reproducible() -> void:
	var gen := _generator()
	gen.w = 2
	gen.h = 1
	gen.terrain = PackedStringArray(["forest", "forest"])
	gen._attempt_seed = 17
	gen.objects = [
		{"id": "a", "type": "neutral_army", "pos": [0, 0], "stacks": [["dune_scuttler", 10]], "value": 1400},
		{"id": "b", "type": "neutral_army", "pos": [1, 0], "stacks": [["dune_scuttler", 10]], "value": 1400}]
	var original := gen.objects.duplicate(true)
	gen._apply_neutral_habitats()
	var result := gen.objects.duplicate(true)
	assert_eq(result[0]["stacks"], result[1]["stacks"])
	gen.objects = original
	gen._apply_neutral_habitats()
	assert_eq(JSON.stringify(gen.objects), JSON.stringify(result))


func test_habitat_probability_validation() -> void:
	var original: Variant = data.map_templates.get("neutral_habitats", {})
	data.map_templates["neutral_habitats"] = {"native_chance": 1.5}
	var errors := data.validate()
	data.map_templates["neutral_habitats"] = original
	assert_true(errors.any(func(e): return e.contains("native_chance")))


func test_generated_map_guards_fit_the_final_terrain() -> void:
	var gen := _generator(1.0)
	var result := gen.run("crossing", 17)
	assert_true(MapValidator.validate(result, data).is_empty())
	var map := AdventureMap.from_definition(result, data)
	var count := 0
	for obj in result["objects"]:
		# Trading-house escorts travel with their posts; they are not local fauna.
		if MapCobolts.is_post(obj, data):
			continue
		var field := "stacks" if obj["type"] == "neutral_army" else "guard"
		for stack in obj.get(field, []):
			var biome := map.combat_terrain(AdventureMap.object_pos(obj))
			assert_true(MapGenerator.native_to(data, stack[0], biome), "%s should fit %s" % [obj["id"], biome])
			count += 1
	assert_gt(count, 10, "check generated gate, pocket and roaming guards")
