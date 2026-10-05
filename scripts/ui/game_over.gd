extends CanvasLayer

## Game over (D-051). Restart and Menu carry a pink stylebox with text_on_color —
## that colour is unreadable on the default dark button. An unnamed player, and
## an unconfirmed one (D-058), are asked for a name here. The field opens
## blank only when this device has no last player; otherwise it is pre-filled
## with that name. Save is disabled while the field is blank. A typed name
## that differs from the last player and is already held asks before it adopts.
## The name commits on Save, on the return key, and on leaving the field with
## text, so a typed name cannot sit uncommitted. Not now discards it.

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
var _resolve_pending := false
var _lookup_pending := false
var _pending_lookup := -1
var _confirming := false
## The invite opened with a last player already on the device. A name that
## arrives later, from a claim this invite did not start, is a different case.
var _opened_with_name := false
var _pending_gen := -1
var _pending_score := 0
var _game_serial := 0
var _pending_serial := -1
## Submit token of the game on screen, or -1 when that game did not post.
## A 409 for any other token must not open this game's invite.
var _screen_token := -1
var _applied_epoch := 0
## Latest score-refusal token. Applied once `_screen_token` is known, so a
## fast answer cannot land before the screen has recorded its game.
var _pending_refusal := -1
## True only for a claim this invite started. A carried claim must still
## finish, and Not now must not cancel it.
var _claim_started_here := false
## This game's score has been handed to Leaderboard. A second path (the late
## claim, or Save after the name already landed) must not post it again.
var _posted_final := false
## The score captured when a claim started. Distinct from `_posted_final` when
## a newer game is on screen by the time the claim returns.
var _posted_pending := false
const _NAME_PROMPT := "Name this score"
const _WELCOME_FMT := "Welcome back, %s!"
## True only while Not now is held. A drag-off must not latch a decline.
var _skip_holding := false
## Set on Not now press-down so a blur queued by that gesture cannot commit
## after the finger lifts outside the button.
var _suppress_blur_commit := false
## Name and id read at submit_attempted, which is the same moment Leaderboard
## reads them for the POST body. The 201 must show this pair, not whoever
## Profile says when the response lands.
var _bound_token := -1
var _bound_id := ""
var _bound_name := ""

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
@onready var _welcome: Label = $WelcomeLabel
@onready var _yes: Button = $YesButton
@onready var _no: Button = $NoButton
@onready var _saved_as: Label = $SavedAsLabel
@onready var _not_you: Button = $NotYouButton


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
	_skip_button.button_up.connect(_on_skip_up)
	_skip_button.pressed.connect(_on_skip_pressed)
	_name_edit.max_length = 16
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.text_changed.connect(_on_name_text_changed)
	_name_edit.focus_exited.connect(_on_name_focus_exited)
	if _yes != null:
		_yes.focus_mode = Control.FOCUS_NONE
		_yes.pressed.connect(_on_yes_pressed)
	if _no != null:
		_no.focus_mode = Control.FOCUS_NONE
		_no.pressed.connect(_on_no_pressed)
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
		if _leaderboard.has_signal("name_resolved") and not _leaderboard.name_resolved.is_connected(_on_name_resolved):
			_leaderboard.name_resolved.connect(_on_name_resolved)
		if _leaderboard.has_signal("name_lookup") and not _leaderboard.name_lookup.is_connected(_on_name_lookup):
			_leaderboard.name_lookup.connect(_on_name_lookup)
		if _leaderboard.has_signal("refused_score") and not _leaderboard.refused_score.is_connected(_on_refused_score):
			_leaderboard.refused_score.connect(_on_refused_score)
		if _leaderboard.has_signal("submit_attempted") and not _leaderboard.submit_attempted.is_connected(_on_submit_attempted):
			_leaderboard.submit_attempted.connect(_on_submit_attempted)
	if _not_you != null:
		_not_you.focus_mode = Control.FOCUS_ALL
		_not_you.pressed.connect(_on_not_you_pressed)
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
	if _welcome != null:
		_welcome.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_style_button(_restart_button, theme_node)
	_style_button(_menu_button, theme_node)
	_style_button(_save_button, theme_node)
	_style_button(_skip_button, theme_node)
	_style_button(_yes, theme_node)
	_style_button(_no, theme_node)
	_style_button(_not_you, theme_node)
	if _saved_as != null:
		_saved_as.add_theme_color_override("font_color", theme_node.color("glow_gold"))
		_saved_as.autowrap_mode = TextServer.AUTOWRAP_OFF
		_saved_as.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_saved_as.clip_text = true
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
	_posted_final = false
	_screen_token = -1
	_pending_refusal = -1
	_confirming = false
	_lookup_pending = false
	_pending_lookup = -1
	_opened_with_name = false
	_game_serial += 1
	_blur_commit_queued = false
	_skip_holding = false
	_suppress_blur_commit = false
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
	# Leaderboard connects first, so its submit (and submit_attempted) has
	# usually already snapshotted the posting id. Keep that snapshot; do not
	# re-read Profile, which may already be someone else.
	var keep_bound := _leaderboard != null and _bound_token >= 0 and int(_leaderboard._game_over_submit_token) == _bound_token
	if not keep_bound:
		_clear_bound()
	_reveal_bound_save()
	# Leaderboard may have handled this signal already, or it may run next.
	# Both orders have to record this game's token before a late 409.
	_apply_game_over_token()
	_apply_game_over_token.call_deferred()
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
	_clear_bound()
	_hide_player_save()


