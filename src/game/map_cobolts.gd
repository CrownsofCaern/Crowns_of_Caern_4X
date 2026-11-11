class_name MapCobolts
extends RefCounted
## Persistent neutral shops. Military state is private until combat starts.

const ROSTER := ["cobolt_pack_runner", "cobolt_caravan_spear", "cobolt_bolt_broker", "cobolt_cinder_alchemist", "cobolt_vault_warden"]
const POSTS := ["cobolt_stall", "cobolt_yard", "cobolt_exchange"]


static func is_post(obj: Dictionary, data: GameData) -> bool:
	return obj.get("type", "") == "site" and data.sites.get(obj.get("site", ""), {}).get("kind", "") == "cobolt"


static func config(obj: Dictionary, data: GameData) -> Dictionary:
	return data.sites.get(obj.get("site", ""), {}).get("cobolt", {})


static func normalize(obj: Dictionary, data: GameData) -> void:
	var cfg := config(obj, data)
	obj["sprite"] = obj.get("sprite", data.sites[obj["site"]]["sprite"])
	obj["visitors"] = obj.get("visitors", [])
	var rng := GameRng.new(MapGenerator._stable_hash(String(obj["id"]) + ":" + String(obj["site"])))
	if not bool(obj.get("cobolt_initialized", false)):
		var tiers: Array = cfg["tiers"]
		var cid: String = ROSTER[rng.next_int(int(tiers[0]) - 1, int(tiers[1]) - 1)]
		var ids := data.artifacts.keys()
		ids.sort()
		var pool: Array = ids.filter(func(id): return cfg["artifact_rarities"].has(data.artifacts[id]["rarity"]))
		var aid := String(pool[rng.next_int(0, pool.size() - 1)])
		var resources: Array = data.resource_order.filter(func(id): return id != "gold")
		var sell := String(resources[rng.next_int(0, resources.size() - 1)])
		resources.erase(sell)
		var buy := String(resources[rng.next_int(0, resources.size() - 1)])
		var output := 8
		var baseline := Economy.trade_price(sell, buy, output, 1, data)
		var price := maxi(1, int(ceil(baseline * (1.0 - float(cfg["discount"])))))
		var cap := int(data.creature(cid)["growth"])
		var stock := [
			{"kind": "recruit", "creature": cid, "remaining": cap, "cap": cap},
			{"kind": "artifact", "artifact": aid, "price": int(data.artifacts[aid]["value"]), "remaining": 1},
			{"kind": "exchange", "sell": sell, "buy": buy, "input": price, "output": output,
				"baseline": baseline, "remaining": int(cfg["exchange_uses"]), "cap": int(cfg["exchange_uses"])}]
		if not obj.has("stock"):
			obj["stock"] = stock
		# All levels share the full guard range. Wealth cannot identify escorts.
		if not obj.has("guard"):
			var guards := []
			var budget := rng.next_int(1200, 12000)
			for i in rng.next_int(2, 4):
				var guard: String = ROSTER[rng.next_int(0, 4)]
				var count := maxi(1, budget / (4 * int(data.creature(guard)["cost"]["gold"])))
				guards.append([guard, count])
			obj["guard"] = guards
		if not obj.has("loot_gold"):
			obj["loot_gold"] = rng.next_int(int(cfg["loot_gold"][0]), int(cfg["loot_gold"][1]))
		obj["cobolt_initialized"] = true
	if obj.has("pos"):
		obj["pos"] = [int(obj["pos"][0]), int(obj["pos"][1])]
	obj["plundered"] = bool(obj.get("plundered", false))
	var hostile: Array = []
	for player in obj.get("hostile_players", []):
		hostile.append(int(player))
	obj["hostile_players"] = hostile
	for key in ["loot_gold"]:
		obj[key] = int(obj.get(key, 0))
	for offer in obj.get("stock", []):
		for key in ["remaining", "cap", "price", "input", "output", "baseline"]:
			if offer.has(key):
				offer[key] = int(offer[key])


