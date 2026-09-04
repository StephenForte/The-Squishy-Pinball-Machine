class_name SquishyCatalog
extends RefCounted

## D-020 squishy roster. Read-only JSON; scoring still follows D-005.

const PATH := "res://assets/design/squishes/squishies_catalog.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_data = parsed
	return _data


static func entry(id: String) -> Dictionary:
	for item in data().get("squishies", []):
		if String(item.get("id", "")) == id:
			return item
	return {}


static func first_table_slots() -> Dictionary:
	var slots: Variant = data().get("first_table_slots", {})
	if typeof(slots) == TYPE_DICTIONARY:
		return slots
	return {}


static func sprite_path(id: String) -> String:
	var item := entry(id)
	if item.is_empty():
		return ""
	return String(item.get("assets", {}).get("sprite", "res://assets/design/squishes/art/%s.png" % id))
