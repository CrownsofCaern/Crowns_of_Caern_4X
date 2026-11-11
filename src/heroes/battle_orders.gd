class_name BattleOrders
extends RefCounted
## A hero's battle orders, all given before the fight (data/tactics.json):
##   stance     how the army fights (balanced, hold the line, all-out attack)
##   focus      what it goes for (free fighting, hunt the archers, ...)
##   formation  how it deploys (battle line, shield wall, wedge, skirmish
##              screen, crescent, held reserve)
##   art        when the hero looses the battle art (at once, when the lines
##              meet, when the line bends)
##   retreat    the standing retreat order (fight to the last, fall back at
##              half strength, fall back when broken)
## Options open with hero level (the Tactics skill lowers the level needed).
## A formation or art timing may also name a skill that lowers its level, and a
## formation lists hero classes that know it by heart (open from level 1 and
## drilled: its benefits grow). A hero specialty can unlock and drill a
## formation too ({"formations": {id: {"unlock": true, "bonus_pct": x}}}).
## CombatSimulator reads only the summed effects; the defaults have none, so a
## battle under default orders is the plain combat model.

const STANCE := "stance"
const FOCUS := "focus"
const FORMATION := "formation"
const ART := "art"
const RETREAT := "retreat"
const KINDS := [STANCE, FOCUS, FORMATION, ART, RETREAT]
const DEFAULT := {"stance": "balanced", "focus": "any", "formation": "line", "art": "at_once", "retreat": "never"}
## Where each kind's options live in data/tactics.json.
const TABLES := {"stance": "stances", "focus": "focus", "formation": "formations", "art": "art_timing", "retreat": "retreat"}

## Effect keys and their allowed range (validated in GameData).
const EFFECT_RANGES := {
	"attack": [-5, 5], "initiative": [-5, 5], "front_defense": [-5, 5], "advance": [-2, 2],
	"screen": [-1.0, 1.0], "bypass": [-1.0, 1.0], "back_target_weight": [0.0, 10.0],
	"guard_weight": [0.0, 10.0], "strongest_weight": [0.0, 10.0], "weakest_weight": [0.0, 10.0],
	"charge_pct": [0.0, 1.0], "shot_cover": [0.0, 0.6], "volley_pct": [0.0, 1.0], "enemy_delay": [0, 2],
	"flank_pct": [0.0, 1.0], "reserve_round": [0, 6], "reserve_attack": [0, 5], "reserve_morale": [0, 3],
	"art_round": [0, 5], "art_loss": [0.0, 0.9], "art_power": [0.0, 1.0],
	"withdraw_at": [0.0, 0.9], "rear_guard": [0.0, 0.9],
}
## Effects that are timings or thresholds: drill never scales them.
const UNSCALED := ["advance", "enemy_delay", "reserve_round", "art_round", "art_loss", "withdraw_at", "rear_guard"]
## Most a drilled effect may reach (drill never pushes past these).
const DRILL_CAPS := {"shot_cover": 0.6, "screen": 0.6}


## The table for a kind, e.g. data.tactics["formations"].
static func table(data: GameData, kind: String) -> Dictionary:
	return data.tactics.get(TABLES.get(kind, ""), {})


## Option ids of a kind, in data order.
static func ids(data: GameData, kind: String) -> Array:
	return table(data, kind).keys()


## What the gates need to know about a hero: {level, class, skills, specialty}.
## Built by Hero.commander(); hand-written battle heroes may leave parts out.
static func commander(level: int, class_id: String = "", skills: Dictionary = {}, specialty: Dictionary = {}) -> Dictionary:
	return {"level": level, "class": class_id, "skills": skills, "specialty": specialty}


## The specialty's word on a formation ({unlock, bonus_pct}) or {}.
static func _specialty_entry(cmd: Dictionary, id: String) -> Dictionary:
	var sp: Variant = cmd.get("specialty", {})
	if typeof(sp) != TYPE_DICTIONARY:
		return {}
	var forms: Variant = sp.get("formations", {})
	if typeof(forms) != TYPE_DICTIONARY or typeof(forms.get(id)) != TYPE_DICTIONARY:
		return {}
	return forms[id]


## True if the hero's class (or specialty) knows this option by heart.
static func knows_by_heart(data: GameData, kind: String, id: String, cmd: Dictionary) -> bool:
	var opt: Dictionary = table(data, kind).get(id, {})
	if opt.is_empty():
		return false
	if String(cmd.get("class", "")) != "" and (opt.get("classes", []) as Array).has(String(cmd["class"])):
		return true
	return kind == FORMATION and bool(_specialty_entry(cmd, id).get("unlock", false))


