extends "res://tests/test_case.gd"
## Headless checks of the interface widgets: they build from the art set, show
## the session's state and route every change through GameSession commands.

const G := "garrison:town_greyhold"

var session: GameSession


func before_each() -> void:
	session = GameSession.new_game(data, "ember_ford", 11)


func test_ui_icons_are_built() -> void:
	for n in ["attack", "defense", "power", "knowledge", "move", "xp", "day", "town", "hero", "armor", "charm", "banner", "pack"]:
		assert_true(Art.sprite("ui_icon_" + n) != null, n)


func test_sentence_case() -> void:
	assert_eq(UiStyle.sentence("a hero needs at least one creature"), "A hero needs at least one creature")
	assert_eq(UiStyle.sentence(""), "")


func test_scouted_counts_read_on_their_own() -> void:
	assert_eq(UiStyle.count_word(12), "A pack of", "before a name")
	assert_eq(UiStyle.count_caption(12), "Pack", "under a portrait, without a dangling 'of'")
	assert_eq(UiStyle.count_range(12), "10-19")
	assert_eq(UiStyle.count_caption(1), "Few")
	assert_eq(UiStyle.count_caption(5000), "Legion")
	assert_eq(UiStyle.count_range(100), "100+")
	for n in [1, 4, 5, 9, 10, 19, 20, 49, 50, 99, 100]:
		assert_false(UiStyle.count_caption(n).ends_with(" of"), "caption for %d" % n)


func test_creature_tooltip_lists_numbers_and_abilities() -> void:
	var tip := UiStyle.creature_tooltip(data, "pike_militia", 12)
	assert_true(tip.begins_with("12 Pike Militia"), tip)
	assert_true(tip.contains("Attack 4"), tip)
	assert_true(tip.contains("Brace"), tip)


func test_cost_row_marks_unaffordable_amounts() -> void:
	var bank := ResourceBank.new()
	bank.add("gold", 100)
	var row := UiStyle.cost_row({"gold": 500, "wood": 2}, data, bank)
	var labels := row.get_children().filter(func(c): return c is Label)
	assert_eq(labels.size(), 2)
	assert_eq(labels[0].text, "500")
	assert_eq(labels[0].get_theme_color("font_color"), UiStyle.BAD)
	row.free()


func test_army_exchange_select_split_and_swap() -> void:
	var ex := ArmyExchange.new()
	ex.setup(session, [["hero_wren", "Wren"]])
	var wren := session.hero("hero_wren")
	ex.click("hero_wren", 0)
	assert_eq(ex.selected(), ["hero_wren", 0])
	var r := ex.click("hero_wren", 5, true)   # shift: split half of 24
	assert_true(r["ok"], str(r))
	assert_eq(int(wren.army.slots[5]["count"]), 12)
	assert_eq(int(wren.army.slots[0]["count"]), 12)
	assert_eq(ex.selected(), ["", -1])
	ex.click("hero_wren", 1)
	r = ex.click("hero_wren", 2)
	assert_true(r["swapped"])
	# Picking up an empty slot does nothing; clicking the picked stack drops it.
	ex.click("hero_wren", 6)
	assert_eq(ex.selected(), ["", -1])
	ex.click("hero_wren", 0)
	ex.click("hero_wren", 0)
	assert_eq(ex.selected(), ["", -1])
	ex.free()


func test_army_exchange_reports_refusals() -> void:
	var ex := ArmyExchange.new()
	ex.setup(session, [["hero_wren", "Wren"], [G, "Garrison"]])
	ex.click("hero_wren", 0)
	var r := ex.click(G, 0)
	assert_eq(r["reason"], "hero not in town")
	ex.free()


func test_hero_screen_rows_include_garrison_in_town() -> void:
	var hs := HeroScreen.new()
	hs.build(data)
	hs.session = session
	var wren := session.hero("hero_wren")
	assert_eq(hs.army_rows(wren).size(), 1)
	wren.pos = Vector2i(1, 8)
	var rows := hs.army_rows(wren)
	assert_eq(rows.size(), 2)
	assert_eq(rows[1][0], G)
	hs.free()


