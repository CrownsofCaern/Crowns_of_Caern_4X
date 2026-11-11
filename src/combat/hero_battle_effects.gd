class_name HeroBattleEffects
extends RefCounted
## How a hero shapes a battle. The simulator calls these helpers so that every
## hero rule lives in one place and works the same for real battles, forecasts,
## balance tools and a future tactical mode.
##
## A side's hero is a plain dictionary (Hero.combat_profile() or a hand-written
## {name, attack, defense, power, skills}); "mods" are HeroModifiers keys. A
## hero without "mods" gets them from its skills. The town walls "hero" has
## neither and only adds defense.
##
## Battle arts are deterministic (no random draws), so they never shift the
## battle's random stream: the same seed without a hero plays out identically.


static func mods_of(hero: Variant, data: GameData) -> Dictionary:
	if hero == null:
		return {}
	if hero.has("mods"):
		return hero["mods"]
	return HeroModifiers.from_skills(hero.get("skills", {}), data)


## Attack and defense a hero adds to one creature stack of its army.
## `creature_id` enables creature-line bonuses (specialties): a bonus keyed by
## a base creature also applies to its upgrade.
static func stat_bonus(hero: Variant, mods: Dictionary, creature: Dictionary, creature_id: String = "") -> Dictionary:
	if hero == null:
		return {"attack": 0, "defense": 0}
	var role: String = creature.get("role", "")
	var att := int(hero.get("attack", 0)) + int(HeroModifiers.sub(mods, "role_attack", role))
	var def := int(hero.get("defense", 0)) + int(HeroModifiers.sub(mods, "role_defense", role))
	if creature_id != "":
		var line := HeroSpecialties.line_of(creature_id, creature)
		att += int(HeroModifiers.sub(mods, "creature_attack", line))
		def += int(HeroModifiers.sub(mods, "creature_defense", line))
	if hero.get("faction", "") != "" and creature.get("faction", "") == hero.get("faction", ""):
		att += HeroModifiers.whole(mods, "faction_attack")
		def += HeroModifiers.whole(mods, "faction_defense")
	return {"attack": att, "defense": def}


## Configures a unit's hero-driven multipliers.
static func setup_unit(u: CombatUnit, mods: Dictionary) -> void:
	u.shot_mult = 1.0 + HeroModifiers.num(mods, "ranged_damage_pct")
	u.melee_mult = 1.0 + HeroModifiers.num(mods, "melee_damage_pct")
	u.shot_taken_mult = 1.0 - HeroModifiers.num(mods, "shot_resist_pct")


## Describes the side-wide hero effects for the battle report.
static func notes(hero: Variant, mods: Dictionary, data: GameData) -> Array:
	var out := []
	if hero == null:
		return out
	var parts := []
	for pair in [["ranged_damage_pct", "ranged damage"], ["melee_damage_pct", "melee damage"]]:
		var v := HeroModifiers.num(mods, pair[0])
		if v != 0.0:
			parts.append("%+d%% %s" % [int(round(v * 100)), pair[1]])
	if HeroModifiers.num(mods, "shot_resist_pct") > 0.0:
		parts.append("-%d%% damage from shots" % int(round(HeroModifiers.num(mods, "shot_resist_pct") * 100)))
	if HeroModifiers.num(mods, "screen") > 0.0:
		parts.append("enemy flankers find %d%% fewer gaps" % int(round(HeroModifiers.num(mods, "screen") * 100)))
	for key in ["role_attack", "role_defense"]:
		var roles: Dictionary = mods.get(key, {})
		for r in roles:
			if int(roles[r]) != 0:
				parts.append("%s %+d %s" % [r, int(roles[r]), key.trim_prefix("role_")])
	var lines := {}
	for key in ["creature_attack", "creature_defense"]:
		for cid in mods.get(key, {}):
			lines[cid] = true
	var line_ids := lines.keys()
	line_ids.sort()
	for cid in line_ids:
		var cname: String = data.creatures.get(cid, {}).get("name", cid)
		parts.append("%s line %+d/%+d" % [cname, int(HeroModifiers.sub(mods, "creature_attack", cid)), int(HeroModifiers.sub(mods, "creature_defense", cid))])
	if HeroModifiers.whole(mods, "faction_attack") != 0 or HeroModifiers.whole(mods, "faction_defense") != 0:
		var fac: String = data.factions.get(hero.get("faction", ""), {}).get("adjective", "own")
		parts.append("%s troops %+d/%+d" % [fac, HeroModifiers.whole(mods, "faction_attack"), HeroModifiers.whole(mods, "faction_defense")])
	if HeroModifiers.whole(mods, "ignore_hostile_terrain") > 0:
		parts.append("no hostile-terrain penalty")
	if not parts.is_empty():
		out.append("%s: %s" % [hero.get("name", "Hero"), ", ".join(parts)])
	return out


