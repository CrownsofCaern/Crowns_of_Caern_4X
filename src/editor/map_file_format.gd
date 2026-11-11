class_name MapFileFormat
extends RefCounted
## The on-disk layout of data/maps/*.json, byte-compatible with maplib.write in
## tools/maps/maplib.py: one terrain row per line, one entry per line for
## players, heroes, objects and roads, every other top-level key on one line.
## Values are written like Python's json.dumps (", " and ": " separators,
## non-ASCII escaped), so a map saved by the editor, frozen by the tool or
## written by a builder script diffs cleanly against the others.

const ROW_KEYS := ["heroes", "objects", "players", "roads"]


static func encode(definition: Dictionary) -> String:
	var lines: Array[String] = []
	var keys := definition.keys()
	for i in keys.size():
		var key: Variant = keys[i]
		var value: Variant = definition[key]
		var separator := "," if i < keys.size() - 1 else ""
		var key_text := value_text(String(key))
		if key == "terrain" and value is Array:
			var rows: Array[String] = []
			for row in value:
				rows.append("    " + value_text(row))
			lines.append("  %s: [\n%s\n  ]%s" % [key_text, ",\n".join(rows), separator])
		elif key in ROW_KEYS and value is Array:
			var entries: Array[String] = []
			for entry in value:
				entries.append("    " + value_text(entry))
			# maplib writes an empty list as "[\n\n  ]"; keep the same bytes.
			lines.append("  %s: [\n%s\n  ]%s" % [key_text, ",\n".join(entries), separator])
		else:
			lines.append("  %s: %s%s" % [key_text, value_text(value), separator])
	return "{\n" + "\n".join(lines) + "\n}\n"


## One JSON value in json.dumps style. JSON has a single number type and Godot
## decodes every number as a float, so whole numbers are written without ".0".
static func value_text(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var number := float(value)
			if is_finite(number) and number == floor(number) and absf(number) < 9007199254740992.0:
				return str(int(number))
			return str(number)
		TYPE_STRING, TYPE_STRING_NAME:
			return _string_text(String(value))
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var parts: Array[String] = []
			for entry in value:
				parts.append(value_text(entry))
			return "[" + ", ".join(parts) + "]"
		TYPE_VECTOR2I, TYPE_VECTOR2:
			return "[%s, %s]" % [value_text(value.x), value_text(value.y)]
		TYPE_DICTIONARY:
			var parts: Array[String] = []
			for key in value:
				parts.append(_string_text(String(key)) + ": " + value_text(value[key]))
			return "{" + ", ".join(parts) + "}"
	return _string_text(str(value))


static func _string_text(text: String) -> String:
	var out := "\""
	for i in text.length():
		var code := text.unicode_at(i)
		match code:
			0x22:
				out += "\\\""
			0x5C:
				out += "\\\\"
			0x0A:
				out += "\\n"
			0x0D:
				out += "\\r"
			0x09:
				out += "\\t"
			0x08:
				out += "\\b"
			0x0C:
				out += "\\f"
			_:
				if code < 0x20 or code > 0x7E:
					if code > 0xFFFF:
						var rest := code - 0x10000
						out += "\\u%04x\\u%04x" % [0xD800 + (rest >> 10), 0xDC00 + (rest & 0x3FF)]
					else:
						out += "\\u%04x" % code
				else:
					out += char(code)
	return out + "\""
