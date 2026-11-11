extends Control
## Cosmetic eight-second loops; the architecture and clickable footprint stay fixed.

const LOOP_SHADER = preload("res://assets/shaders/town_life.gdshader")
var _image: TextureRect
var _material: ShaderMaterial
var _features: Dictionary = {}
var _phase := 0.0
var _offset := 0.0
var _color := Color.WHITE


func configure(tex: Texture2D, profile: Dictionary, features: Dictionary, index: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_features = features
	_offset = fposmod(float(index) * 0.381966, 1.0)
	_color = Color(String(profile.get("light", "#ffad45")))
	_image = TextureRect.new()
	_image.texture = tex
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_image)
	_material = ShaderMaterial.new()
	_material.shader = LOOP_SHADER
	_material.set_shader_parameter("offset", _offset)
	_material.set_shader_parameter("light_color", Vector3(_color.r, _color.g, _color.b))
	var flag: Array = features.get("banner", [])
	if flag.size() == 4:
		_material.set_shader_parameter("banner", Vector4(flag[0], flag[1], flag[2], flag[3]))
	_image.material = _material


func set_phase(value: float) -> void:
	_phase = fposmod(value, 1.0)
	_material.set_shader_parameter("loop_phase", _phase)
	queue_redraw()


func set_highlight(value: bool) -> void:
	_image.self_modulate = Color(1.12, 1.12, 1.08) if value else Color.WHITE


func _draw() -> void:
	# Draw behind this building, but above earlier buildings in the town's depth order.
	for point in _features.get("smoke", []):
		var anchor := Vector2(point[0], point[1]) * size
		for i in 7:
			var age := fposmod(_phase * 2.0 + float(i) / 7.0 + _offset, 1.0)
			var envelope := sin(PI * age)
			var drift := Vector2(age * 15.0 + sin(TAU * (age + _phase)) * 3.0, -age * 43.0)
			var radius := (2.0 + age * 6.5) * size.y / 190.0
			draw_circle(anchor + drift * size.y / 190.0, radius, Color(0.63, 0.66, 0.69, envelope * 0.10))
	for point in _features.get("motes", []):
		var anchor := Vector2(point[0], point[1]) * size
		for i in 5:
			var age := fposmod(_phase + float(i) / 5.0 + _offset, 1.0)
			var drift := Vector2(sin(TAU * (age + _offset)) * 10.0, -age * 28.0) * size.y / 190.0
			var tint := _color
			tint.a = sin(PI * age) * 0.48
			draw_circle(anchor + drift, maxf(0.65, size.y / 220.0), tint)
