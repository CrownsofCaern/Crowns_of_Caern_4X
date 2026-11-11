extends SceneTree
## Render every terrain/variant in the real viewer and the compact forecast band.

const OUT := "res://docs/art/production/battlefields/"
var viewer: BattleViewer


func _initialize() -> void:
	_run.call_deferred()


func _side(ids: Array, title: String) -> Dictionary:
	var stacks := []
	for i in ids.size():
		stacks.append({"slot":i,"creature":ids[i],"count":12})
	return {"name":title,"hero":null,"stacks":stacks}


func _shot(path: String) -> void:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+path+".png")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var data := GameData.get_default()
	var left := _side(["pike_militia","shieldwarden","bulwark_sworn","pike_veteran","bastion_colossus","warbow_sergeant","lancer","lightbearer","sunhawk_rider","iron_margrave"],"Aldmere Concord")
	var right := _side(["shambler","rotting_shambler","marrow_archer","marrow_deadeye","gravecrawler","wailing_shade","corpse_weaver","gibbet_knight","charnel_hulk","rotwing_leviathan"],"Hollow Dominion")
	var result := CombatSimulator.new(data).simulate(CombatSimulator.make_setup(left,right,"grass",17),true)
	viewer = BattleViewer.new()
	root.add_child(viewer)
	viewer.build()
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/battlefields.json"))
	var visits := {}
	for asset in spec["assets"]:
		var terrain := String(asset["terrain"])
		var variant := int(visits.get(terrain,0))
		visits[terrain] = variant+1
		viewer._clear()
		viewer._replay = BattleReplay.from_result(result)
		viewer._bg.setup(terrain,[],[],variant)
		viewer._title.text = asset["name"] + " / " + terrain
		viewer._round_label.text = "Ten stacks per side / native-scale review"
		viewer._layout()
		viewer.show()
		if viewer._bg.selected_background != asset["id"]:
			push_error("Battlefield variant did not select the requested artwork")
			quit(1)
			return
		await _shot(String(asset["id"])+"-live")
		viewer.hide()
		var compact := BattleVignette.new()
		compact.size = Vector2(1200,160)
		compact.position = Vector2(40,320)
		root.add_child(compact)
		compact.setup(terrain,[{"creature":"pike_militia"},{"creature":"lancer"},{"creature":"lightbearer"}],
			[{"creature":"shambler"},{"creature":"marrow_archer"},{"creature":"gibbet_knight"}],variant)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image().get_region(Rect2i(40,320,1200,160))
		image.save_png(OUT+String(asset["id"])+"-forecast.png")
		compact.queue_free()
		await process_frame
	# Full playback on a ford keeps grass combat rules and river scenery.
	var small_left := _side(["pike_militia","longbowman"],"Aldmere Concord")
	var small_right := _side(["shambler","marrow_archer"],"Hollow Dominion")
	var fight := CombatSimulator.new(data).simulate(CombatSimulator.make_setup(small_left,small_right,"grass",17),true)
	fight["visual_terrain"] = "river"
	fight["visual_seed"] = 19
	viewer.play(fight)
	viewer._set_speed(4.0,false)
	var selected := viewer._bg.selected_background
	var verified := false
	for frame in 1800:
		await process_frame
		if not viewer.is_playing():
			break
		if viewer._bg.selected_background != selected or selected != "river_stoneford":
			push_error("Scenery changed during recorded playback")
			quit(1)
			return
		if viewer._verdict.text != "" and not verified:
			var expected := BattleReplay.from_result(fight).final_counts()
			for key in expected:
				if viewer._figs[key].count != int(expected[key]):
					push_error("Battlefield artwork changed final survivors")
					quit(1)
					return
			verified = true
			await _shot("river-playback-result")
	if not verified:
		push_error("Recorded battle did not finish")
		quit(1)
		return
	print("BATTLEFIELD_REVIEW_OK: 17 scenes, forecast crops and unchanged river battle result")
	viewer.queue_free()
	await process_frame
	quit(0)
