extends Node

## Autoload Theme. Loads D-020 palettes and exposes colours by semantic role.
## palette_changed fires so every themed node can re-apply at runtime.

signal palette_changed(id: String)

const PALETTES_PATH := "res://assets/design/themes/squishies_theme_palettes.json"
const SETTINGS_PATH := "user://settings.save"

var palette_id: String = ""
var default_palette_id: String = ""
var colors: Dictionary = {}

var _palettes: Array = []
var _by_id: Dictionary = {}


func _ready() -> void:
	_load_catalog()
	_load_settings()
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	call_deferred("_apply_table_in_tree")


func color(role: String) -> Color:
	if colors.has(role) and colors[role] is Color:
		return colors[role]
	return Color.WHITE


func palette_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in _palettes:
		ids.append(String(entry.get("id", "")))
	return ids


func palette_name(id: String) -> String:
	if _by_id.has(id):
		return String(_by_id[id].get("name", id))
	return id


func palette_count() -> int:
	return _palettes.size()


func set_palette(id: String) -> void:
	if not _by_id.has(id):
		push_warning("Theme: unknown palette %s" % id)
		return
	palette_id = id
	_rebuild_colors()
	_save_settings()
	_apply_table_in_tree()
	_apply_slots_in_tree()
	palette_changed.emit(id)


func cycle(delta: int) -> void:
	var ids := palette_ids()
	if ids.is_empty():
		return
	var idx := 0
	for i in ids.size():
		if ids[i] == palette_id:
			idx = i
			break
	var next := (idx + delta) % ids.size()
	if next < 0:
		next += ids.size()
	set_palette(ids[next])


func _load_catalog() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PALETTES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Theme: palettes catalog is not a dictionary")
		return
	var data: Dictionary = parsed
	default_palette_id = String(data.get("default_palette_id", ""))
	_palettes = data.get("palettes", [])
	_by_id.clear()
	for entry_var in _palettes:
		var entry: Dictionary = entry_var
		_by_id[String(entry.get("id", ""))] = entry
	if palette_id.is_empty():
		palette_id = default_palette_id
	_rebuild_colors()


func _rebuild_colors() -> void:
	colors.clear()
	var entry: Dictionary = _by_id.get(palette_id, {})
	var raw: Dictionary = entry.get("colors", {})
	for role in raw.keys():
		colors[String(role)] = Color(String(raw[role]))


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		if default_palette_id != "":
			palette_id = default_palette_id
			_rebuild_colors()
		return
	var text := FileAccess.get_file_as_string(SETTINGS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var saved := String(parsed.get("palette_id", ""))
	if _by_id.has(saved):
		palette_id = saved
		_rebuild_colors()


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"palette_id": palette_id}))


func _on_node_added(node: Node) -> void:
	if node.name == "Table":
		call_deferred("_apply_table", node)
		call_deferred("_apply_slots", node)


func _apply_table_in_tree() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var table := tree.root.find_child("Table", true, false)
	if table != null:
		_apply_table(table)


func _apply_slots_in_tree() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var table := tree.root.find_child("Table", true, false)
	if table != null:
		_apply_slots(table)


func _apply_table(table: Node) -> void:
	var bg := table.get_node_or_null("Background")
	if bg is Polygon2D:
		(bg as Polygon2D).color = color("playfield_base")
	var walls := table.get_node_or_null("WallVisuals")
	if walls != null:
		for child in walls.get_children():
			if not (child is Polygon2D):
				continue
			var poly := child as Polygon2D
			if child.name == "LaneSeparator" or child.name == "LaneFloor":
				poly.color = color("rail_secondary")
			else:
				poly.color = color("rail_primary")
	var drain_visual := table.get_node_or_null("Drain/Visual")
	if drain_visual is Polygon2D:
		(drain_visual as Polygon2D).color = color("shadow")


func _apply_slots(table: Node) -> void:
	var slots: Dictionary = SquishyCatalog.first_table_slots()
	for key in slots.keys():
		if key == "decor":
			continue
		var host := table.find_child(String(key), true, false)
		if host == null:
			continue
		var squishy := host.get_node_or_null("Squishy")
		if squishy != null and squishy.has_method("setup"):
			squishy.setup(String(slots[key]))
	var decor_ids: Array = slots.get("decor", [])
	var decor_nodes := [table.get_node_or_null("Decor0"), table.get_node_or_null("Decor1")]
	for i in mini(decor_ids.size(), decor_nodes.size()):
		var decor: Node = decor_nodes[i]
		if decor != null and decor.has_method("setup"):
			decor.setup(String(decor_ids[i]))
