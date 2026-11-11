extends "res://tests/test_case.gd"
## Loads every script under res://src and res://tools so parse errors in code
## that no unit test touches (UI, tools) still fail the suite and CI.

func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)


func test_all_scripts_parse() -> void:
	var files := []
	_collect("res://src", files)
	_collect("res://tools", files)
	assert_gt(files.size(), 10)
	for path in files:
		var s: GDScript = load(path)
		assert_true(s != null and s.can_instantiate(), "script failed to load: %s" % path)
