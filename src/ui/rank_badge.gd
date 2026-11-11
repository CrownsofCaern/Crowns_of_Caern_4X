class_name RankBadge
extends RefCounted
## Veteran rank symbols drawn in a slot corner: one, two and three chevrons for
## levels 1-3, a gem for level 4 and a star for level 5. Simple vector shapes in
## brass with a dark outline, so they read at small sizes. To use painted art
## instead, drop res://assets/ui/ranks/rank_<level>.png (any square size);
## it replaces the drawn symbol for that level.

const ART_PATH := "res://assets/ui/ranks/rank_%d.png"
const OUTLINE := Color("#120d0b")
const STAR := Color("#f2c14e")


## The rank's name for tooltips and captions.
static func rank_name(level: int) -> String:
	return ["Recruit", "Blooded", "Seasoned", "Hardened", "Elite"][clampi(level, 1, 5) - 1]


## Painted art for the level, or null when the drawn symbol is used.
static func texture(level: int) -> Texture2D:
	return Art.texture_at(ART_PATH % clampi(level, 1, 5))


## The shapes of a rank as closed or open point lists inside a box of side
## `px` at the origin: {"chevrons": [PackedVector2Array...], "fill": PackedVector2Array}.
static func shapes(level: int, px: float) -> Dictionary:
	level = clampi(level, 1, 5)
	var out := {"chevrons": [], "fill": PackedVector2Array()}
	if level <= 3:
		var w := px
		var h := px * 0.32
		var step := px * 0.3
		var total := h + step * float(level - 1)
		var top := (px - total) * 0.5
		for i in level:
			var y := top + step * float(i)
			out["chevrons"].append(PackedVector2Array([Vector2(0, y + h), Vector2(w * 0.5, y), Vector2(w, y + h)]))
	elif level == 4:
		var c := Vector2(px, px) * 0.5
		out["fill"] = PackedVector2Array([c + Vector2(0, -px * 0.5), c + Vector2(px * 0.38, 0), c + Vector2(0, px * 0.5), c + Vector2(-px * 0.38, 0)])
	else:
		var c := Vector2(px, px) * 0.5 + Vector2(0, px * 0.04)
		var pts := PackedVector2Array()
		for i in 10:
			var r := px * (0.54 if i % 2 == 0 else 0.23)
			var a := -PI * 0.5 + PI * float(i) / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		out["fill"] = pts
	return out


## Draws the rank symbol of `level` with its top-left corner at `at`.
static func paint(canvas: CanvasItem, at: Vector2, level: int, px: float = 14.0) -> void:
	if level < 1:
		return
	var tex := texture(level)
	if tex != null:
		canvas.draw_texture_rect(tex, Rect2(at, Vector2(px, px)), false)
		return
	var s := shapes(level, px)
	var color := STAR if level >= 5 else UiStyle.BRASS
	var line := maxf(2.0, px * 0.17)
	for ch in s["chevrons"]:
		var pts := PackedVector2Array()
		for p in ch:
			pts.append(p + at)
		canvas.draw_polyline(pts, OUTLINE, line + 2.5, true)
	for ch in s["chevrons"]:
		var pts := PackedVector2Array()
		for p in ch:
			pts.append(p + at)
		canvas.draw_polyline(pts, color, line, true)
	var fill: PackedVector2Array = s["fill"]
	if not fill.is_empty():
		var pts := PackedVector2Array()
		for p in fill:
			pts.append(p + at)
		var ring := pts.duplicate()
		ring.append(pts[0])
		canvas.draw_polyline(ring, OUTLINE, 3.0, true)
		canvas.draw_colored_polygon(pts, color)
		canvas.draw_polyline(ring, color.lightened(0.35), 1.0, true)
