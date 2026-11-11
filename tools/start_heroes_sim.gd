extends SceneTree
## Starting-hero balance sim: computer-versus-computer standard games on a
## generated map, one faction against every other, with and without that
## faction's extra starting hero (both slots played by each side in turn):
##   godot --headless --path . --script res://tools/start_heroes_sim.gd -- [faction] [seeds] [days] [template]
## Prints, per opponent, the faction's score share (towns, mines and army value
## at the last day, or 1/0 for a decided game) with the trait and without it.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var faction: String = args[0] if args.size() > 0 else "frostmarch"
	var seeds := int(args[1]) if args.size() > 1 else 6
	var days := int(args[2]) if args.size() > 2 else 35
	var template: String = args[3] if args.size() > 3 else "twin_marches"
	var data := GameData.get_default()
	var trait_heroes := data.starting_heroes(faction)
	var entry := GameSetup.map_entry(data, MapGenerator.make_id(template, 1))
	print("%s (trait: %d starting heroes) on %s, %d seeds x 2 sides, %d days" % [faction, trait_heroes, template, seeds, days])
	var total := {"trait": 0.0, "plain": 0.0}
	var count := 0
	for other in GameSetup.playable_factions(data):
		if other == faction:
			continue
		var row := {}
		for mode in ["trait", "plain"]:
			data.factions[faction]["starting_heroes"] = trait_heroes if mode == "trait" else 1
			var share := 0.0
			for sd in seeds:
				for side in 2:
					share += _play(data, entry, faction, other, side, 100 + sd, days)
			row[mode] = share / (seeds * 2)
			total[mode] += row[mode]
		count += 1
		print("  vs %-11s with trait %.2f   without %.2f" % [other, row["trait"], row["plain"]])
	data.factions[faction]["starting_heroes"] = trait_heroes
	print("average: with trait %.2f, without %.2f" % [total["trait"] / count, total["plain"] / count])
	quit(0)


## The faction's share (0..1) of the two players' score at the end.
func _play(data: GameData, entry: Dictionary, faction: String, other: String, side: int, seed_value: int, days: int) -> float:
	var setup := GameSetup.default_setup(entry)
	setup["standard_start"] = true
	for i in 2:
		setup["players"][i]["type"] = "computer"
		setup["players"][i]["faction"] = faction if i == side else other
	var s := GameSession.new_game(data, GameSetup.map_id_for(entry, seed_value), seed_value, setup)
	while s.state.day <= days and not s.state.game_over:
		StrategicAI.new(s, s.state.current_player).play_turn()
		s.end_turn()
	var me := side
	var them := 1 - side
	if s.state.player(them)["defeated"] and not s.state.player(me)["defeated"]:
		return 1.0
	if s.state.player(me)["defeated"]:
		return 0.0
	var a := _score(s, me)
	var b := _score(s, them)
	return a / maxf(1.0, a + b)


func _score(s: GameSession, idx: int) -> float:
	var ai := StrategicAI.new(s, idx)
	var v := 4000.0 * s.towns_of(idx).size() + 1000.0 * s.mines_of(idx).size()
	for h in s.state.heroes_of(idx):
		v += ai.army_value(h.army)
	for t in s.towns_of(idx):
		v += ai.army_value(Town.garrison(t))
	return v
