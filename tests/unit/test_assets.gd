extends "res://tests/test_case.gd"
## Built art (assets/manifest.json + atlases) against game data, and the
## terrain-transition maths used by MapView.

var tiles: TerrainTiles


func before_each() -> void:
	if tiles == null:
		Art.reload()
		tiles = TerrainTiles.new(Art.terrain_info())


func test_manifest_loads() -> void:
	var m := Art.manifest()
	assert_eq(int(m.get("version", 0)), 1, "manifest version")
	for a in ["units", "objects", "ui"]:
		assert_true(m["atlases"].has(a), "atlas " + a)
		assert_true(Art.texture_at(m["atlases"][a]["path"]) != null, "atlas texture loads: " + a)


func test_every_creature_has_a_sprite() -> void:
	for cid in data.creatures:
		var tex := Art.creature(cid)
		assert_true(tex != null, "sprite for " + cid)
		if tex != null:
			var sz := tex.get_size()
			assert_true(sz.x >= 32 and sz.y >= 32, "%s at least 32 px" % cid)
			assert_eq(Art.anchor("creature_" + cid), Vector2(int(sz.x) / 2, sz.y - 1), "feet anchor " + cid)


func test_every_resource_has_an_icon() -> void:
	for rid in data.resource_order:
		assert_true(Art.resource_icon(rid) != null, "icon for " + rid)


func test_ui_frames_build_styleboxes() -> void:
	for id in ["ui_panel", "ui_button", "ui_button_hover", "ui_button_pressed", "ui_button_disabled", "ui_slot"]:
		var sb := Art.stylebox(id)
		assert_true(sb != null, id)
		if sb != null:
			assert_gt(sb.texture_margin_left, 0.0, id + " nine-slice")
	assert_true(UiStyle.frame_panel() is StyleBoxTexture, "theme uses the art frame")
	assert_eq(Art.sprite("no_such_sprite"), null, "missing sprite is null, not an error")


func test_terrain_tileset_covers_all_terrains() -> void:
	assert_true(tiles.is_valid(), "tileset builds")
	for tid in data.terrains:
		assert_true(tiles.terrain_row(tid) >= 0, "terrain row for " + tid)
	var src: TileSetAtlasSource = tiles.tile_set.get_source(TerrainTiles.SOURCE_TERRAIN)
	for tid in data.terrains:
		var row := tiles.terrain_row(tid)
		for m in tiles.info["transition_masks"]:
			for x in 24:
				assert_true(src.has_tile(tiles.transition_coords(row, int(m), Vector2i(x, 3))), "%s mask %d" % [tid, m])
	for m in 16:
		assert_true(src.has_tile(tiles.road_coords(m, false)), "road %d" % m)
		assert_true(src.has_tile(tiles.road_coords(m, true)), "bridge %d" % m)


func test_reduce_mask_matches_pipeline() -> void:
	var seen := {}
	for bits in range(1, 256):
		seen[TerrainTiles.reduce_mask(bits)] = true
	seen.erase(0)
	var keys := seen.keys()
	keys.sort()
	var expected: Array = tiles.info["transition_masks"].map(func(v): return int(v))
	assert_eq(keys.size(), 46, "46 distinct transition shapes")
	assert_eq(keys, expected, "same masks and order as tools/assets procedural.all_transition_masks")


func test_reduce_mask_drops_covered_corners() -> void:
	var N := TerrainTiles.N
	assert_eq(TerrainTiles.reduce_mask(N | TerrainTiles.NE | TerrainTiles.NW), N, "edge covers its corners")
	assert_eq(TerrainTiles.reduce_mask(TerrainTiles.SE), TerrainTiles.SE, "lone corner kept")
	assert_eq(TerrainTiles.reduce_mask(0), 0)


func test_themed_road_masks_resolve_from_json() -> void:
	var src: TileSetAtlasSource = tiles.tile_set.get_source(TerrainTiles.SOURCE_TERRAIN)
	for style in ["stone", "dirt", "desert"]:
		for bits in range(256):
			var coords := tiles.themed_road_coords(style, Vector2i(1, 1), bits)
			assert_true(coords.x >= 0 and src.has_tile(coords), "%s road mask %d" % [style, bits])
	assert_eq(TerrainTiles.mask_index([0.0, 4.0, 68.0], 68), 2, "JSON numeric masks")


func test_highres_road_and_barrier_tiles() -> void:
	assert_true(tiles.highres_tile_set != null, "high-resolution overlays load")
	if tiles.highres_tile_set == null:
		return
	assert_eq(tiles.highres_tile_set.tile_size, Vector2i(80, 80))
	var source: TileSetAtlasSource = tiles.highres_tile_set.get_source(TerrainTiles.SOURCE_TERRAIN)
	for style in ["stone", "dirt", "desert"]:
		var coords := tiles.highres_coords("roads", style, Vector2i(1, 1), TerrainTiles.E | TerrainTiles.W)
		assert_true(coords.x >= 0 and source.has_tile(coords), "high-resolution road: " + style)
	for style in ["wall", "lava", "jungle", "chasm", "sandstone", "ice", "bones"]:
		var coords := tiles.highres_coords("barriers", style, Vector2i(1, 1), TerrainTiles.NW | TerrainTiles.SE)
		assert_true(coords.x >= 0 and source.has_tile(coords), "high-resolution barrier: " + style)


