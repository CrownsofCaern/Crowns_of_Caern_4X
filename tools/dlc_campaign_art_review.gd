extends SceneTree
## Render only the two new journeys, without writing saves or replacing old captures.
const OUT := "res://docs/art/production/dlc-campaign-art/"

func _initialize() -> void:
	_run.call_deferred()

func _capture(filename: String) -> void:
	print("CAPTURE ", filename)
	root.grab_focus()
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + filename + ".png")

func _run() -> void:
	root.content_scale_size = Vector2i(1536, 1024)
	root.size = Vector2i(1536, 1024)
	DirAccess.make_dir_recursive_absolute(OUT)
	var data := GameData.get_default()
	var menu := MainMenu.new()
	root.add_child(menu)
	menu.build(data)
	menu.open(false)
	for cid in ["six_eyes", "drowned_oath"]:
		var progress := Campaign.start(data, cid, 79)
		progress.chapter = 4
		for i in 4:
			progress.completed.append(String(data.campaigns[cid]["chapters"][i]["id"]))
		menu.show_campaign_journey(cid, progress)
		menu._campaign_panel.journey.elapsed = 3
		await _capture(cid + "-journey")
		menu._campaign_panel.journey.select_stop(9)
		await _capture(cid + "-finale-preview")
	root.content_scale_size = Vector2i(430, 932)
	root.size = Vector2i(430, 932)
	menu.show_campaign_journey("six_eyes", Campaign.start(data, "six_eyes", 79))
	await _capture("six_eyes-phone")
	menu.free()
	AudioManager.stop_all()
	print("DLC_CAMPAIGN_ART_REVIEW_OK")
	quit()
