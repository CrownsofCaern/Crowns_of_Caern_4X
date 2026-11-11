extends "res://tests/test_case.gd"
## The Concord campaign "The Last Light": ten chapters, the story's enemy in
## each, units unlocking tier by tier, and a tutorial first chapter that a
## player can win against a passive opponent.

## Enemy factions per chapter (computer players not allied with the Concord at
## the start, in slot order), the allies of the 2v2 and betrayal chapters, the
## townless chapter and the slots that only send waves (map overhaul, Nov 9).
const ENEMIES := [["hollow"], ["hollow"], ["hollow"], ["hollow"], ["forge", "forge"], ["thornwood", "thornwood"], ["frostmarch"], ["ashen"], ["ashen"], ["ashen"]]
const ALLIES := {4: ["forge"], 6: ["frostmarch"]}
const TOWNLESS := [2]
const INVADERS := {5: [2]}
const TIERS := [2, 3, 3, 4, 5, 5, 6, 7, 8, 8]


func _chapters() -> Array:
	return data.campaigns["last_light"]["chapters"]


func test_ten_chapters_with_the_tier_schedule() -> void:
	assert_eq(_chapters().size(), 10)
	var tiers := []
	for ch in _chapters():
		tiers.append(int(ch.get("max_tier", 0)))
	assert_eq(tiers, TIERS, "tier 8 only on the last two maps, tier 7 one map earlier and so on")
	for ch in _chapters():
		assert_false(String(ch.get("intro", "")).is_empty(), "%s has a story intro" % ch["id"])
		assert_false(String(ch.get("outro", "")).is_empty(), "%s has a story outro" % ch["id"])


func test_hand_made_maps_validate() -> void:
	for mid in ["greyhold_harvest", "knight_who_came_back", "ll_barrow_roads", "ll_lanterns", "ll_doors", "ll_stumps", "ll_red_sky"]:
		var def := data.load_map(mid)
		assert_false(def.is_empty(), "%s loads" % mid)
		assert_eq(MapValidator.validate(def, data), [] as Array[String], "%s validates" % mid)


func test_every_chapter_begins_against_its_story_enemy() -> void:
	var c := Campaign.start(data, "last_light", 4)
	for i in _chapters().size():
		c.chapter = i
		var s := c.begin_chapter(data)
		var cid: String = _chapters()[i]["id"]
		assert_true(s != null, "%s starts" % cid)
		assert_eq(s.state.player(0)["faction"], "concord")
		assert_true(bool(s.state.player(0)["is_human"]))
		var enemies := []
		var allies := []
		for p in range(1, s.state.players.size()):
			assert_false(bool(s.state.player(p)["is_human"]))
			if s.state.allied(0, p):
				allies.append(s.state.player(p)["faction"])
				assert_gt(float(s.towns_of(p).size()), 0.0, "%s ally %d holds a town" % [cid, p])
			else:
				enemies.append(s.state.player(p)["faction"])
				if not INVADERS.get(i, []).has(p):
					assert_gt(float(s.towns_of(p).size()), 0.0, "%s enemy %d holds a town" % [cid, p])
		assert_eq(enemies, ENEMIES[i], "%s enemies" % cid)
		assert_eq(allies, ALLIES.get(i, []), "%s allies" % cid)
		if TOWNLESS.has(i):
			assert_eq(s.towns_of(0).size(), 0, "%s the Concord starts without a town" % cid)
		else:
			assert_gt(float(s.towns_of(0).size()), 0.0, "%s the Concord holds a town" % cid)
		assert_eq(s.tier_cap(), TIERS[i])
		var wren := s.hero("hero_wren")
		assert_true(wren != null and wren.owner == 0, "%s Aldous Wren leads" % cid)
		for hid in ["hero_maelis", "hero_edda"]:
			var h := s.hero(hid)
			if h != null:
				assert_eq(h.owner, 0)
				assert_true(s.state.map.is_passable(h.pos), "%s %s stands on open ground" % [cid, hid])
		assert_eq(s.hero("hero_edda") != null, i >= 2, "%s: Edda Vey joins in chapter 3" % cid)
		# The Concord starts at or under its cap.
		for id in s.state.heroes:
			var h: Hero = s.state.heroes[id]
			if h.owner != 0:
				continue
			for st in h.army.slots:
				if not st.is_empty():
					assert_true(int(data.creature(st["creature"])["tier"]) <= TIERS[i], "%s %s starts within the cap" % [cid, id])


func test_tutorial_opponent_is_passive() -> void:
	var ch: Dictionary = _chapters()[0]
	assert_true(bool(ch["ai"]["passive"]))
	assert_false(bool(ch["ai"]["builds"]))
	assert_false(bool(ch["ai"]["recruits"]))


func test_tutorial_can_be_won() -> void:
	var c := Campaign.start(data, "last_light", 7)
	var s := c.begin_chapter(data)
	# The stand-in player knows the dead stay home (a human reads it in the
	# briefing), so it does not hold Greyhold against a threat that never comes.
	# The chapter's "ai" rules make every computer player passive, so the
	# stand-in switches them back off for itself.
	var bold := {"threat_days": 0.0, "danger_days": 0.0, "passive": false, "builds": true, "recruits": true}
	# It has also scouted the fen: the AI assumes an unseen enemy hero is as
	# strong as its whole army and would never march on an unscouted camp.
	s.state.player(0)["fog"].reveal(Vector2i(11, 6), 30)
	var notes := []
	for _day in 40:
		if s.state.game_over:
			break
		var player := StrategicAI.new(s, 0, bold)
		var rep := player.play_turn()
		if s.state.day % 5 == 0:
			var wren := s.hero("hero_wren")
			notes.append("day %d: wren %s army %d, battles %d, towns %d/%d; %s" % [s.state.day, wren.pos, wren.army.total_creatures(),
				int(rep["battles"]), s.towns_of(0).size(), s.towns_of(1).size(), " / ".join(player.actions.slice(-4))])
		s.end_turn()
		StrategicAI.play_ai_turns(s, 4)
	assert_true(s.state.game_over, "a plain player wins the tutorial within 40 days\n" + "\n".join(notes))
	assert_eq(s.state.winner, 0)