func test_barrier_biome_matches_nearest_land() -> void:
	var session := GameSession.new_game(data, "ember_ford", 7)
	var map: AdventureMap = session.state.map
	var view := MapView.new()
	view.session = session
	view.tiles = tiles
	var p := Vector2i(4, 4)
	for biome in ["grass", "forest", "swamp", "desert", "rough", "snow", "infernal"]:
		for i in map.terrain.size():
			map.terrain[i] = biome
		map.terrain[map.index(p)] = "mountain"
		map.road.fill(0)
		view._barrier_biomes.clear()
		view._barrier_styles.clear()
		assert_eq(view._barrier_biome(map, p), biome, "nearby terrain: " + biome)
		var style := view._barrier_style(p)
		var expected: String = "mountain" if style == 0 else biome
		assert_eq(view._visual_terrain(map, p), expected, "barrier ground: " + biome)
	view.free()


func test_neighbor_bits() -> void:
	var water := {Vector2i(5, 4): true, Vector2i(6, 6): true}
	var bits := TerrainTiles.neighbor_bits(func(c: Vector2i) -> bool: return water.has(c), Vector2i(5, 5))
	assert_eq(bits, TerrainTiles.N | TerrainTiles.SE)
	var road := {Vector2i(4, 5): true, Vector2i(5, 6): true}
	assert_eq(TerrainTiles.road_mask(func(c: Vector2i) -> bool: return road.has(c), Vector2i(5, 5)), TerrainTiles.RW | TerrainTiles.RS)


func test_cell_hash_is_stable_and_in_range() -> void:
	for i in 50:
		var t := Vector2i(i * 7 % 23, i * 3 % 17)
		var h := TerrainTiles.cell_hash(t, 4)
		assert_between(h, 0, 3)
		assert_eq(h, TerrainTiles.cell_hash(t, 4), "deterministic")


func test_ground_detail_is_stable_and_uses_atlas_tiles() -> void:
	var src: TileSetAtlasSource = tiles.tile_set.get_source(TerrainTiles.SOURCE_TERRAIN)
	var placed := 0
	for x in 80:
		var pos := Vector2i(x, x * 3)
		var detail := tiles.detail_coords("grass", pos)
		assert_eq(detail, tiles.detail_coords("grass", pos), "visual selection is stable")
		if detail.x >= 0:
			placed += 1
			assert_true(src.has_tile(detail), "detail atlas tile exists")
	assert_true(placed > 0 and placed < 80, "details are sparse")


func test_deco_follows_terrain_spec() -> void:
	var forest := 0
	for i in 40:
		var t := Vector2i(i, i * 2)
		if tiles.deco_coords("forest", t).x >= 0:
			forest += 1
		assert_eq(tiles.deco_coords("water", t), Vector2i(-1, -1), "open water stays bare")
	assert_eq(forest, 40, "every forest cell gets trees")


func test_fog_tiles() -> void:
	assert_true(tiles.fog_coords(Vector2i(1, 1), 0, false).x >= 0, "unexplored cell is shrouded")
	assert_eq(tiles.fog_coords(Vector2i(1, 1), 0, true), Vector2i(-1, -1), "explored interior is clear")
	assert_true(tiles.fog_coords(Vector2i(1, 1), TerrainTiles.E, true).x >= 0, "explored edge gets a soft fringe")


func test_specific_edges_replace_haze_but_other_pairs_keep_blending() -> void:
	var session := GameSession.new_game(data, "ember_ford", 1)
	var map := session.state.map
	var grass := Vector2i(2, 2)
	var water := Vector2i(3, 2)
	map.terrain[map.index(grass)] = "grass"
	map.terrain[map.index(water)] = "water"
	map.terrain[map.index(Vector2i(4, 2))] = "desert"
	map.terrain[map.index(Vector2i(2, 3))] = "desert"
	map.terrain[map.index(Vector2i(2, 1))] = "snow"
	var mv := MapView.new()
	mv._ready()
	mv.bind(session)
	assert_eq(mv._blends["water"].get_cell_source_id(grass), -1, "dedicated shore has no water haze")
	assert_eq(mv._blends["grass"].get_cell_source_id(water), -1, "dedicated shore has no grass haze")
	assert_true(mv._blends["snow"].get_cell_source_id(grass) >= 0, "other pairs retain the general blend")
	assert_true(mv._edges["cliff"].get_cell_source_id(grass) == TerrainTiles.SOURCE_EDGES, "shore edge is placed on grass")
	assert_true(mv._edges["beach"].get_cell_source_id(Vector2i(4, 2)) == TerrainTiles.SOURCE_EDGES, "beach is placed on desert")
	assert_true(mv._edges["dry_grass"].get_cell_source_id(grass) == TerrainTiles.SOURCE_EDGES, "dry margin is placed on grass")
	mv.free()


