class_name ThirdPartyNotices
extends RefCounted
## Builds the licence notices that every exported build must ship: the Godot
## Engine's own MIT notice, the copyright lines of every component compiled into
## the engine, and the full text of each licence they use. The text comes from
## the running engine, so it always matches the engine version that made the
## build. tools/release/write_notices.gd writes it next to the release archives.

const HEADER := "Crowns of Caern: third-party notices\n\nThis game is built with the Godot Engine (https://godotengine.org).\nThe Godot Engine and the components compiled into it are distributed under\nthe licences below. The game's own licence is in LICENSE and the credits for\nfonts, textures, models and animation are in CREDITS.md.\n"


static func build_text() -> String:
	var parts: PackedStringArray = [HEADER]
	parts.append(_rule("Godot Engine %s" % _engine_version()))
	parts.append(Engine.get_license_text().strip_edges())
	parts.append(_rule("Components compiled into the Godot Engine"))
	for component: Dictionary in Engine.get_copyright_info():
		parts.append(_component_text(component))
	parts.append(_rule("Licence texts"))
	var licences: Dictionary = Engine.get_license_info()
	var names: Array = licences.keys()
	names.sort()
	for licence_name: String in names:
		parts.append("--- %s ---\n\n%s" % [licence_name, String(licences[licence_name]).strip_edges()])
	return "\n\n".join(parts) + "\n"


static func _component_text(component: Dictionary) -> String:
	var lines: PackedStringArray = [String(component.get("name", ""))]
	for part: Dictionary in component.get("parts", []):
		var files: PackedStringArray = part.get("files", PackedStringArray())
		if not files.is_empty():
			lines.append("  Files: %s" % ", ".join(files))
		for holder: String in part.get("copyright", PackedStringArray()):
			lines.append("  Copyright: %s" % holder)
		lines.append("  License: %s" % String(part.get("license", "")))
	return "\n".join(lines)


static func _engine_version() -> String:
	var info: Dictionary = Engine.get_version_info()
	return "%s (%s)" % [String(info.get("string", "")), String(info.get("hash", "")).left(9)]


static func _rule(title: String) -> String:
	return "=".repeat(79) + "\n" + title + "\n" + "=".repeat(79)
