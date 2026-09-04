extends CanvasLayer

var _game: Node

@onready var _score_label: Label = $ScoreLabel
@onready var _balls_label: Label = $BallsLabel
@onready var _high_score_label: Label = $HighScoreLabel
@onready var _streak_label: Label = $StreakLabel


func _ready() -> void:
	_game = get_node("/root/Game")
	_game.score_changed.connect(_on_score_changed)
	_game.ball_count_changed.connect(_on_ball_count_changed)
	_game.game_over.connect(_on_game_over)
	_game.game_restarted.connect(_on_game_restarted)
	_game.streak_changed.connect(_on_streak_changed)
	var theme_node := get_node("/root/Theme")
	theme_node.palette_changed.connect(_apply_theme)
	_apply_theme(theme_node.palette_id)
	_sync_from_game()


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node("/root/Theme")
	var primary: Color = theme_node.color("text_primary")
	_score_label.add_theme_color_override("font_color", primary)
	_balls_label.add_theme_color_override("font_color", primary)
	_high_score_label.add_theme_color_override("font_color", primary)
	_streak_label.add_theme_color_override("font_color", theme_node.color("glow_gold"))


func _on_score_changed(new_score: int) -> void:
	_set_score(new_score)


func _on_ball_count_changed(balls_left: int) -> void:
	_set_balls(balls_left)


func _on_game_over(_final_score: int, _is_high_score: bool) -> void:
	_set_high(_game.high_score)


func _on_game_restarted() -> void:
	_sync_from_game()


func _on_streak_changed(streak: int) -> void:
	_set_streak(streak)


func _sync_from_game() -> void:
	_set_score(_game.score)
	_set_balls(_game.balls_left)
	_set_high(_game.high_score)
	_set_streak(int(_game.streak))


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
