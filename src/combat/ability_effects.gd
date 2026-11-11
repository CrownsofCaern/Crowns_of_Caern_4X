class_name AbilityEffects
extends RefCounted
## Data-driven creature abilities beyond the core formation rules (see
## data/abilities.json). CombatSimulator calls these hooks at fixed points of a
## battle; every hook is a no-op for units without the matching ability, and
## no random number is drawn unless a unit has an ability that needs one, so
## adding abilities never changes battles between units that lack them.
##
## Per-unit ability state lives in CombatUnit.fx (a plain dictionary).

var sim  # CombatSimulator (untyped to avoid a cyclic class reference)


func _init(simulator) -> void:
	sim = simulator


# ------------------------------------------------------------ battle start --

## Auras, fear and mindless morale. Called once both sides are built.
func on_battle_start(sides: Array, notes: Array) -> void:
	var cap := int(sim.cfg["morale_cap"])
	var fear := [0, 0]   # fear projected BY side s
	for s in 2:
		var aura := {"attack": 0, "defense": 0, "initiative": 0}
		var aura_src := {}
		for u in sides[s]:
			if u.has("aura"):
				for k in aura:
					var v := int(u.param("aura", k, 0))
					if v > aura[k]:
						aura[k] = v
						aura_src[k] = u.name
			if u.has("fear"):
				fear[s] = maxi(fear[s], int(u.param("fear", "morale", 1)))
		if aura["attack"] > 0 or aura["defense"] > 0 or aura["initiative"] > 0:
			for u in sides[s]:
				u.attack += aura["attack"]
				u.defense += aura["defense"]
				u.initiative += aura["initiative"]
			for k in aura:
				if aura[k] > 0:
					notes[s].append("%s aura: +%d %s to the army" % [aura_src[k], aura[k], k])
	for s in 2:
		var incoming: int = fear[1 - s]
		if incoming > 0:
			notes[s].append("Dread of the enemy: -%d morale" % incoming)
		for u in sides[s]:
			if u.has("mindless"):
				u.morale = 0
				continue
			if incoming > 0:
				u.morale = clampi(u.morale - incoming, -cap, cap)
				if u.has("unwavering"):
					u.morale = maxi(0, u.morale)


# ------------------------------------------------------------ round start --

## Riposte, poison ticks and regeneration. Called after per-round resets.
func on_round_start(units: Array) -> void:
	for u in units:
		if not u.is_alive():
			continue
		if u.has("riposte"):
			u.retaliations_left = 1000
		var pending: int = u.fx.get("poison", 0)
		if pending > 0:
			u.fx["poison"] = 0
			var src = u.fx.get("poison_source", null)
			var kills: int = u.take_damage(pending)
			if src != null:
				src.kills += kills
				src.damage_dealt += pending
			sim._stats["poison"] = int(sim._stats.get("poison", 0)) + pending
			sim._emit("poison", src if src != null else u, u, pending, kills)
			_check_rebirth(u)
		if u.has("regenerate") and u.is_alive() and u.top_hp < u.hp_per:
			var amount := mini(int(u.param("regenerate", "amount", 10)), u.hp_per - u.top_hp)
			u.top_hp += amount
			sim._stats["regenerated"] = int(sim._stats.get("regenerated", 0)) + amount
			sim._emit("regenerate", u, u, amount, 0)


## True if the unit loses this action to a stun (consumes the stun).
func consume_stun(u) -> bool:
	if u.fx.get("stunned", false):
		u.fx["stunned"] = false
		sim._emit("stunned", u, null, 0, 0)
		return true
	return false


# -------------------------------------------------------------- targeting --

## A taunting enemy may pull a melee attacker onto itself.
func taunt_target(enemies: Array):
	for e in enemies:
		if e.has("taunt") and sim._rng.chance(float(e.param("taunt", "chance", 0.3))):
			return e
	return null


# ----------------------------------------------------------------- damage --

func effective_defense(att, def) -> int:
	var d: int = def.defense
	if att.has("armor_pierce"):
		d = int(round(d * (1.0 - float(att.param("armor_pierce", "fraction", 0.3)))))
	return d


func damage_mult(att, _def, kind: String) -> float:
	var m := 1.0
	if att.has("momentum") and sim._round > 1:
		m *= 1.0 + minf(float(att.param("momentum", "per_round", 0.05)) * (sim._round - 1), float(att.param("momentum", "cap", 0.3)))
	if kind != "retaliation":
		m *= float(att.fx.get("strike_mult", 1.0))
	return m


## Evasion check for an incoming attack or shot.
func evades(def) -> bool:
	if def.has("evasion") and sim._rng.chance(float(def.param("evasion", "chance", 0.2))):
		sim._stats["evaded"] = int(sim._stats.get("evaded", 0)) + 1
		return true
	return false


