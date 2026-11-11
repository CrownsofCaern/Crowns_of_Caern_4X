extends SceneTree
## Balance probe for Karzhaloth, the ancient dragon of The Six Eyes' finale.
## Design rule (Nov 9 2026): the fight is won by a hero who had a whole campaign
## to level up and collect strong items; without them it is lost. The probe runs
## the_nightgate's starting veteran armies against the dragon three ways:
## no hero, a fresh hero, and a level-12 Dreadmarshal in relics with war skills.
## Tuned Nov 9 2026 (hp 4400, att 42, def 36, dmg 170-260, regen 220): no hero or
## a fresh hero always loses, level 12 without items wins a third, level 12 in
## relics with both armies merged wins nearly always and loses half the army.
##   godot --headless --path . --script res://tools/story/dragon_probe.gd

const RUNS := 60
const RELICS := ["headsmans_maul", "emberforged_cuirass", "greathelm_of_dread", "aegis_of_cinders", "sabatons_of_the_long_road", "crown_of_thorns", "warhost_oriflamme"]
const SKILLS := ["leadership", "leadership", "leadership", "onslaught", "onslaught", "onslaught", "tactics", "tactics", "tactics", "shieldcraft", "shieldcraft"]


func _side(pairs: Array, name: String, hero: Variant) -> Dictionary:
	var stacks := []
	for i in pairs.size():
		stacks.append({"slot": i, "creature": pairs[i][0], "count": pairs[i][1]})
	return {"name": name, "hero": hero, "stacks": stacks}


func _hero(data: GameData, level: int, relics: Array) -> Dictionary:
	var h := Hero.create({"id": "probe", "name": "Serane", "class": "de_dreadmarshal", "pos": [0, 0], "army": [["de_gloam_spear", 1]]}, data)
	var thresholds: Array = data.progression["xp_thresholds"]
	if level > 1:
		h.add_xp(int(thresholds[level - 1]), data)
	for s in SKILLS:
		if h.skill_points <= 0:
			break
		h.learn_skill(s, data)
	for a in relics:
		h.give_artifact(a, data)
	return h.combat_profile(data)


func _rate(data: GameData, left: Array, right: Array, hero: Variant) -> String:
	var wins := 0
	var left_left := 0.0
	for s in RUNS:
		var r := CombatSimulator.new(data).simulate(CombatSimulator.make_setup(_side(left, "Wardens", hero), _side(right, "Karzhaloth", null), "rough", 500 + s), false)
		var ls := 0
		for st in r["sides"][0]["stacks"]:
			ls += int(st["end"])
		if int(r["winner"]) == 0:
			wins += 1
			left_left += ls
	return "wins %d/%d, avg survivors when winning %.0f" % [wins, RUNS, left_left / max(1, wins)]


func _init() -> void:
	var data := GameData.get_default()
	var m: Dictionary = data.load_map("the_nightgate")
	var serane: Array = []
	var rhuvel: Array = []
	var dragon: Array = []
	for h in m["heroes"]:
		if h["id"] == "hero_serane": serane = h["army"]
		if h["id"] == "hero_rhuvel": rhuvel = h["army"]
	for o in m["objects"]:
		if o["id"] == "neutral_dragon": dragon = o["stacks"]
	var both := serane.duplicate(true)
	both.append_array(rhuvel)
	var n := 0
	for st in both:
		n += int(st[1])
	print("Dragon ", dragon, "; merged veteran armies: %d creatures in %d stacks" % [n, both.size()])
	print("No hero, Serane alone:          ", _rate(data, serane, dragon, null))
	print("No hero, merged armies:         ", _rate(data, both, dragon, null))
	print("Fresh level-1 hero, merged:     ", _rate(data, both, dragon, _hero(data, 1, [])))
	print("Level 12, no items, merged:     ", _rate(data, both, dragon, _hero(data, 12, [])))
	print("Level 12 in relics, Serane only:", _rate(data, serane, dragon, _hero(data, 12, RELICS)))
	print("Level 12 in relics, merged:     ", _rate(data, both, dragon, _hero(data, 12, RELICS)))
	quit()
