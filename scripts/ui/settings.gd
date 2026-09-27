extends Control

## Title-screen settings overlay (D-035, D-052). Hidden on boot.
## Two pages, stacked from the page buttons downward so a new section
## takes the next free row instead of a hand-picked y.
## Look: avatar and theme. This phone: the app icon.
## While visible it consumes S, menu/Escape, restart/R, launch_ball/Space
## and change_name/N so those keys do not reach main.gd or open NameEntry.
## Guard is is_visible_in_tree(): a closed overlay must not steal Escape/R.
## Children run _unhandled_input before parents, so this Control under Title
## beats scripts/main.gd without editing it.

const PAGE_LOOK := "look"
const PAGE_DEVICE := "device"
const SECTION_GAP := 12.0

var _page := PAGE_LOOK

@onready var _heading: Label = $Heading
@onready var _close: Button = $CloseButton
@onready var _look_button: Button = $LookButton
@onready var _device_button: Button = $DeviceButton
@onready var _avatar: Control = $AvatarPicker
@onready var _theme: Control = $ThemePicker
@onready var _icon: Control = $IconPicker


func _ready() -> void:
	visible = false
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(close)
	_look_button.focus_mode = Control.FOCUS_NONE
	_look_button.pressed.connect(_on_look_pressed)
	_device_button.focus_mode = Control.FOCUS_NONE
	_device_button.pressed.connect(_on_device_pressed)
	resized.connect(queue_redraw)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed"):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme()
	_page = PAGE_LOOK
	_apply_page_layout()
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
	_page = PAGE_LOOK
	_apply_page_layout()
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return is_visible_in_tree()


func show_page(page: String) -> void:
	if page != PAGE_LOOK and page != PAGE_DEVICE:
		return
	_page = page
	_apply_page_layout()


func current_page() -> String:
	return _page


func _on_look_pressed() -> void:
	show_page(PAGE_LOOK)


func _on_device_pressed() -> void:
	show_page(PAGE_DEVICE)


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node == null or not theme_node.has_method("color"):
		return
	_heading.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_style_button(_close, theme_node, false)
	_refresh_page_button_styles()
	queue_redraw()


func _style_button(button: Button, theme_node: Node, selected: bool) -> void:
	if button == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = theme_node.color("glow_gold") if selected else theme_node.color("object_pink")
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	var font: Color = Color(0.12, 0.08, 0.16) if selected else theme_node.color("text_on_color")
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_disabled_color", font)
	button.add_theme_color_override("font_hover_color", font)
	button.add_theme_color_override("font_pressed_color", font)


func _refresh_page_button_styles() -> void:
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node == null or not theme_node.has_method("color"):
		return
	_style_button(_look_button, theme_node, _page == PAGE_LOOK)
	_style_button(_device_button, theme_node, _page == PAGE_DEVICE)


func _all_sections() -> Array[Control]:
	var sections: Array[Control] = []
	for section in [_avatar, _theme, _icon]:
		if section != null:
			sections.append(section)
	return sections


func _sections_for(page: String) -> Array[Control]:
	var sections: Array[Control] = []
	if page == PAGE_DEVICE:
		if _icon != null:
			sections.append(_icon)
		return sections
	for section in [_avatar, _theme]:
		if section != null:
			sections.append(section)
	return sections


func _apply_page_layout() -> void:
	for section in _all_sections():
		section.visible = false
	if _look_button != null:
		_look_button.visible = true
	if _device_button != null:
		_device_button.visible = true
	var y := _content_top()
	for section in _sections_for(_page):
		section.visible = true
		y = _place(section, y)
	_refresh_page_button_styles()


func _content_top() -> float:
	var bottom := 0.0
	if _look_button != null:
		bottom = maxf(bottom, _look_button.offset_bottom)
	if _device_button != null:
		bottom = maxf(bottom, _device_button.offset_bottom)
	return bottom + SECTION_GAP


func _place(ctrl: Control, y: float) -> float:
	if ctrl == null:
		return y
	var h := ctrl.offset_bottom - ctrl.offset_top
	if h < 1.0:
		h = ctrl.size.y
	ctrl.offset_top = y
	ctrl.offset_bottom = y + h
	return y + h + SECTION_GAP


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
