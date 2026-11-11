extends "res://tests/test_case.gd"

func _labels(node: Node) -> String:
	var text: String = node.text if node is Label else ""
	for child in node.get_children():
		text += "\n" + _labels(child)
	return text

func test_visible_levels_and_progress_refresh_after_merge() -> void:
	var session := GameSession.new_game(data, "ember_ford", 11)
	var h := session.hero("hero_wren")
	h.army.slots[0]["veteran_xp"] = 1700
	var exchange := ArmyExchange.new()
	exchange.show_veteran_details = true
	exchange.setup(session, [[h.id, "Army"]])
	assert_true(_labels(exchange).contains("Level 2"))
	assert_true(_labels(exchange).contains("200 / 3500 XP"))
	assert_eq(exchange._slots[h.id][0].veteran_level, 2)
	h.army.slots[0]["veteran_xp"] = 35000
	exchange.refresh()
	assert_true(_labels(exchange).contains("Veteran level 5 (maximum)"))
	assert_eq(exchange._slots[h.id][0].veteran_level, 5)
	exchange.free()
