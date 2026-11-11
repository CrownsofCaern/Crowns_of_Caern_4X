extends SceneTree
## Review uses the real TownScene, BattleFigure and UnitAnimation renderers.
## Temporary GameData additions here exist only in this isolated art harness.

const OUT := "res://docs/art/production/dlc-factions/"
var pack: Dictionary
var canvas: Control


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int = 4) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")


func _new_page(title: String, color: Color) -> void:
	if canvas != null:
		canvas.free()
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = color
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(background)
	var label := Label.new()
	label.position = Vector2(24, 12)
	label.text = title
	label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(label)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	pack = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/dlc_factions.json"))
	var review_data := GameData.new()
	for fid in pack["factions"]:
		var faction: Dictionary = pack["factions"][fid]
		var color := Color("#14101c") if fid == "darkelf" else Color("#0c1a1b")
		_new_page(faction["name"] + " / native 128px creature review", color)
		var figures := []
		for i in faction["creature_ids"].size():
			var cid: String = faction["creature_ids"][i]
			var figure := BattleFigure.new()
			figure.setup(cid, 12, 1.0, 0.0)
			figure.position = Vector2(160 + (i % 4) * 320, 200 + (i / 4) * 175)
			canvas.add_child(figure)
			if not figure.has_move or not figure.has_attack:
				push_error("Missing real action clip: " + cid)
				quit(1)
				return
			figures.append(figure)
			var label := Label.new()
			label.position = figure.position + Vector2(-120, 22)
			label.text = pack["creatures"][cid]["name"]
			canvas.add_child(label)
		await _shot(fid + "-creatures-idle-godot")
		for figure in figures:
			figure.set_walking(true)
		await _frames(9)
		await _shot(fid + "-creatures-move-godot")
		for figure in figures:
			figure.set_walking(false)
			figure.start_attack()
		await _frames(10)
		await _shot(fid + "-creatures-attack-godot")
		for frame in 30:
			await process_frame
		for figure in figures:
			if figure.sprite.animation != "idle":
				push_error("Attack failed to recover to rest")
				quit(1)
				return
		_new_page(faction["name"] + " / three hero-class gaits", color)
		var heroes := []
		for i in faction["hero_ids"].size():
			var sid := "hero_" + String(faction["hero_ids"][i])
			var figure := Sprite2D.new()
			figure.centered = false
			figure.position = Vector2(220 + i * 420, 440)
			figure.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			canvas.add_child(figure)
			heroes.append({"sprite":figure,"id":sid})
		for phase in 4:
			for hero in heroes:
				var pose := UnitAnimation.sample(hero["id"], "move", phase * 0.08)
				hero["sprite"].texture = pose["texture"]
				hero["sprite"].offset = -pose["anchor"]
			await _shot(fid + "-hero-gait-%d-godot" % phase)
		_new_page(faction["name"] + " / modular town construction", color)
		var definitions := {}
		for bid in faction["building_ids"]:
			definitions[bid] = pack["buildings"][bid]
		review_data.town_types[fid] = {"buildings":definitions}
		var town := TownScene.new()
		town.position = Vector2(40, 50)
		town.size = Vector2(1200, 740)
		canvas.add_child(town)
		var scene := TownScene.scene_for(fid)
		for stage in 4:
			var built := []
			for slot in scene["slots"]:
				var variants: Array = slot["variants"]
				if stage == 0 and not slot["id"] in ["civic", "dw1"]:
					continue
				if stage == 1 and String(slot["id"]).begins_with("dw") and int(String(slot["id"]).trim_prefix("dw")) > 4:
					continue
				built.append(variants[mini(stage, variants.size() - 1)] if stage != 2 else variants[0])
			town.setup({"town_type":fid,"built":built}, review_data)
			await _shot(fid + "-town-stage-%d-godot" % (stage + 1))
	print("DLC_VISUAL_REVIEW_OK: 32 creatures, 64 clips, 6 hero gaits and 8 town states")
	quit(0)
