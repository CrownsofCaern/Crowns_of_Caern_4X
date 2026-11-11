extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd [-- filter]
## Discovers res://tests/unit/test_*.gd and runs every method named test_*.
## With "--queue <dir>" several runners share the files: each runner claims a
## file by creating <dir>/<file> (mkdir is atomic), so run_tests.sh can start
## one runner per CPU core and they balance themselves.
## A test file may list long-running tests (whole AI games, statistical
## balance sweeps) in `const SLOW := ["test_..."]`; they run only with "--slow".

func _init() -> void:
	var filter := ""
	var queue := ""
	var slow := false
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--queue" and i + 1 < args.size():
			queue = args[i + 1]
			i += 2
			continue
		if args[i] == "--slow":
			slow = true
		else:
			filter = args[i]
		i += 1
	var dir := DirAccess.open("res://tests/unit")
	var files := []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	var skipped := 0
	var all_failures: Array[String] = []
	var t0 := Time.get_ticks_msec()
	for f in files:
		if queue != "" and DirAccess.make_dir_absolute(queue.path_join(f)) != OK:
			continue   # another runner has it
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
		var slow_tests: Array = script.get_script_constant_map().get("SLOW", [])
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if filter != "" and not (f + ":" + mname).contains(filter):
				continue
			if slow_tests.has(mname) and not slow:
				skipped += 1
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
	print("\n%d tests, %d failed, %.1fs (%d slow tests skipped; run with --slow)" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0, skipped])
	GameData._default = null
	quit(1 if failed > 0 or (total == 0 and queue == "") else 0)
