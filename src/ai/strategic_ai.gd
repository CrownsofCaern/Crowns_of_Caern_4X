class_name StrategicAI
extends RefCounted
## Rule-based, utility-driven computer opponent for one player.
##
## The AI only reads the game state and acts through GameSession commands
## (move_hero, attack, build, recruit, move_stack, hire_hero, trade,
## cast_spell, upgrade_stack, trader_buy, send_resources), exactly like the
## UI, so it can never do anything a human player could not.
##
## A turn has three phases:
##   1. Towns: build the best-value affordable building (buying a missing
##      resource at the market if that unlocks a much better building), hire a
##      hero when the economy can carry one.
##   2. Heroes, one after another: score every known target (resource piles,
##      mines, towns, neutral armies, own towns worth visiting, unexplored
##      frontier) as value / travel time, minus expected battle losses, walk to
##      the best one and repeat until movement runs out. Guarded targets are
##      fought only when the combat forecast says the battle is safe enough.
##      A hero standing in an own town recruits, picks up the garrison, or
##      leaves its army behind as garrison if the town is threatened.
##      Spells: a battle spell before a fight it wins or makes cheaper, a
##      movement spell to reach today's target, Homeward / Town Gate to defend
##      a threatened town. A hero on a road trader buys what it would wear.
##   3. Towns again: spend what is left on recruits for the garrison, upgrade
##      stacks, hire, and send spare resources to allies that lack them.
##
## The AI keeps no memory between turns: every decision is a pure function of
## the game state, so it is deterministic and a loaded game plays on exactly
## as the unsaved one would. It never draws from the game RNG; forecasts use
## the predictor's own salted seeds.

const DEFAULT_SETTINGS := {
	"min_win_probability": 0.8,     # attack only at or above this forecast
	"max_loss_fraction": 0.45,      # ... and with expected losses below this share of the army
	"loss_weight": 1.0,             # utility lost per gold of expected casualties
	"forecast_simulations": 48,     # fewer than the player's forecast; enough for a go/no-go
	"forecasts_per_decision": 4,    # guarded candidates forecast per hero decision
	"strength_prefilter": 0.7,      # skip a fight outright if our army value < this x theirs
	"mine_horizon_days": 12,        # days of income a mine is worth
	"town_value": 9000,             # gold value of taking a town (besides its income)
	"income_horizon_days": 10,
	"explore_value_per_tile": 35,   # gold value of each tile revealed
	"neutral_value_rate": 0.6,      # value of beating a neutral army (XP, spoils, open roads) per gold of its troops
	"enemy_bonus": 1.4,             # extra value of taking something from a rival player
	"threat_days": 1.0,             # enemy armies that can reach a town within this many days threaten it
	"danger_days": 2.0,             # heroes leave the garrison in place while an enemy is this close
	"defend_value": 14000,          # value of returning to a threatened town
	"max_actions_per_hero": 16,
	"xp_value": 2.0,                # gold value of one experience point (encounters)
	"skill_priority": ["leadership", "onslaught", "tactics", "archery", "logistics", "shieldcraft", "sorcery", "gravecalling", "drill", "stewardship", "wayfinding", "fieldcraft", "scouting", "quartermaster", "lore"],
	"max_heroes": 3,
	"hire_reserve_gold": 1500,      # gold kept after hiring a hero
	"trade_value_ratio": 1.5,       # trade for a building only if its score beats the best affordable one by this
	"hero_kill_value": 4000,        # value of removing an enemy hero from the map (besides its army)
	"site_capture_weeks": 3.0,      # weeks of a dwelling site's troops that taking it is worth
	"site_recruit_rate": 0.8,       # utility per gold of troops the hero can recruit at a held dwelling site
	"artifact_value_rate": 1.0,     # utility per gold of artifact value that the hero would wear
	"spare_artifact_rate": 0.15,    # ... and of one it can only carry in the pack
	"army_upgrade_share": 0.3,      # a faction ultimate is worth this share of the troops it empowers
	"mana_value": 60,               # gold value of one point of mana (spells are cast when they save more)
	"trader_buy_ratio": 0.9,        # buy a trader's artifact if it is worth this share of its price to the hero
	"trader_reserve_gold": 1500,    # gold kept after buying from a road trader
	"cobolt_from_day": 8,           # first day the AI goes shopping at cobolt posts
	"trader_visit_rate": 0.25,      # walking to a trader is worth this share of what the hero would buy there
	"trader_map_rate": 0.6,         # a trader's map is worth this share of explore_value_per_tile per hidden tile it shows
	"upgrade_reserve_gold": 1000,   # gold kept after upgrading a stack (buildings come first)
	"upgrade_reserve_resource": 5,  # ... and of every other resource the upgrade costs
	"gift_reserve_gold": 4000,      # gold kept before sending anything to an ally
	"gift_reserve_resource": 12,    # ... and of every other resource
	"gift_share": 0.3,              # share of the surplus above the reserve sent to a poorer ally
	# A difficulty level (data/ai_difficulty.json) and then GameState.rules["ai"] override any
	# setting above (e.g. a passive tutorial opponent):
	"passive": false,               # never goes after rival players' heroes, towns or mines
	"builds": true,                 # constructs buildings
	"recruits": true,               # recruits creatures
	"battle_orders": true,          # gives battle orders (stance, focus, formation, art timing) suited to the armies
	"casts_spells": true,           # casts hero spells on the adventure map
	"upgrades": true,               # upgrades stacks in towns with upgrade buildings
	"trades_at_sites": true,        # buys artifacts and maps from road traders
	"ally_gifts": true,             # sends spare resources to allies that need them
	"reads_invasions": true,        # plans with announced invasion waves and marching invaders
	"invasion_margin": 1.5,         # invasion armies count this much more than their troops (commander stats, siege)
	"chase_rate": 0.5,              # an enemy hero out of today's reach is worth this share (it moves away)
	"sorties": true,                # a hero in a town in danger takes the whole garrison out to beat a nearby enemy hero
	"screen_width": 1.0,            # quick-forecast this many x forecasts_per_decision fights first (above 1: drop the clearly lost ones)
	"screen_margin": 0.25,          # ... a quick forecast this far below min_win_probability drops the fight
	"guarded_captures": true,       # takes a town only if a stronger enemy hero cannot retake it tomorrow (or it ends the rival)
}

var session: GameSession
var data: GameData
var player: int
var settings: Dictionary
var battle_handler: Callable
var actions: Array[String] = []   # human-readable log of this turn's decisions

var _forecasts := {}
var _recruited := 0
var _threats := {}   # town id -> strongest enemy army that can strike it next turn
var _danger := {}    # town id -> strongest enemy army within danger_days
var _reach := []     # enemy heroes: [{field, move, strength}] for one day's walk
var _home_guard := 0.0   # assumed strength of an enemy hero we cannot see (all our troops at turn start)
var _report := {}        # this turn's report (counters for upgrades, spells, purchases, gifts)
var _sortie := {}        # a target chosen by _try_sortie for the hero's next step
var _reserved := {}      # town id -> true: kept free for the main hero coming to defend it


func _init(game_session: GameSession, player_idx: int, overrides: Dictionary = {}) -> void:
	session = game_session
	data = session.data
	player = player_idx
	settings = DEFAULT_SETTINGS.duplicate()
	# The player's difficulty level, then the game's rules (a campaign chapter's
	# "ai"), then the caller's overrides.
	settings.merge(data.difficulty(session.difficulty_of(player)).get("ai", {}), true)
	settings.merge(session.state.rules.get("ai", {}), true)
	settings.merge(overrides, true)


## Lets every computer player act until a human is to move or the game ends.
## Returns the number of AI turns played. max_turns guards headless runs.
static func play_ai_turns(game_session: GameSession, max_turns: int = 64) -> int:
	var played := 0
	while played < max_turns and not game_session.state.game_over:
		var p := game_session.current_player()
		if p["is_human"] or p["defeated"]:
			break
		StrategicAI.new(game_session, game_session.state.current_player).play_turn()
		game_session.end_turn()
		played += 1
	return played


## Plays the current player's turn (does not end it). Returns
## {actions: [String], battles: int, builds: int, recruits: int, hires: int,
## upgrades: int, spells: int, purchases: int, gifts: int}.
func play_turn() -> Dictionary:
	var report := _new_report()
	if session.state.game_over or session.state.current_player != player:
		return report
	if WaveDirector.invasion_player(session.state, player):
		for h in _own_heroes():
			if WaveDirector.has_order(session.state, h.id):
				report["battles"] += WaveDirector.play_order(session, h)
		return report
	_begin_turn(report)
	for h in _own_heroes():
		report["battles"] += _run_hero(h, report)
	_finish_turn(report)
	return report


## As play_turn, but battles against a human player go through battle_handler
## (the live battle view), which is awaited.
func play_turn_interactive() -> Dictionary:
	var report := _new_report()
	if session.state.game_over or session.state.current_player != player:
		return report
	if WaveDirector.invasion_player(session.state, player):
		for h in _own_heroes():
			if WaveDirector.has_order(session.state, h.id):
				report["battles"] += await WaveDirector.play_order_interactive(session, h, battle_handler)
		return report
	_begin_turn(report)
	for h in _own_heroes():
		report["battles"] += await _run_hero_interactive(h, report)
	_finish_turn(report)
	return report


func _new_report() -> Dictionary:
	return {"actions": actions, "battles": 0, "builds": 0, "recruits": 0, "hires": 0,
		"upgrades": 0, "spells": 0, "purchases": 0, "gifts": 0}


## Phase 1: threats, buildings and hires.
func _begin_turn(report: Dictionary) -> void:
	_report = report
	_home_guard = 0.0
	for h in _own_heroes():
		_home_guard += army_value(h.army)
	for t in _own_towns():
		_home_guard += army_value(Town.garrison(t))
	_compute_threats()
	_reserved = {}
	_recruited = 0
	for t in _own_towns():
		# Without a hero nothing can be taken back: a new hero comes before buildings.
		if _own_heroes().is_empty() and _maybe_hire(t):
			report["hires"] += 1
		if not _saving_for_hero() and _build_best(t):
			report["builds"] += 1
		# A hero hired now would stand on the town's tile and lock out the main
		# hero coming home to defend it; hire after the heroes have moved.
		if (not is_threatened(t["id"]) or _own_heroes().is_empty()) and _maybe_hire(t):
			report["hires"] += 1


## Phase 3: standing orders and spells, recruits, upgrades, hires, gifts.
func _finish_turn(report: Dictionary) -> void:
	for h in _own_heroes():
		_give_orders(h, [])   # standing orders for being attacked
		_standing_spell(h)
	for t in _own_towns():
		if not _saving_for_hero():
			_recruit_all(t, true)
			_upgrade_stacks(t)
		if _maybe_hire(t):
			report["hires"] += 1
	_support_allies()
	report["recruits"] = _recruited


func _note(text: String) -> void:
	actions.append(text)


