extends CanvasLayer

var _game: Node

@onready var _final_score_label: Label = $FinalScoreLabel
@onready var _high_score_label: Label = $GameOverHighScoreLabel
@onready var _new_high_score_label: Label = $NewHighScoreLabel
@onready var _restart_button: Button = $RestartButton


func _ready() -> void:
	_game = get_node("/root/Game")
	visible = false
	_new_high_score_label.visible = false
	_restart_button.focus_mode = Control.FOCUS_NONE
	_restart_button.pressed.connect(_on_restart_pressed)
	_game.game_over.connect(_on_game_over)
	_game.game_restarted.connect(_on_game_restarted)


func _on_game_over(final_score: int, is_high_score: bool) -> void:
	_final_score_label.text = "FINAL  %d" % final_score
	_high_score_label.text = "HIGH  %d" % _game.high_score
	_new_high_score_label.visible = is_high_score
	visible = true


func _on_game_restarted() -> void:
	visible = false
	_new_high_score_label.visible = false


func _on_restart_pressed() -> void:
	_game.restart()