# ------------------------------------------------------------------- arts --

## The art a side can use this battle, or {} for none:
## {name, kind, strength, uses}. Strength is hit points for strike/storm/mend,
## morale points for rally, and a damage fraction for hex/ward.
static func art_plan(hero: Variant, mods: Dictionary, cfg: Dictionary) -> Dictionary:
	if hero == null or not hero.has("art") or hero["art"].is_empty():
		return {}
	var art: Dictionary = hero["art"]
	var power := int(hero.get("power", 0))
	var strength := (float(art["base"]) + float(art["per_power"]) * power) * (1.0 + HeroModifiers.num(mods, "art_power_pct"))
	var kind: String = art["kind"]
	match kind:
		"rally":
			strength = floorf(strength)
		"hex":
			strength = minf(strength, float(cfg.get("art_hex_cap", 0.6)))
		"ward":
			strength = minf(strength, float(cfg.get("art_ward_cap", 0.5)))
		_:
			strength = roundf(strength)
	var uses := 1 + int(hero.get("knowledge", 0)) / 2 + HeroModifiers.whole(mods, "art_uses")
	uses = clampi(uses, 1, int(cfg.get("art_max_uses", 5)))
	return {"name": art["name"], "kind": kind, "strength": strength, "uses": uses}


static func describe_art(plan: Dictionary) -> String:
	var what := ""
	match plan["kind"]:
		"strike": what = "%d damage to the most dangerous enemy" % int(plan["strength"])
		"storm": what = "%d damage to every enemy stack" % int(plan["strength"])
		"mend": what = "restores %d hit points" % int(plan["strength"])
		"rally": what = "+%d morale" % int(plan["strength"])
		"hex": what = "the most dangerous enemy deals %d%% less damage" % int(round(plan["strength"] * 100))
		"ward": what = "the army takes %d%% less damage" % int(round(plan["strength"] * 100))
	return "%s, %d round%s: %s" % [plan["name"], plan["uses"], "" if plan["uses"] == 1 else "s", what]


## Most dangerous living stack (ties: lower slot), deterministic.
static func top_threat(units: Array) -> CombatUnit:
	var best: CombatUnit = null
	for u in units:
		if not u.is_alive():
			continue
		if best == null or u.threat() > best.threat() or (u.threat() == best.threat() and u.slot < best.slot):
			best = u
	return best


## Most wounded living stack (ties: lower slot), or null if nobody is hurt.
static func most_wounded(units: Array) -> CombatUnit:
	var best: CombatUnit = null
	var best_missing := 0
	for u in units:
		if not u.is_alive():
			continue
		var missing: int = u.max_total_hp() - u.total_hp()
		if missing > best_missing:
			best_missing = missing
			best = u
	return best


## Share of own fallen creatures that rise again after a victory (Gravecalling,
## Ossuary Bond, artifacts). Applied by GameSession, not inside the battle.
static func recovered(lost: int, mods: Dictionary) -> int:
	return int(floor(lost * HeroModifiers.num(mods, "recover_pct")))
