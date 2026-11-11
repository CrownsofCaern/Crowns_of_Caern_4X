extends SceneTree
## Exercise phone setup with emulated finger input, not wheels or direct scroll assignment.
## godot --headless --path . --script res://tools/mobile_menu_check.gd
var menu: MainMenu
var failures: Array[String] = []
var starts := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Run this input regression check with --headless to isolate it from OS cursor/window events.")
		quit(2)
		return
	TouchGestures.force_touch_ui = true
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true
	_run.call_deferred()

func frames(count: int = 6) -> void:
	for i in count:
		await process_frame

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func finger(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = root.get_final_transform() * position
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames(2)

func swipe(position: Vector2, distance: float) -> void:
	await finger(position, true)
	for step in 8:
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = root.get_final_transform() * (position + Vector2(0, -distance * (step + 1) / 8.0))
		event.relative = root.get_final_transform().basis_xform(Vector2(0, -distance / 8.0))
		Input.parse_input_event(event)
		await frames(2)
	await finger(position - Vector2(0, distance), false)
	await frames()

func _run() -> void:
	await frames(2)
	root.gui_embed_subwindows = true
	for window_size in [Vector2i(844, 390), Vector2i(667, 375)]:
		# The window is in points here: one pixel stands for one point.
		TouchLayout.simulated_points_height = window_size.y
		TouchLayout.configure(root)
		root.size = window_size
		menu = MainMenu.new()
		root.add_child(menu)
		menu.build(GameData.get_default())
		menu.start_requested.connect(func(_map: String, _seed: int, _setup: Dictionary): starts += 1)
		menu.open(false)
		menu._show_setup()
		root.grab_focus()
		await create_timer(0.4).timeout
		await frames(15)
		var scroll := menu._setup_scroll
		var viewport := root.get_visible_rect()
		check(viewport.encloses(menu._start_btn.get_global_rect()), "Begin must stay visible at %s" % window_size)
		check(root.get_final_transform().basis_xform(menu._start_btn.size).y >= 44, "Begin needs a 44-point touch target")
		check(scroll.get_h_scroll_bar().max_value <= scroll.size.x + 1, "No horizontal overflow at %s" % window_size)
		var pick: OptionButton = menu._random_picks["size"]
		await finger(pick.get_global_rect().get_center(), true)
		await finger(pick.get_global_rect().get_center(), false)
		check(pick.get_popup().visible, "A tap must still open the picker")
		pick.get_popup().hide()
		root.grab_focus()
		await create_timer(0.15).timeout
		await frames()
		var before := scroll.scroll_vertical
		await swipe(pick.get_global_rect().get_center(), 180)
		print("SWIPE ", window_size, " ", before, " -> ", scroll.scroll_vertical, " touchscreen=", DisplayServer.is_touchscreen_available())
		check(scroll.scroll_vertical > before + 50, "Finger swipe over picker must scroll at %s" % window_size)
		check(not pick.get_popup().visible, "Swipe must not open a picker")
		check(viewport.encloses(menu._start_btn.get_global_rect()), "Begin must stay visible after swipe")
		await finger(menu._start_btn.get_global_rect().get_center(), true)
		await finger(menu._start_btn.get_global_rect().get_center(), false)
		check(starts > 0, "Begin must respond to a tap (focus=%s, disabled=%s, error=%s)" % [root.has_focus(), menu._start_btn.disabled, menu._error.text])

		menu.queue_free()
		await frames()
		starts = 0
	print("MOBILE_MENU_CHECK: %d failures" % failures.size())
	GameData._default = null
	quit(0 if failures.is_empty() else 1)
