class_name UltimateCreatureArt
extends RefCounted
## Visual treatment for faction-wide ultimate upgrades (a town's army_upgrade
## building, see ArmyUpgrade). Callers decide whether a stack is upgraded:
## battle figures use the battle result's "ultimate" field, army slots ask
## faction_if_upgraded(). Apply the material to the creature sprite only, never
## to its count badge or slot frame.

const SHADER := preload("res://assets/effects/ultimate_creature.gdshader")
const ACCENTS := {
	"concord": Color("f4ce7a"),
	"ashen": Color("ff7134"),
	"hollow": Color("a8df9b"),
	"thornwood": Color("a5cf70"),
	"forge": Color("e6b477"),
	"frostmarch": Color("b8e6f2"),
	"darkelf": Color("b48ce0"),
	"fishmen": Color("5cc9bd"),
}
## The animated accent each faction's shader draws (see ultimate_creature.gdshader).
const STYLES := {
	"concord": 0, "ashen": 1, "hollow": 2, "thornwood": 3, "forge": 4, "frostmarch": 5,
	"darkelf": 6, "fishmen": 7,
}

static var _cache := {}


static func material_for(faction: String) -> ShaderMaterial:
	if not ACCENTS.has(faction):
		return null
	if _cache.has(faction):
		return _cache[faction]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("accent", ACCENTS[faction])
	material.set_shader_parameter("style", int(STYLES[faction]))
	_cache[faction] = material
	return material


## The creature's faction if its owner has that faction's ultimate upgrade, else "".
static func faction_if_upgraded(session: GameSession, owner: int, creature_id: String) -> String:
	if session == null or creature_id == "" or owner < 0:
		return ""
	var faction := String(session.data.creature(creature_id).get("faction", ""))
	return faction if session.army_upgrades(owner).has(faction) else ""
