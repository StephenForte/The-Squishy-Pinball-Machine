extends CanvasLayer

var _game: Node

@onready var _score_label: Label = $ScoreLabel
@onready var _balls_label: Label = $BallsLabel
@onready var _high_score_label: Label = $HighScoreLabel


func _ready() -> void:
	_game = get_node("/root/Game")
	_game.score_changed.connect(_on_score_changed)
	_game.ball_count_changed.connect(_on_ball_count_changed)
	_game.game_over.connect(_on_game_over)
	_game.game_restarted.connect(_on_game_restarted)
	_sync_from_game()


func _on_score_changed(new_score: int) -> void:
	_set_score(new_score)


func _on_ball_count_changed(balls_left: int) -> void:
	_set_balls(balls_left)


func _on_game_over(_final_score: int, _is_high_score: bool) -> void:
	_set_high(_game.high_score)


func _on_game_restarted() -> void:
	_sync_from_game()


func _sync_from_game() -> void:
	_set_score(_game.score)
	_set_balls(_game.balls_left)
	_set_high(_game.high_score)


func _set_score(value: int) -> void:
	_score_label.text = "SCORE  %d" % value


func _set_balls(value: int) -> void:
	_balls_label.text = "BALLS  %d" % value


func _set_high(value: int) -> void:
	_high_score_label.text = "HIGH  %d" % value
