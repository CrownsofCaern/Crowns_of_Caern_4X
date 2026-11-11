extends SceneTree
## Real map/HUD and town-cost review. All review-map edits are temporary.

const OUT := "res://docs/art/production/resource-pickups/"
var main: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")


func _run() -> void:
	for i in 5:
		await process_frame
	main.start_new_game("ember_ford", 11, {"players":[{"type":"human","faction":"concord"}]})
	var map: AdventureMap = main.session.state.map
	for y in range(6, 11):
		for x in range(3, 20):
			var p := Vector2i(x, y)
			var existing := map.object_at(p)
			if not existing.is_empty() and existing.get("type") in ["resource", "chest", "neutral_army", "encounter", "site"]:
				map.remove_object(existing["id"])
			map.terrain[map.index(p)] = "grass"
	for i in main.data.resource_order.size():
		var rid: String = main.data.resource_order[i]
		map.add_object({"id":"art_review_"+rid,"type":"resource","resource":rid,"amount":5,"pos":[4+i*2,8]})
	map.add_object({"id":"art_review_chest","type":"chest","pos":[18,8],"gold":500})
	main.session.current_player()["fog"].reveal(Vector2i(12,8),80)
	main.map_view.bind(main.session)
	main._look_at = main.map_view.center_px(Vector2i(12,8))
	main._refresh()
	await _shot("map-and-resource-hud-godot")
	main.set_zoom_level(0)
	await _shot("map-zoomed-out-godot")
	main.set_zoom_level(1)
	main._open_town("town_greyhold")
	await _shot("town-and-resource-costs-godot")
	main.town_screen._inspect_building("c_up8")
	await _shot("building-resource-costs-godot")
	AudioManager.stop_all()
	print("RESOURCE_VISUAL_REVIEW_OK: seven pickups, seven HUD icons, chest and town costs")
	quit(0)
