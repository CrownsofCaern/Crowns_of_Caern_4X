class_name OnlineView
extends GameSession
## A look-only copy of an online game for a player waiting for their turn:
## their own side (fog, towns, heroes, armies, resources) as if they were to
## move, while every order is refused. The copy is never sent or saved; the
## next game from the host replaces it.

const WAIT := "Wait for your turn to give orders"

## The player shown to this person, or -1 when they hold no seat in the game.
var viewer := -1


## A copy of game's state seen by person's first undefeated seat, or null.
static func of(game: GameSession, person: String) -> OnlineView:
	var seat := -1
	for i in OnlineMatch.seats_held(game.state, person):
		if not game.state.player(i)["defeated"]:
			seat = i
			break
	if seat < 0:
		return null
	var v := OnlineView.new()
	v.data = game.data
	v._attach(GameState.from_dict(game.state.to_dict(), game.data))
	v.state.current_player = seat
	v.viewer = seat
	return v


func end_turn() -> void:
	pass


func save_to_file(_path: String) -> Error:
	return ERR_UNAVAILABLE


func move_hero(_hero_id: String, _target: Vector2i) -> Dictionary:
	return {"ok": false, "reason": WAIT, "steps": [], "battle": "", "encounter": "", "town": "", "site": ""}


# Checks the screens use to grey out their buttons.
func can_build(_t: String, _b: String) -> String: return WAIT
func can_hire_hero(_t: String) -> String: return WAIT
func can_upgrade_stack(_t: String, _s: int, _g: bool) -> String: return WAIT
func can_cast_spell(_h: String, _s: String, _d: String = "") -> String: return WAIT
func can_deep_road(_h: String, _d: String) -> String: return WAIT
func can_convert_town(_t: String) -> String: return WAIT
func can_scout(_h: String, _t: String) -> String: return WAIT
func can_send_resources(_p: int, _b: Dictionary) -> String: return WAIT
func trader_buy_error(_s: String, _h: String, _o: int) -> String: return WAIT
func site_recruit_error(_s: String, _h: String, _c: int, _cr: String = "") -> String: return WAIT
func cobolt_buy_error(_s: String, _h: String, _o: int, _q: int = 1) -> String: return WAIT
func cobolt_rob_error(_s: String, _h: String) -> String: return WAIT
func max_recruitable(_t: String, _c: String) -> int: return 0
func max_site_recruitable(_s: String, _h: String, _c: String = "") -> int: return 0

# The orders themselves.
func build(_t: String, _b: String) -> Dictionary: return _fail(WAIT)
func recruit(_t: String, _c: String, _n: int, _g: bool = false) -> Dictionary: return _fail(WAIT)
func move_stack(_t: String, _s: int, _g: bool) -> Dictionary: return _fail(WAIT)
func transfer_stack(_f: String, _fs: int, _t: String, _ts: int, _n: int = 0) -> Dictionary: return _fail(WAIT)
func upgrade_stack(_t: String, _s: int, _g: bool) -> Dictionary: return _fail(WAIT)
func hire_hero(_t: String) -> Dictionary: return _fail(WAIT)
func trade(_s: String, _b: String, _n: int) -> Dictionary: return _fail(WAIT)
func send_resources(_p: int, _b: Dictionary) -> Dictionary: return _fail(WAIT)
func equip_artifact(_h: String, _a: String) -> Dictionary: return _fail(WAIT)
func unequip_artifact(_h: String, _s: String) -> Dictionary: return _fail(WAIT)
func give_artifact(_f: String, _t: String, _a: String) -> Dictionary: return _fail(WAIT)
func transfer_quest_item(_f: String, _t: String, _i: String) -> Dictionary: return _fail(WAIT)
func cast_spell(_h: String, _s: String, _d: String = "") -> Dictionary: return _fail(WAIT)
func deep_road(_h: String, _d: String) -> Dictionary: return _fail(WAIT)
func convert_town(_t: String) -> Dictionary: return _fail(WAIT)
func trader_buy(_s: String, _h: String, _o: int) -> Dictionary: return _fail(WAIT)
func site_recruit(_s: String, _h: String, _c: int, _cr: String = "") -> Dictionary: return _fail(WAIT)
func cobolt_buy(_s: String, _h: String, _o: int, _q: int = 1) -> Dictionary: return _fail(WAIT)
func cobolt_claim_loot(_s: String, _h: String) -> Dictionary: return _fail(WAIT)
func scout(_h: String, _t: String) -> Dictionary: return _fail(WAIT)
func scenario_act(_h: String, _s: String, _a: String) -> Dictionary: return _fail(WAIT)
func learn_skill(_h: String, _s: String) -> bool: return false
func set_hero_orders(_h: String, _s: String, _f: String) -> bool: return false
func set_battle_orders(_h: String, _c: Dictionary) -> bool: return false
