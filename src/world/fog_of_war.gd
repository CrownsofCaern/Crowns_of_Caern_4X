class_name FogOfWar
extends RefCounted
## Per-player explored-tile mask. Tiles, once explored, stay revealed (classic
## shroud); a "currently visible" layer can be added later for hidden movement.

var width: int
var height: int
var explored: PackedByteArray = PackedByteArray()


func _init(w: int = 0, h: int = 0) -> void:
	width = w
	height = h
	explored.resize(w * h)


func is_explored(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= width or p.y >= height:
		return false
	return explored[p.y * width + p.x] == 1


## Reveals a disc of `radius` around `center`. Returns how many tiles were newly revealed.
func reveal(center: Vector2i, radius: int) -> int:
	var newly := 0
	var r2 := radius * radius + radius  # slightly rounder disc
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > r2:
				continue
			var p := center + Vector2i(dx, dy)
			if p.x < 0 or p.y < 0 or p.x >= width or p.y >= height:
				continue
			var i := p.y * width + p.x
			if explored[i] == 0:
				explored[i] = 1
				newly += 1
	return newly


func explored_count() -> int:
	return explored.count(1)


func to_dict() -> Dictionary:
	return {"width": width, "height": height, "explored": Marshalls.raw_to_base64(explored)}


static func from_dict(d: Dictionary) -> FogOfWar:
	var f := FogOfWar.new(int(d["width"]), int(d["height"]))
	var raw := Marshalls.base64_to_raw(d["explored"])
	if raw.size() == f.explored.size():
		f.explored = raw
	return f