func _own_heroes() -> Array:
	var hs := session.state.heroes_of(player)
	hs.sort_custom(func(a, b): return a.id < b.id)
	return hs


func _own_towns() -> Array:
	var ts := session.towns_of(player)
	ts.sort_custom(func(a, b): return a["id"] < b["id"])
	return ts


func _bank() -> ResourceBank:
	return session.state.player(player)["resources"]


func _sorted_object_ids() -> Array:
	var ids := session.state.map.objects.keys()
	ids.sort()
	return ids


# ------------------------------------------------------------ valuations --

func resource_value(res: String) -> float:
	return float(data.economy["market"]["values"].get(res, 0))


func bundle_value(bundle: Dictionary) -> float:
	var v := 0.0
	for res in bundle:
		v += float(bundle[res]) * resource_value(res)
	return v


func creature_value(creature_id: String) -> float:
	return bundle_value(data.creature(creature_id).get("cost", {}))


## Gold-equivalent value of [{creature, count}] stacks: a cheap strength proxy
## (creature costs are calibrated by combat power per gold).
func stacks_value(stacks: Array) -> float:
	var v := 0.0
	for st in stacks:
		v += stack_value(st)
	return v


func stack_value(stack: Dictionary) -> float:
	if stack.is_empty():
		return 0.0
	var base := data.creature(stack["creature"])
	var ranked := Army.creature_stats(stack, data)
	var health := float(ranked["hp"]) / float(base["hp"])
	var damage := float(ranked["damage"][0] + ranked["damage"][1]) / float(base["damage"][0] + base["damage"][1])
	var offense := (1.0 + 0.05 * int(ranked["attack"])) / (1.0 + 0.05 * int(base["attack"]))
	var defense := (1.0 + 0.05 * int(ranked["defense"])) / (1.0 + 0.05 * int(base["defense"]))
	return int(stack["count"]) * creature_value(stack["creature"]) * sqrt(health * damage * offense * defense)


## What picking up an artifact is worth to this hero: its gain over what the
## hero wears in that slot, a little if it can only be carried, nothing if the
## pack is full.
func artifact_value(h: Hero, artifact_id: String) -> float:
	if not data.artifacts.has(artifact_id):
		return 0.0
	var a: Dictionary = data.artifacts[artifact_id]
	var worn := String(h.equipment.get(a["slot"], ""))
	var spare := float(a["value"]) * float(settings["spare_artifact_rate"])
	if worn == "":
		return float(a["value"]) * float(settings["artifact_value_rate"])
	if h.pack.size() >= int(data.artifact_rules["pack_size"]):
		return 0.0
	var gain := float(int(a["value"]) - int(data.artifacts[worn]["value"])) * float(settings["artifact_value_rate"])
	return maxf(gain, spare)


## Wears the most valuable artifact the hero carries for each slot (ties keep
## what is worn). Returns how many artifacts were swapped in.
func equip_best(h: Hero) -> int:
	var swaps := 0
	for slot in data.artifact_slots:
		var best := String(h.equipment.get(slot, ""))
		var best_value := int(data.artifacts[best]["value"]) if best != "" else -1
		for aid in h.pack:
			if String(data.artifacts[aid]["slot"]) == slot and int(data.artifacts[aid]["value"]) > best_value:
				best = aid
				best_value = int(data.artifacts[aid]["value"])
		if best != "" and h.pack.has(best) and session.equip_artifact(h.id, best)["ok"]:
			swaps += 1
	return swaps


func army_value(army: Army) -> float:
	return stacks_value(army.to_combat_stacks())


## Strength of whatever defends this map object, walls and a defending hero included.
func defender_value(obj: Dictionary) -> float:
	if MapCobolts.is_post(obj, data):
		return 0.0 # No military estimate without observing the post.
	# A pickup or mine next to a neutral army: that army is what must be beaten.
	var guard := session.claim_guard(obj, player)
	if not guard.is_empty():
		return defender_value(guard)
	match obj["type"]:
		"town":
			var walls := Town.defense_bonus(obj, data)
			var value := army_value(Town.garrison(obj))
			var foe := session.town_defender(obj)
			if foe != null:
				value += army_value(foe.army)
				walls += foe.defense
			return value * (1.0 + 0.05 * walls)
		"mine", "site":
			return stacks_value(GameSession._pairs_to_stacks(obj.get("guard", [])))
		"neutral_army":
			return stacks_value(GameSession._pairs_to_stacks(obj.get("stacks", [])))
	return 0.0


# ---------------------------------------------------------------- threats --

## Looks at every visible enemy hero and how far it could walk. A town is in
## danger if an enemy army can reach it within danger_days, and threatened if
## one can reach it within threat_days and is stronger than the garrison.
## Fills _danger and _threats (town id -> strongest enemy army value).
func _compute_threats() -> void:
	_threats = {}
	_danger = {}
	_reach = []
	var towns := _own_towns()
	var fog: FogOfWar = session.state.player(player)["fog"]
	var ids := session.state.heroes.keys()
	ids.sort()
	for id in ids:
		var e: Hero = session.state.heroes[id]
		if not e.alive or session.allied(e.owner, player) or not fog.is_explored(e.pos) or e.army.is_empty():
			continue
		var move := e.max_movement(data)
		var blocked := {}
		for oid in _sorted_object_ids():
			var o: Dictionary = session.state.map.objects[oid]
			if session.is_guarded(o, e.owner) or session.is_allied_town(o, e.owner):
				blocked[AdventureMap.object_pos(o)] = true
		var field := AiDistanceField.build(session.state.map, e.pos, blocked, int(move * float(settings["danger_days"])))
		var strength := army_value(e.army)
		_reach.append({"field": field, "move": move, "strength": strength * (1.0 + 0.05 * e.defense), "seen": true})
		for t in towns:
			var cost := field.cost_to(AdventureMap.object_pos(t))
			if cost == AiDistanceField.UNREACHABLE or cost > int(move * float(settings["danger_days"])):
				continue
			_danger[t["id"]] = maxf(float(_danger.get(t["id"], 0.0)), strength)
			if cost <= int(move * float(settings["threat_days"])) and strength > garrison_defense(t):
				_threats[t["id"]] = maxf(float(_threats.get(t["id"], 0.0)), strength)
	_add_unseen_heroes(fog)
	_add_invasion_threats()


## Scenario invasions aimed at our towns. The warning news names the day, the
## entry and the army of every wave, and an invader on the map marches on its
## ordered target, so the AI plans with both exactly as a reader of the news
## would: a town an announced wave or a marching invader will strike is in
## danger (its garrison stays), and threatened (the main hero comes home)
## once the hero needs the time that is left to get there.
func _add_invasion_threats() -> void:
	var st := session.state
	if not ScenarioRules.active(st) or not bool(settings["reads_invasions"]):
		return
	var towns := {}
	for t in _own_towns():
		towns[t["id"]] = t
	if towns.is_empty():
		return
	var runtime: Dictionary = st.scenario_runtime
	var main := main_hero()
	var home: AiDistanceField = null
	if main != null:
		home = AiDistanceField.build(st.map, main.pos, _blocked_for(main))
	for wave in WaveDirector.waves(st):
		var id := String(wave["id"])
		if not runtime.get("warned", []).has(id) or runtime.get("spawned", []).has(id):
			continue
		var t: Dictionary = towns.get(String(wave["target"]), {})
		if t.is_empty():
			continue
		var strength := stacks_value(GameSession._pairs_to_stacks(WaveDirector.scaled_army(session, wave)))
		var days_left := int(wave["day"]) - st.day
		_mark_invasion(t, strength, days_left <= _days_home(main, home, t) + 1)
	var ids := st.heroes.keys()
	ids.sort()
	for hid in ids:
		var e: Hero = st.heroes[hid]
		if not e.alive or session.allied(e.owner, player) or not WaveDirector.has_order(st, e.id) or e.army.is_empty():
			continue
		var order: Dictionary = runtime["orders"][e.id]
		if String(order.get("kind", "assault")) in ["defend", "escort"]:
			continue
		var goal := WaveDirector._order_target(session, e, order)
		var t: Dictionary = {}
		for tid in towns:
			if AdventureMap.object_pos(towns[tid]) == goal:
				t = towns[tid]
		if t.is_empty():
			continue
		var strength := army_value(e.army) * (1.0 + 0.05 * e.defense)
		var blocked := {}
		var field := AiDistanceField.build(st.map, e.pos, blocked)
		var cost := field.cost_to(goal)
		var days_away := 1 if cost == AiDistanceField.UNREACHABLE else int(ceil(float(cost) / float(maxi(1, e.max_movement(data)))))
		_mark_invasion(t, strength, days_away <= _days_home(main, home, t) + 1)


func _mark_invasion(t: Dictionary, raw: float, imminent: bool) -> void:
	# Invasion commanders bring siege-hardened stats the troop value misses.
	var strength := raw * float(settings["invasion_margin"])
	_danger[t["id"]] = maxf(float(_danger.get(t["id"], 0.0)), strength)
	if imminent and strength > garrison_defense(t):
		_threats[t["id"]] = maxf(float(_threats.get(t["id"], 0.0)), strength)


## Whole days the main hero needs to stand in town t (0 if it is there).
func _days_home(main: Hero, field: AiDistanceField, t: Dictionary) -> int:
	if main == null or field == null:
		return 0
	var p := AdventureMap.object_pos(t)
	if p == main.pos:
		return 0
	var cost := field.cost_to(p)
	if cost == AiDistanceField.UNREACHABLE:
		return 0
	return int(ceil(float(cost) / float(maxi(1, main.max_movement(data)))))


## An enemy hero out of sight may be back home tomorrow. Without peeking at
## it, assume the rival is our match (as strong as all our troops at the
## start of the turn) and could stand in any enemy town we know of: a hero weakened today must
## not stop next to that town (best_target), unless it takes the town today.
func _add_unseen_heroes(fog: FogOfWar) -> void:
	if _home_guard <= 0.0:
		return
	var players := {}
	var ids := session.state.heroes.keys()
	ids.sort()
	for id in ids:
		var e: Hero = session.state.heroes[id]
		if e.alive and not session.allied(e.owner, player) and not fog.is_explored(e.pos):
			players[e.owner] = true
	var main := main_hero()
	if players.is_empty() or main == null:
		return
	var move := main.max_movement(data)
	for oid in _sorted_object_ids():
		var t: Dictionary = session.state.map.objects[oid]
		if t["type"] != "town" or not players.has(int(t["owner"])):
			continue
		var p := AdventureMap.object_pos(t)
		if not fog.is_explored(p):
			continue
		var blocked := {}
		for bid in _sorted_object_ids():
			var o: Dictionary = session.state.map.objects[bid]
			if session.is_guarded(o, int(t["owner"])) or session.is_allied_town(o, int(t["owner"])):
				blocked[AdventureMap.object_pos(o)] = true
		var field := AiDistanceField.build(session.state.map, p, blocked, move)
		_reach.append({"field": field, "move": move, "strength": _home_guard, "seen": false})


