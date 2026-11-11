class_name ArtifactSlot
extends Control
## One equipment or pack slot: the brass slot frame with the slot-type icon
## (weapon, helm, armor, shield, boots, charm, banner). An empty slot shows the icon faded; an
## artifact shows it in full with a rim in its rarity colour. Emits clicks;
## holds no rules.

signal clicked(slot: ArtifactSlot, shift: bool)

const SIZE := 52
## Drawn icon size: the slot art is 48 px, shown a little smaller inside the frame.
const ICON_PX := 40.0
const RARITY_COLORS := {"minor": Color("#a39788"), "major": Color("#c9a24a"), "relic": Color("#e0682a")}
const SLOT_ICONS := {"weapon": "attack", "helm": "hero", "armor": "armor", "shield": "defense", "boots": "move",
	"charm": "charm", "banner": "banner"}

var slot_type := ""
var artifact_id := ""
var rarity := ""
var _icon: Texture2D
var _frame: StyleBox
var _hover := false
var _touch_pending := false


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame = UiStyle.slot_box(2.0)
	if _frame == null:
		_frame = UiStyle.panel_box(Color("#120f0b"), UiStyle.BRASS.darkened(0.3), 1)
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())


## slot: the slot type; artifact: "" for an empty slot.
func setup(slot: String, artifact: String, data: GameData, extra_tip: String = "") -> ArtifactSlot:
	slot_type = slot
	artifact_id = artifact
	var def: Dictionary = data.artifacts.get(artifact, {})
	rarity = String(def.get("rarity", ""))
	_icon = null
	if artifact != "":
		var item_path := "res://assets/artifacts/%s.png" % artifact
		if ResourceLoader.exists(item_path):
			_icon = Art.texture_at(item_path)
	if _icon == null:
		_icon = Art.sprite("ui_icon_" + String(SLOT_ICONS.get(slot, "pack")))
	texture_filter = UiStyle.smooth_filter(_icon, ICON_PX)
	if artifact == "":
		tooltip_text = "%s slot: empty" % slot.capitalize() + extra_tip
	else:
		tooltip_text = "%s\n%s %s\n%s" % [def.get("name", artifact), rarity.capitalize(), slot, def.get("text", "")] \
			+ set_tip(artifact, data) + extra_tip
	queue_redraw()
	return self


## The set an artifact belongs to and its bonuses, for tooltips ("" if none).
static func set_tip(artifact: String, data: GameData) -> String:
	var sid := data.artifact_set_of(artifact)
	if sid == "":
		return ""
	var st: Dictionary = data.artifact_sets[sid]
	var names: Array = (st["pieces"] as Array).map(func(a): return data.artifacts[a]["name"])
	var lines := ["", "Part of the %s (%s):" % [st["name"], ", ".join(names)]]
	for b in st["bonuses"]:
		lines.append("  " + String(b["text"]))
	return "\n".join(lines)


func is_empty() -> bool:
	return artifact_id == ""


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_frame, r)
	if _icon != null:
		var k := minf(ICON_PX / _icon.get_size().x, ICON_PX / _icon.get_size().y)
		if k >= 1.0:
			k = floorf(k)  # small pixel icons (the pack bag) keep whole pixels
		var d := _icon.get_size() * k
		var col := Color(1, 1, 1, 0.22) if artifact_id == "" else Color.WHITE
		draw_texture_rect(_icon, Rect2((size - d) * 0.5, d), false, col)
	if artifact_id != "":
		draw_rect(r.grow(-2), RARITY_COLORS.get(rarity, UiStyle.BRASS), false, 2.0)
	if _hover:
		draw_rect(r.grow(-1), UiStyle.accent().lightened(0.2), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if TouchGestures.touch_ui():
		if event.pressed:
			_touch_pending = true
		else:
			if _touch_pending and Rect2(Vector2.ZERO, size).has_point(event.position):
				clicked.emit(self, event.shift_pressed)
			_touch_pending = false
	elif event.pressed:
		clicked.emit(self, event.shift_pressed)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN or what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_EXIT_TREE:
		_touch_pending = false


func _refresh_faction_style() -> void:
	_frame = UiStyle.slot_box(2.0)
	queue_redraw()