## The hero level an option needs, after the Tactics skill discount (and the
## option's own skill, read from cmd["skills"]). Known by heart: level 1.
static func level_needed(data: GameData, kind: String, id: String, tactics_level: int, cmd: Dictionary = {}) -> int:
	var opt: Dictionary = table(data, kind).get(id, {})
	if opt.is_empty():
		return 999
	if knows_by_heart(data, kind, id, cmd):
		return 1
	var disc := int(data.tactics.get("tactics_skill_discount", 0))
	var own := 0
	if opt.has("skill"):
		own = int(cmd.get("skills", {}).get(String(opt["skill"]), 0))
		if String(opt["skill"]) == "tactics":
			own = 0   # already counted
	return maxi(1, int(opt["min_level"]) - (tactics_level + own) * disc)


static func is_open(data: GameData, kind: String, id: String, hero_level: int, tactics_level: int, cmd: Dictionary = {}) -> bool:
	return table(data, kind).has(id) and hero_level >= level_needed(data, kind, id, tactics_level, cmd)


## How much stronger a formation's benefits are for this hero (0 = plain):
## its class knows it, each level of its skill, and the specialty's bonus_pct.
static func drill_pct(data: GameData, id: String, cmd: Dictionary) -> float:
	var opt: Dictionary = table(data, FORMATION).get(id, {})
	if opt.is_empty() or (opt.get("effects", {}) as Dictionary).is_empty():
		return 0.0
	var cfg: Dictionary = data.tactics.get("formation_drill", {})
	var pct := 0.0
	if String(cmd.get("class", "")) != "" and (opt.get("classes", []) as Array).has(String(cmd["class"])):
		pct += float(cfg.get("class_pct", 0.0))
	if opt.has("skill"):
		pct += float(cfg.get("per_skill_level_pct", 0.0)) * int(cmd.get("skills", {}).get(String(opt["skill"]), 0))
	pct += float(_specialty_entry(cmd, id).get("bonus_pct", 0.0))
	return clampf(pct, 0.0, float(cfg.get("max_pct", 1.0)))


## Orders a hero of this level can actually give: unknown or locked choices
## fall back to the defaults. A formation's drill comes along as "drill".
static func sanitized(data: GameData, orders: Dictionary, hero_level: int, tactics_level: int, cmd: Dictionary = {}) -> Dictionary:
	var out := DEFAULT.duplicate()
	for kind in KINDS:
		var id := String(orders.get(kind, DEFAULT[kind]))
		if is_open(data, kind, id, hero_level, tactics_level, cmd):
			out[kind] = id
	var drill := drill_pct(data, String(out[FORMATION]), cmd)
	if drill > 0.0:
		out["drill"] = drill
	return out


## Summed effects of all orders. A formation's positive effects grow with
## orders["drill"] (UNSCALED timings and thresholds stay as they are).
static func effects(data: GameData, orders: Dictionary) -> Dictionary:
	var out := {}
	var drill := float(orders.get("drill", 0.0))
	for kind in KINDS:
		var opt: Dictionary = table(data, kind).get(String(orders.get(kind, DEFAULT[kind])), {})
		var fx: Dictionary = opt.get("effects", {})
		for k in fx:
			var v: Variant = fx[k]
			if kind == FORMATION and drill > 0.0 and float(v) > 0.0 and not UNSCALED.has(k):
				v = float(v) * (1.0 + drill)
				if typeof(fx[k]) == TYPE_INT:
					v = int(round(v))
				if DRILL_CAPS.has(k):
					v = minf(float(v), float(DRILL_CAPS[k]))
			out[k] = out.get(k, 0) + v
	return out


static func is_default(orders: Dictionary) -> bool:
	for kind in KINDS:
		if String(orders.get(kind, DEFAULT[kind])) != DEFAULT[kind]:
			return false
	return true


## The display name of one order ("Shield wall").
static func option_name(data: GameData, kind: String, id: String) -> String:
	return String(table(data, kind).get(id, {}).get("name", "?"))


## "Hold the line, Guard the archers" plus any formation, art timing and
## retreat order that differ from the defaults.
static func describe(data: GameData, orders: Dictionary) -> String:
	var parts := []
	for kind in KINDS:
		var id := String(orders.get(kind, DEFAULT[kind]))
		if kind in [STANCE, FOCUS] or id != DEFAULT[kind]:
			var label := option_name(data, kind, id)
			if kind == FORMATION and float(orders.get("drill", 0.0)) > 0.0:
				label += " (drilled +%d%%)" % int(round(float(orders["drill"]) * 100.0))
			elif kind == ART:
				label = "art " + label.to_lower()
			parts.append(label)
	return ", ".join(parts)