func _on_board_updated(entries: Array, _total_players: int) -> void:
	if not visible:
		return
	_offline_label.visible = false
	_render_list(entries)


func _on_submitted(result: Dictionary) -> void:
	_last_submit = result
	_offline_label.visible = false
	_your_rank_label.text = _format_rank_line(result)
	if visible and not _invite_open:
		_show_saved_line(result)
	_maybe_upgrade_celebration(result)


func _on_submit_attempted(token: int, _attempt: int) -> void:
	# Leaderboard emits this for every attempt, including a delayed retry of
	# an earlier game. submitted only fires for the latest token, so adopting
	# an older token would replace "SAVED AS" and hide "Not you?" for good.
	if _leaderboard != null and token != int(_leaderboard._submit_token):
		return
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	var player_name := String(profile.player_name)
	var player_id := String(profile.player_id)
	if player_name.is_empty() or player_id.is_empty():
		return
	_bound_token = token
	_bound_id = player_id
	_bound_name = player_name
	if visible and not _invite_open:
		_show_saving_line()


func _on_offline(reason: String) -> void:
	if not visible:
		return
	# The invite is the message for a refused current id. A 409 that is
	# not name_taken still uses today's line.
	if _invite_open and _identity_unconfirmed() and reason == "http_409":
		_offline_label.visible = false
		return
	# A failed save has no rank yet, so drop "SAVING AS". A score that already
	# landed keeps "SAVED AS"; the failure still uses today's offline line.
	if _last_submit.is_empty():
		_hide_player_save()
	_offline_label.text = _offline_line(reason)
	_offline_label.visible = true


func _offline_line(reason: String) -> String:
	if _leaderboard != null and _leaderboard.has_method("offline_line"):
		return String(_leaderboard.offline_line(reason))
	return "Leaderboard offline"


func _reset_leaderboard_ui() -> void:
	_last_submit = {}
	_your_rank_label.text = ""
	_offline_label.text = "Leaderboard offline"
	_offline_label.visible = false
	_hide_player_save()
	_clear_list()


func _clear_bound() -> void:
	_bound_token = -1
	_bound_id = ""
	_bound_name = ""


func _hide_player_save() -> void:
	if _saved_as != null:
		_saved_as.text = ""
		_saved_as.visible = false
	if _not_you != null:
		_not_you.visible = false


func _reveal_bound_save() -> void:
	if _invite_open or _bound_name.is_empty():
		_hide_player_save()
		return
	if not _last_submit.is_empty():
		_show_saved_line(_last_submit)
		return
	if _bound_matches_inflight():
		_show_saving_line()


func _bound_matches_inflight() -> bool:
	if _leaderboard == null or _bound_token < 0:
		return false
	if int(_leaderboard._game_over_submit_token) != _bound_token:
		return false
	var state: Dictionary = _leaderboard._submit_state.get(_bound_token, {})
	if state.is_empty():
		return false
	if bool(_leaderboard._submitted_tokens.get(_bound_token, false)):
		return false
	return bool(state.get("in_flight", false)) or bool(state.get("retry_pending", false))


func _show_saving_line() -> void:
	if _saved_as == null or _bound_name.is_empty() or _invite_open:
		return
	_saved_as.text = "SAVING AS %s…" % _bound_name.to_upper()
	_saved_as.visible = true
	if _not_you != null:
		_not_you.visible = false


