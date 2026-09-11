extends CanvasLayer

var _game: Node
var _leaderboard: Node
var _last_submit: Dictionary = {}
var _final_score: int = 0
var _is_high_score: bool = false

@onready var _celebration: Node = get_node_or_null("Celebration")
@onready var _final_score_label: Label = $FinalScoreLabel
@onready var _high_score_label: Label = $GameOverHighScoreLabel
@onready var _new_high_score_label: Label = $NewHighScoreLabel
@onready var _your_rank_label: Label = $YourRankLabel
@onready var _offline_label: Label = $OfflineLabel
@onready var _leaderboard_list: VBoxContainer = $LeaderboardList
@onready var _restart_button: Button = $RestartButton
@onready var _menu_button: Button = $MenuButton


func _ready() -> void:
	_game = get_node("/root/Game")
	_leaderboard = get_node_or_null("/root/Leaderboard")
	visible = false
	_new_high_score_label.visible = false
	_restart_button.focus_mode = Control.FOCUS_NONE
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.pressed.connect(_on_menu_pressed)
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
	_restart_button.add_theme_color_override("font_color", theme_node.color("text_on_color"))
	_restart_button.add_theme_color_override("font_hover_color", theme_node.color("object_white"))
	_menu_button.add_theme_color_override("font_color", theme_node.color("text_on_color"))
	_menu_button.add_theme_color_override("font_hover_color", theme_node.color("object_white"))
	_paint_list_theme()


func _on_game_over(final_score: int, is_high_score: bool) -> void:
	_final_score_label.text = "FINAL  %d" % final_score
	_high_score_label.text = "HIGH  %d" % _game.high_score
	_new_high_score_label.visible = is_high_score
	_reset_leaderboard_ui()
	if _leaderboard != null and (_leaderboard.last_entries as Array).size() > 0:
		_render_list(_leaderboard.last_entries)
	visible = true
	_final_score = final_score
	_is_high_score = is_high_score
	_play_celebration(_tier_for(final_score, is_high_score, 0))


func _on_game_restarted() -> void:
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


func _on_restart_pressed() -> void:
	_game.restart()


func _on_menu_pressed() -> void:
	var main := get_parent()
	if main != null and main.has_method("return_to_menu"):
		main.return_to_menu()
