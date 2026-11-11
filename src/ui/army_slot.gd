class_name ArmySlot
extends Control
## One army slot: brass slot frame, creature sprite 1:1, stack count in the
## corner. Draws a highlight when selected. Emits clicks; holds no rules.

signal clicked(slot: ArmySlot, shift: bool)

const SIZE := 68

var index := 0
var creature := ""
var count := 0
var veteran_level := 0
var selected := false
var dim := false
var _tex: Texture2D
var _frame: StyleBox
var _hover := false
var _touch_pending := false
## Faction ultimate treatment for the sprite (with_ultimate); null = plain.
var _glow: ShaderMaterial
var _art: Control    # sprite layer with the shader (with_ultimate)
var _over: Control   # count and selection above it


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame = UiStyle.slot_box(2.0)
	if _frame == null:
		_frame = UiStyle.panel_box(Color("#120f0b"), UiStyle.accent().darkened(0.3), 1)
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())


func setup(slot_index: int, creature_id: String, stack_count: int, tip: String, level: int = 1) -> ArmySlot:
	index = slot_index
	creature = creature_id
	count = stack_count
	veteran_level = level
	_tex = Art.creature(creature_id, level) if creature_id != "" else null
	tooltip_text = tip
	queue_redraw()
	return self


## Shows the creature with its faction's ultimate treatment (UltimateCreatureArt)
## when `faction` is not empty. The sprite then draws in its own child layer so
## the shader never touches the frame, and the count draws in a layer above it.
func with_ultimate(faction: String) -> ArmySlot:
	_glow = UltimateCreatureArt.material_for(faction) if faction != "" else null
	if _glow != null and _art == null:
		_art = _layer(_draw_sprite)
		_over = _layer(_draw_marks)
	if _art != null:
		_art.material = _glow
		_art.visible = _glow != null
		_over.visible = _glow != null
		_art.queue_redraw()
		_over.queue_redraw()
	queue_redraw()
	return self


func _layer(painter: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(func(): painter.call(c))
	add_child(c)
	return c


## Shrinks the slot (the HUD side panel fits five small slots per row).
func with_size(px: int) -> ArmySlot:
	custom_minimum_size = Vector2(px, px)
	return self


func is_empty() -> bool:
	return creature == ""


## Side of the veteran rank symbol: a fifth of the slot, at least 10 px.
func rank_px() -> float:
	return maxf(10.0, roundf(minf(size.x, size.y) * 0.2)) if size.x > 0.0 else 14.0


func set_selected(on: bool) -> void:
	selected = on
	queue_redraw()


func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	if _glow == null:
		_draw_sprite(self)
		_draw_marks(self)
	elif _art != null:
		_art.queue_redraw()
		_over.queue_redraw()


func _draw_sprite(canvas: CanvasItem) -> void:
	if _tex == null:
		return
	var ts := _tex.get_size()
	var scale := maxf(1.0, floorf(minf((size.x - 4) / ts.x, (size.y - 4) / ts.y)))
	if ts.x > size.x - 4:
		scale = (size.x - 4) / ts.x
	var d := ts * scale
	canvas.draw_texture_rect(_tex, Rect2((size - d) * 0.5, d), false, Color(1, 1, 1, 0.45 if dim else 1.0))


func _draw_marks(canvas: CanvasItem) -> void:
	var r := Rect2(Vector2.ZERO, size)
	if count > 0:
		var font := get_theme_default_font()
		var txt := str(count)
		var fs := 15
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(size.x - w - 5, size.y - 5)
		canvas.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color("#120d0b"))
		canvas.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.TEXT)
	if count > 0 and veteran_level > 0:
		RankBadge.paint(canvas, Vector2(5, 5), veteran_level, rank_px())
	if selected:
		canvas.draw_rect(r.grow(-1), UiStyle.accent().lightened(0.25), false, 2.0)
	elif _hover:
		canvas.draw_rect(r.grow(-1), UiStyle.accent().darkened(0.1), false, 1.0)


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
