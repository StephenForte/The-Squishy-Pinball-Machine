extends Node2D

signal ball_drained

const BALL_SCENE := preload("res://scenes/ball.tscn")
const BALL_SPAWN := Vector2(666, 1219)


func _ready() -> void:
	$Drain.body_entered.connect(_on_drain_body_entered)
	spawn_ball()


func spawn_ball() -> void:
	var ball := BALL_SCENE.instantiate() as RigidBody2D
	ball.freeze = false
	ball.position = BALL_SPAWN
	add_child(ball)
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	PhysicsServer2D.body_set_state(
		ball.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, BALL_SPAWN)
	)


func _on_drain_body_entered(body: Node2D) -> void:
	if not body.is_in_group("ball"):
		return
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	body.queue_free()
	ball_drained.emit()
