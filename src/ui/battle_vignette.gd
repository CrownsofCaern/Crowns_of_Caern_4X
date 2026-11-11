class_name BattleVignette
extends Control
## Terrain scenery for the battle forecast, report and live viewer.
## Stacks face each other over a shared painted field; missing scenery falls
## back to the original sky and ground tiles. Destroyed stacks become dark shapes.
## Pure drawing from data handed in; no rules.

const SKY_TOP := Color("#1a0707")
const SKY_LOW := Color("#7a1c12")

var terrain_id := "grass"
var selected_background := ""
var _background: BattlefieldBackdrop
## Where the sky meets the ground, as a share of the height.
var horizon_ratio := 0.52
## [{creature, alive}] per side, front stacks first.
var left: Array = []
var right: Array = []
var _animation_time := 0.0
var _sky: GradientTexture2D
var _ground: Array = []        # AtlasTexture variants


func _init() -> void:
	custom_minimum_size = Vector2(0, 132)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var g := Gradient.new()
	g.set_color(0, SKY_TOP)
	g.set_color(1, SKY_LOW)
	_sky = GradientTexture2D.new()
	_sky.gradient = g
	_sky.fill_from = Vector2(0.5, 0.0)
	_sky.fill_to = Vector2(0.5, 1.0)
	_sky.width = 8
	_sky.height = 64


func setup(terrain: String, left_side: Array, right_side: Array, visual_seed: int = 0) -> void:
	_animation_time = 0.0
	terrain_id = terrain
	var scene := BattlefieldArt.select(terrain,visual_seed)
	selected_background = String(scene.get("id",""))
	if _background == null:
		_background = BattlefieldBackdrop.new()
		add_child(_background)
	_background.setup(scene,horizon_ratio)
	left = left_side.duplicate(true)
	right = right_side.duplicate(true)
	_ground.clear()
	var info := Art.terrain_info()
	var sheet := Art.texture_at(info.get("atlas", ""))
	var row: Dictionary = info.get("terrains", {}).get(terrain, {})
	if sheet != null and not row.is_empty():
		var ts := float(info["tile_size"])
		for v in int(info.get("variants", 1)):
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(v * ts, int(row["row"]) * ts, ts, ts)
			_ground.append(at)
	queue_redraw()


func _draw() -> void:
	var horizon := size.y * horizon_ratio
	if _background == null or _background.texture == null:
		_draw_legacy_background(horizon)
	_draw_side(left, false, horizon)
	_draw_side(right, true, horizon)
	# Vignette edges.
	for k in 6:
		var a := 0.10 * (6 - k) / 6.0
		draw_rect(Rect2(k * 4, 0, 4, size.y), Color(0, 0, 0, a))
		draw_rect(Rect2(size.x - (k + 1) * 4, 0, 4, size.y), Color(0, 0, 0, a))


## Lines a side up from the centre outwards, in two staggered ranks; lower
## figures are drawn last so they stand in front.
func _draw_side(units: Array, mirrored: bool, horizon: float) -> void:
	var figs := []
	for idx in mini(units.size(), 7):
		var u: Dictionary = units[idx]
		var tex := Art.creature(u["creature"], int(u.get("veteran_level", 1)))
		var anchor := Art.anchor("creature_" + String(u["creature"]))
		if u.get("alive", true):
			var frame := UnitAnimation.sample("creature_" + String(u["creature"]), String(u.get("action", "idle")), _animation_time - float(u.get("action_started", 0.0)))
			if not frame.is_empty():
				tex = frame["texture"]
				anchor = frame["anchor"]
		if tex == null:
			continue
		var rank := idx % 2
		var dx := 44.0 + idx * 34.0 + rank * 6.0
		figs.append({"tex": tex, "x": size.x * 0.5 + (dx if mirrored else -dx),
			"foot": horizon + 46.0 + rank * 18.0 - (idx % 3) * 4.0, "alive": u.get("alive", true), "anchor": anchor})
	figs.sort_custom(func(p, q): return p["foot"] < q["foot"])
	for f in figs:
		var tex: Texture2D = f["tex"]
		var d := tex.get_size()
		var col := Color.WHITE if f["alive"] else Color(0.12, 0.08, 0.08, 0.85)
		draw_set_transform(Vector2(f["x"], f["foot"]), 0.0, Vector2(-1, 1) if mirrored else Vector2.ONE)
		draw_texture_rect(tex, Rect2(-f["anchor"], d), false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Future battle playback can drive this with authoritative action events.
## Forecasts stay still; attacks are never invented or started automatically.
func play_action(on_right: bool, index: int, action: String) -> void:
	var units := right if on_right else left
	if index < 0 or index >= units.size() or not units[index].get("alive", true):
		return
	units[index]["action"] = action
	units[index]["action_started"] = _animation_time
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_animation_time += delta
	var changed := false
	for side in [left, right]:
		for unit in side:
			var action := String(unit.get("action", "idle"))
			if action in ["move", "attack"]:
				changed = true
				if action == "attack":
					var animation := UnitAnimation.clip("creature_" + String(unit["creature"]), action)
					if UnitAnimation.frame_index(animation, _animation_time - float(unit.get("action_started", 0.0))) < 0:
						unit["action"] = "idle"
	if changed:
		queue_redraw()


func _draw_legacy_background(horizon: float) -> void:
	draw_texture_rect(_sky, Rect2(0, 0, size.x, horizon), false)
	# A pale moon low in the sky, for mood.
	draw_circle(Vector2(size.x * 0.82, horizon * 0.42), 13.0, Color("#b83a22", 0.55))
	draw_circle(Vector2(size.x * 0.82, horizon * 0.42), 10.0, Color("#e0682a", 0.35))
	if _ground.is_empty():
		draw_rect(Rect2(0, horizon, size.x, size.y - horizon), Color("#2a2420"))
	else:
		var ts: float = (_ground[0] as Texture2D).get_size().x
		var x := 0.0
		var i := 0
		while x < size.x:
			var y := horizon
			while y < size.y:
				draw_texture_rect(_ground[(i * 7 + int(y)) % _ground.size()], Rect2(x, y, ts, ts), false)
				y += ts
				i += 1
			x += ts
		draw_rect(Rect2(0, horizon, size.x, size.y - horizon), Color(0, 0, 0, 0.25))
	draw_line(Vector2(0, horizon), Vector2(size.x, horizon), Color("#120d0b", 0.7), 2.0)
