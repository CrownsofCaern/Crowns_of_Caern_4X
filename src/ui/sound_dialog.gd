class_name SoundDialog
extends ModalPanel
## Volume sliders per bus and a mute switch. Changes apply and save at once
## (AudioManager / AudioSettings); M toggles mute on the map.

signal closed

const ROWS := [["Master", "Master volume"], ["Music", "Music"], ["SFX", "Effects"], ["UI", "Interface"]]


func open() -> void:
	set_menu_background("setup")
	_clear()
	_body.add_child(UiStyle.label("Sound", 22, UiStyle.BRASS))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	for row in ROWS:
		var bus: String = row[0]
		grid.add_child(UiStyle.label(row[1], 15, UiStyle.TEXT_DIM))
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 100
		s.step = 5
		s.value = roundf(AudioManager.volume(bus) * 100)
		s.custom_minimum_size = Vector2(260, 24)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var pct := UiStyle.label("%d%%" % int(s.value), 14)
		pct.custom_minimum_size.x = 48
		s.value_changed.connect(func(v: float):
			pct.text = "%d%%" % int(v)
			AudioManager.set_volume(bus, v / 100.0))
		# A sample of the bus on release, so the level can be judged.
		s.drag_ended.connect(func(_changed: bool):
			AudioManager.play("battle_start" if bus == "SFX" else "ui_click"))
		grid.add_child(s)
		grid.add_child(pct)
	var mute := CheckBox.new()
	mute.text = "Mute all sound"
	mute.button_pressed = AudioManager.is_muted()
	mute.toggled.connect(func(on: bool): AudioManager.set_muted(on))
	_body.add_child(mute)
	if AudioManager.instance() == null or not AudioManager.instance().enabled:
		_body.add_child(_wrapped("Audio is off in this session (headless or --mute).", 13, UiStyle.TEXT_DIM))
	_buttons([["Close", func():
		hide()
		closed.emit()]])
	show()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		hide()
		closed.emit()
