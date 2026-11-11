extends "res://tests/test_case.gd"
## Attack lean (BattleFigure) and elemental battle effects (BattleFx).


func test_attack_lean_draws_back_then_strikes() -> void:
	assert_lt(BattleFigure.attack_lean(0.1, 0.2, 0.5), 0.0, "winds up before the blow")
	assert_gt(BattleFigure.attack_lean(0.28, 0.2, 0.5), 0.05, "lunges on the blow")
	assert_eq(BattleFigure.attack_lean(-0.1, 0.2, 0.5), 0.0)
	assert_eq(BattleFigure.attack_lean(2.0, 0.2, 0.5), 0.0)
	assert_lt(absf(BattleFigure.attack_lean(0.74, 0.2, 0.5)), 0.01, "settles at the end")


func test_fx_table_names_real_creatures_and_elements() -> void:
	var data := GameData.get_default()
	var t := BattleFx.table()
	assert_false((t.get("creatures", {}) as Dictionary).is_empty(), "battle_fx.json lists creatures")
	for id in t["creatures"]:
		assert_false(data.creature(id).is_empty(), "battle_fx.json: unknown creature %s" % id)
		assert_true(t["creatures"][id] in BattleFx.ELEMENTS, "%s: unknown element" % id)
	for type in t["events"]:
		assert_true(t["events"][type] in BattleFx.ELEMENTS, "event %s: unknown element" % type)
	for e in BattleFx.ELEMENTS:
		assert_true(BattleFx.STYLES.has(e), "no style for element %s" % e)


func test_every_caster_and_breather_has_an_element() -> void:
	var data := GameData.get_default()
	for id in data.creatures:
		var c := data.creature(id)
		var ids := []
		for a in c.get("abilities", []):
			ids.append(String(a.get("id", "")))
		if "caster" in c.get("tags", []) or "breath" in ids or "poison" in ids:
			assert_ne(BattleFx.element_of(id), "", "%s attacks without an effect" % id)
	assert_eq(BattleFx.element_of("longbowman"), "", "archers keep the plain arrow")
	assert_eq(BattleFx.element_of("ash_witch"), "fire")


func test_event_elements() -> void:
	assert_eq(BattleFx.element_for_event("poison"), "poison")
	assert_eq(BattleFx.element_for_event("heal"), "life")
	assert_eq(BattleFx.element_for_event("breath", "winter_wyrm_ancient"), "frost")
	assert_eq(BattleFx.element_for_event("splash", "pike_militia"), "blast")
	assert_eq(BattleFx.element_for_event("melee"), "")


func test_burst_and_projectile_build_and_free() -> void:
	var root := Node2D.new()
	for e in BattleFx.ELEMENTS:
		var p := BattleFx.burst(root, Vector2(10, 10), e, 1.0)
		assert_true(p.amount >= 6, "%s burst has particles" % e)
		var bolt := BattleFx.projectile(e)
		assert_gt(float(bolt.get_child_count()), 0.0, "%s projectile has parts" % e)
		bolt.free()
	root.free()


func test_gore_follows_what_a_creature_is_made_of() -> void:
	assert_eq(BattleGore.kind_from(["human"]), "blood")
	assert_eq(BattleGore.kind_from(["undead"]), "bone")
	assert_eq(BattleGore.kind_from(["undead", "spirit"]), "wisp")
	assert_eq(BattleGore.kind_from(["construct"]), "sparks")
	assert_eq(BattleGore.kind_from(["demon"]), "ember")
	assert_eq(BattleGore.kind_from(["treant"]), "sap")
	assert_eq(BattleGore.kind_from([], "fishmen"), "ichor")
	var data := GameData.get_default()
	for id in data.creatures:
		assert_true(BattleGore.KINDS.has(BattleGore.kind_of(id)), id)
	for k in BattleGore.KINDS:
		var st: Dictionary = BattleGore.KINDS[k]
		for field in ["colors", "gravity", "speed", "pool", "death", "corpse"]:
			assert_true(st.has(field), "%s lacks %s" % [k, field])
		assert_true(st["death"] in ["fall", "crumble", "fade", "topple"], k)


func test_gore_builds_and_frees() -> void:
	var root := Node2D.new()
	for k in BattleGore.KINDS:
		assert_gt(BattleGore.death_burst(root, Vector2.ZERO, k, 1.0).amount, 1, k)
		BattleGore.spurt(root, Vector2.ZERO, k, -1.0)
		var pool := BattleGore.pool(root, Vector2(5, 5), k, 40.0)
		assert_eq(pool == null, String(BattleGore.KINDS[k]["pool"]) == "", "%s pool" % k)
	assert_true(BattleGore.poison_cloud(root, Vector2.ZERO) != null)
	var sh := BattleGore.shadow(40.0)
	assert_true(sh.texture != null)
	sh.free()
	assert_eq(BattleGore.blob(Vector2(3, 4), 20.0, 8.0, 12), BattleGore.blob(Vector2(3, 4), 20.0, 8.0, 12), "stains are stable")
	root.free()


func test_creatures_without_an_idle_sheet_keep_the_still() -> void:
	var manifest := UnitAnimation.manifest()
	for sid in manifest.get("units", {}):
		var has_clip: bool = manifest["units"][sid]["actions"].has("idle")
		var id := String(sid).trim_prefix("creature_")
		assert_eq(not CreatureAnims.frames(id, "idle").is_empty(), has_clip, sid)
