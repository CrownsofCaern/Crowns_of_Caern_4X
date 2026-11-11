extends "res://tests/test_case.gd"


func _blank() -> MapDocument:
	return MapDocument.blank(data, "custom:test", "Test map", 8, 6)


func test_blank_draft_and_dimension_limits() -> void:
	var document := _blank()
	assert_true(document != null)
	assert_eq(document.definition()["terrain"], ["........", "........", "........", "........", "........", "........"])
	assert_true(document.is_dirty(), "new drafts have not been saved")
	assert_false(document.read_only())
	assert_true(MapDocument.blank(data, "a", "a", 0, 8) == null)
	assert_true(MapDocument.blank(data, "a", "a", 257, 8) == null)
	assert_true(MapDocument.blank(data, "a", "a", 8, 8, "unknown") == null)


func test_document_and_copies_do_not_alias_caller_data() -> void:
	var original := data.load_map("ember_ford")
	original["future_metadata"] = {"nested": ["preserve me"]}
	var document := MapDocument.from_definition(original, data)
	original["future_metadata"]["nested"][0] = "outside change"
	var exported := document.definition()
	assert_eq(exported["future_metadata"]["nested"][0], "preserve me")
	exported["future_metadata"]["nested"].clear()
	assert_eq(document.definition()["future_metadata"]["nested"], ["preserve me"])
	var copied := document.copy_as("custom:copy", "Copy")
	copied.paint_terrain([Vector2i.ZERO], "grass")
	assert_eq(document.definition()["terrain"][0][0], "s")
	assert_eq(copied.definition()["objects"], document.definition()["objects"], "internal IDs survive copying")


func test_drag_is_one_action_and_cancel_restores_repeated_cells() -> void:
	var document := _blank()
	document.mark_saved()
	assert_true(document.begin_action("Stroke"))
	assert_false(document.begin_action("Nested"))
	document.paint_terrain([Vector2i.ZERO, Vector2i(1, 0)], "forest")
	document.paint_terrain([Vector2i.ZERO, Vector2i(2, 0)], "snow")
	assert_false(document.can_undo(), "an unfinished stroke cannot be undone")
	document.end_action()
	assert_eq(document.definition()["terrain"][0], "sfs.....")
	document.undo()
	assert_eq(document.definition()["terrain"][0], "........")
	assert_false(document.is_dirty())
	assert_false(document.can_undo(), "the whole stroke was one action")
	document.redo()
	assert_eq(document.definition()["terrain"][0], "sfs.....")
	document.begin_action("Cancelled")
	document.paint_terrain([Vector2i.ZERO], "water")
	document.paint_terrain([Vector2i.ZERO], "desert")
	document.cancel_action()
	assert_eq(document.definition()["terrain"][0], "sfs.....")


func test_saved_revision_survives_undo_redo_and_branching() -> void:
	var document := _blank()
	document.paint_terrain([Vector2i.ZERO], "forest")
	document.mark_saved()
	document.set_title("Renamed")
	assert_true(document.is_dirty())
	document.undo()
	assert_false(document.is_dirty())
	document.undo()
	assert_true(document.is_dirty())
	document.redo()
	assert_false(document.is_dirty())
	document.undo()
	document.set_title("Branch")
	assert_false(document.can_redo())
	assert_true(document.is_dirty(), "branching must not reuse a saved revision number")


func test_invalid_paint_is_atomic_and_noop_does_not_add_history() -> void:
	var document := _blank()
	document.mark_saved()
	assert_false(document.paint_terrain([Vector2i.ZERO, Vector2i(-1, 0)], "forest"))
	assert_false(document.paint_terrain([Vector2i.ZERO], "unknown"))
	assert_eq(document.definition()["terrain"][0], "........")
	assert_true(document.paint_terrain([Vector2i.ZERO], "grass"))
	assert_false(document.can_undo())
	assert_false(document.is_dirty())


