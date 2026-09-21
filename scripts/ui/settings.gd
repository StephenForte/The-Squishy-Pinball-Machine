extends Control

## Title-screen settings overlay (D-035). Hidden on boot. While visible it
## consumes S, menu/Escape, restart/R, launch_ball/Space and change_name/N
## so those keys do not reach main.gd or open NameEntry under the overlay. Guard is is_visible_in_tree(): a closed overlay
## must not steal Escape/R. Children run _unhandled_input before parents,
## so this Control under Title beats scripts/main.gd without editing it.

@onready var _heading: Label = $Heading
@onready var _close: Button = $CloseButton
@onready var _name_label: Label = $ThisDevice/NameLabel
@onready var _show_toggle: Button = $ThisDevice/ShowCodeToggle
@onready var _code_label: Label = $ThisDevice/CodeLabel
@onready var _copy_button: Button = $ThisDevice/CopyButton
@onready var _restore_edit: LineEdit = $RestoreProfile/CodeEdit
@onready var _restore_button: Button = $RestoreProfile/RestoreButton
@onready var _status_label: Label = $RestoreProfile/StatusLabel


func _ready() -> void:
	visible = false
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(close)
	_show_toggle.focus_mode = Control.FOCUS_NONE
	_show_toggle.pressed.connect(_on_show_code_pressed)
	_copy_button.focus_mode = Control.FOCUS_NONE
	_copy_button.pressed.connect(_on_copy_pressed)
	_restore_button.focus_mode = Control.FOCUS_NONE
	_restore_button.pressed.connect(_on_restore_pressed)
	if _restore_edit != null:
		_restore_edit.focus_mode = Control.FOCUS_CLICK
		_restore_edit.text_submitted.connect(_on_restore_submitted)
	_set_code_visible(false)
	resized.connect(queue_redraw)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed"):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme()
	var profile := get_node_or_null("/root/Profile")
	if profile != null:
		if profile.has_signal("name_changed") and not profile.name_changed.is_connected(_on_profile_name_changed):
			profile.name_changed.connect(_on_profile_name_changed)
		if profile.has_signal("avatar_changed") and not profile.avatar_changed.is_connected(_on_profile_avatar_changed):
			profile.avatar_changed.connect(_on_profile_avatar_changed)
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard != null and leaderboard.has_signal("restore_finished"):
		if not leaderboard.restore_finished.is_connected(_on_restore_finished):
			leaderboard.restore_finished.connect(_on_restore_finished)
	_refresh_transfer_ui()
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
	_set_code_visible(false)
	_set_status("")
	_refresh_transfer_ui()
	visible = true


func close() -> void:
	visible = false
	_set_code_visible(false)
	_release_restore_focus()


func is_open() -> bool:
	return is_visible_in_tree()


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node == null or not theme_node.has_method("color"):
		return
	_heading.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_style_button(_close, theme_node)
	_style_button(_show_toggle, theme_node)
	_style_button(_copy_button, theme_node)
	_style_button(_restore_button, theme_node)
	var gold: Color = theme_node.color("glow_gold")
	var primary: Color = theme_node.color("text_primary")
	for path in ["ThisDevice/Caption", "RestoreProfile/Caption"]:
		var caption := get_node_or_null(path) as Label
		if caption != null:
			caption.add_theme_color_override("font_color", gold)
	if _name_label != null:
		_name_label.add_theme_color_override("font_color", primary)
	if _code_label != null:
		_code_label.add_theme_color_override("font_color", primary)
	if _status_label != null:
		_status_label.add_theme_color_override("font_color", primary)
	if _restore_edit != null:
		_restore_edit.add_theme_color_override("font_color", primary)
		_restore_edit.add_theme_color_override("caret_color", primary)
	queue_redraw()


func _style_button(button: Button, theme_node: Node) -> void:
	if button == null:
		return
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


func _on_profile_name_changed(_name: String) -> void:
	_refresh_transfer_ui()


func _on_profile_avatar_changed(_avatar_id: String) -> void:
	_refresh_transfer_ui()


func _refresh_transfer_ui() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if _name_label != null:
		_name_label.text = String(profile.player_name)
	if _code_label != null:
		_code_label.text = String(profile.player_id)


func _on_show_code_pressed() -> void:
	_set_code_visible(not _code_is_visible())


func _code_is_visible() -> bool:
	return _code_label != null and _code_label.visible


func _set_code_visible(shown: bool) -> void:
	if _code_label != null:
		_code_label.visible = shown
	if _copy_button != null:
		_copy_button.visible = shown
	if _show_toggle != null:
		_show_toggle.text = "Hide transfer code" if shown else "Show transfer code"
	if shown:
		_refresh_transfer_ui()


func _on_copy_pressed() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	var id := String(profile.player_id)
	if id.is_empty():
		return
	DisplayServer.clipboard_set(id)


func _on_restore_submitted(_text: String) -> void:
	_on_restore_pressed()


func _on_restore_pressed() -> void:
	if _restore_edit == null:
		return
	var raw := String(_restore_edit.text).strip_edges()
	if raw.is_empty():
		return
	_set_status("")
	var profile := get_node_or_null("/root/Profile")
	if profile == null or not profile.has_method("_is_uuid_v4") or not bool(profile._is_uuid_v4(raw)):
		_set_status("that code doesn't look right")
		return
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard == null or not leaderboard.has_method("restore_profile"):
		_set_status("couldn't reach the leaderboard")
		return
	leaderboard.restore_profile(raw)


func _on_restore_finished(ok: bool, reason: String) -> void:
	if ok:
		_set_status("")
		if _restore_edit != null:
			_restore_edit.text = ""
		_refresh_transfer_ui()
		return
	if reason == "not_found":
		_set_status("no profile found")
		return
	_set_status("couldn't reach the leaderboard")


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _release_restore_focus() -> void:
	if _restore_edit != null and _restore_edit.has_focus():
		_restore_edit.release_focus()
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_release_focus()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _restore_edit == null or not _restore_edit.has_focus():
		return
	# Swallow only synthetic actions. Real keys must reach CodeEdit as text
	# (`_input` runs before GUI).
	if not (event is InputEventAction):
		return
	if event.is_action_pressed("launch_ball") or event.is_action_pressed("restart") or event.is_action_pressed("change_name"):
		get_viewport().set_input_as_handled()


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
		if _restore_edit != null and _restore_edit.has_focus():
			get_viewport().set_input_as_handled()
			return
		close()
		get_viewport().set_input_as_handled()