## What holds a town without its visiting hero: garrison and walls. A hero
## standing in town does not count, or it would see no threat, march off and
## leave the town empty for the enemy.
func garrison_defense(t: Dictionary) -> float:
	return army_value(Town.garrison(t)) * (1.0 + 0.05 * Town.defense_bonus(t, data))


## A secondary hero standing in a threatened town blocks the tile for the
## main hero, which could hold the town where the secondary cannot. If the
## main hero can walk next to the town today, the secondary leaves its troops
## in the garrison and steps out, and the main hero walks in (the town then
## stays free of other heroes this turn). Returns true if the main hero is in.
func _relieve_town(h: Hero) -> bool:
	if h != main_hero() or _threats.is_empty() or _owned_town_at(h.pos):
		return false
	var field := AiDistanceField.build(session.state.map, h.pos, _blocked_for(h))
	for t in _own_towns():
		var p := AdventureMap.object_pos(t)
		var other := session.state.hero_at(p)
		if not is_threatened(t["id"]) or other == null or other == h or other.owner != player or other.movement_left <= 0:
			continue
		var cost := field.cost_to(p)
		if cost == AiDistanceField.UNREACHABLE or cost > h.movement_left or not can_hold_with(t, h):
			continue
		var gate := _free_neighbour(p, h)
		if gate.x < 0:
			continue
		session.move_hero(h.id, gate)
		if h.pos != gate or h.movement_left <= 0:
			continue
		var aside := _free_neighbour(p, other)
		if aside.x < 0:
			continue
		_garrison_army(t, other)
		session.move_hero(other.id, aside)
		if other.pos == p:
			continue
		_reserved[t["id"]] = true
		session.move_hero(h.id, p)
		if h.pos == p:
			_note("%s makes way in %s for %s." % [other.name, t["name"], h.name])
			return true
	return false


## The free tile next to p that hero h reaches most cheaply today, or (-1, -1).
func _free_neighbour(p: Vector2i, h: Hero) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_cost := 0
	for off in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var q: Vector2i = p + off
		if q == h.pos:
			return q
		if not session.state.map.in_bounds(q) or not session.state.map.is_passable(q) \
				or session.state.hero_at(q) != null or not session.state.map.object_at(q).is_empty():
			continue
		var route := session.plan_path(h.id, q)
		if route["path"].is_empty() or int(route["total_cost"]) >= h.movement_left:
			continue
		if best.x < 0 or int(route["total_cost"]) < best_cost:
			best = q
			best_cost = int(route["total_cost"])
	return best


## The threatened town this hero must guard, or {}: the main hero answers the
## nearest threatened town it can reach. While it guards, it takes no fight
## except against an enemy hero, and ends the turn in the town.
func town_to_guard(h: Hero, field: AiDistanceField) -> Dictionary:
	if h != main_hero():
		return {}
	var best := {}
	var best_cost := AiDistanceField.UNREACHABLE
	for t in _own_towns():
		if not is_threatened(t["id"]) or not can_hold_with(t, h):
			continue
		var p := AdventureMap.object_pos(t)
		var cost := 0 if p == h.pos else field.cost_to(p)
		var other := session.state.hero_at(p)
		if other != null and other != h:
			continue   # another of our heroes stands there (and stays: _manage_town)
		if cost != AiDistanceField.UNREACHABLE and (best.is_empty() or cost < best_cost):
			best = t
			best_cost = cost
	return best


## True if a visible enemy hero stronger than `strength` could reach this tile
## on its next turn: a hero that ends its turn there would be caught.
func exposed(p: Vector2i, strength: float, seen_only: bool = false) -> bool:
	for r in _reach:
		if float(r["strength"]) <= strength or (seen_only and not bool(r.get("seen", true))):
			continue
		var cost: int = (r["field"] as AiDistanceField).cost_to(p)
		if cost != AiDistanceField.UNREACHABLE and cost <= int(float(r["move"]) * float(settings["threat_days"])):
			return true
	return false


## True if this hero standing in the threatened town, with its garrison and
## walls, has a fair chance against the threat.
func can_hold_with(t: Dictionary, h: Hero) -> bool:
	var combined := garrison_defense(t) + army_value(h.army) * (1.0 + 0.05 * Town.defense_bonus(t, data))
	return combined >= float(_threats.get(t["id"], 0.0)) * 0.6


func in_danger(town_id: String) -> bool:
	return _danger.has(town_id)


func is_threatened(town_id: String) -> bool:
	return _threats.has(town_id)


# ------------------------------------------------------------------ towns --

## Value of a building to this player right now, in gold.
func building_value(t: Dictionary, building_id: String) -> float:
	var b := Town.building(t, building_id, data)
	var v := 0.0
	for e in b.get("effects", []):
		match e["type"]:
			"income":
				v += bundle_value(e["resources"]) * float(settings["income_horizon_days"])
			"dwelling":
				var c: String = e["creature"]
				v += float(data.creature(c).get("growth", 0)) * creature_value(c) * 1.5 + 400.0 * int(data.creature(c)["tier"])
			"growth":
				v += float(e["amount"]) * creature_value(e["creature"]) * 1.2
			"dwelling_upgrade":
				var base: String = e["creature"]
				var up := String(data.creature(base).get("upgrade", ""))
				v += float(Town.weekly_growth(t, base, data)) * maxf(0.0, creature_value(up) - creature_value(base)) * 0.6
			"growth_pct":
				var weekly := 0.0
				for c in Town.dwellings(t, data):
					weekly += float(Town.weekly_growth(t, c, data)) * creature_value(c)
				v += float(e["pct"]) * weekly * 1.2
			"defense":
				v += float(e["amount"]) * (1500.0 if is_threatened(t["id"]) else 350.0)
			"tavern":
				v += 1500.0 if session.state.heroes_of(player).size() < int(settings["max_heroes"]) else 200.0
			"market":
				v += 1200.0 if session.market_count(player) == 0 else 300.0
			"build_discount":
				v += 1200.0
			"battle_spoils":
				v += 1200.0
			"army_upgrade":
				v += army_upgrade_value(t)
	# Buildings that unlock others are worth a little more.
	for other in Town.building_ids(t, data):
		if not Town.has_building(t, other) and (Town.building(t, other, data).get("requires", []) as Array).has(building_id):
			v += 300.0
	return v


## Worth of a faction ultimate (army_upgrade) in this town: a share of the
## value of every creature of that faction the player fields now, plus a few
## weeks of the town's growth. Nothing if the player already has that faction's.
func army_upgrade_value(t: Dictionary) -> float:
	var fac := String(t["town_type"])
	if session.army_upgrades(player).has(fac):
		return 0.0
	var fielded := 0.0
	var armies := []
	for h in session.state.heroes_of(player):
		armies.append((h as Hero).army)
	for town in Economy.towns_of(session.state.map, player):
		armies.append(Town.garrison(town))
	for army in armies:
		for st in (army as Army).to_combat_stacks():
			if String(data.creature(String(st["creature"])).get("faction", "")) == fac:
				fielded += creature_value(String(st["creature"])) * int(st["count"])
	var weekly := 0.0
	for c in Town.dwellings(t, data):
		weekly += float(Town.weekly_growth(t, c, data)) * creature_value(c)
	return float(settings["army_upgrade_share"]) * (fielded + 3.0 * weekly)


func building_score(t: Dictionary, building_id: String) -> float:
	var cost := bundle_value(Town.build_cost(t, building_id, data))
	return building_value(t, building_id) / maxf(500.0, cost)


## Builds the best-scoring building, if any is affordable today. When the best
## building overall is blocked only by a missing non-gold resource and a market
## can supply it, trades gold for it first.
func _build_best(t: Dictionary) -> bool:
	if not bool(settings["builds"]):
		return false
	var best_id := ""
	var best := 0.0
	var wish_id := ""
	var wish := 0.0
	for opt in session.build_options(t["id"]):
		if opt["built"]:
			continue
		var reason: String = opt["reason"]
		if reason == "already built today":
			return false
		var s := building_score(t, opt["id"])
		if reason == "" and s > best:
			best = s
			best_id = opt["id"]
		elif reason == "not enough resources" and s > wish:
			wish = s
			wish_id = opt["id"]
	if wish_id != "" and wish > best * float(settings["trade_value_ratio"]) and _trade_for(Town.build_cost(t, wish_id, data)):
		best_id = wish_id
	if best_id == "":
		return false
	var r := session.build(t["id"], best_id)
	if r["ok"]:
		_note("%s builds %s." % [t["name"], Town.building(t, best_id, data)["name"]])
	return r["ok"]


## Buys the missing non-gold resources for a cost with gold, if the player owns
## a market and can afford the whole thing afterwards. All or nothing.
func _trade_for(cost: Dictionary) -> bool:
	var markets := session.market_count(player)
	if markets == 0:
		return false
	var bank := _bank()
	var gold_needed := int(cost.get("gold", 0))
	var buys := {}
	for res in data.resource_order:
		if res == "gold" or not cost.has(res):
			continue
		var short := int(cost[res]) - bank.get_amount(res)
		if short > 0:
			var price := Economy.trade_price("gold", res, short, markets, data)
			if price < 0:
				return false
			buys[res] = price
			gold_needed += price
	if buys.is_empty() or bank.get_amount("gold") < gold_needed:
		return false
	for res in data.resource_order:
		if buys.has(res):
			var r := session.trade("gold", res, int(buys[res]))
			if not r["ok"]:
				return false
			_note("Trades %d gold for %d %s." % [int(buys[res]), int(r["received"]), data.resources[res]["name"]])
	return true


## Recruits as much as possible, best creatures first. Into the visiting hero
## unless to_garrison is set or the hero has no room. Returns creatures recruited.
func _recruit_all(t: Dictionary, to_garrison: bool) -> int:
	var total := 0
	if not bool(settings["recruits"]):
		return 0
	var opts := session.recruit_options(t["id"])
	opts.reverse()   # highest tier first
	for opt in opts:
		var n := session.max_recruitable(t["id"], opt["creature"])
		if n <= 0:
			continue
		var r := session.recruit(t["id"], opt["creature"], n, to_garrison)
		if not r["ok"] and not to_garrison:
			r = session.recruit(t["id"], opt["creature"], n, true)
		if r["ok"]:
			total += n
			_recruited += n
			_note("%s recruits %d %s (%s)." % [t["name"], n, data.creature(opt["creature"])["name"], r["to"]])
	return total


func _wanted_heroes() -> int:
	return mini(int(settings["max_heroes"]), 1 + _own_towns().size())


## True while the player has no hero but a town that could hire one: gold is
## then kept for the hire instead of being spent on buildings and recruits.
func _saving_for_hero() -> bool:
	if not _own_heroes().is_empty():
		return false
	for t in _own_towns():
		var why := session.can_hire_hero(t["id"])
		if why == "" or why == "not enough gold":
			return true
	return false


