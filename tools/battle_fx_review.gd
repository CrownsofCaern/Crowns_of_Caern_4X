extends SceneTree
## Renders review frames of the live battle with elemental effects: a casters' battle, captured every few frames.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/battle_fx_review.gd -- /tmp/fx

var out_dir := "/tmp/battle_fx"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	_run.call_deferred()


func _side(stacks: Array, title: String) -> Dictionary:
	var units := []
	for i in stacks.size():
		units.append({"slot": i, "creature": stacks[i][0], "count": stacks[i][1]})
	return {"name": title, "hero": null, "stacks": units}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	var data := GameData.get_default()
	var left := _side([["ash_witch", 14], ["frost_shaman", 12], ["storm_shaman", 6], ["plague_lobber", 10], ["frost_drake", 3]], "Casters")
	var right := _side([["pike_militia", 40], ["shambler", 30], ["thornwolf", 10], ["de_mirror_witch", 8], ["doom_bombard", 3]], "Wall")
	if OS.get_cmdline_user_args().has("armies"):
		# Two full field armies, for the clash (RTS-like) view.
		left = _side([["pike_militia", 60], ["longbowman", 30], ["ash_witch", 12], ["shambler", 30], ["thornwolf", 14], ["cairn_giant", 3], ["frost_drake", 4]], "Host of the West")
		right = _side([["shambler", 70], ["marrow_archer", 30], ["pike_militia", 40], ["frost_shaman", 12], ["thornwolf", 16], ["winter_wyrm_ancient", 1], ["doom_bombard", 3]], "Host of the East")
	var result := CombatSimulator.new(data).simulate(CombatSimulator.make_setup(left, right, "grass", 11), true)
	var viewer := BattleViewer.new()
	root.add_child(viewer)
	viewer.build()
	viewer.play(result)
	var frame := 0
	var saved := 0
	while viewer.is_playing() and frame < 2400 and saved < 400:
		await process_frame
		await RenderingServer.frame_post_draw
		frame += 1
		if frame % 3 == 0:
			root.get_texture().get_image().save_png("%s/f_%04d.png" % [out_dir, saved])
			saved += 1
	print("saved %d frames to %s" % [saved, out_dir])
	quit()

