extends "res://tests/test_case.gd"
## Layout families of the random-map generator (LayoutFamilies, map overhaul
## step 1): per-seed orientation, moving town spots, wide open passes with
## one-tile guarded chokepoints, mixed rock and lake walls, more room per
## player, fewer neutral towns and optional zones.


func _cfg() -> Dictionary:
	return data.map_templates


func _start_anchor(t: Dictionary, player: int) -> Vector2:
	for z in t["zones"]:
		if int(z.get("player", -1)) == player:
			return Vector2(float(z["anchor"][0]), float(z["anchor"][1]))
	return Vector2(-1, -1)


func _sector(v: Vector2) -> int:
	return int(round(fposmod(v.angle(), TAU) / (TAU / 8.0))) % 8


func test_every_family_is_known_and_generates_valid_maps() -> void:
	assert_eq(LayoutFamilies.validate(_cfg()), [] as Array[String])
	for fam in LayoutFamilies.ids(_cfg()):
		assert_true(LayoutFamilies.FAMILIES.has(fam), fam)
		var tname := RandomMapTemplate.make_name("s", 2, "normal", "normal", fam)
		for s in [1, 2]:
			var g := MapGenerator.new(data)
			var def := g.run(tname, s)
			assert_false(def.is_empty(), "%s seed %d generates (%s)" % [fam, s, g.rejected])
			if def.is_empty():
				continue
			assert_eq(MapValidator.validate(def, data), [] as Array[String], "%s seed %d" % [fam, s])
			assert_eq(String(def["generator"]["layout_family"]), fam)


func test_multi_player_families_hold_four_players() -> void:
	for fam in LayoutFamilies.for_players(_cfg(), 4):
		var tname := RandomMapTemplate.make_name("m", 4, "normal", "normal", fam)
		var g := MapGenerator.new(data)
		var def := g.run(tname, 3)
		assert_false(def.is_empty(), "%s for 4 players generates (%s)" % [fam, g.rejected])
		if not def.is_empty():
			assert_eq(MapValidator.validate(def, data), [] as Array[String], fam)
			assert_eq((def["heroes"] as Array).size(), 4)
	assert_true(LayoutFamilies.for_players(_cfg(), 4).size() >= 3, "ring, hub and archipelago hold four players")


func test_no_family_plays_in_a_single_direction() -> void:
	# The line between the two starts points in many compass directions over
	# a handful of seeds, in every family (8 orientations per seed).
	for fam in LayoutFamilies.for_players(_cfg(), 2):
		var sectors := {}
		var orients := {}
		for s in range(1, 13):
			var t := RandomMapTemplate.build(_cfg(), RandomMapTemplate.make_name("m", 2, "normal", "normal", fam), s)
			sectors[_sector(_start_anchor(t, 1) - _start_anchor(t, 0))] = true
			orients[int(t["orientation"])] = true
		assert_true(sectors.size() >= 4, "%s points in %d directions over 12 seeds" % [fam, sectors.size()])
		assert_true(orients.size() >= 5, "%s uses %d orientations over 12 seeds" % [fam, orients.size()])


func test_towns_never_sit_on_fixed_tiles() -> void:
	for fam in LayoutFamilies.for_players(_cfg(), 2):
		var spots := {}
		for s in range(1, 9):
			var t := RandomMapTemplate.build(_cfg(), RandomMapTemplate.make_name("m", 2, "normal", "normal", fam), s)
			var a := _start_anchor(t, 0)
			spots["%.2f,%.2f" % [a.x, a.y]] = true
		assert_eq(spots.size(), 8, "%s: player 0 starts somewhere else on every seed" % fam)
	# And in the generated maps themselves.
	var tiles := {}
	for s in range(1, 6):
		var def := MapGenerator.generate(data, "random_s_2p_normal_normal_diagonal", s)
		for o in def["objects"]:
			if o["type"] == "town" and int(o.get("owner", -1)) == 0:
				tiles["%d,%d" % [int(o["pos"][0]), int(o["pos"][1])]] = true
	assert_eq(tiles.size(), 5, "five seeds, five different town tiles")


func test_open_passes_are_wide_and_guarded_passes_are_chokepoints() -> void:
	var widths := {}
	for fam in ["diagonal", "lanes", "hub"]:
		var def := MapGenerator.generate(data, RandomMapTemplate.make_name("s", 2, "normal", "normal", fam), 4)
		for c in def["generator"]["connections"]:
			var n := (c["gate"] as Array).size()
			if String(c["guard"]) != "":
				assert_eq(n, 1, "%s: a guarded pass is one tile, the guard is the chokepoint" % fam)
			else:
				assert_true(n >= 2 and n <= 4, "%s: an open pass is 2-4 tiles wide (%d)" % [fam, n])
				widths[n] = true
	assert_true(widths.size() >= 2, "open pass widths vary")
	# Templates never ask for a wide guarded pass.
	for s in range(1, 6):
		var t := RandomMapTemplate.build(_cfg(), "random_l_4p_normal_normal_ring", s)
		for c in t["connections"]:
			if String(c["guard"]) != "none":
				assert_eq(int(c["width"]), 1)


