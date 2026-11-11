class_name CombatSimulator
extends RefCounted
## Deterministic, headless, round-based automatic battle resolution.
##
## Input is a plain-data BattleSetup dictionary (see make_setup) so a battle can
## be replayed, predicted (Monte Carlo) or, later, handed to a tactical
## battlefield without changing army, creature or modifier definitions.
##
## Abstract formation: infantry/heavy form the FRONT that screens the BACK
## (ranged) and SUPPORT. Cavalry and flyers are FLANK units that may slip past
## the screen. Speed decides in which round a melee unit reaches the enemy, so
## ranged units get free volleys against slow armies.
##
## Army synergy comes from roles, not flat bonuses:
## - PINNING: the first melee stack to reach a target pins it. A pinned stack
##   keeps fighting its pinner, so a front line "holds" an enemy stack.
## - FLANK ATTACKS: any other melee stack striking a pinned enemy gets no
##   retaliation and ignores brace (hammer and anvil). One huge stack can only
##   face one opponent at a time, which is what makes doom stacks beatable.
## - TARGETING: front units prefer enemies nobody holds yet; flank units and
##   ranged prefer pinned enemies.
## - STAND AND SHOOT: an unpinned ranged stack fires a volley at the first
##   melee stack that closes in, before that stack strikes.
## - AIRBORNE FLYERS: a flyer lifts off at the start of each of its actions and
##   only lands when it strikes in melee. While it is in the air, ground melee
##   cannot pick it as a target; shots, other flyers and `reach` units can.
## - MATCHUPS: role against role damage bonuses (combat_config.role_matchups),
##   e.g. cavalry riding down archers.
## - HOLDING: charging cavalry waits for its own front to pin an enemy melee
##   stack instead of charging it head-on (and into braced pikes).

const ATTACKER := 0
const DEFENDER := 1

var data: GameData
var cfg: Dictionary

var _rng: GameRng
var _units: Array = []          # all CombatUnit
var _sides: Array = [[], []]    # CombatUnit per side
var _heroes: Array = [null, null]
var _mods: Array = [{}, {}]         # HeroModifiers per side
var _orders: Array = [{}, {}]       # summed battle-order effects per side (BattleOrders)
var _order_ids: Array = [{}, {}]    # {stance, focus} per side
var _arts: Array = [{}, {}]         # HeroBattleEffects.art_plan per side, plus "left" and "ready"
var _can_withdraw: Array = [true, false]  # whether a side may fall back (retreat order)
var _withdrew: int = -1             # the side that fell back, or -1
var _round_morale: Array = [0, 0]   # rally bonus for the current round
var _ward: Array = [1.0, 1.0]       # damage taken multiplier for the current round
var _log: Array = []
var _record: bool = true
var _stats: Dictionary = {}
var _engaged_by: Dictionary = {}    # CombatUnit -> CombatUnit
var _locked: Dictionary = {}        # CombatUnit -> CombatUnit (pursuit target)
var _round: int = 0
var _fortune: Array = [1.0, 1.0]
var _fx: AbilityEffects


func _init(game_data: GameData) -> void:
	data = game_data
	cfg = game_data.combat
	_fx = AbilityEffects.new(self)


## Builds a BattleSetup. Each side: {name, hero (combat_profile() or null), stacks: [{slot, creature, count}]}.
static func make_setup(attacker: Dictionary, defender: Dictionary, terrain: String, seed_value: int) -> Dictionary:
	return {"seed": seed_value, "terrain": terrain, "sides": [attacker, defender]}


func simulate(setup: Dictionary, record_log: bool = true) -> Dictionary:
	_record = record_log
	_rng = GameRng.new(int(setup["seed"]))
	_log = []
	_units = []
	_sides = [[], []]
	_engaged_by = {}
	_locked = {}
	_stats = {"charges": 0, "bypasses": 0, "surges": 0, "falters": 0, "healed": 0, "braced": 0,
		"flank_attacks": 0, "stand_and_shoot": 0, "held": 0, "overflow": 0, "art_damage": 0}
	_round_morale = [0, 0]
	_ward = [1.0, 1.0]
	_withdrew = -1
	var notes := [[], []]
	var terrain: String = setup["terrain"]
	for s in 2:
		_heroes[s] = setup["sides"][s].get("hero", null)
		_mods[s] = HeroBattleEffects.mods_of(_heroes[s], data)
		_order_ids[s] = BattleOrders.DEFAULT.duplicate()
		if _heroes[s] != null and typeof(_heroes[s].get("orders")) == TYPE_DICTIONARY:
			_order_ids[s] = _heroes[s]["orders"].duplicate()
		_orders[s] = BattleOrders.effects(data, _order_ids[s])
		# Attackers may always fall back; defenders only where the caller says
		# there is somewhere to go (GameSession: a hero in the open with a town).
		_can_withdraw[s] = bool(setup["sides"][s].get("can_withdraw", s == ATTACKER))
	for s in 2:
		var side_def: Dictionary = setup["sides"][s]
		_arts[s] = HeroBattleEffects.art_plan(_heroes[s], _mods[s], cfg)
		if not _arts[s].is_empty():
			_arts[s]["left"] = _arts[s]["uses"]
			_arts[s]["ready"] = false
			var held := float(_orders[s].get("art_power", 0.0))
			if held > 0.0 and _arts[s]["kind"] in ["strike", "storm", "mend", "rally"]:
				_arts[s]["strength"] = roundf(float(_arts[s]["strength"]) * (1.0 + held))
			elif held > 0.0:
				var cap := float(cfg.get("art_hex_cap", 0.6)) if _arts[s]["kind"] == "hex" else float(cfg.get("art_ward_cap", 0.5))
				_arts[s]["strength"] = minf(float(_arts[s]["strength"]) * (1.0 + held), cap)
			notes[s].append("Battle art: " + HeroBattleEffects.describe_art(_arts[s]))
		_sides[s] = _build_side(s, side_def, terrain, notes[s])
		_units.append_array(_sides[s])
	_fx.on_battle_start(_sides, notes)

	# Fortune of war: one triangular roll per side and battle scales all damage
	# that side deals. It keeps outcomes from being a pure function of a few
	# percent of army strength (a 10% edge should win often, not always).
	var spread := float(cfg["battle_fortune_spread"])
	for s in 2:
		_fortune[s] = 1.0 + spread * (_rng.next_float() + _rng.next_float() - 1.0)
	var max_rounds := int(cfg["max_rounds"])
	_round = 0
	if bool(cfg["opening_volley"]):
		_opening_volley()
	while _round < max_rounds and _side_alive(ATTACKER) and _side_alive(DEFENDER):
		_round += 1
		_run_round()
		if _check_withdraw():
			break

	return _build_result(setup, notes)


