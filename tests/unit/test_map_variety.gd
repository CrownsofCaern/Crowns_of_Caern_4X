extends "res://tests/test_case.gd"


func test_recipe_data_is_valid() -> void:
	assert_eq(MapGenerator.validate_templates(data), [] as Array[String])


func test_layout_families_are_valid_and_topology_varies() -> void:
	for policy in ["fair", "adventure"]:
		for family in ["frontiers", "ringlands"]:
			var graphs := {}
			for seed_value in [1, 2, 7, 17, 31, 404]:
				var def := MapGenerator.generate(data, "%s_%s_v1" % [policy, family], seed_value)
				var errors := MapValidator.validate(def, data)
				assert_true(errors.is_empty(), "%s %s seed %d: %s" % [policy, family, seed_value, ", ".join(errors)])
				assert_eq(def["generator"]["policy"], policy)
				var connections: Array = def["generator"]["connections"].map(func(c): return "%s-%s" % [c["a"], c["b"]])
				connections.sort()
				graphs[JSON.stringify(connections)] = true
			assert_gt(graphs.size(), 1, "%s %s must vary connections, not just terrain" % [policy, family])


func test_recipe_does_not_mutate_registry_and_is_reproducible() -> void:
	var before := JSON.stringify(data.map_templates)
	var a := MapGenerator.generate(data, "fair_frontiers_v1", 11)
	var b := MapGenerator.generate(data, "fair_frontiers_v1", 11)
	assert_eq(JSON.stringify(a), JSON.stringify(b))
	assert_eq(JSON.stringify(data.map_templates), before)


func test_adventure_has_independent_regions() -> void:
	var def := MapGenerator.generate(data, "adventure_frontiers_v1", 7)
	var metrics := MapValidator.fairness(def, data)
	assert_ne(metrics[0]["pile_value"], metrics[1]["pile_value"], "Adventure starts roll independent resource amounts")
	assert_true(MapValidator.validate(def, data).is_empty())
	def["generator"]["policy"] = "fair"
	assert_false(MapValidator.validate(def, data).is_empty(), "Fair still enforces equal opportunities")


func test_adventure_supports_three_to_six_realms() -> void:
	for count in [3, 4, 5, 6]:
		var def := MapGenerator.generate(data, "adventure_marches_%d_v1" % count, 7)
		var errors := MapValidator.validate(def, data)
		assert_true(errors.is_empty(), "%d realms: %s" % [count, ", ".join(errors)])
		assert_eq(def["players"].size(), count)
		assert_eq(def["generator"]["policy"], "adventure")