func test_walls_mix_rock_and_lakes() -> void:
	var count := func(def: Dictionary, ch: String) -> int:
		var n := 0
		for row in def["terrain"]:
			n += String(row).count(ch)
		return n
	var water := String(data.terrain("water")["char"])
	var rock := String(data.terrain("mountain")["char"])
	var isles := MapGenerator.generate(data, "random_s_2p_normal_normal_archipelago", 2)
	assert_gt(count.call(isles, water), count.call(isles, rock), "an archipelago is cut by lakes")
	var mixed := 0
	for s in range(1, 5):
		var def := MapGenerator.generate(data, "random_s_2p_normal_normal_lanes", s)
		if count.call(def, water) > 40 and count.call(def, rock) > 40:
			mixed += 1
	assert_gt(mixed, 1, "other families mix ridges and lakes")


func test_maps_have_more_room_per_player() -> void:
	# Before the overhaul a medium two-player map was 50x50 (1250 tiles per
	# player) and a large four-player map 82x82 (about 1700).
	var m2 := RandomMapTemplate.build(_cfg(), "random_m_2p_normal_normal", 1)
	assert_gt(int(m2["width"]) * int(m2["height"]) / 2.0, 1250 * 1.5)
	var l4 := RandomMapTemplate.build(_cfg(), "random_l_4p_normal_normal", 1)
	assert_gt(int(l4["width"]) * int(l4["height"]) / 4.0, 1700 * 1.5)


func test_neutral_towns_are_few_and_contested() -> void:
	var counts := {}
	for fam in LayoutFamilies.for_players(_cfg(), 2):
		for s in range(1, 9):
			var t := RandomMapTemplate.build(_cfg(), RandomMapTemplate.make_name("m", 2, "normal", "normal", fam), s)
			var n := 0
			for z in t["zones"]:
				if z.has("player"):
					continue
				assert_true(["neutral", "none"].has(String(z.get("town", ""))), "every zone says whether it has a town")
				if z["town"] == "neutral":
					n += 1
					assert_ne(String(z["group"]), "start")
			assert_true(n <= 2, "%s seed %d: at most two neutral towns (%d)" % [fam, s, n])
			counts[n] = true
	assert_true(counts.has(0) and counts.has(1) and counts.has(2), "maps have none, one or two neutral towns")
	# The heart, as far from one start as from the other, is the favourite.
	var heart := 0
	for s in range(1, 21):
		var t := RandomMapTemplate.build(_cfg(), "random_m_2p_normal_normal_hub", s)
		for z in t["zones"]:
			if z["id"] == "heart" and z["town"] == "neutral":
				heart += 1
	assert_gt(heart, 8, "the contested heart usually holds the town")


func test_optional_zones_get_varied_profiles() -> void:
	var profiles := {}
	for s in range(1, 13):
		var t := RandomMapTemplate.build(_cfg(), "random_m_2p_normal_normal_tree", s)
		for z in t["zones"]:
			if bool(z.get("optional", false)):
				profiles[z["profile"]] = true
	for p in ["valley", "mineland", "ruins"]:
		assert_true(profiles.has(p), "optional zones can be %s" % p)
	var def := MapGenerator.generate(data, "random_m_2p_normal_normal_tree", 2)
	var open := 0
	var opt := 0
	for z in def["generator"]["zones"]:
		open += int(z["tiles"])
		if bool(z.get("optional", false)):
			opt += int(z["tiles"])
	assert_gt(float(opt) / float(open), 0.2, "a fifth of the map or more is optional ground")


func test_mixed_maps_pick_families_by_seed_and_stay_deterministic() -> void:
	var seen := {}
	for s in range(1, 25):
		seen[RandomMapTemplate.family_for(_cfg(), "random_m_2p_normal_normal", s)] = true
	assert_true(seen.size() >= 4, "a mixed random map plays %d families over 24 seeds" % seen.size())
	for s in range(1, 25):
		assert_true(LayoutFamilies.supports(_cfg(), RandomMapTemplate.family_for(_cfg(), "random_m_5p_normal_normal", s), 5))
	var a := MapGenerator.generate(data, "random_s_2p_normal_normal", 9)
	var b := MapGenerator.generate(data, "random_s_2p_normal_normal", 9)
	assert_eq(a, b, "same name and seed, same map")


func test_orientation_keeps_point_symmetry() -> void:
	for o in LayoutFamilies.ORIENTATIONS:
		var p := Vector2(0.2, 0.7)
		var q: Array = LayoutFamilies.oriented(p, o)
		var m: Array = LayoutFamilies.oriented(Vector2(1.0, 1.0) - p, o)
		assert_true(is_equal_approx(float(q[0]) + float(m[0]), 1.0) and is_equal_approx(float(q[1]) + float(m[1]), 1.0), "orientation %d" % o)
	var seen := {}
	for o in LayoutFamilies.ORIENTATIONS:
		seen[str(LayoutFamilies.oriented(Vector2(0.1, 0.3), o))] = true
	assert_eq(seen.size(), 8, "eight different orientations")


func test_bad_family_settings_are_reported() -> void:
	var cfg := _cfg().duplicate(true)
	cfg["random_maps"]["families"]["moat"] = {"min_players": 2, "max_players": 2}
	cfg["random_maps"]["families"]["hub"]["walls"] = {"water": 2.0, "thick": [3, 1]}
	cfg["random_maps"]["families"]["ring"]["max_players"] = 1
	cfg["random_maps"]["optional_profiles"]["castle"] = 1
	cfg["random_maps"]["pass_width"] = [1, 3]
	var errors := LayoutFamilies.validate(cfg)
	for want in ["moat: unknown", "walls.water", "walls.thick", "bad player range", "optional profile castle", "pass_width"]:
		assert_true(errors.any(func(e): return String(e).contains(want)), "reports: " + want)
