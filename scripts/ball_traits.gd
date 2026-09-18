class_name BallTraits
extends RefCounted

## D-041 ball-trait catalog. Read-only JSON; missing/malformed → empty, one warning.

const PATH := "res://assets/design/ball_traits.json"

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _path: String = PATH
static var warning_count: int = 0
static var last_warning: String = ""


static func load_from(path: String = "") -> void:
	_loaded = false
	_data = {}
	_path = PATH if path.is_empty() else path
	data()


static func data() -> Dictionary:
	if _loaded:
		return _data
	_loaded = true
	_data = {}
	if not FileAccess.file_exists(_path):
		_warn("BallTraits: catalog missing at %s" % _path)
		return _data
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_warn("BallTraits: catalog malformed at %s" % _path)
		return _data
	var catalog: Dictionary = parsed
	if int(catalog.get("schema_version", 0)) != 1:
		_warn("BallTraits: catalog malformed at %s" % _path)
		return _data
	if typeof(catalog.get("traits", null)) != TYPE_ARRAY:
		_warn("BallTraits: catalog malformed at %s" % _path)
		return _data
	_data = catalog
	return _data


static func trait_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item in data().get("traits", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var id := String(item.get("id", ""))
		if not id.is_empty():
			ids.append(id)
	return ids


static func entry(id: String) -> Dictionary:
	for item in data().get("traits", []):
		if typeof(item) == TYPE_DICTIONARY and String(item.get("id", "")) == id:
			return item
	return {}


static func grants(event: String) -> Dictionary:
	var all_grants: Variant = data().get("grants", {})
	if typeof(all_grants) != TYPE_DICTIONARY:
		return {}
	var entry: Variant = (all_grants as Dictionary).get(event, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	return entry


static func _warn(message: String) -> void:
	last_warning = message
	warning_count += 1
	push_warning(message)