# ---------------------------------------------------------------- setup ----

func _build_side(s: int, side_def: Dictionary, terrain: String, notes: Array) -> Array:
	var hero = side_def.get("hero", null)
	var stacks: Array = side_def["stacks"]
	var factions := {}
	var roles := {}
	var inspire := 0
	for st in stacks:
		var c := data.creature(st["creature"])
		factions[c["faction"]] = true
		roles[c["role"]] = true
		for a in c["abilities"]:
			if a["id"] == "inspire":
				inspire = maxi(inspire, int(a.get("morale", 1)))

	var mods: Dictionary = _mods[s]
	var army_morale := 0
	var army_init := HeroModifiers.whole(mods, "initiative")
	if army_init != 0:
		notes.append("Drilled troops: %+d initiative" % army_init)
	if HeroModifiers.whole(mods, "morale") != 0:
		army_morale += HeroModifiers.whole(mods, "morale")
		notes.append("Command: %+d morale" % HeroModifiers.whole(mods, "morale"))
	var dread := HeroModifiers.whole(_mods[1 - s], "enemy_morale")
	if dread != 0:
		army_morale -= dread
		notes.append("Dread of the enemy hero: %+d morale" % -dread)
	var coh: Dictionary = cfg["faction_cohesion"]
	if factions.size() == 1:
		army_morale += int(coh["single_faction_morale"])
		notes.append("Faction cohesion: +%d morale" % int(coh["single_faction_morale"]))
	elif factions.size() >= 3:
		army_morale += int(coh["three_plus_factions_morale"])
		notes.append("Mixed factions (%d): %d morale" % [factions.size(), int(coh["three_plus_factions_morale"])])
	if inspire > 0:
		army_morale += inspire
		notes.append("Inspiring presence: +%d morale" % inspire)
	var ca: Dictionary = cfg["combined_arms"]
	if roles.size() >= int(ca["distinct_roles_required"]) - HeroModifiers.whole(mods, "combined_arms_roles"):
		army_init += int(ca["initiative"])
		notes.append("Combined arms (%d roles): +%d initiative" % [roles.size(), int(ca["initiative"])])
	if hero != null and (int(hero["attack"]) != 0 or int(hero["defense"]) != 0):
		notes.append("%s: +%d attack, +%d defense" % [hero["name"], int(hero["attack"]), int(hero["defense"])])
	notes.append_array(HeroBattleEffects.notes(hero, mods, data))
	if not BattleOrders.is_default(_order_ids[s]):
		notes.append("Orders: " + BattleOrders.describe(data, _order_ids[s]))
	var ord: Dictionary = _orders[s]

	var terrain_name: String = data.terrain(terrain).get("name", terrain)
	var noted_factions := {}
	var noted_upgrades := {}
	var cap := int(cfg["morale_cap"])
	var out := []
	for st in stacks:
		var c := Army.creature_stats(st, data)
		var u := CombatUnit.new()
		u.veteran_level = Army.veteran_level(st)
		u.side = s
		u.slot = int(st.get("slot", out.size()))
		u.creature_id = st["creature"]
		u.name = c["name"]
		u.role = c["role"]
		u.formation = c.get("formation", CombatUnit.formation_for_role(u.role))
		u.start_count = int(st["count"])
		u.count = u.start_count
		u.hp_per = int(c["hp"])
		u.top_hp = u.hp_per
		u.attack = int(c["attack"])
		u.defense = int(c["defense"])
		u.dmg_min = int(c["damage"][0])
		u.dmg_max = int(c["damage"][1])
		u.speed = int(c["speed"])
		u.initiative = int(c["initiative"]) + army_init
		for a in c["abilities"]:
			u.abilities[a["id"]] = a
		u.airborne = u.has("flying")
		var hb := HeroBattleEffects.stat_bonus(hero, mods, c, String(st["creature"]))
		u.attack = maxi(0, u.attack + int(hb["attack"]))
		u.defense = maxi(0, u.defense + int(hb["defense"]))
		HeroBattleEffects.setup_unit(u, mods)
		var up := ArmyUpgrade.for_creature(side_def, c)
		if not up.is_empty():
			ArmyUpgrade.apply(u, up, data)
			if not noted_upgrades.has(c["faction"]):
				noted_upgrades[c["faction"]] = true
				var fac_name := String(data.factions.get(c["faction"], {}).get("adjective", c["faction"]))
				notes.append("%s (%s ultimate): %s" % [up["name"], fac_name, ArmyUpgrade.describe(up, data)])
		u.attack = maxi(0, u.attack + int(ord.get("attack", 0)))
		u.initiative += int(ord.get("initiative", 0))
		if u.formation == "front":
			u.defense = maxi(0, u.defense + int(ord.get("front_defense", 0)))
		# Faction terrain affinity
		var fac: Dictionary = data.factions.get(c["faction"], {})
		var tmod := {}
		var tag := ""
		if fac.get("native_terrain", []).has(terrain):
			tmod = cfg["native_terrain_bonus"]
			tag = "native"
		elif fac.get("hostile_terrain", []).has(terrain) and HeroModifiers.whole(mods, "ignore_hostile_terrain") <= 0:
			tmod = cfg["hostile_terrain_penalty"]
			tag = "hostile"
		if tag == "native" and HeroModifiers.whole(mods, "native_bonus") > 0:
			u.attack += HeroModifiers.whole(mods, "native_bonus")
		if not tmod.is_empty():
			_apply_stat_delta(u, tmod)
			if not noted_factions.has(c["faction"]):
				noted_factions[c["faction"]] = true
				notes.append("%s %s terrain (%s): %s" % [fac["adjective"], tag, terrain_name, _describe_delta(tmod)])
		# Creature-specific terrain affinity
		var cmod: Dictionary = c["terrain"].get(terrain, {})
		if not cmod.is_empty():
			_apply_stat_delta(u, cmod)
			notes.append("%s in %s: %s" % [u.name, terrain_name, _describe_delta(cmod)])
		u.morale = clampi(int(c.get("morale", 0)) + army_morale + ArmyUpgrade.morale_bonus(up), -cap, cap)
		if u.has("unwavering") or HeroModifiers.whole(mods, "morale_floor") > 0:
			u.morale = maxi(0, u.morale)
		out.append(u)
	_pick_reserve(out, ord, notes)
	return out


