extends "res://tests/test_case.gd"
## Army management: split, merge and swap stacks within an army, between a hero
## and its town's garrison, and between adjacent heroes (GameSession.transfer_stack).

const TOWN := "town_greyhold"
const G := "garrison:town_greyhold"

var session: GameSession
var wren: Hero


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 11)
	wren = session.hero("hero_wren")
	# These tests count garrison troops from zero: drop the starting garrison.
	for t in session.towns_of(0):
		Town.set_garrison(t, Army.new())


func _slot(army: Army, i: int) -> Array:
	var s: Dictionary = army.slots[i]
	return [] if s.is_empty() else [s["creature"], int(s["count"])]


func _garrison() -> Army:
	return Town.garrison(session.town(TOWN))


func test_garrison_ref() -> void:
	assert_eq(GameSession.garrison_ref(TOWN), G)


func test_split_into_empty_slot() -> void:
	var r := session.transfer_stack("hero_wren", 0, "hero_wren", 5, 10)
	assert_true(r["ok"], str(r))
	assert_eq(_slot(wren.army, 0), ["pike_militia", 14])
	assert_eq(_slot(wren.army, 5), ["pike_militia", 10])
	assert_eq(wren.army.total_creatures(), 24 + 14 + 6 + 3)


func test_merge_same_creature() -> void:
	session.transfer_stack("hero_wren", 0, "hero_wren", 5, 10)
	var r := session.transfer_stack("hero_wren", 5, "hero_wren", 0)
	assert_true(r["ok"])
	assert_eq(_slot(wren.army, 0), ["pike_militia", 24])
	assert_eq(_slot(wren.army, 5), [])


func test_swap_different_creatures() -> void:
	var r := session.transfer_stack("hero_wren", 0, "hero_wren", 1)
	assert_true(r["ok"])
	assert_true(r["swapped"])
	assert_eq(_slot(wren.army, 0), ["longbowman", 14])
	assert_eq(_slot(wren.army, 1), ["pike_militia", 24])


func test_partial_move_onto_other_creature_fails() -> void:
	assert_eq(session.transfer_stack("hero_wren", 0, "hero_wren", 1, 5)["reason"], "slot holds another creature")
	assert_eq(_slot(wren.army, 0), ["pike_militia", 24], "nothing changed")


func test_bad_requests_fail() -> void:
	assert_eq(session.transfer_stack("hero_wren", 6, "hero_wren", 5)["reason"], "empty slot")
	assert_eq(session.transfer_stack("hero_wren", 0, "hero_wren", 0)["reason"], "same slot")
	assert_eq(session.transfer_stack("hero_wren", 0, "hero_wren", Army.MAX_SLOTS)["reason"], "no such slot")
	assert_eq(session.transfer_stack("hero_wren", 0, "hero_wren", 5, 99)["reason"], "not enough creatures")
	assert_eq(session.transfer_stack("nobody", 0, "hero_wren", 5)["reason"], "not your army")


func test_cannot_touch_another_players_army() -> void:
	var s := GameSession.new_game(data, "twin_marches", 3)
	var theirs: Hero = s.state.heroes_of(1)[0]
	assert_eq(s.transfer_stack(theirs.id, 0, theirs.id, 6)["reason"], "not your army")


func test_garrison_exchange_needs_hero_in_town() -> void:
	session.recruit(TOWN, "pike_militia", 4)
	assert_eq(session.transfer_stack(G, 0, "hero_wren", 5)["reason"], "hero not in town")
	session.move_hero("hero_wren", Vector2i(1, 8))
	var r := session.transfer_stack(G, 0, "hero_wren", 0)
	assert_true(r["ok"], str(r))
	assert_eq(_slot(wren.army, 0), ["pike_militia", 28], "merged into the hero's pikes")
	assert_true(_garrison().is_empty(), "garrison saved back to the town")


func test_hero_to_garrison_split_and_swap() -> void:
	session.move_hero("hero_wren", Vector2i(1, 8))
	assert_true(session.transfer_stack("hero_wren", 1, G, 2, 4)["ok"])
	assert_eq(_slot(_garrison(), 2), ["longbowman", 4])
	assert_eq(_slot(wren.army, 1), ["longbowman", 10])
	# Swapping a whole stack with a different garrison creature.
	var r := session.transfer_stack("hero_wren", 3, G, 2)
	assert_true(r["swapped"])
	assert_eq(_slot(_garrison(), 2), ["lancer", 3])
	assert_eq(_slot(wren.army, 3), ["longbowman", 4])


func test_garrison_internal_moves() -> void:
	session.recruit(TOWN, "pike_militia", 6)
	assert_true(session.transfer_stack(G, 0, G, 4, 2)["ok"])
	assert_eq(_slot(_garrison(), 0), ["pike_militia", 4])
	assert_eq(_slot(_garrison(), 4), ["pike_militia", 2])


func test_hero_keeps_one_creature() -> void:
	session.move_hero("hero_wren", Vector2i(1, 8))
	for i in [1, 2, 3]:
		assert_true(session.transfer_stack("hero_wren", i, G, i)["ok"])
	assert_eq(session.transfer_stack("hero_wren", 0, G, 0)["reason"], "a hero needs at least one creature")
	assert_true(session.transfer_stack("hero_wren", 0, G, 0, 23)["ok"], "leaving one behind is fine")
	assert_eq(wren.army.total_creatures(), 1)


func test_adjacent_heroes_exchange() -> void:
	var maelis := session.hero("hero_maelis")
	assert_eq(session.transfer_stack("hero_wren", 0, "hero_maelis", 3)["reason"], "too far apart")
	maelis.pos = wren.pos + Vector2i(1, 1)
	assert_true(session.transfer_stack("hero_wren", 0, "hero_maelis", 1, 4)["ok"])
	assert_eq(_slot(maelis.army, 1), ["pike_militia", 14])
	assert_eq(_slot(wren.army, 0), ["pike_militia", 20])


func test_total_creatures_conserved_under_many_moves() -> void:
	session.move_hero("hero_wren", Vector2i(1, 8))
	var total := wren.army.total_creatures()
	var rng := GameRng.new(7)
	for i in 200:
		var refs := ["hero_wren", G]
		session.transfer_stack(refs[rng.next_int(0, 1)], rng.next_int(0, 6), refs[rng.next_int(0, 1)], rng.next_int(0, 6), rng.next_int(0, 5))
	assert_eq(wren.army.total_creatures() + _garrison().total_creatures(), total)
	assert_gt(wren.army.total_creatures(), 0)