func _show_saved_line(result: Dictionary) -> void:
	if _saved_as == null or _invite_open:
		_hide_player_save()
		return
	var name := _name_for_posted_id()
	if name.is_empty():
		_hide_player_save()
		return
	var rank := int(result.get("rank", 0))
	var total := int(result.get("total_players", 0))
	_saved_as.text = "SAVED AS %s · %s OF %d" % [name.to_upper(), _ordinal(rank), total]
	_saved_as.visible = true
	if _not_you != null:
		_not_you.visible = true


## The id appended to score_post_ids is the one in the POST body. The name
## snapshotted for that same id is what we show — not Profile's current name.
func _name_for_posted_id() -> String:
	if _bound_name.is_empty() or _leaderboard == null:
		return ""
	var ids: Array = _leaderboard.score_post_ids
	if ids.is_empty():
		return ""
	if String(ids[ids.size() - 1]) != _bound_id:
		return ""
	return _bound_name


func _ordinal(n: int) -> String:
	var teen := n % 100
	if teen >= 11 and teen <= 13:
		return "%dTH" % n
	match n % 10:
		1:
			return "%dST" % n
		2:
			return "%dND" % n
		3:
			return "%dRD" % n
		_:
			return "%dTH" % n


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


func _identity_unconfirmed() -> bool:
	return _leaderboard != null and bool(_leaderboard.get("identity_unconfirmed"))


func _apply_game_over_token() -> void:
	if _leaderboard == null:
		return
	var epoch := int(_leaderboard._game_over_epoch)
	if epoch <= _applied_epoch:
		return
	_applied_epoch = epoch
	_screen_token = int(_leaderboard._game_over_submit_token)
	_open_refused_invite()


func _on_refused_score(token: int) -> void:
	_pending_refusal = token
	_open_refused_invite()


func _open_refused_invite() -> void:
	if _pending_refusal < 0 or not visible:
		return
	if _screen_token < 0 or _pending_refusal != _screen_token:
		return
	if _declined or _committed:
		_pending_refusal = -1
		return
	_pending_refusal = -1
	if _offline_label != null:
		_offline_label.visible = false
	if not _invite_open:
		_sync_name_invite()


func _sync_name_invite() -> void:
	var profile := get_node_or_null("/root/Profile")
	var saved := ""
	if profile != null:
		saved = String(profile.player_name)
	# Unnamed, and a dead id that still remembers its last player (D-058).
	if saved.is_empty() or _identity_unconfirmed():
		_open_invite(saved)
	else:
		_hide_invite()


func _open_invite(saved: String) -> void:
	_invite_open = true
	_confirming = false
	_lookup_pending = false
	_pending_lookup = -1
	# A claim already in flight (this overlay, or the title) must keep its
	# generation. Clearing it here adopted the name and dropped the score.
	if not _claim_is_current():
		_resolve_pending = false
		_pending_gen = -1
		_pending_score = 0
		_pending_serial = -1
	_claim_started_here = false
	_opened_with_name = not saved.is_empty()
	_name_edit.text = saved
	if _name_prompt != null:
		_name_prompt.text = _NAME_PROMPT
	_hide_player_save()
	_show_edit_row()
	_place_list(true)


func _hide_invite() -> void:
	_invite_open = false
	_confirming = false
	_lookup_pending = false
	if _name_prompt != null:
		_name_prompt.visible = false
	if _name_edit != null:
		_name_edit.visible = false
	if _save_button != null:
		_save_button.visible = false
	if _skip_button != null:
		_skip_button.visible = false
	if _welcome != null:
		_welcome.visible = false
	if _yes != null:
		_yes.visible = false
		_yes.disabled = false
	if _no != null:
		_no.visible = false
		_no.disabled = false
	_place_list(false)
	if visible:
		_reveal_bound_save()


func _show_edit_row() -> void:
	_confirming = false
	# Welcome sets this so hiding the field cannot commit. If the field was
	# already unfocused, that hide never blurs, and the flag would swallow
	# the next leave. A blur already queued still consumes the flag itself.
	if not _skip_holding and not _blur_commit_queued:
		_suppress_blur_commit = false
	if _welcome != null:
		_welcome.visible = false
	if _yes != null:
		_yes.visible = false
		_yes.disabled = false
	if _no != null:
		_no.visible = false
		_no.disabled = false
	if _name_prompt != null:
		_name_prompt.visible = true
	if _name_edit != null:
		_name_edit.visible = true
	if _save_button != null:
		_save_button.visible = true
	if _skip_button != null:
		_skip_button.visible = true
	_sync_save_enabled()


