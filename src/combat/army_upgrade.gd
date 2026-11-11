class_name ArmyUpgrade
extends RefCounted
## A faction's ultimate building (an "army_upgrade" building effect, see
## data/buildings.json) applied to one creature stack in battle. The session
## puts the owner's upgrades on each battle side as "upgrades": {faction id:
## effect}; CombatSimulator calls apply() for every stack of that faction.
## Pure data in, no random draws, so a battle without upgrades is unchanged.


## The upgrade a side's stack of this creature fights with, or {}.
static func for_creature(side_def: Dictionary, creature: Dictionary) -> Dictionary:
	var ups: Dictionary = side_def.get("upgrades", {})
	return ups.get(String(creature.get("faction", "")), {})


## Applies the upgrade's stats, multipliers and abilities to a freshly built
## unit (after hero bonuses, before morale is settled; morale is added by the
## caller through morale_bonus()).
static func apply(u: CombatUnit, e: Dictionary, data: GameData) -> void:
	u.attack += int(e.get("attack", 0))
	u.defense += int(e.get("defense", 0))
	u.initiative += int(e.get("initiative", 0))
	var hp_pct := float(e.get("hp_pct", 0.0))
	if hp_pct > 0.0:
		u.hp_per = maxi(1, int(round(u.hp_per * (1.0 + hp_pct))))
		u.top_hp = u.hp_per
	var dmg := 1.0 + float(e.get("damage_pct", 0.0))
	u.melee_mult *= dmg
	u.shot_mult *= dmg * (1.0 + float(e.get("ranged_damage_pct", 0.0)))
	u.shot_taken_mult *= 1.0 - float(e.get("shot_resist_pct", 0.0))
	for a in e.get("abilities", []):
		var aid := String(a["id"])
		var defaults: Dictionary = data.abilities.get(aid, {}).get("params", {})
		var merged: Dictionary = (u.abilities.get(aid, {"id": aid}) as Dictionary).duplicate()
		for k in a:
			if k == "id":
				continue
			# A stronger copy the creature already has wins, parameter by parameter.
			var have := float(merged.get(k, defaults.get(k, a[k])))
			merged[k] = maxf(have, float(a[k])) if u.abilities.has(aid) else float(a[k])
		u.abilities[aid] = merged
	u.ultimate = String(e.get("name", ""))


static func morale_bonus(e: Dictionary) -> int:
	return int(e.get("morale", 0))


## One line for the battle report and the town screen: "+2 attack, +1 morale, ...".
static func describe(e: Dictionary, data: GameData) -> String:
	var parts := []
	for k in ["attack", "defense", "initiative", "morale"]:
		if int(e.get(k, 0)) != 0:
			parts.append("%+d %s" % [int(e[k]), k])
	var pcts := {"hp_pct": "hit points", "damage_pct": "damage", "ranged_damage_pct": "ranged damage"}
	for k in pcts:
		if float(e.get(k, 0.0)) != 0.0:
			parts.append("%+d%% %s" % [int(round(float(e[k]) * 100)), pcts[k]])
	if float(e.get("shot_resist_pct", 0.0)) > 0.0:
		parts.append("-%d%% damage from shots" % int(round(float(e["shot_resist_pct"]) * 100)))
	for a in e.get("abilities", []):
		var ab: Dictionary = data.abilities.get(String(a["id"]), {})
		var label := String(ab.get("name", a["id"])).to_lower()
		var params := []
		for k in a:
			if k != "id":
				var v := float(a[k])
				params.append("%d%%" % int(round(v * 100)) if v < 1.0 else str(int(v)))
		parts.append(label + ("" if params.is_empty() else " " + "/".join(params)))
	return ", ".join(parts)
