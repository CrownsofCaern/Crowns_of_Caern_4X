class_name BattleViewer
extends Control
## Optional live view of a battle that has already been resolved: retells the
## recorded log (BattleReplay) as a clash. Every round plays at once; each
## battalion splits into groups that pair off with the enemy groups they
## trade blows with, so the field shows who fought whom and who lost
## creatures to whom. Figures fall where they were struck and leave blood
## (or bone dust, sparks, embers, sap) behind. The outcome is fixed before
## the first frame; watching never changes it. Esc or Skip jumps to the end.
## Pure presentation, no rules.

signal finished

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "battle"
const SPEEDS := [1.0, 2.0, 4.0]
const TOP_H := 46.0
const HORIZON := 0.30
const FIGHT_SOUND_GAP := 0.12
## Longest a group waits for its charge to arrive before it strikes anyway.
const CHARGE_WAIT := 2.6
## Two fights closer than this are pushed apart.
const FIGHT_ROOM := 78.0
## How close two standing figures may stand, as a share of their summed
## radii (friends shoulder to shoulder, foes at arm's length). Depth on the
## ground counts ROOM_DEPTH times as much as width, so ranks may overlap.
const ROOM_FRIEND := 0.6
const ROOM_FOE := 0.85
const ROOM_DEPTH := 2.2
## Battle seconds between two small effects of brawl swings, so a big melee
## keeps a steady patter of sparks and blood instead of a flood.
const BRAWL_FX_GAP := 0.07
## Most lingering ground effects (embers, mist) alive at once.
const MAX_LINGER := 10
## How fast a charge runs compared with a walk.
const CHARGE_RUSH := 1.45
## Seconds a round takes before one has been timed (at speed 1).
const ROUND_GUESS := 6.0
## The slowest march pace (share of a figure's walk); slower would look like
## wading, so a battalion with time to spare holds its ranks a little longer
## and sets off later, in step, to arrive on time.
const MARCH_MIN_PACE := 0.45
## How often (seconds) figures look round for a foe in reach to fight.
const SCAN_GAP := 0.25
## How far in front of a held line the attackers form up (field pixels).
const HELD_GAP := 90.0
## Gap (field pixels) between the two blocks' front edges when they meet.
const BLOCK_GAP := 4.0
## Share of the field's height a block row may span.
const BLOCK_FILL := 0.8
## Room around each figure in a block (1 = shoulder to shoulder).
const BLOCK_ROOM := 1.25
## Figures per row of a block: about sqrt(figures x this).
const BLOCK_ASPECT := 1.6

var _replay: BattleReplay
var _figs: Dictionary = {}      # stack key -> BattleFigure
var _speed := 1.0
var _last_hit_ms := -1000
var _skip := false
var _bg: BattleVignette
## The 3D battlefield (LiveUnit models on the src/world3d ground), or null where
## this build has no 3D (then the painted backdrop and sprites show).
var _stage: BattleStage3D
## The 3D stage, built once; _stage is it while a battle plays in 3D, null
## when the player chose the sprite battlefield (see three_d_enabled).
var _stage3d: BattleStage3D
var _field: Node2D
var _overlay: Node2D
var _round_label: Label
var _title: Label
var _verdict: Label
var _speed_buttons: Array = []
var _orders: Array = [{}, {}]   # each side's battle orders {stance, focus}
var _start_home: Dictionary = {} # stack key -> home before the lines closed
var _engaged: Dictionary = {}    # stack key -> true while (some of) it is locked in melee
var _shown_at: Dictionary = {}   # stack key -> log index of the count shown
## stack key -> {enemy stack key -> [figure indices]}: who fights whom this round.
var _groups: Dictionary = {}
var _meet: Dictionary = {}       # "a|b" -> where that pair fights
var _round_meets: Dictionary = {} # the fights placed this round
var _ground := Rect2()
## stack key -> the round it first trades melee blows (absent: never).
var _first_fight: Dictionary = {}
## stack key -> [[round, foe key], ...]: every round it trades melee blows.
var _fights: Dictionary = {}
## Held reserve: stack key -> the round it enters (absent: not a reserve, or it
## never entered). Reserves without an entry wait at the back all battle.
var _reserve_entry: Dictionary = {}
var _reserves: Dictionary = {}   # stack key -> true for every held reserve
## Skirmish screen: stack key -> x the skirmisher falls back to behind its line.
var _retire_x: Dictionary = {}
## Ring colours under the figures that tell the two sides apart.
const SIDE_COLORS := [Color("#7aa6ff"), Color("#ff6a50")]
const FORMATION_NAMES := {"front": "Front line", "flank": "Flank", "back": "Ranged", "support": "Support"}
## Battle time runs slower for a moment when a whole battalion is wiped out.
var _slowmo := 1.0
var _slowmo_id := 0
## Battle time played so far (seconds at speed 1, slow motion included).
var _clock := 0.0
var _round_at := -1.0            # _clock when the last round began
var _round_len := ROUND_GUESS    # average seconds per round so far
var _rounds_timed := 0
var _scan_at := 0.0
## Melee blocks (design decision, Nov 11): each side's front-line infantry stands in
## one mixed block, rows ordered by when the log has them fall (the front
## row dies first), as many to a row as fit without crowding. As a row falls
## the ones behind step up. side -> [[stack key, figure], ...] in that order.
var _blocks: Array = [[], []]
var _block_of: Dictionary = {}       # stack key -> true for stacks in a block
## Block figures on a block's outer edge -> the way out of the block there
## (field direction); flankers fight only these, from outside.
var _block_edge: Dictionary = {}
var _block_front: Array[float] = [0.0, 0.0] # x of each block's front edge
var _block_alive: Array[int] = [0, 0]
var _use_blocks := false
## Choreographs the melee between the logged blows (3D battles only).
var _director := BattleDirector.new()
var _directing := false
var _brawl_fx_at := 0.0
var _lingering: Array = []


# ----------------------------------------------------------- preferences ---

## Whether the player wants to watch battles (off unless they ticked it).
static func watch_enabled(path: String = SETTINGS_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	return bool(cfg.get_value(SECTION, "watch", false))


static func set_watch_enabled(on: bool, path: String = SETTINGS_PATH) -> void:
	_save_value("watch", on, path)


## Whether watched battles play on the 3D battlefield (on unless the player
## unticked it); off, they play on the sprite battlefield.
static func three_d_enabled(path: String = SETTINGS_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return true
	return bool(cfg.get_value(SECTION, "three_d", true))


static func set_three_d_enabled(on: bool, path: String = SETTINGS_PATH) -> void:
	_save_value("three_d", on, path)


static func saved_speed(path: String = SETTINGS_PATH) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return 1.0
	var s := float(cfg.get_value(SECTION, "speed", 1.0))
	return s if SPEEDS.has(s) else 1.0


static func _save_value(k: String, v: Variant, path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)   # keep the other sections (audio)
	cfg.set_value(SECTION, k, v)
	cfg.save(path)


# ----------------------------------------------------------------- build ---

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = BattleVignette.new()
	_bg.horizon_ratio = HORIZON
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	if BattleStage3D.available():
		_stage3d = BattleStage3D.new()
		add_child(_stage3d)
		_stage3d.build()
		_stage3d.visible = false
	_field = Node2D.new()
	_field.y_sort_enabled = true
	# Above the scenery, so pools and the fallen (negative z) stay visible.
	_field.z_index = 10
	add_child(_field)
	_overlay = Node2D.new()
	_overlay.z_index = 50
	add_child(_overlay)
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, TOP_H)
	bar.z_index = 60
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	_title = UiStyle.label("", 16, UiStyle.BRASS)
	row.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_round_label = UiStyle.label("", 16)
	row.add_child(_round_label)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer2)
	var group := ButtonGroup.new()
	for s in SPEEDS:
		var b := Button.new()
		b.text = "%dx" % int(s)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44, 32)
		b.pressed.connect(_set_speed.bind(s, true))
		row.add_child(b)
		_speed_buttons.append(b)
	var skip := Button.new()
	skip.text = "Skip"
	skip.tooltip_text = "Show the result now  (Esc)"
	skip.focus_mode = Control.FOCUS_NONE
	skip.custom_minimum_size = Vector2(90, 32)
	skip.pressed.connect(skip_to_end)
	row.add_child(skip)
	_verdict = UiStyle.label("", 44, UiStyle.BRASS)
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_verdict.add_theme_color_override("font_outline_color", Color.BLACK)
	_verdict.add_theme_constant_override("outline_size", 10)
	_verdict.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_verdict.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_verdict.grow_vertical = Control.GROW_DIRECTION_BOTH
	_verdict.z_index = 60
	add_child(_verdict)
	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_SPACE or event.keycode == KEY_ENTER):
		skip_to_end()
		get_viewport().set_input_as_handled()


func skip_to_end() -> void:
	_skip = true


