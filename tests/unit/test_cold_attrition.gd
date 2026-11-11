extends "res://tests/test_case.gd"
## Cold attrition (ColdAttrition): armies whose faction counts the snowfield as
## hostile lose a share of every stack each day they stand on snow, unless the
## hero ignores hostile terrain.

const SPEAR := "fm_brine_spear"
const PIKE := "pike_militia"
const GUARD := "fm_reef_guard"

var _saved_hostile: Array = []


func _session(rules: Dictionary = {"cold_attrition": true}) -> GameSession:
	var s := GameSession.new_game(data, "ember_ford", 11, {}, rules)
	var h := s.hero("hero_wren")
	h.army = Army.new()
	h.army.add(SPEAR, 30)
	h.army.add(PIKE, 20)
	h.army.add(GUARD, 1)
	h.boons = []
	_put_on(s, h, "snow")
	return s


func _put_on(s: GameSession, h: Hero, terrain: String) -> void:
	s.state.map.terrain[s.state.map.index(h.pos)] = terrain


func _count(h: Hero, creature: String) -> int:
	var n := 0
	for st in h.army.slots:
		if not st.is_empty() and st["creature"] == creature:
			n += int(st["count"])
	return n


func _next_day(s: GameSession) -> void:
	for i in s.state.players.size():
		s.end_turn()
		if s.state.current_player == 0:
			break


func _with_cold_shoal(body: Callable) -> void:
	var fac: Dictionary = data.factions["fishmen"]
	_saved_hostile = (fac.get("hostile_terrain", []) as Array).duplicate()
	fac["hostile_terrain"] = ["snow"]
	body.call()
	fac["hostile_terrain"] = _saved_hostile


func test_rule_data_is_valid() -> void:
	assert_true(data.rules.has("cold_attrition_pct"))
	assert_true(ColdAttrition.is_cold("snow", data))
	assert_false(ColdAttrition.is_cold("swamp", data))


func test_loss_rounds_up_and_keeps_one() -> void:
	assert_eq(ColdAttrition.loss(30, data), 3)
	assert_eq(ColdAttrition.loss(31, data), 4, "rounded up")
	assert_eq(ColdAttrition.loss(5, data), 1)
	assert_eq(ColdAttrition.loss(2, data), 1)
	assert_eq(ColdAttrition.loss(1, data), 0, "never below one creature")


func test_shoal_freezes_on_snow() -> void:
	_with_cold_shoal(func():
		var s := _session()
		var h := s.hero("hero_wren")
		_next_day(s)
		assert_eq(_count(h, SPEAR), 27, "the 30 stack loses 3")
		assert_eq(_count(h, GUARD), 1, "a stack of one keeps its last creature")
		assert_eq(_count(h, PIKE), 20, "Concord pikes do not mind snow")
		var news := s.take_news(0)
		var found := false
		for line in news:
			if String(line).begins_with(ColdAttrition.NEWS_PREFIX):
				found = true
		assert_true(found, "the player is told")
		_next_day(s)
		assert_eq(_count(h, SPEAR), 24, "it keeps biting every day"))


func test_no_cold_off_snow() -> void:
	_with_cold_shoal(func():
		var s := _session()
		var h := s.hero("hero_wren")
		_put_on(s, h, "swamp")
		_next_day(s)
		assert_eq(_count(h, SPEAR), 30))


func test_ignore_hostile_terrain_protects() -> void:
	_with_cold_shoal(func():
		var s := _session()
		var h := s.hero("hero_wren")
		h.add_boon("test_warmth", "Warmth", 999, {"ignore_hostile_terrain": 1})
		assert_eq(ColdAttrition.preview(h, s.state, data), [])
		_next_day(s)
		assert_eq(_count(h, SPEAR), 30, "a warm hero loses nothing"))


## Gives the hero an artifact and makes sure it is worn (give_artifact wears it
## at once when the slot is empty, otherwise it goes to the pack first).
func _wear(h: Hero, artifact_id: String) -> void:
	assert_true(h.give_artifact(artifact_id, data), artifact_id)
	if h.pack.has(artifact_id):
		assert_true(h.equip(artifact_id, data), artifact_id)
	assert_eq(String(h.equipment.get(data.artifacts[artifact_id]["slot"], "")), artifact_id, artifact_id + " is worn")


func test_forgewarm_set_protects_when_present() -> void:
	if not data.artifact_sets.has("forgewarm"):
		return   # the set's data comes with the Drowned Oath campaign
	_with_cold_shoal(func():
		var s := _session()
		var h := s.hero("hero_wren")
		var pieces: Array = data.artifact_sets["forgewarm"]["pieces"]
		_wear(h, String(pieces[0]))
		assert_false(ColdAttrition.preview(h, s.state, data).is_empty(), "one piece is not enough")
		_wear(h, String(pieces[1]))
		assert_eq(ColdAttrition.preview(h, s.state, data), [], "two pieces keep the army warm"))


func test_hero_in_town_is_sheltered() -> void:
	_with_cold_shoal(func():
		var s := _session()
		var h := s.hero("hero_wren")
		var t := s.town("town_greyhold")
		h.pos = Vector2i(int(t["pos"][0]), int(t["pos"][1]))
		_put_on(s, h, "snow")
		assert_eq(ColdAttrition.preview(h, s.state, data), []))


func test_garrisons_are_exempt() -> void:
	_with_cold_shoal(func():
		var s := _session()
		var t := s.town("town_greyhold")
		var tp := Vector2i(int(t["pos"][0]), int(t["pos"][1]))
		s.state.map.terrain[s.state.map.index(tp)] = "snow"
		t["garrison"] = Army.from_pairs([[SPEAR, 30]]).to_dict()
		_next_day(s)
		assert_eq(int(t["garrison"][0]["count"]), 30))


func test_skirmish_default_is_off() -> void:
	_with_cold_shoal(func():
		var s := _session({})
		assert_false(ColdAttrition.enabled(s.state, data))
		_next_day(s)
		assert_eq(_count(s.hero("hero_wren"), SPEAR), 30))


func test_campaign_default_is_on_and_chapter_can_turn_it_off() -> void:
	var s := _session({})
	s.state.campaign = {"id": "drowned_oath"}
	assert_true(ColdAttrition.enabled(s.state, data), "campaign games play with cold")
	assert_false(Campaign.chapter_rules({}).has("cold_attrition"))
	var rules := Campaign.chapter_rules({"cold_attrition": false})
	assert_eq(rules["cold_attrition"], false)
	s.state.rules["cold_attrition"] = false
	assert_false(ColdAttrition.enabled(s.state, data), "a chapter can turn it off")


func test_deterministic() -> void:
	_with_cold_shoal(func():
		var a := _session()
		var b := _session()
		_next_day(a)
		_next_day(b)
		assert_eq(a.hero("hero_wren").army.to_dict(), b.hero("hero_wren").army.to_dict()))
