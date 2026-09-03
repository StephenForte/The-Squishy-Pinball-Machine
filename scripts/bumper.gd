extends StaticBody2D

## Pop bumper: one score + kick per visit. Detection is this node's Area2D,
## not the ball scene (D-013). Debounce keeps a jittering overlap from
## firing add_score more than once.
@export var kick_impulse: float = 750.0
@export var radius: float = 28.0

const SCORE := 100
const COOLDOWN_SEC := 0.18

var _cooling: bool = false
var _scored_bodies: Dictionary = {}


func _ready() -> void:
	add_to_group("bumpers")
	var sensor: Area2D = $Sensor
	sensor.body_entered.connect(_on_sensor_body_entered)
	sensor.body_exited.connect(_on_sensor_body_exited)


func _on_sensor_body_entered(body: Node2D) -> void:
	if not body.is_in_group("ball"):
		return
	if _cooling:
		return
	if _scored_bodies.has(body):
		return
	_scored_bodies[body] = true
	_cooling = true
	get_node("/root/Game").add_score(SCORE)
	_kick(body)
	get_tree().create_timer(COOLDOWN_SEC).timeout.connect(_end_cooldown, CONNECT_ONE_SHOT)


func _on_sensor_body_exited(body: Node2D) -> void:
	_scored_bodies.erase(body)


func _end_cooldown() -> void:
	_cooling = false


func _kick(body: Node2D) -> void:
	if not body is RigidBody2D:
		return
	var ball := body as RigidBody2D
	var away := ball.global_position - global_position
	if away.length_squared() < 0.0001:
		away = Vector2.UP
	ball.sleeping = false
	ball.apply_central_impulse(away.normalized() * kick_impulse)
