extends Control

## Title-screen name prompt. LineEdit max 16; Enter or Done confirms, Escape cancels (D-027).
## Done is pinned to the top-right band (viewport 576,48, 128×144) so it stays
## clear of PlayButton (ends at x=552) and above a keyboard covering the bottom
## half of 720×1280. Offsets are parent-local: NameEntry's origin is (80, 600).
## clip_contents stays off so the button still receives taps outside that box.

@onready var _prompt: Label = $PromptLabel
@onready var _line: LineEdit = $NameEdit
@onready var _confirm: Button = $ConfirmButton


func _ready() -> void:
	visible = false
	_line.max_length = 16
	_line.text_submitted.connect(_on_text_submitted)
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.pressed.connect(_on_confirm_pressed)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed"):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme()


func is_capturing() -> bool:
	return visible and is_instance_valid(_line) and _line.has_focus()


func open(grab_focus: bool = true) -> void:
	_line.text = String(Profile.player_name)
	visible = true
	if grab_focus:
		call_deferred("grab_name_focus")
	else:
		release_name_focus()


func grab_name_focus() -> void:
	if not visible or not is_instance_valid(_line):
		return
	_line.grab_focus()
	_line.caret_column = _line.text.length()


func release_name_focus() -> void:
	if is_instance_valid(_line) and _line.has_focus():
		_line.release_focus()
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_release_focus()


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node == null or not theme_node.has_method("color"):
		return
	_prompt.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_line.add_theme_color_override("font_color", theme_node.color("text_primary"))
	_line.add_theme_color_override("caret_color", theme_node.color("text_primary"))
	if _confirm != null:
		var style := StyleBoxFlat.new()
		style.bg_color = theme_node.color("object_pink")
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		_confirm.add_theme_stylebox_override("normal", style)
		_confirm.add_theme_stylebox_override("hover", style)
		_confirm.add_theme_stylebox_override("pressed", style)
		_confirm.add_theme_color_override("font_color", theme_node.color("text_on_color"))


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	# Escape is not a name character. Do not mark A/D/R/Space/arrows handled
	# here — `_input` runs before GUI, and the LineEdit needs those keys.
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			_cancel()
			get_viewport().set_input_as_handled()


func _on_confirm_pressed() -> void:
	_on_text_submitted(_line.text)


func _on_text_submitted(raw: String) -> void:
	Profile.call("set_name", raw)
	if String(Profile.player_name).is_empty():
		call_deferred("grab_name_focus")
		return
	release_name_focus()
	visible = false


func _cancel() -> void:
	if String(Profile.player_name).is_empty():
		call_deferred("grab_name_focus")
		return
	_line.text = String(Profile.player_name)
	release_name_focus()
	visible = false
