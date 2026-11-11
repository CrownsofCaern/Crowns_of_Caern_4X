class_name HeroPortrait
extends Control
## Framed hero picture: the mounted hero sprite with its banner in the owner's
## colour, over a dusk backdrop (blood-red sky fading into dark ground), drawn
## at an integer scale. Click to open the hero screen.

signal pressed

const SKY_TOP := Color("#2e0c0c")
const SKY_LOW := Color("#5a1410")
const GROUND := Color("#1c1816")

var pixel_scale := 1
var banner_color := Color.WHITE
var _frame: StyleBox
var _hero: Texture2D
var _profile: Texture2D
var _banner: Texture2D
var _sky: GradientTexture2D


func _init(scale_px: int = 1) -> void:
	pixel_scale = scale_px
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	_frame = UiStyle.slot_box(2.0)
	_hero = Art.sprite("hero_knight")
	_banner = Art.sprite("hero_banner")
	var g := Gradient.new()
	g.set_color(0, Color(UiStyle.palette()["background"]))
	g.set_color(1, Color(UiStyle.palette()["raised"]))
	g.add_point(0.72, Color(UiStyle.palette()["raised"]).lightened(0.04))
	_sky = GradientTexture2D.new()
	_sky.gradient = g
	_sky.fill_from = Vector2(0.5, 0.0)
	_sky.fill_to = Vector2(0.5, 1.0)
	_sky.width = 8
	_sky.height = 64
	custom_minimum_size = Vector2(64, 64) * pixel_scale + Vector2(8, 8)


## A named character portrait, otherwise the hero class portrait.
func set_hero_class(class_id: String) -> void:
	set_hero("", class_id)


func set_hero(hero_id: String, class_id: String) -> void:
	_profile = Art.hero_profile(hero_id, class_id)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if _profile != null else CanvasItem.TEXTURE_FILTER_NEAREST
	var tex := Art.hero(class_id)
	if tex != null and tex != _hero:
		_hero = tex
	queue_redraw()


func set_owner_color(c: Color) -> void:
	banner_color = Art.banner_tint(c)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _frame != null:
		draw_style_box(_frame, r)
	var inner := r.grow(-4)
	if _profile != null:
		draw_texture_rect(_profile, inner, false)
		draw_rect(inner, banner_color.darkened(0.25), false, 2.0)
		return
	draw_texture_rect(_sky, Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.7)), false)
	draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.7), Vector2(inner.size.x, inner.size.y * 0.3)), GROUND)
	if _hero != null:
		var hr := hero_rect()
		draw_texture_rect(_hero, hr, false)
		if _banner != null:
			draw_texture_rect(_banner, hr, false, banner_color)
	draw_rect(inner, UiStyle.accent().darkened(0.35), false, 1.0)


## Where the hero sprite is drawn: at pixel_scale, but never larger than the
## frame's inside (sprites may be higher resolution than the 64 px frame, such
## as the 128 px production art), centred and standing on the frame's floor.
func hero_rect() -> Rect2:
	if _hero == null:
		return Rect2()
	var inner := Rect2(Vector2.ZERO, size).grow(-4)
	var src := _hero.get_size()
	var fit := minf(inner.size.x / src.x, inner.size.y / src.y)
	var d := src * minf(float(pixel_scale), fit)
	return Rect2(Vector2((size.x - d.x) * 0.5, inner.end.y - d.y), d)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func _refresh_faction_style() -> void:
	_frame = UiStyle.slot_box(2.0)
	if _sky != null:
		_sky.gradient.set_color(0, Color(UiStyle.palette()["background"]))
		_sky.gradient.set_color(1, Color(UiStyle.palette()["raised"]).lightened(0.04))
		_sky.gradient.set_color(2, Color(UiStyle.palette()["raised"]))
	queue_redraw()
