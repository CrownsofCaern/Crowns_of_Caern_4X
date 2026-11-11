class_name CombatUnit
extends RefCounted
## Runtime state of one creature stack during a simulated battle.
## Built fresh from a BattleSetup for every simulation run.

var side: int = 0            # 0 = attacker, 1 = defender
var slot: int = 0
var creature_id: String = ""
var veteran_level := 1
var name: String = ""
var role: String = ""
var formation: String = ""   # front | flank | back | support
var start_count: int = 0
var count: int = 0
var hp_per: int = 1
var top_hp: int = 1
var attack: int = 0
var defense: int = 0
var dmg_min: int = 1
var dmg_max: int = 1
var speed: int = 0
var initiative: int = 0
var morale: int = 0
var abilities: Dictionary = {}   # ability id -> params dictionary
var fx: Dictionary = {}          # per-battle ability state (see AbilityEffects)
# Hero-driven multipliers (HeroBattleEffects.setup_unit)
var shot_mult: float = 1.0
var melee_mult: float = 1.0
var shot_taken_mult: float = 1.0
## Name of the faction ultimate upgrade this stack fights with ("" = none; ArmyUpgrade).
var ultimate: String = ""

# Per-battle flags
var has_charged: bool = false
## Held reserve (BattleOrders formation "reserve"): out of reach and idle until
## this round (0 = not a reserve), unless it is the last stack standing.
var reserve_round: int = 0
var reserve_in: bool = false    # the reserve has entered the battle
var first_blow_done: bool = false  # has struck its first melee blow (charge_pct)
var airborne: bool = false     # a flyer in the air: only flyers, reach units and shots can hit it
var kills: int = 0
var damage_dealt: int = 0
# Per-round flags (reset each round)
var retaliations_left: int = 1
var retaliation_pool: int = 0     # creatures that may still strike back this round
var acted: bool = false
var curse_mult: float = 1.0


static func formation_for_role(r: String) -> String:
	match r:
		"infantry", "heavy": return "front"
		"cavalry", "flyer": return "flank"
		"ranged": return "back"
		"support": return "support"
	return "front"


func has(ability: String) -> bool:
	return abilities.has(ability)


func param(ability: String, key: String, default_value: Variant) -> Variant:
	return abilities.get(ability, {}).get(key, default_value)


func is_alive() -> bool:
	return count > 0


func total_hp() -> int:
	if count <= 0:
		return 0
	return (count - 1) * hp_per + top_hp


func max_total_hp() -> int:
	return start_count * hp_per


func avg_damage() -> float:
	return (dmg_min + dmg_max) * 0.5


## Rough per-round damage potential, used for target prioritisation.
func threat() -> float:
	return count * avg_damage() * (1.0 + 0.05 * attack)


## Applies damage and returns the number of creatures killed.
func take_damage(amount: int) -> int:
	if amount <= 0 or count <= 0:
		return 0
	var before := count
	var remaining := total_hp() - amount
	if remaining <= 0:
		count = 0
		top_hp = 0
	else:
		count = int(ceil(float(remaining) / hp_per))
		top_hp = remaining - (count - 1) * hp_per
	return before - count


## Restores hit points, reviving fallen creatures up to the starting count.
## Returns the hit points actually restored.
func heal(amount: int) -> int:
	if count <= 0 or amount <= 0:
		return 0
	var missing := max_total_hp() - total_hp()
	var restored := mini(missing, amount)
	var new_total := total_hp() + restored
	count = int(ceil(float(new_total) / hp_per))
	top_hp = new_total - (count - 1) * hp_per
	return restored
