class_name UiStyle
extends RefCounted
## Shared faction material theme. Semantic warning/success colours stay stable.

const PANEL_BG := Color("#1d1813")
const PANEL_BG_LIGHT := Color("#2a221a")
const BRASS := Color("#c9a24a")
const TEXT := Color("#eadfc4")
const TEXT_DIM := Color("#a89a7c")
const GOOD := Color("#7fc06a")
const BAD := Color("#d96a52")
const WARN := Color("#e0b450")

static var faction := "concord"
static var _palettes: Dictionary = {}
static var _shared_theme: Theme


static func palette(id: String = "") -> Dictionary:
	if _palettes.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/specs/faction_ui.json"))
		if parsed is Dictionary:
			_palettes = parsed
	return _palettes.get(id if id != "" else faction, _palettes.get("concord", {}))


static func accent() -> Color:
	return Color(palette().get("accent", "#c9a24a"))


static func material_color(base: Color) -> Color:
	var p := palette()
	var backgrounds := {
		"0b0a09": "background", "120f0b": "background", "17120e": "panel",
		"15110d": "panel", "1d1813": "panel", "2a221a": "raised",
		"3a2e20": "raised", "4d3c27": "raised", "2a2117": "panel", "2a2520": "panel"}
	var key := base.to_html(false)
	if backgrounds.has(key):
		var mapped := Color(p.get(backgrounds[key], "#1d1813"))
		mapped.a = base.a
		return mapped
	for amount in [0.0, 0.2, 0.3, 0.35, 0.55, 0.6]:
		if base.is_equal_approx(BRASS.darkened(amount)):
			return accent().darkened(amount)
	if base.is_equal_approx(BRASS.lightened(0.2)):
		return accent().lightened(0.2)
	return base


static func apply_faction(root: Node, id: String) -> void:
	palette()
	var next := id if _palettes.has(id) else "concord"
	if next == faction:
		return
	faction = next
	if _shared_theme != null:
		_shared_theme.clear()
		_shared_theme.merge_with(_build_theme())
	_restyle(root)
	RenderingServer.set_default_clear_color(Color(palette()["background"]))


static func _restyle(node: Node) -> void:
	if node is Control:
		var control := node as Control
		if control is BaseButton:
			control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if control.has_method("_refresh_faction_style"):
			control.call("_refresh_faction_style")
		if control.has_meta("ui_base_color"):
			control.add_theme_color_override("font_color", material_color(control.get_meta("ui_base_color")))
		for property in control.get_property_list():
			var name := String(property["name"])
			if not name.begins_with("theme_override_styles/"):
				continue
			var style: Variant = control.get(name)
			if style is StyleBoxFlat and style.has_meta("ui_base_bg"):
				style.bg_color = material_color(style.get_meta("ui_base_bg"))
				style.border_color = material_color(style.get_meta("ui_base_border"))
		if control is ColorRect:
			if not control.has_meta("ui_rect_color"):
				control.set_meta("ui_rect_color", control.color)
			control.color = material_color(control.get_meta("ui_rect_color"))
		if control.has_meta("ui_faction_glow"):
			control.self_modulate = accent()
		control.queue_redraw()
	for child in node.get_children():
		_restyle(child)


