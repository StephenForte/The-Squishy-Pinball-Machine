extends CanvasLayer

## Game over (D-051). Restart and Menu carry a pink stylebox with text_on_color —
## that colour is unreadable on the default dark button. An unnamed player is
## asked for a name here. Save sits on the same row as the field. The name
## commits on Save, on the return key, and on leaving the field with text, so
## a typed name cannot sit uncommitted. Not now discards it.

const DESKTOP_HINT := "R restart · Esc menu"
const TOUCH_HINT := "Restart button  ·  Menu button"

var _game: Node
var _leaderboard: Node
var _last_submit: Dictionary = {}
var _final_score: int = 0
var _is_high_score: bool = false
var _invite_open := false
var _committed := false
var _declined := false
var _blur_commit_queued := false

@onready var _celebration: Node = get_node_or_null("Celebration")
@onready var _final_score_label: Label = $FinalScoreLabel
@onready var _high_score_label: Label = $GameOverHighScoreLabel
@onready var _new_high_score_label: Label = $NewHighScoreLabel
@onready var _your_rank_label: Label = $YourRankLabel
@onready var _offline_label: Label = $OfflineLabel
@onready var _leaderboard_list: VBoxContainer = $LeaderboardList
@onready var _restart_button: Button = $RestartButton
@onready var _menu_button: Button = $MenuButton
@onready var _name_prompt: Label = $NamePrompt
@onready var _name_edit: LineEdit = $NameEdit
@onready var _save_button: Button = $SaveButton
@onready var _skip_button: Button = $SkipButton


func _ready() -> void:
	_game = get_node("/root/Game")
	_leaderboard = get_node_or_null("/root/Leaderboard")
	visible = false
	_new_high_score_label.visible = false
	_restart_button.focus_mode = Control.FOCUS_NONE
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.pressed.connect(_on_menu_pressed)
	_save_button.focus_mode = Control.FOCUS_NONE
	_save_button.pressed.connect(_on_save_pressed)
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.button_down.connect(_on_skip_down)
	_skip_button.pressed.connect(_on_skip_pressed)
	_name_edit.max_length = 16
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(_on_name_focus_exited)
	_hide_invite()
	_game.game_over.connect(_on_game_over)
	_game.game_restarted.connect(_on_game_restarted)
	if _leaderboard != null:
		if _leaderboard.has_signal("board_updated") and not _leaderboard.board_updated.is_connected(_on_board_updated):
			_leaderboard.board_updated.connect(_on_board_updated)
		if _leaderboard.has_signal("submitted") and not _leaderboard.submitted.is_connected(_on_submitted):
			_leaderboard.submitted.connect(_on_submitted)
		if _leaderboard.has_signal("offline") and not _leaderboard.offline.is_connected(_on_offline):
			_leaderboard.offline.connect(_on_offline)
	var theme_node := get_node("/root/Theme")
	theme_node.palette_changed.connect(_apply_theme)
	_apply_theme(theme_node.palette_id)
	_apply_control_hints()
	_reset_leaderboard_ui()


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node("/root/Theme")
	var primary: Color = theme_node.color("text_primary")
	var shade := get_node_or_null("Shade") as ColorRect
	if shade != null:
		var bg: Color = theme_node.color("background")
		bg.a = 0.72
		shade.color = bg
	$TitleLabel.add_theme_color_override("font_color", primary)
	_final_score_label.add_theme_color_override("font_color", primary)
	_high_score_label.add_theme_color_override("font_color", primary)
	_new_high_score_label.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	$HintLabel.add_theme_color_override("font_color", primary)
	_your_rank_label.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_offline_label.add_theme_color_override("font_color", primary)
	_name_prompt.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_style_button(_restart_button, theme_node)
	_style_button(_menu_button, theme_node)
	_style_button(_save_button, theme_node)
	_style_button(_skip_button, theme_node)
	_style_name_edit(theme_node)
	_paint_list_theme()


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


