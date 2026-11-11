class_name HeroModifiers
extends RefCounted
## The single modifier interface between hero progression and the game systems.
##
## Skills (per level), class traits, personal specialties and worn artifacts all describe their effect
## as a "mods" dictionary using the keys below. Hero.modifiers() sums them; the
## consumers read only the summed dictionary:
##   combat    HeroBattleEffects (via Hero.combat_profile()["mods"])
##   movement  Hero.max_movement(), Hero.move_cost_mods() -> Pathfinder.step_costs()
##   vision    Hero.vision_radius(), GameSession.scout_cost() (scout_cost_pct)
##   economy   GameSession daily income and recruitment
##   progress  Hero.add_xp() (xp_pct), GameSession.attack() (recover, spoils)
## Adding a key means: add it here with a kind, implement it in a consumer, test it.

## key -> kind. int/num/pct/flag values add up; *_map values add per key.
const KEYS := {
	# primaries (folded into the hero's attributes)
	"attack": "int", "defense": "int", "power": "int", "knowledge": "int",
	# combat
	"morale": "int", "enemy_morale": "int", "morale_floor": "flag", "initiative": "int",
	"combined_arms_roles": "int", "ranged_damage_pct": "pct", "melee_damage_pct": "pct",
	"shot_resist_pct": "pct", "screen": "pct", "role_attack": "role_map", "role_defense": "role_map",
	"creature_attack": "creature_map", "creature_defense": "creature_map",
	"faction_attack": "int", "faction_defense": "int", "ignore_hostile_terrain": "flag", "native_bonus": "int",
	"art_power_pct": "pct", "art_uses": "int",
	# after battle
	"recover_pct": "pct", "spoils_pct": "num",
	# travel
	"movement_pct": "pct", "rough_ground_pct": "pct", "terrain_move_pct": "terrain_map", "vision": "int",
	"scout_cost_pct": "pct",
	# economy and progress
	"income": "resource_map", "recruit_discount_pct": "pct", "xp_pct": "pct", "veteran_xp_pct": "pct",
}

## Upper bounds for summed values, so stacking sources never breaks a system.
const CAPS := {
	"rough_ground_pct": 0.9, "shot_resist_pct": 0.5, "recruit_discount_pct": 0.3, "recover_pct": 0.6,
	"xp_pct": 0.5, "veteran_xp_pct": 0.3, "screen": 0.6, "art_power_pct": 2.0, "scout_cost_pct": 1.0,
}

const ROLES := ["infantry", "ranged", "cavalry", "flyer", "support", "heavy"]


## Adds `mods` (scaled by `times`) into `into`. Integer kinds stay integers
## (scaled values are floored), so per-level traits should use pct/num keys.
static func combine(into: Dictionary, mods: Dictionary, times: float = 1.0) -> void:
	for k in mods:
		var kind: String = KEYS.get(k, "")
		if kind.ends_with("_map"):
			var sub: Dictionary = into.get(k, {})
			for sk in mods[k]:
				sub[sk] = _scaled(float(sub.get(sk, 0)) + float(mods[k][sk]) * times, kind)
			into[k] = sub
		elif kind == "int" or kind == "flag":
			into[k] = int(into.get(k, 0)) + int(floor(float(mods[k]) * times))
		elif kind != "":
			into[k] = float(into.get(k, 0.0)) + float(mods[k]) * times


static func _scaled(v: float, kind: String) -> Variant:
	return int(round(v)) if kind in ["role_map", "resource_map", "creature_map"] else v


## Applies CAPS in place and returns the dictionary.
static func clamp_all(mods: Dictionary) -> Dictionary:
	for k in CAPS:
		if mods.has(k):
			mods[k] = minf(float(mods[k]), float(CAPS[k]))
	if mods.has("terrain_move_pct"):
		for t in mods["terrain_move_pct"]:
			mods["terrain_move_pct"][t] = minf(float(mods["terrain_move_pct"][t]), float(CAPS["rough_ground_pct"]))
	return mods


## The mods of one skill at a level (0 = not learned).
static func skill_mods(skill_id: String, level: int, data: GameData) -> Dictionary:
	if level <= 0 or not data.skills.has(skill_id):
		return {}
	var levels: Array = data.skills[skill_id]["levels"]
	return levels[mini(level, levels.size()) - 1].get("mods", {})


## Summed mods of a skills dictionary {id: level}; used for battle setups that
## carry only skills (e.g. hand-written test or scenario heroes).
static func from_skills(skills: Dictionary, data: GameData) -> Dictionary:
	var out := {}
	var ids := skills.keys()
	ids.sort()
	for sk in ids:
		combine(out, skill_mods(sk, int(skills[sk]), data))
	return clamp_all(out)


static func num(mods: Dictionary, key: String) -> float:
	return float(mods.get(key, 0.0))


static func whole(mods: Dictionary, key: String) -> int:
	return int(mods.get(key, 0))


static func sub(mods: Dictionary, key: String, sub_key: String) -> float:
	return float(mods.get(key, {}).get(sub_key, 0.0))


## Validation of a mods dictionary from data. Returns problems.
static func validate(mods: Variant, where: String, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	if typeof(mods) != TYPE_DICTIONARY:
		errors.append("%s mods must be a dictionary" % where)
		return errors
	for k in mods:
		if not KEYS.has(k):
			errors.append("%s has unknown modifier %s" % [where, k])
			continue
		var kind: String = KEYS[k]
		var v: Variant = mods[k]
		if kind.ends_with("_map"):
			if typeof(v) != TYPE_DICTIONARY or v.is_empty():
				errors.append("%s modifier %s must be a non-empty dictionary" % [where, k])
				continue
			for sk in v:
				var ok := true
				match kind:
					"role_map": ok = ROLES.has(sk)
					"terrain_map": ok = data.terrains.has(sk)
					"resource_map": ok = data.resources.has(sk)
					"creature_map": ok = data.creatures.has(sk)
				if not ok:
					errors.append("%s modifier %s has unknown key %s" % [where, k, sk])
				if typeof(v[sk]) not in [TYPE_INT, TYPE_FLOAT]:
					errors.append("%s modifier %s.%s must be a number" % [where, k, sk])
		elif typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("%s modifier %s must be a number" % [where, k])
		elif kind == "pct" and (float(v) < -1.0 or float(v) > 1.0):
			errors.append("%s modifier %s must be within [-1, 1]" % [where, k])
	return errors
