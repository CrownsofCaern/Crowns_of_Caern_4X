extends SceneTree
## Render runtime Ashen clips at native size and verify every action resolves.

const OUT := "res://docs/art/production/demon-ready/"

class Gallery extends Control:
	var units: Array[String] = []
	var action := "idle"

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#17191f"))
		var font := ThemeDB.fallback_font
		for i in units.size():
			var pose := UnitAnimation.sample(units[i], action, 0.31)
			var at := Vector2((i % 4) * 320 + 160, (i / 4) * 190 + 174)
			if not pose.is_empty():
				var texture: Texture2D = pose["texture"]
				draw_texture_rect(texture, Rect2(at - Vector2(pose["anchor"]), texture.get_size()), false)
			draw_string(font, Vector2((i % 4) * 320 + 12, (i / 4) * 190 + 22), units[i].trim_prefix("creature_") + " / " + action, HORIZONTAL_ALIGNMENT_LEFT, 306, 13, Color("#dac59b"))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var gallery := Gallery.new()
	gallery.size = Vector2(1280, 800)
	root.add_child(gallery)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/creature_animations.json"))
	for group in spec["groups"]:
		if group["faction"] == "ashen":
			for unit in group["units"]:
				gallery.units.append("creature_" + String(unit["id"]))
	for action in ["idle", "move", "attack"]:
		for sid in gallery.units:
			if UnitAnimation.sample(sid, action, 0.31).is_empty():
				push_error("Missing Ashen clip: %s/%s" % [sid, action])
				quit(1)
				return
		gallery.action = action
		gallery.queue_redraw()
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + action + "-godot.png")
	print("ASHEN_ANIMATIONS_OK: 16 creatures, 48 runtime clips")
	quit(0)
