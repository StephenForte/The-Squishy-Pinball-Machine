extends CanvasLayer

var _dismissed := false


func _ready() -> void:
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if _dismissed:
		return
	if event.is_action_pressed("launch_ball"):
		_dismissed = true
		visible = false
