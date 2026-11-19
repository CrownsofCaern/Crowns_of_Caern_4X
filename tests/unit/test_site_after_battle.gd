extends "res://tests/test_case.gd"
## Winning the battle for a guarded site (a dwelling) leaves the hero standing
## on it: its dialog opens once the battle report closes, and a click on the
## hero's own tile opens it again, so nobody has to step off and back.


class DialogProbe:
	extends SiteDialog
	var opened := ""
	func open(_s: GameSession, site_id: String, _hero_id: String, _lines: Array = []) -> void:
		opened = site_id


class ScreenProbe:
	extends "res://src/ui/adventure_screen.gd"
	func _set_busy(b: bool) -> void:
		_busy = b


func _screen(s: GameSession) -> Array:
	var screen := ScreenProbe.new()
	var dialog := DialogProbe.new()
	screen.session = s
	screen.data = data
	screen.site_dialog = dialog
	screen.selected_hero_id = s.state.heroes_of(0)[0].id
	return [screen, dialog]


func _site(s: GameSession) -> Dictionary:
	var h: Hero = s.state.heroes_of(0)[0]
	var p := s._free_tile_near(h.pos)
	var o := {"id": "test_dwelling", "type": "site", "site": "elder_rings", "pos": [p.x, p.y]}
	s.state.map.add_object(o)
	MapSites.normalize(o, data)
	return o


func test_a_won_site_opens_after_the_report() -> void:
	var s := GameSession.new_game(data, "twin_marches", 3)
	var parts := _screen(s)
	var screen = parts[0]
	var dialog: DialogProbe = parts[1]
	var o := _site(s)
	s.state.heroes_of(0)[0].pos = AdventureMap.object_pos(o)
	screen._site_after_battle = {"id": o["id"], "lines": ["Captured"]}
	assert_true(screen._open_won_site())
	assert_eq(dialog.opened, o["id"])
	assert_true(screen._busy, "the map waits for the dialog")
	dialog.opened = ""
	assert_false(screen._open_won_site(), "only once")
	assert_eq(dialog.opened, "")
	screen.free()
	dialog.free()


func test_no_site_dialog_when_the_hero_is_elsewhere() -> void:
	var s := GameSession.new_game(data, "twin_marches", 3)
	var parts := _screen(s)
	var screen = parts[0]
	var dialog: DialogProbe = parts[1]
	var o := _site(s)
	screen._site_after_battle = {"id": o["id"], "lines": []}
	assert_false(screen._open_won_site(), "a lost or held-off battle leaves the hero off the site")
	assert_eq(dialog.opened, "")
	screen.free()
	dialog.free()
