class_name Arena
extends RefCounted
## The Battle Arena: quick fights away from the adventure map, in two modes.
##   sandbox: pick both factions and heroes, recruit both armies in fully built
##     towns (optionally with endless resources and the ultimate building), or
##     let the enemy be built automatically to match your army ("fight equal").
##   rogue: a run of ever stronger fights. A small starting purse, rewards after
##     every victory, endless troop supply in your town; the run ends when your
##     hero falls. Veterancy, hero levels, orders and found equipment carry over.
## The arena plays inside its own tiny GameSession (two towns, two heroes on a
## strip of land), so the regular town, hero and battle screens work unchanged.
## It never touches another game's state, and all of its own randomness comes
## from its own GameRng (seeded from config.seed), not the session's.

const MAP_ID := "arena"
const PLAYER_TOWN := "arena_town_you"
const ENEMY_TOWN := "arena_town_foe"
const PLAYER_HERO := "arena_you"
const FIELD := Vector2i(6, 2)
const PLAYER_TOWN_POS := Vector2i(2, 2)
const ENEMY_TOWN_POS := Vector2i(10, 2)
const WIDTH := 13
const HEIGHT := 5
## "Endless" resources: what the bank is topped up to.
const PLENTY := 999999
## "Endless" troop supply: what every recruitment pool is topped up to.
const SUPPLY := 9999
const MODES := ["sandbox", "rogue"]
const DIFFICULTIES := ["easy", "medium", "hard"]
## Rogue tuning per difficulty.
##   start_gold: purse for the first army (a handful of tier 1-2 stacks).
##   first_enemy: gold worth of the first enemy army; growth: per round after it.
##   match: hard mode builds every enemy to the player's own strength (army,
##     veterancy and hero) times (1 + match_step * wins) instead.
##   reward: share of the beaten army's worth paid out in gold.
##   item_chance: chance of an equipment find after a victory.
##   foe_level_rate: enemy hero levels per round (hard copies the player's level).
const ROGUE := {
	"easy": {"name": "Easy", "start_gold": 3000, "first_enemy": 1700, "growth": 1.22, "reward": 0.95, "item_chance": 0.6, "foe_level_rate": 0.35, "match": false, "match_step": 0.0},
	"medium": {"name": "Medium", "start_gold": 2500, "first_enemy": 2200, "growth": 1.3, "reward": 0.8, "item_chance": 0.45, "foe_level_rate": 0.5, "match": false, "match_step": 0.0},
	"hard": {"name": "Hard", "start_gold": 2000, "first_enemy": 2000, "growth": 1.0, "reward": 0.7, "item_chance": 0.35, "foe_level_rate": 1.0, "match": true, "match_step": 0.03},
}
## Combat worth of a stack per veteran level (1-5): the +1/+1 ranks and the
## Ascendant form (+20 % hit points and damage, +2/+2) make a stack stronger
## than its gold price says.
const VETERAN_WORTH := [1.0, 1.07, 1.07, 1.14, 1.55]
## A rough worth for each point of the commanding hero's attack and defense,
## after the combat formula (+3 % damage per attack point, -2 % per defense point).
const HERO_ATTACK_WORTH := 0.03
const HERO_DEFENSE_WORTH := 0.02

var data: GameData
var session: GameSession
var config: Dictionary = {}
var rng: GameRng
## Rogue: fights won so far (the next enemy is wins + 1).
var wins := 0
## The current enemy hero's id.
var enemy_id := ""
## Rogue: true once the player's hero has fallen.
var run_over := false
## Rogue: gold worth of the current enemy army (the reward is a share of it).
var enemy_worth := 0
## Sandbox: both armies as they stood before the last fight, to restore them.
var _snapshot: Dictionary = {}
var _foe_serial := 0


## config: {mode, faction, hero_class, seed, and for sandbox: enemy_faction,
## enemy_class, enemy ("build" | "equal"), infinite, ultimate, enemy_ultimate,
## level, enemy_level, terrain; for rogue: difficulty}. Missing keys get defaults.
static func create(game_data: GameData, cfg: Dictionary) -> Arena:
	var a := Arena.new()
	a.data = game_data
	a.config = normalized_config(game_data, cfg)
	a.rng = GameRng.new(int(a.config["seed"]))
	a._build_session()
	return a


