extends SceneTree
## Deterministic native-renderer frames for the eight-second town ambience loops.
## Godot --path . --resolution 960x640 --script res://tools/town_loop_review.gd -- OUTPUT

var _scene: TownScene
var _out := "/tmp/town-loops"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(960, 640)
	root.content_scale_size = Vector2i(960, 640)
	_scene = TownScene.new()
	_scene.animation_enabled = false
	_scene.size = Vector2(960, 640)
	root.add_child(_scene)
	_run.call_deferred()


func _run() -> void:
	var data := GameData.get_default()
	for faction in ["concord", "thornwood", "hollow", "frostmarch", "forge", "ashen", "darkelf", "fishmen"]:
		var built: Array = data.town_types[faction]["buildings"].keys()
		_scene.setup({"town_type": faction, "built": built}, data)
		# The final frame repeats time zero for an exact pixel seam comparison.
		for frame in 25:
			_scene.set_animation_time(float(frame) / 3.0)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_out.path_join("%s-%02d.png" % [faction, frame]))
		print("TOWN_LOOP ", faction)
	quit()
