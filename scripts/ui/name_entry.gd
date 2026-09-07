extends Control

## Title-screen name prompt. LineEdit max 16; Enter confirms, Escape cancels (D-027).

@onready var _prompt: Label = $PromptLabel
@onready var _line: LineEdit = $NameEdit


func _ready() -> void:
	visible = false
	_line.max_length = 16
	_line.text_submitted.connect(_on_text_submitted)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed"):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme()


func is_capturing() -> bool:
	return visible and is_instance_valid(_line) and _line.has_focus()


func open() -> void:
	_line.text = String(Profile.player_name)
	visible = true
	call_deferred("grab_name_focus")


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


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			_cancel()
			get_viewport().set_input_as_handled()
			return
	if not is_capturing():
		return
	if (
		event.is_action_pressed("launch_ball")
		or event.is_action_pressed("restart")
		or event.is_action_pressed("flipper_left")
		or event.is_action_pressed("flipper_right")
	):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_LEFT or key.physical_keycode == KEY_RIGHT:
			get_viewport().set_input_as_handled()


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
