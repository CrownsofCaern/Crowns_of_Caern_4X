extends SceneTree
## Writes the third-party notices for a release build.
## Usage: godot --headless --path . --script res://tools/release/write_notices.gd -- <output file>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: write_notices.gd -- <output file>")
		quit(2)
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s: %s" % [args[0], error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(ThirdPartyNotices.build_text())
	file.close()
	print("Wrote ", args[0])
	quit(0)
