extends "res://tests/test_case.gd"


func test_menu_sources_and_brand_are_available() -> void:
	assert_eq(MenuArt.TITLE, "Crowns of Caern")
	assert_eq(ProjectSettings.get_setting("application/config/name"), MenuArt.TITLE, "project name matches the brand (old saves migrate, see LegacyUserData)")
	for id in ["title", "campaign", "setup", "archive", "emblem", "wordmark"]:
		assert_true(MenuArt.texture(id) != null, id)
	var logo := MenuArt.texture("wordmark")
	if logo != null:
		assert_true(logo.get_width() > logo.get_height() * 2, "wordmark preserves its wide aspect")


func test_menu_navigation_changes_art_and_compacts_header() -> void:
	var menu := MainMenu.new()
	menu.build(data)
	menu.open(false)
	assert_eq(menu._art_background.texture, MenuArt.texture("title"))
	assert_eq(menu._wordmark.custom_minimum_size, Vector2(780, 260))
	menu._show_setup()
	assert_eq(menu._art_background.texture, MenuArt.texture("setup"))
	assert_eq(menu._wordmark.custom_minimum_size, Vector2(420, 92))
	menu.show_campaigns()
	assert_eq(menu._art_background.texture, MenuArt.texture("campaign"))
	menu.open(false)
	assert_eq(menu._wordmark.custom_minimum_size, Vector2(780, 260))
	assert_eq(menu._art_background.texture, MenuArt.texture("title"))
	menu.free()


func test_setup_class_picker_tracks_faction() -> void:
	var menu := MainMenu.new()
	menu.build(data)
	menu._show_setup()
	var row: Dictionary = menu._slot_rows[0]
	var factions := GameSetup.playable_factions(data)
	var index := factions.find("concord")
	row["faction"].select(index)
	row["faction"].item_selected.emit(index)
	var picker: OptionButton = row["hero_class"]
	assert_eq(picker.item_count, 4)
	for i in range(1, picker.item_count):
		assert_eq(String(data.hero_classes[picker.get_item_metadata(i)]["faction"]), "concord")
	picker.select(1)
	assert_eq(String(menu.current_setup()["players"][0]["hero_class"]), String(picker.get_selected_metadata()))
	index = factions.find("ashen")
	row["faction"].select(index)
	row["faction"].item_selected.emit(index)
	assert_eq(String(picker.get_selected_metadata()), "")
	for i in range(1, picker.item_count):
		assert_eq(String(data.hero_classes[picker.get_item_metadata(i)]["faction"]), "ashen")
	menu.free()


func test_detailed_faction_emblems_are_available() -> void:
	for faction in GameSetup.playable_factions(data):
		var emblem := Art.faction_emblem(faction)
		assert_true(emblem != null, faction)
		if emblem != null:
			assert_true(emblem.get_width() >= 440, "retains source detail")
		var icon := Art.faction_emblem_icon(faction)
		assert_true(icon != null, faction)
		if icon != null:
			assert_eq(icon.get_size(), Vector2(28, 28))
	assert_true(Art.faction_emblem("wilds") == null)