func is_playing() -> bool:
	return _replay != null


# ------------------------------------------------------------------ play ---

## Plays a recorded result (it must carry a log) and returns when the player
## has seen the end or skipped. Await it.
func play(result: Dictionary, attacker_name: String = "", perspective: int = 0, settings_path: String = SETTINGS_PATH) -> void:
	_clear()
	_stage = _stage3d if three_d_enabled(settings_path) else null
	if _stage3d != null:
		_stage3d.visible = _stage != null
	_replay = BattleReplay.from_result(result)
	_skip = false
	_bg.setup(String(result.get("visual_terrain",result.get("terrain","grass"))), [], [], int(result.get("visual_seed",result.get("seed",0))))
	var names: Array = [result["sides"][0]["name"], result["sides"][1]["name"]]
	_title.text = "%s  vs  %s" % [attacker_name if attacker_name != "" else names[0], names[1]]
	_round_label.text = ""
	_verdict.text = ""
	var ords: Array = result.get("orders", [{}, {}])
	_orders = [ords[0] if ords.size() > 0 else {}, ords[1] if ords.size() > 1 else {}]
	_first_fight = first_fights(_replay)
	_fights = fight_rounds(_replay)
	_reserve_entry = reserve_entries(_replay)
	_bg.visible = _stage == null
	if _stage != null:
		_stage.setup(String(result.get("terrain", "grass")), int(result.get("visual_seed", result.get("seed", 0))),
			ground_rect(get_viewport_rect().size))
	_layout()
	_use_blocks = _stage != null
	if _use_blocks:
		_build_blocks()
	_set_speed(saved_speed(), false)
	show()
	UiStyle.fade_in(self)
	AudioManager.begin_battle_music()
	_last_hit_ms = -1000
	_announce_orders()
	_announce_formations()
	await _wait(1.3)
	await _play_rounds()
	_settle()
	var won: bool = result["winner"] == perspective
	_verdict.text = "Victory!" if won else ("Fell back" if int(result.get("withdrew", -1)) == perspective else ("Withdrawal" if perspective == 0 and result["outcome"] == "attacker_withdrew" else "Defeat"))
	_verdict.add_theme_color_override("font_color", UiStyle.BRASS.lightened(0.2) if won else UiStyle.BAD)
	if not _skip:
		await _wait(1.4)
	AudioManager.end_battle_music()
	hide()
	_clear()
	finished.emit()


func _set_speed(s: float, remember: bool) -> void:
	_speed = s
	for i in SPEEDS.size():
		if i < _speed_buttons.size():
			_speed_buttons[i].set_pressed_no_signal(is_equal_approx(SPEEDS[i], s))
	_set_figure_speed()
	if remember:
		_save_value("speed", s, SETTINGS_PATH)


func _clear() -> void:
	for c in _field.get_children() + _overlay.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	_figs.clear()
	if _stage != null:
		_stage.clear_units()
	_start_home.clear()
	_engaged.clear()
	_shown_at.clear()
	_groups.clear()
	_meet.clear()
	_round_meets.clear()
	_first_fight.clear()
	_fights.clear()
	_reserve_entry.clear()
	_reserves.clear()
	_retire_x.clear()
	_field.position = Vector2.ZERO
	_slowmo = 1.0
	_clock = 0.0
	_round_at = -1.0
	_round_len = ROUND_GUESS
	_rounds_timed = 0
	_scan_at = 0.0
	_director.clear()
	_blocks = [[], []]
	_block_of.clear()
	_block_alive = [0, 0] as Array[int]
	_brawl_fx_at = 0.0
	_lingering.clear()
	_replay = null


## Where each part of an army forms up for a battle formation (shares of the
## screen width from the middle; spans are shares of the ground's height kept
## free at the top and bottom). shape: the front blocks' BattleFigure.shape;
## arrow: how far the middle battalion of the front leads the others;
## flank_centre: the flankers ride behind the point instead of on the wings;
## retire: where a skirmish screen falls back to once the lines close.
static func deployment(formation: String) -> Dictionary:
	var plan := {"front": 0.15, "front_span": 0.18, "support": 0.26, "back": 0.37, "flank": 0.21,
		"wing_span": 0.2, "shape": "", "arrow": 0.0, "flank_centre": false, "retire": -1.0}
	match formation:
		"shield_wall":
			# One long locked wall, the archers right behind it.
			plan.merge({"front": 0.17, "front_span": 0.04, "support": 0.22, "back": 0.26, "flank": 0.25,
				"shape": "wall"}, true)
		"wedge":
			# An arrowhead: the middle leads, the cavalry rides in behind the point.
			plan.merge({"front": 0.15, "front_span": 0.3, "support": 0.27, "flank": 0.22, "shape": "wedge",
				"arrow": 0.06, "flank_centre": true}, true)
		"skirmish_screen":
			# Archers out ahead of the line, falling back behind it when it closes.
			plan.merge({"front": 0.21, "support": 0.29, "back": 0.1, "flank": 0.24, "retire": 0.37}, true)
		"crescent":
			# A held-back centre, horns sweeping forward and out.
			plan.merge({"front": 0.21, "front_span": 0.26, "support": 0.3, "flank": 0.1, "wing_span": 0.16}, true)
	return plan


## The armies deploy as their formations say: attackers on the left,
## defenders on the right. In the plain battle line the front stands nearest
## the middle, flankers on the wings (top and bottom), support behind the
## front and the ranged line at the back; the other formations move these
## parts (see deployment()). A held reserve waits far behind its army.
func _layout() -> void:
	var vp := get_viewport_rect().size
	var cx := vp.x * 0.5
	_ground = ground_rect(vp)
	var top := _ground.position.y + 14.0
	var bottom := _ground.end.y - 6.0
	var h := bottom - top
	for s in 2:
		var lines := {"front": [], "flank": [], "back": [], "support": [], "reserve": []}
		for st in _replay.stacks[s]:
			var form := String(st["formation"])
			if int(st.get("reserve", 0)) > 0:
				lines["reserve"].append(st)
				continue
			lines[form if lines.has(form) else "front"].append(st)
		var away := -1.0 if s == 0 else 1.0
		var shift := _stance_shift(s) * vp.x
		var plan := deployment(String(_orders[s].get("formation", "line")))
		_deploy(lines["front"], s, cx + away * (vp.x * float(plan["front"]) + shift), top + h * float(plan["front_span"]),
			bottom - h * float(plan["front_span"]), "front", String(plan["shape"]), float(plan["arrow"]) * vp.x)
		_deploy(lines["support"], s, cx + away * (vp.x * float(plan["support"]) + shift), top + h * 0.25, bottom - h * 0.25, "support")
		_deploy(lines["back"], s, cx + away * vp.x * float(plan["back"]), top + h * 0.08, bottom - h * 0.08, "back")
		if float(plan["retire"]) > 0.0:
			for st in lines["back"]:
				_retire_x[st["key"]] = cx + away * vp.x * float(plan["retire"])
		var flank_x := cx + away * (vp.x * float(plan["flank"]) + shift)
		if bool(plan["flank_centre"]):
			_deploy(lines["flank"], s, flank_x, top + h * 0.3, bottom - h * 0.3, "flank")
		else:
			var wings: Array = [[], []]
			for k in lines["flank"].size():
				wings[k % 2].append(lines["flank"][k])
			var ws := float(plan["wing_span"])
			_deploy(wings[0], s, flank_x, top, top + h * ws * maxf(1.0, wings[0].size()), "flank")
			_deploy(wings[1], s, flank_x, bottom - h * ws * maxf(1.0, wings[1].size()), bottom, "flank")
		_deploy(lines["reserve"], s, cx + away * vp.x * 0.43, top + h * 0.3, bottom - h * 0.3, "front", "wedge" if plan["shape"] == "wedge" else "")
		for st in lines["reserve"]:
			_reserves[st["key"]] = true


## Spreads one line's battalions evenly between y0 and y1 at x. shape: the
## blocks' BattleFigure.shape; arrow: how far (pixels) the middle battalion
## stands ahead of the outermost ones.
func _deploy(list: Array, side: int, x: float, y0: float, y1: float, form: String, shape: String = "", arrow: float = 0.0) -> void:
	var n := list.size()
	for k in n:
		var st: Dictionary = list[k]
		var f := BattleFigure.new()
		f.stage = _stage
		f.key = st["key"]
		f.formation = form
		f.shape = shape
		f.span_y = maxf(30.0, (y1 - y0) / maxf(1.0, n) * (0.95 if shape == "wall" else 0.8))
		f.side_color = SIDE_COLORS[side]
		var y := lerpf(y0, y1, (k + 0.5) / float(n))
		var dir := -1.0 if side == 0 else 1.0
		# Neighbouring battalions stand a little apart in depth; in a wedge the
		# middle leads.
		var lead := 0.0
		if arrow != 0.0 and n > 1:
			lead = arrow * (1.0 - absf((k + 0.5) / float(n) - 0.5) * 2.0)
		elif arrow != 0.0:
			lead = arrow
		f.home = Vector2(x - dir * lead + dir * (8.0 if k % 2 == 1 and shape != "wall" else 0.0), y)
		f.position = f.home
		f.setup(st["creature"], int(st["start"]), -dir, float(k) * 1.3 + side, String(st.get("ultimate", "")) != "", int(st.get("veteran_level", 1)))
		_start_home[st["key"]] = f.home
		f.set_speed(_speed)
		f.brawl_hit.connect(_on_brawl_hit)
		_field.add_child(f)
		_figs[st["key"]] = f


