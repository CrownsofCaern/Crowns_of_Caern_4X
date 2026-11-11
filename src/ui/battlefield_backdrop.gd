class_name BattlefieldBackdrop
extends Control
## Independently filtered scenery; the parent's creature drawing stays pixel-crisp.

var scene: Dictionary = {}
var texture: Texture2D
var horizon_ratio := 0.30


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(record: Dictionary, horizon: float) -> void:
	scene = record
	horizon_ratio = horizon
	texture = null
	var path := String(record.get("path", ""))
	if path != "":
		if ResourceLoader.exists(path):
			texture = load(path)
		elif FileAccess.file_exists(path):
			var image := Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
				texture = ImageTexture.create_from_image(image)
	visible = texture != null
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	var region := BattlefieldArt.source_rect(texture.get_size(),size,float(scene.get("horizon_ratio",0.30)),horizon_ratio)
	if region.has_area():
		draw_texture_rect_region(texture,Rect2(Vector2.ZERO,size),region)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
