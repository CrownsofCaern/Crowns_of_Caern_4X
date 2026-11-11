class_name CreatureAnims
extends RefCounted
## Battle animations use the generated atlas manifest through UnitAnimation.
## Individually authored strips override manifest clips and load straight from
##   res://assets/animations/<creature_id>/<creature_id>_<kind>.png
## Each file is one horizontal strip of square frames (128x128, facing right,
## feet at the bottom centre like the still sprite). The frame count is the
## width divided by the height. A creature without a strip falls back to its
## still sprite with simple placeholder motion (see BattleFigure).

const DIR := "res://assets/animations"
const KINDS := ["move", "attack"]
const FRAME := 128
const FPS := 10.0

static var _cache: Dictionary = {}
static var _manifest_used: Dictionary = {}


static func path(creature_id: String, kind: String) -> String:
	return "%s/%s/%s_%s.png" % [DIR, creature_id, creature_id, kind]


## The frames of one animation, or [] when the creature has none.
static func frames(creature_id: String, kind: String, level: int = 1) -> Array:
	if level >= 5:
		var veteran := VeteranVisual.frames(creature_id, kind)
		if not veteran.is_empty():
			return veteran
	var p := path(creature_id, kind)
	if not _cache.has(p):
		var tex := _load_strip(p)
		if tex != null:
			_cache[p] = split(tex)
			_manifest_used[p] = false
		else:
			_cache[p] = UnitAnimation.frames("creature_" + creature_id, kind)
			_manifest_used[p] = not _cache[p].is_empty()
	return _cache[p]


static func has(creature_id: String, kind: String) -> bool:
	return not frames(creature_id, kind).is_empty()


## Cuts a strip into square frames (side = strip height).
static func split(strip: Texture2D) -> Array:
	var out := []
	var h := strip.get_height()
	if h <= 0:
		return out
	for i in strip.get_width() / h:
		var at := AtlasTexture.new()
		at.atlas = strip
		at.region = Rect2(i * h, 0, h, h)
		out.append(at)
	return out


## Imported textures load normally; a strip dropped in without a Godot import
## (running straight from a fresh checkout) is read from the PNG bytes.
static func _load_strip(p: String) -> Texture2D:
	if ResourceLoader.exists(p):
		var res := load(p)
		if res is Texture2D:
			return res
	if not FileAccess.file_exists(p):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) != OK:
		return null
	return ImageTexture.create_from_image(img)


## Problems with the files under DIR (unknown creature, wrong name or size);
## empty when every strip can be used. `known` maps creature ids to anything.
static func audit(known: Dictionary, dir: String = DIR) -> Array:
	var problems := []
	var root := DirAccess.open(dir)
	if root == null:
		return problems
	for id in root.get_directories():
		if not known.has(id):
			problems.append("%s: no creature with this id" % id)
			continue
		var sub := DirAccess.open(dir.path_join(id))
		for f in sub.get_files():
			if f.ends_with(".import") or f.ends_with(".md"):
				continue
			var ok_name := false
			for k in KINDS:
				if f == "%s_%s.png" % [id, k]:
					ok_name = true
			if not ok_name:
				problems.append("%s/%s: expected %s_move.png or %s_attack.png" % [id, f, id, id])
				continue
			var img := Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(dir.path_join(id).path_join(f))) != OK:
				problems.append("%s/%s: not a readable PNG" % [id, f])
				continue
			if img.get_height() != FRAME or img.get_width() % FRAME != 0:
				problems.append("%s/%s: %dx%d, expected a strip of %dx%d frames" % [id, f, img.get_width(), img.get_height(), FRAME, FRAME])
	if dir == DIR:
		# Optional art packs can be audited before gameplay activation. Accept
		# only explicitly declared IDs that also have a built still sprite.
		var optional: Array = UnitAnimation.manifest().get("optional_creatures", [])
		for sid in UnitAnimation.manifest().get("units", {}):
			var cid := String(sid).trim_prefix("creature_")
			var declared_art := cid in optional and Art.has_sprite(sid)
			if String(sid).begins_with("creature_") and not known.has(cid) and not declared_art:
				problems.append("%s: no creature with this id" % sid)
	return problems


## Native atlas frames reserve extra transparent room for weapons and wings.
## Legacy 128px strips retain their original anchor and timing.
static func anchor(creature_id: String, kind: String, level: int = 1) -> Vector2:
	if level >= 5 and not VeteranVisual.frames(creature_id, kind).is_empty():
		return Vector2(160, 207)
	frames(creature_id, kind)
	if _manifest_used.get(path(creature_id, kind), false):
		var at: Array = UnitAnimation.manifest()["anchor"]
		return Vector2(at[0], at[1])
	return Vector2(FRAME * 0.5, FRAME - 1)


static func durations_ms(creature_id: String, kind: String, level: int = 1) -> Array:
	if level >= 5 and not VeteranVisual.frames(creature_id, kind).is_empty():
		return VeteranVisual.unit(creature_id)["actions"][kind]["durations_ms"]
	var poses := frames(creature_id, kind)
	if _manifest_used.get(path(creature_id, kind), false):
		return UnitAnimation.clip("creature_" + creature_id, kind)["durations_ms"]
	var durations := []
	for pose in poses:
		durations.append(1000.0 / FPS)
	return durations


static func attack_timing(creature_id: String, level: int = 1) -> Array:
	if level >= 5 and not VeteranVisual.frames(creature_id, "attack").is_empty():
		return [0.18, 0.6]
	var poses := frames(creature_id, "attack")
	if _manifest_used.get(path(creature_id, "attack"), false):
		var animation := UnitAnimation.clip("creature_" + creature_id, "attack")
		var total := 0.0
		for duration in animation["durations_ms"]:
			total += float(duration) / 1000.0
		var impact := 0.0
		for event in animation.get("events", []):
			if event["name"] == "impact":
				impact = float(event["time_ms"]) / 1000.0
		return [impact, total]
	return [maxf(0.0, poses.size() - 2) / FPS, poses.size() / FPS]
