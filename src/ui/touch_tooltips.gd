class_name TouchTooltips
extends Node
## Tooltips on a touch screen. Godot shows a Control's tooltip only after the
## mouse moves and rests, and a touch only sends clicks, so a finger never sees
## one. When a finger rests (TouchGestures' long press), this sends one mouse
## motion to where it rests; the tooltip then opens as for a resting mouse
## (quickly on phones: gui/timers/tooltip_delay_sec.mobile in project.godot).

var gestures := TouchGestures.new()
var _index := -1


func _input(event: InputEvent) -> void:
	var now := Time.get_ticks_msec()
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and not gestures.is_down():
			_index = st.index
			gestures.press(st.position, now)
		elif not st.pressed and st.index == _index:
			_index = -1
			gestures.release(st.position, now)
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _index:
		gestures.move((event as InputEventScreenDrag).position)


func _process(_delta: float) -> void:
	if gestures.is_down() and gestures.poll_long_press(Time.get_ticks_msec()):
		# Touch positions arrive in viewport units; parsed events start in window pixels.
		Input.parse_input_event(rest_event(get_viewport().get_final_transform() * gestures.start_position()))


## The mouse motion that stands for a finger resting at `pos` (window pixels). It is marked as
## emulated so the map does not take it for a real mouse.
static func rest_event(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.device = InputEvent.DEVICE_ID_EMULATION
	ev.position = pos
	ev.global_position = pos
	return ev
