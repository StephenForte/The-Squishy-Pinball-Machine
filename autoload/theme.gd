extends Node

## Autoload Theme. Loads D-020 palettes and exposes colours by semantic role.
## palette_changed fires so every themed node can re-apply at runtime.
##
## D-061: during a run the active palette is the saved pick shifted by
## floor(score / 10_000), and that shift is never written to settings.save.
## palette_id is the palette on screen. saved_palette_id is the player's pick
## and the only id _save_settings() stores. A pick (set_palette / cycle) updates
## the saved base, then the run offset is applied on top.

signal palette_changed(id: String)

const PALETTES_PATH := "res://assets/design/themes/squishies_theme_palettes.json"
const SETTINGS_PATH := "user://settings.save"
const CYCLE_EVERY := 10000

var palette_id: String = ""
var saved_palette_id: String = ""
var default_palette_id: String = ""
var colors: Dictionary = {}

var _palettes: Array = []
var _by_id: Dictionary = {}
var _other_settings: Dictionary = {}


func _ready() -> void:
	_load_catalog()
	_load_settings()
	_connect_game()
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	# Real boot already has the main scene in the tree (D-030). Tests add it later.
	call_deferred("_bind_title")
	call_deferred("_apply_table_in_tree")
	call_deferred("_apply_slots_in_tree")


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)
	_disconnect_game()
	_unwatch_title(_find_title())


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
	saved_palette_id = id
	_save_settings()
	# Force an emission even when the resolved id is unchanged, matching the
	# previous set_palette contract (listeners re-tint on every pick).
	_sync_active(true)


func cycle(delta: int) -> void:
	var ids := palette_ids()
	if ids.is_empty():
		return
	var next := (_index_of(saved_palette_id) + delta) % ids.size()
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
	if saved_palette_id.is_empty():
		saved_palette_id = palette_id
	_rebuild_colors()


func _rebuild_colors() -> void:
	colors.clear()
	var entry: Dictionary = _by_id.get(palette_id, {})
	var raw: Dictionary = entry.get("colors", {})
	for role in raw.keys():
		colors[String(role)] = Color(String(raw[role]))


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		_other_settings = {}
		if default_palette_id != "":
			saved_palette_id = default_palette_id
			palette_id = default_palette_id
			_rebuild_colors()
		_sync_active(false)
		return
	var text := FileAccess.get_file_as_string(SETTINGS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	var extra := data.duplicate()
	extra.erase("palette_id")
	_other_settings = extra
	var saved := String(data.get("palette_id", ""))
	if _by_id.has(saved):
		saved_palette_id = saved
		palette_id = saved
		_rebuild_colors()
	_sync_active(false)


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	var payload := _other_settings.duplicate()
	payload["palette_id"] = saved_palette_id
	file.store_string(JSON.stringify(payload))


func _connect_game() -> void:
	var game := get_node_or_null("/root/Game")
	if game == null:
		push_warning("Theme: Game autoload missing; run palette will not follow score")
		return
	if not game.score_changed.is_connected(_on_score_changed):
		game.score_changed.connect(_on_score_changed)
	if not game.game_over.is_connected(_on_game_over):
		game.game_over.connect(_on_game_over)
	if not game.game_restarted.is_connected(_on_game_restarted):
		game.game_restarted.connect(_on_game_restarted)


func _disconnect_game() -> void:
	var game := get_node_or_null("/root/Game")
	if game == null:
		return
	if game.score_changed.is_connected(_on_score_changed):
		game.score_changed.disconnect(_on_score_changed)
	if game.game_over.is_connected(_on_game_over):
		game.game_over.disconnect(_on_game_over)
	if game.game_restarted.is_connected(_on_game_restarted):
		game.game_restarted.disconnect(_on_game_restarted)


func _on_score_changed(_new_score: int) -> void:
	_sync_active(false)


func _on_game_over(_final_score: int, _is_high_score: bool) -> void:
	_sync_active(false)


func _on_game_restarted() -> void:
	_sync_active(false)


func _on_title_visibility() -> void:
	_sync_active(false)


func _bind_title() -> void:
	var title := _find_title()
	if title == null:
		return
	_watch_title(title)
	_sync_active(false)


func _find_title() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.find_child("Title", true, false)


func _watch_title(title: Node) -> void:
	if title == null or not title.has_signal("visibility_changed"):
		return
	if not title.is_connected("visibility_changed", _on_title_visibility):
		title.connect("visibility_changed", _on_title_visibility)


func _unwatch_title(title: Node) -> void:
	if title == null or not title.has_signal("visibility_changed"):
		return
	if title.is_connected("visibility_changed", _on_title_visibility):
		title.disconnect("visibility_changed", _on_title_visibility)


func _title_is_shown() -> bool:
	# Title is a CanvasLayer, which is not a CanvasItem, so it has `visible`
	# and no is_visible_in_tree().
	var title := _find_title()
	if title == null:
		return false
	return bool(title.get("visible"))


func _show_saved_pick() -> bool:
	if _title_is_shown():
		return true
	var game := get_node_or_null("/root/Game")
	if game == null:
		return true
	return int(game.state) == int(game.GAME_OVER)


func _current_score() -> int:
	var game := get_node_or_null("/root/Game")
	if game == null:
		return 0
	return int(game.score)


func _index_of(id: String) -> int:
	var ids := palette_ids()
	for i in ids.size():
		if ids[i] == id:
			return i
	return 0


func _palette_for_score(score: int) -> String:
	var ids := palette_ids()
	if ids.is_empty():
		return saved_palette_id
	var steps := 0
	if score > 0:
		steps = int(floor(float(score) / float(CYCLE_EVERY)))
	var idx := (_index_of(saved_palette_id) + steps) % ids.size()
	return String(ids[idx])


func _resolved_palette_id() -> String:
	if saved_palette_id.is_empty():
		return palette_id
	if _show_saved_pick():
		return saved_palette_id
	return _palette_for_score(_current_score())


func _sync_active(force_emit: bool) -> void:
	var id := _resolved_palette_id()
	if id.is_empty() or not _by_id.has(id):
		return
	var changed := palette_id != id
	if not changed and not force_emit:
		return
	palette_id = id
	_rebuild_colors()
	_apply_table_in_tree()
	_apply_slots_in_tree()
	palette_changed.emit(id)


func _on_node_added(node: Node) -> void:
	if node.name == "Table":
		call_deferred("_apply_table", node)
		call_deferred("_apply_slots", node)
	elif node.name == "Title":
		_watch_title(node)
		call_deferred("_sync_active", false)


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
