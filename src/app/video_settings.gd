class_name VideoSettings
extends CanvasLayer
## Display options (autoload "Video"): fullscreen and brightness, stored in
## user://settings.cfg [display] beside the audio settings. Brightness is a
## full-screen shader over everything, off at 100%. F11 toggles fullscreen.

const PATH := "user://settings.cfg"
const SECTION := "display"
const MIN_BRIGHTNESS := 0.5
const MAX_BRIGHTNESS := 1.5

static var _instance: VideoSettings

var path := PATH
var fullscreen := false
var brightness := 1.0
var _veil: ColorRect


static func instance() -> VideoSettings:
	return _instance


## Fullscreen only means something on desktop windows.
static func can_fullscreen() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("mobile") and not OS.has_feature("web")


func _init() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_instance = self
	_veil = ColorRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float brightness = 1.0;
void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	COLOR = vec4(clamp(c.rgb * brightness, 0.0, 1.0), 1.0);
}"""
	_veil.material = mat
	add_child(_veil)
	load_file()
	apply()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	fullscreen = bool(cfg.get_value(SECTION, "fullscreen", fullscreen))
	brightness = clampf(float(cfg.get_value(SECTION, "brightness", brightness)), MIN_BRIGHTNESS, MAX_BRIGHTNESS)


func save_file() -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)   # keep the audio section
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.set_value(SECTION, "brightness", brightness)
	return cfg.save(path)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply()
	save_file()


func set_brightness(v: float) -> void:
	brightness = clampf(v, MIN_BRIGHTNESS, MAX_BRIGHTNESS)
	apply()
	save_file()


func apply() -> void:
	if _veil != null:
		_veil.visible = absf(brightness - 1.0) > 0.001
		(_veil.material as ShaderMaterial).set_shader_parameter("brightness", brightness)
	if can_fullscreen():
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		var now := DisplayServer.window_get_mode()
		var is_full := now == DisplayServer.WINDOW_MODE_FULLSCREEN or now == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if is_full != fullscreen:
			DisplayServer.window_set_mode(want)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_F11 and can_fullscreen():
		get_viewport().set_input_as_handled()
		set_fullscreen(not fullscreen)