func _maybe_hire(t: Dictionary) -> bool:
	if session.state.heroes_of(player).size() >= _wanted_heroes():
		return false
	if session.can_hire_hero(t["id"]) != "":
		return false
	var cost := int(session.hire_cost(t["id"]).get("gold", 0))
	# Without a hero the player cannot take anything back: hire at any price.
	var reserve := 0 if session.state.heroes_of(player).is_empty() else int(settings["hire_reserve_gold"])
	if _bank().get_amount("gold") < cost + reserve:
		return false
	var r := session.hire_hero(t["id"])
	if r["ok"]:
		_note("%s hires %s." % [t["name"], session.hero(r["hero_id"]).name])
	return r["ok"]


## A hero standing in an own town: recruit and collect the garrison, or, if
## the town is threatened, leave the army as garrison. Returns true if the hero
## should stay put this turn.
func _manage_town(t: Dictionary, h: Hero) -> bool:
	_sortie = {}
	if in_danger(t["id"]) and _try_sortie(t, h):
		return false
	if is_threatened(t["id"]):
		_recruit_all(t, true)
		var combined := defender_value(t) + army_value(h.army) * (1.0 + 0.05 * Town.defense_bonus(t, data))
		if combined >= float(_threats[t["id"]]) * 0.8:
			_garrison_army(t, h)
			_note("%s garrisons %s against an attack." % [h.name, t["name"]])
			return true
		if can_hold_with(t, h):
			# Together with the garrison the hero may hold; out in the field the
			# town would fall and the hero be caught alone.
			_note("%s stays to defend %s." % [h.name, t["name"]])
			return true
		return false   # hopeless: the hero would only die with the town
	if h != main_hero():
		# Secondary heroes scout and collect; their troops reinforce the main army.
		_recruit_all(t, true)
		if h.army.stack_count() > 1:
			_garrison_army(t, h)
			_note("%s leaves troops in %s for the main army." % [h.name, t["name"]])
		return false
	_recruit_all(t, false)
	_consolidate(t, h)
	_upgrade_stacks(t, true)
	return false


## An enemy hero is near this town and today's walk can reach it: with the
## whole garrison behind it, can our hero beat it in the open? A garrison
## that only waits lets the enemy pick off every hero that leaves the town and
## take the mines and towns around it. The hero takes up the garrison's best
## stacks and, if the forecast is good, _sortie names the enemy as its next
## target; otherwise the troops go back. Returns true when the sortie is on.
func _try_sortie(t: Dictionary, h: Hero) -> bool:
	if not bool(settings["sorties"]) or bool(settings["passive"]) or Town.garrison(t).is_empty():
		return false
	var field := AiDistanceField.build(session.state.map, h.pos, _blocked_for(h), h.movement_left)
	var pool := army_value(h.army) + army_value(Town.garrison(t))
	var foes := _hero_targets(h, field, float(maxi(1, h.max_movement(data))), pool)
	foes = foes.filter(func(c): return int(c["cost"]) <= h.movement_left)
	if foes.is_empty():
		return false
	foes.sort_custom(func(a, b): return a["value"] > b["value"] or (a["value"] == b["value"] and a["id"] < b["id"]))
	var before := army_value(h.army)
	if _consolidate(t, h, true) == 0:
		return false
	for foe in foes:
		var pred: Dictionary = battle_plan(h, foe["id"])["pred"]
		if _fight_ok(pred):
			_sortie = foe
			_note("%s rides out of %s with the garrison against %s (forecast %d%%)." % [h.name, t["name"], foe["label"],
				int(round(float(pred["win_probability"]) * 100.0))])
			return true
	# No fight worth it: the garrison goes back, the hero keeps its own army.
	if army_value(h.army) > before:
		_garrison_army(t, h)
	return false


## Rebuilds the main hero's army slots from its own stacks and the garrison's
## spare ones: garrison stacks merge into matching or empty slots, and a stack
## stronger than the hero's weakest swaps places with it. Without the swap a
## hero with full slots could never take up the garrison's troops, and
## the strongest armies would idle in towns. Returns the number of transfers.
func _consolidate(t: Dictionary, h: Hero, every_slot: bool = false) -> int:
	var moved := 0
	var ref := GameSession.garrison_ref(t["id"])
	for _pass in Army.MAX_SLOTS * 3:
		var g := Town.garrison(t)
		var spare := _all_slots(g) if every_slot else spare_garrison_slots(t)
		spare.sort_custom(func(a, b):
			var va := _slot_value(g, a, h)
			var vb := _slot_value(g, b, h)
			return va > vb or (va == vb and a < b))
		var done := false
		for i in spare:
			var to := _slot_for(h.army, String(g.slots[i]["creature"]), _slot_value(g, i, h), Army.veteran_level(g.slots[i]), h)
			if to < 0:
				continue
			var r := session.transfer_stack(ref, i, h.id, to)
			if r["ok"]:
				moved += 1
				done = true
				break
		if not done:
			break
	if moved > 0:
		_note("%s gathers the strongest troops of %s." % [h.name, t["name"]])
	return moved


static func _all_slots(army: Army) -> Array[int]:
	var out: Array[int] = []
	for i in Army.MAX_SLOTS:
		if not army.slots[i].is_empty():
			out.append(i)
	return out


## A slot's value, raised for `h` when the stack is of the hero's specialty line.
func _slot_value(army: Army, i: int, h: Hero = null) -> float:
	var st: Dictionary = army.slots[i]
	if h == null or st.is_empty():
		return stack_value(st)
	return stack_value(st) * specialty_factor(h, String(st["creature"]))


## How much better a creature fights under this hero because of its personal
## specialty: 5% per point of line attack and defense (1.0 if none). Lets the
## AI gather and keep the troops its heroes specialise in.
func specialty_factor(h: Hero, creature_id: String) -> float:
	var mods := h.modifiers(data)
	if not mods.has("creature_attack") and not mods.has("creature_defense"):
		return 1.0
	var line := HeroSpecialties.line_of(creature_id, data.creature(creature_id))
	var pts := HeroModifiers.sub(mods, "creature_attack", line) + HeroModifiers.sub(mods, "creature_defense", line)
	return 1.0 + 0.05 * pts


## Where a stack of `creature` worth `value` goes in this army: the slot that
## already holds the creature, else an empty slot, else the weakest slot if it
## is worth less. -1 if the stack does not improve the army.
func _slot_for(army: Army, creature: String, value: float, level: int = 1, h: Hero = null) -> int:
	var empty := -1
	var weakest := -1
	for j in Army.MAX_SLOTS:
		var st: Dictionary = army.slots[j]
		if st.is_empty():
			if empty < 0:
				empty = j
		elif st["creature"] == creature and Army.veteran_level(st) == level:
			return j
		elif weakest < 0 or _slot_value(army, j, h) < _slot_value(army, weakest, h):
			weakest = j
	if empty >= 0:
		return empty
	return weakest if weakest >= 0 and _slot_value(army, weakest, h) < value else -1


## Garrison slots a hero may take along: all of them, unless an enemy is near,
## in which case enough stays behind to hold the town against it (walls count).
func spare_garrison_slots(t: Dictionary) -> Array[int]:
	var g := Town.garrison(t)
	var walls := 1.0 + 0.05 * Town.defense_bonus(t, data)
	var need := float(_danger.get(t["id"], 0.0)) * 1.25
	var remaining := army_value(g) * walls
	var order: Array[int] = []
	for i in Army.MAX_SLOTS:
		if not g.slots[i].is_empty():
			order.append(i)
	var value_of := func(i: int) -> float:
		return stack_value(g.slots[i]) * walls
	order.sort_custom(func(a, b): return value_of.call(a) > value_of.call(b) or (value_of.call(a) == value_of.call(b) and a < b))
	var out: Array[int] = []
	for i in order:
		var v: float = value_of.call(i)
		if need <= 0.0 or remaining - v >= need:
			out.append(i)
			remaining -= v
	out.sort()
	return out


## Leaves everything but the hero's weakest stack in the garrison.
func _garrison_army(t: Dictionary, h: Hero) -> void:
	var keep := -1
	var keep_value := INF
	for i in Army.MAX_SLOTS:
		var st: Dictionary = h.army.slots[i]
		if not st.is_empty():
			var v := float(st["count"]) * creature_value(st["creature"])
			if v < keep_value:
				keep_value = v
				keep = i
	for i in Army.MAX_SLOTS:
		if i != keep and not h.army.slots[i].is_empty():
			session.move_stack(t["id"], i, false)


## The hero with the strongest army (ties: lowest id). The other heroes feed
## their troops to it through the towns.
func main_hero() -> Hero:
	var best: Hero = null
	var best_value := -1.0
	for h in _own_heroes():
		var v := army_value(h.army)
		if v > best_value:
			best_value = v
			best = h
	return best


func _town_visit_value(t: Dictionary, h: Hero) -> float:
	if is_threatened(t["id"]):
		return float(settings["defend_value"])
	if h != main_hero():
		return 0.0
	# Only the best MAX_SLOTS kinds of hero, spare garrison and recruits count:
	# the visit is worth what it adds over the hero's current army.
	var pool := {}
	for st in h.army.slots:
		if not st.is_empty():
			pool[st["creature"]] = int(pool.get(st["creature"], 0)) + int(st["count"])
	var g := Town.garrison(t)
	for i in spare_garrison_slots(t):
		pool[g.slots[i]["creature"]] = int(pool.get(g.slots[i]["creature"], 0)) + int(g.slots[i]["count"])
	for opt in session.recruit_options(t["id"]):
		if int(opt["max"]) > 0:
			pool[opt["creature"]] = int(pool.get(opt["creature"], 0)) + int(opt["max"])
	var values: Array[float] = []
	var kinds := pool.keys()
	kinds.sort()
	for c in kinds:
		values.append(float(pool[c]) * creature_value(c))
	values.sort()
	values.reverse()
	var best := 0.0
	for k in mini(Army.MAX_SLOTS, values.size()):
		best += values[k]
	var v := best - army_value(h.army)
	# Only worth a trip if it adds a real share to the army.
	return v if v > 0.15 * army_value(h.army) else 0.0


# ----------------------------------------------------------------- heroes --

## Tiles the hero cannot walk through: neutral armies, guarded objects, other heroes.
func _blocked_for(h: Hero) -> Dictionary:
	var out := {}
	for id in _sorted_object_ids():
		var o: Dictionary = session.state.map.objects[id]
		if session.is_guarded(o, player) or session.is_allied_town(o, player):
			out[AdventureMap.object_pos(o)] = true
	for p in session.state.map.blocking_positions():
		out[p] = true
	for id in session.state.heroes:
		var other: Hero = session.state.heroes[id]
		if other.alive and other != h:
			out[other.pos] = true
	return out


