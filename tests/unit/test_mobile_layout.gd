extends "res://tests/test_case.gd"


func test_touch_town_places_recruitment_in_a_tab() -> void:
	TouchGestures.force_touch_ui = true
	var session := GameSession.new_game(data, "ember_ford", 11)
	var screen := TownScreen.new()
	screen.build_ui(data)
	screen.session = session
	screen.town_id = "town_greyhold"
	screen.refresh()
	assert_eq(String(screen._right.get_parent().name), "Recruit & town")
	assert_true(screen._next_btn.custom_minimum_size.y >= 44)
	screen.free()
	TouchGestures.force_touch_ui = false


func test_touch_hero_and_hud_use_scrollable_layouts() -> void:
	TouchGestures.force_touch_ui = true
	var session := GameSession.new_game(data, "ember_ford", 11)
	var hero_screen := HeroScreen.new()
	hero_screen.build(data, 760)
	hero_screen.session = session
	hero_screen.hero_id = "hero_wren"
	hero_screen.refresh()
	assert_true(hero_screen._panel.get_parent() is CenterContainer, "dialogs are centred on a phone")
	assert_true(hero_screen._body.get_parent() is ScrollContainer, "the body scrolls inside the panel")
	assert_false(hero_screen._body.get_parent().is_ancestor_of(hero_screen._footer), "Close stays below the scroll")
	assert_true(hero_screen._footer.get_child_count() > 0)
	assert_eq(hero_screen.exchange.columns, 5)
	var hud := Hud.new()
	hud.build(data)
	hud.refresh(session, session.hero("hero_wren"))
	assert_true(hud._roster.get_parent().get_parent() is ScrollContainer)
	assert_true(hud._end_turn.custom_minimum_size.y >= TouchLayout.MIN_TARGET)
	assert_true(hud._end_turn.get_parent().get_parent() is PanelContainer, "commands stay outside the scrolling hero details")
	hud.free()
	hero_screen.free()
	TouchGestures.force_touch_ui = false


func test_phone_canvas_uses_one_uniform_scale() -> void:
	var window := Window.new()
	window.content_scale_size = Vector2i(1280, 800)
	TouchLayout.simulated_points_height = 390.0
	TouchLayout.configure(window)
	assert_eq(window.content_scale_size, Vector2i(1280, 800), "desktop keeps its canvas")
	TouchGestures.force_touch_ui = true
	TouchLayout.configure(window)
	assert_eq(window.content_scale_size.y, 500, "an iPhone 12 Pro gets a 500-unit canvas")
	# 44 points of touch target and about 10 points of small print at that scale.
	assert_true(TouchLayout.MIN_TARGET * 390.0 / 500.0 >= 43.5)
	assert_true(TouchLayout.MIN_FONT * 390.0 / 500.0 >= 10.0)
	assert_eq(TouchLayout.canvas_height(1024.0), 800, "tablets keep the desktop canvas")
	assert_eq(TouchLayout.canvas_height(320.0), TouchLayout.MIN_HEIGHT, "small phones still fit dialogs")
	window.free()
	TouchLayout.simulated_points_height = 0.0
	TouchGestures.force_touch_ui = false


func test_safe_area_insets_move_the_hud_inside() -> void:
	TouchGestures.force_touch_ui = true
	TouchLayout.simulated_points_height = 390.0
	TouchLayout.simulated_insets = Vector4(47, 0, 47, 21)
	var window := Window.new()
	window.size = Vector2i(2532, 1170)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	TouchLayout.configure(window)
	TouchLayout.update_safe_area(window)
	var inset := TouchLayout.insets()
	assert_between(inset.x, 47.0 * 500.0 / 390.0 - 0.5, 47.0 * 500.0 / 390.0 + 0.5)
	assert_between(inset.w, 21.0 * 500.0 / 390.0 - 0.5, 21.0 * 500.0 / 390.0 + 0.5)
	var hud := Hud.new()
	hud.build(data)
	assert_between(hud.offset_left, inset.x - 0.01, inset.x + 0.01)
	assert_between(hud.offset_right, -inset.z - 0.01, -inset.z + 0.01)
	assert_between(hud.offset_bottom, -inset.w - 0.01, -inset.w + 0.01)
	assert_between(Hud.map_margins().z, Hud.PANEL_W + inset.z - 0.01, Hud.PANEL_W + inset.z + 0.01)
	hud.free()
	window.free()
	TouchLayout.simulated_insets = Vector4.ZERO
	TouchLayout.simulated_points_height = 0.0
	TouchLayout.update_safe_area(null)
	TouchGestures.force_touch_ui = false


