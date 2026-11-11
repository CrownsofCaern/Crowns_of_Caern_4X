extends "res://tests/test_case.gd"
## How the battle lines meet (room between figures, charges, shoves, strike
## on contact) and how the effects are paced (lanes spread over a round,
## brawl hits, lingering element effects). Presentation only.


func test_figures_keep_room_foes_at_arms_length() -> void:
	assert_eq(BattleViewer.room_push(Vector2(80, 0), 60.0, true), Vector2.ZERO, "far apart: no push")
	var friend := BattleViewer.room_push(Vector2(20, 0), 60.0, false)
	var foe := BattleViewer.room_push(Vector2(20, 0), 60.0, true)
	assert_gt(friend.x, 0.0, "crowding friends are eased apart")
	assert_gt(foe.x, friend.x, "foes need more room than friends")
	assert_eq(BattleViewer.room_push(Vector2(40, 0), 60.0, false), Vector2.ZERO, "friends stand shoulder to shoulder")
	assert_gt(BattleViewer.room_push(Vector2(40, 0), 60.0, true).x, 0.0, "but foes do not")
	# Ranks one behind the other (depth) may stand closer than side by side.
	assert_eq(BattleViewer.room_push(Vector2(0, 30), 60.0, true), Vector2.ZERO, "a rank behind has room")
	var stacked := BattleViewer.room_push(Vector2.ZERO, 60.0, false)
	assert_ne(stacked, Vector2.ZERO, "two figures on one spot are split")
	# The push closes exactly the missing room.
	var gap := Vector2(10, 0)
	var after := gap + BattleViewer.room_push(gap, 60.0, true)
	assert_lt(absf(after.x - 60.0 * BattleViewer.ROOM_FOE), 0.01)


func test_crowded_figures_drift_apart() -> void:
	var v := BattleViewer.new()
	var a := BattleFigure.new()
	a.key = "0:0"
	a.setup("pike_militia", 1, 1.0, 0.0)
	var b := BattleFigure.new()
	b.key = "1:0"
	b.setup("flayer", 1, -1.0, 0.0)
	a.position = Vector2(400, 300)
	b.position = Vector2(404, 300)
	v._figs = {"0:0": a, "1:0": b}
	for k in 30:
		v._keep_room(1.0 / 30.0)
	var apart := b.member_pos(0).x - a.member_pos(0).x
	assert_gt(apart, (a.member_radius() + b.member_radius()) * BattleViewer.ROOM_FOE - 2.0, "the foes stand at arm's length")
	assert_true(a.arrived([0]) and b.arrived([0]), "their places move with them, so they do not walk back in")
	a.free()
	b.free()
	v.free()


func test_shove_throws_back_then_steps_in() -> void:
	assert_eq(BattleFigure.shove_curve(-0.1), 0.0)
	assert_eq(BattleFigure.shove_curve(0.0), 0.0)
	assert_gt(BattleFigure.shove_curve(0.09), 0.95, "thrown back fast")
	assert_lt(BattleFigure.shove_curve(0.3), BattleFigure.shove_curve(0.12), "then steps back in")
	assert_eq(BattleFigure.shove_curve(BattleFigure.SHOVE_SECONDS), 0.0, "back in place")
	var f := BattleFigure.new()
	f.key = "1:2"
	f.setup("pike_militia", 40, -1.0, 0.0)
	var home := f.members[0].position
	f.shove([0], 12.0)
	f._process(0.09)
	assert_gt(f.members[0].position.x, home.x + 5.0, "the shoved figure gives ground")
	for k in 10:
		f._process(0.1)
	assert_lt(absf(f.members[0].position.x - home.x), 4.0, "and comes back")
	f.free()


func test_a_charge_runs_faster_and_knows_when_it_lands() -> void:
	var f := BattleFigure.new()
	f.key = "0:4"
	f.setup("lancer", 6, 1.0, 0.0)
	var start := f.member_pos(0)
	f.send(0, start + Vector2(300, 0), 1.0, 0.0, 1.5)
	var walk_eta := 300.0 / (BattleFigure.WALK_PX * f._pace[0])
	assert_lt(absf(f.eta([0]) - walk_eta / 1.5), 0.01, "a charge sprints")
	f.send(1, f.member_pos(1) + Vector2(300, 0), 1.0, 0.5)
	assert_gt(f.eta([0, 1]), f.eta([0]), "the eta waits for the last figure, late start included")
	for k in 30:
		f._process(0.1)
	assert_eq(f.eta([0, 1]), 0.0, "there")
	assert_eq(f._rush[0], 1.0, "the sprint ends on arrival")
	f.free()