func test_road_bridges_and_round_trip_undo() -> void:
	var document := _blank()
	document.paint_terrain([Vector2i(2, 2)], "water")
	var before := document.definition()
	assert_true(document.paint_roads([Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)], true))
	var map := AdventureMap.from_definition(document.definition(), data)
	assert_true(map.is_passable(Vector2i(2, 2)))
	assert_eq(document.definition()["roads"], [{"from": [1, 2], "to": [3, 2]}])
	document.undo()
	assert_eq(document.definition(), before)
	document.redo()
	document.paint_roads([Vector2i(2, 2)], false)
	map = AdventureMap.from_definition(document.definition(), data)
	assert_false(map.is_passable(Vector2i(2, 2)))


func test_entities_properties_players_and_decorations_are_reversible() -> void:
	var document := _blank()
	var original := document.definition()
	var entity := {"id": "town_1", "type": "town", "pos": [2, 3], "owner": 0, "name": "Keep", "town_type": "concord"}
	document.begin_action("Build start")
	assert_true(document.put_entity(entity))
	assert_eq(document.unique_entity_id("town"), "town_2")
	entity["pos"] = [3, 3]
	entity["name"] = "Moved keep"
	assert_true(document.put_entity(entity))
	assert_true(document.set_players([{"id": 0, "faction": "concord"}]))
	assert_true(document.set_decorations([{"pos": [1, 1], "kind": "tree"}]))
	document.end_action()
	var edited := document.definition()
	assert_eq(edited["objects"].size(), 1)
	assert_eq(edited["objects"][0]["pos"], [3, 3])
	entity["name"] = "Caller mutation"
	assert_eq(document.definition()["objects"][0]["name"], "Moved keep")
	assert_false(document.put_entity({"id": "town_1", "pos": [3, 3]}, true), "IDs shared between objects and heroes")
	document.undo()
	assert_eq(document.definition(), original)
	document.redo()
	assert_eq(document.definition(), edited)
	document.remove_entity("town_1")
	assert_eq(document.definition()["objects"].size(), 0)
	document.undo()
	assert_eq(document.definition(), edited)


func test_existing_optional_fields_remain_absent_after_undo() -> void:
	var definition := _blank().definition()
	definition.erase("decorations")
	var document := MapDocument.from_definition(definition, data)
	document.set_decorations([{"pos": [0, 0], "kind": "tree"}])
	document.undo()
	assert_eq(document.definition(), definition)


func test_malformed_structures_are_rejected_before_constructors() -> void:
	for patch in [
		{"width": -1}, {"height": 2.5}, {"terrain": [null]}, {"roads": "bad"},
		{"generator": "bad"}, {"scenario": []}, {"name": 10},
		{"objects": [null]}, {"players": [3]}, {"decorations": [false]},
		{"objects": [{"id": "x", "type": "mine", "pos": [1.5, 0]}]},
		{"roads": [{"from": [0, 0], "to": [3, 2]}]},
		{"roads": [{"from": [0, 0], "to": [8, 0]}]},
		{"roads": [{"from": "bad", "to": [0, 0]}]},
	]:
		var definition := _blank().definition()
		definition.merge(patch, true)
		assert_true(MapDocument.structural_errors(definition, data).size() > 0, str(patch))
		assert_true(MapDocument.from_definition(definition, data) == null)


func test_scenario_snapshot_is_preserved_and_cannot_be_edited() -> void:
	var definition := data.load_map("last_watch")
	var document := MapDocument.from_definition(definition, data)
	assert_true(document != null)
	if document == null:
		return
	assert_true(document.read_only())
	assert_eq(document.definition(), definition, "retain quests, gates, waves, orders and objective references")
	assert_false(document.paint_terrain([Vector2i.ZERO], "grass"))
	assert_false(document.set_title("Accidental conquest copy"))
	assert_true(document.copy_as("custom:copy", "Copy") == null)
	assert_eq(document.definition(), definition)


