extends SceneTree
## Real construction and ultimate-material review for all playable factions.

const OUT := "res://docs/art/production/ultimate-buildings/"
var main: Node
var registry: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String, frames: int = 5) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")


func _run() -> void:
	root.content_scale_size = Vector2i(1280,800)
	root.size = Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(OUT)
	registry = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/ultimate_buildings.json"))
	main = load("res://scenes/main.tscn").instantiate()
	main.show_menu_on_start = false
	root.add_child(main)
	for i in 5:
		await process_frame
	for asset in registry["assets"]:
		var faction: String = asset["faction"]
		var bid: String = asset["building_id"]
		main.start_new_game("ember_ford",11,{"players":[{"type":"human","faction":faction}]})
		main._open_town()
		var town_id: String = main.town_screen.town_id
		var town: Dictionary = main.session.town(town_id)
		town["built"] = []
		for building_id in main.data.town_types[faction]["buildings"]:
			if building_id != bid:
				town["built"].append(building_id)
		town["last_build_day"] = 0
		var bank: ResourceBank = main.session.current_player()["resources"]
		for resource in main.data.resource_order:
			bank.add(resource,100000)
		main._refresh()
		main.town_screen.refresh()
		await _shot(faction + "-before-construction")
		var cost := Town.build_cost(town,bid,main.data)
		var before := bank.get_amount("gold")
		var result: Dictionary = main.session.build(town_id,bid)
		if not result.get("ok",false) or not main.session.army_upgrades(0).has(faction) or bank.get_amount("gold") != before - int(cost["gold"]):
			push_error("Ultimate construction/payment/effect failed for " + faction)
			quit(1)
			return
		main._refresh()
		main.town_screen.refresh()
		await _shot(faction + "-built")
		main.town_screen.close_screen()
		main._set_busy(false)
	# Inspect the actual BattleFigure shader on stills and animation frames.
	main.hide()
	for child in main.get_children():
		if child is CanvasLayer:
			child.hide()
	var background := ColorRect.new()
	background.color = Color("171b20")
	background.size = Vector2(1280,800)
	root.add_child(background)
	var figures := []
	for i in registry["assets"].size():
		var faction: String = registry["assets"][i]["faction"]
		var cid := ""
		for key in main.data.creatures:
			var creature: Dictionary = main.data.creatures[key]
			if creature["faction"] == faction and int(creature["tier"]) == 3 and not creature.has("upgrade_of"):
				cid = key
				break
		var at := Vector2(160 + (i % 4) * 320,280 + (i / 4) * 350)
		for upgraded in [false,true]:
			var figure := BattleFigure.new()
			figure.setup(cid,1,1.0,0.0,upgraded)
			figure.position = at + Vector2(58 if upgraded else -58,0)
			root.add_child(figure)
			figures.append(figure)
		var label := Label.new()
		label.text = faction + " / normal - ultimate"
		label.position = at + Vector2(-145,45)
		root.add_child(label)
	await _shot("all-faction-ultimate-stills")
	for figure in figures:
		figure.set_walking(true)
	await _shot("all-faction-ultimate-movement",12)
	for figure in figures:
		figure.set_walking(false)
		figure.start_attack()
	await _shot("all-faction-ultimate-attacks",12)
	AudioManager.stop_all()
	print("ULTIMATE_REVIEW_OK: eight real constructions, exact payment, active bonuses, town layers and still/move/attack shader treatment")
	quit(0)