## Held reserve: the strongest melee stack (front or flank, ties: lower slot)
## waits out of reach until ord.reserve_round and enters with its bonus. Needs
## at least one other stack to hold the field meanwhile.
func _pick_reserve(units: Array, ord: Dictionary, notes: Array) -> void:
	var rr := int(ord.get("reserve_round", 0))
	if rr <= 0 or units.size() < 2:
		return
	var best: CombatUnit = null
	for u in units:
		if u.formation != "front" and u.formation != "flank":
			continue
		if best == null or u.threat() > best.threat() or (u.threat() == best.threat() and u.slot < best.slot):
			best = u
	if best == null:
		return
	best.reserve_round = rr
	best.attack += int(ord.get("reserve_attack", 0))
	var cap := int(cfg["morale_cap"])
	best.morale = clampi(best.morale + int(ord.get("reserve_morale", 0)), -cap, cap)
	notes.append("Held reserve: %s enters in round %d (%+d attack, %+d morale)" % [best.name, rr,
		int(ord.get("reserve_attack", 0)), int(ord.get("reserve_morale", 0))])


## A reserve still waiting: out of reach and idle while another stack of its
## side (not itself a reserve) still stands.
func _held(u: CombatUnit) -> bool:
	if u.reserve_round <= _round or u.reserve_in:
		return false
	for a in _sides[u.side]:
		if a != u and a.is_alive() and a.reserve_round == 0:
			return true
	return false


## Reserves that may fight now enter the battle (logged once, for the viewer).
func _release_reserves() -> void:
	for u in _units:
		if u.reserve_round > 0 and not u.reserve_in and u.is_alive() and not _held(u):
			u.reserve_in = true
			_stats["reserves"] = int(_stats.get("reserves", 0)) + 1
			_emit("reserve", u, null, 0, 0)


## Share of a side's starting hit points still standing.
func _hp_share(side: int) -> float:
	var now := 0
	var start := 0
	for u in _sides[side]:
		now += u.total_hp()
		start += u.max_total_hp()
	return float(now) / float(maxi(1, start))


## Standing retreat order: after a round, a side whose strength fell to its
## withdraw_at share falls back (attacker checked first). The rear guard,
## rear_guard of every surviving stack, is cut down covering it. True if the
## battle ends here.
func _check_withdraw() -> bool:
	if not (_side_alive(ATTACKER) and _side_alive(DEFENDER)):
		return false
	for s in 2:
		var at := float(_orders[s].get("withdraw_at", 0.0))
		if at <= 0.0 or not _can_withdraw[s] or _hp_share(s) > at:
			continue
		var rg := float(_orders[s].get("rear_guard", 0.0))
		for u in _sides[s]:
			if not u.is_alive():
				continue
			var lost := int(floor(u.count * rg))
			if lost > 0:
				u.count -= lost
			_emit("withdraw", u, u, lost * u.hp_per, lost)
		_withdrew = s
		_stats["withdrawals"] = int(_stats.get("withdrawals", 0)) + 1
		return true
	return false


func _apply_stat_delta(u: CombatUnit, d: Dictionary) -> void:
	u.attack = maxi(0, u.attack + int(d.get("attack", 0)))
	u.defense = maxi(0, u.defense + int(d.get("defense", 0)))
	u.initiative += int(d.get("initiative", 0))
	u.speed = maxi(1, u.speed + int(d.get("speed", 0)))


static func _describe_delta(d: Dictionary) -> String:
	var parts := []
	for k in ["attack", "defense", "initiative", "speed"]:
		var v := int(d.get(k, 0))
		if v != 0:
			parts.append("%+d %s" % [v, k])
	return ", ".join(parts)


# ---------------------------------------------------------------- rounds ---

func _run_round() -> void:
	for u in _units:
		u.retaliations_left = int(cfg["retaliations_per_round"])
		u.retaliation_pool = u.count
		u.acted = false
		u.curse_mult = 1.0
	_fx.on_round_start(_units)
	_release_reserves()
	_use_arts()
	if not (_side_alive(ATTACKER) and _side_alive(DEFENDER)):
		return
	var jitter := int(cfg["initiative_jitter"])
	var order := []
	for u in _units:
		if u.is_alive():
			order.append({"u": u, "ini": u.initiative + _rng.next_int(0, jitter)})
	# Deterministic tie-break: higher speed, then defender first, then slot.
	order.sort_custom(func(a, b):
		if a["ini"] != b["ini"]:
			return a["ini"] > b["ini"]
		if a["u"].speed != b["u"].speed:
			return a["u"].speed > b["u"].speed
		if a["u"].side != b["u"].side:
			return a["u"].side > b["u"].side
		return a["u"].slot < b["u"].slot)
	var p := float(cfg["morale_chance_per_point"])
	for entry in order:
		var u: CombatUnit = entry["u"]
		if not u.is_alive():
			continue
		if not (_side_alive(ATTACKER) and _side_alive(DEFENDER)):
			return
		if _held(u):
			continue
		if u.reserve_round > 0 and not u.reserve_in:
			_release_reserves()   # the rest of its side fell this round
		if _fx.consume_stun(u):
			continue
		var morale := _morale_now(u)
		if morale < 0 and _rng.chance(-morale * p):
			_stats["falters"] += 1
			_emit("falter", u, null, 0, 0)
			continue
		_act(u)
		if morale > 0 and u.is_alive() and _side_alive(1 - u.side) and _rng.chance(morale * p):
			_stats["surges"] += 1
			_emit("surge", u, null, 0, 0)
			_act(u)


