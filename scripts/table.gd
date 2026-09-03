extends Node2D

signal ball_drained

const BALL_SCENE := preload("res://scenes/ball.tscn")
const BALL_SPAWN := Vector2(666, 1219)
const RESPAWN_DELAY := 1.0

var _respawn_pending := false


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
	# TEMP: T4 replaces with Game.on_ball_drained()
	_schedule_respawn()


func _schedule_respawn() -> void:
	if _respawn_pending:
		return
	_respawn_pending = true
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_on_respawn_timer, CONNECT_ONE_SHOT)


func _on_respawn_timer() -> void:
	_respawn_pending = false
	spawn_ball()
