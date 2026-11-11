extends RefCounted
## Minimal GUT-style test base (see docs/DESIGN.md: we use a tiny runner
## because GUT could not be fetched in the build environment; assertion names
## match GUT so tests can migrate unchanged).

var failures: Array[String] = []
var _current: String = ""
var data: GameData = GameData.get_default()


func _fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		_fail("expected true. " + msg)


func assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		_fail("expected false. " + msg)


func assert_eq(got: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(got) != typeof(expected) and not (typeof(got) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]):
		_fail("expected %s (%s) but got %s (%s). %s" % [expected, type_string(typeof(expected)), got, type_string(typeof(got)), msg])
	elif got != expected:
		_fail("expected %s but got %s. %s" % [expected, got, msg])


func assert_ne(got: Variant, unexpected: Variant, msg: String = "") -> void:
	if got == unexpected:
		_fail("did not expect %s. %s" % [got, msg])


func assert_gt(got: float, bound: float, msg: String = "") -> void:
	if not got > bound:
		_fail("expected %s > %s. %s" % [got, bound, msg])


func assert_lt(got: float, bound: float, msg: String = "") -> void:
	if not got < bound:
		_fail("expected %s < %s. %s" % [got, bound, msg])


func assert_between(got: float, lo: float, hi: float, msg: String = "") -> void:
	if got < lo or got > hi:
		_fail("expected %s in [%s, %s]. %s" % [got, lo, hi, msg])
