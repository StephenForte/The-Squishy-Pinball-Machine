extends Control

## Title-screen settings overlay (D-035). Hidden on boot. While visible it
## consumes S, menu/Escape, restart/R, launch_ball/Space and change_name/N
## so those keys do not reach main.gd or open NameEntry under the overlay. Guard is is_visible_in_tree(): a closed overlay
## must not steal Escape/R. Children run _unhandled_input before parents,
## so this Control under Title beats scripts/main.gd without editing it.

@onready var _heading: Label = $Heading
@onready var _close: Button = $CloseButton


func _ready() -> void:
	visible = false
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(close)
	resized.connect(queue_redraw)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed"):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme()
	queue_redraw()


func _draw() -> void:
	var fill := Color(0.05, 0.04, 0.08, 0.92)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null and theme_node.has_method("color"):
		fill = theme_node.color("background")
		fill.a = 0.97
	draw_rect(Rect2(Vector2.ZERO, size), fill)


func open() -> void:
	var title := get_parent()
	if title != null and title.has_method("is_capturing_name") and title.is_capturing_name():
		return
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return is_visible_in_tree()


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node == null or not theme_node.has_method("color"):
		return
	_heading.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	var style := StyleBoxFlat.new()
	style.bg_color = theme_node.color("object_pink")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_close.add_theme_stylebox_override("normal", style)
	_close.add_theme_stylebox_override("hover", style)
	_close.add_theme_stylebox_override("pressed", style)
	_close.add_theme_color_override("font_color", theme_node.color("text_on_color"))
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("menu"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("launch_ball"):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("change_name"):
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_S:
		close()
		get_viewport().set_input_as_handled()