func _show_welcome(display: String) -> void:
	# Set before hiding the field, so the blur that hiding causes cannot commit.
	_confirming = true
	_suppress_blur_commit = true
	if _name_prompt != null:
		_name_prompt.visible = false
	if _name_edit != null:
		_name_edit.visible = false
	if _save_button != null:
		_save_button.visible = false
	if _skip_button != null:
		_skip_button.visible = false
	if _welcome != null:
		_welcome.text = _WELCOME_FMT % display
		_welcome.visible = true
	if _yes != null:
		_yes.disabled = false
		_yes.visible = true
	if _no != null:
		_no.disabled = false
		_no.visible = true
	_release_name_focus()


func _sync_save_enabled() -> void:
	if _save_button == null or _name_edit == null:
		return
	_save_button.disabled = _name_edit.text.strip_edges().is_empty()


func _on_name_text_changed(_text: String) -> void:
	_sync_save_enabled()


func _matches_last_player(raw: String) -> bool:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return false
	var saved := String(profile.player_name)
	if saved.is_empty():
		return false
	if not profile.has_method("_name_key") or not profile.has_method("_sanitize_name"):
		return false
	var typed_key := String(profile._name_key(profile._sanitize_name(raw)))
	var saved_key := String(profile._name_key(saved))
	return not typed_key.is_empty() and typed_key == saved_key


func _place_list(invite_open: bool) -> void:
	if _leaderboard_list == null:
		return
	if invite_open:
		_leaderboard_list.offset_top = 700.0
		_leaderboard_list.offset_bottom = 1120.0
	else:
		_leaderboard_list.offset_top = 220.0
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
	var suppress := _suppress_blur_commit or _skip_holding
	if not _skip_holding:
		_suppress_blur_commit = false
	if _declined or _committed or not _invite_open or suppress or _confirming or _lookup_pending:
		return
	var viewport := get_viewport()
	if viewport != null and viewport.gui_get_hovered_control() == _skip_button:
		return
	_commit_pending_name()


func _commit_pending_name() -> void:
	if _resolve_pending and not _claim_is_current():
		_resolve_pending = false
	if _committed or _declined or not _invite_open or _resolve_pending or _lookup_pending or _confirming:
		return
	if _name_edit == null:
		return
	# A claim this invite did not start can land on an unnamed invite and
	# leave a name behind. An invite that opened already named (the dead id's
	# last player) must not take that path: posting now would spend the run
	# on the dead id.
	if not _opened_with_name:
		var profile := get_node_or_null("/root/Profile")
		if profile != null and not String(profile.player_name).is_empty():
			_committed = true
			_hide_invite()
			_release_name_focus()
			_submit_score(_final_score)
			return
	var raw := _name_edit.text
	if raw.strip_edges().is_empty():
		return
	if _leaderboard == null or not _leaderboard.has_method("resolve_name"):
		_show_unresolved("unreachable")
		return
	# Same name as this device's last player, compared the way the server
	# does (sanitised, then Profile._name_key). No extra question.
	if _matches_last_player(raw) or _lookup_skipped():
		_start_resolve(raw)
		return
	_start_lookup(raw)


func _lookup_skipped() -> bool:
	return _leaderboard != null and _leaderboard.has_method("_profile_http_skipped") and bool(_leaderboard._profile_http_skipped())


func _start_lookup(raw: String) -> void:
	if _leaderboard == null or not _leaderboard.has_method("lookup_name"):
		_start_resolve(raw)
		return
	_lookup_pending = true
	_pending_lookup = int(_leaderboard.lookup_name(raw))


func _on_name_lookup(generation: int, info: Dictionary) -> void:
	if generation != _pending_lookup:
		return
	if not _lookup_pending:
		return
	_lookup_pending = false
	if _declined or _committed or not _invite_open or _confirming:
		return
	var queried := String(info.get("queried", ""))
	if _name_edit == null or _name_edit.text != queried:
		return
	if bool(info.get("answered", false)) and bool(info.get("held", false)):
		var display := String(info.get("display", "")).strip_edges()
		if display.is_empty():
			display = queried.strip_edges()
		_show_welcome(display)
		return
	_start_resolve(queried)


func _start_resolve(raw: String) -> void:
	if _resolve_pending:
		return
	if raw.strip_edges().is_empty():
		return
	if _leaderboard == null or not _leaderboard.has_method("resolve_name"):
		_show_unresolved("unreachable")
		return
	_resolve_pending = true
	_claim_started_here = true
	_pending_score = _final_score
	_pending_serial = _game_serial
	_posted_pending = false
	_pending_gen = int(_leaderboard.resolve_name(raw))


