extends Control

## Settings-overlay avatar grid (D-036). Enumerates every D-020 catalog
## entry at run time, in catalog order. An entry whose sprite will not
## load is skipped (one push_warning, no error spam).

var _offered: PackedStringArray = PackedStringArray()

@onready var _caption: Label = $Caption
@onready var _grid: GridContainer = $Grid


func offered_ids() -> PackedStringArray:
	return _offered


func _ready() -> void:
	_build()
	var profile := get_node("/root/Profile")
	if not profile.avatar_changed.is_connected(_on_avatar_changed):
		profile.avatar_changed.connect(_on_avatar_changed)
	var theme_node := get_node("/root/Theme")
	if not theme_node.palette_changed.is_connected(_on_palette_changed):
		theme_node.palette_changed.connect(_on_palette_changed)
	_apply_theme()
	_refresh_selection()


func _build() -> void:
	_offered = PackedStringArray()
	for child in _grid.get_children():
		child.queue_free()
	var catalog: Dictionary = SquishyCatalog.data()
	for item_variant in catalog.get("squishies", []):
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_variant
		var id := String(item.get("id", ""))
		if id.is_empty():
			continue
		var path := SquishyCatalog.sprite_path(id)
		if path.is_empty() or not ResourceLoader.exists(path):
			push_warning("AvatarPicker: skipping %s (sprite will not load)" % id)
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			push_warning("AvatarPicker: skipping %s (sprite will not load)" % id)
			continue
		_offered.append(id)
		var button := Button.new()
		button.name = "Choice_%s" % id
		button.icon = tex
		button.expand_icon = true
		button.flat = true
		button.custom_minimum_size = Vector2(148, 128)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_choice.bind(id))
		_grid.add_child(button)


func _on_choice(id: String) -> void:
	get_node("/root/Profile").set_avatar(id)


func _on_avatar_changed(_id: String) -> void:
	_refresh_selection()


func _on_palette_changed(_id: String) -> void:
	_apply_theme()
	_refresh_selection()


func _apply_theme() -> void:
	var theme_node := get_node("/root/Theme")
	_caption.add_theme_color_override("font_color", theme_node.color("glow_gold"))


func _refresh_selection() -> void:
	var current := String(get_node("/root/Profile").avatar_id)
	var theme_node := get_node("/root/Theme")
	var selected: Color = theme_node.color("glow_gold")
	for child in _grid.get_children():
		if not (child is Button):
			continue
		var button := child as Button
		var id := String(button.name).trim_prefix("Choice_")
		button.modulate = selected if id == current else Color.WHITE
