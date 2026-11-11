extends SceneTree
## Production MainMenu captures with in-memory progress fixtures; never writes player saves.
const OUT := "res://docs/art/production/campaign-journeys/"
var data: GameData
var menu: MainMenu


func _initialize() -> void:
	_run.call_deferred()


func _capture(filename: String) -> void:
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + filename + ".png")


func _progress(id: String, chapter: int) -> Campaign:
	var campaign := Campaign.start(data, id, 79)
	campaign.chapter = chapter
	for i in chapter:
		campaign.completed.append(String(data.campaigns[id]["chapters"][i]["id"]))
	return campaign


func _run() -> void:
	root.content_scale_size = Vector2i(1536, 1024)
	root.size = Vector2i(1536, 1024)
	DirAccess.make_dir_recursive_absolute(OUT)
	data = GameData.get_default()
	menu = MainMenu.new()
	root.add_child(menu)
	menu.build(data)
	menu.open(false)
	for cid in data.campaigns:
		menu.show_campaign_journey(cid, _progress(cid, 3))
		menu._campaign_panel.journey.elapsed = 3
		await _capture(cid)
	menu.show_campaign_journey("last_light", _progress("last_light", 7))
	menu._campaign_panel.journey.elapsed = .9
	await _capture("hero-travelling")
	menu.show_campaign_journey("last_light", _progress("last_light", 3))
	menu._campaign_panel.journey.select_stop(8)
	await _capture("locked-preview")
	menu.show_campaign_journey("briar_oath", _progress("briar_oath", 10))
	await _capture("campaign-complete")
	root.content_scale_size = Vector2i(768, 1024)
	root.size = Vector2i(768, 1024)
	menu.show_campaign_journey("pale_inheritance", _progress("pale_inheritance", 6))
	await _capture("portrait")
	menu._campaign_panel.journey.zoom_at(2, menu._campaign_panel.journey.size * .5)
	await _capture("portrait-zoom")
	root.content_scale_size = Vector2i(430, 932)
	root.size = Vector2i(430, 932)
	menu.show_campaign_journey("last_light", _progress("last_light", 3))
	await _capture("phone")
	menu._campaign_panel.journey.zoom_at(2.4, menu._campaign_panel.journey.stop_position(3))
	await _capture("phone-zoom")
	menu.free()
	print("CAMPAIGN_JOURNEYS_REVIEW_OK: six real menu paintings, travel, locked preview, completion, portrait and zoom; no player saves written")
	quit(0)
