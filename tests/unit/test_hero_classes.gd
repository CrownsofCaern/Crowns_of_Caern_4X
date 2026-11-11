extends "res://tests/test_case.gd"
## Hero classes, skills and the hero modifier interface: every modifier key has
## a real effect, so no skill, trait or artifact can be a placeholder.

const PROBE := "_test_probe"


func _hero(cls: String, skills: Dictionary = {}) -> Hero:
	var h := Hero.create({"id": "h_" + cls, "name": "Test " + cls, "class": cls, "pos": [0, 0], "army": [["pike_militia", 5]]}, data)
	h.skills = skills.duplicate()
	return h


## Wears a temporary artifact with the given mods (removed by _drop_probe).
func _with_probe(h: Hero, mods: Dictionary) -> Hero:
	data.artifacts[PROBE] = {"name": "Probe", "slot": "charm", "rarity": "minor", "value": 1, "text": "", "mods": mods}
	h.equipment["charm"] = PROBE
	return h


func _drop_probe() -> void:
	data.artifacts.erase(PROBE)


func _side(stacks: Array, hero: Variant) -> Dictionary:
	var out := []
	for i in stacks.size():
		out.append({"slot": i, "creature": stacks[i][0], "count": stacks[i][1]})
	return {"name": "Side", "hero": hero, "stacks": out}


## A combat fingerprint over several seeds and two terrains: grass is native
## to the concord army, infernal is hostile. Our army has three roles (so
## combined arms is one role short); the enemy has flankers, archers and a
## dreadful hero that pushes our morale below zero.
func _combat_fingerprint(profile: Dictionary) -> String:
	var mine := [["pike_militia", 30], ["longbowman", 20], ["lancer", 4]]
	var theirs := [["cinderling", 40], ["scorchhound", 10], ["brimstone_hurler", 12], ["gorgewing", 2]]
	var foe := {"name": "Foe", "attack": 1, "defense": 1, "power": 0, "skills": {}, "mods": {"enemy_morale": 3}}
	var sim := CombatSimulator.new(data)
	var parts := []
	for terrain in ["grass", "infernal"]:
		for i in 6:
			var r := sim.simulate(CombatSimulator.make_setup(_side(mine, profile), _side(theirs, foe), terrain, 300 + i), false)
			parts.append("%d/%d/%d/%s" % [r["sides"][0]["hp_end"], r["sides"][1]["hp_end"], r["rounds"], str(r["stats"])])
	return "|".join(parts)


## Everything a hero's modifiers can change, as one comparable string.
func _fingerprint(h: Hero, session: GameSession) -> String:
	var parts := []
	parts.append(h.max_movement(data))
	parts.append(h.vision_radius(data))
	var cm := h.move_cost_mods(data)
	for t in ["forest", "desert", "snow", "swamp", "infernal", "rough", "river"]:
		parts.append(Pathfinder.adjusted_cost(int(data.terrains[t]["move_cost"]), t, false, cm))
	parts.append(h.xp_with_bonus(1000, data))
	for a in ["attack", "defense", "power", "knowledge"]:
		parts.append(h.total_attr(a, data))
	parts.append(HeroBattleEffects.recovered(1000, h.modifiers(data)))
	# Economy through the session: income and the recruiting price in town.
	var wren := session.hero("hero_wren")
	var keep := [wren.equipment.duplicate(), wren.pos]
	wren.equipment = h.equipment.duplicate()
	wren.pos = Vector2i(1, 8)  # Greyhold
	parts.append(str(session.daily_income(0)))
	parts.append(str(session.recruit_price("town_greyhold", "pike_militia", 10)))
	parts.append(session.scout_cost(wren.id))
	wren.equipment = keep[0]
	wren.pos = keep[1]
	var profile := h.combat_profile(data)
	profile["art"] = {"name": "Probe Art", "kind": "strike", "base": 20, "per_power": 10}
	parts.append(_combat_fingerprint(profile))
	h.add_xp(1000, data)
	parts.append(h.army.slots[0]["veteran_xp"])
	return "#".join(parts.map(func(x): return str(x)))