## The part of a `vp`-sized viewer where the armies stand (pixels).
static func ground_rect(vp: Vector2) -> Rect2:
	var ground_top := vp.y * HORIZON + 60.0
	return Rect2(Vector2(vp.x * 0.05, ground_top + 16.0), Vector2(vp.x * 0.90, vp.y - ground_top - 54.0))


## For each held reserve that entered the fight, the round it entered.
static func reserve_entries(replay: BattleReplay) -> Dictionary:
	var out := {}
	for st in replay.steps:
		if String(st.get("type", "")) == "reserve" and String(st["actor"]) != "" and not out.has(st["actor"]):
			out[st["actor"]] = int(st["round"])
	return out


## For each stack, the round it first trades melee blows in.
static func first_fights(replay: BattleReplay) -> Dictionary:
	var out := {}
	for st in replay.steps:
		if st["kind"] in [BattleReplay.MELEE, BattleReplay.ANSWER]:
			for role in ["actor", "target"]:
				var k := String(st[role])
				if k != "" and not out.has(k):
					out[k] = int(st["round"])
	return out


## Every melee of every stack, in log order: stack key -> [[round, foe], ...].
static func fight_rounds(replay: BattleReplay) -> Dictionary:
	var out := {}
	for st in replay.steps:
		if st["kind"] in [BattleReplay.MELEE, BattleReplay.ANSWER]:
			var a := String(st["actor"])
			var t := String(st["target"])
			if a == "" or t == "":
				continue
			for pair in [[a, t], [t, a]]:
				if not out.has(pair[0]):
					out[pair[0]] = []
				out[pair[0]].append([int(st["round"]), pair[1]])
	return out


## The next melee of stack `k` from round `round_no` on: [round, foe key], or
## [] when it has no more.
func _next_fight(k: String, round_no: int) -> Array:
	for e in _fights.get(k, []):
		if int(e[0]) >= round_no:
			var g: BattleFigure = _figs.get(e[1])
			if g != null and not g.is_dead():
				return e
	return []


## Shows each battalion's place in the formation as the armies deploy.
func _announce_formations() -> void:
	for k in _figs:
		var f: BattleFigure = _figs[k]
		var label: String = "Reserve" if _reserves.has(k) else ("Skirmishers" if _retire_x.has(k) else FORMATION_NAMES.get(f.formation, ""))
		_pop(f.home + Vector2(0, 30), label, UiStyle.TEXT.darkened(0.15), 120.0, 1.8, 12)


## Where a side's army forms up: forward for an all-out attack, back for
## holding the line (a share of the screen width, + towards the enemy).
func _stance_shift(side: int) -> float:
	match String(_orders[side].get("stance", "balanced")):
		"aggressive": return -0.03
		"defensive": return 0.03
	return 0.0


## How fast a side's melee closes in, per round, as a share of the width.
func _advance_rate(side: int) -> float:
	var rate := 0.02
	match String(_orders[side].get("stance", "balanced")):
		"aggressive": rate = 0.03
		"defensive": rate = 0.01
	match String(_orders[side].get("formation", "line")):
		"wedge": rate += 0.01
		"shield_wall": rate -= 0.01
	return maxf(0.0, rate)


## Where a side's front line meets the enemy's: the middle, pushed towards
## the side that holds while the other attacks all out.
## A side that holds the line (one side only) is met where it stands: its
## front is the contact line and the attackers close the whole gap.
func _contact_x(side: int) -> float:
	var held := _held_side()
	if held >= 0:
		var front := _front_x(held)
		if not is_nan(front):
			var toward := 1.0 if held == 0 else -1.0   # from the holder towards the attackers
			return front if side == held else front + toward * HELD_GAP
	var vp := get_viewport_rect().size
	var gap := vp.x * 0.035
	var line := vp.x * 0.5 + (_advance_rate(0) - _advance_rate(1)) * 3.0 * vp.x
	return line + (-1.0 if side == 0 else 1.0) * gap


## Net advance of a side's orders: + closes in sooner, - holds back (the
## stance's and the formation's "advance" in tactics.json).
func _advance_orders(side: int) -> int:
	var n := 0
	match String(_orders[side].get("stance", "balanced")):
		"aggressive": n += 1
		"defensive": n -= 1
	match String(_orders[side].get("formation", "line")):
		"wedge": n += 1
		"shield_wall": n -= 1
	return n


## True when the side's orders hold the line (defensive stance or a shield
## wall, not outweighed by aggressive orders).
func _holds(side: int) -> bool:
	return _advance_orders(side) < 0


## The one side that holds while the other does not, or -1 (neither, or
## both: then the lines meet in the middle).
func _held_side() -> int:
	var h0 := _holds(0)
	var h1 := _holds(1)
	if h0 == h1:
		return -1
	return 0 if h0 else 1


## Where a side's front line stood at deployment (its foremost front
## battalion), or NAN when it has none.
func _front_x(side: int) -> float:
	var best := NAN
	for st in _replay.stacks[side]:
		var f: BattleFigure = _figs.get(st["key"])
		if f == null or f.formation != "front" or _reserves.has(f.key):
			continue
		var x: float = (_start_home.get(f.key, f.home) as Vector2).x
		if is_nan(best) or (x > best if side == 0 else x < best):
			best = x
	return best


## Seconds (at speed 1) until round `round_no` begins, from now (the start of
## `now_round`), by the rounds timed so far.
func _seconds_until(round_no: int, now_round: int) -> float:
	return maxf(0.0, float(round_no - now_round)) * _round_len


## The pace for `dist` pixels in `seconds` at a full walk of `walk_px` px/s:
## between MARCH_MIN_PACE and 1, or 0 when even the slowest pace would arrive
## too early (the battalion waits).
static func march_pace(dist: float, seconds: float, walk_px: float) -> float:
	var plan := march_plan(dist, seconds, walk_px)
	return 0.0 if plan.y > 0.0 else plan.x


## How to cover `dist` pixels in `seconds`: (pace, seconds to wait before
## setting off). Never slower than MARCH_MIN_PACE: with time to spare the
## battalion waits, then marches the whole way without stopping.
static func march_plan(dist: float, seconds: float, walk_px: float) -> Vector2:
	if dist <= 2.0 or seconds <= 0.0 or walk_px <= 0.0:
		return Vector2(1.0, 0.0)
	var want := dist / (seconds * walk_px)
	if want >= MARCH_MIN_PACE:
		return Vector2(minf(1.0, want), 0.0)
	return Vector2(MARCH_MIN_PACE, seconds - dist / (MARCH_MIN_PACE * walk_px))


