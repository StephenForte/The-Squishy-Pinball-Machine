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
	var theme_node := get_node("/root/Theme")
	theme_node.palette_changed.connect(_apply_theme)
	_apply_theme(theme_node.palette_id)


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
	_restart_button.add_theme_color_override("font_color", theme_node.color("text_on_color"))
	_restart_button.add_theme_color_override("font_hover_color", theme_node.color("object_white"))


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
