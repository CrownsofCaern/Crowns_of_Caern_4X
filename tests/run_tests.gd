extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd [-- filter]
## Discovers res://tests/unit/test_*.gd and runs every method named test_*.

func _init() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var dir := DirAccess.open("res://tests/unit")
	var files := []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	var all_failures: Array[String] = []
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		# A script with a parse error loads as null or as a script that cannot
		# be instantiated; calling new() on it would leave the runner hanging.
		if script == null or not script.can_instantiate():
			total += 1
			failed += 1
			print("FAIL %s (script failed to load)" % f.get_basename())
			all_failures.append("%s: script failed to load (parse error?)" % f)
			continue
		var inst = script.new()
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if filter != "" and not (f + ":" + mname).contains(filter):
				continue
			total += 1
			inst._current = "%s:%s" % [f.get_basename(), mname]
			var before: int = inst.failures.size()
			if inst.has_method("before_each"):
				inst.before_each()
			var t := Time.get_ticks_msec()
			inst.call(mname)
			var ok: bool = inst.failures.size() == before
			print("%s %s (%d ms)" % ["PASS" if ok else "FAIL", inst._current, Time.get_ticks_msec() - t])
			if not ok:
				failed += 1
		all_failures.append_array(inst.failures)
	print("")
	for msg in all_failures:
		print("  - " + msg)
	print("\n%d tests, %d failed, %.1fs" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	GameData._default = null
	quit(1 if failed > 0 or total == 0 else 0)
