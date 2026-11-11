extends "res://tests/test_case.gd"

## Long-running tests (whole AI games, balance sweeps, many generated maps):
## they run only with ./run_tests.sh --slow.
const SLOW := ["test_adventure_supports_three_to_six_realms"]


func test_recipe_data_is_valid() -> void:
	assert_eq(MapGenerator.validate_templates(data), [] as Array[String])


func test_layout_families_are_valid_and_topology_varies() -> void:
	for policy in ["fair", "adventure"]:
		for family in ["frontiers", "ringlands"]:
			var tpl := "%s_%s_v1" % [policy, family]
			# One full map per family (generation takes seconds) ...
			var def := generated_map(tpl, 7)
			var errors := MapValidator.validate(def, data)
			assert_true(errors.is_empty(), "%s %s: %s" % [policy, family, ", ".join(errors)])
			assert_eq(def["generator"]["policy"], policy)
			# ... and the zone graphs of several seeds: the layout step that
			# picks the connections, as the generator's first attempt runs it.
			var graphs := {}
			for seed_value in [1, 2, 7, 17, 31, 404]:
				var t := MapGenerator.find_template(data.map_templates, tpl, seed_value).duplicate(true)
				var rng := GameRng.new(GameRng.mix(GameRng.mix(seed_value, MapGenerator._stable_hash(tpl)), 0))
				assert_true(ZoneLayout.new().build(t, rng), "%s seed %d lays out" % [tpl, seed_value])
				var connections: Array = t["connections"].map(func(c): return "%s-%s" % [c["a"], c["b"]])
				connections.sort()
				graphs[JSON.stringify(connections)] = true
			assert_gt(graphs.size(), 1, "%s %s must vary connections, not just terrain" % [policy, family])


func test_recipe_does_not_mutate_registry_and_is_reproducible() -> void:
	var before := JSON.stringify(data.map_templates)
	# Reproducibility of whole maps is covered by test_mapgen; one generation
	# here proves the recipe leaves the shared registry untouched.
	var a := MapGenerator.generate(data, "fair_frontiers_v1", 11)
	assert_false(a.is_empty())
	assert_eq(JSON.stringify(data.map_templates), before)


func test_adventure_has_independent_regions() -> void:
	var def := generated_map("adventure_frontiers_v1", 7)
	var metrics := MapValidator.fairness(def, data)
	assert_ne(metrics[0]["pile_value"], metrics[1]["pile_value"], "Adventure starts roll independent resource amounts")
	assert_true(MapValidator.validate(def, data).is_empty())
	def["generator"]["policy"] = "fair"
	assert_false(MapValidator.validate(def, data).is_empty(), "Fair still enforces equal opportunities")


func test_adventure_supports_three_to_six_realms() -> void:
	for count in [3, 6]:
		var def := generated_map("adventure_marches_%d_v1" % count, 7)
		var errors := MapValidator.validate(def, data)
		assert_true(errors.is_empty(), "%d realms: %s" % [count, ", ".join(errors)])
		assert_eq(def["players"].size(), count)
		assert_eq(def["generator"]["policy"], "adventure")
