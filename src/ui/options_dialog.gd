class_name OptionsDialog
extends ModalPanel
## Options from the title screen and the in-game menu (Esc): fullscreen and
## brightness (VideoSettings), volume sliders per bus and a mute switch
## (AudioManager / AudioSettings). Changes apply and save at once; F11 toggles
## fullscreen and M mute on the map.

signal closed

const ROWS := [["Master", "Master volume"], ["Music", "Music"], ["SFX", "Effects"], ["UI", "Interface"]]


func open() -> void:
	set_menu_background("setup")
	_clear()
	_body.add_child(UiStyle.label("Options", 22, UiStyle.BRASS))
	_body.add_child(UiStyle.section("Display", 16))
	var video := VideoSettings.instance()
	if video != null and VideoSettings.can_fullscreen():
		var full := CheckBox.new()
		full.text = "Fullscreen (F11)"
		full.button_pressed = video.fullscreen
		full.toggled.connect(func(on: bool): video.set_fullscreen(on))
		_body.add_child(full)
	if video != null:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var cap := UiStyle.label("Brightness", 15, UiStyle.TEXT_DIM)
		cap.custom_minimum_size.x = 120
		row.add_child(cap)
		var b := HSlider.new()
		b.min_value = VideoSettings.MIN_BRIGHTNESS * 100
		b.max_value = VideoSettings.MAX_BRIGHTNESS * 100
		b.step = 5
		b.value = roundf(video.brightness * 100)
		b.custom_minimum_size = Vector2(260, 24)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		var bpct := UiStyle.label("%d%%" % int(b.value), 14)
		bpct.custom_minimum_size.x = 48
		row.add_child(bpct)
		b.value_changed.connect(func(v: float):
			bpct.text = "%d%%" % int(v)
			video.set_brightness(v / 100.0))
		_body.add_child(row)
	_body.add_child(UiStyle.section("Sound", 16))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	for row in ROWS:
		var bus: String = row[0]
		var name_label := UiStyle.label(row[1], 15, UiStyle.TEXT_DIM)
		name_label.custom_minimum_size.x = 120   # lines up with Brightness
		grid.add_child(name_label)
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
