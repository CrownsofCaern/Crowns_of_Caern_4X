extends SceneTree
## Review-only overlays; the original painting and live campaign UI are untouched.

const OUT := "res://docs/art/production/world-atlas/"
var atlas: Dictionary
var data: GameData
var canvas: Node2D
var image: Texture2D
var font := ThemeDB.fallback_font
const SIZE := Vector2(1536, 1024)


class Overlay:
	extends Node2D
	var draw_content: Callable
	func _draw() -> void:
		draw_content.call(self)


func _initialize() -> void:
	_run.call_deferred()


func _label(node: Node2D, text: String, at: Vector2, color: Color = Color("dfcc9c"), size: int = 19) -> void:
	var dimensions := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var origin := at - Vector2(dimensions.x * 0.5, 0)
	(node as CanvasItem).draw_style_box(_box(), Rect2(origin - Vector2(6, size), dimensions + Vector2(12, 8)))
	(node as CanvasItem).draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _box() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.05, 0.87)
	style.set_corner_radius_all(3)
	return style


func _overview(node: Node2D) -> void:
	node.draw_texture_rect(image, Rect2(Vector2.ZERO, SIZE), false)
	# Territorial overlays stay separate from the source; these are spheres of influence.
	for key in atlas["empires"]:
		var empire: Dictionary = atlas["empires"][key]
		var color := Color(data.factions[empire["faction"]]["color"]).lightened(.25)
		var polygon := PackedVector2Array()
		for p in empire["influence_polygon"]:
			polygon.append(Vector2(p[0], p[1]) * SIZE)
		node.draw_colored_polygon(polygon, Color(color, .045))
		polygon.append(polygon[0])
		node.draw_polyline(polygon, Color(color, .55), 1.5, true)
		for settlement in empire["hinterland_settlements"]:
			var at := Vector2(settlement["at"][0], settlement["at"][1]) * SIZE
			# Tiny schematic settlements establish scale without inventing story towns.
			node.draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color("101519"))
			node.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), color, false, 1.2)
			if settlement["kind"] == "city":
				node.draw_circle(at, 1.4, color)
		var label := Vector2(empire["label_at"][0], empire["label_at"][1]) * SIZE
		_label(node, empire["name"].to_upper(), label, color, 20)
	_label(node, "Uncharted western reaches", Vector2(.12,.15) * SIZE, Color("dfcc9c"), 17)
	_label(node, "Eastern sea / Atlantis reserved", Vector2(.85,.87) * SIZE, Color("91c9ca"), 18)
	var label_offsets := {"greyhold":Vector2(-25,-20), "burning_ford":Vector2(45,40), "highmere":Vector2(0,25), "last_grove":Vector2(0,25), "lockstone":Vector2(55,-20)}
	for key in ["greyhold","burning_ford","highmere","last_grove","lockstone"]:
		var landmark: Dictionary = atlas["landmarks"][key]
		var at := Vector2(landmark["at"][0],landmark["at"][1]) * SIZE
		node.draw_circle(at, 4, Color("f3d47e"))
		_label(node, landmark["name"], at + label_offsets[key], Color("f3dfb0"), 15)
	var gateways: Array = atlas["layers"]["deep_underworld"]["surface_gateways"]
	for p in gateways:
		var at := Vector2(p[0],p[1]) * SIZE
		node.draw_arc(at, 12, 0, TAU, 40, Color("b48ce0"), 2, true)
	_label(node, "Sealed depths: dark-elf realm reserved below", Vector2(.25,.76) * SIZE, Color("c9a4ea"), 15)
	_label(node, "EMPIRE ATLAS / schematic influence boundaries / small squares: unnamed settlements / north at top", Vector2(.5,.97) * SIZE, Color("d8d2bc"), 16)


func _route(node: Node2D, campaign_id: String) -> void:
	node.draw_texture_rect(image, Rect2(Vector2.ZERO, SIZE), false)
	var campaign: Dictionary = data.campaigns[campaign_id]
	var color := Color(data.factions[campaign["faction"]]["color"]).lightened(.25)
	var route: Array = atlas["campaign_routes"][campaign_id]
	for i in route.size() - 1:
		var a: Dictionary = atlas["landmarks"][route[i]]
		var b: Dictionary = atlas["landmarks"][route[i+1]]
		var start := Vector2(a["at"][0],a["at"][1]) * SIZE
		var end := Vector2(b["at"][0],b["at"][1]) * SIZE
		node.draw_line(start, end, Color(0,0,0,.8), 7, true)
		if a["layer"] != "surface" or b["layer"] != "surface":
			node.draw_dashed_line(start, end, color, 3, 10, true)
		else:
			node.draw_line(start, end, color, 3, true)
	var visits := {}
	for i in route.size():
		if not visits.has(route[i]):
			visits[route[i]] = []
		visits[route[i]].append(str(i + 1))
	for key in visits:
		var landmark: Dictionary = atlas["landmarks"][key]
		var at := Vector2(landmark["at"][0],landmark["at"][1]) * SIZE
		var text := ",".join(visits[key])
		var radius := 18 if visits[key].size() > 1 else 14
		node.draw_circle(at, radius, Color("11161b"))
		node.draw_arc(at, radius, 0, TAU, 40, color, 2, true)
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		node.draw_string(font, at + Vector2(-width * .5,6), text, HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
	_label(node, campaign["name"] + " / geographic route index", Vector2(.5,.06) * SIZE, color, 25)
	_label(node, "Dashed: underground / Regional campaign paintings will use closer, authored compositions", Vector2(.5,.97) * SIZE, Color("dfd8c6"), 17)


func _shot(name: String, draw_content: Callable) -> void:
	var overlay := Overlay.new()
	overlay.draw_content = draw_content
	canvas.add_child(overlay)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	overlay.free()


func _run() -> void:
	root.content_scale_size = Vector2i(SIZE)
	root.size = Vector2i(SIZE)
	DirAccess.make_dir_recursive_absolute(OUT)
	atlas = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/world_atlas.json"))
	data = GameData.get_default()
	var original := Image.new()
	if original.load_png_from_buffer(FileAccess.get_file_as_bytes("res://" + atlas["source"])) != OK:
		quit(1)
		return
	image = ImageTexture.create_from_image(original)
	canvas = Node2D.new()
	root.add_child(canvas)
	await _shot("world-geography-proposal", _overview)
	for campaign_id in atlas["campaign_routes"]:
		await _shot(campaign_id + "-route-proposal", _route.bind(campaign_id))
	print("WORLD_ATLAS_REVIEW_OK: shared geography and six campaign routes; no production UI changes")
	quit(0)
