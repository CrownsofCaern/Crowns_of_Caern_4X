extends "res://tests/test_case.gd"


func _ids(entries: Array) -> Array:
	return entries.map(func(entry): return entry["id"])


func test_creature_tabs_are_factions_with_wild_last() -> void:
	var tabs := MapPaletteCatalog.categories(data, "neutral_army")
	var ids: Array = tabs.map(func(tab): return tab["id"])
	assert_eq(ids[0], MapPaletteCatalog.ALL)
	assert_eq(ids[ids.size() - 1], "wilds", "Wild creatures get the last tab")
	for faction in GameSetup.playable_factions(data):
		assert_true(ids.has(faction), "tab for " + faction)
	assert_eq(tabs[tabs.size() - 1]["label"], "Wild")


func test_faction_tab_lists_only_that_faction_sorted_by_tier() -> void:
	var entries := MapPaletteCatalog.entries(data, "neutral_army", "concord")
	assert_gt(entries.size(), 0)
	var last_tier := 0
	for entry in entries:
		var creature: Dictionary = data.creatures[entry["id"]]
		assert_eq(creature["faction"], "concord", entry["id"])
		assert_true(int(creature["tier"]) >= last_tier, "tiers ascend at " + entry["id"])
		last_tier = int(creature["tier"])
		assert_eq(entry["group"], "Tier %d" % last_tier)


func test_every_upgrade_follows_its_base_unit() -> void:
	var ids := _ids(MapPaletteCatalog.entries(data, "neutral_army"))
	assert_eq(ids.size(), data.creatures.size(), "All tab lists every creature")
	for id in data.creatures:
		var upgrade := str(data.creatures[id].get("upgrade", ""))
		if upgrade != "":
			assert_eq(ids.find(upgrade), ids.find(id) + 1, id + " then " + upgrade)
	assert_true(MapPaletteCatalog.entry_label(data, "neutral_army", "pike_veteran").begins_with("T1+"))
	assert_true(MapPaletteCatalog.entry_label(data, "neutral_army", "pike_militia").begins_with("T1 "))


func test_wild_tab_and_search() -> void:
	var wild := MapPaletteCatalog.entries(data, "neutral_army", "wilds")
	assert_gt(wild.size(), 20)
	for entry in wild:
		assert_eq(data.creatures[entry["id"]]["faction"], "wilds")
	var found := _ids(MapPaletteCatalog.entries(data, "neutral_army", MapPaletteCatalog.ALL, "Longbow"))
	assert_true(found.has("longbowman"))
	assert_eq(_ids(MapPaletteCatalog.entries(data, "neutral_army", "wilds", "longbow")), [])
	# Searching a faction's display name finds its units.
	assert_true(_ids(MapPaletteCatalog.entries(data, "neutral_army", MapPaletteCatalog.ALL, "concordant")).has("pike_militia"))


func test_hero_artifact_and_site_tabs() -> void:
	for type in ["hero", "artifact", "site"]:
		var tabs := MapPaletteCatalog.categories(data, type)
		assert_gt(tabs.size(), 2, type + " has tabs")
		var total := 0
		for tab in tabs.slice(1):
			var entries := MapPaletteCatalog.entries(data, type, tab["id"])
			assert_gt(entries.size(), 0, type + " tab " + tab["id"])
			total += entries.size()
		assert_eq(total, MapAuthoring.registry(data, type).size(), type + " tabs cover every item once")
	var hero_tabs: Array = MapPaletteCatalog.categories(data, "hero").map(func(tab): return tab["id"])
	assert_false(hero_tabs.has("wilds"), "no hero classes are wild")
	var weapons := MapPaletteCatalog.entries(data, "artifact", "weapon")
	var rank := -1
	for entry in weapons:
		var next := MapPaletteCatalog.RARITY_ORDER.find(data.artifacts[entry["id"]]["rarity"])
		assert_true(next >= rank, "rarity ascends")
		rank = next


func test_small_types_have_no_tabs_and_keep_everything() -> void:
	for type in ["town", "mine", "resource", "encounter"]:
		assert_eq(MapPaletteCatalog.categories(data, type).size(), 0, type)
		assert_eq(MapPaletteCatalog.entries(data, type).size(), MapAuthoring.registry(data, type).size(), type)


func test_army_editor_opens_on_the_shared_faction() -> void:
	assert_eq(MapArmyEditor.initial_category(data, [["pike_militia", 3], ["longbowman", 2]], "wilds"), "concord")
	assert_eq(MapArmyEditor.initial_category(data, [], "wilds"), "wilds")
	var mixed := [["pike_militia", 3], [str(MapPaletteCatalog.entries(data, "neutral_army", "wilds")[0]["id"]), 2]]
	assert_eq(MapArmyEditor.initial_category(data, mixed, "concord"), MapPaletteCatalog.ALL)
