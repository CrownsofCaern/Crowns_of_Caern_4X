extends SceneTree
## Rebuild runtime 256px portraits from the preserved generated originals:
## godot --headless --path . --script res://tools/art/build_hero_portraits.gd

func _init() -> void:
	var failed := false
	for group in ["classes", "campaign"]:
		var files := Array(DirAccess.get_files_at("res://assets/source/hero_portraits/" + group))
		for file in files:
			if not file.ends_with(".png"):
				continue
			var img := Image.new()
			if img.load("res://assets/source/hero_portraits/" + group + "/" + file) != OK:
				push_error("Cannot load " + file)
				failed = true
				continue
			img.convert(Image.FORMAT_RGBA8)
			img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
			if img.save_png("res://assets/hero_portraits/" + group + "/" + file) != OK:
				push_error("Cannot save " + file)
				failed = true
	quit(1 if failed else 0)
