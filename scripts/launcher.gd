extends Node2D

signal launched(impulse: float)

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


## Body launch() would pass to _try_launch, or null when that search finds
## nothing it can fire. Sensor overlap first, then the x/y fallback. The
## fallback stops on the first in-lane body, matching launch().
func lane_ball() -> Node:
	var sensor := get_node_or_null("LaneSensor") as Area2D
	if sensor != null:
		for body in sensor.get_overlapping_bodies():
			if _can_launch(body):
				return body
	var tree := get_tree()
	if tree == null:
		return null
	for body in tree.get_nodes_in_group("ball"):
		if body is Node2D:
			var pos: Vector2 = (body as Node2D).global_position
			if pos.x > _LANE_MIN_X and pos.y > _LANE_MIN_Y:
				if _can_launch(body):
					return body
				return null
	return null


func _can_launch(body: Node) -> bool:
	return body.is_in_group("ball") and body.has_method("launch")


func _try_launch(body: Node, impulse: float) -> bool:
	if _can_launch(body):
		body.launch(impulse)
		launched.emit(impulse)
		return true
	return false
