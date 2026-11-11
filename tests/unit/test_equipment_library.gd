extends "res://tests/test_case.gd"
## The equipment artwork library (assets/source/equipment-002) as hero artifacts: every design is
## an artifact with its icon, legendaries are relics, and the four elemental sets work.


func _library() -> Array:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/batches/equipment-002.json"))
	return spec["assets"]


func _hero(cls: String = "knight") -> Hero:
	return Hero.create({"id": "h", "name": "h", "class": cls, "pos": [0, 0], "army": [["pike_militia", 10]]}, data)


func test_every_design_is_an_artifact_with_its_icon() -> void:
	var lib := _library()
	assert_eq(lib.size(), 112)
	for entry: Dictionary in lib:
		var id: String = entry["id"]
		assert_true(data.artifacts.has(id), id)
		if not data.artifacts.has(id):
			continue
		var a: Dictionary = data.artifacts[id]
		assert_eq(a["slot"], entry["slot"], id)
		var rarity: String = "relic" if entry["quality"] == "legendary" else entry["quality"]
		assert_eq(a["rarity"], rarity, id)
		assert_false((a["mods"] as Dictionary).is_empty(), id + " has an effect")
		assert_true(ResourceLoader.exists("res://assets/artifacts/%s.png" % id), id + " icon")
		if entry["element"] != "none":
			assert_true(String(a["text"]).begins_with(String(entry["element"]).capitalize() + "."), id + " names its element")


func test_legendaries_are_the_strongest_relics() -> void:
	for entry: Dictionary in _library():
		var v := int(data.artifacts[entry["id"]]["value"])
		match entry["quality"]:
			"minor":
				assert_between(float(v), 1000.0, 3000.0, entry["id"])
			"major":
				assert_between(float(v), 4000.0, 6000.0, entry["id"])
			"relic":
				assert_between(float(v), 9000.0, 14000.0, entry["id"])
			"legendary":
				assert_between(float(v), 15000.0, 18000.0, entry["id"])


func test_elemental_sets() -> void:
	assert_eq(data._validate_artifact_sets().size(), 0)
	assert_eq((data.artifact_sets["emerald_blight"]["pieces"] as Array).size(), 7, "one poison piece per slot")
	var h := _hero()
	var before := h.modifiers(data)
	for a in data.artifact_sets["emerald_blight"]["pieces"]:
		assert_true(h.give_artifact(a, data), a)
	assert_eq(h.worn_set_pieces("emerald_blight", data), 7)
	assert_eq(h.active_set_bonuses(data).size(), 3, "2, 4 and 7 pieces")
	var mods := h.modifiers(data)
	assert_eq(int(mods.get("enemy_morale", 0)) - int(before.get("enemy_morale", 0)), 1 + 1 + 1,
		"panoply, standard and the 4-piece bonus")
	var art := float(mods.get("art_power_pct", 0.0)) - float(before.get("art_power_pct", 0.0))
	assert_between(art, 0.449, 0.451, "reliquary 20% and the full set 25%")


func test_traders_and_drops_can_offer_library_pieces() -> void:
	var by_rarity := {}
	for entry: Dictionary in _library():
		var r: String = data.artifacts[entry["id"]]["rarity"]
		by_rarity[r] = int(by_rarity.get(r, 0)) + 1
	assert_eq(by_rarity, {"minor": 28, "major": 28, "relic": 56})
	var drop_slots: Array = data.artifact_rules["drop_slots"]
	var armor := 0
	for entry: Dictionary in _library():
		if drop_slots.has(entry["slot"]):
			armor += 1
	assert_eq(armor, 52, "helms, armor, shields and boots join the scattered armor pool")
