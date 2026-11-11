class_name MapPreview
extends RefCounted
## Minimap image of any map definition, for PRs and contact sheets. Pure Image
## drawing, so it works headless (no renderer, no fonts).
## Legend: ground in terrain colours, roads in road colour; towns are big
## squares and heroes diamonds in their owner's colour (neutral towns grey);
## mines gold, resource piles teal, guards/neutral armies red, encounters
## orange, sites violet, artifacts pink, scenario sites/quest items/gates
## white-cored; scenario "reach" targets get a yellow frame.

const OBJECT_COLORS := {
	"mine": "#e8c547", "resource": "#5ac8c8", "neutral_army": "#d8322a", "encounter": "#e0892c",
	"site": "#9a6ae0", "artifact": "#ff7ae0", "scenario_site": "#ffffff", "quest_item": "#ffffff",
	"gate": "#ffffff",
}
const NEUTRAL := "#9a9a9a"
const OUTLINE := Color(0.05, 0.04, 0.04)
const REACH := "#ffe040"


static func render(definition: Dictionary, data: GameData, tile: int = 6) -> Image:
	tile = maxi(tile, 2)
	var map := AdventureMap.from_definition(definition.merged({"objects": [], "heroes": []}, true), data)
	var image := Image.create(map.width * tile, map.height * tile, false, Image.FORMAT_RGBA8)
	var road := Color(String(data.road.get("color", "#8a6a44")))
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var colour := Color(String(data.terrain(map.terrain_at(cell)).get("color", "#777777")))
			if map.has_road(cell):
				colour = road
			image.fill_rect(Rect2i(x * tile, y * tile, tile, tile), colour)
	var owners := {}
	for player in definition.get("players", []):
		owners[int(player.get("id", -1))] = Color(String(player.get("color", NEUTRAL)))
	# Small markers first so towns and heroes stay on top.
	for object in definition.get("objects", []):
		var type := String(object.get("type", ""))
		if type == "town":
			continue
		var colour := Color(String(OBJECT_COLORS.get(type, "#000000")))
		if type in ["mine", "site"] and int(object.get("owner", -1)) >= 0:
			colour = owners.get(int(object["owner"]), colour)
		_square(image, _pos(object), tile, 1, colour, type in ["scenario_site", "quest_item", "gate"])
	for object in definition.get("objects", []):
		if String(object.get("type", "")) == "town":
			_square(image, _pos(object), tile, 3, owners.get(int(object.get("owner", -1)), Color(NEUTRAL)), false)
	for hero in definition.get("heroes", []):
		_diamond(image, _pos(hero), tile, owners.get(int(hero.get("owner", -1)), Color(NEUTRAL)))
	for objective in definition.get("scenario", {}).get("objectives", []):
		if objective is Dictionary and String(objective.get("type", "")) == "reach" and objective.get("pos") is Array:
			_frame(image, Vector2i(int(objective["pos"][0]), int(objective["pos"][1])), tile, Color(REACH))
	return image


## Renders and writes a PNG. Returns "" or an error.
static func save_png(definition: Dictionary, data: GameData, path: String, tile: int = 6) -> String:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := render(definition, data, tile).save_png(absolute)
	return "" if error == OK else "Cannot write %s: %s." % [absolute, error_string(error)]


static func _pos(entity: Dictionary) -> Vector2i:
	var p: Array = entity.get("pos", [0, 0])
	return Vector2i(int(p[0]), int(p[1]))


## A square `span` tiles wide (rounded to odd), centred on the tile, outlined.
static func _square(image: Image, cell: Vector2i, tile: int, span: int, colour: Color, hollow: bool) -> void:
	var half := (span * tile) / 2
	var centre := cell * tile + Vector2i(tile / 2, tile / 2)
	var outer := Rect2i(centre - Vector2i(half, half) - Vector2i.ONE, Vector2i(half * 2 + 2, half * 2 + 2))
	if span == 1:
		outer = Rect2i(cell * tile, Vector2i(tile, tile))
	outer = outer.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image.fill_rect(outer, OUTLINE)
	var inner := outer.grow(-1)
	if inner.size.x <= 0 or inner.size.y <= 0:
		image.fill_rect(outer, colour)
		return
	image.fill_rect(inner, colour)
	if hollow and inner.size.x > 2:
		image.fill_rect(inner.grow(-1), OUTLINE)


static func _diamond(image: Image, cell: Vector2i, tile: int, colour: Color) -> void:
	var centre := cell * tile + Vector2i(tile / 2, tile / 2)
	var radius := maxi(tile, 2)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var distance := absi(dx) + absi(dy)
			var p := centre + Vector2i(dx, dy)
			if distance > radius or p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height():
				continue
			image.set_pixelv(p, OUTLINE if distance == radius else colour)


static func _frame(image: Image, cell: Vector2i, tile: int, colour: Color) -> void:
	var rect := Rect2i(cell * tile - Vector2i(tile, tile), Vector2i(tile * 3, tile * 3)).intersection(
		Rect2i(Vector2i.ZERO, image.get_size()))
	for x in range(rect.position.x, rect.end.x):
		for y in [rect.position.y, rect.end.y - 1]:
			image.set_pixel(x, y, colour)
	for y in range(rect.position.y, rect.end.y):
		for x in [rect.position.x, rect.end.x - 1]:
			image.set_pixel(x, y, colour)