func test_every_modifier_key_has_an_effect() -> void:
	# spoils_pct pays out in GameSession.attack (test_reaver_spoils).
	var skip := ["spoils_pct"]
	var session := GameSession.new_game(data, "ember_ford", 3)
	var base_hero := _hero("knight", {})
	base_hero.skills = {}
	var base := _fingerprint(base_hero, session)
	var samples := {
		"role_attack": {"ranged": 2, "infantry": 2}, "role_defense": {"infantry": 2, "ranged": 2},
		"terrain_move_pct": {"forest": 0.5}, "income": {"gold": 100},
		"faction_attack": 2, "faction_defense": 2, "art_uses": 2, "art_power_pct": 0.5,
		"combined_arms_roles": 2, "enemy_morale": 2, "morale": 2, "morale_floor": 1, "native_bonus": 2,
		"screen": 0.5, "ignore_hostile_terrain": 1,
		"creature_attack": {"pike_militia": 2}, "creature_defense": {"pike_militia": 2},
	}
	for key in HeroModifiers.KEYS:
		if skip.has(key):
			continue
		var kind: String = HeroModifiers.KEYS[key]
		var v: Variant = samples.get(key, 2 if kind in ["int", "flag"] else 0.25)
		var h := _with_probe(_hero("knight", {}), {key: v})
		h.skills = {}
		var got := _fingerprint(h, session)
		_drop_probe()
		assert_ne(got, base, "modifier %s changes nothing" % key)


func test_skills_classes_and_artifacts_use_only_known_modifiers() -> void:
	var errors := data.validate_heroes()
	assert_eq(errors.size(), 0, "\n".join(errors))
	assert_true(data.skills.size() >= 12, "skill variety")
	assert_eq(data.hero_classes.size(), 24)   # 3 per faction, art packs included
	assert_true(data.artifacts.size() >= 20, "artifact variety")


func test_classes_differ() -> void:
	# No two classes share the same trait, art and starting skills.
	var seen := {}
	for cid in data.hero_classes:
		var c: Dictionary = data.hero_classes[cid]
		var key := "%s|%s|%s" % [str(c["trait"]["mods"]) + str(c["trait"].get("per_level", {})), c["art"]["name"], str(c["skills"])]
		assert_false(seen.has(key), "%s duplicates %s" % [cid, seen.get(key, "")])
		seen[key] = cid


func test_offers_only_from_class_weights() -> void:
	var h := _hero("warlock")
	h.skill_points = 1
	for s in 20:
		for sk in h.skill_offers_seeded(data, s):
			assert_true(data.hero_classes["warlock"]["skill_weights"].has(sk), sk)


func test_growth_follows_class() -> void:
	var lock := _hero("warlock")
	var lord := _hero("warlord")
	lock.add_xp(41000, data)
	lord.add_xp(41000, data)
	assert_eq(lock.level, 10)
	assert_eq(lord.power, 0, "warlords never grow power")
	assert_gt(lock.power, lord.power + 2, "warlocks grow power")
	assert_gt(lord.attack, lock.attack + 3, "warlords grow attack")
	# Nine levels add nine primary points: progression stays modest.
	assert_eq(lock.attack + lock.defense + lock.power + lock.knowledge, 5 + 9)


# ------------------------------------------------------------ consumers ----

func test_logistics_and_wayfinding_move_further() -> void:
	var plain := _hero("knight", {})
	assert_eq(plain.max_movement(data), 1500)
	var fast := _hero("knight", {"logistics": 2})
	assert_eq(fast.max_movement(data), 1800)
	var way := _hero("knight", {"wayfinding": 2})
	assert_eq(Pathfinder.adjusted_cost(150, "forest", false, way.move_cost_mods(data)), 125)
	assert_eq(Pathfinder.adjusted_cost(150, "forest", true, way.move_cost_mods(data)), 150, "roads are untouched")
	assert_eq(Pathfinder.adjusted_cost(100, "grass", false, way.move_cost_mods(data)), 100)


func test_ranger_crosses_forest_cheaply_in_a_session() -> void:
	var s := GameSession.new_game(data, "ember_ford", 5)
	var maelis := s.hero("hero_maelis")   # ranger: Woodwise
	var wren := s.hero("hero_wren")       # knight
	var path: Array[Vector2i] = [Vector2i(3, 6)]
	assert_eq(s.state.map.terrain_at(path[0]), "forest")
	assert_eq(s.pathfinder.step_costs(Vector2i(3, 7), path, maelis.move_cost_mods(data))[0], 125)
	assert_eq(s.pathfinder.step_costs(Vector2i(3, 7), path, wren.move_cost_mods(data))[0], 150)


func test_scouting_and_oracle_vision() -> void:
	assert_eq(_hero("knight", {}).vision_radius(data), 4)
	assert_eq(_hero("knight", {"scouting": 3}).vision_radius(data), 7)
	assert_eq(_hero("oracle", {}).vision_radius(data), 5, "Clear Sight")


func test_lore_and_level_cap() -> void:
	var h := _hero("knight", {"lore": 2})
	assert_eq(h.xp_with_bonus(1000, data), 1100)
	h.level_cap = 2
	assert_eq(h.add_xp(5000, data), 1, "capped at level 2")
	assert_eq(h.xp, 5000, "XP is banked")
	h.level_cap = 4
	assert_eq(h.add_xp(0, data), 2, "banked XP pays out when the cap rises")