static func access_error(obj: Dictionary, player: int) -> String:
	if obj.get("plundered", false):
		return "This post was plundered. Trade has ended for everyone."
	if (obj.get("hostile_players", []) as Array).has(player):
		return "This trading house refuses you after your robbery."
	return ""


static func restock(obj: Dictionary) -> void:
	if obj.get("plundered", false):
		return
	for offer in obj.get("stock", []):
		if offer.get("kind", "") in ["recruit", "exchange"]:
			offer["remaining"] = int(offer["cap"])


## Stable, coarse observations. No true counts, full roster or predictions leave here.
## The visible patrol estimate uses a bucket, and never fresh independent noise.
static func report(obj: Dictionary, data: GameData, scouted: bool, expertise: int = 0) -> Array:
	if not scouted:
		return ["Guards concealed"]
	var guards: Array = obj.get("guard", [])
	if guards.is_empty():
		return ["No patrol observed. Reserves unknown."]
	var first: Array = guards[0]
	var visible := maxi(1, int(first[1]) / 2)
	var bucket := 5 if visible < 10 else (20 if visible < 40 else 50)
	var low := (visible / bucket) * bucket
	var roles := [String(data.creature(first[0])["role"])]
	if expertise >= 2 and guards.size() > 1:
		var role := String(data.creature(guards[1][0])["role"])
		if not roles.has(role):
			roles.append(role)
	return ["Observed patrol roles: %s." % ", ".join(roles),
		"Roughly %d–%d visible guards; reserves unknown." % [maxi(1, low), low + bucket * 2],
		"Observation only — not a bound on total defenders. Exact counts and odds remain unknown."]


## Authored maps receive one independently seeded post at new game only.
static func populate_authored(state: GameState, data: GameData) -> void:
	if MapGenerator.is_generated_id(state.map.map_id):
		return
	if state.map.objects.values().any(func(o): return is_post(o, data)):
		return
	var rng := GameRng.new(GameRng.mix(state.game_seed, MapGenerator._stable_hash(state.map.map_id + ":cobolts")))
	var map := state.map
	var passable := PackedByteArray()
	passable.resize(map.width * map.height)
	for i in passable.size():
		passable[i] = 1 if map.is_passable(Vector2i(i % map.width, i / map.width)) else 0
	var starts := PackedInt32Array()
	for h in state.heroes.values():
		starts.append(map.index(h.pos))
	var reached := GridSearch.flood(map.width, map.height, passable, starts)
	var occupied := {}
	for o in map.objects.values():
		occupied[AdventureMap.object_pos(o)] = true
	var hero_pos: Array[Vector2i] = []
	for h in state.heroes.values():
		hero_pos.append(h.pos)
	var candidates: Array[int] = []
	for i in reached.size():
		if reached[i] == 0:
			continue
		var p := Vector2i(i % map.width, i / map.width)
		if not occupied.has(p) and not hero_pos.any(func(q): return q.distance_squared_to(p) < 36):
			candidates.append(i)
	if candidates.is_empty():
		return
	var at := candidates[rng.next_int(0, candidates.size() - 1)]
	var obj := {"id": "cobolt_%d" % rng.next_u32(), "type": "site", "site": POSTS[rng.next_int(0, 2)], "pos": [at % map.width, at / map.width]}
	normalize(obj, data)
	map.add_object(obj)