static func normalized_config(game_data: GameData, cfg: Dictionary) -> Dictionary:
	var c := cfg.duplicate(true)
	var factions := GameSetup.playable_factions(game_data)
	c["mode"] = String(c.get("mode", "sandbox")) if String(c.get("mode", "sandbox")) in MODES else "sandbox"
	c["faction"] = String(c.get("faction", factions[0])) if factions.has(String(c.get("faction", ""))) else factions[0]
	c["hero_class"] = _class_or_default(game_data, String(c["faction"]), String(c.get("hero_class", "")))
	var other := _other_faction(factions, String(c["faction"]))
	c["enemy_faction"] = String(c.get("enemy_faction", other)) if factions.has(String(c.get("enemy_faction", ""))) else other
	c["enemy_class"] = _class_or_default(game_data, String(c["enemy_faction"]), String(c.get("enemy_class", "")))
	c["enemy"] = String(c.get("enemy", "build")) if String(c.get("enemy", "build")) in ["build", "equal"] else "build"
	c["infinite"] = bool(c.get("infinite", c["mode"] == "sandbox"))
	c["ultimate"] = bool(c.get("ultimate", false))
	c["enemy_ultimate"] = bool(c.get("enemy_ultimate", false))
	c["level"] = clampi(int(c.get("level", 1)), 1, max_level(game_data))
	c["enemy_level"] = clampi(int(c.get("enemy_level", 1)), 1, max_level(game_data))
	c["difficulty"] = String(c.get("difficulty", "medium")) if String(c.get("difficulty", "")) in DIFFICULTIES else "medium"
	c["terrain"] = String(c.get("terrain", "grass")) if battle_terrains(game_data).has(String(c.get("terrain", ""))) else "grass"
	c["seed"] = int(c.get("seed", 1)) & GameRng.MASK32
	return c


static func _other_faction(factions: Array, mine: String) -> String:
	for f in factions:
		if f != mine:
			return f
	return mine


static func _class_or_default(game_data: GameData, faction: String, wanted: String) -> String:
	var classes := GameSetup.classes_for_faction(game_data, faction)
	if classes.has(wanted):
		return wanted
	return String(classes[0]) if not classes.is_empty() else ""


static func max_level(game_data: GameData) -> int:
	return (game_data.progression["xp_thresholds"] as Array).size()


## Terrains a battle can be fought on (passable, their own combat terrain).
static func battle_terrains(game_data: GameData) -> Array:
	var out := []
	for id in game_data.terrains:
		var t: Dictionary = game_data.terrains[id]
		if bool(t.get("passable", true)) and String(t.get("combat_terrain", id)) == id:
			out.append(id)
	return out


func is_rogue() -> bool:
	return config["mode"] == "rogue"


func player_hero() -> Hero:
	return session.hero(PLAYER_HERO)


func enemy_hero() -> Hero:
	return session.hero(enemy_id) if enemy_id != "" else null


func difficulty() -> Dictionary:
	return ROGUE[config["difficulty"]]


# ------------------------------------------------------------------ setup --

func _build_session() -> void:
	var row := ""
	for x in WIDTH:
		row += String(data.terrains["grass"]["char"])
	var rows := []
	for y in HEIGHT:
		rows.append(row)
	var players := [
		{"id": 0, "name": "You", "faction": config["faction"], "color": "#3a6fd8", "is_human": true},
		{"id": 1, "name": "Arena foe", "faction": config["enemy_faction"], "color": "#c8423a", "is_human": true},
	]
	var def := {"id": MAP_ID, "name": "Battle Arena", "width": WIDTH, "height": HEIGHT, "terrain": rows,
		"players": players, "heroes": [], "objects": [
			_town_def(PLAYER_TOWN, 0, String(config["faction"]), PLAYER_TOWN_POS, bool(config["ultimate"])),
			_town_def(ENEMY_TOWN, 1, String(config["enemy_faction"]), ENEMY_TOWN_POS, bool(config["enemy_ultimate"])),
		]}
	session = GameSession.new_game_from_definition(data, def, int(config["seed"]), {}, {"arena": config["mode"]})
	session.state.current_player = 0
	var me := _make_hero(PLAYER_HERO, 0, String(config["hero_class"]), _hero_name(String(config["faction"]), 0), PLAYER_TOWN_POS)
	session.state.heroes[me.id] = me
	if is_rogue():
		_level_up_to(me, 1)
		var bank: ResourceBank = session.state.player(0)["resources"]
		_set_bank(bank, {"gold": int(difficulty()["start_gold"])})
		_set_bank(session.state.player(1)["resources"], {})
		_set_field_terrain("grass")
		_spawn_rogue_enemy()
	else:
		_level_up_to(me, int(config["level"]))
		_set_field_terrain(String(config["terrain"]))
		var foe := _make_hero(_next_foe_id(), 1, String(config["enemy_class"]), _hero_name(String(config["enemy_faction"]), 1), FIELD)
		session.state.heroes[foe.id] = foe
		enemy_id = foe.id
		_level_up_to(foe, int(config["enemy_level"]))
		_auto_learn(foe)
		refill()
	session.state.current_player = 0


