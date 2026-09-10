extends Node

## Autoload AppIcon. Loads the D-032 catalog, persists user://app_icon.save,
## and applies the running dock/window icon via DisplayServer.set_icon.

signal icon_changed(id: String)

const CATALOG_PATH := "res://assets/design/icons/app_icons.json"
const SAVE_PATH := "user://app_icon.save"

var icon_id: String = ""
var default_icon_id: String = ""

var _icons: Array = []
var _by_id: Dictionary = {}


func _ready() -> void:
	_load_catalog()
	_load_save()
	apply()


func icon_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in _icons:
		ids.append(String(entry.get("id", "")))
	return ids


func icon_name(id: String) -> String:
	if _by_id.has(id):
		return String(_by_id[id].get("display_name", id))
	return id


func set_icon(id: String) -> bool:
	if not _by_id.has(id):
		return false
	icon_id = id
	_save()
	apply()
	icon_changed.emit(id)
	return true


func apply() -> void:
	var path := _icon_path(icon_id)
	if path.is_empty():
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	DisplayServer.set_icon(img)


func _load_catalog() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AppIcon: catalog is not a dictionary")
		return
	var data: Dictionary = parsed
	default_icon_id = String(data.get("default_icon_id", ""))
	_icons = data.get("icons", [])
	_by_id.clear()
	for entry_var in _icons:
		var entry: Dictionary = entry_var
		_by_id[String(entry.get("id", ""))] = entry
	if icon_id.is_empty():
		icon_id = default_icon_id


func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		if default_icon_id != "":
			icon_id = default_icon_id
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		if default_icon_id != "":
			icon_id = default_icon_id
		return
	var parsed: Dictionary = json.data
	var saved := String(parsed.get("icon_id", ""))
	if _by_id.has(saved):
		icon_id = saved
	elif default_icon_id != "":
		icon_id = default_icon_id


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"icon_id": icon_id}))


func _icon_path(id: String) -> String:
	if not _by_id.has(id):
		return ""
	var assets: Dictionary = _by_id[id].get("assets", {})
	return String(assets.get("icon", ""))