func test_minimap_scales_to_the_map() -> void:
	var mm := Minimap.new()
	mm.bind(session)
	var w := session.state.map.width
	var h := session.state.map.height
	assert_true(mm.custom_minimum_size.x <= Minimap.MAX_SIZE.x and mm.custom_minimum_size.y <= Minimap.MAX_SIZE.y)
	assert_eq(mm.custom_minimum_size, Vector2(w, h) * mm.cell_size())
	assert_eq(mm.tile_at(Vector2(mm.cell_size() * 3 + 1, mm.cell_size() * 2 + 1)), Vector2i(3, 2))
	assert_eq(mm.tile_at(Vector2(-50, 9999)), Vector2i(0, h - 1), "clamped to the map")
	mm.free()


func test_hud_builds_and_refreshes() -> void:
	var hud := Hud.new()
	hud.build(data)
	hud.minimap.bind(session)
	hud.refresh(session, session.hero("hero_wren"))
	hud.refresh(session, null)
	hud.set_minimap_visible(false)
	assert_false(hud.minimap_visible())
	hud.free()


func test_main_menu_opens_campaign_map_and_previews_chapters() -> void:
	var m := MainMenu.new()
	m.build(data)
	m.show_campaigns()
	assert_true(m._campaign_panel.visible)
	assert_false(m._home.visible)
	var screen := m._campaign_panel
	assert_eq(screen.journey.buttons.size(), 10)
	screen.journey.select_stop(0)
	assert_eq(screen.title.text, "Greyhold Harvest")
	screen.journey.select_stop(9)
	assert_eq(screen.title.text, "Into the Embers")
	assert_true(screen.go.disabled, "future destinations are previews only")
	m.free()


func test_chapter_dialog_opens() -> void:
	var d := ChapterDialog.new()
	d.build(data, 560)
	d.open("The Burning Ford", "The Ember Chronicle", ["Hold the ford."])
	assert_true(d.visible)
	d.free()


func test_every_chapter_has_a_briefing_illustration() -> void:
	var ids: Array = data.campaigns.keys()
	ids.sort()
	for cid in ids:
		for ch in data.campaigns[cid]["chapters"]:
			var tex := CampaignArt.texture(String(cid), String(ch["id"]))
			assert_true(tex != null, "%s/%s has a briefing illustration" % [cid, ch["id"]])
			if tex != null:
				assert_gt(minf(tex.get_size().x, tex.get_size().y), 767.0, "%s is shown at full resolution" % ch["id"])
	assert_true(CampaignArt.texture("last_light", "no_such_chapter") == null)
	assert_eq(CampaignArt.path_of("last_light", "no_such_chapter"), "", "unknown chapters show text only")


func test_every_campaign_opens_with_an_illustration() -> void:
	var ids: Array = data.campaigns.keys()
	ids.sort()
	for cid in ids:
		var first := String(data.campaigns[cid]["chapters"][0]["id"])
		var tex := CampaignArt.texture(String(cid), first)
		assert_true(tex != null, "%s chapter 1 has a briefing illustration" % cid)
		if tex != null:
			assert_gt(minf(tex.get_size().x, tex.get_size().y), 767.0, "%s is full resolution" % cid)


func test_campaign_cover_shows_the_current_chapter() -> void:
	var c := Campaign.start(data, "ashwinter", 1)
	var opening := CampaignArt.texture("ashwinter", String(data.campaigns["ashwinter"]["chapters"][0]["id"]))
	assert_true(opening != null)
	assert_true(CampaignArt.campaign_texture(data, c) == opening, "a fresh campaign shows its opening picture")
	c.chapter = 4
	var fifth := CampaignArt.texture("ashwinter", String(data.campaigns["ashwinter"]["chapters"][4]["id"]))
	assert_true(fifth != null and fifth != opening, "chapter 5 has a picture of its own")
	assert_true(CampaignArt.campaign_texture(data, c) == fifth, "so the cover follows the campaign")