static func panel_box(bg: Color = PANEL_BG, border: Color = BRASS, width: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_meta("ui_base_bg", bg)
	sb.set_meta("ui_base_border", border)
	sb.bg_color = material_color(bg)
	sb.border_color = material_color(border)
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	return sb


## The framed panel from the art set (wood, iron band, brass trim), or the
## flat placeholder when the art is not built.
static func frame_panel(content_margin: float = 14.0) -> StyleBox:
	var sb := Art.stylebox("ui_panel_" + faction, content_margin)
	if sb != null:
		# Painted material is not a repeating tile. Stretch the quiet centre;
		# nine-slicing preserves the original corner ornaments and edge widths.
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb if sb != null else panel_box()


static func make_theme() -> Theme:
	if _shared_theme == null:
		_shared_theme = _build_theme()
	return _shared_theme


static func _build_theme() -> Theme:
	var t := Theme.new()
	if TouchGestures.touch_ui():
		for control_type in ["TabContainer", "TabBar"]:
			t.set_font_size("font_size", control_type, TouchLayout.CONTROL_FONT)
			for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
				var tab := panel_box(PANEL_BG_LIGHT if state == "tab_selected" else PANEL_BG, BRASS.darkened(0.3), 1)
				# 18-unit text plus these margins: a tab of about MIN_TARGET (44 pt).
				tab.content_margin_top = 17
				tab.content_margin_bottom = 17
				tab.content_margin_left = 14
				tab.content_margin_right = 14
				t.set_stylebox(state, control_type, tab)
	t.set_stylebox("panel", "PanelContainer", frame_panel())
	t.set_stylebox("panel", "Panel", frame_panel())
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 15)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 14)
	var normal := panel_box(Color("#3a2e20"), BRASS.darkened(0.3), 1)
	normal.set_content_margin_all(6)
	normal.shadow_size = 0
	var hover := normal.duplicate()
	hover.bg_color = Color(palette()["raised"]).lightened(0.12)
	hover.border_color = accent()
	var pressed := normal.duplicate()
	pressed.bg_color = material_color(Color("#2a2117"))
	var disabled := normal.duplicate()
	disabled.bg_color = material_color(Color("#2a2520"))
	disabled.border_color = Color("#4a4030")
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	var focus := panel_box(Color(0, 0, 0, 0), BRASS, 2)
	focus.shadow_size = 0
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.3))
	t.set_font_size("font_size", "Button", TouchLayout.CONTROL_FONT if TouchGestures.touch_ui() else 15)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#120f0b")
	bar_bg.set_corner_radius_all(3)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = accent()
	bar_fill.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_font_size("font_size", "ProgressBar", 11)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_outline_color", "ProgressBar", Color("#080909"))
	t.set_constant("outline_size", "ProgressBar", 1)
	# Tooltips: the same wood and brass, readable parchment text.
	var tip := panel_box(Color("#17120e"), BRASS.darkened(0.2), 1)
	tip.set_content_margin_all(8)
	tip.shadow_size = 4
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16 if TouchGestures.touch_ui() else 13)
	for control_type in ["LineEdit", "SpinBox"]:
		if TouchGestures.touch_ui():
			t.set_font_size("font_size", control_type, TouchLayout.CONTROL_FONT)
		t.set_stylebox("normal", control_type, panel_box(PANEL_BG_LIGHT, BRASS.darkened(0.3), 1))
		t.set_stylebox("focus", control_type, focus)
		t.set_color("font_color", control_type, TEXT)
		t.set_color("selection_color", control_type, accent().darkened(0.55))
	t.set_stylebox("panel", "PopupMenu", frame_panel(8))
	t.set_color("font_color", "PopupMenu", TEXT)
	return t


## Qualitative army size, so the map shows a scouting estimate rather than exact counts.
## Scouting bands for creature counts: [upper bound (exclusive), phrase before a
## name, word on its own, range].
const COUNT_BANDS := [
	[5, "A few", "Few", "1-4"],
	[10, "Several", "Several", "5-9"],
	[20, "A pack of", "Pack", "10-19"],
	[50, "Many", "Many", "20-49"],
	[100, "A horde of", "Horde", "50-99"],
	[1 << 30, "A legion of", "Legion", "100+"],
]


static func _count_band(n: int) -> Array:
	for b in COUNT_BANDS:
		if n < int(b[0]):
			return b
	return COUNT_BANDS[-1]


## Scouted count as a phrase before a creature name: "A pack of Thornwolves".
static func count_word(n: int) -> String:
	return _count_band(n)[1]


## Scouted count on its own, for a portrait caption: "Pack".
static func count_caption(n: int) -> String:
	return _count_band(n)[2]


## The range a scouted count stands for: "10-19".
static func count_range(n: int) -> String:
	return _count_band(n)[3]


static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.set_meta("ui_base_color", color)
	l.add_theme_color_override("font_color", material_color(color))
	return l