## The armies march: battalions not locked in a fight walk on towards where
## they will first fight in one steady march, paced to arrive in the round
## their first melee comes (so the lines meet when the log says they do, with
## no stop-and-go each round). A side that holds the line stays where it
## stands and lets the enemy come. Flankers ride up their wing, support
## follows the front, the ranged line holds. Groups whose enemies have all
## fallen fall back into formation. Nobody waits for the march: figures walk
## while the rounds play.
func _march(round_no: int) -> void:
	if _skip:
		return
	if round_no >= 1:
		_round_sound(round_no)
		if _round_at >= 0.0:
			_rounds_timed += 1
			var took := _clock - _round_at
			_round_len = lerpf(_round_len, took, 1.0 / float(mini(_rounds_timed, 4)))
		_round_at = _clock
	var vp := get_viewport_rect().size
	var walk := BattleFigure.WALK_PX * 0.9
	for s in 2:
		var away := -1.0 if s == 0 else 1.0
		var holds := _holds(s) and _held_side() == s
		for st in _replay.stacks[s]:
			var f: BattleFigure = _figs.get(st["key"])
			if f == null or f.is_dead() or _block_of.has(f.key):
				continue
			if _engaged.has(f.key) and _has_living_foe(f.key):
				continue
			var was_engaged := _engaged.has(f.key)
			_engaged.erase(f.key)
			_groups.erase(f.key)
			var start: Vector2 = _start_home.get(f.key, f.home)
			var first := int(_first_fight.get(f.key, -1))
			if _reserves.has(f.key):
				# A held reserve waits behind the army until its round comes,
				# then marches up to the line.
				var entry := int(_reserve_entry.get(f.key, 999))
				if round_no < entry:
					continue
				_march_to(f, _contact_x(s), first, round_no, walk, 0.5)
				continue
			if _retire_x.has(f.key) and round_no >= 1:
				# The skirmish screen falls back behind its own line.
				f.home = Vector2(float(_retire_x[f.key]), f.home.y)
				f.form_up(0.8)
				continue
			if round_no >= 1 and not holds and f.formation != "back" and (was_engaged or (first >= 0 and round_no > first)):
				# Between fights: on towards the battalion it fights next, to
				# arrive when that fight comes, instead of standing about.
				var nxt := _next_fight(f.key, round_no + 1)
				if not nxt.is_empty():
					var g: BattleFigure = _figs[nxt[1]]
					var at := g.centroid(g.alive_members())
					var gap := (f.figure_width + g.figure_width) * 0.5 + 30.0
					f.home = Vector2(f.home.x, lerpf(f.home.y, at.y, 0.5))
					_march_to(f, at.x + away * gap, int(nxt[0]), round_no, walk, 0.2)
					continue
			if was_engaged:
				# Back from a fight: hold the ground it won.
				var x := f.centroid(f.alive_members()).x if f.formation != "back" else start.x
				f.home = Vector2(x, f.home.y)
				f.form_up(0.5)
				continue
			if round_no < 1 or holds:
				continue
			match f.formation:
				"front", "flank":
					var to := _contact_x(s) + (away * vp.x * 0.05 if f.formation == "flank" else 0.0)
					if first < 0:
						# Never meets the enemy in melee: closes up part way.
						to = lerpf(start.x, to, 0.6)
					_march_to(f, to, first if first >= 0 else round_no + 3, round_no, walk, 0.3)
				"support":
					_march_to(f, _contact_x(s) + away * vp.x * 0.1, maxi(round_no + 1, first if first >= 0 else 4), round_no, walk, 0.3)

	_march_blocks(round_no)


## The melee blocks close in one steady march, arriving as the first of
## their battalions' fights comes; a block that holds the line stays put and
## the other comes all the way to it, otherwise they meet in the middle.
func _march_blocks(round_no: int) -> void:
	if round_no < 1 or (_blocks[0].is_empty() and _blocks[1].is_empty()):
		return
	var first := -1
	for s in 2:
		for e in _blocks[s]:
			var r := int(_first_fight.get(e[0], -1))
			if r >= 0 and (first < 0 or r < first):
				first = r
	if first < 0:
		return
	var held := _held_side()
	var meet: float = (_block_front[0] + _block_front[1]) * 0.5
	if _blocks[0].is_empty() or _blocks[1].is_empty():
		meet = _contact_x(0 if _blocks[1].is_empty() else 1)
	for s in 2:
		if _blocks[s].is_empty() or held == s:
			continue
		var toward := 1.0 if s == 0 else -1.0
		var target: float = meet - toward * BLOCK_GAP
		if held == 1 - s and not _blocks[held].is_empty():
			target = _block_front[held] - toward * BLOCK_GAP * 2.0
		if absf(target - _block_front[s]) < 1.0:
			continue
		var plan := march_plan(absf(target - _block_front[s]), _seconds_until(first, round_no), BattleFigure.WALK_PX * 0.9)
		_block_front[s] = target
		_block_place(s, plan.x, plan.y)


## Builds both blocks at deployment (see _blocks): the order comes from the
## log, the block stands where the front line deployed.
func _build_blocks() -> void:
	for s in 2:
		var list := []
		for st in _replay.stacks[s]:
			var k := String(st["key"])
			var f: BattleFigure = _figs.get(k)
			if f == null or f.formation != "front" or _reserves.has(k) or _retire_x.has(k):
				continue
			_block_of[k] = true
			var deaths := death_steps(_replay, k, int(st["start"]), f.members.size())
			for i in f.alive_members():
				list.append([k, i, int(deaths.get(i, 1 << 30))])
		list.sort_custom(func(a, b):
			if a[2] != b[2]:
				return a[2] < b[2]
			if a[0] != b[0]:
				return String(a[0]) < String(b[0])
			return int(a[1]) > int(b[1]))
		_blocks[s] = list
		if list.is_empty():
			continue
		var front := _front_x(s)
		_block_front[s] = front if not is_nan(front) else get_viewport_rect().size.x * (0.4 if s == 0 else 0.6)
		_block_place(s, 1.0, 0.0, true)


## When each figure of stack `key` falls, by the log: figure -> index of the
## step that brings its count below it. Figures fall from the last one down
## (BattleFigure.apply_count with no preferred figures), so the order is
## known before the battle plays.
static func death_steps(replay: BattleReplay, key: String, start: int, size: int) -> Dictionary:
	var out := {}
	var up := size
	for idx in replay.steps.size():
		var st: Dictionary = replay.steps[idx]
		for role in ["actor", "target"]:
			if String(st.get(role, "")) != key or not st.has(role + "_count"):
				continue
			var want := BattleFigure.standing(int(st[role + "_count"]), start, size)
			while up > want:
				up -= 1
				out[up] = idx
			if want > up:
				for i in range(up, want):
					out.erase(i)
				up = want
	return out


## Where every standing figure of side `s`'s block stands, rows from the
## front edge _block_front[s] backwards, each row as wide as fits in the
## field's height without crowding: "stack#figure" -> field point.
func block_spots(s: int) -> Dictionary:
	var out := {}
	var toward := 1.0 if s == 0 else -1.0
	var top := _ground.position.y + 14.0
	var bottom := _ground.end.y - 6.0
	var span := (bottom - top) * BLOCK_FILL
	var mid := (top + bottom) * 0.5
	var rows: Array = []
	var row: Array = []
	var row_w := 0.0
	var standing := 0
	for e in _blocks[s]:
		var f: BattleFigure = _figs.get(e[0])
		if f != null and f.is_member_alive(int(e[1])):
			standing += 1
	# A square-ish block, a little wider than deep.
	var per_row := maxi(4, int(ceil(sqrt(float(standing) * BLOCK_ASPECT))))
	for e in _blocks[s]:
		var f: BattleFigure = _figs.get(e[0])
		var i := int(e[1])
		if f == null or not f.is_member_alive(i):
			continue
		var ext := f.member_extent(i)
		# Across the screen's depth figures overlap the ones behind them, so a
		# row gives each its full width there too.
		var w := 2.0 * maxf(ext.y, f.member_radius() * 0.6) * BLOCK_ROOM
		# Rows as deep as figures are wide (a square on screen); a long body
		# takes its length.
		var d := 2.0 * maxf(ext.x if ext.x > ext.y * BattleDirector.LONG else ext.y, f.member_radius() * 0.6) * BLOCK_ROOM
		if not row.is_empty() and (row_w + w > span or row.size() >= per_row):
			rows.append(row)
			row = []
			row_w = 0.0
		row.append([e[0], i, w, d])
		row_w += w
	if not row.is_empty():
		rows.append(row)
	for id in _block_edge.keys():
		if String(id).get_slice(":", 0) == str(s):
			_block_edge.erase(id)
	# Edge figures, the front first (a figure on two edges keeps the first).
	for ri in rows.size():
		var r: Array = rows[ri]
		for ci in r.size():
			var id := "%s#%d" % [r[ci][0], r[ci][1]]
			if ri == 0:
				_block_edge[id] = Vector2(toward, 0.0)
			elif ci == 0:
				_block_edge[id] = Vector2(0.0, -1.0)
			elif ci == r.size() - 1:
				_block_edge[id] = Vector2(0.0, 1.0)
			elif ri == rows.size() - 1:
				_block_edge[id] = Vector2(-toward, 0.0)
	var depth := 0.0
	for r in rows:
		var deep := 0.0
		var wide := 0.0
		for c in r:
			deep = maxf(deep, float(c[3]))
			wide += float(c[2])
		var x: float = _block_front[s] - toward * (depth + deep * 0.5)
		var y := mid - wide * 0.5
		for c in r:
			y += float(c[2]) * 0.5
			out["%s#%d" % [c[0], c[1]]] = Vector2(x, y)
			y += float(c[2]) * 0.5
		depth += deep
	return out


## Sends side `s`'s block figures to their places at `pace`, setting off
## after `wait` seconds (or puts them there at once).
func _block_place(s: int, pace: float, wait: float, snap: bool = false) -> void:
	var spots := block_spots(s)
	var toward := 1.0 if s == 0 else -1.0
	var n := 0
	for e in _blocks[s]:
		var f: BattleFigure = _figs.get(e[0])
		var i := int(e[1])
		var id := "%s#%d" % [e[0], i]
		if f == null or not spots.has(id):
			continue
		n += 1
		var to: Vector2 = spots[id]
		f.block_spots[i] = to
		if snap:
			f.place_member(i, to, toward)
		elif f.member_goal(i).distance_to(to) > 2.0:
			f.send(i, to, toward, wait + BattleFigure.jitter(f.key, i, 23) * 0.25, pace)
	_block_alive[s] = n