func _morale_now(u: CombatUnit) -> int:
	if _round_morale[u.side] == 0:
		return u.morale
	var cap := int(cfg["morale_cap"])
	return clampi(u.morale + _round_morale[u.side], -cap, cap)


## Hero battle arts, at the start of each round, attacker first. Deterministic.
func _use_arts() -> void:
	_round_morale = [0, 0]
	_ward = [1.0, 1.0]
	for s in 2:
		var art: Dictionary = _arts[s]
		if art.is_empty() or int(art["left"]) <= 0:
			continue
		if not bool(art.get("ready", true)):
			# A prepared art waits for its round, or for the line to bend.
			if _round < int(_orders[s].get("art_round", 0)):
				continue
			if 1.0 - _hp_share(s) < float(_orders[s].get("art_loss", 0.0)):
				continue
			art["ready"] = true
		var strength: float = art["strength"]
		var used := true
		match art["kind"]:
			"strike":
				var t := HeroBattleEffects.top_threat(_alive(1 - s))
				used = t != null
				if used:
					_art_hit(s, art, t, int(strength))
			"storm":
				for t in _alive(1 - s):
					_art_hit(s, art, t, int(strength))
			"mend":
				var w := HeroBattleEffects.most_wounded(_sides[s])
				used = w != null
				if used:
					var restored := w.heal(int(strength))
					_stats["healed"] += restored
					_emit_art(s, art, w, restored, 0)
			"rally":
				_round_morale[s] = int(strength)
				_emit_art(s, art, null, int(strength), 0)
			"hex":
				var t := HeroBattleEffects.top_threat(_alive(1 - s))
				used = t != null
				if used:
					t.curse_mult = minf(t.curse_mult, 1.0 - strength)
					_emit_art(s, art, t, int(round(strength * 100)), 0)
			"ward":
				_ward[s] = 1.0 - strength
				_emit_art(s, art, null, int(round(strength * 100)), 0)
		if used:
			art["left"] = int(art["left"]) - 1


func _art_hit(s: int, art: Dictionary, t: CombatUnit, amount: int) -> void:
	var kills := t.take_damage(amount)
	_stats["art_damage"] += amount
	_emit_art(s, art, t, amount, kills)


func _emit_art(s: int, art: Dictionary, target: CombatUnit, amount: int, kills: int) -> void:
	if not _record:
		return
	var who: String = _heroes[s].get("name", "Hero")
	_log.append({"round": _round, "type": "art_" + String(art["kind"]), "actor": "%s (%s)" % [who, art["name"]],
		"actor_side": s, "actor_slot": -1, "actor_count": 0,
		"target": target.name if target != null else "",
		"target_side": target.side if target != null else -1,
		"target_slot": target.slot if target != null else -1,
		"target_count": target.count if target != null else 0,
		"amount": amount, "kills": kills})


## Round 0: every ranged stack looses one long-range volley (at reduced
## strength) while the lines close. The volleys are simultaneous: all are aimed
## and rolled before any lands.
func _opening_volley() -> void:
	var volleys := []
	for u in _units:
		var enemies := _alive(1 - u.side)
		if u.has("ranged") and not enemies.is_empty():
			var t := _pick_ranged_target(u, enemies)
			var dmg := int(round(_damage(u, t, "shot", false) * float(cfg["opening_volley_mult"]) * (1.0 + float(_orders[u.side].get("volley_pct", 0.0)))))
			volleys.append([u, t, maxi(1, dmg)])
	for v in volleys:
		var excess: int = v[2]
		if v[1].is_alive():
			excess = v[2] - v[1].total_hp()
			_apply(v[0], v[1], mini(v[2], v[1].total_hp()), "volley")
			if v[0].has("curse"):
				v[1].curse_mult = minf(v[1].curse_mult, float(v[0].param("curse", "damage_mult", 0.8)))
		_spill(v[0], excess, "volley")


func _approach_round(u: CombatUnit) -> int:
	return maxi(1, _base_approach_round(u) - int(_orders[u.side].get("advance", 0)) + int(_orders[1 - u.side].get("enemy_delay", 0)))


func _base_approach_round(u: CombatUnit) -> int:
	if u.has("flying"):
		return 1
	for pair in cfg["approach_round_by_speed"]:
		if u.speed >= int(pair[0]):
			return int(pair[1])
	return 3


func _act(u: CombatUnit) -> void:
	u.acted = true
	if u.has("flying"):
		u.airborne = true   # lifts off; lands again when it strikes in melee
	var enemies := _alive(1 - u.side)
	if enemies.is_empty():
		return
	# Support: heal the most wounded ally instead of attacking. A healer with
	# no fighting allies left fights instead of only tending its own wounds.
	if u.has("heal"):
		var best: CombatUnit = null
		var best_missing := 0
		var lone := not _has_fighting_ally(u)
		var only_tag: String = u.param("heal", "tag", "")
		for a in _alive(u.side):
			if lone and a == u:
				continue
			if only_tag != "" and not data.creature(a.creature_id).get("tags", []).has(only_tag):
				continue
			var missing: int = a.max_total_hp() - a.total_hp()
			if missing > best_missing:
				best_missing = missing
				best = a
		if best != null:
			var restored := best.heal(int(u.param("heal", "per_creature", 5)) * u.count)
			_stats["healed"] += restored
			_emit("heal", u, best, restored, 0)
			return
	var engager := _pinner(u)
	if engager != null and not can_reach(u, engager) and not u.has("ranged"):
		engager = null   # the flyer that held it has taken to the air again
	if u.has("ranged"):
		if engager != null and can_reach(u, engager):
			_melee(u, engager)
		else:
			_shoot(u, _pick_ranged_target(u, enemies))
		return
	if engager == null and _round < _approach_round(u):
		return
	if engager == null and u.formation == "support" and _has_fighting_ally(u) and not _ally_holds_enemy(u.side):
		return   # support stays behind the line until an ally has pinned someone
	var target := engager if engager != null else _pick_melee_target(u, enemies)
	if target == null:
		# Only flyers in the air are left in reach: ground troops wait for them to dive.
		_stats["out_of_reach"] = int(_stats.get("out_of_reach", 0)) + 1
		_emit("out_of_reach", u, null, 0, 0)
		return
	if engager == null and _should_hold(u, target):
		_stats["held"] += 1
		_emit("hold", u, target, 0, 0)
		return
	_melee(u, target)


