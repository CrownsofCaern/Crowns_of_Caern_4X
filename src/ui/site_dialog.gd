class_name SiteDialog
extends ModalPanel
## A rare map building the hero stands on: its story, what it does, what this
## visit gave, dwelling and village recruitment, or an illustrated trader shop. Reads
## GameSession queries and acts through site_recruit() / trader_buy().

signal closed
signal rob_requested(site_id: String)

var session: GameSession
var _site_id := ""
var _hero_id := ""
var _lines: Array = []


## lines: what the visit just gave (from move_hero's "visited"), shown once.
func open(s: GameSession, site_id: String, hero_id: String, lines: Array = []) -> void:
	session = s
	_site_id = site_id
	_hero_id = hero_id
	_lines = lines
	_render()
	show()
	UiStyle.fade_in(self)


func _render() -> void:
	_clear()
	var info := session.site_info(_site_id, _hero_id)
	if info.is_empty():
		hide()
		return
	if info["kind"] == "cobolt":
		_render_cobolt(info)
		return
	if info["kind"] == "trader":
		_render_shop()
		return
	_body.add_child(UiStyle.titled(Art.sprite(String(info["sprite"])), info["name"], info["summary"]))
	_body.add_child(_wrapped(info["text"], 15))
	if not _lines.is_empty():
		_body.add_child(HSeparator.new())
		for line in _lines:
			_body.add_child(UiStyle.label("  " + String(line), 14, UiStyle.GOOD))
	elif info["block"] != "":
		_body.add_child(UiStyle.label(String(info["block"]).capitalize() + ".", 13, UiStyle.TEXT_DIM))
	if MapSites.RECRUIT_KINDS.has(String(info["kind"])):
		for offer in info.get("offers", []):
			_body.add_child(HSeparator.new())
			_body.add_child(_recruit_row(offer))
	_buttons([["Close", _close]])


