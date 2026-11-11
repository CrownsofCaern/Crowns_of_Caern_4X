class_name ResourceBank
extends RefCounted
## A player's stockpile of the seven resources. Amounts never go negative.

var amounts: Dictionary = {}


func _init(initial: Dictionary = {}) -> void:
	for k in initial:
		amounts[k] = int(initial[k])


func get_amount(res: String) -> int:
	return int(amounts.get(res, 0))


func add(res: String, amount: int) -> void:
	assert(amount >= 0, "use spend() to remove resources")
	amounts[res] = get_amount(res) + amount


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if get_amount(k) < int(cost[k]):
			return false
	return true


## Spends the whole cost or nothing. Returns true on success.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		amounts[k] = get_amount(k) - int(cost[k])
	return true


func to_dict() -> Dictionary:
	return amounts.duplicate()


static func from_dict(d: Dictionary) -> ResourceBank:
	return ResourceBank.new(d)