## Cavalry with an unspent charge waits for its own front line to pin an enemy
## melee stack instead of charging it head-on (the hammer waits for the anvil).
## It never waits to ride down ranged or support stacks.
## Mobile strikers (cavalry that can still charge, and flyers when
## flyers_hold_for_the_line is on) wait until a front-line ally holds their
## target, so they hit it in the flank instead of taking its full answer alone.
func _should_hold(u: CombatUnit, target: CombatUnit) -> bool:
	var striker := (u.has("charge") and not u.has_charged) or (u.has("flying") and bool(cfg["flyers_hold_for_the_line"]))
	if not striker:
		return false
	if not (target.formation == "front" or target.formation == "flank"):
		return false
	if _held_by_line(target, u) or _round > int(cfg["cavalry_hold_max_rounds"]):
		return false
	for a in _alive(u.side):
		if a.formation == "front":
			return true
	return false


## Whether `u` has a living non-support ally that can take the front.
func _has_fighting_ally(u: CombatUnit) -> bool:
	for a in _alive(u.side):
		if a != u and a.formation != "support":
			return true
	return false


func _ally_holds_enemy(side: int) -> bool:
	for e in _alive(1 - side):
		if _pinner(e) != null:
			return true
	return false


## The stack currently pinning `u`, or null.
func _pinner(u: CombatUnit) -> CombatUnit:
	var p: CombatUnit = _engaged_by.get(u, null)
	if p != null and not p.is_alive():
		_engaged_by.erase(u)
		return null
	return p


func _pinned_by_other(target: CombatUnit, att: CombatUnit) -> bool:
	var p := _pinner(target)
	return p != null and p != att


## Hammer and anvil: the target is held by a front-line stack (infantry or
## heavy) of the attacker's side. A cavalry stack pinning an enemy does not
## open it up for other cavalry, so splitting one unit into stacks gains nothing.
func _held_by_line(target: CombatUnit, att: CombatUnit) -> bool:
	var p := _pinner(target)
	return p != null and p != att and p.formation == "front"


## Whether `att` can strike `def` in melee: a flyer in the air is out of reach
## of ground troops without `reach`.
func can_reach(att: CombatUnit, def: CombatUnit) -> bool:
	return not def.airborne or att.has("flying") or att.has("reach")


func _reachable_only(att: CombatUnit, list: Array) -> Array:
	var out := []
	for e in list:
		if can_reach(att, e):
			out.append(e)
	return out


## Role against role damage multiplier (combat_config.role_matchups).
func matchup_mult(att: CombatUnit, def: CombatUnit) -> float:
	var table: Dictionary = cfg.get("role_matchups", {}).get(att.role, {})
	return 1.0 + float(table.get(def.role, 0.0))


# -------------------------------------------------------------- targeting --

## Living stacks of a side that are on the field (a held reserve is not).
func _alive(side: int) -> Array:
	var out := []
	for u in _sides[side]:
		if u.is_alive() and (u.reserve_round == 0 or not _held(u)):
			out.append(u)
	return out


func _side_alive(side: int) -> bool:
	for u in _sides[side]:
		if u.is_alive():
			return true
	return false


func _weighted_pick(candidates: Array, weights: Array) -> CombatUnit:
	return candidates[_rng.weighted_index(weights)]


func _pick_ranged_target(u: CombatUnit, enemies: Array) -> CombatUnit:
	var weights := []
	for e in enemies:
		var w: float = e.threat()
		if _pinner(e) != null:
			w *= float(cfg["ranged_pinned_target_weight"])   # shoot what our line holds
		if e.has("ranged"):
			w *= float(cfg["counter_battery_weight"])
		if e.formation == "back" or e.formation == "support":
			w *= float(_orders[u.side].get("back_target_weight", 1.0))
		weights.append(w)
	_apply_order_weights(u, enemies, weights)
	return _weighted_pick(enemies, weights)


## Battle orders that steer targeting: the most dangerous or most wounded
## enemy in reach weighs more, and (Guard the archers) flank units weigh
## enemies that attack their side's archers and supporters more.
func _apply_order_weights(u: CombatUnit, candidates: Array, weights: Array) -> void:
	var ord: Dictionary = _orders[u.side]
	if ord.is_empty() or candidates.is_empty():
		return
	if ord.has("strongest_weight"):
		var best := 0
		for i in candidates.size():
			if candidates[i].threat() > candidates[best].threat():
				best = i
		weights[best] *= float(ord["strongest_weight"])
	if ord.has("weakest_weight"):
		var low := 0
		for i in candidates.size():
			if candidates[i].total_hp() < candidates[low].total_hp():
				low = i
		weights[low] *= float(ord["weakest_weight"])
	if ord.has("guard_weight") and u.formation == "flank":
		for i in candidates.size():
			if _threatens_back(candidates[i], u.side):
				weights[i] *= float(ord["guard_weight"])


## True if enemy stack `e` is fighting (pinning or hunting) one of side's
## ranged or support stacks.
func _threatens_back(e: CombatUnit, side: int) -> bool:
	for a in _alive(side):
		if a.formation != "back" and a.formation != "support":
			continue
		if _pinner(a) == e or _locked.get(e, null) == a:
			return true
	return false