func test_brawl_swings_announce_their_blow() -> void:
	var f := BattleFigure.new()
	f.key = "0:0"
	f.setup("pike_militia", 40, 1.0, 0.0)
	var hits := []
	f.brawl_hit.connect(func(fig: BattleFigure, i: int): hits.append(i))
	f.set_brawling([0], true)
	for k in 60:
		f._process(0.1)
	assert_gt(float(hits.size()), 1.0, "a brawler lands swings between the logged blows")
	assert_false(hits.has(1), "only brawlers swing")
	hits.clear()
	f.set_brawling([0], false)
	f.start_attack([2])
	for k in 20:
		f._process(0.1)
	assert_eq(hits, [], "a logged blow is not a brawl swing")
	f.free()


func test_lanes_spread_over_the_round() -> void:
	assert_eq(BattleViewer.lane_delay(0, 1), 0.0)
	assert_eq(BattleViewer.lane_delay(0, 6), 0.0, "the first stack strikes at once")
	assert_gt(BattleViewer.lane_delay(1, 3), 0.3, "few lanes stand well apart")
	var last := BattleViewer.lane_delay(15, 16)
	assert_lt(last, 2.7, "many lanes still fit in the round")
	assert_gt(last, 2.0)
	for n in 15:
		assert_gt(BattleViewer.lane_delay(n + 1, 16), BattleViewer.lane_delay(n, 16))


func test_elements_linger_and_small_hits_do_not_flash() -> void:
	var root := Node2D.new()
	assert_eq(BattleFx.linger(root, Vector2.ZERO, "storm"), null, "storms leave nothing")
	var embers := BattleFx.linger(root, Vector2.ZERO, "fire")
	assert_true(embers != null and embers.emitting, "fire leaves embers")
	assert_eq(String(embers.get_meta("element")), "fire")
	var before := root.get_child_count()
	BattleFx.burst(root, Vector2.ZERO, "fire", 0.4)
	assert_eq(root.get_child_count(), before + 1, "a small hit is particles only")
	BattleFx.burst(root, Vector2.ZERO, "fire", 1.0)
	assert_eq(root.get_child_count(), before + 3, "a full blow flashes too")
	assert_gt(float(BattleGore.contact(root, Vector2.ZERO, 1.0).amount), float(BattleGore.contact(root, Vector2.ZERO, 0.0).amount), "a charge throws more sparks")
	assert_gt(float(BattleGore.nick(root, Vector2.ZERO, "blood", 1.0).amount), 0.0)
	root.free()


func test_burning_creatures_strike_with_fire() -> void:
	for id in ["scorchhound", "pyre_titan", "cinder_maw"]:
		assert_eq(BattleFx.element_of(id), "fire", id)
	assert_eq(BattleFx.element_of("lightbearer"), "holy")
	assert_eq(BattleFx.element_of("pike_militia"), "", "plain soldiers keep plain blows")


func test_march_is_one_steady_walk_paced_to_the_first_fight() -> void:
	var walk := 150.0
	# 300 px in 4 s at 150 px/s: half pace, all the way.
	assert_lt(absf(BattleViewer.march_pace(300.0, 4.0, walk) - 0.5), 0.001)
	assert_eq(BattleViewer.march_pace(300.0, 1.0, walk), 1.0, "late: a full walk (the engage runs the rest)")
	assert_eq(BattleViewer.march_pace(30.0, 10.0, walk), 0.0, "far too early: waits instead of wading")
	var slow := BattleViewer.march_pace(160.0, 4.0, walk)
	assert_true(slow == 0.0 or slow >= BattleViewer.MARCH_MIN_PACE, "never slower than the slowest march")
	assert_eq(BattleViewer.march_pace(1.0, 4.0, walk), 1.0, "already there")
	var plan := BattleViewer.march_plan(30.0, 10.0, walk)
	assert_lt(absf(plan.x - BattleViewer.MARCH_MIN_PACE), 0.0001, "with time to spare: the slowest steady march...")
	assert_lt(absf(plan.y + 30.0 / (BattleViewer.MARCH_MIN_PACE * walk) - 10.0), 0.001, "...setting off late enough to arrive on time")


