extends CanvasLayer

var _dismissed := false


func _ready() -> void:
	visible = true
	var theme_node := get_node("/root/Theme")
	theme_node.palette_changed.connect(_apply_theme)
	_apply_theme(theme_node.palette_id)


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node("/root/Theme")
	var primary: Color = theme_node.color("text_primary")
	var shade := get_node_or_null("Shade") as ColorRect
	if shade != null:
		var bg: Color = theme_node.color("background")
		bg.a = 0.78
		shade.color = bg
	$TableNameLabel.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	$ControlsLabel.add_theme_color_override("font_color", primary)
	$PlayHintLabel.add_theme_color_override("font_color", primary)


func _unhandled_input(event: InputEvent) -> void:
	if _dismissed:
		return
	if event.is_action_pressed("launch_ball"):
		_dismissed = true
		visible = false
