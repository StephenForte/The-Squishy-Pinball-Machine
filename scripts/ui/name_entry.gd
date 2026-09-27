extends Control

## Title-screen name prompt. The name commits on Done, on the return key, and
## on leaving the field with text (the same rule as game over). Done sits on
## the field's row, under Play and above the keyboard line. A typed name is
## resolved against the server; a failure keeps the text on screen and does
## not mint a local identity.

@onready var _prompt: Label = $PromptLabel
@onready var _line: LineEdit = $NameEdit
@onready var _confirm: Button = $ConfirmButton
@onready var _status: Label = $StatusLabel

var _resolve_pending := false
var _pending_gen := -1
var _blur_commit_queued := false
var _suppress_blur := false
## What they typed when the server could not say who owns it. Shown again if
## the prompt is reopened before a name is actually saved.
var _unresolved_text := ""


func _ready() -> void:
	visible = false
	_line.max_length = 16
	_line.text_submitted.connect(_on_text_submitted)
	_line.focus_exited.connect(_on_focus_exited)
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.pressed.connect(_on_confirm_pressed)
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard != null and leaderboard.has_signal("name_resolved"):
		if not leaderboard.name_resolved.is_connected(_on_name_resolved):
			leaderboard.name_resolved.connect(_on_name_resolved)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed"):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme()


func is_capturing() -> bool:
	return visible and is_instance_valid(_line) and _line.has_focus()


func open(grab_focus: bool = true) -> void:
	var saved := _saved_name()
	if saved.is_empty() and not _unresolved_text.is_empty():
		_line.text = _unresolved_text
	else:
		_line.text = saved
		if not saved.is_empty():
			_unresolved_text = ""
			_set_status("")
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
	if _status != null:
		_status.add_theme_color_override("font_color", theme_node.color("text_primary"))
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
	_commit_text()


func _on_text_submitted(raw: String) -> void:
	_line.text = raw
	_commit_text()


func _on_focus_exited() -> void:
	if _suppress_blur:
		_suppress_blur = false
		return
	if _blur_commit_queued or _resolve_pending:
		return
	_blur_commit_queued = true
	_commit_from_blur.call_deferred()


func _commit_from_blur() -> void:
	_blur_commit_queued = false
	if _suppress_blur:
		_suppress_blur = false
		return
	if _resolve_pending:
		return
	_commit_text()


func _commit_text() -> void:
	_drop_stale_claim()
	if _resolve_pending:
		return
	if _line == null:
		return
	var raw := _line.text
	if raw.strip_edges().is_empty():
		return
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard == null or not leaderboard.has_method("resolve_name"):
		_show_unresolved(raw, "unreachable")
		return
	_resolve_pending = true
	_pending_gen = int(leaderboard.resolve_name(raw))


func _on_name_resolved(generation: int, ok: bool, info: Dictionary) -> void:
	if generation != _pending_gen:
		return
	_resolve_pending = false
	if ok:
		_unresolved_text = ""
		_set_status("")
		visible = false
		_release_without_commit()
		return
	_show_unresolved(_line.text if _line != null else "", String(info.get("reason", "")))


func _show_unresolved(text: String, reason: String) -> void:
	_unresolved_text = text
	if _line != null:
		_line.text = text
	visible = true
	_set_status(_failure_line(reason))
	# Leave the field so Play is not swallowed, but keep the typed name up.
	_release_without_commit()


func _failure_line(reason: String) -> String:
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard != null and leaderboard.has_method("offline_line"):
		return String(leaderboard.offline_line(reason))
	return "Leaderboard offline"


func _release_without_commit() -> void:
	if _line != null and _line.has_focus():
		_suppress_blur = true
		release_name_focus()
	else:
		_suppress_blur = false


func _cancel() -> void:
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if _claim_is_current() and leaderboard != null and leaderboard.has_method("retire_name_resolve"):
		leaderboard.retire_name_resolve()
	_resolve_pending = false
	if _saved_name().is_empty():
		call_deferred("grab_name_focus")
		return
	_unresolved_text = ""
	_set_status("")
	_line.text = _saved_name()
	_release_without_commit()
	visible = false


func _drop_stale_claim() -> void:
	if _resolve_pending and not _claim_is_current():
		_resolve_pending = false


func _claim_is_current() -> bool:
	if not _resolve_pending:
		return false
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard == null:
		return false
	return int(leaderboard._resolve_gen) == _pending_gen


func _saved_name() -> String:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return ""
	return String(profile.player_name)


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message