func _run_hero(h: Hero, report: Dictionary) -> int:
	if WaveDirector.has_order(session.state, h.id):
		return WaveDirector.play_order(session, h)
	var battles := 0
	var skip := {}
	_spend_skill_points(h)
	equip_best(h)
	_teleport_to_defend(h)
	_relieve_town(h)
	for _i in int(settings["max_actions_per_hero"]):
		if not h.alive or session.state.game_over or h.movement_left <= 0:
			break
		var here := session.state.map.object_at(h.pos)
		var choice := best_target(h, skip, true)
		if not here.is_empty() and here["type"] == "town" and int(here["owner"]) == player:
			# Striking the threatening hero today beats waiting for it behind the walls.
			var hunt: bool = is_threatened(here["id"]) and not choice.is_empty() and choice["kind"] == "hero"
			if not hunt and _manage_town(here, h):
				break
			if not hunt:
				choice = best_target(h, skip, true)   # the army may have changed
			if not _sortie.is_empty():
				choice = _sortie
				_sortie = {}
		if choice.is_empty():
			break
		if float(choice.get("days", 0.0)) > 1.0 and _take_deep_road(h, choice["pos"]):
			break
		var target: Vector2i = choice["pos"]
		var r := session.move_hero(h.id, target)
		if not r["captured"].is_empty():
			_compute_threats()   # a new town may need defending
		for got in r["collected"]:
			if got["type"] == "artifact":
				equip_best(h)
		if r["site"] != "":
			_recruit_at_site(h, r["site"])
			_shop_at_trader(h, r["site"])
		if r["encounter"] != "":
			if not _handle_encounter(h, r["encounter"]):
				skip[choice["id"]] = true
			_spend_skill_points(h)
			equip_best(h)
			continue
		if r["battle"] != "":
			var plan := battle_plan(h, r["battle"])
			var pred: Dictionary = plan["pred"]
			if _fight_ok(pred, is_decisive(r["battle"])):
				_cast(h, plan["spell"])
				var res := session.attack(h.id, r["battle"])
				battles += 1
				if res["winner"] == 0:
					_compute_threats()
					var won := session.state.map.object_at(h.pos)
					if not won.is_empty() and won["type"] == "site":
						_recruit_at_site(h, won["id"])
				_spend_skill_points(h)
				_note("%s attacks %s (forecast %d%%): %s." % [h.name, choice["label"],
					int(round(float(pred["win_probability"]) * 100.0)), "victory" if res["winner"] == 0 else "defeat"])
			else:
				skip[choice["id"]] = true
			continue
		if r["steps"].is_empty():
			skip[choice["id"]] = true
			continue
		_note("%s heads for %s." % [h.name, choice["label"]])
		if h.pos != target:
			if _cast_for_movement(h, target):
				continue
			break   # out of movement for today
		if choice["kind"] == "explore":
			skip[choice["id"]] = true
	return battles



func _run_hero_interactive(h: Hero, report: Dictionary) -> int:
	if WaveDirector.has_order(session.state, h.id):
		return await WaveDirector.play_order_interactive(session, h, battle_handler)
	var battles := 0
	var skip := {}
	_spend_skill_points(h)
	equip_best(h)
	_teleport_to_defend(h)
	_relieve_town(h)
	for _i in int(settings["max_actions_per_hero"]):
		if not h.alive or session.state.game_over or h.movement_left <= 0:
			break
		var here := session.state.map.object_at(h.pos)
		var choice := best_target(h, skip, true)
		if not here.is_empty() and here["type"] == "town" and int(here["owner"]) == player:
			# Striking the threatening hero today beats waiting for it behind the walls.
			var hunt: bool = is_threatened(here["id"]) and not choice.is_empty() and choice["kind"] == "hero"
			if not hunt and _manage_town(here, h):
				break
			if not hunt:
				choice = best_target(h, skip, true)   # the army may have changed
			if not _sortie.is_empty():
				choice = _sortie
				_sortie = {}
		if choice.is_empty():
			break
		if float(choice.get("days", 0.0)) > 1.0 and _take_deep_road(h, choice["pos"]):
			break
		var target: Vector2i = choice["pos"]
		var r := session.move_hero(h.id, target)
		if not r["captured"].is_empty():
			_compute_threats()   # a new town may need defending
		for got in r["collected"]:
			if got["type"] == "artifact":
				equip_best(h)
		if r["site"] != "":
			_recruit_at_site(h, r["site"])
			_shop_at_trader(h, r["site"])
		if r["encounter"] != "":
			if not _handle_encounter(h, r["encounter"]):
				skip[choice["id"]] = true
			_spend_skill_points(h)
			equip_best(h)
			continue
		if r["battle"] != "":
			var plan := battle_plan(h, r["battle"])
			var pred: Dictionary = plan["pred"]
			if _fight_ok(pred, is_decisive(r["battle"])):
				_cast(h, plan["spell"])
				var tgt := session.battle_target(r["battle"])
				var defender: Hero = tgt["hero"]
				var owner := defender.owner if defender != null else int(tgt["object"].get("owner", -1))
				var res: Dictionary
				if battle_handler.is_valid() and owner >= 0 and session.state.player(owner)["is_human"]:
					res = await battle_handler.call(h.id, r["battle"])
				else:
					res = session.attack(h.id, r["battle"])
				battles += 1
				if res["winner"] == 0:
					_compute_threats()
					var won := session.state.map.object_at(h.pos)
					if not won.is_empty() and won["type"] == "site":
						_recruit_at_site(h, won["id"])
				_spend_skill_points(h)
				_note("%s attacks %s (forecast %d%%): %s." % [h.name, choice["label"],
					int(round(float(pred["win_probability"]) * 100.0)), "victory" if res["winner"] == 0 else "defeat"])
			else:
				skip[choice["id"]] = true
			continue
		if r["steps"].is_empty():
			skip[choice["id"]] = true
			continue
		_note("%s heads for %s." % [h.name, choice["label"]])
		if h.pos != target:
			if _cast_for_movement(h, target):
				continue
			break   # out of movement for today
		if choice["kind"] == "explore":
			skip[choice["id"]] = true
	return battles


## The best thing for this hero to do next:
## {id, kind, pos, label, value, cost, utility} or {} if nothing is worth it.
func best_target(h: Hero, skip: Dictionary = {}, guard_home: bool = false) -> Dictionary:
	var field := AiDistanceField.build(session.state.map, h.pos, _blocked_for(h))
	var cands := candidate_targets(h, field)
	var guard := town_to_guard(h, field) if guard_home else {}
	if not guard.is_empty():
		# Home first: only the town itself, or an enemy hero within today's reach.
		cands = cands.filter(func(c): return c["id"] == guard["id"] \
			or (c["kind"] == "hero" and int(c["cost"]) <= h.movement_left))
	var best := {}
	var forecasts_left := int(settings["forecasts_per_decision"])
	var hero_value := army_value(h.army)
	cands.sort_custom(func(a, b):
		return a["utility"] > b["utility"] or (a["utility"] == b["utility"] and a["id"] < b["id"]))
	var hopeless := _screen_fights(h, cands, skip)
	for c in cands:
		if skip.has(c["id"]) or hopeless.has(c["id"]):
			continue
		if not best.is_empty() and c["utility"] <= best["utility"]:
			break   # sorted by optimistic utility: nothing later can win
		if c["guarded"]:
			if forecasts_left <= 0:
				continue
			forecasts_left -= 1
			var pred: Dictionary = battle_plan(h, c["id"])["pred"]
			var decisive := is_decisive(c["id"])
			if not _fight_ok(pred, decisive):
				continue
			var loss := 0.0 if decisive else float(pred["expected_loss_fraction"]) * hero_value * float(settings["loss_weight"])
			c["utility"] = (float(c["value"]) * float(pred["win_probability"]) - loss) / (1.0 + float(c["days"]))
			c["win_probability"] = pred["win_probability"]
			c["loss_fraction"] = pred["expected_loss_fraction"]
			if c["utility"] <= 0.0:
				continue
		if c["kind"] != "hero" and not (c["kind"] == "town" and (_owned_town_at(c["pos"]) or int(c["cost"]) <= h.movement_left)) \
				and exposed(c["pos"], hero_value * (1.0 - float(c.get("loss_fraction", 0.0)))):
			continue   # a stronger enemy hero would catch us there tomorrow
		if c["kind"] == "town" and not _owned_town_at(c["pos"]) and bool(settings["guarded_captures"]) \
				and not is_decisive(c["id"]) and _retaken(c, hero_value):
			continue   # we would only hold the town for a night
		if best.is_empty() or c["utility"] > best["utility"]:
			best = c
	return best


## True if a stronger visible enemy hero could reach town candidate c tomorrow
## and beat the hero that took it, walls included: the capture would cost the
## hero. Heroes out of sight do not count here (a town is worth the gamble).
func _retaken(c: Dictionary, hero_value: float) -> bool:
	var o: Dictionary = session.state.map.objects.get(c["id"], {})
	if o.is_empty():
		return false
	var held := hero_value * (1.0 - float(c.get("loss_fraction", 0.0))) * (1.0 + 0.05 * Town.defense_bonus(o, data))
	return exposed(c["pos"], held, true)


## Successive screening of the guarded candidates (a best-arm bandit): the
## top screen_width x forecasts_per_decision fights by optimistic utility get a
## quick forecast with a quarter of the simulations, and the ones that are
## clearly lost (win chance screen_margin below the bar) are dropped, so the
## full forecasts go to the fights that might be taken. Returns their ids.
func _screen_fights(h: Hero, cands: Array, skip: Dictionary) -> Dictionary:
	var out := {}
	var width := int(float(settings["forecasts_per_decision"]) * float(settings["screen_width"]))
	if width <= int(settings["forecasts_per_decision"]):
		return out
	var quick := maxi(8, int(settings["forecast_simulations"]) / 4)
	var bar := float(settings["min_win_probability"]) - float(settings["screen_margin"])
	for c in cands:
		if width <= 0:
			break
		if not c["guarded"] or skip.has(c["id"]):
			continue
		width -= 1
		if float(forecast(h, c["id"], quick)["win_probability"]) < bar:
			out[c["id"]] = true
	return out


func _owned_town_at(p: Vector2i) -> bool:
	var o := session.state.map.object_at(p)
	return not o.is_empty() and o["type"] == "town" and int(o["owner"]) == player


