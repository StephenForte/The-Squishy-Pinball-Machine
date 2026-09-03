extends StaticBody2D

## Stand-up target. First unlit hit scores 500 and lights; later hits score
## nothing (D-013). Detection is this node's Area2D, not the ball scene.
signal hit

const SCORE := 500
const COOLDOWN_SEC := 0.12
const COLOR_UNLIT := Color(0.42, 0.48, 0.58, 1)
const COLOR_LIT := Color(0.95, 0.82, 0.28, 1)

var lit: bool = false
var _cooling: bool = false


func _ready() -> void:
	add_to_group("targets")
	_update_visual()
	var sensor: Area2D = $Sensor
	sensor.body_entered.connect(_on_sensor_body_entered)


func reset() -> void:
	lit = false
	_cooling = false
	_update_visual()


func _on_sensor_body_entered(body: Node2D) -> void:
	if not body.is_in_group("ball"):
		return
	if _cooling:
		return
	_cooling = true
	get_tree().create_timer(COOLDOWN_SEC).timeout.connect(_end_cooldown, CONNECT_ONE_SHOT)
	if lit:
		return
	lit = true
	_update_visual()
	get_node("/root/Game").add_score(SCORE)
	hit.emit()


func _end_cooldown() -> void:
	_cooling = false


func _update_visual() -> void:
	var visual := get_node_or_null("Visual") as Polygon2D
	if visual != null:
		visual.color = COLOR_LIT if lit else COLOR_UNLIT