## Orders a computer player gives, from the shape of both armies (stacks of
## {creature, count}; enemy may be empty when the foe is unknown). Only open
## options are picked. Deterministic. cmd: commander() of the hero (class,
## skills, specialty), so a hero leans to the formation it is drilled in.
static func choose(data: GameData, hero_level: int, tactics_level: int, own: Array, enemy: Array, cmd: Dictionary = {}) -> Dictionary:
	var mine := _role_shares(data, own)
	var theirs := _role_shares(data, enemy)
	var mine_back: float = mine.get("ranged", 0.0) + mine.get("support", 0.0)
	var their_back: float = theirs.get("ranged", 0.0) + theirs.get("support", 0.0)
	var mine_flank: float = mine.get("cavalry", 0.0) + mine.get("flyer", 0.0)
	var their_flank: float = theirs.get("cavalry", 0.0) + theirs.get("flyer", 0.0)
	var stance := "balanced"
	if mine_back >= 0.35 and their_back < 0.25:
		stance = "defensive"
	elif their_back >= 0.3 and mine_back < 0.25:
		stance = "aggressive"
	var focus := "any"
	var wishes := []
	if their_back >= 0.25 and mine_flank >= 0.15:
		wishes.append("hunt_archers")
	if mine_back >= 0.3 and (their_flank >= 0.15 or enemy.is_empty()):
		wishes.append("protect_archers")
	wishes.append("wounded")
	for w in wishes:
		if is_open(data, FOCUS, w, hero_level, tactics_level, cmd):
			focus = w
			break
	if not is_open(data, STANCE, stance, hero_level, tactics_level, cmd):
		stance = "balanced"
	var formation := choose_formation(data, hero_level, tactics_level, own, enemy, cmd)
	# A wall or a reserve pairs badly with an all-out charge; a wedge with holding back.
	if formation in ["shield_wall", "skirmish_screen"] and stance == "aggressive":
		stance = "balanced"
	if formation == "wedge" and stance == "defensive":
		stance = "balanced"
	# The AI looses its art at once: most of its fights (neutral packs) end in
	# a round or two, before a prepared art would fire (measured with
	# tools/formation_probe.gd: holding the art cost the hard AI its lead).
	return {"stance": stance, "focus": focus, "formation": formation, "art": "at_once", "retreat": "never"}


## Fit of each formation to the two armies (higher is better), for the AI and
## for the forecast's hint. Deterministic.
static func formation_scores(data: GameData, own: Array, enemy: Array) -> Dictionary:
	var mine := _role_shares(data, own)
	var theirs := _role_shares(data, enemy)
	var mine_back: float = mine.get("ranged", 0.0) + mine.get("support", 0.0)
	var their_back: float = theirs.get("ranged", 0.0) + theirs.get("support", 0.0)
	var mine_flank: float = mine.get("cavalry", 0.0) + mine.get("flyer", 0.0)
	var their_flank: float = theirs.get("cavalry", 0.0) + theirs.get("flyer", 0.0)
	var mine_front: float = mine.get("infantry", 0.0) + mine.get("heavy", 0.0)
	var their_front: float = theirs.get("infantry", 0.0) + theirs.get("heavy", 0.0)
	var melee_stacks := 0
	for st in own:
		var role := String(data.creature(String(st["creature"]))["role"])
		if role in ["infantry", "heavy", "cavalry", "flyer"]:
			melee_stacks += 1
	return {
		"line": 0.15,
		"shield_wall": mine_back * 0.6 + mine_front * 0.3 + their_back * 0.3 + their_flank * 0.2 - mine_flank * 0.4,
		"wedge": mine_front * 0.3 + mine_flank * 0.3 + their_back * 0.4 - mine_back * 0.6,
		"skirmish_screen": mine_back * 0.9 - their_flank * 0.5 - their_back * 0.6,
		# Crescent and reserve rarely beat the line in measured fights
		# (tools/formation_probe.gd), so they need a matching army: the
		# crescent many riders, the reserve a foe without archers.
		"crescent": mine_flank * 0.5 - their_flank * 0.3 - mine_back * 0.3,
		"reserve": (0.2 if melee_stacks >= 3 else -1.0) + their_front * 0.1 - their_back * 0.6,
	}


## The formation the AI deploys in: the best fitting open one, with a bonus
## for the formations this hero is drilled in.
static func choose_formation(data: GameData, hero_level: int, tactics_level: int, own: Array, enemy: Array, cmd: Dictionary = {}) -> String:
	if own.is_empty():
		return "line"
	var scores := formation_scores(data, own, enemy)
	var best := "line"
	var best_score := -INF
	for id in ids(data, FORMATION):
		if not is_open(data, FORMATION, id, hero_level, tactics_level, cmd):
			continue
		var sc := float(scores.get(id, 0.0)) + drill_pct(data, id, cmd) * 0.3
		if sc > best_score:
			best = id
			best_score = sc
	return best


## Share of hit points by role.
static func _role_shares(data: GameData, stacks: Array) -> Dictionary:
	var hp := {}
	var total := 0.0
	for st in stacks:
		var c := data.creature(String(st["creature"]))
		var v := float(int(c["hp"]) * int(st["count"]))
		hp[c["role"]] = hp.get(c["role"], 0.0) + v
		total += v
	if total > 0.0:
		for r in hp:
			hp[r] = hp[r] / total
	return hp
