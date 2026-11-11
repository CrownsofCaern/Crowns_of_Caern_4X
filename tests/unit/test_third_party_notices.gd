extends "res://tests/test_case.gd"


func test_notices_contain_godot_licence_and_components() -> void:
	var text := ThirdPartyNotices.build_text()
	assert_true(text.contains("Godot Engine contributors"), "Godot copyright line")
	assert_true(text.contains("Permission is hereby granted"), "MIT licence text")
	assert_true(text.contains("FreeType"), "compiled-in component listed")
	assert_true(text.contains("Licence texts"), "licence text section")


func test_every_component_licence_has_its_text() -> void:
	var text := ThirdPartyNotices.build_text().to_lower()
	var licences: Array = Engine.get_license_info().keys().map(func(n: String) -> String: return n.to_lower())
	for component: Dictionary in Engine.get_copyright_info():
		for part: Dictionary in component["parts"]:
			var licence: String = part["license"]
			# A part's licence may be an expression such as "Expat or MIT"; each name must have its text.
			# Godot's own data spells some names in a different case (BSD-3-Clause / BSD-3-clause).
			for name: String in licence.to_lower().replace("(", " ").replace(")", " ").split(" ", false):
				if name in ["or", "and", "with", "public-domain"]:
					continue
				assert_true(name in licences, "licence %s of %s has a text" % [name, component["name"]])
				assert_true(text.contains("--- %s ---" % name), "licence %s is written out" % name)


func test_notices_are_stable() -> void:
	assert_eq(ThirdPartyNotices.build_text(), ThirdPartyNotices.build_text())
