extends Control

## Title-screen name prompt. The name commits on Done, on the return key, and
## on leaving the field with text (the same rule as game over). Done sits on
## the field's row, under Play and above the keyboard line. A typed name is
## resolved against the server; a failure keeps the text on screen and does
## not mint a local identity.
##
## An existing name asks first. resolve_name adopts before it signals, so the
## prompt peeks at the same route and only calls resolve_name once the player
## says the name is theirs — or immediately, when the name is new.

const _WELCOME_FMT := "Welcome back, %s!"

@onready var _prompt: Label = $PromptLabel
@onready var _line: LineEdit = $NameEdit
@onready var _confirm: Button = $ConfirmButton
@onready var _status: Label = $StatusLabel
@onready var _welcome: Label = $WelcomeLabel
@onready var _yes: Button = $YesButton
@onready var _no: Button = $NoButton

var _resolve_pending := false
var _pending_gen := -1
var _blur_commit_queued := false
var _suppress_blur := false
## What they typed when the server could not say who owns it. Shown again if
## the prompt is reopened before a name is actually saved.
var _unresolved_text := ""
var _probe_pending := false
var _pending_lookup := -1
var _confirming := false


func _ready() -> void:
	visible = false
	_line.max_length = 16
	_line.text_submitted.connect(_on_text_submitted)
	_line.focus_exited.connect(_on_focus_exited)
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.pressed.connect(_on_confirm_pressed)
	_yes.focus_mode = Control.FOCUS_NONE
	_yes.pressed.connect(_on_yes_pressed)
	_no.focus_mode = Control.FOCUS_NONE
	_no.pressed.connect(_on_no_pressed)
	_show_edit_row()
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard != null and leaderboard.has_signal("name_resolved"):
		if not leaderboard.name_resolved.is_connected(_on_name_resolved):
			leaderboard.name_resolved.connect(_on_name_resolved)
	if leaderboard != null and leaderboard.has_signal("name_lookup"):
		if not leaderboard.name_lookup.is_connected(_on_name_lookup):
			leaderboard.name_lookup.connect(_on_name_lookup)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed"):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme()


func is_capturing() -> bool:
	return visible and is_instance_valid(_line) and _line.visible and _line.has_focus()


## True while a rename, a typed-name confirmation, or a claim is on screen.
## The boot prompt must not replace that (D-058).
func blocks_unconfirmed_prompt() -> bool:
	# A claim or probe still in flight must finish, even if the title is hidden.
	if _resolve_pending or _probe_pending:
		return true
	# Hidden with the title: nothing on screen to replace. A confirmation or
	# rename that is actually up must stay up.
	if not visible:
		return false
	if _confirming:
		return true
	if _line != null and _line.visible:
		return true
	return false


## Boot confirmation for the device's last player. That's me claims through
## resolve_name. Not me returns to the edit row. Does nothing if a prompt
## the player already opened would be replaced.
func offer_unconfirmed(display: String) -> void:
	if display.strip_edges().is_empty():
		return
	if blocks_unconfirmed_prompt():
		return
	_invalidate_probe()
	if _line != null:
		_line.text = display
	visible = true
	_show_welcome(display)


func open(grab_focus: bool = true) -> void:
	_invalidate_probe()
	_confirming = false
	_show_edit_row()
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
	if not visible or not is_instance_valid(_line) or not _line.visible:
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
	if _welcome != null:
		_welcome.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_line.add_theme_color_override("font_color", theme_node.color("text_primary"))
	_line.add_theme_color_override("caret_color", theme_node.color("text_primary"))
	if _status != null:
		_status.add_theme_color_override("font_color", theme_node.color("text_primary"))
	for button in [_confirm, _yes, _no]:
		_style_button(button, theme_node)


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


func _on_yes_pressed() -> void:
	if not _confirming or _resolve_pending:
		return
	var raw := _line.text if _line != null else ""
	_confirming = false
	_show_edit_row()
	_resolve_for_commit(raw)