func _pick_melee_target(u: CombatUnit, enemies: Array) -> CombatUnit:
	var locked: CombatUnit = _locked.get(u, null)
	if locked != null and locked.is_alive() and can_reach(u, locked):
		return locked
	enemies = _reachable_only(u, enemies)
	if enemies.is_empty():
		return null
	var taunter = _fx.taunt_target(enemies)
	if taunter != null:
		return taunter
	var screen := []
	var flank := []
	var rear := []
	for e in enemies:
		match e.formation:
			"front": screen.append(e)
			"flank": flank.append(e)
			_: rear.append(e)
	var candidates := enemies
	if not screen.is_empty():
		candidates = screen + flank
		if not rear.is_empty() and (u.role == "cavalry" or u.has("flying")):
			var own_front := false
			for a in _alive(u.side):
				if a.formation == "front":
					own_front = true
					break
			var p := 0.0
			if u.has("flying"):
				p = float(cfg["flyer_backline_preference"])
			else:
				p = float(cfg["cavalry_bypass_with_anchor"] if own_front else cfg["cavalry_bypass_chance"])
			p -= HeroModifiers.num(_mods[1 - u.side], "screen")
			p -= float(_orders[1 - u.side].get("screen", 0.0))
			p += float(_orders[u.side].get("bypass", 0.0))
			for g in screen:
				if g.has("guardian"):
					p -= float(g.param("guardian", "screen", 0.1))
			if _rng.chance(p):
				_stats["bypasses"] += 1
				var weights := []
				for e in rear:
					weights.append(e.threat() * (1.5 if e.has("ranged") else 1.0) * float(_orders[u.side].get("back_target_weight", 1.0)))
				var t := _weighted_pick(rear, weights)
				_locked[u] = t
				_emit("bypass", u, t, 0, 0)
				return t
	# Front units look for enemies nobody holds yet (to pin them); flank units
	# look for enemies already pinned (to hit them from the side).
	var w := []
	var pinned_w := float(cfg["front_pinned_target_weight"] if u.formation == "front" else cfg["flank_pinned_target_weight"])
	for e in candidates:
		var p := _pinner(e)
		w.append(e.threat() * (pinned_w if p != null and p != u else 1.0))
	_apply_order_weights(u, candidates, w)
	return _weighted_pick(candidates, w)


# ----------------------------------------------------------------- damage --

func _roll_base(u: CombatUnit, fighters: int) -> float:
	var n := mini(fighters, 10)
	var total := 0
	for i in n:
		total += _rng.next_int(u.dmg_min, u.dmg_max)
	return float(total) * float(fighters) / float(n)


## Frontage: in melee a stack can only bring as many creatures to bear as fit
## around the target. Room scales with the target's creature count and size
## (hit points per creature), so big targets have room for more attackers.
## Volleys are not limited, but point-blank stand-and-shoot fire is. One huge
## stack therefore cannot use its full weight against a smaller opponent, while
## several stacks can.
func _fighters(att: CombatUnit, def: CombatUnit, kind: String) -> int:
	if kind == "shot":
		return att.count
	if kind == "retaliation" or kind == "point_blank":
		return mini(_frontage(att, def), att.retaliation_pool)
	return _frontage(att, def)


func _frontage(att: CombatUnit, def: CombatUnit) -> int:
	var room := float(cfg["frontage_hp_ratio"]) * def.count * def.hp_per / float(att.hp_per)
	return mini(att.count, maxi(int(cfg["frontage_min_creatures"]), int(ceil(room))))


func _damage(att: CombatUnit, def: CombatUnit, kind: String, charge: bool, fighters: int = -1) -> int:
	var diff := att.attack - _fx.effective_defense(att, def)
	var factor := 1.0
	if diff >= 0:
		factor = minf(1.0 + float(cfg["attack_bonus_per_point"]) * diff, float(cfg["attack_bonus_cap"]))
	else:
		factor = maxf(1.0 - float(cfg["defense_reduction_per_point"]) * -diff, float(cfg["defense_reduction_floor"]))
	var mult := factor * att.curse_mult * float(_fortune[att.side]) * _fx.damage_mult(att, def, kind)
	mult *= _ward[def.side] * matchup_mult(att, def)
	if kind == "shot" or kind == "point_blank":
		mult *= att.shot_mult * def.shot_taken_mult
		if def.formation == "back" or def.formation == "support":
			mult *= 1.0 - float(_orders[def.side].get("shot_cover", 0.0))
		if def.has("shield_wall"):
			mult *= 1.0 - float(def.param("shield_wall", "ranged_reduction", 0.3))
	elif att.has("ranged") and not att.has("skirmisher"):
		mult *= float(cfg["engaged_ranged_penalty"] if kind == "melee" else cfg["ranged_melee_penalty"])
	else:
		mult *= att.melee_mult
	if charge:
		mult *= 1.0 + float(att.param("charge", "bonus", 0.3))
	if fighters < 0:
		fighters = _fighters(att, def, kind)
	return maxi(1, int(round(_roll_base(att, fighters) * mult)))


func _apply(att: CombatUnit, def: CombatUnit, amount: int, kind: String) -> void:
	if _fx.evades(def):
		_emit("evade", att, def, 0, 0)
		return
	var kills := def.take_damage(amount)
	att.kills += kills
	att.damage_dealt += amount
	_emit(kind, att, def, amount, kills)
	_fx.after_hit(att, def, amount, kind)


func _shoot(att: CombatUnit, def: CombatUnit) -> void:
	var dmg := _damage(att, def, "shot", false)
	var excess := dmg - def.total_hp()
	_apply(att, def, mini(dmg, def.total_hp()), "shot")
	if att.has("curse") and def.is_alive():
		def.curse_mult = minf(def.curse_mult, float(att.param("curse", "damage_mult", 0.8)))
	_spill(att, excess, "shot")
	if att.has("double_strike") and att.is_alive():
		var rest2 := _alive(1 - att.side)
		if not rest2.is_empty():
			var t2: CombatUnit = def if def.is_alive() else _pick_ranged_target(att, rest2)
			att.fx["strike_mult"] = _fx.follow_up_mult(att)
			_apply(att, t2, _damage(att, t2, "shot", false), "shot")
			att.fx["strike_mult"] = 1.0


