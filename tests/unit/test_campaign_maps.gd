extends "res://tests/test_case.gd"
## The Ashen chapters of The Last Light (8-10, the old Ember Chronicle): each
## map is valid, sets the veterans against an Ashen enemy, and the enemy grows
## stronger from chapter to chapter.

const FIRST := 7


func _chapters() -> Array:
	return (data.campaigns["last_light"]["chapters"] as Array).slice(FIRST)


func test_each_chapter_has_its_own_valid_map() -> void:
	var seen := {}
	for ch in _chapters():
		var mid := String(ch["map"])
		assert_false(seen.has(mid), "chapter %s reuses map %s" % [ch["id"], mid])
		seen[mid] = true
		var def := data.load_map(mid)
		assert_false(def.is_empty(), "map %s loads" % mid)
		assert_eq(MapValidator.validate(def, data), [] as Array[String], "map %s validates" % mid)


func test_veterans_face_an_ashen_computer_player() -> void:
	for ch in _chapters():
		var def := data.load_map(String(ch["map"]))
		var owners := {}
		for hd in def["heroes"]:
			owners[hd["id"]] = int(hd["owner"])
		for vid in ["hero_wren", "hero_maelis"]:
			assert_eq(owners.get(vid, -1), 0, "%s leads player 0 in %s" % [vid, ch["id"]])
		var enemies: Array = def["players"].filter(func(p: Dictionary) -> bool: return int(p["id"]) != 0)
		assert_eq(enemies.size(), 1, "%s has one enemy player" % ch["id"])
		assert_eq(String(enemies[0]["faction"]), "ashen")
		assert_false(bool(enemies[0]["is_human"]))
		assert_true(owners.values().has(int(enemies[0]["id"])), "%s enemy has a hero" % ch["id"])


func test_every_chapter_begins() -> void:
	var c := Campaign.start(data, "last_light", 4)
	for i in _chapters().size():
		c.chapter = FIRST + i
		var s := c.begin_chapter(data)
		assert_true(s != null, "chapter %d starts" % i)
		assert_eq(s.towns_of(1).size() > 0, true, "enemy holds a town in chapter %d" % i)
		assert_eq(s.hero("hero_wren").owner, 0)


## Opposition in gold value: enemy hero armies and enemy town garrisons plus 300
## per enemy building. Neutral guards are left out: on generated maps they scale
## with the map's area and the ground they stand on, not with the story's enemy.
func _enemy_strength(map_id: String) -> float:
	var s := GameSession.new_game(data, map_id, 1)
	var ai := StrategicAI.new(s, 0)
	var total := 0.0
	var def := data.load_map(map_id)
	for hd in def["heroes"]:
		if int(hd["owner"]) == 1:
			total += ai.army_value(Army.from_pairs(hd["army"]))
	for o in def["objects"]:
		if o["type"] == "town" and int(o.get("owner", -1)) == 1:
			total += ai.army_value(Army.from_pairs(o.get("garrison", []))) + 300.0 * o.get("built", []).size()
	return total


func test_enemy_strength_escalates() -> void:
	var last := 0.0
	var last_heroes := 0
	for ch in _chapters():
		var def := data.load_map(String(ch["map"]))
		var heroes: int = def["heroes"].filter(func(hd: Dictionary) -> bool: return int(hd["owner"]) == 1).size()
		assert_true(heroes >= last_heroes, "%s fields at least as many enemy heroes" % ch["id"])
		last_heroes = heroes
		var v := _enemy_strength(String(ch["map"]))
		assert_gt(v, last * 1.3, "%s enemy (%d) clearly stronger than the chapter before (%d)" % [ch["id"], v, last])
		last = v