func _style_name_edit(theme_node: Node) -> void:
	if _name_edit == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = theme_node.color("object_pink")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_name_edit.add_theme_stylebox_override("normal", style)
	_name_edit.add_theme_stylebox_override("focus", style)
	_name_edit.add_theme_stylebox_override("read_only", style)
	var on_color: Color = theme_node.color("text_on_color")
	_name_edit.add_theme_color_override("font_color", on_color)
	_name_edit.add_theme_color_override("caret_color", on_color)
	var placeholder := on_color
	placeholder.a = 0.65
	_name_edit.add_theme_color_override("font_placeholder_color", placeholder)


func _apply_control_hints() -> void:
	var label := get_node_or_null("HintLabel") as Label
	if label == null:
		return
	if DisplayServer.is_touchscreen_available():
		label.text = TOUCH_HINT
	else:
		label.text = DESKTOP_HINT


func _on_game_over(final_score: int, is_high_score: bool) -> void:
	_committed = false
	_declined = false
	_blur_commit_queued = false
	_final_score_label.text = "FINAL  %d" % final_score
	_high_score_label.text = "HIGH  %d" % _game.high_score
	_new_high_score_label.visible = is_high_score
	_reset_leaderboard_ui()
	if _leaderboard != null and (_leaderboard.last_entries as Array).size() > 0:
		_render_list(_leaderboard.last_entries)
	_final_score = final_score
	_is_high_score = is_high_score
	_sync_name_invite()
	_apply_control_hints()
	visible = true
	_play_celebration(_tier_for(final_score, is_high_score, 0))


func _on_game_restarted() -> void:
	# R and Esc reach Game.restart() without passing the buttons. A name
	# still in the field is the same "tapped elsewhere" case as those buttons.
	if _invite_open and not _declined and not _committed:
		_commit_pending_name()
	_hide_invite()
	_release_name_focus()
	visible = false
	_new_high_score_label.visible = false
	_reset_leaderboard_ui()
	_stop_celebration()
	_final_score = 0
	_is_high_score = false


func _on_board_updated(entries: Array, _total_players: int) -> void:
	if not visible:
		return
	_offline_label.visible = false
	_render_list(entries)


func _on_submitted(result: Dictionary) -> void:
	_last_submit = result
	_offline_label.visible = false
	_your_rank_label.text = _format_rank_line(result)
	_maybe_upgrade_celebration(result)


func _on_offline(_reason: String) -> void:
	if not visible:
		return
	_offline_label.text = "Leaderboard offline"
	_offline_label.visible = true


func _reset_leaderboard_ui() -> void:
	_last_submit = {}
	_your_rank_label.text = ""
	_offline_label.text = "Leaderboard offline"
	_offline_label.visible = false
	_clear_list()


func _format_rank_line(result: Dictionary) -> String:
	var rank := int(result.get("rank", 0))
	var total := int(result.get("total_players", 0))
	var line := "Rank %d of %d" % [rank, total]
	if bool(result.get("is_personal_best", false)):
		line += " · Personal best!"
	return line


func _render_list(entries: Array) -> void:
	_clear_list()
	var theme_node := get_node_or_null("/root/Theme")
	var primary: Color = Color.WHITE
	var gold: Color = Color(1, 0.92, 0.2, 1)
	if theme_node != null:
		primary = theme_node.color("text_primary")
		gold = theme_node.color("glow_gold")
	var profile := get_node_or_null("/root/Profile")
	var mine := String(profile.player_id).to_lower() if profile != null else ""
	var shown := 0
	for entry_variant in entries:
		if shown >= 10:
			break
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var label := Label.new()
		var rank := int(entry.get("rank", shown + 1))
		var player_name := String(entry.get("name", ""))
		var score := int(entry.get("score", 0))
		var line := "%d. %s  %d" % [rank, player_name, score]
		var pid := String(entry.get("player_id", "")).to_lower()
		var is_mine := not mine.is_empty() and pid == mine
		if is_mine:
			line = "▸ %s" % line
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", gold if is_mine else primary)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("outline_size", 6)
		_leaderboard_list.add_child(label)
		shown += 1


func _clear_list() -> void:
	if _leaderboard_list == null:
		return
	for child in _leaderboard_list.get_children():
		_leaderboard_list.remove_child(child)
		child.free()