func _on_yes_pressed() -> void:
	if not _confirming or _resolve_pending:
		return
	var raw := _name_edit.text if _name_edit != null else ""
	_start_resolve(raw)


func _on_no_pressed() -> void:
	if not _confirming or _resolve_pending:
		return
	_show_edit_row()


func _on_name_resolved(generation: int, ok: bool, info: Dictionary) -> void:
	var ours := _pending_gen >= 0 and generation == _pending_gen
	if not ours:
		# Title, or a claim whose invite was replaced. Leaderboard already
		# adopted a success. This game still owes its score.
		if ok and not _declined:
			_post_current_score()
		return
	_resolve_pending = false
	_claim_started_here = false
	if not ok:
		if not _declined:
			_show_edit_row()
			_show_unresolved(String(info.get("reason", "")))
		return
	if not _declined:
		if _pending_serial == _game_serial:
			_submit_pending()
			_posted_final = true
		else:
			_submit_pending()
			_post_current_score()
		if _invite_open:
			_committed = true
			_hide_invite()
			_release_name_focus()
		return
	# Not now discarded this game. An earlier game's claim still posts.
	if _pending_serial != _game_serial:
		_submit_pending()


func _show_unresolved(reason: String) -> void:
	# They already left this game over. Do not bring the prompt back, and do
	# not invent an identity for the name that never resolved.
	if not _invite_open:
		return
	if _name_prompt != null:
		_name_prompt.text = _offline_line(reason)


func _on_save_pressed() -> void:
	# Assigning LineEdit.text does not emit text_changed, so a press re-reads
	# the field. Blank after trim stays disabled and does nothing.
	_sync_save_enabled()
	if _save_button != null and _save_button.disabled:
		return
	_commit_pending_name()


func _on_skip_down() -> void:
	_skip_holding = true
	_suppress_blur_commit = true


func _on_skip_up() -> void:
	_skip_holding = false
	if not _blur_commit_queued:
		_suppress_blur_commit = false


func _on_skip_pressed() -> void:
	_declined = true
	_skip_holding = false
	_suppress_blur_commit = false
	if _claim_started_here and _claim_is_current() and _leaderboard != null and _leaderboard.has_method("retire_name_resolve"):
		_leaderboard.retire_name_resolve()
		_resolve_pending = false
		_claim_started_here = false
	_hide_invite()
	_release_name_focus()


func _claim_is_current() -> bool:
	if not _resolve_pending:
		return false
	if _leaderboard == null:
		return false
	return int(_leaderboard._resolve_gen) == _pending_gen


func _post_current_score() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null or String(profile.player_name).is_empty():
		return
	if _final_score <= 0 or _posted_final or _declined:
		return
	_committed = true
	if _invite_open:
		_hide_invite()
		_release_name_focus()
	_submit_score(_final_score)


func _submit_pending() -> void:
	if _posted_pending or _pending_score <= 0:
		return
	if _leaderboard == null or not _leaderboard.has_method("submit"):
		return
	_posted_pending = true
	_leaderboard.submit(_pending_score)


func _submit_score(score: int) -> void:
	if score <= 0 or score != _final_score or _posted_final:
		return
	if _leaderboard == null or not _leaderboard.has_method("submit"):
		return
	_posted_final = true
	_leaderboard.submit(score)


func _release_name_focus() -> void:
	if _name_edit != null and is_instance_valid(_name_edit) and _name_edit.has_focus():
		_name_edit.release_focus()
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_release_focus()


func _on_not_you_pressed() -> void:
	# The score already posted stays on the id it was posted to. This only
	# opens the title rename so the next game can be someone else.
	var main := get_parent()
	if main != null and main.has_method("return_to_menu"):
		main.return_to_menu()
	if main == null:
		return
	var title := main.get_node_or_null("Title")
	if title != null and title.has_method("open_rename"):
		title.open_rename()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _not_you == null or not _not_you.visible:
		return
	if event.is_action_pressed("change_name"):
		_on_not_you_pressed()
		get_viewport().set_input_as_handled()


func _on_restart_pressed() -> void:
	_game.restart()


func _on_menu_pressed() -> void:
	var main := get_parent()
	if main != null and main.has_method("return_to_menu"):
		main.return_to_menu()