func test_onslaught_wins_more() -> void:
	var sim := CombatSimulator.new(data)
	var army := [["pike_militia", 30], ["shieldwarden", 6]]
	var wins := [0, 0]
	for i in 200:
		for k in 2:
			var prof := {"name": "H", "attack": 0, "defense": 0, "power": 0, "skills": {"onslaught": 3} if k == 1 else {}}
			var r := sim.simulate(CombatSimulator.make_setup(_side(army, prof), _side(army, {"name": "F", "attack": 0, "defense": 0, "power": 0, "skills": {}}), "rough", 900 + i), false)
			if r["winner"] == 0:
				wins[k] += 1
	assert_gt(wins[1], wins[0] + 20, "onslaught %d vs %d" % [wins[1], wins[0]])


func test_battle_arts_act() -> void:
	var sim := CombatSimulator.new(data)
	var army := [["pike_militia", 20], ["longbowman", 12]]
	var enemy := [["cinderling", 30], ["brimstone_hurler", 10]]
	var warlock := _hero("warlock").combat_profile(data)
	var r := sim.simulate(CombatSimulator.make_setup(_side(army, warlock), _side(enemy, null), "rough", 11), true)
	assert_gt(r["stats"]["art_damage"], 0, "Cinderfall hits")
	var arts: Array = r["log"].filter(func(e): return String(e["type"]).begins_with("art_"))
	# Knowledge 2 -> 1 + 1 = 2 uses.
	assert_eq(arts.size(), 2)
	# Mending restores hit points.
	var oracle := _hero("oracle").combat_profile(data)
	var m := sim.simulate(CombatSimulator.make_setup(_side(army, oracle), _side(enemy, null), "rough", 11), true)
	assert_gt(m["log"].filter(func(e): return e["type"] == "art_mend").size(), 0)
	# Determinism: a battle without heroes is unchanged by the art machinery.
	var a := sim.simulate(CombatSimulator.make_setup(_side(army, null), _side(enemy, null), "rough", 5), false)
	var b := sim.simulate(CombatSimulator.make_setup(_side(army, null), _side(enemy, null), "rough", 5), false)
	assert_eq(str(a), str(b))


func test_ward_and_hex_reduce_damage_taken() -> void:
	var sim := CombatSimulator.new(data)
	var army := [["pike_militia", 30], ["longbowman", 15]]
	var plain := {"name": "P", "attack": 0, "defense": 0, "power": 2, "knowledge": 4, "skills": {}, "mods": {}}
	var loss := {"none": 0, "ward": 0, "hex": 0}
	for kind in loss:
		var prof := plain.duplicate()
		if kind != "none":
			prof["art"] = {"name": kind, "kind": kind, "base": 0.3, "per_power": 0.0}
		for i in 150:
			var r := sim.simulate(CombatSimulator.make_setup(_side(army, prof), _side(army, null), "rough", 40 + i), false)
			loss[kind] += r["sides"][0]["hp_start"] - r["sides"][0]["hp_end"]
	assert_lt(loss["ward"], loss["none"] * 0.95, str(loss))
	assert_lt(loss["hex"], loss["none"] * 0.98, str(loss))


func test_dread_lowers_enemy_morale() -> void:
	var sim := CombatSimulator.new(data)
	var army := [["pike_militia", 30]]
	var torment := _hero("tormentor").combat_profile(data)
	var r := sim.simulate(CombatSimulator.make_setup(_side(army, torment), _side(army, null), "rough", 1), true)
	var notes: Array = r["sides"][1]["notes"]
	assert_true(notes.any(func(n): return String(n).begins_with("Dread")), str(notes))


func test_fieldcraft_ignores_hostile_terrain() -> void:
	var sim := CombatSimulator.new(data)
	var army := [["pike_militia", 30]]
	var plain := {"name": "P", "attack": 0, "defense": 0, "power": 0, "skills": {}}
	var crafty := {"name": "C", "attack": 0, "defense": 0, "power": 0, "skills": {"fieldcraft": 1}}
	var r1 := sim.simulate(CombatSimulator.make_setup(_side(army, plain), _side(army, null), "infernal", 1), true)
	var r2 := sim.simulate(CombatSimulator.make_setup(_side(army, crafty), _side(army, null), "infernal", 1), true)
	assert_true(r1["sides"][0]["notes"].any(func(n): return "hostile" in String(n)))
	assert_false(r2["sides"][0]["notes"].any(func(n): return "hostile terrain (" in String(n)))