## On-hit effects. kind is shot | melee | charge | retaliation.
func after_hit(att, def, amount: int, kind: String) -> void:
	if amount <= 0:
		return
	if att.has("life_drain") and att.is_alive():
		var restored: int = att.heal(int(round(amount * float(att.param("life_drain", "fraction", 0.25)))))
		if restored > 0:
			sim._stats["drained"] = int(sim._stats.get("drained", 0)) + restored
			sim._emit("drain", att, att, restored, 0)
	if def.is_alive():
		if att.has("poison"):
			var p := int(round(amount * float(att.param("poison", "fraction", 0.25))))
			if p > int(def.fx.get("poison", 0)):
				def.fx["poison"] = p
				def.fx["poison_source"] = att
		if att.has("stun") and sim._rng.chance(float(att.param("stun", "chance", 0.15))):
			def.fx["stunned"] = true
			sim._stats["stuns"] = int(sim._stats.get("stuns", 0)) + 1
		if att.has("sunder"):
			var done: int = def.fx.get("sundered", 0)
			var step := mini(int(att.param("sunder", "amount", 2)), int(att.param("sunder", "cap", 6)) - done)
			step = mini(step, def.defense)
			if step > 0:
				def.defense -= step
				def.fx["sundered"] = done + step
	if att.has("splash") and kind != "retaliation":
		_splash(att, def, int(round(amount * float(att.param("splash", "fraction", 0.3)))))
	if att.has("cleave") and (kind == "melee" or kind == "charge") and att.is_alive():
		_cleave(att, def, int(round(amount * float(att.param("cleave", "fraction", 0.5)))))
	if att.has("breath") and (kind == "melee" or kind == "charge" or kind == "shot" or kind == "volley") and att.is_alive():
		_breath(att, def, int(round(amount * float(att.param("breath", "fraction", 0.5)))))
	_check_rebirth(def)


func _splash(att, primary, amount: int) -> void:
	if amount <= 0:
		return
	var others := []
	var weights := []
	for e in sim._alive(primary.side):
		if e != primary:
			others.append(e)
			weights.append(e.threat())
	if others.is_empty():
		return
	var t = others[sim._rng.weighted_index(weights)]
	var kills: int = t.take_damage(amount)
	att.kills += kills
	att.damage_dealt += amount
	sim._stats["splash"] = int(sim._stats.get("splash", 0)) + amount
	sim._emit("splash", att, t, amount, kills)
	_check_rebirth(t)


## Cleave: the sweep carries into up to `targets` other enemy stacks within
## melee reach of the attacker (never a flyer in the air for ground troops).
func _cleave(att, primary, amount: int) -> void:
	if amount <= 0:
		return
	var hit := {primary: true}
	for i in int(att.param("cleave", "targets", 1)):
		var others := []
		var weights := []
		for e in sim._melee_reachable(att):
			if not hit.has(e):
				others.append(e)
				weights.append(e.threat())
		if others.is_empty():
			return
		var t = others[sim._rng.weighted_index(weights)]
		hit[t] = true
		_side_hit(att, t, amount, "cleave")


## Breath: a cone that rolls past the stack it is aimed at and engulfs one
## behind it. Aimed at the front or the flanks, it reaches the archers and
## supporters at the back; aimed at the back, it catches another stack there.
func _breath(att, primary, amount: int) -> void:
	if amount <= 0:
		return
	var behind := []
	var weights := []
	var others := []
	for e in sim._alive(primary.side):
		if e == primary:
			continue
		others.append(e)
		if e.formation == "back" or e.formation == "support":
			behind.append(e)
			weights.append(e.threat())
	if behind.is_empty():
		for e in others:
			behind.append(e)
			weights.append(e.threat())
	if behind.is_empty():
		return
	_side_hit(att, behind[sim._rng.weighted_index(weights)], amount, "breath")


func _side_hit(att, t, amount: int, kind: String) -> void:
	var kills: int = t.take_damage(amount)
	att.kills += kills
	att.damage_dealt += amount
	sim._stats[kind] = int(sim._stats.get(kind, 0)) + amount
	sim._emit(kind, att, t, amount, kills)
	_check_rebirth(t)


func _check_rebirth(u) -> void:
	if u.is_alive() or not u.has("rebirth") or u.fx.get("reborn", false):
		return
	u.fx["reborn"] = true
	var n := maxi(1, int(round(u.start_count * float(u.param("rebirth", "fraction", 0.5)))))
	u.count = n
	u.top_hp = u.hp_per
	u.fx["poison"] = 0
	sim._stats["reborn"] = int(sim._stats.get("reborn", 0)) + n
	sim._emit("rebirth", u, u, 0, n)


## Second strike of a double_strike unit (no retaliation).
func follow_up_mult(att) -> float:
	return float(att.param("double_strike", "mult", 0.5))


func summary_lines(st: Dictionary) -> Array:
	var lines := []
	if st.get("stuns", 0) > 0:
		lines.append("%d stack(s) stunned." % st["stuns"])
	if st.get("evaded", 0) > 0:
		lines.append("%d attack(s) evaded." % st["evaded"])
	if st.get("drained", 0) > 0:
		lines.append("%d hit points drained by life-stealers." % st["drained"])
	if st.get("reborn", 0) > 0:
		lines.append("%d creature(s) rose again from their ashes." % st["reborn"])
	if st.get("cleave", 0) > 0:
		lines.append("%d damage from sweeping blows that cleaved into neighbouring stacks." % st["cleave"])
	if st.get("breath", 0) > 0:
		lines.append("%d damage from breath that rolled over the lines." % st["breath"])
	if st.get("out_of_reach", 0) > 0:
		lines.append("Ground troops waited %d time(s) for flyers out of reach." % st["out_of_reach"])
	if st.get("poison", 0) > 0:
		lines.append("%d damage from poison and burning." % st["poison"])
	return lines
