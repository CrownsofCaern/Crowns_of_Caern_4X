class_name TownPicture
extends Control
## Town header picture: the town sprite on its hill under a dusk sky, in a
## slot frame, with the faction colour on a pennant strip. Drawing only.

const SKY_TOP := Color("#16080a")
const SKY_LOW := Color("#5a1410")

var town_tex: Texture2D
var accent := UiStyle.BRASS
var pixel_scale := 1
var _sky: GradientTexture2D
var _frame: StyleBox


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(210, 104)
	_frame = UiStyle.slot_box(2.0)
	var g := Gradient.new()
	g.set_color(0, Color(UiStyle.palette()["background"]))
	g.set_color(1, Color(UiStyle.palette()["raised"]))
	_sky = GradientTexture2D.new()
	_sky.gradient = g
	_sky.fill_from = Vector2(0.5, 0.0)
	_sky.fill_to = Vector2(0.5, 1.0)
	_sky.width = 8
	_sky.height = 64


func setup(tex: Texture2D, accent_color: Color) -> void:
	town_tex = tex
	accent = accent_color
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _frame != null:
		draw_style_box(_frame, r)
	var inner := r.grow(-4)
	var horizon := inner.position.y + inner.size.y * 0.72
	draw_texture_rect(_sky, Rect2(inner.position, Vector2(inner.size.x, horizon - inner.position.y)), false)
	draw_rect(Rect2(inner.position.x, horizon, inner.size.x, inner.end.y - horizon), Color("#1c1816"))
	# Distant ridge line.
	var pts := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var x := inner.position.x + inner.size.x * i / steps
		pts.append(Vector2(x, horizon - 6.0 - float((i * 37) % 11)))
	pts.append(Vector2(inner.end.x, horizon))
	pts.append(Vector2(inner.position.x, horizon))
	draw_colored_polygon(pts, Color("#2a1210"))
	if town_tex != null:
		var d := town_tex.get_size() * pixel_scale
		d *= minf(1.0, minf(inner.size.x / d.x, inner.size.y / d.y))
		draw_texture_rect(town_tex, Rect2(Vector2(inner.position.x + (inner.size.x - d.x) * 0.5, inner.end.y - d.y - 2), d), false)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 3)), accent)
	draw_rect(inner, UiStyle.accent().darkened(0.35), false, 1.0)


func _refresh_faction_style() -> void:
	_frame = UiStyle.slot_box(2.0)
	if _sky != null:
		_sky.gradient.set_color(0, Color(UiStyle.palette()["background"]))
		_sky.gradient.set_color(1, Color(UiStyle.palette()["raised"]))
	queue_redraw()
