extends "res://tests/test_case.gd"
## Ten army slots (heroes and garrisons) and switching between towns on the
## town screen (Tab, Shift+Tab, the < and > buttons and the town list).

const TOWN := "town_greyhold"
const OTHER := "town_cindermaw"

var session: GameSession


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 11)


func test_armies_hold_ten_stacks() -> void:
	assert_eq(Army.MAX_SLOTS, 10)
	var a := Army.new()
	var kinds := ["pike_militia", "longbowman", "lancer", "bastion_colossus"]
	var all := data.creatures.keys()
	all.sort()
	for c in all:
		if kinds.size() >= 10:
			break
		if not kinds.has(c):
			kinds.append(c)
	for c in kinds:
		assert_true(a.add(c, 3), "room for %s" % c)
	assert_eq(a.stack_count(), 10)
	assert_false(a.add("not_in_army", 1), "an eleventh kind has no room")
	assert_eq(a.to_combat_stacks().size(), 10)


func test_old_seven_slot_armies_load_into_ten_slots() -> void:
	var old := [{"creature": "pike_militia", "count": 5}, {}, {}, {}, {}, {}, {"creature": "longbowman", "count": 2}]
	var a := Army.from_dict(old)
	assert_eq(a.slots.size(), 10)
	assert_eq(int(a.slots[6]["count"]), 2)
	assert_true(a.slots[9].is_empty())
	assert_eq(a.to_dict().size(), 10)


func test_stacks_move_into_the_new_slots() -> void:
	var wren := session.hero("hero_wren")
	var r := session.transfer_stack("hero_wren", 0, "hero_wren", 9, 4)
	assert_true(r["ok"], str(r))
	assert_eq(String(wren.army.slots[9]["creature"]), String(wren.army.slots[0]["creature"]))
	assert_eq(int(wren.army.slots[9]["count"]), 4)
	assert_false(session.transfer_stack("hero_wren", 0, "hero_wren", 10, 1)["ok"], "slot 10 does not exist")


func test_ten_stacks_fight() -> void:
	var stacks := []
	for i in 10:
		stacks.append({"slot": i, "creature": "pike_militia" if i % 2 == 0 else "longbowman", "count": 5})
	var setup := CombatSimulator.make_setup({"name": "Ten", "hero": null, "stacks": stacks},
		{"name": "Foe", "hero": null, "stacks": [{"slot": 0, "creature": "pike_militia", "count": 10}]}, "grass", 3)
	var res := CombatSimulator.new(data).simulate(setup, false)
	assert_eq(int(res["winner"]), 0)
	assert_eq((res["sides"][0]["stacks"] as Array).size(), 10, "all ten stacks take part")


func _screen() -> TownScreen:
	var ts := TownScreen.new()
	ts.build_ui(data)
	ts.session = session
	ts.town_id = TOWN
	ts.refresh()
	return ts


func test_town_screen_switch_is_off_with_one_town() -> void:
	var ts := _screen()
	assert_eq(ts.own_town_ids(), [TOWN] as Array[String])
	ts.switch_town(1)
	assert_eq(ts.town_id, TOWN)
	assert_true(ts._next_btn.disabled)
	ts.free()


func test_town_screen_cycles_through_own_towns() -> void:
	session.town(OTHER)["owner"] = 0
	var ts := _screen()
	assert_false(ts._next_btn.disabled)
	assert_eq(ts._town_pick.item_count, 2)
	ts.switch_town(1)
	assert_eq(ts.town_id, OTHER)
	assert_eq(ts._title.text, String(session.town(OTHER)["name"]))
	assert_eq(ts._town_pick.selected, 1)
	ts.switch_town(1)
	assert_eq(ts.town_id, TOWN, "wraps around")
	ts.switch_town(-1)
	assert_eq(ts.town_id, OTHER, "backwards wraps too")
	ts.show_town(TOWN)
	assert_eq(ts.town_id, TOWN)
	ts.show_town("no_such_town")
	assert_eq(ts.town_id, TOWN)
	ts.free()


