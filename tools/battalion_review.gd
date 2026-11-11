extends SceneTree
## Renders the live battle view with battalions and battle orders at a few
## moments of a recorded fight (for checking the look by eye):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/battalion_review.gd -- /tmp/out

var viewer: BattleViewer


func _initialize() -> void:
	_run.call_deferred()


func _side(pairs: Array, title: String, orders: Dictionary) -> Dictionary:
	var stacks := []
	for i in pairs.size():
		stacks.append({"slot": i, "creature": pairs[i][0], "count": pairs[i][1]})
	var hero := {"name": title, "attack": 2, "defense": 2, "power": 0, "knowledge": 0, "skills": {}, "orders": orders}
	return {"name": title, "hero": hero, "stacks": stacks}


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "user://battalions"
	DirAccess.make_dir_recursive_absolute(out)
	var data := GameData.get_default()
	var left := _side([["pike_militia", 40], ["shieldwarden", 12], ["longbowman", 30], ["lancer", 6], ["lightbearer", 3], ["bastion_colossus", 1]],
		"Aldmere Concord", {"stance": "defensive", "focus": "protect_archers"})
	var right := _side([["cinderling", 60], ["flayer", 14], ["brimstone_hurler", 20], ["scorchhound", 12], ["gorgewing", 2]],
		"Ashen Host", {"stance": "aggressive", "focus": "hunt_archers"})
	var result := CombatSimulator.new(data).simulate(CombatSimulator.make_setup(left, right, "grass", 21), true)
	viewer = BattleViewer.new()
	root.add_child(viewer)
	viewer.build()
	viewer.play(result)
	viewer._set_speed(2.0, false)
	var shots := [20, 160, 420, 800]
	var n := 0
	for frame in 4000:
		await process_frame
		if not viewer.is_playing():
			break
		if n < shots.size() and frame == shots[n]:
			await _shot("%s/battalions_%d.png" % [out, n])
			n += 1
	print("BATTALION_REVIEW_OK ", n)
	quit()
