class_name TouchGestures
extends RefCounted
## Turns one finger on the adventure map into a gesture: a tap (plan a route,
## tap again to march, and show what is there), a long press (show what is
## there without moving) or a drag (pan the map). A second finger cancels the
## planned route, like a right click. Pure bookkeeping over positions and times
## the caller passes in, so it can be tested without a touch screen.

## Screen pixels a finger may wander before a press becomes a drag.
const DRAG_SLOP := 14.0
## Milliseconds a still finger must rest to count as a long press.
const LONG_PRESS_MS := 450

enum Kind { NONE, TAP, LONG_PRESS, DRAG, CANCEL }

## Tests set this to check the touch wording without a touch screen.
static var force_touch_ui := false

var _down := false
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _start_ms := 0
var _dragging := false
var _long_fired := false
var _cancelled := false


## True on phones and tablets: hints name taps instead of keys and clicks.
static func touch_ui() -> bool:
	return force_touch_ui or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


## The how-to-play line at the start of a map: taps on a touch screen, mouse
## and keys elsewhere.
static func controls_hint() -> String:
	if TouchGestures.touch_ui():
		return "Tap a tile to plan a route, tap it again to march. Hold a finger on anything to see what it is, drag to look around, pinch to zoom, tap with two fingers to cancel the route. Tap an enemy twice for the battle forecast and its Send scout button."
	return "Click a tile to plan a route, click again to march. Right-click cancels. H: hero and army, T: town, Tab: next hero, S: scout the army under the pointer, arrows scroll, wheel or +/-: zoom, M: mute."


func is_down() -> bool:
	return _down


func is_dragging() -> bool:
	return _dragging


## Where the current (or last) press started.
func start_position() -> Vector2:
	return _start


## Forgets the current press (input was switched off while a finger was down).
func reset() -> void:
	_down = false
	_dragging = false


## The first finger touches the screen.
func press(pos: Vector2, now_ms: int) -> void:
	_down = true
	_start = pos
	_last = pos
	_start_ms = now_ms
	_dragging = false
	_long_fired = false
	_cancelled = false


## Another finger touches while the first is down: the press is spent and the
## caller should cancel (Kind.CANCEL), unless it was already a drag.
func second_finger() -> Kind:
	if not _down or _dragging or _cancelled:
		return Kind.NONE
	_cancelled = true
	return Kind.CANCEL


## The finger moved; returns how far to pan the map (zero until the press has
## become a drag).
func move(pos: Vector2) -> Vector2:
	if not _down or _cancelled:
		return Vector2.ZERO
	if not _dragging:
		if _long_fired or pos.distance_to(_start) < DRAG_SLOP:
			return Vector2.ZERO
		_dragging = true
	var d := pos - _last
	_last = pos
	return d


## Called every frame while the finger is down: true exactly once, when the
## finger has rested long enough to count as a long press.
func poll_long_press(now_ms: int) -> bool:
	if not _down or _dragging or _long_fired or _cancelled:
		return false
	if now_ms - _start_ms < LONG_PRESS_MS:
		return false
	_long_fired = true
	return true


## The finger lifts: what the press turned out to be.
func release(pos: Vector2, now_ms: int) -> Kind:
	if not _down:
		return Kind.NONE
	_down = false
	if _cancelled:
		return Kind.NONE
	if _dragging:
		return Kind.DRAG
	if _long_fired or now_ms - _start_ms >= LONG_PRESS_MS:
		return Kind.LONG_PRESS
	if pos.distance_to(_start) >= DRAG_SLOP:
		return Kind.DRAG
	return Kind.TAP
