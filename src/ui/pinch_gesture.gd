class_name PinchGesture
extends RefCounted
## Two fingers on the adventure map: spreading or pinching them zooms one
## level per step, a quick two-finger tap that barely moves cancels the planned
## route (the right click). Pure bookkeeping over positions and times the
## caller passes in, so it can be tested without a touch screen.

## Finger distance ratio for one zoom level.
const STEP_RATIO := 1.3
## A two-finger tap lifts within this many milliseconds...
const TAP_MS := 350
## ...and neither finger wanders further than this (screen pixels).
const TAP_SLOP := 18.0

var _first := -1
var _second := -1
var _pos := {}
var _start := {}
var _base := 1.0
var _start_ms := 0
var _zoomed := false


func is_active() -> bool:
	return _second >= 0


## A second finger lands while `first` is down.
func begin(first: int, first_pos: Vector2, second: int, second_pos: Vector2, now_ms: int) -> void:
	_first = first
	_second = second
	_pos = {first: first_pos, second: second_pos}
	_start = _pos.duplicate()
	_base = maxf(first_pos.distance_to(second_pos), 1.0)
	_start_ms = now_ms
	_zoomed = false


## Owns this finger (one of the two).
func tracks(index: int) -> bool:
	return is_active() and (index == _first or index == _second)


## A finger moved: +1 to zoom in a level, -1 to zoom out, 0 for nothing yet.
func move(index: int, pos: Vector2) -> int:
	if not tracks(index):
		return 0
	_pos[index] = pos
	var d := maxf((_pos[_first] as Vector2).distance_to(_pos[_second]), 1.0)
	if d / _base >= STEP_RATIO:
		_base = d
		_zoomed = true
		return 1
	if _base / d >= STEP_RATIO:
		_base = d
		_zoomed = true
		return -1
	return 0


## Where the zoom centres: between the fingers.
func midpoint() -> Vector2:
	if not is_active():
		return Vector2.ZERO
	return ((_pos[_first] as Vector2) + (_pos[_second] as Vector2)) * 0.5


## A finger lifts: the pinch is over. True when it was a two-finger tap.
func finish(now_ms: int) -> bool:
	if not is_active():
		return false
	var still := true
	for i in [_first, _second]:
		if (_pos[i] as Vector2).distance_to(_start[i]) > TAP_SLOP:
			still = false
	var tap := not _zoomed and still and now_ms - _start_ms <= TAP_MS
	_first = -1
	_second = -1
	return tap