func test_a_held_line_stays_and_is_met_where_it_stands() -> void:
	var v := BattleViewer.new()
	v._replay = BattleReplay.new()
	v._replay.stacks = [[{"key": "0:0"}], [{"key": "1:0"}]]
	var a := BattleFigure.new()
	a.key = "0:0"
	a.formation = "front"
	a.setup("pike_militia", 4, 1.0, 0.0)
	var b := BattleFigure.new()
	b.key = "1:0"
	b.formation = "front"
	b.setup("flayer", 4, -1.0, 0.0)
	v._figs = {"0:0": a, "1:0": b}
	v._start_home = {"0:0": Vector2(300, 300), "1:0": Vector2(900, 300)}
	v._orders = [{"stance": "defensive"}, {}]
	assert_true(v._holds(0) and not v._holds(1))
	assert_eq(v._held_side(), 0)
	assert_eq(v._contact_x(0), 300.0, "the holder's contact line is its own front")
	assert_gt(v._contact_x(1), 300.0, "the attackers come all the way to it")
	v._orders = [{"stance": "defensive"}, {"formation": "wedge"}]
	assert_eq(v._held_side(), 0, "a wedge does not hold")
	v._orders = [{"stance": "defensive", "formation": "wedge"}, {}]
	assert_eq(v._held_side(), -1, "a wedge outweighs a defensive stance")
	v._orders = [{"formation": "shield_wall"}, {"stance": "defensive"}]
	assert_eq(v._held_side(), -1, "both hold: the lines meet in the middle")
	a.free()
	b.free()
	v.free()


func test_figures_fight_any_foe_in_reach_and_face_it() -> void:
	var v := BattleViewer.new()
	var giant := BattleFigure.new()
	giant.key = "0:0"
	giant.setup("pike_militia", 1, 1.0, 0.0)
	var foe := BattleFigure.new()
	foe.key = "1:0"
	foe.setup("flayer", 1, -1.0, 0.0)
	giant.position = Vector2(400, 300)
	foe.position = Vector2(400, 300 + giant.figure_width * 0.5)
	v._figs = {"0:0": giant, "1:0": foe}
	v._fight_in_reach()
	assert_true(giant.is_brawling(0), "a foe at its side: it fights, paired or not")
	assert_true(foe.is_brawling(0))
	assert_ne(giant._aim[0], Vector2.ZERO, "and squares up to it")
	foe.position = Vector2(2000, 300)
	v._fight_in_reach()
	assert_false(giant.is_brawling(0), "the foe gone: it stops swinging at air")
	giant.free()
	foe.free()
	v.free()


func test_live_figures_only_take_a_breath_between_brawl_swings() -> void:
	assert_lt(BattleFigure.brawl_pause(0.99, true), BattleFigure.brawl_pause(0.0, false), "3D brawlers barely pause")
	assert_lt(BattleFigure.brawl_pause(0.99, true), 0.6)