## Rows step up as figures fall: called every scan; re-places a block when
## its count of standing figures changed.
func _close_ranks() -> void:
	for s in 2:
		if _blocks[s].is_empty():
			continue
		var n := 0
		for e in _blocks[s]:
			var f: BattleFigure = _figs.get(e[0])
			if f != null and f.is_member_alive(int(e[1])):
				n += 1
		if n != _block_alive[s]:
			_block_place(s, 1.0, 0.0)


## Sends `f` towards x = `to` so it arrives as round `arrive` begins: a steady
## march, or a wait this round when even the slowest pace would be early.
func _march_to(f: BattleFigure, to: float, arrive: int, round_no: int, walk: float, stagger: float) -> void:
	var here := f.centroid(f.alive_members()).x
	var dist := absf(to - here)
	var plan := march_plan(dist, _seconds_until(arrive, round_no), walk)
	if absf(f.home.x - to) < 1.0 and not f.arrived(f.alive_members()):
		return   # already on its way (or waiting to set off): no stop-and-go
	f.home = Vector2(to, f.home.y)
	f.form_up(stagger, plan.x, plan.y)


func _has_living_foe(k: String) -> bool:
	for foe in _groups.get(k, {}):
		var g: BattleFigure = _figs.get(foe)
		if g != null and not g.is_dead():
			return true
	return false


## War drums every other round and, rarely, a horn from behind the lines.
func _round_sound(round_no: int) -> void:
	if round_no % 5 == 3:
		AudioManager.play("battle_horn")
	elif round_no % 2 == 1:
		AudioManager.play("battle_drums")


