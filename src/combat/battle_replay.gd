class_name BattleReplay
extends RefCounted
## Turns a recorded battle result (CombatSimulator.simulate with a log) into
## a list of simple, ordered steps a viewer can play back: who walks to whom,
## who shoots, what number pops up and how many creatures each stack has left.
## Pure data; the outcome is never recomputed, only retold.

## Step kinds a viewer has to draw.
const MELEE := "melee"       # walk to the target, strike, stay until the exchange ends
const ANSWER := "answer"     # strike back where the unit stands (retaliation)
const SHOT := "shot"         # strike in place and loose a projectile
const EFFECT := "effect"     # a number on the target (heals, poison, hero arts, ...)
const NOTICE := "notice"     # a word over a stack (falters, holds, evades, ...)
const ROUND := "round"       # a new round begins

const MELEE_TYPES := ["melee", "charge", "overflow"]
const SHOT_TYPES := ["shot", "volley", "stand_and_shoot"]
const GAIN_TYPES := ["heal", "regenerate", "drain", "art_mend"]
const NOTICE_WORDS := {
	"falter": "Falters", "surge": "Surge!", "hold": "Holds", "bypass": "Slips past",
	"evade": "Evades", "stunned": "Stunned", "art_rally": "Rally", "art_hex": "Hexed", "art_ward": "Ward",
	"out_of_reach": "Out of reach", "reserve": "The reserve!",
}

## [side] -> [{key, slot, creature, name, start, end, formation, ultimate}], in result order
## (ultimate: name of the faction ultimate upgrade the stack fought with, or "").
var stacks: Array = [[], []]
## [{kind, round, actor, target, actor_count, target_count, text, gain, type}];
## actor/target are stack keys ("<side>:<slot>") or "" (a hero, or nobody).
var steps: Array = []


static func key(side: int, slot: int) -> String:
	return "%d:%d" % [side, slot]


static func from_result(result: Dictionary) -> BattleReplay:
	var r := BattleReplay.new()
	for s in 2:
		for st in result["sides"][s]["stacks"]:
			r.stacks[s].append({"key": key(s, int(st["slot"])), "slot": int(st["slot"]),
				"creature": st["creature"], "name": st["name"], "start": int(st["start"]),
				"end": int(st["end"]), "formation": st.get("formation", "front"),
				"veteran_level": int(st.get("veteran_level", 1)), "ultimate": String(st.get("ultimate", ""))})
	var round_now := -1
	for e in result.get("log", []):
		var rd := int(e.get("round", 0))
		if rd != round_now:
			round_now = rd
			r.steps.append({"kind": ROUND, "round": rd, "actor": "", "target": "", "text": "Opening volley" if rd == 0 else "Round %d" % rd})
		r.steps.append(_step(e))
	return r


static func _step(e: Dictionary) -> Dictionary:
	var t := String(e["type"])
	var actor := ""
	if int(e.get("actor_slot", -1)) >= 0:
		actor = key(int(e["actor_side"]), int(e["actor_slot"]))
	var target := ""
	if int(e.get("target_slot", -1)) >= 0:
		target = key(int(e["target_side"]), int(e["target_slot"]))
	var amount := int(e.get("amount", 0))
	var kind := EFFECT
	var text := "-%d" % amount
	var gain := false
	if t in MELEE_TYPES:
		kind = MELEE
	elif t == "retaliation":
		kind = ANSWER
	elif t in SHOT_TYPES:
		kind = SHOT
	elif NOTICE_WORDS.has(t):
		kind = NOTICE
		text = NOTICE_WORDS[t]
		# An evasion and a hero's hex show over the stack that was aimed at.
		if t == "evade" or t == "art_hex":
			actor = target
	elif t in GAIN_TYPES:
		text = "+%d" % amount
		gain = true
	elif t == "rebirth":
		text = "+%d risen" % int(e.get("kills", 0))
		gain = true
	if t == "charge":
		text = "Charge! -%d" % amount
	elif t == "withdraw":
		# Standing retreat order: the stack falls back; kills = rear guard lost.
		text = "Rear guard -%d" % int(e.get("kills", 0)) if int(e.get("kills", 0)) > 0 else "Falls back"
	var step := {"kind": kind, "type": t, "round": int(e.get("round", 0)), "actor": actor, "target": target,
		"actor_count": int(e.get("actor_count", 0)), "target_count": int(e.get("target_count", 0)),
		"text": text, "gain": gain}
	if t.begins_with("art_"):
		step["hero_side"] = int(e.get("actor_side", 0))
	return step


## Every stack key, both sides.
func all_keys() -> Array:
	var out := []
	for s in 2:
		for st in stacks[s]:
			out.append(st["key"])
	return out


## Creature counts after playing every step (equal to the result's survivors).
func final_counts() -> Dictionary:
	var counts := {}
	for s in 2:
		for st in stacks[s]:
			counts[st["key"]] = st["start"]
	for st in steps:
		if String(st["actor"]) != "" and st["kind"] != NOTICE and st["kind"] != ROUND and counts.has(st["actor"]) and st["type"] != "art_hex":
			counts[st["actor"]] = int(st["actor_count"])
		if String(st["target"]) != "" and counts.has(st["target"]):
			counts[st["target"]] = int(st["target_count"])
	return counts