func test_director_surrounds_a_giant_with_its_attackers() -> void:
	assert_eq(BattleDirector.room_for(20.0, 20.0), 2, "same size: two on one")
	assert_gt(BattleDirector.room_for(70.0, 20.0), 4, "a giant has room for many")
	# Attackers from the left stand left of their foe, spread round it.
	var foe := Vector2(500, 300)
	var first := BattleDirector.place(foe, 0, 0, 60.0)
	assert_lt(first.x, foe.x, "the first attacker faces it from its own army's side")
	assert_lt(absf(first.y - foe.y), 0.5)
	var second := BattleDirector.place(foe, 1, 0, 60.0)
	var third := BattleDirector.place(foe, 2, 0, 60.0)
	assert_lt((second.y - foe.y) * (third.y - foe.y), 0.0, "the next ones fan out to either side of it")
	assert_lt(second.x, foe.x)
	assert_gt(BattleDirector.place(foe, 0, 1, 60.0).x, foe.x, "the other army comes from the right")

	var v := BattleViewer.new()
	var men := BattleFigure.new()
	men.key = "0:0"
	men.setup("pike_militia", 40, 1.0, 0.0)
	var giant := BattleFigure.new()
	giant.key = "1:0"
	giant.setup("flayer", 1, -1.0, 0.0)
	giant.figure_width = men.figure_width * 3.0
	men.position = Vector2(300, 300)
	giant.position = Vector2(420, 300)
	var d := BattleDirector.new()
	d.step({"0:0": men, "1:0": giant}, {"0:0": true, "1:0": true}, {"0:0": {"1:0": []}, "1:0": {"0:0": []}}, -1)
	var on_giant := 0
	for k in d.duels:
		if String(k).begins_with("0:0#"):
			on_giant += 1
	assert_eq(on_giant, BattleDirector.room_for(giant.member_radius(), men.member_radius()), "as many men as fit take on the giant")
	for k in 40:
		men._process(0.1)
		d.step({"0:0": men, "1:0": giant}, {"0:0": true, "1:0": true}, {"0:0": {"1:0": []}, "1:0": {"0:0": []}}, -1)
	var busy := 0
	for k in d.duels:
		if String(k).begins_with("0:0#") and men.is_brawling(int(String(k).get_slice("#", 1))):
			busy += 1
	assert_eq(busy, on_giant, "every attacker fights the giant from its place")
	assert_true(d.duels.has("1:0#0") and giant.is_brawling(0), "and the giant fights back")
	assert_lt(giant.member_pos(0).distance_to(Vector2(420, 300) + giant._slot(0, 1)), 3.0, "standing its ground while they come to it")
	d.step({"0:0": men, "1:0": giant}, {"0:0": true}, {"0:0": {"1:0": []}}, -1)
	assert_true(d.duels.has("0:0#0") or not d.duels.is_empty(), "duels stand while the battalion is engaged")
	d.step({"0:0": men, "1:0": giant}, {}, {}, -1)
	assert_true(d.duels.is_empty(), "and end with the fight")
	men.free()
	giant.free()
	v.free()


func test_a_hit_throws_a_3d_body_back_and_it_recovers() -> void:
	assert_eq(LiveUnit.flinch_curve(-0.1), 0.0)
	assert_gt(LiveUnit.flinch_curve(0.07), 0.95, "thrown back at once")
	assert_lt(LiveUnit.flinch_curve(0.3), LiveUnit.flinch_curve(0.1), "then recovers")
	assert_eq(LiveUnit.flinch_curve(LiveUnit.FLINCH_SECONDS), 0.0)


func test_attackers_of_a_long_body_take_its_head_and_flanks() -> void:
	var at := Vector2(500, 300)
	var ext := Vector2(120, 25)
	var head := BattleDirector.flank_place(at, ext, 1.0, 0, 20.0)
	assert_gt(head.x, at.x + ext.x, "the first takes on the head, past its snout")
	var a := BattleDirector.flank_place(at, ext, 1.0, 1, 20.0)
	var b := BattleDirector.flank_place(at, ext, 1.0, 2, 20.0)
	assert_lt((a.y - at.y) * (b.y - at.y), 0.0, "the next stand on either flank")
	assert_gt(absf(a.y - at.y) * BattleDirector.DEPTH, ext.y, "beside the body, not on its back")
	assert_lt(BattleDirector.flank_place(at, ext, -1.0, 0, 20.0).x, at.x - ext.x, "the head is where it faces")


func test_duel_places_hold_when_a_comrade_falls() -> void:
	var men := BattleFigure.new()
	men.key = "0:0"
	men.setup("pike_militia", 40, 1.0, 0.0)
	var giant := BattleFigure.new()
	giant.key = "1:0"
	giant.setup("flayer", 1, -1.0, 0.0)
	giant.figure_width = men.figure_width * 3.0
	men.position = Vector2(300, 300)
	giant.position = Vector2(420, 300)
	var figs := {"0:0": men, "1:0": giant}
	var eng := {"0:0": true, "1:0": true}
	var groups := {"0:0": {"1:0": []}, "1:0": {"0:0": []}}
	var d := BattleDirector.new()
	for k in 30:
		men._process(0.1)
		d.step(figs, eng, groups, -1)
	var slots := {}
	for k in d.duels:
		if String(k).begins_with("0:0#"):
			slots[k] = d.duels[k][2]
	var first: String = slots.keys()[0]
	men.apply_count(men.count - 1, [int(first.get_slice("#", 1))], 1.0, false)
	d.step(figs, eng, groups, -1)
	for k in slots:
		if k != first and d.duels.has(k):
			assert_eq(d.duels[k][2], slots[k], "the others keep their places")
	var spare := 0
	for i in men.alive_members():
		if not d.duels.has("0:0#%d" % i) and not men.is_brawling(i):
			spare += 1
	assert_gt(spare, 0, "spare men wait behind without swinging at air")
	men.free()
	giant.free()


