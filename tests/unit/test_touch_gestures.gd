extends "res://tests/test_case.gd"
## Touch controls on the adventure map: tap, long press, drag and the
## two-finger cancel (TouchGestures), and the touch wording of the hints.

const K := TouchGestures.Kind


func test_quick_still_press_is_a_tap() -> void:
	var g := TouchGestures.new()
	g.press(Vector2(100, 100), 1000)
	assert_eq(g.move(Vector2(104, 103)), Vector2.ZERO, "small jitter does not pan")
	assert_eq(g.release(Vector2(104, 103), 1150), K.TAP)
	assert_false(g.is_down())


func test_resting_finger_fires_long_press_once() -> void:
	var g := TouchGestures.new()
	g.press(Vector2(50, 50), 0)
	assert_false(g.poll_long_press(TouchGestures.LONG_PRESS_MS - 1))
	assert_true(g.poll_long_press(TouchGestures.LONG_PRESS_MS))
	assert_false(g.poll_long_press(TouchGestures.LONG_PRESS_MS + 500), "fires only once")
	assert_eq(g.move(Vector2(90, 50)), Vector2.ZERO, "after a long press the finger no longer pans")
	assert_eq(g.release(Vector2(50, 50), 900), K.LONG_PRESS, "a long press never taps (no march)")


func test_drag_pans_by_finger_movement() -> void:
	var g := TouchGestures.new()
	g.press(Vector2(200, 200), 0)
	var first := g.move(Vector2(200 + TouchGestures.DRAG_SLOP + 1, 200))
	assert_eq(first, Vector2(TouchGestures.DRAG_SLOP + 1, 0), "the first pan includes the slop")
	assert_true(g.is_dragging())
	assert_eq(g.move(Vector2(230, 190)), Vector2(230 - (200 + TouchGestures.DRAG_SLOP + 1), -10))
	assert_false(g.poll_long_press(5000), "a drag never becomes a long press")
	assert_eq(g.release(Vector2(230, 190), 5000), K.DRAG)


func test_second_finger_cancels_and_spends_the_press() -> void:
	var g := TouchGestures.new()
	g.press(Vector2(10, 10), 0)
	assert_eq(g.second_finger(), K.CANCEL)
	assert_eq(g.second_finger(), K.NONE, "one cancel per press")
	assert_false(g.poll_long_press(2000))
	assert_eq(g.move(Vector2(200, 200)), Vector2.ZERO)
	assert_eq(g.release(Vector2(10, 10), 100), K.NONE, "no tap after a cancel")


func test_second_finger_while_dragging_keeps_the_drag() -> void:
	var g := TouchGestures.new()
	g.press(Vector2(10, 10), 0)
	g.move(Vector2(60, 10))
	assert_eq(g.second_finger(), K.NONE)
	assert_eq(g.release(Vector2(60, 10), 100), K.DRAG)


func test_reset_forgets_the_press() -> void:
	var g := TouchGestures.new()
	g.press(Vector2(10, 10), 0)
	g.reset()
	assert_false(g.is_down())
	assert_eq(g.release(Vector2(10, 10), 50), K.NONE)


func test_release_without_press_is_nothing() -> void:
	assert_eq(TouchGestures.new().release(Vector2.ZERO, 0), K.NONE)


func test_hints_use_touch_wording_on_touch_screens() -> void:
	TouchGestures.force_touch_ui = true
	var hint := TouchGestures.controls_hint()
	var scout: String = MapTip.scout_line({"scout_cost": 2})[0]
	TouchGestures.force_touch_ui = false
	assert_true(hint.contains("Tap a tile"), hint)
	assert_false(hint.contains("Right-click"), hint)
	assert_true(scout.contains("forecast"), scout)
	assert_true(TouchGestures.controls_hint().contains("Right-click"), "desktop keeps the mouse wording")


func test_resting_finger_becomes_an_emulated_mouse_rest() -> void:
	var ev := TouchTooltips.rest_event(Vector2(120, 80))
	assert_eq(ev.position, Vector2(120, 80))
	assert_eq(ev.device, InputEvent.DEVICE_ID_EMULATION, "the map ignores it as a click source")
	assert_eq(ev.button_mask, 0, "no button held, so the tooltip may open")


func test_spreading_two_fingers_zooms_in_and_pinching_zooms_out() -> void:
	var p := PinchGesture.new()
	p.begin(0, Vector2(100, 100), 1, Vector2(200, 100), 0)
	assert_true(p.is_active())
	assert_eq(p.move(1, Vector2(210, 100)), 0, "a small spread is not a zoom yet")
	assert_eq(p.move(1, Vector2(240, 100)), 1, "spread 1.4x: one level closer")
	assert_eq(p.midpoint(), Vector2(170, 100))
	assert_eq(p.move(1, Vector2(150, 100)), -1, "pinch back: one level farther")
	assert_false(p.finish(2000), "a pinch is not a tap")
	assert_false(p.is_active())


func test_quick_still_two_finger_tap_cancels() -> void:
	var p := PinchGesture.new()
	p.begin(0, Vector2(100, 100), 1, Vector2(200, 120), 1000)
	p.move(0, Vector2(104, 102))
	assert_true(p.finish(1000 + PinchGesture.TAP_MS), "two-finger tap")
	p.begin(0, Vector2(100, 100), 1, Vector2(200, 120), 0)
	assert_false(p.finish(PinchGesture.TAP_MS + 200), "a slow two-finger hold is not a tap")
	assert_eq(p.move(0, Vector2.ZERO), 0, "finished pinches ignore fingers")
