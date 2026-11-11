extends SceneTree
## Exercise real BattleViewer replay with atlas clips and verify final counts.

var viewer: BattleViewer


func _initialize() -> void:
	_run.call_deferred()


func _side(stacks: Array, title: String) -> Dictionary:
	var units := []
	for i in stacks.size():
		units.append({"slot":i,"creature":stacks[i][0],"count":stacks[i][1]})
	return {"name":title,"hero":null,"stacks":units}


func _run() -> void:
	var data := GameData.get_default()
	var left := _side([["pike_militia",12],["longbowman",8]],"Aldmere Concord")
	var right := _side([["shambler",14],["marrow_archer",7]],"Hollow Dominion")
	var result := CombatSimulator.new(data).simulate(CombatSimulator.make_setup(left,right,"grass",17),true)
	viewer = BattleViewer.new()
	root.add_child(viewer)
	viewer.build()
	viewer.play(result)
	viewer._set_speed(2.0,false)
	DirAccess.make_dir_recursive_absolute("/tmp/crowns-live-battle")
	var saw_move := false
	var saw_attack := false
	var verified_counts := false
	var shot := 0
	for frame in 1800:
		await process_frame
		await RenderingServer.frame_post_draw
		if not viewer.is_playing():
			break
		var moving := false
		var attacking := false
		for figure in viewer._figs.values():
			moving = moving or figure.sprite.animation == "move"
			attacking = attacking or figure.sprite.animation == "attack"
			if not figure.has_move or not figure.has_attack:
				push_error("Live replay used a missing-clip fallback")
				quit(1)
				return
		var image := root.get_texture().get_image()
		if moving and not saw_move:
			image.save_png("res://docs/art/production/animations/live-battle-movement-godot.png")
			saw_move = true
		if attacking and not saw_attack:
			image.save_png("res://docs/art/production/animations/live-battle-attack-godot.png")
			saw_attack = true
		if viewer._verdict.text != "" and not verified_counts:
			var expected := BattleReplay.from_result(result).final_counts()
			for key in expected:
				if viewer._figs[key].count != int(expected[key]):
					push_error("Animation replay changed final survivors")
					quit(1)
					return
			image.save_png("res://docs/art/production/animations/live-battle-result-godot.png")
			verified_counts = true
		if frame % 3 == 0:
			image.resize(640,400,Image.INTERPOLATE_LANCZOS)
			image.save_png("/tmp/crowns-live-battle/%04d.png" % shot)
			shot += 1
	if not saw_move or not saw_attack or not verified_counts or viewer.is_playing():
		push_error("Incomplete animated battle review")
		quit(1)
		return
	print("LIVE_ANIMATED_REPLAY_OK: movement, attacks and exact final survivors")
	viewer.queue_free()
	await process_frame
	quit(0)