## Every target the player knows about that this hero can reach, with an
## optimistic utility (battles assumed free; best_target refines them).
func candidate_targets(h: Hero, field: AiDistanceField) -> Array:
	var out := []
	var fog: FogOfWar = session.state.player(player)["fog"]
	var hero_value := army_value(h.army)
	var move := float(maxi(1, h.max_movement(data)))
	for id in _sorted_object_ids():
		var o: Dictionary = session.state.map.objects[id]
		var p := AdventureMap.object_pos(o)
		if p == h.pos or not fog.is_explored(p):
			continue
		var cost := field.cost_to(p)
		if cost == AiDistanceField.UNREACHABLE:
			continue
		var other := session.state.hero_at(p)
		# An enemy hero standing on an object is fought as the hero (below),
		# except in its own town, which is a siege of the town.
		# An ally's hero blocks the tile.
		if other != null and other != h and other.owner != player \
				and (session.allied(other.owner, player) or not (o["type"] == "town" and int(o["owner"]) == other.owner)):
			continue
		var value := 0.0
		var label: String = o.get("name", id)
		var owner := int(o.get("owner", -1))
		# An ally's towns and mines are off limits.
		if owner >= 0 and owner != player and session.allied(owner, player) and o["type"] in ["town", "mine"]:
			continue
		if bool(settings["passive"]) and owner >= 0 and owner != player and o["type"] in ["town", "mine"]:
			continue
		match o["type"]:
			"resource":
				value = float(o["amount"]) * resource_value(o["resource"])
				label = "%d %s" % [int(o["amount"]), data.resources[o["resource"]]["name"]]
			"mine":
				if owner == player:
					continue
				value = float(Economy.mine_income(o, data)) * resource_value(o["resource"]) * float(settings["mine_horizon_days"])
				value += faction_capture_bonus(o)
				if owner >= 0:
					value *= float(settings["enemy_bonus"])
				label = Economy.mine_name(o, data)
			"town":
				if owner == player:
					if other != null or (_reserved.has(id) and h != main_hero()):
						continue
					value = _town_visit_value(o, h)
				else:
					value = float(settings["town_value"]) + bundle_value(Town.daily_income(o, data)) * float(settings["income_horizon_days"])
					value += faction_capture_bonus(o)
					if owner >= 0:
						value *= float(settings["enemy_bonus"])
					if other != null:
						value += float(settings["hero_kill_value"])
			"neutral_army":
				value = defender_value(o) * float(settings["neutral_value_rate"])
				value += harvest_value(h, o)
				value += bundle_value(RoamingThreats.bounty(o))   # a roaming horror's bounty
				var held: Dictionary = session.state.map.objects.get(String(o.get("guards", "")), {})
				if not held.is_empty() and held["type"] == "artifact":
					value += artifact_value(h, String(held["artifact"]))   # the pocket behind the guard
				elif not held.is_empty() and held["type"] == "resource":
					value += float(held["amount"]) * resource_value(held["resource"])
			"artifact":
				value = artifact_value(h, String(o["artifact"]))
				label = String(data.artifacts[o["artifact"]]["name"])
			"encounter":
				value = float(encounter_choice(h, id).get("value", 0.0))
				label = session.encounters.definition(o).get("name", "an encounter")
			"site":
				if bool(settings["passive"]) and owner >= 0 and owner != player:
					continue
				value = site_value(h, o)
				label = MapSites.site_name(o, data)
			_:
				continue
		if value <= 0.0:
			continue
		var guarded := session.is_guarded(o, player)
		if guarded and hero_value < defender_value(o) * float(settings["strength_prefilter"]):
			continue
		var days := float(cost) / move
		out.append({"id": id, "kind": o["type"], "pos": p, "label": label, "value": value, "cost": cost,
			"days": days, "guarded": guarded, "utility": value / (1.0 + days)})
	out.append_array(_hero_targets(h, field, move, hero_value))
	out.append_array(_explore_targets(h, field, move))
	return out


## What walking onto a map site is worth to this hero: a dwelling is worth
## its weekly troops for site_capture_weeks when someone else holds it, and its
## affordable pool when we hold it; other sites are worth their data "ai" value
## (flat + army_pct of the hero's army) or their XP, once per hero.
func site_value(h: Hero, o: Dictionary) -> float:
	if MapCobolts.is_post(o, data):
		# Week one's gold belongs to the towns: an AI that spends it on cobolts
		# snowballs into early capital rushes (twin_marches duels ending before
		# day 12 went from 3 to 9 in 40 seeds).
		if MapCobolts.access_error(o, player) != "" or session.state.day < int(settings["cobolt_from_day"]):
			return 0.0
		var offer: Dictionary = o["stock"][0]
		var cid := String(offer["creature"])
		if not bool(settings["recruits"]) or not GameSession._has_room(h.army, cid) or (session.tier_cap() > 0 and int(data.creature(cid)["tier"]) > session.tier_cap()):
			return 0.0
		var n := mini(int(offer["remaining"]), _bank().get_amount("gold") / int(data.creature(cid)["cost"]["gold"]))
		return float(n) * creature_value(cid) * float(settings["site_recruit_rate"])
	if MapSites.kind(o, data) == "village":
		return _village_value(h, o)
	if MapSites.kind(o, data) == "dwelling":
		var c := String(o["creature"])
		var cap := session.tier_cap()
		if cap > 0 and int(data.creature(c)["tier"]) > cap:
			return 0.0
		var site_owner := int(o.get("owner", -1))
		if site_owner != player and session.allied(site_owner, player):
			return 0.0   # an ally's dwelling: neither ours to take nor to recruit from
		if site_owner != player:
			var v := float(MapSites.weekly_growth(o, data)) * creature_value(c) * float(settings["site_capture_weeks"])
			return v * (float(settings["enemy_bonus"]) if int(o.get("owner", -1)) >= 0 else 1.0)
		if not bool(settings["recruits"]) or not GameSession._has_room(h.army, c):
			return 0.0
		var n := int(o["available"])
		var unit: Dictionary = data.creature(c).get("cost", {})
		for res in unit:
			if int(unit[res]) > 0:
				n = mini(n, _bank().get_amount(res) / int(unit[res]))
		return float(n) * creature_value(c) * float(settings["site_recruit_rate"])
	if MapSites.kind(o, data) == "trader":
		return trader_value(h, o) * float(settings["trader_visit_rate"])
	if MapSites.visit_block(h, o, data, session.state.day) != "":
		return 0.0
	var def := MapSites.definition(o, data)
	if String(def["kind"]) == "lore":
		return float(def["xp"]) * float(settings["xp_value"])
	var ai: Dictionary = def.get("ai", {})
	return float(ai.get("flat", 0)) + float(ai.get("army_pct", 0)) * army_value(h.army)


## A village frees once and sells its stock once: an unclaimed one is worth
## its whole stock (as a dwelling is worth its weeks of growth); one we hold
## is worth what the purse can buy now; anyone else's is worth nothing.
func _village_value(h: Hero, o: Dictionary) -> float:
	var site_owner := int(o.get("owner", -1))
	if site_owner >= 0 and site_owner != player:
		return 0.0
	var cap := session.tier_cap()
	var gold := _bank().get_amount("gold")
	var v := 0.0
	for pair in MapSites.offers(o, data):
		var c := String(pair[0])
		if cap > 0 and int(data.creature(c)["tier"]) > cap:
			continue
		var n := int(pair[1])
		if site_owner == player:
			if not bool(settings["recruits"]) or not GameSession._has_room(h.army, c):
				continue
			var price := int(data.creature(c).get("cost", {}).get("gold", 0))
			if price > 0:
				n = mini(n, gold / price)
				gold -= n * price
			v += float(n) * creature_value(c) * float(settings["site_recruit_rate"])
		else:
			v += float(n) * creature_value(c)
	return v


## Standing on a dwelling or village site we hold: recruit what the purse allows,
## offer by offer.
func _recruit_at_site(h: Hero, site_id: String) -> void:
	if not bool(settings["recruits"]):
		return
	if session.is_cobolt_target(site_id):
		var obj: Dictionary = session.state.map.objects[site_id]
		if MapCobolts.access_error(obj, h.owner) != "":
			return
		var offer: Dictionary = obj["stock"][0]
		var n := mini(int(offer["remaining"]), _bank().get_amount("gold") / int(data.creature(offer["creature"])["cost"]["gold"]))
		if n > 0 and session.cobolt_buy(site_id, h.id, 0, n)["ok"]:
			_recruited += n
		return
	var info := session.site_info(site_id, h.id)
	if not MapSites.RECRUIT_KINDS.has(String(info.get("kind", ""))):
		return
	for offer in info.get("offers", []):
		var c := String(offer["creature"])
		var n := session.max_site_recruitable(site_id, h.id, c)
		if n > 0 and session.site_recruit(site_id, h.id, n, c)["ok"]:
			_recruited += n
			_note("%s recruits %d %s at the %s." % [h.name, n, data.creature(c)["name"], info["name"]])


## Visible enemy heroes outside their towns (inside, the town is the target).
## Beating one removes a rival's army and hero: worth its troops plus a bonus.
func _hero_targets(h: Hero, field: AiDistanceField, move: float, hero_value: float) -> Array:
	var out := []
	if bool(settings["passive"]):
		return out
	var fog: FogOfWar = session.state.player(player)["fog"]
	var ids := session.state.heroes.keys()
	ids.sort()
	for id in ids:
		var e: Hero = session.state.heroes[id]
		if not e.alive or session.allied(e.owner, player) or not fog.is_explored(e.pos):
			continue
		if session.battle_target(e.id).get("kind", "") != "hero":
			continue
		var cost := field.cost_to(e.pos)
		if cost == AiDistanceField.UNREACHABLE:
			continue
		var strength := army_value(e.army) * (1.0 + 0.05 * e.defense)
		if hero_value < strength * float(settings["strength_prefilter"]):
			continue
		var value := (army_value(e.army) * float(settings["neutral_value_rate"]) + float(settings["hero_kill_value"])) \
			* float(settings["enemy_bonus"])
		if cost > h.movement_left:
			value *= float(settings["chase_rate"])   # it will not wait for us
		var days := float(cost) / move
		out.append({"id": e.id, "kind": "hero", "pos": e.pos, "label": e.name, "value": value, "cost": cost,
			"days": days, "guarded": true, "utility": value / (1.0 + days)})
	return out


## Reachable explored tiles next to unexplored ones, valued by how much they reveal.
func _explore_targets(h: Hero, field: AiDistanceField, move: float) -> Array:
	var map := session.state.map
	var fog: FogOfWar = session.state.player(player)["fog"]
	var radius := maxi(1, h.vision_radius(data))
	var best := {}
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var cost := field.cost_to(p)
			if cost <= 0 or not fog.is_explored(p) or not map.object_at(p).is_empty() or session.state.hero_at(p) != null:
				continue
			if not _next_to_unexplored(fog, map, p):
				continue
			var hidden := 0
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var q := p + Vector2i(dx, dy)
					if map.in_bounds(q) and dx * dx + dy * dy <= radius * radius and not fog.is_explored(q):
						hidden += 1
			var value := float(hidden) * float(settings["explore_value_per_tile"])
			var days := float(cost) / move
			var u := value / (1.0 + days)
			if best.is_empty() or u > best["utility"]:
				best = {"id": "explore_%d_%d" % [x, y], "kind": "explore", "pos": p, "label": "the unknown at %d,%d" % [x, y],
					"value": value, "cost": cost, "days": days, "guarded": false, "utility": u}
	return [] if best.is_empty() else [best]


static func _next_to_unexplored(fog: FogOfWar, map: AdventureMap, p: Vector2i) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var q := p + Vector2i(dx, dy)
			if map.in_bounds(q) and not fog.is_explored(q):
				return true
	return false


# ------------------------------------------------------ faction mechanics --