func _town_def(id: String, owner: int, faction: String, pos: Vector2i, ultimate: bool) -> Dictionary:
	return {"id": id, "type": "town", "pos": [pos.x, pos.y], "town_type": faction, "owner": owner,
		"name": "%s arena" % String(data.factions[faction].get("adjective", data.factions[faction]["name"])),
		"built": built_list(data, faction, ultimate), "garrison": []}


## Every building of the faction's town; the ultimate building only on request.
static func built_list(game_data: GameData, faction: String, ultimate: bool) -> Array:
	var out := []
	var buildings: Dictionary = game_data.town_types[faction]["buildings"]
	for b in buildings:
		if String(buildings[b].get("category", "")) == "ultimate" and not ultimate:
			continue
		out.append(b)
	return out


func _make_hero(id: String, owner: int, class_id: String, hero_name: String, pos: Vector2i) -> Hero:
	return Hero.create({"id": id, "name": hero_name, "class": class_id, "owner": owner, "pos": [pos.x, pos.y], "army": []}, data)


func _hero_name(faction: String, pick: int) -> String:
	var names: Array = data.town_types[faction]["hire"].get("heroes", [])
	if names.is_empty():
		return "Champion"
	return String(names[pick % names.size()]["name"])


func _next_foe_id() -> String:
	_foe_serial += 1
	return "arena_foe_%d" % _foe_serial


## Raises a hero (with an empty army, so no veteran experience leaks in) to a level.
func _level_up_to(h: Hero, level: int) -> void:
	var thresholds: Array = data.progression["xp_thresholds"]
	var keep := h.army
	h.army = Army.new()
	var target := int(thresholds[clampi(level, 1, thresholds.size()) - 1])
	if target > h.xp:
		h.add_xp(target - h.xp, data)
	h.army = keep
	h.mana = h.max_mana(data)


## Spends a computer hero's skill points on its class's offers.
func _auto_learn(h: Hero) -> void:
	var guard := 0
	while h.skill_points > 0 and guard < 64:
		guard += 1
		var offers := h.skill_offers_seeded(data, GameRng.mix(int(config["seed"]), _foe_serial * 97 + guard))
		if offers.is_empty() or not h.learn_skill(String(offers[0]), data):
			break


func _set_bank(bank: ResourceBank, amounts: Dictionary) -> void:
	for res in data.resource_order:
		var diff := int(amounts.get(res, 0)) - bank.get_amount(res)
		if diff > 0:
			bank.add(res, diff)
		elif diff < 0:
			bank.spend({res: -diff})


func _set_field_terrain(terrain_id: String) -> void:
	var m := session.state.map
	for y in HEIGHT:
		for x in range(PLAYER_TOWN_POS.x + 2, ENEMY_TOWN_POS.x - 1):
			m.terrain[m.index(Vector2i(x, y))] = terrain_id


func field_terrain() -> String:
	return session.state.map.terrain_at(FIELD)


## Keeps the endless parts endless: troop pools always (sandbox and rogue), and
## the treasury when config.infinite is set. Call after every recruitment.
func refill() -> void:
	for id in [PLAYER_TOWN, ENEMY_TOWN]:
		var t := session.town(id)
		for c in Town.dwellings(t, data):
			t["available"][c] = SUPPLY
	if bool(config["infinite"]) and not is_rogue():
		var plenty := {}
		for res in data.resource_order:
			plenty[res] = PLENTY
		_set_bank(session.state.player(0)["resources"], plenty)
		_set_bank(session.state.player(1)["resources"], plenty)


## Sandbox, enemy built by hand: the enemy hero steps into its town and the
## enemy takes the turn, so the town screen recruits into the enemy's army.
func begin_enemy_edit() -> void:
	var foe := enemy_hero()
	if foe != null:
		foe.pos = ENEMY_TOWN_POS
	session.state.current_player = 1


