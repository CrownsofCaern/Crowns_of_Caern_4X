extends "res://tests/test_case.gd"


func test_expansion_journeys_have_ten_stops_and_keep_opening_art() -> void:
	var screen := CampaignJourneyScreen.new()
	screen.build(data)
	for cid in ["six_eyes", "drowned_oath"]:
		screen.show_campaign(cid)
		assert_eq(screen.journey.nodes.size(), 10, cid)
		assert_true(screen.journey.painting != null, cid)
		assert_false(screen.go.disabled)
		for chapter in data.campaigns[cid]["chapters"]:
			assert_true(CampaignArt.texture(cid, String(chapter["id"])) != null, chapter["id"])
		screen.journey.select_stop(9)
		assert_true(screen.go.disabled, "finale previews without unlocking it")
	screen.free()


func test_all_destinations_match_real_chapters_and_shared_world_places() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/campaign_journeys.json"))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/world_atlas.json"))
	assert_true(catalog["campaigns"].size() <= data.campaigns.size())
	for cid in catalog["campaigns"]:
		var record: Dictionary = catalog["campaigns"][cid]
		var chapters: Array = data.campaigns[cid]["chapters"]
		assert_eq(record["nodes"].size(), chapters.size(), cid)
		for i in chapters.size():
			var node: Dictionary = record["nodes"][i]
			assert_eq(node["chapter"], chapters[i]["id"])
			assert_eq(node["location"], world["chapter_locations"][cid][node["chapter"]])
			assert_eq(node["layer"], world["landmarks"][node["location"]]["layer"])
			assert_between(node["at"][0], .04, .96)
			assert_between(node["at"][1], .04, .96)
		assert_true(CampaignArt.texture(cid, "", "journey") != null, cid)


func test_locked_and_won_nodes_preview_without_advancing_or_emitting_play() -> void:
	var screen := CampaignJourneyScreen.new()
	screen.build(data)
	var campaign := Campaign.start(data, "last_light", 91)
	campaign.chapter = 3
	for i in 3:
		campaign.completed.append(String(data.campaigns["last_light"]["chapters"][i]["id"]))
	var before := campaign.to_dict().duplicate(true)
	var emissions := []
	screen.campaign_requested.connect(func(id, fresh): emissions.append([id, fresh]))
	screen.show_campaign("last_light", campaign)
	assert_eq(screen.journey.selected, 3)
	assert_false(screen.go.disabled)
	screen.journey.select_stop(8)
	assert_true(screen.go.disabled)
	screen._launch_selected()
	assert_true(emissions.is_empty(), "locked stops never launch")
	screen.journey.select_stop(0)
	screen._launch_selected()
	assert_true(emissions.is_empty(), "won stops do not rewind veteran progress")
	screen.journey.select_stop(3)
	screen._launch_selected()
	assert_eq(emissions, [["last_light", false]])
	assert_eq(campaign.to_dict(), before, "preview and travel animation do not mutate saves")
	screen.free()


func test_finished_campaign_stays_finished_and_stops_fit_letterboxed_image() -> void:
	var screen := CampaignJourneyScreen.new()
	screen.build(data)
	var campaign := Campaign.start(data, "briar_oath", 19)
	campaign.chapter = data.campaigns["briar_oath"]["chapters"].size()
	screen.show_campaign("briar_oath", campaign)
	assert_true(screen.go.disabled)
	assert_eq(screen.go.text, "Campaign complete")
	var map := screen.journey
	map.size = Vector2(800, 800)
	for i in map.nodes.size():
		assert_true(map.image_rect().has_point(map.stop_position(i)))
	assert_eq(map.current, 9)
	screen.free()


func test_resume_and_fresh_signals_keep_existing_campaign_contract() -> void:
	var screen := CampaignJourneyScreen.new()
	screen.build(data)
	var campaign := Campaign.start(data, "last_light", 22)
	campaign.active_game = {"day": 3} # Presentation only: no save or game is loaded.
	screen.show_campaign("last_light", campaign)
	assert_eq(screen.go.text, "Continue chapter 1")
	var emissions := []
	screen.campaign_requested.connect(func(id, fresh): emissions.append([id, fresh]))
	screen._launch_selected()
	assert_eq(emissions, [["last_light", false]])
	screen.had_save = false
	screen._launch_selected()
	assert_eq(emissions[-1], ["last_light", true])
	screen.confirm_restart.canceled.emit()
	assert_eq(emissions.size(), 2, "cancelled restart leaves progress alone")
	screen.confirm_restart.confirmed.emit()
	assert_eq(emissions[-1], ["last_light", true])
	screen.free()


func test_zoom_keeps_map_coordinates_and_touch_pan_bounded() -> void:
	var map := CampaignJourneyMap.new()
	map.size = Vector2(800, 600)
	map.configure(null, [{"at":[.5,.5], "layer":"surface"}], [{"name":"test", "state":"current"}], 0, "hero_knight", Color.GOLD)
	var pivot := map.stop_position(0)
	map.zoom_at(2, pivot)
	assert_eq(map.zoom, 2.0)
	assert_true(map.stop_position(0).distance_to(pivot) < .01)
	map.pan = Vector2(99999, -99999)
	map._clamp_pan()
	var rect := map.image_rect()
	assert_true(rect.position.x <= 0 and rect.end.x >= map.size.x)
	map.zoom_at(.1, map.size * .5)
	assert_eq(map.zoom, 1.0)
	assert_eq(map.pan, Vector2.ZERO)
	map.free()


class MenuProbe:
	extends MainMenu
	var opened_campaign := ""
	var viewed_progress: Campaign
	func show_campaign_journey(id: String, campaign: Campaign = null) -> void:
		opened_campaign = id
		viewed_progress = campaign


class FlowProbe:
	extends "res://src/ui/adventure_screen.gd"
	var opened_menu := false
	var retried := false
	func _open_menu() -> void:
		opened_menu = true
	func _play_campaign_chapter() -> void:
		retried = true


func test_victory_goes_through_journey_while_defeat_keeps_retry() -> void:
	var flow := FlowProbe.new()
	var probe := MenuProbe.new()
	flow.menu = probe
	flow.session = GameSession.new_game(data, "ember_ford", 6)
	flow.campaign = Campaign.start(data, "last_light", 6)
	flow.campaign.chapter = 1
	flow.session.state.game_over = true
	flow.session.state.winner = 0
	flow._campaign_journey_or_retry()
	assert_true(flow.opened_menu)
	assert_false(flow.retried)
	assert_eq(probe.opened_campaign, "last_light")
	assert_true(probe.viewed_progress == flow.campaign)
	flow.opened_menu = false
	flow.session.state.winner = -1
	flow._campaign_journey_or_retry()
	assert_true(flow.retried)
	assert_false(flow.opened_menu, "defeat retries without travelling to another chapter")
	probe.free()
	flow.free()


func test_scenario_campaign_without_painting_has_all_chapter_stops() -> void:
	var screen := CampaignJourneyScreen.new()
	screen.build(data)
	screen.show_campaign("long_watch")
	assert_eq(screen.journey.nodes.size(), 3)
	assert_false(screen.go.disabled)
	screen.journey.select_stop(2)
	assert_true(screen.go.disabled)
	assert_true(screen.title.text.contains("Heart"))
	screen.free()