## A blow or a volley, at most one every FIGHT_SOUND_GAP seconds so a busy
## clash stays a murmur under the music.
func _fight_sound(event_id: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < int(FIGHT_SOUND_GAP * 1000.0):
		return
	_last_hit_ms = now
	AudioManager.play(event_id)


## Shows each side's battle orders over its army at the start.
func _announce_orders() -> void:
	for s in 2:
		var o: Dictionary = _orders[s]
		if o.is_empty() or BattleOrders.is_default(o):
			continue
		var at := _side_centre(s) + Vector2(0, 26)
		_pop(at, BattleOrders.describe(GameData.get_default(), o), UiStyle.BRASS, 360.0, 2.4)


# ---------------------------------------------------------------- rounds ---

## Plays the log round by round; inside a round every stack's blows run at
## the same time, each stack keeping its own order. Counts follow the log:
## a stack only shows a count from a later log entry than the one it shows.
func _play_rounds() -> void:
	var steps := _replay.steps
	var i := 0
	while i < steps.size() and not _skip:
		var st: Dictionary = steps[i]
		if st["kind"] == BattleReplay.ROUND:
			_round_label.text = st["text"]
			_march(int(st["round"]))
			await _wait(0.2)
			i += 1
			continue
		var batch := []
		while i < steps.size() and steps[i]["kind"] != BattleReplay.ROUND:
			batch.append(i)
			i += 1
		_plan_round(batch)
		await _clash_round(batch)
		await _wait(0.12)


## Who fights whom this round: every pair of stacks that trade melee blows.
## Each stack splits its standing figures into one group per enemy it fights,
## top to bottom, so groups pair off one to one with the enemy's groups.
func _plan_round(indices: Array) -> void:
	_round_meets.clear()
	var partners := {}
	for idx in indices:
		var st: Dictionary = _replay.steps[idx]
		if not (st["kind"] in [BattleReplay.MELEE, BattleReplay.ANSWER]):
			continue
		var a := String(st["actor"])
		var t := String(st["target"])
		if not _figs.has(a) or not _figs.has(t):
			continue
		for pair in [[a, t], [t, a]]:
			if not partners.has(pair[0]):
				partners[pair[0]] = []
			if not partners[pair[0]].has(pair[1]):
				partners[pair[0]].append(pair[1])
	for k in partners:
		var f: BattleFigure = _figs[k]
		var foes: Array = partners[k].duplicate()
		foes.sort_custom(func(x, y): return _figs[x].centroid(_figs[x].alive_members()).y < _figs[y].centroid(_figs[y].alive_members()).y)
		_groups[k] = split_evenly(_sorted_by_y(f, f.alive_members()), foes)


## Splits `ids` into one run per entry of `foes`, as even as it gets; when
## there are fewer figures than foes, figures fight more than one foe.
static func split_evenly(ids: Array, foes: Array) -> Dictionary:
	var out := {}
	var n := ids.size()
	var k := foes.size()
	for j in k:
		var part: Array = ids.slice(int(floor(float(j) * n / k)), int(floor(float(j + 1) * n / k)))
		if part.is_empty() and n > 0:
			part = [ids[mini(n - 1, int(float(j) * n / k))]]
		out[foes[j]] = part
	return out


func _sorted_by_y(f: BattleFigure, ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(x, y): return f.member_pos(x).y < f.member_pos(y).y)
	return out


## The figures of `f` that fight `foe`: its group for that foe while any of
## it stands, otherwise the standing figures nearest the foe.
func _group(f: BattleFigure, foe: BattleFigure) -> Array:
	if _block_of.has(f.key):
		# In a block: its figures nearest the enemy's line strike and take
		# the blows.
		var alive := f.alive_members()
		var toward := 1.0 if _side_of(f) == 0 else -1.0
		alive.sort_custom(func(x, y): return f.member_pos(x).x * toward > f.member_pos(y).x * toward)
		return alive.slice(0, clampi(alive.size() / 3, 1, 4))
	var ids := []
	for i in _groups.get(f.key, {}).get(foe.key, []):
		if f.is_member_alive(i):
			ids.append(i)
	if ids.is_empty():
		var alive := f.alive_members()
		if alive.is_empty():
			return []
		var near := foe.centroid(foe.alive_members())
		alive.sort_custom(func(x, y): return f.member_pos(x).distance_to(near) < f.member_pos(y).distance_to(near))
		var parts := maxi(1, _groups.get(f.key, {}).size())
		ids = alive.slice(0, maxi(1, alive.size() / parts))
		if not _groups.has(f.key):
			_groups[f.key] = {}
		_groups[f.key][foe.key] = ids
	return ids


## Splits a round into lanes: each striking stack opens or extends its lane;
## answers and follow-up effects ride in the lane of the blow before them.
func _clash_round(indices: Array) -> void:
	var lanes := {}
	var order := []
	var current := "_"
	for idx in indices:
		var st: Dictionary = _replay.steps[idx]
		if st["kind"] in [BattleReplay.MELEE, BattleReplay.SHOT]:
			current = String(st["actor"])
		if not lanes.has(current):
			lanes[current] = []
			order.append(current)
		lanes[current].append(idx)
	var running := [0]
	for n in order.size():
		running[0] += 1
		_run_lane(lanes[order[n]], lane_delay(n, order.size()), running)
	while running[0] > 0 and not _skip and is_inside_tree():
		await get_tree().process_frame


## When the n-th of `lanes` stacks starts its blows in a round: spread over
## the round (about a third of a second apart, closer when many act) so
## volleys and charges do not all go off in the same instant.
static func lane_delay(n: int, lanes: int) -> float:
	if lanes <= 1:
		return 0.0
	var step := clampf(2.4 / float(lanes - 1), 0.15, 0.34)
	return float(n) * step


func _run_lane(indices: Array, delay: float, running: Array) -> void:
	await _wait(delay)
	for idx in indices:
		if _skip:
			break
		await _clash_step(idx)
	running[0] -= 1


func _clash_step(idx: int) -> void:
	var st: Dictionary = _replay.steps[idx]
	var actor: BattleFigure = _figs.get(st["actor"])
	var target: BattleFigure = _figs.get(st["target"])
	match st["kind"]:
		BattleReplay.MELEE, BattleReplay.ANSWER:
			if actor == null or target == null or actor.is_dead():
				_land(idx, target, [], 0.0)
				return
			var a_ids := _group(actor, target)
			var t_ids := _group(target, actor)
			var crash := -1.0
			if st["kind"] == BattleReplay.MELEE or not _close_enough(actor, a_ids, target, t_ids):
				crash = await _engage(actor, a_ids, target, t_ids, st["type"] == "charge")
			await _melee_strike(idx, actor, a_ids, target, t_ids, crash)
		BattleReplay.SHOT:
			if actor == null or target == null or actor.is_dead():
				_land(idx, target, [], 0.0)
				return
			await _volley_strike(idx, actor, target)
		BattleReplay.EFFECT:
			await _effect(idx, actor, target)
		BattleReplay.NOTICE:
			if actor != null:
				_pop(actor.chest(), st["text"], UiStyle.BRASS)
			await _wait(0.2)


# ----------------------------------------------------------------- melee ---

func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func _close_enough(a: BattleFigure, a_ids: Array, t: BattleFigure, t_ids: Array) -> bool:
	if a_ids.is_empty() or t_ids.is_empty():
		return true
	var reach := (a.figure_width + t.figure_width) * 0.5 + 70.0
	return a.centroid(a_ids).distance_to(t.centroid(t_ids)) < reach


## Where a pair fights: where it fought last round if both are still near,
## otherwise just in front of the target, pushed clear of the other fights.
func _meet_point(a: BattleFigure, a_ids: Array, t: BattleFigure, t_ids: Array) -> Vector2:
	var pk := _pair_key(a.key, t.key)
	if _round_meets.has(pk):
		return _round_meets[pk]
	var ca := a.centroid(a_ids)
	var ct := t.centroid(t_ids)
	# Lines meet halfway; a held line or a ranged or support stack is met
	# where it stands.
	var at_target := 0.5
	var held := _held_side()
	if t.formation == "back" or t.formation == "support":
		at_target = 0.85
	elif held == _side_of(t):
		at_target = 0.9    # a held line is met where it stands
	elif held == _side_of(a):
		at_target = 0.1    # the holder strikes the attackers as they reach it
	elif String(_orders[_side_of(t)].get("stance", "balanced")) == "defensive":
		at_target = 0.68
	var m := ca.lerp(ct, at_target)
	if _meet.has(pk) and ct.distance_to(_meet[pk]) < 110.0 and ca.distance_to(_meet[pk]) < 110.0:
		m = _meet[pk]
	var push := 1.0 if posmod(hash(pk), 2) == 0 else -1.0
	for _try in 8:
		var clear := true
		for other in _round_meets.values():
			if m.distance_to(other) < FIGHT_ROOM:
				clear = false
				m.y += push * FIGHT_ROOM * 0.75
				if m.y > _ground.end.y or m.y < _ground.position.y:
					push = -push
					m.y = clampf(m.y, _ground.position.y, _ground.end.y)
				break
		if clear:
			break
	m.x = clampf(m.x, _ground.position.x, _ground.end.x)
	_meet[pk] = m
	_round_meets[pk] = m
	return m


## The attacking group runs at the meeting point (a charge at a sprint); the
## defenders step up to meet it. Returns just before the attackers get
## there, early enough that their blow lands as the lines meet (or after
## CHARGE_WAIT): how hard the lines crash together (0 a walk-up, up to 1 a
## heavy charge), or -1 when the groups were already in reach.
func _engage(a: BattleFigure, a_ids: Array, t: BattleFigure, t_ids: Array, charge: bool) -> float:
	if a_ids.is_empty() or t_ids.is_empty():
		return -1.0
	var m := _meet_point(a, a_ids, t, t_ids)
	var dir := signf(t.centroid(t_ids).x - a.centroid(a_ids).x)
	if dir == 0.0:
		dir = a.facing
	var gap := (a.figure_width + t.figure_width) * 0.3 + 10.0
	var spots_a := a.group_spots(a_ids.size(), m - Vector2(dir * gap, 0), dir)
	var spots_t := t.group_spots(t_ids.size(), m + Vector2(dir * gap, 0), -dir)
	var far := false
	for k in a_ids.size():
		var i: int = a_ids[k]
		if a.member_pos(i).distance_to(spots_a[k]) > 60.0:
			far = true
		if not _block_of.has(a.key):
			a.send(i, spots_a[k], dir, BattleFigure.jitter(a.key, i, 21) * (0.12 if charge else 0.3), CHARGE_RUSH if charge else 1.0)
	# A held line braces where it stands; otherwise the defenders step up.
	var bracing := _held_side() == _side_of(t) or _block_of.has(t.key)
	for k in t_ids.size():
		var i: int = t_ids[k]
		if bracing and t.member_pos(i).distance_to(spots_t[k]) < 90.0:
			t.aim_member(i, Vector2(-dir, 0.0))
			continue
		t.send(i, spots_t[k], -dir, 0.15 + BattleFigure.jitter(t.key, i, 22) * 0.35)
	_engaged[a.key] = true
	_engaged[t.key] = true
	if far:
		for i in a_ids.slice(0, 3):
			BattleGore.dust(_field, a.member_pos(i), dir, _speed)
		if charge:
			_fight_sound("battle_hit")
	var waited := 0.0
	# Strike on contact: the swing starts on the run, so the blow lands as
	# the attackers reach the line instead of after they stop.
	var lead := a.impact_seconds() + 0.04
	while not _block_of.has(a.key) and not a.arrived(a_ids) and a.eta(a_ids) > lead and waited < CHARGE_WAIT and not _skip and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time() * _speed * _slowmo
	a.set_brawling(a_ids, true)
	t.set_brawling(t_ids, true)
	_brawl_whole(a)
	_brawl_whole(t)
	if not far:
		return -1.0
	return clampf((0.5 if charge else 0.0) + _impact_weight(a) * 0.6, 0.0, 1.0)


## crash: how hard the lines just ran into each other (see _engage), or -1.
func _melee_strike(idx: int, a: BattleFigure, a_ids: Array, t: BattleFigure, t_ids: Array, crash: float = -1.0) -> void:
	var timing := a.start_attack(a_ids)
	await _wait(float(timing[0]) + 0.04)
	_fight_sound("battle_hit")
	var dir := signf(t.centroid(t_ids).x - a.centroid(a_ids).x)
	if dir == 0.0:
		dir = a.facing
	if crash >= 0.0 and not t_ids.is_empty():
		# The lines crash together: sparks between the fronts, the struck
		# rank thrown back a step, harder for a charge or a giant.
		var front := (a.centroid(a_ids) + t.centroid(t_ids)) * 0.5
		BattleGore.contact(_overlay, front + Vector2(0, -28), crash, _speed)
		t.shove(t_ids, dir * (7.0 + crash * 16.0))
		if crash >= 0.5:
			_shake(2.0 + crash * 3.0)
	t.hurt(t_ids)
	for i in t_ids.slice(0, 3):
		BattleGore.spurt(_overlay, t.member_chest(i), t.gore, dir, _speed)
	var heavy := _impact_weight(a)
	if a.element != "":
		BattleFx.burst(_overlay, t.centroid(t_ids) + Vector2(0, -30), a.element, 0.8 + heavy * 0.5, _speed)
		_linger(t.centroid(t_ids), a.element)
	if heavy > 0.0:
		_shake(3.0 + heavy * 5.0)
	_land(idx, t, t_ids, dir)
	await _wait(maxf(0.12, float(timing[1]) - float(timing[0])))


## 0 for ordinary blows, up to 1 for the biggest creatures and blasts.
func _impact_weight(actor: BattleFigure) -> float:
	var tier := int(GameData.get_default().creature(actor.creature_id).get("tier", 1))
	var w := clampf(float(tier - 5) / 3.0, 0.0, 1.0)
	if actor.element == "blast":
		w = maxf(w, 0.6)
	return w


# ---------------------------------------------------------------- ranged ---

## Every standing shooter looses at one enemy figure (six missiles at most),
## a moment apart; the figures that fall are the ones hit.
func _volley_strike(idx: int, a: BattleFigure, t: BattleFigure) -> void:
	var shooters := a.alive_members()
	var timing := a.start_attack(shooters)
	await _wait(float(timing[0]))
	_fight_sound("battle_shot")
	var marks := _sorted_by_y(t, t.alive_members())
	if marks.is_empty():
		_land(idx, t, [], 0.0)
		return
	var n := clampi(shooters.size(), 1, 6)
	var hit := []
	for k in n:
		var from := a.member_chest(shooters[k % shooters.size()]) if not shooters.is_empty() else a.chest()
		var mark: int = marks[(k * 5 + idx) % marks.size()]
		if not hit.has(mark):
			hit.append(mark)
		# A ragged volley: missiles leave a beat apart and each one lands
		# with its own small hit, so the sky stays busy for the whole volley.
		if k == n - 1:
			await _missile(from, t, mark, a.element)
		else:
			_missile(from, t, mark, a.element)
			await _wait(0.07 + BattleFigure.jitter(a.key, k, idx) * 0.08)
	var dir := signf(t.position.x - a.position.x)
	t.hurt(hit)
	for i in hit.slice(0, 3):
		BattleGore.spurt(_overlay, t.member_chest(i), t.gore, dir, _speed)
	var heavy := _impact_weight(a)
	if a.element != "":
		BattleFx.burst(_overlay, t.centroid(hit) + Vector2(0, -30), a.element, 0.8 + heavy * 0.5, _speed)
		_linger(t.centroid(hit), a.element)
	if heavy > 0.0:
		_shake(3.0 + heavy * 5.0)
	_land(idx, t, hit, dir)
	await _wait(maxf(0.12, float(timing[1]) - float(timing[0])))


## One missile of a volley at figure `mark` of `t`, with a small hit where
## it lands (the volley's last, big hit comes after).
func _missile(from: Vector2, t: BattleFigure, mark: int, element: String) -> void:
	var to := t.member_chest(mark)
	await _projectile(from, to, element)
	if _skip or not t.is_member_alive(mark):
		return
	var dir := signf(to.x - from.x)
	if element != "":
		BattleFx.burst(_overlay, to, element, 0.35, _speed)
	else:
		BattleGore.nick(_overlay, to, t.gore, dir, _speed)
	t.hurt([mark])


func _projectile(from: Vector2, to: Vector2, element: String = "") -> void:
	var bolt: Node2D
	if element != "":
		bolt = BattleFx.projectile(element, _speed)
	else:
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Color("#e8d8b0")
		var dir := (to - from).normalized()
		line.points = PackedVector2Array([-dir * 7.0, dir * 7.0])
		bolt = line
	_overlay.add_child(bolt)
	var arc := minf(70.0, from.distance_to(to) * 0.18)
	if element == "blast":
		arc = minf(140.0, from.distance_to(to) * 0.35)
	await _animate(0.32, func(p: float):
		if is_instance_valid(bolt):
			bolt.position = from.lerp(to, p) + Vector2(0, -sin(PI * p) * arc)
			if bolt is Line2D:
				# Arrows follow the arc.
				bolt.rotation = ((to - from) + Vector2(0, -cos(PI * p) * PI * arc)).angle() - (to - from).angle())
	if is_instance_valid(bolt):
		bolt.queue_free()


# --------------------------------------------------------------- effects ---

func _effect(idx: int, actor: BattleFigure, target: BattleFigure) -> void:
	var st: Dictionary = _replay.steps[idx]
	var over := target if target != null else actor
	if over == null or (over.is_dead() and not st["gain"]):
		_land(idx, target, [], 0.0)
		await _wait(0.2)
		return
	var type := String(st["type"])
	var ids := _sorted_by_y(over, over.alive_members())
	if actor != null and target != null and actor != target and _groups.get(target.key, {}).has(actor.key):
		ids = _group(target, actor)
	var fx := BattleFx.element_for_event(type, actor.creature_id if actor != null else "")
	if type == "drain" and actor != null and target != null:
		# Life flows from the drained to the drinker.
		for i in ids.slice(0, 3):
			_projectile(target.member_chest(i), actor.chest(), "blood")
		await _wait(0.3)
		BattleFx.burst(_overlay, actor.chest(), "blood", 0.7, _speed)
	elif type == "poison":
		for i in ids.slice(0, 4):
			BattleGore.poison_cloud(_overlay, over.member_chest(i), _speed)
	elif fx != "":
		BattleFx.burst(_overlay, over.centroid(ids) + Vector2(0, -30), fx, 0.8, _speed)
		_linger(over.centroid(ids), fx)
	if not st["gain"]:
		over.hurt(ids)
	var dir := signf(over.position.x - actor.position.x) if actor != null and actor != over else 0.0
	_land(idx, target, ids, dir)
	if type == "withdraw":
		_fall_back(over, idx)
	await _wait(0.3)


## Standing retreat order: the survivors leave the fight and fall back to
## their own edge of the field.
func _fall_back(f: BattleFigure, idx: int) -> void:
	if f.is_dead():
		return
	var side := int(String(f.key).get_slice(":", 0))
	_engaged.erase(f.key)
	_groups.erase(f.key)
	var edge := _ground.position.x + 24.0 if side == 0 else _ground.end.x - 24.0
	f.home = Vector2(edge, f.home.y)
	f.set_brawling(f.alive_members(), false)
	f.form_up(0.6)
	_pop(f.chest(), String(_replay.steps[idx]["text"]), UiStyle.BRASS)


# ---------------------------------------------------------------- counts ---

## Applies a log entry's counts. Figures of `fig` that fall are taken from
## `prefer` (the ones struck) and fall away from the blow (`dir`); each leaves
## its gore. Pops the damage over the struck group, and the losses when
## creatures died. Never shows an older log entry over a newer one.
func _land(idx: int, fig: BattleFigure, prefer: Array, dir: float) -> void:
	var st: Dictionary = _replay.steps[idx]
	for role in ["actor", "target"]:
		var key := String(st[role])
		var f: BattleFigure = _figs.get(key)
		if f == null or (role == "actor" and st["kind"] == BattleReplay.NOTICE):
			continue
		if int(_shown_at.get(key, -1)) > idx:
			continue
		_shown_at[key] = idx
		var before := f.count
		var n := int(st[role + "_count"])
		if n == before:
			continue
		# Block figures fall in the order their rows were built from.
		var fell := f.apply_count(n, prefer if f == fig and not _block_of.has(key) else [], dir if f == fig else 0.0, true)
		for i in fell:
			_death_mark(f, i, dir if f == fig else -f.facing)
		if n <= 0 and before > 0 and not _skip:
			_wiped_out(f)
		if f == fig and not st["gain"]:
			var at := f.centroid(prefer if not prefer.is_empty() else f.alive_members()) + Vector2(0, -f.figure_width * 0.9 - 20.0)
			# Losses say who lost creatures to whom; a blow that kills
			# nobody only shows its damage, small.
			if st["type"] == "charge":
				_pop(at + Vector2(0, -22), "Charge!", UiStyle.BRASS, 140.0, 0.9, 15)
			if before - n > 0:
				_pop(at, "-%d" % (before - n), UiStyle.BAD, 140.0, 1.1, 20)
			else:
				_pop(at, st["text"], UiStyle.BAD.lightened(0.35), 140.0, 0.7, 13)
		elif f == fig and st["gain"]:
			_pop(f.chest(), st["text"], UiStyle.GOOD)


## A figure going down: its gore bursts and pools where it falls.
func _death_mark(f: BattleFigure, i: int, dir: float) -> void:
	if _skip:
		return
	var d := dir if dir != 0.0 else -f.facing
	BattleGore.death_burst(_overlay, f.member_chest(i), f.gore, d, _speed)
	BattleGore.pool(_field, f.member_pos(i) + Vector2(d * 14.0, 2.0), f.gore, f.figure_width * 0.9, _speed)


## A battalion is gone: a beat of slow motion (longer for an army's last
## battalion) so the moment reads.
func _wiped_out(f: BattleFigure) -> void:
	var side := int(String(f.key).get_slice(":", 0))
	var last := true
	for st in _replay.stacks[side]:
		var g: BattleFigure = _figs.get(st["key"])
		if g != null and not g.is_dead():
			last = false
	# Whoever fought it stops swinging at the fallen.
	for k in _groups:
		var g: BattleFigure = _figs.get(k)
		if g != null and _groups[k].has(f.key):
			g.set_brawling(_groups[k][f.key], false)
	_slowmo_id += 1
	var id := _slowmo_id
	_slowmo = 0.3 if last else 0.55
	_set_figure_speed()
	var left := 1.0 if last else 0.35
	while left > 0.0 and is_inside_tree() and not _skip and id == _slowmo_id:
		await get_tree().process_frame
		left -= get_process_delta_time()
	if id == _slowmo_id:
		_slowmo = 1.0
		_set_figure_speed()


func _set_figure_speed() -> void:
	for g in _figs.values():
		g.set_speed(_speed * _slowmo)


## The end state, whether played through or skipped: counts as the result
## says, every figure on its place.
func _settle() -> void:
	var counts := _replay.final_counts()
	for k in _figs:
		var f: BattleFigure = _figs[k]
		var n := int(counts.get(k, f.count))
		if n != f.count:
			f.apply_count(n, [], 0.0, false)
		f.snap()


# ------------------------------------------------------------------ juice ---

## Embers, mist or motes left on the ground where an element struck, at most
## MAX_LINGER at once (the oldest burn out first).
func _linger(feet: Vector2, element: String) -> void:
	if _skip:
		return
	var alive := []
	for n in _lingering:
		if is_instance_valid(n):
			alive.append(n)
	_lingering = alive
	if _lingering.size() >= MAX_LINGER:
		var old: Node = _lingering.pop_front()
		if old is CPUParticles2D:
			old.emitting = false
	var p := BattleFx.linger(_overlay, feet + Vector2(0, -6), element, _speed)
	if p != null:
		_lingering.append(p)


## A swing between the logged blows landed: the foe it is locked with takes
## a nick (or a small burst of the striker's element) and gives a step. No
## counts change; at most one such effect every BRAWL_FX_GAP seconds.
func _on_brawl_hit(f: BattleFigure, i: int) -> void:
	if _skip or _clock < _brawl_fx_at or not f.is_member_alive(i):
		return
	var foe: BattleFigure = null
	var groups: Dictionary = _groups.get(f.key, {})
	for k in groups:
		if (groups[k] as Array).has(i):
			foe = _figs.get(k)
			break
	if foe == null or foe.is_dead():
		var near := _nearest_foe(f, i)
		if near.is_empty():
			return
		foe = near[0]
	var at := f.member_pos(i)
	var best := -1
	var best_d := INF
	for j in foe.alive_members():
		var d := foe.member_pos(j).distance_to(at)
		if d < best_d:
			best_d = d
			best = j
	if best < 0 or best_d > (f.figure_width + foe.figure_width) * 0.5 + 90.0:
		return
	_brawl_fx_at = _clock + BRAWL_FX_GAP
	var dir := signf(foe.member_pos(best).x - at.x)
	var chest := foe.member_chest(best)
	if f.element != "":
		BattleFx.burst(_overlay, chest, f.element, 0.4, _speed)
	else:
		BattleGore.nick(_overlay, chest, foe.gore, dir if dir != 0.0 else f.facing, _speed)
	foe.hurt([best])
	foe.shove([best], (dir if dir != 0.0 else f.facing) * 5.0)
	_fight_sound("battle_hit")


func _process(delta: float) -> void:
	if _replay == null or _skip:
		return
	_clock += delta * _speed * _slowmo
	_keep_room(delta * _speed * _slowmo)
	if _clock >= _scan_at:
		_scan_at = _clock + SCAN_GAP
		_close_ranks()
		if _stage != null or _directing:
			_director.step(_figs, _engaged, _groups, _held_side(), _block_of, _block_edge)
		_fight_in_reach()


## Every standing figure with a foe in arm's reach squares up to it and fights
## (a giant surrounded by three battalions swings at all of them, not only at
## the one the log pairs it with). Figures of a battalion out of the fight
## whose foes have gone stop.
func _fight_in_reach() -> void:
	for k in _figs:
		var f: BattleFigure = _figs[k]
		if f.is_dead():
			continue
		for i in f.alive_members():
			if f.is_moving(i) or _director.duels.has("%s#%d" % [k, i]):
				continue
			var near := _nearest_foe(f, i)
			if near.is_empty():
				if f.is_brawling(i) and not _engaged.has(k):
					f.set_brawling([i], false)
				continue
			var g: BattleFigure = near[0]
			var gap: Vector2 = g.member_pos(int(near[1])) - f.member_pos(i)
			if gap.length() > _reach(f, g):
				if f.is_brawling(i) and not _engaged.has(k):
					f.set_brawling([i], false)
				continue
			f.aim_member(i, gap)
			if not f.is_brawling(i):
				f.set_brawling([i], true)


## Arm's reach between figures of `f` and `g` (field pixels).
func _reach(f: BattleFigure, g: BattleFigure) -> float:
	return (f.figure_width + g.figure_width) * 0.5 + 40.0


## The nearest standing enemy figure to figure i of `f`: [figure, index,
## distance], or [] when the enemy has none.
func _nearest_foe(f: BattleFigure, i: int) -> Array:
	var side := _side_of(f)
	var at := f.member_pos(i)
	var best: Array = []
	var best_d := INF
	for k in _figs:
		var g: BattleFigure = _figs[k]
		if _side_of(g) == side or g.is_dead():
			continue
		for j in g.alive_members():
			var d := g.member_pos(j).distance_to(at)
			if d < best_d:
				best_d = d
				best = [g, j, d]
	return best


## Figures never stand inside each other: every pair of standing figures
## closer than their room (see ROOM_FRIEND, ROOM_FOE) is eased apart, both
## giving half. Foes keep arm's length, so lines meet face to face instead
## of melting into one another.
func _keep_room(dt: float) -> void:
	var pts := []
	var widest := 0.0
	for k in _figs:
		var f: BattleFigure = _figs[k]
		var side := int(String(k).get_slice(":", 0))
		for i in f.alive_members():
			# A long body (a wyrm) keeps room along its whole length: an
			# ellipse, stretched by `stretch` along x.
			var ext := f.member_extent(i)
			var stretch := 1.0
			var r := f.member_radius()
			if ext.x > ext.y * BattleDirector.LONG:
				r = maxf(r * 0.6, ext.y)
				stretch = ext.x / maxf(1.0, ext.y)
			pts.append([f.member_pos(i), f, i, r, side, stretch])
			widest = maxf(widest, r * stretch)
	pts.sort_custom(func(x, y): return x[0].x < y[0].x)
	var ease := minf(1.0, dt * 8.0)
	for a in pts.size():
		var pa: Array = pts[a]
		for b in range(a + 1, pts.size()):
			var pb: Array = pts[b]
			var gap: Vector2 = pb[0] - pa[0]
			if gap.x > (float(pa[3]) * float(pa[5]) + widest) * ROOM_FOE:
				break
			var stretch := maxf(float(pa[5]), float(pb[5]))
			var push := room_push(Vector2(gap.x / stretch, gap.y), float(pa[3]) + float(pb[3]), int(pa[4]) != int(pb[4]))
			if push == Vector2.ZERO:
				continue
			push.x *= stretch
			# A melee block holds its ranks: whoever crowds a block figure
			# gives all the room (two block figures already have theirs).
			var fixed_a := _block_of.has((pa[1] as BattleFigure).key)
			var fixed_b := _block_of.has((pb[1] as BattleFigure).key)
			if fixed_a and fixed_b:
				continue
			var share_a := 0.0 if fixed_a else (1.0 if fixed_b else 0.5)
			var share_b := 1.0 - share_a
			(pa[1] as BattleFigure).nudge(int(pa[2]), -push * share_a * ease)
			(pb[1] as BattleFigure).nudge(int(pb[2]), push * share_b * ease)
			pa[0] = pa[0] - push * share_a * ease
			pb[0] = pb[0] + push * share_b * ease


## How far two figures `gap` apart (b minus a, field pixels) with summed
## radii `radii` must move apart (b moves along the result, a against it);
## zero when they have room.
static func room_push(gap: Vector2, radii: float, foes: bool) -> Vector2:
	var room := radii * (ROOM_FOE if foes else ROOM_FRIEND)
	var d := Vector2(gap.x, gap.y * ROOM_DEPTH)
	var dist := d.length()
	if dist >= room:
		return Vector2.ZERO
	if dist < 0.01:
		return Vector2(0.0, room / ROOM_DEPTH)
	var dir := d / dist
	var over := room - dist
	return Vector2(dir.x * over, dir.y * over / ROOM_DEPTH)

## Shakes the battlefield for a heavy blow; runs alongside the playback.
func _shake(px: float) -> void:
	var t := 0.0
	while t < 0.22 and is_inside_tree() and not _skip:
		var k := 1.0 - t / 0.22
		_field.position = Vector2(sin(t * 90.0) * px * k, cos(t * 70.0) * px * 0.5 * k)
		if _stage != null:
			_stage.camera.h_offset = -_field.position.x * 0.012
			_stage.camera.v_offset = _field.position.y * 0.012
		await get_tree().process_frame
		t += get_process_delta_time() * _speed
	_field.position = Vector2.ZERO
	if _stage != null:
		_stage.camera.h_offset = 0.0
		_stage.camera.v_offset = 0.0


## A number or word that rises and fades; runs alongside the playback.
func _pop(at: Vector2, text: String, color: Color, width: float = 140.0, seconds: float = 0.8, font_size: int = 18) -> void:
	var l := UiStyle.label(text, font_size, color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(width, 24)
	_overlay.add_child(l)
	var start := at + Vector2(-width * 0.5, -10)
	await _animate(seconds, func(p: float):
		if is_instance_valid(l):
			l.position = start + Vector2(0, -30.0 * p)
			l.modulate.a = 1.0 - maxf(0.0, p - 0.6) / 0.4)
	if is_instance_valid(l):
		l.queue_free()


func _side_of(f: BattleFigure) -> int:
	return int(String(f.key).get_slice(":", 0))


## A small stack (a giant or a handful of big beasts) fights with every
## figure it has once it is in a melee, not just the ones paired off.
func _brawl_whole(f: BattleFigure) -> void:
	var alive := f.alive_members()
	if alive.size() <= 3:
		f.set_brawling(alive, true)


func _side_centre(side: int) -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x * (0.3 if side == 0 else 0.7), vp.y * HORIZON + 60.0)


# ------------------------------------------------------------------ time ---

## Waits `seconds` of battle time (scaled by the speed); returns at once when
## the player skips.
func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _skip and is_inside_tree():
		await get_tree().process_frame
		left -= get_process_delta_time() * _speed * _slowmo


## Calls `step` with progress 0..1 over `seconds` of battle time; ends on 1.
func _animate(seconds: float, step: Callable) -> void:
	var t := 0.0
	while t < seconds and not _skip and is_inside_tree():
		step.call(t / seconds)
		await get_tree().process_frame
		t += get_process_delta_time() * _speed * _slowmo
	step.call(1.0)
