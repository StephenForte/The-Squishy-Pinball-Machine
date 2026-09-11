extends Control

## Title-screen app-icon cycle. I or the buttons; live preview via AppIcon.

const CATALOG_PATH := "res://assets/design/icons/app_icons.json"

@onready var _name_label: Label = $NameLabel
@onready var _prev: Button = $PrevButton
@onready var _next: Button = $NextButton
@onready var _preview: TextureRect = $Preview


func _ready() -> void:
	var app_icon := get_node("/root/AppIcon")
	app_icon.icon_changed.connect(_on_icon_changed)
	var theme_node := get_node("/root/Theme")
	theme_node.palette_changed.connect(_on_palette_changed)
	_prev.pressed.connect(func() -> void: _cycle(-1))
	_next.pressed.connect(func() -> void: _cycle(1))
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_I:
		_cycle(1)


func _on_icon_changed(_id: String) -> void:
	_refresh()


func _on_palette_changed(_id: String) -> void:
	_refresh()


func _cycle(step: int) -> void:
	var app_icon := get_node("/root/AppIcon")
	var ids: PackedStringArray = app_icon.icon_ids()
	var n := ids.size()
	if n == 0:
		return
	var idx := 0
	for i in n:
		if String(ids[i]) == String(app_icon.icon_id):
			idx = i
			break
	app_icon.set_icon(String(ids[posmod(idx + step, n)]))


func _refresh() -> void:
	var app_icon := get_node("/root/AppIcon")
	var theme_node := get_node("/root/Theme")
	_name_label.text = app_icon.icon_name(app_icon.icon_id)
	_name_label.add_theme_color_override("font_color", theme_node.color("text_primary"))
	var caption := get_node_or_null("Caption") as Label
	if caption != null:
		caption.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_style_button(_prev, theme_node)
	_style_button(_next, theme_node)
	_preview.texture = load(_catalog_icon_path(app_icon.icon_id)) as Texture2D
	modulate = Color.WHITE


func _catalog_icon_path(id: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var icons: Array = parsed.get("icons", [])
	for entry_var in icons:
		var entry: Dictionary = entry_var
		if String(entry.get("id", "")) == id:
			var assets: Dictionary = entry.get("assets", {})
			return String(assets.get("icon", ""))
	return ""


func _style_button(button: Button, theme_node: Node) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = theme_node.color("object_pink")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_color_override("font_color", theme_node.color("text_on_color"))