## What the player's faction map mechanic adds to taking a mine or town: the
## Brand and Plunder payout, and for a Levy of the Shires player the weekly
## recruits one more mine musters in every town (over mine_horizon_days).
func faction_capture_bonus(o: Dictionary) -> float:
	var v := bundle_value(FactionMechanics.plunder(o, int(o.get("owner", -1)), player, session.state, data))
	if o["type"] == "mine":
		var per := FactionMechanics.levy_per_mine(String(session.state.player(player)["faction"]), data)
		if per > 0:
			for t in _own_towns():
				var c := FactionMechanics.levy_creature(t, data)
				if c != "":
					v += float(per) * creature_value(c) * float(settings["mine_horizon_days"]) / 7.0
	return v


## Grave Harvest: the creatures beating this neutral army would raise.
func harvest_value(h: Hero, o: Dictionary) -> float:
	if not FactionMechanics.hero_has(h, "grave_harvest", data):
		return 0.0
	var slain := []
	for st in o.get("stacks", []):
		slain.append({"creature": String(st[0]), "lost": int(st[1])})
	var n := FactionMechanics.harvest_count(slain, h.faction, data)
	return float(n) * creature_value(String(FactionMechanics.of_faction(h.faction, data)["creature"]))


## Deep Roads (Sunken Forge): a hero standing by one of our holdings with most
## of its movement left tunnels to the holding nearest to where it wants to go
## when that saves at least a day of walking. Returns true if it travelled.
func _take_deep_road(h: Hero, goal: Vector2i) -> bool:
	if not FactionMechanics.hero_has(h, "deep_roads", data) or FactionMechanics.deep_road_origin(session.state, h).is_empty():
		return false
	if h.movement_left < h.max_movement(data) * 3 / 4:
		return false
	var walk := _straight_cost(h.pos, goal)
	var best_id := ""
	var best_cost := walk - float(h.max_movement(data))   # must save more than a day
	for d in session.deep_road_destinations(h.id):
		var c := _straight_cost(d["pos"], goal) + float(h.max_movement(data))   # the trip spends today
		if c < best_cost:
			best_cost = c
			best_id = String(d["id"])
	if best_id == "":
		return false
	var dest_name := String(session.state.map.objects[best_id].get("name", best_id))
	if session.deep_road(h.id, best_id).get("ok", false):
		_note("%s takes the deep roads toward %s." % [h.name, dest_name])
		return true
	return false


## A rough walking cost between two tiles (open ground, a little detour).
static func _straight_cost(a: Vector2i, b: Vector2i) -> float:
	var d := (a - b).abs()
	return (float(maxi(d.x, d.y)) + 0.41 * float(mini(d.x, d.y))) * 100.0 * 1.25


# ------------------------------------------------- encounters and skills --

## Expected gain of raising one random stack of this hero to the top veteran
## level: the average over the stacks that can still rise.
func _ascend_value(h: Hero) -> float:
	var candidates := h.army.ascendable_slots()
	if candidates.is_empty():
		return 0.0
	var gain := 0.0
	for i in candidates:
		var st: Dictionary = (h.army.slots[i] as Dictionary).duplicate()
		if not st.has("veteran_xp"):
			st["veteran_xp"] = Army.VETERAN_THRESHOLDS[2] if data.creature(st["creature"]).has("upgrade_of") else 0
		var before := stack_value(st)
		Army.ascend_stack(st, data)
		gain += stack_value(st) - before
	return gain / float(candidates.size())


## Expected gold value of an encounter choice's effects for this hero.
func _effects_value(h: Hero, effects: Array) -> float:
	var v := 0.0
	var hero_value := army_value(h.army)
	for e in effects:
		match String(e["type"]):
			"resources":
				v += bundle_value(e["resources"])
			"xp":
				v += float(e["amount"]) * float(settings["xp_value"])
			"recruit":
				v += float(session.encounters.scaled_count(e)) * creature_value(String(e["creature"]))
			"casualties":
				v -= float(e["fraction"]) * hero_value * (0.5 if String(e.get("role", "")) != "" else 1.0)
			"movement":
				v += float(e["amount"]) * 2.0
			"skill_point":
				v += 2500.0 * float(e.get("amount", 1))
			"mark":
				v += 300.0
			"boon":
				v += 150.0 * float(e.get("days", 7)) * float(e["mods"].size())
			"mana":
				v += float(e["amount"]) * 15.0
			"veteran_xp":
				v += float(e["amount"]) / 5000.0 * 0.15 * hero_value   # a rank is worth ~15% of the army
			"ascend":
				v += _ascend_value(h)
			"artifact":
				v += artifact_value(h, String(e["artifact"]))
			"reveal":
				v += float(e["radius"]) * float(e["radius"]) * float(settings["explore_value_per_tile"])
			"ambush":
				var stacks := []
				for st in e["stacks"]:
					stacks.append({"creature": String(st["creature"]), "count": session.encounters.scaled_count(st)})
				var threat := stacks_value(stacks)
				# A fight the hero wins easily is worth its XP; anything closer is a real risk.
				v += threat * 0.3 if hero_value >= 3.0 * threat else -2.0 * threat
	return v


## The best choice of an encounter for this hero: {index, value} or {} if
## every choice is unavailable or not worth it (leaving is always an option).
func encounter_choice(h: Hero, object_id: String) -> Dictionary:
	var opts := session.encounter_options(h.id, object_id)
	if opts.is_empty():
		return {}
	var obj: Dictionary = session.state.map.objects[object_id]
	var raw: Array = session.encounters.definition(obj).get("choices", [])
	var best := {}
	for c in opts["choices"]:
		if not c["available"] or c["leave"]:
			continue
		var def: Dictionary = raw[int(c["index"])]
		var chance := float(c["chance"])
		var v := chance * _effects_value(h, def.get("success", {}).get("effects", []))
		if c["has_check"]:
			v += (1.0 - chance) * _effects_value(h, def.get("failure", {}).get("effects", []))
		var cost: Dictionary = c["cost"]
		for res in cost:
			v -= float(cost[res]) * (2.0 if res == "movement" else resource_value(res))
		if v > 0.0 and (best.is_empty() or v > best["value"]):
			best = {"index": int(c["index"]), "value": v}
	return best


## Resolves an encounter the hero has walked up to. Fights an ambush only if
## the forecast allows. Returns false if the AI chose to leave it.
func _handle_encounter(h: Hero, object_id: String) -> bool:
	var pick := encounter_choice(h, object_id)
	if pick.is_empty():
		return false
	var res := session.resolve_encounter(h.id, object_id, pick["index"])
	if not res.get("ok", false):
		return false
	_note("%s resolves %s: %s." % [h.name, res.get("name", "an encounter"), "success" if res["success"] else "failure"])
	if res["battle"] != "" and session.state.map.objects.has(res["battle"]):
		var pred := forecast(h, res["battle"])
		if _fight_ok(pred):
			var b := session.attack(h.id, res["battle"])
			_note("%s fights off the ambush: %s." % [h.name, "victory" if b["winner"] == 0 else "defeat"])
	return true


## Spends every skill point on the offer ranked highest in skill_priority.
func _spend_skill_points(h: Hero) -> void:
	var prio: Array = settings["skill_priority"]
	while h.alive and h.skill_points > 0:
		var offers := session.skill_offers(h.id)
		if offers.is_empty():
			return
		var pick: String = offers[0]
		var rank := prio.size()
		for o in offers:
			var r := prio.find(o)
			if r >= 0 and r < rank:
				rank = r
				pick = o
		if not session.learn_skill(h.id, pick):
			return
		_note("%s learns %s." % [h.name, data.skills[pick]["name"]])


# ---------------------------------------------------------------- battles --

## Combat forecast for this hero against a map object, cached for the turn
## (keyed by both armies, so it is redone after casualties or recruits).
func forecast(h: Hero, object_id: String, simulations: int = 0) -> Dictionary:
	if session.is_cobolt_target(object_id):
		return {"win_probability": -1.0, "expected_loss_fraction": 1.0, "concealed": true}
	var setup := session.battle_setup(h.id, object_id)
	if _give_orders(h, setup["sides"][1]["stacks"]):
		setup = session.battle_setup(h.id, object_id)
	var sims := simulations if simulations > 0 else int(settings["forecast_simulations"])
	var key := "%s|%s|%s|%s|%s|%s|%d" % [h.id, object_id, str(setup["sides"][0]["stacks"]), str(setup["sides"][1]["stacks"]),
		str(h.orders), h.battle_spell_damage, sims]
	if not _forecasts.has(key):
		_forecasts[key] = CombatPredictor.new(data).predict(setup, sims)
	return _forecasts[key]


## Picks battle orders for the hero against these enemy stacks ([] = whoever
## comes). Returns true if the orders changed.
func _give_orders(h: Hero, enemy_stacks: Array) -> bool:
	if not bool(settings["battle_orders"]):
		return false
	var o := BattleOrders.choose(data, h.level, h.skill_level("tactics"), h.army.to_combat_stacks(), enemy_stacks, h.commander(data))
	if o == h.orders:
		return false
	return session.set_battle_orders(h.id, o)


## A decisive battle ends a rival: the last town of a player with no hero left.
## Losses do not matter there, only the chance to win.
func _fight_ok(pred: Dictionary, decisive: bool = false) -> bool:
	return float(pred["win_probability"]) >= float(settings["min_win_probability"]) \
		and (decisive or float(pred["expected_loss_fraction"]) <= float(settings["max_loss_fraction"]))


## True if beating this target eliminates its owner: its last town, and no
## hero of that player is left outside it (a hero inside defends it).
func is_decisive(target_id: String) -> bool:
	var o: Dictionary = session.state.map.objects.get(target_id, {})
	if o.is_empty() or o["type"] != "town":
		return false
	var owner := int(o["owner"])
	if owner < 0 or session.allied(owner, player) or session.towns_of(owner).size() != 1:
		return false
	for e in session.state.heroes_of(owner):
		if e.pos != AdventureMap.object_pos(o):
			return false
	return true


func _count(key: String, n: int = 1) -> void:
	if _report.has(key):
		_report[key] = int(_report[key]) + n


# ------------------------------------------------------------------ magic --

func _spell(spell_id: String) -> Dictionary:
	return data.magic["spells"].get(spell_id, {})


## The strongest battle spell the hero can cast now, or "".
func best_battle_spell(h: Hero) -> String:
	if not bool(settings["casts_spells"]):
		return ""
	var best := ""
	for sid in h.known_spells(data):
		var sp := _spell(sid)
		if String(sp.get("effect", "")) != "battle_damage" or session.can_cast_spell(h.id, sid) != "":
			continue
		if best == "" or float(sp["amount"]) > float(_spell(best)["amount"]):
			best = sid
	return best