func test_pair_edges_continue_along_boundary_and_shift_slowly() -> void:
	var n := tiles.edge_coords("grass", "cliff", TerrainTiles.N, Vector2i(2, 2))
	var next := tiles.edge_coords("grass", "cliff", TerrainTiles.N, Vector2i(3, 2))
	var shifted := tiles.edge_coords("grass", "cliff", TerrainTiles.N, Vector2i(2, 8))
	assert_true(n.x >= 0, "grass and water have a cliff edge")
	assert_eq(next.x, n.x + 1, "adjacent tiles advance one phase")
	assert_eq(shifted.x, n.x + 1, "different shoreline shifts phase slowly")
	assert_true(tiles.edge_coords("desert", "beach", TerrainTiles.N, Vector2i.ZERO).x >= 0, "desert and water have a beach")
	assert_true(tiles.edge_coords("grass", "cliff_river", TerrainTiles.N, Vector2i.ZERO).x >= 0, "river cliffs use river water")
	assert_true(tiles.edge_coords("desert", "beach_river", TerrainTiles.N, Vector2i.ZERO).x >= 0, "river beaches use river water")
	assert_true(tiles.edge_coords("grass", "dry_grass", TerrainTiles.N, Vector2i.ZERO).x >= 0, "grass and desert have a dry margin")
	assert_eq(tiles.edge_coords("snow", "cliff", TerrainTiles.N, Vector2i.ZERO), Vector2i(-1, -1), "other pairs use the general blend")


func test_map_object_sprite_ids() -> void:
	var mv := MapView.new()
	assert_eq(mv.object_sprite_id({"type": "resource", "resource": "gems"}), "resource_gems")
	assert_eq(mv.object_sprite_id({"type": "neutral_army", "stacks": [["thornwolf", 3]]}), "creature_thornwolf")
	assert_eq(mv.object_sprite_id({"type": "town", "town_type": "ashen"}), "town_ashen")
	assert_eq(mv.object_sprite_id({"type": "mine", "resource": "sulfur"}), "mine_sulfur")
	assert_eq(mv.object_sprite_id({"type": "encounter", "encounter": "ember_rift"}), "encounter_ember_rift")
	assert_eq(mv.object_sprite_id({"type": "chest", "sprite": "object_chest"}), "object_chest")
	assert_eq(mv.object_sprite_id({"type": "shrine_of_something"}), "")
	for o in GameSession.new_game(data, "ember_ford", 1).state.map.objects.values():
		assert_true(Art.has_sprite(mv.object_sprite_id(o)), "sprite for map object " + String(o["id"]))
	mv.free()


func test_towns_mines_and_encounters_have_art() -> void:
	for tt in data.town_types:
		assert_true(Art.sprite("town_" + tt) != null, "town " + tt)
		assert_true(Art.sprite_info("town_" + tt).has("flag"), "owner flag point on town " + tt)
	for r in data.resource_order:
		assert_true(Art.sprite("mine_" + r) != null, "mine " + r)
	for e in data.encounters:
		assert_true(Art.sprite(EncounterSystem.sprite_id(e, data)) != null, "encounter " + e)
	assert_true(Art.sprite("object_flag") != null, "owner pennant")


func test_every_hero_class_has_its_own_mounted_sprite() -> void:
	var seen := {}
	for cid in data.hero_classes:
		var sid := Art.hero_sprite_id(cid)
		assert_eq(sid, "hero_" + cid, "own sprite for hero class " + cid)
		assert_true(Art.hero(cid) != null, "texture for hero class " + cid)
		assert_false(seen.has(sid), "sprite shared by two classes: " + sid)
		seen[sid] = true
	assert_eq(Art.hero_sprite_id("no_such_class"), "hero_knight", "unknown classes fall back to the knight")


func test_hero_portrait_shows_the_class_sprite() -> void:
	var p := HeroPortrait.new(1)
	p.set_hero_class("necromancer")
	assert_eq(p._hero, Art.hero("necromancer"))
	p.set_hero_class("thane")
	assert_eq(p._hero, Art.hero("thane"))
	p.free()


func test_hero_banners_take_their_players_colour() -> void:
	var st: GameState = GameSession.new_game(data, "ember_ford", 1).state
	var tints := {}
	for pid in range(st.players.size()):
		var c := Color(st.player(pid)["color"])
		var t := Art.banner_tint(c)
		assert_true(t.r >= c.r and t.g >= c.g and t.b >= c.b, "tint keeps the player's hue")
		tints[t.to_html()] = true
	assert_eq(tints.size(), st.players.size(), "every player's banner has its own colour")
	var p := HeroPortrait.new(1)
	p.set_owner_color(Color(st.player(0)["color"]))
	assert_eq(p.banner_color, Art.banner_tint(Color(st.player(0)["color"])))
	p.free()



func test_hero_portrait_keeps_large_sprites_inside_its_frame() -> void:
	var p := HeroPortrait.new(1)
	p.size = p.custom_minimum_size
	p.set_hero_class("knight")
	var frame := Rect2(Vector2.ZERO, p.size).grow(-4)
	var r := p.hero_rect()
	assert_true(r.size.x > 0.0 and frame.encloses(r), "hero %s inside frame %s" % [r, frame])
	p.free()