func test_block_rows_follow_the_death_order_of_the_log() -> void:
	var replay := BattleReplay.new()
	replay.steps = [
		{"kind": BattleReplay.MELEE, "actor": "1:0", "target": "0:0", "actor_count": 10, "target_count": 8},
		{"kind": BattleReplay.MELEE, "actor": "1:0", "target": "0:0", "actor_count": 10, "target_count": 5},
	]
	var deaths := BattleViewer.death_steps(replay, "0:0", 10, 10)
	assert_eq(deaths.get(9), 0, "the last figures fall first")
	assert_eq(deaths.get(8), 0)
	assert_eq(deaths.get(7), 1)
	assert_eq(deaths.get(5), 1)
	assert_false(deaths.has(4), "survivors never fall")
	assert_true(BattleViewer.death_steps(replay, "1:0", 10, 10).is_empty())


func test_a_melee_block_is_square_ish_with_the_doomed_in_front() -> void:
	var v := BattleViewer.new()
	v._ground = Rect2(0, 100, 1280, 500)
	var f := BattleFigure.new()
	f.key = "0:0"
	f.setup("pike_militia", 40, 1.0, 0.0)
	v._figs = {"0:0": f}
	var order := []
	for i in range(f.members.size() - 1, -1, -1):
		order.append(["0:0", i, i])
	v._blocks = [order, []]
	v._block_front[0] = 600.0
	var spots := v.block_spots(0)
	assert_eq(spots.size(), f.members.size())
	var first: Vector2 = spots["0:0#%d" % (f.members.size() - 1)]
	var last: Vector2 = spots["0:0#0"]
	assert_gt(first.x, last.x, "the first to fall stand in front (side 0 faces right)")
	assert_lt(first.x, 600.0, "behind the front edge")
	var xs := {}
	for k in spots:
		xs[int(round(spots[k].x))] = true
	assert_gt(xs.size(), 1, "more than one row")
	f.free()
	v.free()


func test_flankers_fight_a_block_only_at_its_edge_from_outside() -> void:
	var v := BattleViewer.new()
	v._ground = Rect2(0, 100, 1280, 500)
	var f := BattleFigure.new()
	f.key = "1:0"
	f.setup("pike_militia", 40, -1.0, 0.0)
	v._figs = {"1:0": f}
	var order := []
	for i in f.members.size():
		order.append(["1:0", i, i])
	v._blocks = [[], order]
	v._block_front[1] = 600.0
	var spots := v.block_spots(1)
	for i in f.members.size():
		f.place_member(i, spots["1:0#%d" % i], -1.0)
	var inner := 0
	for k in spots:
		if not v._block_edge.has(k):
			inner += 1
	assert_gt(inner, 0, "a block has figures inside, off every edge")
	assert_eq(v._block_edge.get("1:0#0"), Vector2(-1.0, 0.0), "the front row faces the foe (side 1 faces left)")
	# Riders come at the block from above it.
	var riders := BattleFigure.new()
	riders.key = "0:1"
	riders.setup("pike_militia", 4, 1.0, 0.0)
	riders.position = Vector2(700, 120)
	var d := BattleDirector.new()
	var figs := {"1:0": f, "0:1": riders}
	d.step(figs, {"0:1": true, "1:0": true}, {"0:1": {"1:0": []}, "1:0": {"0:1": []}}, -1, {"1:0": true}, v._block_edge)
	assert_false(d.duels.is_empty(), "the riders find foes")
	for k in d.duels:
		var foe: Array = d.duels[k]
		assert_true(v._block_edge.has("%s#%d" % [foe[0], foe[1]]), "only figures on the block's edge are fought")
	assert_true(BattleDirector.edge_place(Vector2(600, 300), Vector2(0, -1), 0, 40.0).y < 300.0, "from outside the edge")
	riders.free()
	f.free()
	v.free()
