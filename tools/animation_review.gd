extends SceneTree
## DISPLAY=:92 godot --path . --audio-driver Dummy --script res://tools/animation_review.gd

const OUT := "res://docs/art/production/animations/"

class Gallery extends Control:
	var units: Array = []
	var action := "move"
	var elapsed := 0.22
	var heading := ""

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#17191f"))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(16,22), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#dac59b"))
		for i in units.size():
			var sid := String(units[i])
			var at := Vector2((i%4)*320+160, (i/4)*184+205)
			var texture := Art.sprite(sid)
			var anchor := Art.anchor(sid)
			var pose := UnitAnimation.sample(sid, action, elapsed)
			if not pose.is_empty():
				texture = pose["texture"]
				anchor = pose["anchor"]
			if texture != null:
				draw_texture_rect(texture, Rect2(at-anchor, texture.get_size()), false)
			draw_string(font, Vector2((i%4)*320+12, (i/4)*184+52), sid.trim_prefix("creature_").trim_prefix("hero_"), HORIZONTAL_ALIGNMENT_LEFT, 300, 13, Color("#cbbda5"))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var gallery := Gallery.new()
	gallery.size = Vector2(1280,800)
	gallery.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(gallery)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/creature_animations.json"))
	var factions := {}
	for group in spec["groups"]:
		if not factions.has(group["faction"]):
			factions[group["faction"]] = []
		for unit in group["units"]:
			factions[group["faction"]].append("creature_" + String(unit["id"]))
	factions["hero-knight"] = ["hero_knight"]
	for faction in factions:
		var units: Array = factions[faction]
		for start in range(0,units.size(),16):
			gallery.units = units.slice(start,mini(start+16,units.size()))
			for action in ["move","attack"]:
				if faction == "hero-knight" and action == "attack":
					continue
				gallery.action = action
				gallery.heading = "Crowns of Caern / %s / %s / Godot native-scale review" % [faction,action]
				gallery.queue_redraw()
				for frame in 3:
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUT + "%s-%02d-%s-godot.png" % [faction,start/16+1,action])
	# Exercise the same explicit action API that a future battle replay will drive.
	gallery.hide()
	var picture := BattleVignette.new()
	picture.size = Vector2(1000,240)
	picture.position = Vector2(140,250)
	root.add_child(picture)
	picture.setup("grass", [{"creature":"pike_militia","alive":true}], [{"creature":"marrow_archer","alive":true}])
	picture.play_action(false,0,"attack")
	picture.play_action(true,0,"attack")
	picture.set_process(false)
	picture._animation_time = 0.22
	picture.queue_redraw()
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"battle-vignette-actions-godot.png")
	gallery.queue_free()
	picture.queue_free()
	await process_frame
	quit(0)
