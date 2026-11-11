class_name Army
extends RefCounted
## Up to MAX_SLOTS creature stacks. Empty slots are empty dictionaries so slot
## indices stay stable (they matter for UI and for combat bookkeeping).

const MAX_SLOTS := 10
# Cumulative hero XP earned while this stack is present.
const VETERAN_THRESHOLDS := [0, 1500, 5000, 13000, 35000]

var slots: Array = []


func _init() -> void:
	slots.resize(MAX_SLOTS)
	for i in MAX_SLOTS:
		slots[i] = {}


static func from_pairs(pairs: Array) -> Army:
	var a := Army.new()
	for p in pairs:
		a.add(String(p[0]), int(p[1]))
	return a


## Adds creatures, merging into an existing stack of the same type.
## Returns false if there is no room.
func add(creature_id: String, count: int, veteran_xp: int = -1) -> bool:
	if count <= 0:
		return false
	if veteran_xp < 0:
		veteran_xp = VETERAN_THRESHOLDS[2] if GameData.get_default().creature(creature_id).has("upgrade_of") else 0
	for s in slots:
		if not s.is_empty() and s["creature"] == creature_id and veteran_level(s) == level_for_xp(veteran_xp):
			s["veteran_xp"] = int((int(s.get("veteran_xp", 0)) * int(s["count"]) + veteran_xp * count) / float(int(s["count"]) + count))
			s["count"] += count
			return true
	for i in MAX_SLOTS:
		if slots[i].is_empty():
			slots[i] = {"creature": creature_id, "count": count, "veteran_xp": veteran_xp}
			return true
	return false


static func level_for_xp(xp: int) -> int:
	var level := 1
	for i in range(1, VETERAN_THRESHOLDS.size()):
		if xp >= VETERAN_THRESHOLDS[i]:
			level = i + 1
	return level


static func veteran_level(stack: Dictionary) -> int:
	return level_for_xp(int(stack.get("veteran_xp", 0)))


static func veteran_description(stack: Dictionary) -> String:
	var level := veteran_level(stack)
	var xp := int(stack.get("veteran_xp", 0))
	if level >= 5:
		return "Veteran level 5 (maximum)"
	return "Veteran level %d — %d / %d XP to next level" % [level, xp - VETERAN_THRESHOLDS[level - 1], VETERAN_THRESHOLDS[level] - VETERAN_THRESHOLDS[level - 1]]


## Initialize legacy or starting upgraded creatures at level 3.
func initialize_veterans(data: GameData) -> void:
	for s in slots:
		if not s.is_empty() and not s.has("veteran_xp"):
			s["veteran_xp"] = VETERAN_THRESHOLDS[2] if data.creature(s["creature"]).has("upgrade_of") else 0


func gain_veteran_xp(amount: int, data: GameData) -> void:
	initialize_veterans(data)
	for s in slots:
		if s.is_empty():
			continue
		s["veteran_xp"] = mini(VETERAN_THRESHOLDS[4], int(s["veteran_xp"]) + maxi(0, amount))
		if veteran_level(s) >= 3:
			var upgrade := String(data.creature(s["creature"]).get("upgrade", ""))
			if upgrade != "":
				s["creature"] = upgrade


## Slots whose stacks are below the top veteran level (in slot order).
func ascendable_slots() -> Array[int]:
	var out: Array[int] = []
	for i in MAX_SLOTS:
		if not slots[i].is_empty() and veteran_level(slots[i]) < VETERAN_THRESHOLDS.size():
			out.append(i)
	return out


## Raises one stack straight to the top veteran level (the Ascendant form),
## promoting it to its improved creature on the way like gain_veteran_xp does.
static func ascend_stack(stack: Dictionary, data: GameData) -> void:
	stack["veteran_xp"] = VETERAN_THRESHOLDS[VETERAN_THRESHOLDS.size() - 1]
	var upgrade := String(data.creature(stack["creature"]).get("upgrade", ""))
	if upgrade != "":
		stack["creature"] = upgrade


## Picks one stack below the top level at random and ascends it. Returns the
## slot index, or -1 if every stack is already at the top level.
func ascend_random(rng: GameRng, data: GameData) -> int:
	initialize_veterans(data)
	var candidates := ascendable_slots()
	if candidates.is_empty():
		return -1
	var slot := candidates[rng.next_int(0, candidates.size() - 1)]
	ascend_stack(slots[slot], data)
	return slot


## Stat definitions remain immutable. Veteran ranks enhance the current form.
static func creature_stats(stack: Dictionary, data: GameData) -> Dictionary:
	var c := data.creature(stack["creature"]).duplicate(true)
	if c.is_empty():
		return c
	var level := veteran_level(stack)
	var bonus := (1 if level >= 2 else 0) + (1 if level >= 4 else 0)
	c["attack"] = int(c["attack"]) + bonus
	c["defense"] = int(c["defense"]) + bonus
	if level >= 5:
		c["name"] = "Ascendant " + String(c["name"])
		c["hp"] = int(ceil(int(c["hp"]) * 1.2))
		c["attack"] += 2
		c["defense"] += 2
		c["damage"] = [int(ceil(int(c["damage"][0]) * 1.2)), int(ceil(int(c["damage"][1]) * 1.2))]
	return c


func stack_count() -> int:
	var n := 0
	for s in slots:
		if not s.is_empty():
			n += 1
	return n


func is_empty() -> bool:
	return stack_count() == 0


func total_creatures() -> int:
	var n := 0
	for s in slots:
		if not s.is_empty():
			n += int(s["count"])
	return n


## Sets the surviving count of each slot (index -> count). Zero clears the slot.
func set_survivors(survivors: Dictionary) -> void:
	for i in survivors:
		var idx := int(i)
		if slots[idx].is_empty():
			continue
		var c := int(survivors[i])
		if c <= 0:
			slots[idx] = {}
		else:
			slots[idx]["count"] = c


## Combat input: [{slot, creature, count}, ...]
func to_combat_stacks() -> Array:
	var out := []
	for i in MAX_SLOTS:
		if not slots[i].is_empty():
			out.append({"slot": i, "creature": slots[i]["creature"], "count": slots[i]["count"], "veteran_xp": slots[i].get("veteran_xp", 0)})
	return out


func to_dict() -> Array:
	return slots.duplicate(true)


static func from_dict(arr: Array) -> Army:
	var a := Army.new()
	for i in mini(arr.size(), MAX_SLOTS):
		var s: Dictionary = arr[i]
		if not s.is_empty():
			a.slots[i] = s.duplicate(true)
			a.slots[i]["count"] = int(s["count"])
			if s.has("veteran_xp"):
				a.slots[i]["veteran_xp"] = int(s["veteran_xp"])
	return a
