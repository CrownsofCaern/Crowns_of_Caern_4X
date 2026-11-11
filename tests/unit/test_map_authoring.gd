extends "res://tests/test_case.gd"


func _player(id: int, faction: String = "concord") -> Dictionary:
	return {"id": id, "name": "Player %d" % id, "faction": faction, "is_human": id == 0,
		"color": "#c94040", "difficulty": data.default_difficulty(), "team": 0}


func _draft() -> MapDocument:
	var document := MapDocument.blank(data, "custom:authoring", "Authoring", 12, 12)
	document.set_players([_player(0), _player(1, "ashen")])
	return document


func test_all_registered_content_has_defaults_that_can_be_placed() -> void:
	for type in MapAuthoring.TYPES:
		for content in MapAuthoring.registry(data, type):
			var document := _draft()
			var result := MapAuthoring.place(document, data, type, content, Vector2i(3, 3), 0)
			assert_eq(result["error"], "", type + ": " + str(content))
			if result["error"] == "":
				assert_false(document.entity(result["id"], type == "hero").is_empty())


func test_place_move_duplicate_and_delete_are_independent_undo_actions() -> void:
	var document := _draft()
	var original := document.definition()
	var result := MapAuthoring.place(document, data, "hero", "knight", Vector2i(2, 2), 0)
	assert_eq(result["error"], "")
	var id: String = result["id"]
	var hero := document.entity(id, true)
	assert_eq(MapAuthoring.move(document, data, id, true, Vector2i(4, 4))["error"], "")
	assert_eq(document.entity(id, true)["pos"], [4, 4])
	document.undo()
	assert_eq(document.entity(id, true), hero)
	document.redo()
	var copy := MapAuthoring.move(document, data, id, true, Vector2i(5, 4), true)
	assert_eq(copy["error"], "")
	assert_ne(copy["id"], id)
	assert_eq(document.entity(copy["id"], true)["army"], hero["army"])
	assert_eq(MapAuthoring.delete(document, copy["id"], true), "")
	document.undo()
	assert_false(document.entity(copy["id"], true).is_empty())
	document.undo()
	document.undo()
	document.undo()
	assert_eq(document.definition(), original)


func test_occupied_and_impassable_placements_fail_without_dirtying() -> void:
	var document := _draft()
	MapAuthoring.place(document, data, "mine", "wood", Vector2i(2, 2))
	document.paint_terrain([Vector2i(4, 4)], "water")
	document.mark_saved()
	var original := document.definition()
	assert_ne(MapAuthoring.place(document, data, "town", "concord", Vector2i(2, 2), 0)["error"], "")
	assert_ne(MapAuthoring.place(document, data, "hero", "knight", Vector2i(4, 4), 0)["error"], "")
	assert_ne(MapAuthoring.place(document, data, "resource", "gold", Vector2i(-1, 4))["error"], "")
	assert_eq(document.definition(), original)
	assert_false(document.is_dirty())


func test_hero_can_share_own_town_but_not_enemy_town_or_another_hero() -> void:
	var document := _draft()
	assert_eq(MapAuthoring.place(document, data, "town", "concord", Vector2i(3, 3), 0)["error"], "")
	assert_ne(MapAuthoring.place(document, data, "hero", "knight", Vector2i(3, 3), 1)["error"], "")
	assert_eq(MapAuthoring.place(document, data, "hero", "knight", Vector2i(3, 3), 0)["error"], "")
	assert_ne(MapAuthoring.place(document, data, "hero", "knight", Vector2i(3, 3), 0)["error"], "")
	assert_eq(document.entities_at(Vector2i(3, 3)).size(), 2)
	assert_eq(document.placement_errors().size(), 0)


func test_property_updates_preserve_unknown_fields_and_are_reversible() -> void:
	var document := _draft()
	var result := MapAuthoring.place(document, data, "town", "concord", Vector2i(2, 2), 0)
	var id: String = result["id"]
	var value := document.entity(id)
	value["future_metadata"] = {"flag": true}
	value["garrison"] = [["pike_militia", 33]]
	value["available"] = {"pike_militia": 7}
	value["name"] = "My keep"
	var original := document.entity(id)
	assert_eq(MapAuthoring.store(document, data, value, false, id), "")
	assert_eq(document.entity(id)["garrison"], [["pike_militia", 33]])
	assert_true(document.entity(id)["future_metadata"]["flag"])
	assert_eq(document.entity(id)["available"], {"pike_militia": 7})
	document.undo()
	assert_eq(document.entity(id), original)