## A volley that wipes out its target carries on into the next enemy stack,
## and the next, so one big stack of archers wastes no more arrows than several
## small ones (armies hold up to ten small stacks).
func _spill(att: CombatUnit, excess: int, kind: String) -> void:
	while excess > 0 and bool(cfg["volley_spill"]):
		var rest := _alive(1 - att.side)
		if rest.is_empty():
			return
		var t := _pick_ranged_target(att, rest)
		var hp := t.total_hp()
		_apply(att, t, mini(excess, hp), kind)
		excess -= hp


func _melee(att: CombatUnit, def: CombatUnit) -> void:
	att.airborne = false   # a flyer comes down to strike and can be struck back
	# Stand and shoot: a free ranged stack fires at the first enemy that closes
	# in, before the blow lands. This uses its retaliation for the round.
	if def.has("ranged") and _pinner(def) == null and _can_retaliate(def):
		_stats["stand_and_shoot"] += 1
		var shot := maxi(1, int(round(_damage(def, att, "point_blank", false) * float(cfg["stand_and_shoot_mult"]))))
		_spend_retaliation(def, att)
		_apply(def, att, shot, "stand_and_shoot")
		if not att.is_alive():
			return
	var charging := att.has("charge") and not att.has_charged
	if charging:
		att.has_charged = true
	var spare := 0
	if not att.has("ranged") and bool(cfg["frontage_overflow"]):
		spare = att.count - _frontage(att, def)
	_exchange(att, def, _fighters(att, def, "melee"), charging, 1.0, false)
	if spare > 0 and att.is_alive():
		_overflow(att, def, spare, charging)
	# Double strike: a follow-up blow at reduced strength, never answered.
	if att.has("double_strike") and att.is_alive() and def.is_alive():
		att.fx["strike_mult"] = _fx.follow_up_mult(att)
		_apply(att, def, _damage(att, def, "melee", false), "melee")
		att.fx["strike_mult"] = 1.0


## One melee blow and the answer to it. `fighters` attackers strike; the
## defender's creatures facing them strike back, minus those just killed.
func _exchange(att: CombatUnit, def: CombatUnit, fighters: int, charging: bool, mult: float, overflow: bool) -> void:
	var flank := att.formation == "flank" and _held_by_line(def, att)
	var braced := charging and def.has("brace") and not flank
	var charged := charging and not braced
	if charging:
		_stats["braced" if braced else "charges"] += 1
	var facing := _fighters(def, att, "retaliation")
	var flank_blocks := flank and bool(cfg["flank_attacks_prevent_retaliation"])
	# First strike: the defender's answer lands before the blow.
	if def.has("first_strike") and _can_retaliate(def) and not att.has("relentless") and not flank_blocks:
		var fs := _damage(def, att, "retaliation", false, facing)
		_spend_retaliation(def, att)
		if braced:
			fs = int(round(fs * float(cfg["brace_retaliation_mult"])))
		_apply(def, att, maxi(1, fs), "retaliation")
		if not att.is_alive():
			return
		fighters = mini(fighters, att.count)
		flank_blocks = true   # already answered
	var before := def.count
	var order_mult := 1.0
	if not att.first_blow_done:
		order_mult += float(_orders[att.side].get("charge_pct", 0.0))
	if flank:
		order_mult += float(_orders[att.side].get("flank_pct", 0.0))
	att.first_blow_done = true
	var dmg := maxi(1, int(round(_damage(att, def, "melee", charged, fighters) * mult * order_mult)))
	_apply(att, def, dmg, "overflow" if overflow else ("charge" if charged else "melee"))
	if flank:
		_stats["flank_attacks"] += 1
	# The first melee attacker pins the target: it must fight that stack
	# (ranged units then fight at a penalty) until the pinner falls.
	if not att.has("ranged") and _pinner(def) == null and def.is_alive():
		_engaged_by[def] = att
	if not def.is_alive() or not _can_retaliate(def) or att.has("relentless") or flank_blocks:
		return
	if bool(cfg["retaliation_pool"]):
		# The creatures in contact took the blow, so the dead cannot answer it.
		facing -= before - def.count
		if facing <= 0:
			return
	var r := _damage(def, att, "retaliation", false, facing)
	_spend_retaliation(def, att)
	if braced:
		r = int(round(r * float(cfg["brace_retaliation_mult"])))
	elif def.acted:
		# A stack that already fought this round is out of position and
		# strikes back with only part of its strength.
		r = int(round(r * float(cfg["retaliation_after_acting_mult"])))
	_apply(def, att, maxi(1, r), "retaliation")


## Wrap-around: creatures of a big stack that found no room against its target
## engage other reachable enemy stacks, so frontage spreads a doom stack's
## weight over several opponents instead of wasting it.
func _overflow(att: CombatUnit, first: CombatUnit, spare: int, charging: bool) -> void:
	var hit := {first: true}
	for i in int(cfg["frontage_overflow_targets"]):
		if spare <= 0 or not att.is_alive():
			return
		var candidates := []
		for e in _melee_reachable(att):
			if not hit.has(e):
				candidates.append(e)
		if candidates.is_empty():
			return
		var weights := []
		for e in candidates:
			weights.append(e.threat())
		var t := _weighted_pick(candidates, weights)
		hit[t] = true
		var n := mini(spare, _frontage(att, t))
		spare -= n
		_stats["overflow"] += 1
		_exchange(att, t, n, charging, float(cfg["frontage_overflow_mult"]), true)


## Enemy stacks a melee unit can reach: the front and flanks while the enemy
## still has a front line, otherwise everyone.
func _melee_reachable(u: CombatUnit) -> Array:
	var enemies := _alive(1 - u.side)
	var reach := []
	for e in enemies:
		if e.formation == "front" or e.formation == "flank":
			reach.append(e)
	var has_front := false
	for e in enemies:
		if e.formation == "front":
			has_front = true
	return _reachable_only(u, reach if has_front else enemies)


