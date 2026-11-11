class_name MapTraders
extends RefCounted
## Traders use ordinary persistent site objects. Stock is rolled only once;
## purchases, including the remaining maps, travel with the saved object.

const SITE_ID := "road_trader"


static func settings(data: GameData) -> Dictionary:
	return data.sites.get(SITE_ID, {}).get("trade", {})


## A small map has a 50% chance; each additional small-map area is another
## independent opportunity to encounter the same travelling shop.
static func spawn_chance(width: int, height: int, data: GameData) -> float:
	var cfg := settings(data)
	return 1.0 - pow(1.0 - float(cfg.get("small_map_chance", 0.5)),
		float(width * height) / maxf(1.0, float(cfg.get("small_map_tiles", 4900))))


static func make_stock(data: GameData, rng: GameRng) -> Array:
	var stock: Array = []
	var ids := data.artifacts.keys()
	ids.sort()
	for rarity in settings(data).get("artifact_rarities", ["minor", "major", "relic"]):
		var pool := ids.filter(func(id): return data.artifacts[id]["rarity"] == rarity)
		if pool.is_empty():
			continue
		var aid := String(pool[rng.next_int(0, pool.size() - 1)])
		stock.append({"kind": "artifact", "artifact": aid,
			"price": int(data.artifacts[aid]["value"]), "remaining": 1})
	var cfg := settings(data)
	stock.append({"kind": "map", "price": int(cfg.get("map_price", 750)),
		"tiles": int(cfg.get("map_tiles", 40)), "remaining": int(cfg.get("map_stock", 3))})
	return stock


## Authored maps get the same encounter roll at new-game time. Generated maps
## already contain their trader roll; loading a save never invokes this.
static func populate_authored(state: GameState, data: GameData) -> void:
	if MapGenerator.is_generated_id(state.map.map_id):
		return
	for obj in state.map.objects.values():
		if obj.get("site", "") == SITE_ID:
			return
	var rng := GameRng.new(GameRng.mix(state.game_seed, MapGenerator._stable_hash(state.map.map_id + ":traders")))
	var map := state.map
	if not rng.chance(spawn_chance(map.width, map.height, data)):
		return
	var passable := PackedByteArray()
	passable.resize(map.width * map.height)
	for i in passable.size():
		passable[i] = 1 if map.is_passable(Vector2i(i % map.width, i / map.width)) else 0
	var starts := PackedInt32Array()
	for h in state.heroes.values():
		starts.append(map.index(h.pos))
	var reached := GridSearch.flood(map.width, map.height, passable, starts)
	var candidates: Array[int] = []
	for i in reached.size():
		var p := Vector2i(i % map.width, i / map.width)
		if reached[i] != 0 and map.object_at(p).is_empty() and not state.heroes.values().any(func(h): return h.pos.distance_squared_to(p) < 36):
			candidates.append(i)
	if candidates.is_empty():
		return
	var at := candidates[rng.next_int(0, candidates.size() - 1)]
	var id := "road_trader"
	while map.objects.has(id):
		id += "_1"
	map.add_object({"id": id, "type": "site", "site": SITE_ID,
		"pos": [at % map.width, at / map.width], "stock": make_stock(data, rng)})
	MapSites.normalize(map.objects[id], data)


static func normalize(obj: Dictionary, data: GameData) -> void:
	# Hand-authored traders without stock get a stable inventory; an empty or
	# sold-out inventory is deliberately preserved on load.
	if not obj.has("stock"):
		obj["stock"] = make_stock(data, GameRng.new(MapGenerator._stable_hash(String(obj["id"]))))
	for offer in obj["stock"]:
		for key in ["price", "remaining", "tiles"]:
			if offer.has(key):
				offer[key] = int(offer[key])


static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = []
	var cfg := settings(data)
	for key in ["small_map_tiles", "map_price", "map_tiles", "map_stock"]:
		var value: Variant = cfg.get(key, 0)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or float(value) <= 0 or float(value) != floor(float(value)):
			errors.append("road_trader.trade.%s must be a positive integer" % key)
	var chance: Variant = cfg.get("small_map_chance", -1)
	if typeof(chance) not in [TYPE_INT, TYPE_FLOAT] or float(chance) < 0 or float(chance) > 1:
		errors.append("road_trader.trade.small_map_chance must be between 0 and 1")
	var rarities: Variant = cfg.get("artifact_rarities", [])
	if not rarities is Array or rarities.is_empty():
		errors.append("road_trader.trade.artifact_rarities needs at least one rarity")
	else:
		for rarity in rarities:
			if not data.artifacts.values().any(func(a): return a["rarity"] == rarity):
				errors.append("road_trader.trade unknown rarity %s" % rarity)
	return errors