func test_town_screen_from_an_unowned_town_jumps_to_the_first_own_town() -> void:
	var ts := _screen()
	ts.town_id = OTHER
	ts.refresh()
	assert_eq(ts._town_pick.item_count, 2, "own towns plus the one on screen")
	ts.switch_town(1)
	assert_eq(ts.town_id, TOWN)
	ts.free()


func test_town_scene_preview_then_build_and_unavailable_reason() -> void:
	var ts := _screen()
	var t := session.town(TOWN)
	var bank: ResourceBank = session.current_player()["resources"]
	var gold := bank.get_amount("gold")
	ts._inspect_building("c_dw2")
	assert_true(ts._building_preview.visible)
	assert_false(Town.has_building(t, "c_dw2"), "first click only previews")
	assert_eq(bank.get_amount("gold"), gold)
	assert_true(ts._preview_content.get_child(1) is TextureRect, "preview includes building artwork")
	ts._inspect_building("c_dw2")
	assert_true(Town.has_building(t, "c_dw2"), "second click builds")
	assert_eq(bank.get_amount("gold"), gold - 1000)
	assert_false(ts._building_preview.visible)
	ts._inspect_building("c_palisade")
	var status: Label = ts._preview_content.get_child(ts._preview_content.get_child_count() - 1)
	assert_true(status.text.contains("Already built today"))
	ts._inspect_building("c_palisade")
	assert_false(Town.has_building(t, "c_palisade"))
	ts._inspect_building("")
	assert_false(ts._building_preview.visible)
	ts.free()


func test_town_scene_preview_clears_when_switching_town() -> void:
	session.town(OTHER)["owner"] = 0
	var ts := _screen()
	ts._inspect_building("c_dw2")
	ts.switch_town(1)
	assert_false(ts._building_preview.visible)
	assert_eq(ts._preview_site, "")
	ts.free()


func _recruit_names(ts: TownScreen) -> Array:
	var out := []
	for b in ts._right.find_children("*", "Button", true, false):
		if (b as Button).text == "Recruit":
			var info: Node = b.get_parent().get_child(1)
			out.append((info.get_child(0).get_child(0) as Label).text)
	return out


func test_recruit_lists_the_upgrade_with_a_swap_to_the_base_unit() -> void:
	var t := session.town(TOWN)
	var base := String(Town.dwellings(t, data)[0])
	var up := String(data.creature(base)["upgrade"])
	for b in Town.building_ids(t, data):
		for e in Town.building(t, b, data).get("effects", []):
			if e["type"] == "dwelling_upgrade" and e["creature"] == base and not t["built"].has(b):
				t["built"].append(b)
	assert_true(Town.recruitable(t, data).has(up), "the upgraded dwelling stands")
	var ts := _screen()
	var names := _recruit_names(ts)
	assert_eq(names.size(), Town.dwellings(t, data).size(), "one row per dwelling")
	assert_true(String(names[0]).begins_with(data.creature(up)["name"]), "the better unit by default")
	var swap: Button = ts._right.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text == "⇅")[0]
	swap.pressed.emit()
	assert_true(String(_recruit_names(ts)[0]).begins_with(data.creature(base)["name"]), "swapped to the base unit")
	ts.free()


func test_market_amounts_snap_to_whole_units_bought() -> void:
	var t := session.town(TOWN)
	for b in Town.building_ids(t, data):
		for e in Town.building(t, b, data).get("effects", []):
			if e["type"] == "market" and not t["built"].has(b):
				t["built"].append(b)
	assert_gt(session.market_count(0), 0)
	var ts := _screen()
	ts._sell.select(data.resource_order.find("gold"))
	ts._buy.select(data.resource_order.find("crystal"))
	# Out of the scene tree the SpinBox sends no value_changed, so call what it would.
	ts._amount.set_value_no_signal(1)
	ts._snap_amount(1)
	var one := Economy.trade_price("gold", "crystal", 1, session.market_count(0), data)
	assert_eq(int(ts._amount.value), one, "gold snaps to one whole crystal")
	ts._amount.set_value_no_signal(one + 1)
	ts._snap_amount(one + 1)
	assert_eq(int(ts._amount.value), Economy.trade_price("gold", "crystal", 2, session.market_count(0), data), "up a step buys one more")
	assert_eq(ts._sell.get_item_icon(0) != null, true, "resources show their icons")
	ts.free()