static func validate(data: GameData) -> Array[String]:
	var errors: Array[String] = []
	for i in ROSTER.size():
		var c := data.creature(ROSTER[i])
		if c.get("faction", "") != "cobolts" or int(c.get("tier", 0)) != i + 1 or c.has("upgrade"):
			errors.append("Cobolts need five neutral tiers without upgrades")
	if not bool(data.factions.get("cobolts", {}).get("neutral", false)) or data.town_types.has("cobolts"):
		errors.append("Cobolts must remain non-playable")
	for sid in POSTS:
		var cfg: Dictionary = data.sites.get(sid, {}).get("cobolt", {})
		var tiers: Array = cfg.get("tiers", [])
		if tiers.size() != 2 or int(tiers[0]) < 1 or int(tiers[1]) > 5 or int(tiers[0]) > int(tiers[1]):
			errors.append("%s needs recruit tiers within 1–5" % sid)
		if float(cfg.get("discount", -1)) != 0.4:
			errors.append("%s resource trade discount must be 40%%" % sid)
		if int(cfg.get("level", 0)) < 1 or int(cfg.get("level", 0)) > 3:
			errors.append("%s needs a commercial level within 1–3" % sid)
		for key in ["level", "exchange_uses"]:
			var v := float(cfg.get(key, 0))
			if v <= 0 or v != floor(v):
				errors.append("%s needs a positive integer %s" % [sid, key])
		var loot: Array = cfg.get("loot_gold", [])
		if loot.size() != 2 or float(loot[0]) <= 0 or float(loot[1]) < float(loot[0]):
			errors.append("%s needs a positive loot range" % sid)
		var rarities: Array = cfg.get("artifact_rarities", [])
		if rarities.is_empty():
			errors.append("%s needs artifact rarities" % sid)
		for rarity in rarities:
			if not data.artifacts.values().any(func(a): return a["rarity"] == rarity):
				errors.append("%s has an unknown artifact rarity" % sid)
	return errors


## Authoring checks run before normalization reads optional persistent fields.
static func object_errors(obj: Dictionary, data: GameData) -> Array[String]:
	var errors: Array[String] = []
	if obj.has("unclaimed_artifact") and not data.artifacts.has(obj["unclaimed_artifact"]):
		errors.append("unknown unclaimed artefact")
	if obj.has("loot_owner") and (not _whole(obj["loot_owner"]) or float(obj["loot_owner"]) < 0):
		errors.append("invalid loot owner")
	for key in ["cobolt_initialized", "plundered"]:
		if obj.has(key) and typeof(obj[key]) != TYPE_BOOL:
			errors.append("%s must be boolean" % key)
	if obj.has("hostile_players"):
		if not obj["hostile_players"] is Array:
			errors.append("hostile_players must be a list")
		else:
			for player in obj["hostile_players"]:
				if not _whole(player) or float(player) < 0:
					errors.append("hostile player must be a nonnegative player index")
	if obj.has("loot_gold") and (not _whole(obj["loot_gold"]) or float(obj["loot_gold"]) < 0):
		errors.append("loot_gold must be a nonnegative integer")
	if not obj.has("stock"):
		if obj.get("cobolt_initialized", false):
			errors.append("initialized cobolt post needs its saved stock")
		return errors
	if not obj["stock"] is Array or obj["stock"].size() != 3:
		errors.append("cobolt stock must contain recruit, artifact and exchange offers")
		return errors
	for i in 3:
		var offer: Variant = obj["stock"][i]
		if not offer is Dictionary or offer.get("kind", "") != ["recruit", "artifact", "exchange"][i]:
			errors.append("cobolt offer %d has the wrong kind" % i)
			continue
		var fields: Array = ["remaining"]
		if i == 0:
			fields.append("cap")
			if not ROSTER.has(offer.get("creature", "")):
				errors.append("unknown cobolt recruit")
		elif i == 1:
			fields.append("price")
			if not data.artifacts.has(offer.get("artifact", "")):
				errors.append("unknown cobolt artifact")
		else:
			fields.append_array(["cap", "input", "output", "baseline"])
			if not data.resources.has(offer.get("sell", "")) or not data.resources.has(offer.get("buy", "")) or offer.get("sell") == offer.get("buy"):
				errors.append("cobolt exchange needs two different resources")
		for key in fields:
			var v: Variant = offer.get(key, -1)
			if not _whole(v) or float(v) < (0 if key == "remaining" else 1):
				errors.append("cobolt offer has invalid %s" % key)
	return errors


static func _whole(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value))