func test_chapter_dialog_shows_the_illustration_beside_the_text() -> void:
	var d := ChapterDialog.new()
	d.build(data, 560)
	var tex := CampaignArt.texture("last_light", "ll_harvest")
	d.open("Greyhold Harvest", "The Last Light", ["Clear the barrow camp."], "Take the field", tex)
	assert_true(d.visible)
	assert_true(d.art_rect() != null and d.art_rect().texture == tex, "the picture is in the dialog")
	assert_gt(d._panel.custom_minimum_size.x, 560.0, "and the dialog widens for it")
	d.open("The Barrow Roads", "The Pale Inheritance", ["No picture here."])
	assert_true(d.art_rect() == null)
	assert_eq(d._panel.custom_minimum_size.x, 560.0, "without a picture it is narrow again")
	d.free()


func test_battle_panels_build_forecast_and_report() -> void:
	var bp := BattlePanels.new()
	bp.build(data)
	var pred := session.preview_battle("hero_wren", "neutral_wolves")
	bp.show_forecast("Wolves", pred)
	assert_true(bp.visible)
	session.move_hero("hero_wren", Vector2i(12, 8))
	var result := session.attack("hero_wren", "neutral_wolves")
	bp.show_report(result)
	bp.show_details()
	assert_true(bp.visible)
	bp.free()


func test_forecast_order_pickers_offer_open_orders_and_report_changes() -> void:
	var bp := BattlePanels.new()
	bp.build(data)
	session.hero("hero_wren").level = 3
	var pred := session.preview_battle("hero_wren", "neutral_wolves")
	pred["orders"] = session.order_choices("hero_wren")
	bp.show_forecast("Wolves", pred)
	var row: Node = bp.find_child("Orders", true, false)
	assert_true(row != null, "the forecast shows the orders")
	var stance: OptionButton = row.find_child("Stance", true, false)
	var focus: OptionButton = row.find_child("Focus", true, false)
	var formation: OptionButton = row.find_child("Formation", true, false)
	assert_true(formation != null and row.find_child("Art", true, false) != null and row.find_child("Retreat", true, false) != null)
	assert_eq(formation.item_count, data.tactics["formations"].size())
	assert_eq(stance.item_count, data.tactics["stances"].size())
	assert_false(stance.is_item_disabled(1), "Hold the line is open at level 3")
	assert_true(stance.is_item_disabled(2), "All-out attack needs level 4")
	assert_true(stance.get_item_text(2).contains("level 4"))
	var got := []
	bp.orders_changed.connect(func(o: Dictionary): got.append([o["stance"], o["focus"], o["formation"], o["retreat"]]))
	stance.select(1)
	stance.item_selected.emit(1)
	assert_eq(got, [["defensive", "any", "line", "never"]])
	assert_eq(String(focus.get_item_metadata(focus.selected)), "any")
	bp.free()


func test_hero_screen_equipment_wear_take_off_and_hand_over() -> void:
	var hs := HeroScreen.new()
	hs.build(data)
	var wren := session.hero("hero_wren")
	assert_true(wren.give_artifact("notched_falchion", data))
	assert_true(wren.give_artifact("bleeding_glaive", data))
	assert_eq(String(wren.equipment.get("weapon", "")), "notched_falchion")
	hs.open(session, "hero_wren")
	# Wearing the packed glaive swaps the falchion into the pack.
	assert_true(hs.artifact_click("bleeding_glaive", false)["ok"])
	assert_eq(String(wren.equipment["weapon"]), "bleeding_glaive")
	assert_true(wren.pack.has("notched_falchion"))
	assert_true(hs.artifact_click("bleeding_glaive", true)["ok"], "take off")
	assert_eq(String(wren.equipment.get("weapon", "")), "")
	# Shift hands an artifact to an adjacent hero.
	var maelis := session.hero("hero_maelis")
	maelis.pos = wren.pos + Vector2i(1, 0)
	assert_eq(hs.adjacent_heroes(wren), [maelis])
	assert_true(hs.artifact_click("notched_falchion", false, true)["ok"])
	assert_true(maelis.all_artifacts(data).has("notched_falchion"))
	assert_eq(hs.artifact_click("", false)["ok"], false, "empty slot does nothing")
	hs.free()