## Apply larger touch targets to controls created by a screen, including controls
## with explicit desktop font overrides. Safe to call again after a refresh.
static func enlarge_touch_controls(node: Node) -> void:
	if not TouchGestures.touch_ui():
		return
	TouchLayout.prepare_scroll_input(node)
	if node is HSlider:
		(node as HSlider).custom_minimum_size.y = maxf((node as HSlider).custom_minimum_size.y, TouchLayout.MIN_TARGET)
	if node is VSlider:
		(node as VSlider).custom_minimum_size.x = maxf((node as VSlider).custom_minimum_size.x, TouchLayout.MIN_TARGET)
	if node is ArmySlot or node is ArtifactSlot:
		var slot := node as Control
		slot.custom_minimum_size = slot.custom_minimum_size.max(Vector2.ONE * TouchLayout.MIN_TARGET)
	if (node is BaseButton or node is LineEdit) and not node.has_meta("touch_enlarged"):
		var button := node as Control
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, TouchLayout.MIN_TARGET)
		button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, TouchLayout.MIN_TARGET)
		if button.has_theme_font_size_override("font_size"):
			button.add_theme_font_size_override("font_size", maxi(TouchLayout.CONTROL_FONT, button.get_theme_font_size("font_size")))
		button.set_meta("touch_enlarged", true)
	# Small print stays readable: nothing under MIN_FONT (about 10 pt).
	if node is Label and (node as Label).has_theme_font_size_override("font_size"):
		var l := node as Label
		if l.get_theme_font_size("font_size") < TouchLayout.MIN_FONT:
			l.add_theme_font_size_override("font_size", TouchLayout.MIN_FONT)
	if node is RichTextLabel and (node as RichTextLabel).has_theme_font_size_override("normal_font_size"):
		var r := node as RichTextLabel
		if r.get_theme_font_size("normal_font_size") < TouchLayout.MIN_FONT:
			r.add_theme_font_size_override("normal_font_size", TouchLayout.MIN_FONT)
	for child in node.get_children():
		enlarge_touch_controls(child)