func test_bad_property_values_fail_atomically() -> void:
	var document := _draft()
	var result := MapAuthoring.place(document, data, "neutral_army", "pike_militia", Vector2i(2, 2))
	var id: String = result["id"]
	var original := document.entity(id)
	for stacks in [false, [], [["unknown", 5]], [["pike_militia", 0]], [["pike_militia", 2.5]]]:
		var value := original.duplicate(true)
		value["stacks"] = stacks
		assert_ne(MapAuthoring.store(document, data, value, false, id), "")
		assert_eq(document.entity(id), original)
	var value := original.duplicate(true)
	value["id"] = "renamed"
	assert_ne(MapAuthoring.store(document, data, value, false, id), "")


func test_guard_references_block_deletion_until_explicitly_unlinked() -> void:
	var document := _draft()
	var guard := MapAuthoring.place(document, data, "neutral_army", "pike_militia", Vector2i(2, 2))
	var treasure := MapAuthoring.place(document, data, "artifact", data.artifacts.keys()[0], Vector2i(3, 2))
	var value := document.entity(treasure["id"])
	value["guarded_by"] = guard["id"]
	assert_eq(MapAuthoring.store(document, data, value, false, treasure["id"]), "")
	assert_ne(MapAuthoring.delete(document, guard["id"], false), "")
	value.erase("guarded_by")
	assert_eq(MapAuthoring.store(document, data, value, false, treasure["id"]), "")
	assert_eq(MapAuthoring.delete(document, guard["id"], false), "")


func test_player_removal_blocks_owned_entities_and_keeps_everything_unchanged() -> void:
	var document := _draft()
	MapAuthoring.place(document, data, "hero", "knight", Vector2i(3, 3), 1)
	var original := document.definition()
	assert_ne(MapAuthoring.replace_players(document, data, [_player(0)]), "")
	assert_eq(document.definition(), original)


func test_player_reindex_updates_all_owners_in_one_undo_action() -> void:
	var document := _draft()
	var hero := MapAuthoring.place(document, data, "hero", "knight", Vector2i(3, 3), 1)
	var town := MapAuthoring.place(document, data, "town", "ashen", Vector2i(4, 3), 1)
	var before := document.definition()
	assert_eq(MapAuthoring.replace_players(document, data, [_player(1, "forge")]), "")
	assert_eq(document.definition()["players"][0]["id"], 0)
	assert_eq(document.entity(hero["id"], true)["owner"], 0)
	assert_eq(document.entity(town["id"])["owner"], 0)
	assert_eq(document.entity(hero["id"], true)["class"], "knight", "faction change does not convert authored heroes")
	assert_eq(document.entity(town["id"])["town_type"], "ashen")
	document.undo()
	assert_eq(document.definition(), before)
	document.redo()
	assert_eq(document.entity(hero["id"], true)["owner"], 0)


func test_invalid_players_are_rejected_and_custom_player_fields_survive() -> void:
	var document := _draft()
	var before := document.definition()
	for patch in [{"id": -1}, {"id": 0.5}, {"faction": "missing"}, {"is_human": "yes"}, {"color": "not-a-colour"}, {"team": 999}, {"difficulty": "missing"}]:
		var player := _player(0)
		player.merge(patch, true)
		assert_ne(MapAuthoring.replace_players(document, data, [player]), "", str(patch))
		assert_eq(document.definition(), before)
	var player := _player(0)
	player["custom"] = [1, 2]
	assert_eq(MapAuthoring.replace_players(document, data, [player]), "")
	assert_eq(document.definition()["players"][0]["custom"], [1, 2])


func test_scenario_authoring_commands_cannot_change_read_only_maps() -> void:
	var document := MapDocument.from_definition(data.load_map("last_watch"), data)
	var original := document.definition()
	assert_ne(MapAuthoring.place(document, data, "town", "concord", Vector2i(1, 1), 0)["error"], "")
	assert_ne(MapAuthoring.replace_players(document, data, [_player(0)]), "")
	assert_ne(MapAuthoring.delete(document, str(original["objects"][0]["id"]), false), "")
	assert_eq(document.definition(), original)


func test_malformed_player_and_owner_shapes_are_rejected_before_ui_use() -> void:
	for players in [[{}], [{"id": []}], [{"id": 0}, {"id": 0}], [{"id": 0, "color": []}], [{"id": 0, "team": []}]]:
		var definition := _draft().definition()
		definition["players"] = players
		assert_true(MapDocument.from_definition(definition, data) == null)
	var definition := _draft().definition()
	definition["objects"] = [{"id": "bad", "type": "town", "pos": [1, 1], "owner": []}]
	assert_true(MapDocument.from_definition(definition, data) == null)