func test_artifact_slot_icons_exist_for_every_slot_type() -> void:
	for slot in data.artifact_slots:
		var icon: String = ArtifactSlot.SLOT_ICONS.get(slot, "")
		assert_ne(icon, "", slot)
		assert_true(Art.sprite("ui_icon_" + icon) != null, slot)
	var w := ArtifactSlot.new().setup("weapon", "bleeding_glaive", data)
	assert_true(w.tooltip_text.begins_with("Bleeding Glaive"), w.tooltip_text)
	assert_eq(w.rarity, "major")
	assert_true(w._icon == Art.texture_at("res://assets/artifacts/bleeding_glaive.png"), "uses item artwork")
	for artifact_id in data.artifacts:
		assert_true(ResourceLoader.exists("res://assets/artifacts/%s.png" % artifact_id), artifact_id)
	w.free()


func test_symbol_icons_use_the_detailed_art_and_fit_their_widgets() -> void:
	# The symbol sheet: hourglass, castle, helm, dagger, cuirass, shield, boots, amulet, banner.
	for n in ["day", "town", "hero", "attack", "armor", "defense", "move", "charm", "banner"]:
		var tex := Art.sprite("ui_icon_" + n)
		assert_eq(tex.get_size(), Vector2(48, 48), n)
	var b := Button.new()
	UiStyle.button_icon(b, "day", 30)
	assert_eq(b.get_theme_constant("icon_max_width"), 30, "button icons are capped")
	assert_eq(b.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "shrunk symbols are smoothed")
	b.free()
	var r := UiStyle.icon(Art.sprite("ui_icon_xp"), Vector2(32, 32))
	assert_eq(r.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "small pixel icons stay crisp when enlarged")
	r.free()
	var w := ArtifactSlot.new().setup("helm", "", data)
	assert_true(ArtifactSlot.ICON_PX < ArtifactSlot.SIZE, "slot icon fits inside the frame")
	w.free()


func test_campaign_menu_shows_regional_paintings_and_all_stops() -> void:
	var m := MainMenu.new()
	m.build(data)
	m.show_campaigns()
	var screen := m._campaign_panel
	for cid in data.campaigns:
		screen.show_campaign(cid)
		assert_true(screen.journey.painting == CampaignArt.texture(cid, "", "journey"), cid)
		if screen.catalog["campaigns"].has(cid):
			assert_true(screen.journey.painting != null, "regional painting exists: " + cid)
		assert_eq(screen.journey.buttons.size(), data.campaigns[cid]["chapters"].size(), cid)
	m.free()


func test_campaign_texture_follows_progress() -> void:
	var c := Campaign.start(data, "last_light", 1)
	assert_true(CampaignArt.campaign_texture(data, c) == CampaignArt.texture("last_light", "ll_harvest"), "new: chapter 1")
	c.chapter = 3
	var fourth := String(data.campaigns["last_light"]["chapters"][3]["id"])
	assert_true(CampaignArt.campaign_texture(data, c) == CampaignArt.texture("last_light", fourth), "the next chapter")
	var chapters: Array = data.campaigns["last_light"]["chapters"]
	c.chapter = chapters.size()
	assert_true(CampaignArt.campaign_texture(data, c) == CampaignArt.texture("last_light", String(chapters[-1]["id"])),
		"a won campaign shows its last chapter")
	assert_true(CampaignArt.campaign_texture(data, c) != null)


func test_campaign_end_screen_shows_the_won_chapters_illustration() -> void:
	var d := GameOverDialog.new()
	d.build(data, 640)
	var result := {"human_won": true, "title": "Victory", "text": "The field is yours.", "standings": [], "day": 9, "winner": 0}
	var tex := CampaignArt.texture("last_light", "ll_harvest")
	d.open(result, {"title": "Greyhold Harvest is won", "lines": ["Next: The Barrow Roads."], "action": "Next chapter", "art": tex})
	assert_true(d.visible)
	assert_true(d.art_rect() != null and d.art_rect().texture == tex, "the won chapter's picture is shown")
	assert_gt(d._panel.custom_minimum_size.x, 640.0, "and the panel widens for it")
	d.open(result, {"title": "Lost", "lines": [], "action": "Retry chapter"})
	assert_true(d.art_rect() == null, "no picture after a loss")
	assert_eq(d._panel.custom_minimum_size.x, 640.0)
	d.open(result)
	assert_true(d.art_rect() == null, "nor in a skirmish")
	d.free()
