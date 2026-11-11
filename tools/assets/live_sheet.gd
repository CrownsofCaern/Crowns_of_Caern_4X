extends SceneTree
## Renders live 3D units (assets/units3d GLBs, through LiveUnit) as a frame
## grid, one row per unit and clip, for checking exports without the game:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/assets/live_sheet.gd -- OUT.png [--dir res://assets/units3d/] [--clips idle,move,attack,death] [--frames 6] [--top] ids...

const CELL := Vector2i(220, 220)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var dir := LiveUnit.DIR
	var clips := ["idle", "move", "attack", "death"]
	var frames := 6
	var top := false
	var ids: Array[String] = []
	var i := 1
	while i < args.size():
		match args[i]:
			"--dir":
				i += 1
				dir = args[i].trim_suffix("/") + "/"
			"--clips":
				i += 1
				clips = Array(args[i].split(","))
			"--frames":
				i += 1
				frames = int(args[i])
			"--top":
				top = true
			_:
				ids.append(args[i])
		i += 1
	var vp := SubViewport.new()
	vp.size = CELL
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.32, 0.25)
	ground.material_override = gm
	vp.add_child(ground)
	var cam := Camera3D.new()
	vp.add_child(cam)
	var rows := []
	for id in ids:
		for clip in clips:
			rows.append([id, clip])
	var sheet := Image.create(CELL.x * frames + 160, CELL.y * rows.size(), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	var r := 0
	for row in rows:
		var unit := LiveUnit.spawn(row[0], dir)
		if unit == null:
			r += 1
			continue
		vp.add_child(unit)
		unit.rotation.y = 0.0 if top else deg_to_rad(-25.0)  # faces +X (screen right)
		var h := maxf(unit.height, unit.radius * 2.0)
		cam.fov = 40.0
		if top:
			# Straight down, +X to the right, -Z up the image.
			cam.position = Vector3(0.0, h * 4.0, 0.001)
			cam.look_at(Vector3.ZERO, Vector3.FORWARD)
		else:
			cam.position = Vector3(0.0, h * 0.9, h * 2.6)
			cam.look_at(Vector3(0.0, h * 0.45, 0.0))
		if unit.has_clip(row[1]):
			var anim := unit.player.get_animation(row[1])
			unit.player.play(row[1])
			for f in frames:
				unit.player.seek(anim.length * float(f) / float(frames if row[1] in LiveUnit.LOOPS else maxi(1, frames - 1)), true)
				unit.player.pause()
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(160 + f * CELL.x, r * CELL.y))
		print("%s %s %s" % [row[0], row[1], "ok" if unit.has_clip(row[1]) else "MISSING"])
		unit.queue_free()
		await process_frame
		r += 1
	sheet.save_png(out)
	quit(0)