func end_enemy_edit() -> void:
	var foe := enemy_hero()
	if foe != null:
		foe.pos = FIELD
	session.state.current_player = 0


## Sandbox "fight equal": replaces the enemy army with one of its own faction,
## up to the player's best tier and worth the player's strength (army,
## veterancy and hero). The enemy hero is raised to the player's level.
func build_equal_enemy() -> void:
	var me := player_hero()
	var foe := enemy_hero()
	if foe == null or me.army.is_empty():
		return
	if foe.level < me.level:
		_level_up_to(foe, me.level)
		_auto_learn(foe)
	var top := 1
	var vet := 0
	var stacks := 0
	for s in me.army.slots:
		if not s.is_empty():
			top = maxi(top, int(data.creature(String(s["creature"]))["tier"]))
			vet += Army.veteran_level(s)
			stacks += 1
	var level := clampi(roundi(float(vet) / maxi(1, stacks)), 1, 5)
	foe.army = _compose(String(foe.faction), power_of(me), top, level, foe)


# -------------------------------------------------------------- strength --

## A creature's price in gold, other resources at BalanceScenarios.RESOURCE_VALUE.
func creature_gold(id: String) -> int:
	var total := 0
	var cost: Dictionary = data.creature(id).get("cost", {})
	for r in cost:
		total += int(cost[r]) * int(BalanceScenarios.RESOURCE_VALUE.get(r, 250))
	return total


## Gold worth of an army at its creatures' prices.
func army_gold(army: Army) -> int:
	var total := 0
	for s in army.slots:
		if not s.is_empty():
			total += creature_gold(String(s["creature"])) * int(s["count"])
	return total


## Combat worth of an army: its gold worth, each stack scaled by its veteran level.
func army_worth(army: Army) -> float:
	var total := 0.0
	for s in army.slots:
		if not s.is_empty():
			total += creature_gold(String(s["creature"])) * int(s["count"]) * float(VETERAN_WORTH[Army.veteran_level(s) - 1])
	return total


## How much the commanding hero's attack and defense add to its army.
func hero_factor(h: Hero) -> float:
	if h == null:
		return 1.0
	var p := h.combat_profile(data)
	return (1.0 + HERO_ATTACK_WORTH * int(p["attack"])) * (1.0 + HERO_DEFENSE_WORTH * int(p["defense"]))


## A hero's whole strength in gold: army worth with veterancy, times the hero's factor.
func power_of(h: Hero) -> float:
	return army_worth(h.army) * hero_factor(h)


## An army of the faction worth `power` once led by `leader` and at the given
## veteran level: up to seven stacks of tiers 1..max_tier, more gold going to
## the higher tiers, drawn with the arena's own generator.
func _compose(faction: String, power: float, max_tier: int, veteran_level: int, leader: Hero) -> Army:
	var gold := power / (hero_factor(leader) * float(VETERAN_WORTH[clampi(veteran_level, 1, 5) - 1]))
	var tiers := {}
	for id in data.creatures:
		var c: Dictionary = data.creatures[id]
		if String(c.get("faction", "")) != faction or c.has("upgrade_of") or int(c["tier"]) > max_tier:
			continue
		var t := int(c["tier"])
		if not tiers.has(t) or String(id) < String(tiers[t]):
			tiers[t] = String(id)
	var keys := tiers.keys()
	keys.sort()
	var army := Army.new()
	if keys.is_empty():
		return army
	# The top tiers the purse can buy at least one of, at most seven of them.
	var usable := keys.filter(func(t): return creature_gold(tiers[t]) <= gold)
	if usable.is_empty():
		usable = [keys[0]]
	while usable.size() > 7:
		usable.remove_at(0)
	var weights := []
	var weight_sum := 0.0
	for t in usable:
		var w := (1.0 + float(t)) * rng.next_float_range(0.75, 1.25)
		weights.append(w)
		weight_sum += w
	var spent := 0
	var pairs := []
	for i in usable.size():
		var id := String(tiers[usable[i]])
		var n := int(floor(gold * weights[i] / weight_sum / creature_gold(id)))
		if n > 0:
			pairs.append([id, n])
			spent += n * creature_gold(id)
	# Spend what is left on the cheapest creature, so the worth comes out right.
	var cheapest := String(tiers[usable[0]])
	var extra := int(floor((gold - spent) / creature_gold(cheapest)))
	if extra > 0 or pairs.is_empty():
		var found := false
		for p in pairs:
			if p[0] == cheapest:
				p[1] = int(p[1]) + maxi(1, extra)
				found = true
		if not found:
			pairs.push_front([cheapest, maxi(1, extra)])
	var xp: int = Army.VETERAN_THRESHOLDS[clampi(veteran_level, 1, 5) - 1]
	for p in pairs:
		army.add(String(p[0]), int(p[1]), xp)
	# Veterans of level 3 and up fight in their improved form.
	for s in army.slots:
		if not s.is_empty() and Army.veteran_level(s) >= 3:
			var up := String(data.creature(String(s["creature"])).get("upgrade", ""))
			if up != "":
				s["creature"] = up
	return army