## One recruitable creature (a site_info offer).
func _recruit_row(info: Dictionary) -> Control:
	var data := session.data
	var cid := String(info["creature"])
	var c := data.creature(cid)
	var bank: ResourceBank = session.current_player()["resources"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var slot := ArmySlot.new().setup(0, cid, int(info["available"]), UiStyle.creature_tooltip(data, cid))
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(slot)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	col.add_child(UiStyle.label("%s  (tier %d, %s)" % [c["name"], int(c["tier"]),
		data.factions.get(c["faction"], {}).get("name", c["faction"])], 15))
	col.add_child(UiStyle.label("%d available" % int(info["available"]), 12, UiStyle.TEXT_DIM))
	var cost := HBoxContainer.new()
	cost.add_child(UiStyle.label("Each:", 12, UiStyle.TEXT_DIM))
	cost.add_child(UiStyle.cost_row(info["cost"], data, bank, 12))
	col.add_child(cost)
	if not bool(info["can_recruit"]):
		col.add_child(UiStyle.label(String(info["reason"]).capitalize(), 12, UiStyle.BAD))
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = maxi(0, int(info["max"]))
	spin.value = int(info["max"])
	spin.custom_minimum_size.x = 84
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.editable = bool(info["can_recruit"])
	row.add_child(spin)
	var rb := Button.new()
	rb.text = "Recruit"
	rb.disabled = not bool(info["can_recruit"])
	rb.custom_minimum_size = Vector2(84, 32)
	rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rb.pressed.connect(func():
		var r := session.site_recruit(_site_id, _hero_id, int(spin.value), cid)
		if r["ok"]:
			AudioManager.play("recruit")
			_lines = []
		_render())
	row.add_child(rb)
	return row


## A compact illustrated storefront, using the same modal and controls as
## other map visits. The stock list scrolls on smaller game windows.
func _render_shop() -> void:
	var art := TextureRect.new()
	var source := Art.texture_at("res://assets/illustrations/trader_shop.png")
	if source != null:
		var banner := AtlasTexture.new()
		banner.atlas = source
		banner.region = Rect2(0, source.get_height() * 0.12, source.get_width(), source.get_width() * 130.0 / 600.0)
		art.texture = banner
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.custom_minimum_size = Vector2(0, 130)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_body.add_child(art)
	var heading := HBoxContainer.new()
	var title := UiStyle.label("THE ROAD TRADER", 22, UiStyle.BRASS)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var bank: ResourceBank = session.current_player()["resources"]
	heading.add_child(UiStyle.label("%d gold" % bank.get_amount("gold"), 16, UiStyle.BRASS))
	_body.add_child(heading)
	_body.add_child(_wrapped("Relics for the road. Secrets beyond the shroud.", 14, UiStyle.TEXT_DIM))
	_body.add_child(_wrapped("Limited stock · shared by all visitors · no restocking", 12, UiStyle.TEXT_DIM))
	_body.add_child(HSeparator.new())
	var stock := session.trader_info(_site_id, _hero_id)
	for offer in stock:
		if offer["kind"] == "map":
			_body.add_child(_shop_offer(offer))
	_body.add_child(UiStyle.label("ARTIFACTS", 12, UiStyle.BRASS))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 220
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var offers := VBoxContainer.new()
	offers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers.add_theme_constant_override("separation", 8)
	scroll.add_child(offers)
	for offer in stock:
		if offer["kind"] == "artifact":
			offers.add_child(_shop_offer(offer))
	if not _lines.is_empty():
		_body.add_child(_wrapped(String(_lines[0]), 13, UiStyle.GOOD))
	_buttons([["Leave trader", _close]])


func _shop_offer(offer: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(Color("#18130f"), UiStyle.BRASS.darkened(0.45), 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	if offer["kind"] == "artifact":
		var aid := String(offer["artifact"])
		row.add_child(ArtifactSlot.new().setup(String(session.data.artifacts[aid]["slot"]), aid, session.data))
	else:
		var icon := TextureRect.new()
		icon.texture = Art.sprite("trader_chart")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(52, 52)
		row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var color := UiStyle.TEXT
	if offer["kind"] == "artifact":
		color = ArtifactSlot.RARITY_COLORS.get(session.data.artifacts[offer["artifact"]]["rarity"], UiStyle.TEXT)
	col.add_child(UiStyle.label(String(offer["name"]), 15, color))
	var desc := UiStyle.label(String(offer["text"]), 12, UiStyle.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	col.add_child(UiStyle.label("%d gold · %d left" % [int(offer["price"]), int(offer["remaining"])], 12, UiStyle.BRASS))
	var reason := String(offer["reason"])
	if reason != "":
		col.add_child(UiStyle.label(reason.capitalize(), 11, UiStyle.TEXT_DIM))
	var buy := Button.new()
	buy.text = "Sold out" if int(offer["remaining"]) == 0 else "Buy"
	buy.custom_minimum_size = Vector2(90, 36)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = reason != ""
	buy.tooltip_text = reason
	buy.pressed.connect(func():
		var result := session.trader_buy(_site_id, _hero_id, int(offer["index"]))
		if result["ok"]:
			AudioManager.play("recruit")
			_lines = ["Purchased %s.%s" % [result["name"], " Uncovered %d tiles." % int(result["revealed"]) if int(result["revealed"]) > 0 else ""]]
		else:
			_lines = [String(result["reason"]).capitalize()]
		_render())
	row.add_child(buy)
	return panel


func _close() -> void:
	hide()
	closed.emit()


func _render_cobolt(info: Dictionary) -> void:
	_body.add_child(UiStyle.titled(Art.sprite(String(info["sprite"])), info["name"], "Neutral trading house", 22, Vector2(160, 144)))
	_body.add_child(_wrapped(info["text"], 14))
	var access := session.cobolt_access_error(_site_id, _hero_id)
	if access != "":
		_body.add_child(_wrapped(access, 14, UiStyle.WARN))
	else:
		_body.add_child(_wrapped("One recruit type · one artefact · one fixed resource trade. Recruits and exchanges restock weekly up to their cap; artefacts do not.", 13, UiStyle.TEXT_DIM))
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.y = 250
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_body.add_child(scroll)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(col)
		for offer in session.cobolt_offers(_site_id, _hero_id):
			col.add_child(_cobolt_offer(offer))
	if not session.state.map.objects[_site_id].get("plundered", false):
		var intel := session.intel(_hero_id, _site_id)
		for line in intel.get("report", []):
			_body.add_child(_wrapped(String(line), 13, UiStyle.TEXT_DIM))
		var why := session.can_scout(_hero_id, _site_id)
		var rob_why := session.cobolt_rob_error(_site_id, _hero_id)
		_buttons([["Leave", _close],
			["Scout (%d movement)" % session.scout_cost(_hero_id), func():
				session.scout(_hero_id, _site_id)
				_render(), why, why != ""],
			["Rob…", func(): rob_requested.emit(_site_id), rob_why, rob_why != ""]])
	else:
		var obj: Dictionary = session.state.map.objects[_site_id]
		if obj.has("unclaimed_artifact") and int(obj.get("loot_owner", -1)) == session.state.current_player:
			_body.add_child(_wrapped("An artefact from your victory remains here. Free pack space to recover it.", 14, UiStyle.BRASS))
			_buttons([["Leave", _close], ["Recover loot", func():
				session.cobolt_claim_loot(_site_id, _hero_id)
				_render()]])
		else:
			_buttons([["Leave", _close]])


func _cobolt_offer(offer: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if offer["kind"] == "recruit":
		var slot := ArmySlot.new().setup(0, String(offer["creature"]), int(offer["remaining"]), UiStyle.creature_tooltip(session.data, String(offer["creature"])))
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(slot)
	elif offer["kind"] == "artifact":
		row.add_child(ArtifactSlot.new().setup(String(session.data.artifacts[offer["artifact"]]["slot"]), String(offer["artifact"]), session.data))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var data := session.data
	var kind := String(offer["kind"])
	var title := ""
	var desc := ""
	match kind:
		"recruit":
			var cid := String(offer["creature"])
			var creature := data.creature(cid)
			title = "%s · Tier %d" % [creature["name"], creature["tier"]]
			desc = "Each: %d gold" % int(creature["cost"]["gold"])
			col.tooltip_text = UiStyle.creature_tooltip(data, cid)
		"artifact":
			title = String(data.artifacts[offer["artifact"]]["name"])
			desc = "%d gold · %s" % [offer["price"], data.artifacts[offer["artifact"]]["text"]]
		"exchange":
			title = "%d %s → %d %s" % [offer["input"], data.resources[offer["sell"]]["name"], offer["output"], data.resources[offer["buy"]]["name"]]
			desc = "40%% cheaper than one-market trade. Standard input: %d." % offer["baseline"]
	col.add_child(UiStyle.label(title, 15, UiStyle.BRASS))
	var label := UiStyle.label(desc, 12, UiStyle.TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 220
	col.add_child(label)
	col.add_child(UiStyle.label("%d remaining" % int(offer["remaining"]), 12, UiStyle.TEXT_DIM))
	var why := String(offer["reason"])
	if why != "":
		col.add_child(UiStyle.label(why, 12, UiStyle.WARN))
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = maxi(1, int(offer["remaining"]))
	spin.value = 1
	spin.custom_minimum_size.x = 65
	spin.visible = kind != "artifact"
	row.add_child(spin)
	var button := Button.new()
	button.text = "Hire" if kind == "recruit" else ("Trade" if kind == "exchange" else "Buy")
	button.disabled = why != ""
	button.tooltip_text = why
	button.pressed.connect(func():
		var r := session.cobolt_buy(_site_id, _hero_id, int(offer["index"]), int(spin.value))
		if r["ok"]:
			AudioManager.play("trade")
		else:
			session.message.emit(String(r["reason"]))
		_render())
	row.add_child(button)
	return row