## The forecast for attacking object_id and the battle spell to cast first
## ("" for none): {pred, spell}. A spell is worth its mana when it turns a
## battle the hero would refuse into one it takes, or saves more troops than
## the mana is worth. The spell is tried on the forecast only; nothing is cast.
func battle_plan(h: Hero, object_id: String) -> Dictionary:
	var pred := forecast(h, object_id)
	var spell := best_battle_spell(h)
	if spell == "":
		return {"pred": pred, "spell": ""}
	var before := h.battle_spell_damage
	h.battle_spell_damage = float(_spell(spell)["amount"])
	var boosted := forecast(h, object_id)
	h.battle_spell_damage = before
	var decisive := is_decisive(object_id)
	var enables := _fight_ok(boosted, decisive) and not _fight_ok(pred, decisive)
	var saved := (float(pred["expected_loss_fraction"]) - float(boosted["expected_loss_fraction"])) * army_value(h.army)
	if enables or saved > float(_spell(spell)["cost"]) * float(settings["mana_value"]):
		return {"pred": boosted, "spell": spell}
	return {"pred": pred, "spell": ""}


func _cast(h: Hero, spell_id: String, destination_id: String = "") -> bool:
	if spell_id == "":
		return false
	var r := session.cast_spell(h.id, spell_id, destination_id)
	if r["ok"]:
		_count("spells")
		_note("%s casts %s." % [h.name, _spell(spell_id)["name"]])
	return r["ok"]


## Mana the hero keeps for its cheapest battle spell (0 if it knows none).
func _battle_mana_reserve(h: Hero) -> int:
	var reserve := 0
	for sid in h.known_spells(data):
		var sp := _spell(sid)
		if String(sp.get("effect", "")) == "battle_damage" and (reserve == 0 or int(sp["cost"]) < reserve):
			reserve = int(sp["cost"])
	return reserve


## The hero stopped short of target for lack of movement: casts the cheapest
## movement spell that gets it there today, keeping mana for a battle spell.
func _cast_for_movement(h: Hero, target: Vector2i) -> bool:
	if not bool(settings["casts_spells"]):
		return false
	var plan := session.plan_path(h.id, target)
	if (plan["path"] as Array).is_empty():
		return false
	var need := int(plan["total_cost"])
	var reserve := _battle_mana_reserve(h)
	var full := h.max_movement(data)
	var best := ""
	for sid in h.known_spells(data):
		var sp := _spell(sid)
		if String(sp.get("effect", "")) != "movement" or session.can_cast_spell(h.id, sid) != "":
			continue
		if h.mana - int(sp["cost"]) < reserve:
			continue
		if mini(full, h.movement_left + int(round(full * float(sp["amount"])))) < need:
			continue
		if best == "" or int(sp["cost"]) < int(_spell(best)["cost"]):
			best = sid
	return _cast(h, best)


## End of turn: mana the hero could not hold tomorrow goes into a battle spell
## that stays on until its next battle (also when attacked).
func _standing_spell(h: Hero) -> void:
	if not h.alive or h.battle_spell_damage > 0.0:
		return
	if h.mana + int(data.rules["mana_daily_regen"]) <= h.max_mana(data):
		return
	_cast(h, best_battle_spell(h))


## The main hero cannot walk to a threatened town it could hold today: it
## casts Homeward or Town Gate to get there.
func _teleport_to_defend(h: Hero) -> void:
	var tunnels := FactionMechanics.hero_has(h, "deep_roads", data)
	if not (bool(settings["casts_spells"]) or tunnels) or h != main_hero():
		return
	var here := session.state.map.object_at(h.pos)
	if not here.is_empty() and here["type"] == "town" and int(here["owner"]) == player and is_threatened(here["id"]):
		return
	var field: AiDistanceField = null
	for t in _own_towns():
		if not is_threatened(t["id"]) or not can_hold_with(t, h):
			continue
		var p := AdventureMap.object_pos(t)
		if session.state.hero_at(p) != null:
			continue
		if field == null:
			field = AiDistanceField.build(session.state.map, h.pos, _blocked_for(h))
		if field.cost_to(p) <= h.movement_left:
			continue   # walking there today is enough
		if tunnels and session.can_deep_road(h.id, t["id"]) == "" and session.deep_road(h.id, t["id"]).get("ok", false):
			_note("%s takes the deep roads to defend %s." % [h.name, t["name"]])
			return
		if not bool(settings["casts_spells"]):
			continue
		for sid in h.known_spells(data):
			var effect := String(_spell(sid).get("effect", ""))
			if effect in ["home", "town_gate"] and session.can_cast_spell(h.id, sid, t["id"]) == "":
				if _cast(h, sid, t["id"]):
					_note("%s returns to defend %s." % [h.name, t["name"]])
					return


# --------------------------------------------------------------- upgrades --

func _keeps_upgrade_reserve(cost: Dictionary) -> bool:
	var bank := _bank()
	for res in cost:
		var keep := int(settings["upgrade_reserve_gold"]) if res == "gold" else int(settings["upgrade_reserve_resource"])
		if int(cost[res]) > 0 and bank.get_amount(res) - int(cost[res]) < keep:
			return false
	return true


## Upgrades the stacks of this town's garrison and visiting hero that its
## buildings can, the biggest gain first (the hero's stacks count a little
## more: they fight first). Upgrades come after recruits and only spend what
## is above the upgrade reserves, which stay for tomorrow's building: an
## upgrade is worth no more than its price, a new dwelling keeps paying.
## hero_only: only the visiting hero's stacks. Returns the number of upgrades.
func _upgrade_stacks(t: Dictionary, hero_only: bool = false) -> int:
	if not bool(settings["upgrades"]):
		return 0
	var done := 0
	for _pass in Army.MAX_SLOTS * 2:
		var best := {}
		var best_gain := 0.0
		for opt in session.upgrade_options(t["id"]):
			if opt["reason"] != "" or (hero_only and opt["in_garrison"]) or not _keeps_upgrade_reserve(opt["cost"]):
				continue
			var gain := float(opt["count"]) * (creature_value(opt["upgrade"]) - creature_value(opt["creature"]))
			if not opt["in_garrison"]:
				gain *= 1.25
			if gain > best_gain:
				best_gain = gain
				best = opt
		if best.is_empty():
			break
		var r := session.upgrade_stack(t["id"], int(best["slot"]), bool(best["in_garrison"]))
		if not r["ok"]:
			break
		done += 1
		_note("%s upgrades %d %s to %s." % [t["name"], int(best["count"]), data.creature(best["creature"])["name"],
			data.creature(best["upgrade"])["name"]])
	_count("upgrades", done)
	return done


# ---------------------------------------------------------------- traders --

## What the hero would buy from this road trader now, in stock order:
## [{index, value}]. Artifacts the hero would wear and that are worth
## trader_buy_ratio of their price, and a map while much of the world is hidden;
## trader_reserve_gold stays in the treasury.
func trader_picks(h: Hero, o: Dictionary) -> Array:
	var out := []
	if not bool(settings["trades_at_sites"]) or MapSites.kind(o, data) != "trader":
		return out
	if int(o.get("owner", -1)) >= 0 and int(o.get("owner", -1)) != player:
		return out
	var budget := _bank().get_amount("gold") - int(settings["trader_reserve_gold"])
	var stock: Array = o.get("stock", [])
	for i in stock.size():
		var offer: Dictionary = stock[i]
		var price := int(offer.get("price", 0))
		if int(offer.get("remaining", 0)) <= 0 or price <= 0 or price > budget:
			continue
		var v := 0.0
		if offer.get("kind", "") == "artifact":
			v = artifact_value(h, String(offer["artifact"]))
			if String(h.equipment.get(data.artifacts[offer["artifact"]]["slot"], "")) != "" \
					and v <= float(data.artifacts[offer["artifact"]]["value"]) * float(settings["spare_artifact_rate"]):
				continue   # only a spare for the pack
		elif offer.get("kind", "") == "map":
			v = map_value(int(offer.get("tiles", 0)))
		if v <= 0.0 or v < float(price) * float(settings["trader_buy_ratio"]):
			continue
		out.append({"index": i, "value": v})
		budget -= price
	return out


## What the trader's wares are worth to the hero (see trader_picks).
func trader_value(h: Hero, o: Dictionary) -> float:
	var v := 0.0
	for pick in trader_picks(h, o):
		v += float(pick["value"])
	return v


## Worth of a chart that uncovers `tiles` random hidden tiles: nothing once
## half the map is explored (random tiles then rarely show anything new).
func map_value(tiles: int) -> float:
	var fog: FogOfWar = session.state.player(player)["fog"]
	var total := session.state.map.width * session.state.map.height
	var hidden := total - fog.explored_count()
	if hidden * 2 < total:
		return 0.0
	return float(mini(tiles, hidden)) * float(settings["explore_value_per_tile"]) * float(settings["trader_map_rate"])


## Standing on a road trader: buys what trader_picks chose and wears it.
func _shop_at_trader(h: Hero, site_id: String) -> int:
	var o: Dictionary = session.state.map.objects.get(site_id, {})
	if o.is_empty() or o.get("type", "") != "site":
		return 0
	var bought := 0
	for pick in trader_picks(h, o):
		var r := session.trader_buy(site_id, h.id, int(pick["index"]))
		if r["ok"]:
			bought += 1
			_note("%s buys %s from the %s." % [h.name, r["name"], MapSites.site_name(o, data)])
	if bought > 0:
		equip_best(h)
		_count("purchases", bought)
	return bought


# ----------------------------------------------------------------- allies --

## Sends living allies what they lack: the price of a hero to an ally without
## one, and a share of our surplus (above the gift reserves) of every resource
## an ally has less than half as much of. Returns the number of shipments.
func _support_allies() -> int:
	if not bool(settings["ally_gifts"]):
		return 0
	var sent := 0
	var mine := _bank()
	for ally in session.living_allies(player):
		var theirs: ResourceBank = session.state.player(ally)["resources"]
		var bundle := {}
		if session.state.heroes_of(ally).is_empty():
			var price := 0
			for t in session.towns_of(ally):
				var c := int(session.hire_cost(t["id"]).get("gold", 0))
				if c > 0 and (price == 0 or c < price):
					price = c
			var short := price - theirs.get_amount("gold")
			if short > 0 and mine.get_amount("gold") >= short:
				bundle["gold"] = short
		for res in data.resource_order:
			var have := mine.get_amount(res) - int(bundle.get(res, 0))
			var keep := int(settings["gift_reserve_gold"]) if res == "gold" else int(settings["gift_reserve_resource"])
			if have <= keep or theirs.get_amount(res) * 2 >= have:
				continue
			var n := int(float(have - keep) * float(settings["gift_share"]))
			if n > 0:
				bundle[res] = int(bundle.get(res, 0)) + n
		if bundle.is_empty():
			continue
		var r := session.send_resources(ally, bundle)
		if r["ok"]:
			sent += 1
			var parts: Array[String] = []
			for res in data.resource_order:
				if r["sent"].has(res):
					parts.append("%d %s" % [int(r["sent"][res]), data.resources[res]["name"]])
			_note("Sends %s to %s." % [", ".join(parts), session.state.player(ally)["name"]])
	_count("gifts", sent)
	return sent
