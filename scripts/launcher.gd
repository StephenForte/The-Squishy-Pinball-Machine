extends Node2D

const LAUNCH_IMPULSE := 1850.0
const LAUNCH_IMPULSE_MIN := 1100.0

const _LANE_MIN_X := 620.0
const _LANE_MIN_Y := 1100.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("launch_ball"):
		launch()


func launch(impulse: float = LAUNCH_IMPULSE) -> void:
	var sensor: Area2D = $LaneSensor
	for body in sensor.get_overlapping_bodies():
		if _try_launch(body, impulse):
			return
	for body in get_tree().get_nodes_in_group("ball"):
		if body is Node2D:
			var pos: Vector2 = (body as Node2D).global_position
			if pos.x > _LANE_MIN_X and pos.y > _LANE_MIN_Y:
				_try_launch(body, impulse)
				return


func _try_launch(body: Node, impulse: float) -> bool:
	if body.is_in_group("ball") and body.has_method("launch"):
		body.launch(impulse)
		return true
	return false
