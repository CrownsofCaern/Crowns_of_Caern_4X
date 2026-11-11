class_name CombatPredictor
extends RefCounted
## Monte Carlo battle forecast. Runs N headless simulations with seeds that are
## independent of the real battle's seed, so the forecast describes the
## distribution without leaking the actual outcome.

const PREDICTION_SALT := 0x5EED

const LABELS := [
	[0.95, "Overwhelming advantage"],
	[0.80, "Strong advantage"],
	[0.60, "Favorable"],
	[0.40, "Even"],
	[0.15, "Unfavorable"],
	[0.0, "Severe disadvantage"],
]

var data: GameData


func _init(game_data: GameData) -> void:
	data = game_data


static func label_for(win_prob: float) -> String:
	for pair in LABELS:
		if win_prob >= pair[0]:
			return pair[1]
	return LABELS[-1][1]


func predict(setup: Dictionary, simulations: int = -1) -> Dictionary:
	if simulations <= 0:
		simulations = int(data.combat["prediction_simulations"])
	var sim := CombatSimulator.new(data)
	var wins := 0
	var stacks: Array = setup["sides"][0]["stacks"]
	var loss_samples := []   # per run: total attacker hp lost fraction
	var slot_losses := {}    # slot -> [losses per run]
	for st in stacks:
		slot_losses[int(st["slot"])] = []
	var base_seed := GameRng.mix(PREDICTION_SALT, int(setup.get("prediction_key", 0)))
	for i in simulations:
		var s := setup.duplicate()
		s["seed"] = GameRng.mix(base_seed, i)
		var r := sim.simulate(s, false)
		if r["winner"] == 0:
			wins += 1
		var side0: Dictionary = r["sides"][0]
		loss_samples.append(1.0 - float(side0["hp_end"]) / maxf(1.0, float(side0["hp_start"])))
		for st in side0["stacks"]:
			slot_losses[int(st["slot"])].append(int(st["lost"]))
	loss_samples.sort()
	var per_stack := []
	for st in stacks:
		var arr: Array = slot_losses[int(st["slot"])]
		arr.sort()
		var total := 0
		for v in arr:
			total += v
		per_stack.append({
			"slot": int(st["slot"]), "creature": st["creature"],
			"name": data.creature(st["creature"])["name"], "count": int(st["count"]),
			"expected_lost": float(total) / arr.size(),
			"low": arr[int(arr.size() * 0.1)], "high": arr[mini(arr.size() - 1, int(arr.size() * 0.9))],
		})
	var win_prob := float(wins) / simulations
	return {
		"simulations": simulations,
		"win_probability": win_prob,
		"label": label_for(win_prob),
		"expected_loss_fraction": _mean(loss_samples),
		"loss_fraction_low": loss_samples[int(loss_samples.size() * 0.1)],
		"loss_fraction_high": loss_samples[mini(loss_samples.size() - 1, int(loss_samples.size() * 0.9))],
		"stacks": per_stack,
	}


static func _mean(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var t := 0.0
	for v in arr:
		t += v
	return t / arr.size()