func test_touch_dialogs_scroll_and_controls_do_not_grow_on_refresh() -> void:
	TouchGestures.force_touch_ui = true
	var dialog := SiteDialog.new()
	dialog.build(data, 620)
	assert_true(dialog._body.get_parent() is ScrollContainer)
	var button := Button.new()
	button.custom_minimum_size = Vector2(30, 32)
	button.add_theme_font_size_override("font_size", 14)
	dialog._body.add_child(button)
	UiStyle.enlarge_touch_controls(dialog)
	var font_size := button.get_theme_font_size("font_size")
	UiStyle.enlarge_touch_controls(dialog)
	assert_eq(button.custom_minimum_size, Vector2(TouchLayout.MIN_TARGET, TouchLayout.MIN_TARGET))
	assert_eq(button.get_theme_font_size("font_size"), font_size)
	assert_eq(font_size, TouchLayout.CONTROL_FONT, "button text is phone-sized, not doubled")
	dialog.free()
	TouchGestures.force_touch_ui = false


func test_touch_setup_groups_players_and_keeps_validation_outside_scroll() -> void:
	TouchGestures.force_touch_ui = true
	var menu := MainMenu.new()
	menu.build(data)
	menu._show_setup()
	menu.set_random_options({"size": "xl", "players": 6})
	assert_eq(menu._player_tabs.get_tab_count(), 6)
	assert_eq(menu._slots_box.columns, 1)
	assert_false(menu._setup_scroll.is_ancestor_of(menu._setup_footer), "Back, Begin and errors stay outside scrolling content")
	assert_eq(menu._setup_scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	var row: Dictionary = menu._slot_rows[5]
	row["color"].select(0)
	assert_false(menu._validate(), "duplicate colors still prevent starting")
	assert_true(menu._start_btn.disabled)
	row["color"].select(5)
	assert_true(menu._validate())
	menu._player_tabs.current_tab = 5
	assert_eq(String(menu.current_setup()["players"][5]["color"]), GameSetup.PLAYER_COLORS[5])
	menu.free()
	TouchGestures.force_touch_ui = false


func test_touch_scroll_controls_pass_swipes_to_their_scroll_parent() -> void:
	TouchGestures.force_touch_ui = true
	var scroll := ScrollContainer.new()
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.add_child(wrapper)
	var pick := OptionButton.new()
	wrapper.add_child(pick)
	UiStyle.enlarge_touch_controls(scroll)
	assert_eq(wrapper.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(pick.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(pick.action_mode, BaseButton.ACTION_MODE_BUTTON_RELEASE, "a swipe can cancel before the popup opens")
	var outside := Button.new()
	TouchLayout.prepare_scroll_input(outside)
	assert_eq(outside.mouse_filter, Control.MOUSE_FILTER_STOP, "ordinary controls still block input to the map")
	outside.free()
	scroll.free()
	TouchGestures.force_touch_ui = false


func test_touch_display_labels_keep_normal_font_sizes() -> void:
	TouchGestures.force_touch_ui = true
	var resource := UiStyle.label("7500", 16)
	var town_title := UiStyle.label("Greyhold", 28)
	UiStyle.enlarge_touch_controls(resource)
	UiStyle.enlarge_touch_controls(town_title)
	assert_eq(resource.get_theme_font_size("font_size"), 16)
	assert_eq(town_title.get_theme_font_size("font_size"), 28)
	var small := UiStyle.label("Level 1 Knight", 11)
	UiStyle.enlarge_touch_controls(small)
	assert_eq(small.get_theme_font_size("font_size"), TouchLayout.MIN_FONT, "small print is raised to stay readable")
	small.free()
	var slot := ArmySlot.new()
	UiStyle.enlarge_touch_controls(slot)
	assert_true(slot.custom_minimum_size.x >= TouchLayout.MIN_TARGET and slot.custom_minimum_size.y >= TouchLayout.MIN_TARGET, "army slots are interactive")
	resource.free()
	town_title.free()
	slot.free()
	TouchGestures.force_touch_ui = false


func test_swiping_slots_and_town_art_does_not_activate_them() -> void:
	TouchGestures.force_touch_ui = true
	for slot in [ArmySlot.new(), ArtifactSlot.new(), TownScene.new()]:
		slot.size = Vector2(96, 96)
		var clicks := [0]
		if slot is TownScene:
			slot._hits = [{"id": "building", "rect": Rect2(0, 0, 96, 96)}]
			slot.building_selected.connect(func(_id): clicks[0] += 1)
		else:
			slot.clicked.connect(func(_slot, _shift): clicks[0] += 1)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = Vector2(20, 20)
		press.pressed = true
		var release := press.duplicate() as InputEventMouseButton
		release.pressed = false
		slot._gui_input(press)
		slot.notification(Control.NOTIFICATION_SCROLL_BEGIN)
		slot._gui_input(release)
		assert_eq(clicks[0], 0, "scrolling must not select or move a unit/item")
		slot._gui_input(press)
		slot._gui_input(release)
		assert_eq(clicks[0], 1, "a tap still activates the slot")
		slot.free()
	TouchGestures.force_touch_ui = false