## Texture shown at px_size: crisp pixels when enlarged, smoothed when a
## detailed icon is shown smaller than its art.
static func icon(tex: Texture2D, px_size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.texture_filter = smooth_filter(tex, px_size.x)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = px_size
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


## Creature portrait in a brass slot frame (2x pixels), with a count below.
static func creature_slot(tex: Texture2D, count_text: String, tooltip: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.tooltip_text = tooltip
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	var frame := PanelContainer.new()
	var sb: StyleBox = UiStyle.slot_box(2.0)
	if sb == null:
		sb = panel_box(Color("#120f0b"), BRASS.darkened(0.3), 1)
		sb.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	frame.tooltip_text = tooltip
	if tex != null:
		var r := icon(tex, Vector2(64, 64))
		r.tooltip_text = tooltip
		frame.add_child(r)
	else:
		frame.custom_minimum_size = Vector2(68, 68)
	v.add_child(frame)
	var l := label(count_text, 15, BRASS.lightened(0.2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


## Title row with a pixel-art picture on the left (encounters, towns).
static func titled(tex: Texture2D, title: String, subtitle: String = "", size: int = 22, icon_size: Vector2 = Vector2.ZERO) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if tex != null:
		var frame := PanelContainer.new()
		var sb: StyleBox = UiStyle.slot_box(4.0)
		if sb != null:
			frame.add_theme_stylebox_override("panel", sb)
		frame.add_child(icon(tex, icon_size if icon_size != Vector2.ZERO else tex.get_size() * 2.0))
		row.add_child(frame)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(label(title, size, BRASS))
	if subtitle != "":
		v.add_child(label(subtitle, 13, TEXT_DIM))
	row.add_child(v)
	return row


## Inner card frame (recessed slot look) for choices and skill cards.
static func card_box() -> StyleBox:
	return slot_box(10.0)


static func slot_box(margin: float = 2.0) -> StyleBox:
	var sb := panel_box(PANEL_BG_LIGHT, BRASS.darkened(0.3), 1)
	sb.set_content_margin_all(margin)
	sb.shadow_size = 0
	return sb


## Puts the UI icon ui_<icon_name> on a button, capped at px wide (the
## symbol art is 48 px, too big to show at full size on a button).
static func button_icon(b: Button, icon_name: String, px: int = 24) -> void:
	b.icon = Art.sprite("ui_icon_" + icon_name)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", px)
	if b.icon != null:
		b.texture_filter = smooth_filter(b.icon, px)


## Nearest for pixel art shown at its size or larger; linear when a detailed
## icon (the 48 px UI symbols) is shown smaller, so it does not break up.
static func smooth_filter(tex: Texture2D, px: float) -> CanvasItem.TextureFilter:
	if tex != null and tex.get_width() > px:
		return CanvasItem.TEXTURE_FILTER_LINEAR
	return CanvasItem.TEXTURE_FILTER_NEAREST


## A UI icon from the art set (ui_icon_<name>) drawn at px_size, or an
## empty spacer when the art is not built.
static func ui_icon(icon_name: String, px_size: float = 32.0) -> Control:
	var tex := Art.sprite("ui_icon_" + icon_name)
	if tex == null:
		var c := Control.new()
		c.custom_minimum_size = Vector2(px_size, px_size)
		return c
	return icon(tex, Vector2(px_size, px_size))


## Icon above a big number, as in the hero card (attack, defense, ...).
static func stat_chip(icon_name: String, value: int, tooltip: String, px: float = 32.0) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.tooltip_text = tooltip
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	var ic := ui_icon(icon_name, px)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.tooltip_text = tooltip
	v.add_child(ic)
	var l := label(str(value), 17, TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


## Resource costs as icon + amount pairs; amounts the bank cannot cover are red.
static func cost_row(cost: Dictionary, data: GameData, bank: ResourceBank = null, size: int = 13) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if cost.is_empty():
		row.add_child(label("free", size, TEXT_DIM))
		return row
	for res in data.resource_order:
		var n := int(cost.get(res, 0))
		if n <= 0:
			continue
		var name: String = data.resources[res]["name"]
		var tex := Art.resource_icon(res)
		if tex != null:
			var ic := icon(tex, Vector2(16, 16))
			ic.tooltip_text = name
			row.add_child(ic)
		var short := bank != null and bank.get_amount(res) < n
		var l := label(str(n) if tex != null else "%d %s" % [n, name], size, BAD if short else TEXT)
		l.tooltip_text = name
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(l)
		var gap := Control.new()
		gap.custom_minimum_size.x = 5
		row.add_child(gap)
	return row


## Multi-line tooltip for a creature: role, numbers and abilities.
static func creature_tooltip(data: GameData, creature_id: String, count: int = -1, veteran_level: int = 1) -> String:
	var xp: int = Army.VETERAN_THRESHOLDS[clampi(veteran_level, 1, 5) - 1]
	var c := Army.creature_stats({"creature": creature_id, "veteran_xp": xp}, data)
	if c.is_empty():
		return creature_id
	var head: String = c["name"] if count < 0 else "%d %s" % [count, c["name"]]
	var lines := [head,
		"Tier %d %s  ·  %s" % [int(c["tier"]), c["role"], data.factions.get(c["faction"], {}).get("name", c["faction"])],
		"Attack %d   Defense %d   Damage %d-%d" % [int(c["attack"]), int(c["defense"]), int(c["damage"][0]), int(c["damage"][1])],
		"Health %d   Speed %d   Initiative %d" % [int(c["hp"]), int(c["speed"]), int(c["initiative"])]]
	var abil := []
	for a in c.get("abilities", []):
		abil.append(String(a.get("id", "")).capitalize())
	if not abil.is_empty():
		lines.append("Abilities: " + ", ".join(abil))
	return "\n".join(lines)


## Brass section title with a thin rule under it.
static func section(text: String, size: int = 16) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(label(text, size, BRASS))
	var rule := ColorRect.new()
	rule.color = accent().darkened(0.55)
	rule.set_meta("ui_rect_color", BRASS.darkened(0.55))
	rule.custom_minimum_size.y = 1
	v.add_child(rule)
	return v


## Restrained motion: a quick fade for panels as they open.
static func fade_in(c: CanvasItem, seconds: float = 0.14) -> void:
	if not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, seconds)


## Briefly tints a label (resource gained or spent), then eases back.
static func flash(l: Label, from: Color, to: Color = TEXT, seconds: float = 0.7) -> void:
	if not l.is_inside_tree():
		l.add_theme_color_override("font_color", to)
		return
	var tw := l.create_tween()
	tw.tween_method(func(c: Color): l.add_theme_color_override("font_color", c), from, to, seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## "not enough gold" -> "Not enough gold".
static func sentence(text: String) -> String:
	return text if text.is_empty() else text.left(1).to_upper() + text.substr(1)