# ------------------------------------------------------------------ fight --

## Sandbox: remembers both armies (and the enemy hero) before a fight, so
## restore_armies() can put them back afterwards.
func remember_armies() -> void:
	var foe := enemy_hero()
	_snapshot = {"you": player_hero().army.to_dict(), "foe": foe.army.to_dict() if foe != null else [],
		"foe_hero": foe.to_dict() if foe != null else {}}


func restore_armies() -> void:
	if _snapshot.is_empty():
		return
	var me := player_hero()
	me.army = Army.from_dict(_snapshot["you"])
	me.alive = true
	_reset_hero(me, PLAYER_TOWN_POS)
	var fd: Dictionary = _snapshot["foe_hero"]
	if not fd.is_empty():
		var foe := Hero.from_dict(fd)
		session.state.heroes[foe.id] = foe
		foe.army = Army.from_dict(_snapshot["foe"])
		_reset_hero(foe, FIELD)


func _reset_hero(h: Hero, pos: Vector2i) -> void:
	h.pos = pos
	h.movement_left = h.max_movement(data)
	h.mana = h.max_mana(data)


## Fights the current enemy with the player's hero (GameSession.attack()).
func fight() -> Dictionary:
	end_enemy_edit()
	var me := player_hero()
	_reset_hero(me, PLAYER_TOWN_POS)
	if not is_rogue():
		remember_armies()
	var result := session.attack(PLAYER_HERO, enemy_id)
	if not result.get("ok", true):
		return result
	result["arena_round"] = wins + 1
	return result


## After a fight: rogue victories pay out and bring the next enemy; a hero who
## fell ends the run. Returns {victory, run_over, gold, resources: {res: n},
## found: [artifact ids], wins}.
func after_fight(result: Dictionary) -> Dictionary:
	var me := player_hero()
	var out := {"victory": int(result.get("winner", 1)) == 0, "run_over": false, "gold": 0, "resources": {}, "found": [], "wins": wins}
	if not is_rogue():
		_reset_hero(me, PLAYER_TOWN_POS)
		return out
	if not me.alive or me.army.is_empty():
		run_over = true
		out["run_over"] = true
		return out
	_reset_hero(me, PLAYER_TOWN_POS)
	if not out["victory"]:
		# The enemy keeps its survivors; recruit and try again.
		var foe := enemy_hero()
		if foe != null:
			_reset_hero(foe, FIELD)
		return out
	wins += 1
	out["wins"] = wins
	var bank: ResourceBank = session.state.player(0)["resources"]
	var gold := int(round_to(enemy_worth * float(difficulty()["reward"]), 50))
	bank.add("gold", gold)
	out["gold"] = gold
	for res in reward_resources(wins):
		bank.add(res, int(reward_resources(wins)[res]))
		out["resources"][res] = int(reward_resources(wins)[res])
	if rng.chance(float(difficulty()["item_chance"])):
		var item := random_artifact(wins)
		if item != "" and me.give_artifact(item, data):
			out["found"].append(item)
	# A new day: the town may raise a building again (the ultimate is a goal).
	session.state.day += 1
	_spawn_rogue_enemy()
	return out


static func round_to(v: float, step: int) -> int:
	return maxi(step, int(round(v / step)) * step)


## Rogue: the resources a victory in this round pays besides gold: wood and
## ore, and the player's faction's rare resources.
func reward_resources(round_no: int) -> Dictionary:
	var out := {"wood": 2 + round_no / 2, "ore": 2 + round_no / 2}
	for res in data.factions[config["faction"]].get("economy", {}).get("key_resources", []):
		if res in ["wood", "ore"]:
			out[res] = int(out[res]) + 2 + round_no / 2
		else:
			out[res] = 1 + round_no / 3
	return out