func test_unknown_object_type_is_read_only_without_losing_fields() -> void:
	var definition := _blank().definition()
	definition["objects"] = [{"id": "future", "type": "new_behaviour", "pos": [1, 1], "custom": {"flag": true}}]
	var document := MapDocument.from_definition(definition, data)
	assert_true(document.read_only())
	assert_eq(document.definition(), definition)


func test_generated_copy_retains_provenance_without_fair_guarantee() -> void:
	var definition := _blank().definition()
	definition["id"] = "gen:example:17"
	definition["generator"] = {"template": "example", "seed": 17, "policy": "fair", "zones": [{"id": "start"}]}
	var source := MapDocument.from_definition(definition, data)
	var copied := source.copy_as("custom:authored", "Authored")
	assert_false(copied.definition().has("generator"))
	assert_eq(copied.definition()["editor_source"]["generator"], definition["generator"])
	assert_true(source.definition().has("generator"))


func test_registered_terrain_is_available_without_editor_code_changes() -> void:
	var expanded := GameData.new()
	expanded.terrains = data.terrains.duplicate(true)
	expanded.terrain_by_char = data.terrain_by_char.duplicate(true)
	expanded.terrains["new_terrain"] = {"char": "n"}
	expanded.terrain_by_char["n"] = "new_terrain"
	var document := MapDocument.blank(expanded, "custom:new", "New content", 2, 2)
	assert_true(document.paint_terrain([Vector2i.ZERO], "new_terrain"))
	assert_eq(document.definition()["terrain"][0], "n.")


func test_stroke_returning_to_original_does_not_dirty_or_discard_redo() -> void:
	var document := _blank()
	document.mark_saved()
	document.set_title("Later")
	document.undo()
	document.begin_action("No net change")
	document.paint_terrain([Vector2i.ZERO], "forest")
	document.paint_terrain([Vector2i.ZERO], "grass")
	assert_false(document.is_dirty())
	document.end_action()
	assert_false(document.is_dirty())
	assert_false(document.can_undo())
	assert_true(document.can_redo())


func test_history_memory_is_bounded_and_retained_actions_still_undo() -> void:
	var document := _blank()
	var first := "a".repeat(3 * 1024 * 1024)
	var second := "b".repeat(3 * 1024 * 1024)
	document.set_title(first)
	document.mark_saved()
	document.set_title(second)
	assert_true(document._history_bytes <= MapDocument.MAX_HISTORY_BYTES)
	document.undo()
	assert_eq(document.definition()["name"], first)
	assert_false(document.is_dirty())
	assert_false(document.can_undo(), "oldest action was evicted to enforce the memory budget")


func test_all_bundled_maps_can_be_parsed_without_losing_fields() -> void:
	for filename in DirAccess.get_files_at("res://data/maps"):
		if not filename.ends_with(".json"):
			continue
		var definition: Dictionary = GameData.read_json("res://data/maps/" + filename)
		var document := MapDocument.from_definition(definition, data)
		assert_true(document != null, filename)
		if document != null:
			assert_eq(document.definition(), definition, filename)


func test_draft_placement_reports_collisions_and_terrain_but_allows_own_town() -> void:
	var document := _blank()
	document.put_entity({"id": "town", "type": "town", "pos": [2, 2], "owner": 0})
	document.put_entity({"id": "hero", "pos": [2, 2], "owner": 0}, true)
	assert_eq(document.placement_errors().size(), 0)
	document.put_entity({"id": "enemy", "pos": [2, 2], "owner": 1}, true)
	assert_eq(document.placement_errors().size(), 1)
	document.remove_entity("enemy", true)
	document.paint_terrain([Vector2i(2, 2)], "water")
	assert_eq(document.placement_errors().size(), 2)
	document.paint_roads([Vector2i(2, 2)], true)
	assert_eq(document.placement_errors().size(), 0)
