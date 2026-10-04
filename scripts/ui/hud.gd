extends CanvasLayer

var _game: Node

@onready var _score_label: Label = $ScoreLabel
@onready var _balls_label: Label = $BallsLabel
@onready var _high_score_label: Label = $HighScoreLabel
@onready var _streak_label: Label = $StreakLabel
@onready var _board_label: Label = $BoardLabel
@onready var _player_name_label: Label = $PlayerNameLabel


func _ready() -> void:
	_game = get_node("/root/Game")
	_game.score_changed.connect(_on_score_changed)
	_game.ball_count_changed.connect(_on_ball_count_changed)
	_game.game_over.connect(_on_game_over)
	_game.game_restarted.connect(_on_game_restarted)
	_game.streak_changed.connect(_on_streak_changed)
	if _game.has_signal("board_shifted"):
		_game.board_shifted.connect(_on_board_shifted)
	if _game.has_signal("high_score_changed"):
		_game.high_score_changed.connect(_on_high_score_changed)
	var profile := get_node_or_null("/root/Profile")
	if profile != null and profile.has_signal("name_changed"):
		if not profile.name_changed.is_connected(_on_name_changed):
			profile.name_changed.connect(_on_name_changed)
	var theme_node := get_node("/root/Theme")
	theme_node.palette_changed.connect(_apply_theme)
	_apply_theme(theme_node.palette_id)
	_sync_from_game()
	_sync_player_name()


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node("/root/Theme")
	var primary: Color = theme_node.color("text_primary")
	_score_label.add_theme_color_override("font_color", primary)
	_balls_label.add_theme_color_override("font_color", primary)
	_high_score_label.add_theme_color_override("font_color", primary)
	_streak_label.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	if _board_label != null:
		_board_label.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	if _player_name_label != null:
		_player_name_label.add_theme_color_override("font_color", primary)
		_player_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_player_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_player_name_label.clip_text = true


func _on_score_changed(new_score: int) -> void:
	_set_score(new_score)


func _on_ball_count_changed(balls_left: int) -> void:
	_set_balls(balls_left)


func _on_game_over(_final_score: int, _is_high_score: bool) -> void:
	_set_high(_game.high_score)


func _on_game_restarted() -> void:
	_sync_from_game()
	if _board_label != null:
		_board_label.visible = false


func _on_streak_changed(streak: int) -> void:
	_set_streak(streak)


func _on_board_shifted(wave: int, bonus_count: int, bonus_points: int) -> void:
	if _board_label == null:
		return
	if wave <= 0 or bonus_count <= 0:
		_board_label.visible = false
		return
	_board_label.visible = true
	_board_label.text = "LAYOUT %d  ·  BONUS ×%d  %d" % [wave, bonus_count, bonus_points]


func _on_name_changed(_name: String) -> void:
	_set_high(_game.high_score)
	_sync_player_name()


func _on_high_score_changed(player_id: String, value: int) -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if String(profile.player_id) != player_id:
		return
	_set_high(value)


func _sync_from_game() -> void:
	_set_score(_game.score)
	_set_balls(_game.balls_left)
	_set_high(_game.high_score)
	_set_streak(int(_game.streak))
	_sync_player_name()


func _sync_player_name() -> void:
	if _player_name_label == null:
		return
	var profile := get_node_or_null("/root/Profile")
	var player_name := ""
	if profile != null:
		player_name = String(profile.player_name)
	if player_name.is_empty():
		_player_name_label.text = ""
		_player_name_label.visible = false
		return
	_player_name_label.text = player_name
	_player_name_label.visible = true


func _set_score(value: int) -> void:
	_score_label.text = "SCORE  %d" % value


func _set_balls(value: int) -> void:
	_balls_label.text = "BALLS  %d" % value


func _set_high(value: int) -> void:
	_high_score_label.text = "HIGH  %d" % value


func _set_streak(streak: int) -> void:
	if streak >= 2:
		_streak_label.text = "x%d" % mini(streak, 5)
		_streak_label.visible = true
	else:
		_streak_label.visible = false