## A random artifact for an equipment find: minor ones early, relics later.
func random_artifact(round_no: int) -> String:
	var weights := {"minor": 6.0, "major": 1.0 + round_no * 0.6, "relic": maxf(0.0, (round_no - 4) * 0.4)}
	var ids := data.artifacts.keys()
	ids.sort()
	var me := player_hero()
	var owned := me.all_artifacts(data)
	var pool := []
	var w := []
	for id in ids:
		if owned.has(id):
			continue
		var wt := float(weights.get(String(data.artifacts[id].get("rarity", "minor")), 0.0))
		if wt > 0.0:
			pool.append(id)
			w.append(wt)
	if pool.is_empty():
		return ""
	return String(pool[rng.weighted_index(w)])


## Rogue: worth of the next enemy (before its hero and veterancy). Easy and
## medium follow a growing schedule; hard matches the player's strength.
func rogue_enemy_power(round_no: int) -> float:
	var d := difficulty()
	if bool(d["match"]):
		var mine := power_of(player_hero())
		# Before the first recruitment the player has nothing: use the purse.
		if mine <= 0.0:
			mine = float(d["start_gold"])
		return mine * (1.0 + float(d["match_step"]) * round_no)
	return float(d["first_enemy"]) * pow(float(d["growth"]), round_no)


## Rogue: the highest tier the next enemy may field (two tiers to start, one
## more every two rounds).
static func rogue_max_tier(round_no: int) -> int:
	return clampi(2 + round_no / 2, 2, 8)


## Rogue: replaces the enemy with the next one, of a random faction other than
## the player's, on a random battlefield.
func _spawn_rogue_enemy() -> void:
	var old := enemy_hero()
	if old != null:
		session.state.heroes.erase(old.id)
	var factions := GameSetup.playable_factions(data).filter(func(f): return f != config["faction"])
	if factions.is_empty():
		factions = GameSetup.playable_factions(data)
	var faction := String(factions[rng.next_int(0, factions.size() - 1)])
	var classes := GameSetup.classes_for_faction(data, faction)
	var cls := String(classes[rng.next_int(0, classes.size() - 1)])
	var foe := _make_hero(_next_foe_id(), 1, cls, _hero_name(faction, rng.next_int(0, 9)), FIELD)
	session.state.heroes[foe.id] = foe
	enemy_id = foe.id
	var d := difficulty()
	var level := 1 + int(floor(wins * float(d["foe_level_rate"])))
	if bool(d["match"]):
		level = player_hero().level
	_level_up_to(foe, level)
	_auto_learn(foe)
	# Equipment on later enemies.
	for i in mini(4, wins / 3):
		var item := random_artifact(wins)
		if item != "":
			foe.give_artifact(item, data)
	var vet_level := clampi(1 + wins / 3, 1, 4)
	if bool(d["match"]):
		vet_level = _player_veteran_level()
	foe.army = _compose(faction, rogue_enemy_power(wins), rogue_max_tier(wins), vet_level, foe)
	enemy_worth = army_gold(foe.army)
	# The enemy town takes the foe's faction (for its creatures' ultimate upgrade late in a run).
	var t := session.town(ENEMY_TOWN)
	t["town_type"] = faction
	t["built"] = built_list(data, faction, wins >= 12)
	session.state.player(1)["faction"] = faction
	var terrains := battle_terrains(data)
	terrains.sort()
	_set_field_terrain(String(terrains[rng.next_int(0, terrains.size() - 1)]) if wins > 0 else "grass")
	refill()


func _player_veteran_level() -> int:
	var total := 0
	var n := 0
	for s in player_hero().army.slots:
		if not s.is_empty():
			total += Army.veteran_level(s)
			n += 1
	return clampi(roundi(float(total) / maxi(1, n)), 1, 5)


## One line on what the next rogue fight brings.
func enemy_summary() -> String:
	var foe := enemy_hero()
	if foe == null:
		return ""
	return "%s, level %d %s of %s" % [foe.name, foe.level, String(data.hero_classes[foe.class_id]["name"]),
		String(data.factions[foe.faction]["name"])]


## The arena hides nothing: the player always sees the enemy's exact troops and odds.
func reveal_enemy() -> void:
	var p := session.state.player(0)
	var seen: Dictionary = p.get("scouted", {})
	seen[enemy_id] = session.state.day
	p["scouted"] = seen