func _paint_list_theme() -> void:
	if _leaderboard_list == null or _leaderboard == null:
		return
	if (_leaderboard.last_entries as Array).size() > 0:
		_render_list(_leaderboard.last_entries)


func _tier_rank(tier: String) -> int:
	if tier == "fireworks":
		return 2
	if tier == "confetti":
		return 1
	return 0


func _tier_for(final_score: int, is_high_score: bool, rank: int) -> String:
	if _celebration != null and _celebration.has_method("tier_for"):
		return String(_celebration.tier_for(final_score, is_high_score, rank))
	return "none"


func _play_celebration(tier: String) -> void:
	if _celebration != null and _celebration.has_method("play"):
		_celebration.play(tier)


func _stop_celebration() -> void:
	if _celebration != null and _celebration.has_method("stop"):
		_celebration.stop()


func _maybe_upgrade_celebration(result: Dictionary) -> void:
	if not visible:
		return
	if _celebration == null:
		return
	var current := String(_celebration.get("tier"))
	var rank := int(result.get("rank", 0)) if bool(result.get("is_personal_best", false)) else 0
	var next := _tier_for(_final_score, _is_high_score, rank)
	if _tier_rank(next) > _tier_rank(current):
		_play_celebration(next)


func _sync_name_invite() -> void:
	var profile := get_node_or_null("/root/Profile")
	var unnamed := profile == null or String(profile.player_name).is_empty()
	if unnamed:
		_open_invite()
	else:
		_hide_invite()


func _open_invite() -> void:
	_invite_open = true
	_name_edit.text = ""
	_name_prompt.visible = true
	_name_edit.visible = true
	_save_button.visible = true
	_skip_button.visible = true
	_place_list(true)


func _hide_invite() -> void:
	_invite_open = false
	if _name_prompt != null:
		_name_prompt.visible = false
	if _name_edit != null:
		_name_edit.visible = false
	if _save_button != null:
		_save_button.visible = false
	if _skip_button != null:
		_skip_button.visible = false
	_place_list(false)


func _place_list(invite_open: bool) -> void:
	if _leaderboard_list == null:
		return
	if invite_open:
		_leaderboard_list.offset_top = 700.0
		_leaderboard_list.offset_bottom = 1120.0
	else:
		_leaderboard_list.offset_top = 208.0
		_leaderboard_list.offset_bottom = 500.0


func _on_name_submitted(raw: String) -> void:
	_name_edit.text = raw
	_commit_pending_name()


func _on_name_focus_exited() -> void:
	if _blur_commit_queued or _declined or _committed or not _invite_open:
		return
	# Idle, not now: Not now's button_down in this same click must win, or
	# leaving the field would save a score the player just discarded.
	_blur_commit_queued = true
	_commit_from_blur.call_deferred()


func _commit_from_blur() -> void:
	_blur_commit_queued = false
	if _declined or _committed or not _invite_open:
		return
	var viewport := get_viewport()
	if viewport != null and viewport.gui_get_hovered_control() == _skip_button:
		return
	_commit_pending_name()


func _commit_pending_name() -> void:
	if _committed or _declined or not _invite_open:
		return
	if _name_edit == null:
		return
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if not String(profile.player_name).is_empty():
		_committed = true
		_hide_invite()
		return
	profile.call("set_name", _name_edit.text)
	var named := String(profile.player_name)
	if named.is_empty():
		return
	_committed = true
	var score := _final_score
	_hide_invite()
	_release_name_focus()
	if score > 0 and _leaderboard != null and _leaderboard.has_method("submit"):
		_leaderboard.submit(score)


func _on_save_pressed() -> void:
	_commit_pending_name()


func _on_skip_down() -> void:
	_declined = true


func _on_skip_pressed() -> void:
	_declined = true
	_hide_invite()
	_release_name_focus()


func _release_name_focus() -> void:
	if _name_edit != null and is_instance_valid(_name_edit) and _name_edit.has_focus():
		_name_edit.release_focus()
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_release_focus()


func _on_restart_pressed() -> void:
	_game.restart()


func _on_menu_pressed() -> void:
	var main := get_parent()
	if main != null and main.has_method("return_to_menu"):
		main.return_to_menu()
