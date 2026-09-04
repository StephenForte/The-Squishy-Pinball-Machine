extends Control

## Title-screen palette cycle. ←/→ or the buttons; live preview via Theme.

@onready var _name_label: Label = $NameLabel
@onready var _prev: Button = $PrevButton
@onready var _next: Button = $NextButton


func _ready() -> void:
	var theme_node := get_node("/root/Theme")
	theme_node.palette_changed.connect(_on_palette_changed)
	_prev.pressed.connect(func() -> void: theme_node.cycle(-1))
	_next.pressed.connect(func() -> void: theme_node.cycle(1))
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_LEFT:
		get_node("/root/Theme").cycle(-1)
	elif key.physical_keycode == KEY_RIGHT:
		get_node("/root/Theme").cycle(1)


func _on_palette_changed(_id: String) -> void:
	_refresh()


func _refresh() -> void:
	var theme_node := get_node("/root/Theme")
	_name_label.text = theme_node.palette_name(theme_node.palette_id)
	_name_label.add_theme_color_override("font_color", theme_node.color("text_primary"))
	var caption := get_node_or_null("Caption") as Label
	if caption != null:
		caption.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_style_button(_prev, theme_node)
	_style_button(_next, theme_node)
	modulate = Color.WHITE


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