func _on_no_pressed() -> void:
	_back_out_of_welcome()


func _on_text_submitted(raw: String) -> void:
	_line.text = raw
	_commit_text()


func _on_focus_exited() -> void:
	if _suppress_blur:
		_suppress_blur = false
		return
	if _blur_commit_queued or _resolve_pending or _probe_pending or _confirming:
		return
	_blur_commit_queued = true
	_commit_from_blur.call_deferred()


func _commit_from_blur() -> void:
	_blur_commit_queued = false
	if _suppress_blur:
		_suppress_blur = false
		return
	if _resolve_pending or _probe_pending or _confirming:
		return
	_commit_text()


func _commit_text() -> void:
	_drop_stale_claim()
	if _resolve_pending or _probe_pending or _confirming:
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
	# The closed-port sentinel cannot say whether the name exists. Keep the
	# fail-closed resolve path so a missed server still adopts nothing.
	if leaderboard.has_method("_profile_http_skipped") and bool(leaderboard._profile_http_skipped()):
		_resolve_for_commit(raw)
		return
	_start_probe(raw, leaderboard)


func _resolve_for_commit(raw: String) -> void:
	if _resolve_pending:
		return
	if raw.strip_edges().is_empty():
		return
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard == null or not leaderboard.has_method("resolve_name"):
		_show_unresolved(raw, "unreachable")
		return
	_resolve_pending = true
	_pending_gen = int(leaderboard.resolve_name(raw))


func _start_probe(raw: String, leaderboard: Node) -> void:
	_probe_pending = true
	if not leaderboard.has_method("lookup_name"):
		_probe_pending = false
		_resolve_for_commit(raw)
		return
	_pending_lookup = int(leaderboard.lookup_name(raw))


func _on_name_lookup(generation: int, info: Dictionary) -> void:
	if generation != _pending_lookup:
		return
	if not _probe_pending:
		return
	_probe_pending = false
	if _confirming or _resolve_pending:
		return
	var queried := String(info.get("queried", ""))
	if _line == null or _line.text != queried:
		return
	if not bool(info.get("answered", false)) or not bool(info.get("held", false)):
		_resolve_for_commit(queried)
		return
	var display := String(info.get("display", "")).strip_edges()
	if display.is_empty():
		display = queried.strip_edges()
	_show_welcome(display)


func _show_welcome(display: String) -> void:
	_confirming = true
	_prompt.visible = false
	_line.visible = false
	_confirm.visible = false
	if _status != null:
		_status.visible = false
	_welcome.text = _WELCOME_FMT % display
	_welcome.visible = true
	_yes.visible = true
	_no.visible = true
	_suppress_blur = true
	_release_without_commit()


func _show_edit_row() -> void:
	if _welcome != null:
		_welcome.visible = false
	if _yes != null:
		_yes.visible = false
	if _no != null:
		_no.visible = false
	if _prompt != null:
		_prompt.visible = true
	if _line != null:
		_line.visible = true
	if _confirm != null:
		_confirm.visible = true
	if _status != null:
		_status.visible = true


func _back_out_of_welcome() -> void:
	if not _confirming:
		return
	_confirming = false
	_show_edit_row()
	call_deferred("grab_name_focus")


func _invalidate_probe() -> void:
	_probe_pending = false
	_pending_lookup = -1


func _on_name_resolved(generation: int, ok: bool, info: Dictionary) -> void:
	if generation != _pending_gen:
		return
	_resolve_pending = false
	if ok:
		_confirming = false
		_unresolved_text = ""
		_set_status("")
		visible = false
		_release_without_commit()
		return
	_show_unresolved(_line.text if _line != null else "", String(info.get("reason", "")))


func _show_unresolved(text: String, reason: String) -> void:
	_confirming = false
	_unresolved_text = text
	_show_edit_row()
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
	_invalidate_probe()
	if _confirming:
		_back_out_of_welcome()
		return
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
