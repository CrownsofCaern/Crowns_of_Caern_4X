class_name ArtifactFoundDialog
extends ModalPanel
## Shown when a hero picks up an artifact or armor piece: the item's artwork,
## name, rarity and slot, what it does, its set, and whether the hero put it on
## or packed it. Holds no rules; it only reads GameData and the hero.

signal closed

const ART_PX := 128.0


## Artifacts that `after` holds beyond `before` (both from Hero.all_artifacts),
## counting duplicates, in the order they appear in `after`.
static func gained(before: Array, after: Array) -> Array[String]:
	var left := before.duplicate()
	var out: Array[String] = []
	for a in after:
		var i := left.find(a)
		if i >= 0:
			left.remove_at(i)
		else:
			out.append(String(a))
	return out


## The item's artwork, or its slot icon when it has none yet.
static func artwork(artifact_id: String, data: GameData) -> Texture2D:
	var tex := Art.texture_at("res://assets/artifacts/%s.png" % artifact_id)
	if tex == null:
		var slot := String(data.artifacts.get(artifact_id, {}).get("slot", ""))
		tex = Art.sprite("ui_icon_" + String(ArtifactSlot.SLOT_ICONS.get(slot, "pack")))
	return tex


func open(hero: Hero, artifact_ids: Array) -> void:
	_clear()
	var many := artifact_ids.size() > 1
	_body.add_child(UiStyle.label("%s finds %s" % [hero.name, "treasure" if many else "an item"], 22, UiStyle.BRASS))
	_body.add_child(HSeparator.new())
	for aid in artifact_ids:
		_body.add_child(_item_row(hero, String(aid)))
	_buttons([["Onward", func():
		hide()
		closed.emit()]])
	show()
	UiStyle.fade_in(self)


func _item_row(hero: Hero, aid: String) -> Control:
	var def: Dictionary = _data.artifacts[aid]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var frame := PanelContainer.new()
	var box := UiStyle.slot_box(2.0)
	if box != null:
		frame.add_theme_stylebox_override("panel", box)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var pic := TextureRect.new()
	pic.name = "ArtifactArt"
	pic.texture = artwork(aid, _data)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(ART_PX, ART_PX)
	if pic.texture != null:
		pic.texture_filter = UiStyle.smooth_filter(pic.texture, ART_PX)
	frame.add_child(pic)
	row.add_child(frame)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rarity := String(def.get("rarity", ""))
	var width := _panel.custom_minimum_size.x - ART_PX - 56.0
	text.add_child(UiStyle.label(String(def["name"]), 18, ArtifactSlot.RARITY_COLORS.get(rarity, UiStyle.TEXT)))
	text.add_child(UiStyle.label("%s %s" % [rarity.capitalize(), String(def["slot"])], 13, UiStyle.TEXT_DIM))
	text.add_child(_line(String(def.get("text", "")), 15, UiStyle.TEXT, width))
	var set_text := ArtifactSlot.set_tip(aid, _data).strip_edges()
	if set_text != "":
		text.add_child(_line(set_text, 13, UiStyle.TEXT_DIM, width))
	var worn := String(hero.equipment.get(String(def["slot"]), "")) == aid
	text.add_child(_line("Worn now." if worn else "Packed; wear it from the hero screen (H).", 13, UiStyle.GOOD if worn else UiStyle.TEXT_DIM, width))
	row.add_child(text)
	return row


func _line(s: String, px: int, color: Color, width: float) -> Label:
	var l := UiStyle.label(s, px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


## The artwork shown for the first item (for tests and screenshots).
func art_rect() -> TextureRect:
	return _body.find_child("ArtifactArt", true, false) as TextureRect
