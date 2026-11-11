extends "res://tests/test_case.gd"
## The pick-up dialog for artifacts and the veteran rank symbols on army slots.


func test_gained_counts_new_items_and_duplicates() -> void:
	assert_eq(ArtifactFoundDialog.gained(["bone_dice"], ["bone_dice", "scholars_quill"]), ["scholars_quill"])
	assert_eq(ArtifactFoundDialog.gained(["bone_dice"], ["bone_dice", "bone_dice"]), ["bone_dice"], "a second copy is new")
	assert_eq(ArtifactFoundDialog.gained(["bone_dice", "scholars_quill"], ["scholars_quill"]), [], "lost items are not finds")


func test_every_artifact_has_artwork_for_the_dialog() -> void:
	for aid in data.artifacts:
		assert_true(ArtifactFoundDialog.artwork(String(aid), data) != null, aid)


func test_picking_up_an_artifact_on_the_map_is_detected() -> void:
	var session := GameSession.new_game(data, "ember_ford", 11)
	var h := session.hero("hero_wren")
	var before := h.all_artifacts(data)
	var target := h.pos + Vector2i(1, 0)
	if session.state.map.object_at(target).size() > 0 or not session.state.map.is_passable(target):
		target = h.pos + Vector2i(0, 1)
	session.state.map.add_object({"id": "test_relic", "type": "artifact", "artifact": "bone_dice", "pos": [target.x, target.y]})
	var r := session.move_hero(h.id, target)
	assert_eq(h.pos, target, str(r))
	assert_eq(ArtifactFoundDialog.gained(before, h.all_artifacts(data)), ["bone_dice"])


func test_dialog_shows_artwork_name_and_text() -> void:
	var session := GameSession.new_game(data, "ember_ford", 11)
	var h := session.hero("hero_wren")
	h.give_artifact("bone_dice", data)
	var d := ArtifactFoundDialog.new()
	d.build(data, 600)
	d.open(h, ["bone_dice"])
	assert_true(d.visible)
	assert_true(d.art_rect() != null and d.art_rect().texture != null, "artwork is shown")
	var texts := _label_texts(d)
	assert_true(texts.has(String(data.artifacts["bone_dice"]["name"])), str(texts))
	assert_true(texts.has(String(data.artifacts["bone_dice"]["text"])), str(texts))
	d.free()


func test_rank_symbols_escalate_to_a_star() -> void:
	for level in [1, 2, 3]:
		var s := RankBadge.shapes(level, 14.0)
		assert_eq((s["chevrons"] as Array).size(), level, "level %d shows %d chevrons" % [level, level])
		assert_true((s["fill"] as PackedVector2Array).is_empty())
	assert_eq((RankBadge.shapes(4, 14.0)["fill"] as PackedVector2Array).size(), 4, "level 4 is a gem")
	assert_eq((RankBadge.shapes(5, 14.0)["fill"] as PackedVector2Array).size(), 10, "level 5 is a five-point star")
	for level in range(1, 6):
		var s := RankBadge.shapes(level, 14.0)
		var pts: Array = (s["fill"] as PackedVector2Array) as Array
		for ch in s["chevrons"]:
			pts.append_array(ch as Array)
		for p in pts:
			assert_true(Rect2(-1, -1, 16, 16).has_point(p), "level %d stays inside its corner" % level)
	assert_eq(RankBadge.rank_name(5), "Elite")


func test_army_slot_no_longer_writes_level_text() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/army_slot.gd")
	assert_false(src.contains("\"L%d\""), "levels draw as symbols")
	assert_true(src.contains("RankBadge.paint"))


func _label_texts(n: Node) -> Array:
	var out := []
	for c in n.find_children("*", "Label", true, false):
		out.append((c as Label).text)
	return out
