extends SceneTree
## Inspect connectivity, weighted travel and economy across fixed recipe seeds.
## godot --headless --path . --script res://tools/gameplay_variety_report.gd -- [output.json]

func _init() -> void:
	var data := GameData.get_default()
	var rows := []
	for policy in ["fair", "adventure"]:
		for family in ["frontiers", "ringlands"]:
			for seed_value in [1, 2, 7, 17, 31, 404]:
				var def := MapGenerator.generate(data, "%s_%s_v1" % [policy, family], seed_value)
				var graph: Dictionary = def["generator"]
				var degree := {}
				var guarded := 0
				for edge in graph["connections"]:
					degree[edge["a"]] = int(degree.get(edge["a"], 0)) + 1
					degree[edge["b"]] = int(degree.get(edge["b"], 0)) + 1
					if String(edge["guard"]) != "":
						guarded += 1
				var map := AdventureMap.from_definition(def, data)
				var travel := []
				for hero in def["heroes"]:
					var from := Vector2i(int(hero["pos"][0]), int(hero["pos"][1]))
					var field := AiDistanceField.build(map, from, {})
					for town in def["objects"]:
						if town["type"] == "town" and int(town["owner"]) >= 0 and int(town["owner"]) != int(hero["owner"]):
							travel.append(field.cost_to(AdventureMap.object_pos(town)))
				rows.append({"policy": policy, "family": family, "seed": seed_value, "valid": MapValidator.validate(def, data).is_empty(),
					"regions": graph["zones"].size(), "passes": graph["connections"].size(), "guarded_passes": guarded,
					"independent_cycles": graph["connections"].size() - graph["zones"].size() + 1,
					"dead_ends": degree.values().count(1), "degree": degree, "rival_travel_cost": travel,
					"starts": MapValidator.fairness(def, data)})
				print("checked ", policy, " ", family, " seed ", seed_value)
	var path := "res://docs/reports/gameplay_variety_metrics.json"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples": rows, "count": rows.size()}, "\t"))
	file.close()
	print("wrote ", path)
	GameData._default = null
	quit()
