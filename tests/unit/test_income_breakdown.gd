extends "res://tests/test_case.gd"
## The resource bar's tooltip: daily income per resource and where it comes
## from (GameSession.income_breakdown, Hud.income_tooltip).


func _sum(entry: Dictionary) -> int:
	var n := 0
	for src in entry["sources"]:
		if not String(src[1]).ends_with("%"):
			n += int(String(src[1]))
	return n


func test_totals_match_daily_income_and_sources_add_up() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var town: Dictionary = s.towns_of(0)[0]
	for m in s.state.map.objects.values():
		if m["type"] == "mine":
			m["owner"] = 0
	var b := s.income_breakdown(0)
	var daily := s.daily_income(0)
	for res in data.resource_order:
		assert_eq(int(b[res]["total"]), int(daily.get(res, 0)), res)
		if s.current_omen().is_empty() or WorldEvents.income_pct(s.state, data, res) == 0.0:
			assert_eq(_sum(b[res]), int(b[res]["total"]), "%s sources add up" % res)
	var labels: Array = b["gold"]["sources"].map(func(x): return String(x[0]))
	assert_true(labels.has(String(town["name"])), "the town pays gold")


func test_mines_of_one_kind_are_grouped() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var mines := s.state.map.objects.values().filter(func(o): return o["type"] == "mine" and o["resource"] == "ore")
	assert_false(mines.is_empty())
	var first: Dictionary = mines[0]
	var twin := first.duplicate(true)
	twin["id"] = "test_twin_mine"
	var p := s._free_tile_near(AdventureMap.object_pos(first))
	twin["pos"] = [p.x, p.y]
	s.state.map.add_object(twin)
	first["owner"] = 0
	twin["owner"] = 0
	var lines: Array = s.income_breakdown(0)["ore"]["sources"]
	var name := Economy.mine_name(first, data)
	var found := lines.filter(func(x): return String(x[0]) == "2× " + name)
	assert_eq(found.size(), 1, str(lines))
	assert_eq(String(found[0][1]), "%+d" % (2 * Economy.mine_income(first, data)))


func test_no_income_says_so() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var b := s.income_breakdown(0)
	var res := ""
	for r in data.resource_order:
		if int(b[r]["total"]) == 0:
			res = r
	if res == "":
		return
	assert_true((b[res]["sources"] as Array).is_empty())
	assert_true(Hud.income_tooltip("Crystal", 3, b[res]).contains("No daily income"))


func test_tooltip_lists_total_and_sources() -> void:
	var tip := Hud.income_tooltip("Gold", 7500, {"total": 1250, "sources": [["Greyhold", "+1000"], ["Ore Pit", "+250"]]})
	assert_true(tip.contains("7500"))
	assert_true(tip.contains("+1250 a day"))
	assert_true(tip.contains("+1000  Greyhold"))
	assert_true(tip.contains("+250  Ore Pit"))


func test_computer_difficulty_shows_as_a_percentage() -> void:
	var s := GameSession.new_game(data, "mournfield", 5, {"players": [
		{"type": "human", "faction": "concord"}, {"type": "computer", "faction": "ashen", "difficulty": "hard"},
		{"type": "closed", "faction": "ashen"}, {"type": "closed", "faction": "concord"}]})
	var lines: Array = s.income_breakdown(1)["gold"]["sources"]
	var pct := int(data.difficulty("hard")["income_percent"]) - 100
	assert_true(lines.any(func(x): return String(x[1]) == "%+d%%" % pct), str(lines))
	assert_false(s.income_breakdown(0)["gold"]["sources"].any(func(x): return String(x[1]).ends_with("%") and String(x[0]).contains("difficulty")))
