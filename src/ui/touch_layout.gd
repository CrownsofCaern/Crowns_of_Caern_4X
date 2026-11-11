class_name TouchLayout
extends RefCounted
## Phone and tablet layout. A touch screen gets one uniform scale: the canvas is
## sized so that one canvas unit is about 0.78 points, which puts body text near
## 11 pt and lets a 56-unit control meet the 44-point touch target guideline.
## Taller screens (tablets) keep the 800-unit desktop canvas. The safe area
## (notch, rounded corners, home indicator) is kept free of controls.

const DESKTOP_HEIGHT := 800
## The smallest canvas height a phone gets, so desktop-sized dialogs still fit.
const MIN_HEIGHT := 480
## Points per canvas unit the phone canvas aims for.
const POINTS_PER_UNIT := 0.78
## A finger-sized control: at least 44 points at POINTS_PER_UNIT (45 with rounding room).
const MIN_TARGET := 58.0
## Phone text: no label smaller than this (about 10 points).
const MIN_FONT := 13
## Text on buttons, tabs, fields and dropdowns (about 14 points).
const CONTROL_FONT := 18

## Tools and tests: pretend to be a phone with this screen height and these
## safe-area insets, all in points (left, top, right, bottom). Zero: use the device.
static var simulated_points_height := 0.0
static var simulated_insets := Vector4.ZERO

## The current safe-area insets in canvas units (left, top, right, bottom).
static var _insets := Vector4.ZERO


## The canvas height for a screen `points_height` points tall (the short side).
static func canvas_height(points_height: float) -> int:
	if points_height <= 0.0:
		return DESKTOP_HEIGHT
	return clampi(roundi(points_height / POINTS_PER_UNIT), MIN_HEIGHT, DESKTOP_HEIGHT)


## The short side of the screen in points (0 when unknown).
static func screen_points_height() -> float:
	if simulated_points_height > 0.0:
		return simulated_points_height
	if not OS.has_feature("mobile"):
		return 0.0
	var px := DisplayServer.screen_get_size()
	var scale := DisplayServer.screen_get_scale()
	if scale <= 0.0:
		scale = 1.0
	return minf(px.x, px.y) / scale


static func configure(window: Window) -> void:
	if not TouchGestures.touch_ui():
		return
	var h := canvas_height(screen_points_height())
	window.content_scale_size = Vector2i(roundi(h * 1.6), h)
	update_safe_area(window)
	if not window.size_changed.is_connected(update_safe_area.bind(window)):
		window.size_changed.connect(update_safe_area.bind(window))


## Reads the safe area from the device (or the simulation) in canvas units.
static func update_safe_area(window: Window) -> void:
	_insets = Vector4.ZERO
	if not TouchGestures.touch_ui() or window == null:
		return
	var canvas_h := window.get_visible_rect().size.y
	if simulated_insets != Vector4.ZERO:
		var pts := simulated_points_height if simulated_points_height > 0.0 else canvas_h * POINTS_PER_UNIT
		_insets = simulated_insets * (canvas_h / pts)
		return
	if not OS.has_feature("mobile"):
		return
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if screen.y <= 0.0 or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return
	var k := canvas_h / screen.y
	_insets = Vector4(safe.position.x, safe.position.y, screen.x - safe.end.x, screen.y - safe.end.y).max(Vector4.ZERO) * k


## Safe-area insets in canvas units: x left, y top, z right, w bottom.
static func insets() -> Vector4:
	return _insets


## Keeps a full-rect control inside the safe area, `pad` units further in.
static func inset_full_rect(control: Control, pad: float = 0.0) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.offset_left = _insets.x + pad
	control.offset_top = _insets.y + pad
	control.offset_right = -_insets.z - pad
	control.offset_bottom = -_insets.w - pad


## Enlarged controls can exceed the available height; keep content reachable.
## The scroll area stays inside the safe area.
static func scroll_host(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	parent.add_child(scroll)
	inset_full_rect(scroll)
	return scroll


## A phone dialog: the panel stays centred and never taller than the safe
## area; `body` scrolls inside it, and the returned footer (for the button
## row) stays visible below the scroll, so Attack, Close or Save never sit
## below the fold.
static func fit_dialog(host: Control, panel: PanelContainer, body: VBoxContainer) -> VBoxContainer:
	var center := CenterContainer.new()
	host.add_child(center)
	inset_full_rect(center, 4)
	center.add_child(panel)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 6)
	panel.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	frame.add_child(footer)
	var fit := func() -> void:
		var margins := panel.get_combined_minimum_size().y - frame.get_combined_minimum_size().y
		var room := center.size.y - maxf(margins, 0.0) - footer.get_combined_minimum_size().y - 6.0
		scroll.custom_minimum_size.y = clampf(body.get_combined_minimum_size().y, 0.0, maxf(room, 80.0))
	body.minimum_size_changed.connect(fit)
	footer.minimum_size_changed.connect(fit)
	center.resized.connect(fit)
	return footer


## Let emulated finger motion reach the enclosing ScrollContainer, even when
## a swipe starts on a button. Godot cancels button presses when scrolling begins.
static func prepare_scroll_input(node: Node) -> void:
	if not TouchGestures.touch_ui() or not node is Control or node is ScrollContainer or node is ScrollBar:
		return
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			var control := node as Control
			if control.mouse_filter == Control.MOUSE_FILTER_STOP:
				control.mouse_filter = Control.MOUSE_FILTER_PASS
			if control is OptionButton:
				(control as OptionButton).action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			return
		ancestor = ancestor.get_parent()
