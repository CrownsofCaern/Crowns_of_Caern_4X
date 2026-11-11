class_name MapCamera
extends RefCounted
## Camera math for the adventure map: three zoom levels (twice as far, the
## default, twice as close), where the map sits in the view area for a focus
## point, and which point stays put under the pointer while zooming. Pure
## functions so the screen code stays thin and the math is testable.
##
## "Map pixels" are unscaled MapView coordinates (MapView.TILE per cell);
## "view" coordinates are relative to the top-left of the map's view area.

const LEVELS: Array[float] = [0.5, 1.0, 2.0]
const DEFAULT_LEVEL := 1


static func zoom_of(level: int) -> float:
	return LEVELS[clampi(level, 0, LEVELS.size() - 1)]


## The level `steps` levels closer (positive) or farther (negative), kept in range.
static func stepped(level: int, steps: int) -> int:
	return clampi(level + steps, 0, LEVELS.size() - 1)


## View position of the map's top-left corner so that `focus` (map pixels) sits
## in the middle of the view where possible. The map never leaves a gap at an
## edge it could fill; a map smaller than the view is centred on that axis.
static func map_origin(view: Vector2, map_px: Vector2, focus: Vector2, zoom: float) -> Vector2:
	var size := map_px * zoom
	var target := view * 0.5 - focus * zoom
	var out := Vector2.ZERO
	for axis in 2:
		if size[axis] <= view[axis]:
			out[axis] = roundf((view[axis] - size[axis]) * 0.5)
		else:
			out[axis] = roundf(clampf(target[axis], view[axis] - size[axis], 0.0))
	return out


## The focus (map pixels at the view centre) that a map at `origin` shows.
static func focus_of(view: Vector2, origin: Vector2, zoom: float) -> Vector2:
	return (view * 0.5 - origin) / zoom


## Keeps a focus inside the range where the map still fills the view, so that
## scrolling past an edge does not build up and need undoing.
static func clamp_focus(focus: Vector2, view: Vector2, map_px: Vector2, zoom: float) -> Vector2:
	var half := view * 0.5 / zoom
	var out := focus
	for axis in 2:
		if map_px[axis] <= half[axis] * 2.0:
			out[axis] = map_px[axis] * 0.5
		else:
			out[axis] = clampf(focus[axis], half[axis], map_px[axis] - half[axis])
	return out


## The focus that keeps map pixel `point` under view position `anchor` at `zoom`.
static func focus_for_anchor(point: Vector2, anchor: Vector2, view: Vector2, zoom: float) -> Vector2:
	return point - (anchor - view * 0.5) / zoom


## Cells shown in the view (for the minimap frame), clipped to the map.
static func visible_cells(view: Vector2, map_cells: Vector2i, origin: Vector2, zoom: float) -> Rect2i:
	var cell := MapView.TILE * zoom
	var tl := Vector2i((-origin / cell).floor())
	var br := Vector2i(((view - origin) / cell).ceil())
	tl = tl.clamp(Vector2i.ZERO, map_cells)
	br = br.clamp(Vector2i.ZERO, map_cells)
	return Rect2i(tl, br - tl)