## Retaliation is a per-round pool of creatures rather than a single strike:
## a stack may strike back at every attacker, but each retaliation only uses
## the creatures facing that attacker (frontage), and in total no more than the
## stack's size per round. One big stack and several small ones of the same
## creatures therefore trade blows evenly. With retaliation_pool off, the
## classic "N retaliations per round with the whole stack" rule applies.
func _can_retaliate(u: CombatUnit) -> bool:
	if bool(cfg["retaliation_pool"]):
		return u.retaliation_pool > 0
	return u.retaliations_left > 0


func _spend_retaliation(def: CombatUnit, att: CombatUnit) -> void:
	if def.has("riposte"):
		return   # answers every attack with its full frontage
	if bool(cfg["retaliation_pool"]):
		def.retaliation_pool -= mini(def.retaliation_pool, _frontage(def, att))
	else:
		def.retaliations_left -= 1


func _emit(kind: String, actor: CombatUnit, target: CombatUnit, amount: int, kills: int) -> void:
	if not _record:
		return
	# Slots and counts after the event let the battle viewer replay the log.
	_log.append({
		"round": _round, "type": kind,
		"actor": actor.name, "actor_side": actor.side,
		"actor_slot": actor.slot, "actor_count": actor.count,
		"target": target.name if target != null else "",
		"target_side": target.side if target != null else -1,
		"target_slot": target.slot if target != null else -1,
		"target_count": target.count if target != null else 0,
		"amount": amount, "kills": kills,
	})


# ----------------------------------------------------------------- result --

func _build_result(setup: Dictionary, notes: Array) -> Dictionary:
	var att_alive := _side_alive(ATTACKER)
	var def_alive := _side_alive(DEFENDER)
	var winner := DEFENDER
	var outcome := "defender_victory"
	if att_alive and not def_alive:
		winner = ATTACKER
		outcome = "attacker_victory"
	elif att_alive and def_alive:
		outcome = "attacker_withdrew"
	if _withdrew >= 0:
		winner = 1 - _withdrew
		outcome = "attacker_retreated" if _withdrew == ATTACKER else "defender_retreated"
	var sides := []
	for s in 2:
		var stacks := []
		var hp_start := 0
		var hp_end := 0
		for u in _sides[s]:
			stacks.append({"slot": u.slot, "creature": u.creature_id, "name": u.name, "formation": u.formation,
				"start": u.start_count, "end": u.count, "lost": u.start_count - u.count,
				"veteran_level": u.veteran_level, "kills": u.kills, "damage": u.damage_dealt, "ultimate": u.ultimate,
				"reserve": u.reserve_round})
			hp_start += u.max_total_hp()
			hp_end += u.total_hp()
		sides.append({"name": setup["sides"][s].get("name", "Side %d" % s), "stacks": stacks,
			"hp_start": hp_start, "hp_end": hp_end, "notes": notes[s]})
	var result := {
		"seed": int(setup["seed"]), "terrain": setup["terrain"], "rounds": _round,
		"winner": winner, "outcome": outcome, "sides": sides, "stats": _stats.duplicate(),
		"orders": [_order_ids[0].duplicate(), _order_ids[1].duplicate()],
		"withdrew": _withdrew,
		# Hit points destroyed by each side (input for experience).
		"hp_killed": [sides[1]["hp_start"] - sides[1]["hp_end"], sides[0]["hp_start"] - sides[0]["hp_end"]],
	}
	if _record:
		result["log"] = _log
		result["summary"] = _summarize(result)
	return result


func _summarize(r: Dictionary) -> Array:
	var lines := []
	var names := [r["sides"][0]["name"], r["sides"][1]["name"]]
	match r["outcome"]:
		"attacker_victory": lines.append("%s won in %d rounds." % [names[0], r["rounds"]])
		"defender_victory": lines.append("%s held and destroyed the attackers in %d rounds." % [names[1], r["rounds"]])
		"attacker_retreated": lines.append("%s fell back after %d rounds; the rear guard covered the retreat." % [names[0], r["rounds"]])
		"defender_retreated": lines.append("%s fell back after %d rounds; the rear guard covered the retreat." % [names[1], r["rounds"]])
		_: lines.append("No decision after %d rounds; %s withdrew." % [r["rounds"], names[0]])
	for s in 2:
		var best: Dictionary = {}
		for st in r["sides"][s]["stacks"]:
			if best.is_empty() or st["kills"] > best["kills"]:
				best = st
		if not best.is_empty() and best["kills"] > 0:
			lines.append("Deadliest on %s's side: %s (%d kills)." % [names[s], best["name"], best["kills"]])
	var st: Dictionary = r["stats"]
	if st["charges"] > 0:
		lines.append("%d cavalry charge(s) struck home." % st["charges"])
	if st["braced"] > 0:
		lines.append("%d charge(s) broke on braced pikes." % st["braced"])
	if st["bypasses"] > 0:
		lines.append("Flankers slipped past the front line %d time(s)." % st["bypasses"])
	if st["flank_attacks"] > 0:
		lines.append("%d blow(s) struck enemies already held by the line." % st["flank_attacks"])
	if st["stand_and_shoot"] > 0:
		lines.append("Archers loosed %d point-blank volley(s) at charging foes." % st["stand_and_shoot"])
	if st["surges"] > 0 or st["falters"] > 0:
		lines.append("Morale: %d surge(s), %d falter(s)." % [st["surges"], st["falters"]])
	if int(st.get("reserves", 0)) > 0:
		lines.append("%d held reserve(s) entered the fight fresh." % int(st["reserves"]))
	if st["art_damage"] > 0:
		lines.append("Hero battle arts dealt %d damage." % st["art_damage"])
	if st["healed"] > 0:
		lines.append("%d hit points restored by healers." % st["healed"])
	lines.append_array(_fx.summary_lines(st))
	return lines
