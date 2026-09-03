extends Node2D

var _respawn_generation: int = 0
var _game: Node


func _ready() -> void:
	_game = get_node("/root/Game")
	$Table.ball_drained.connect(_game.on_ball_drained)
	_game.ball_count_changed.connect(_on_ball_count_changed)
	_game.game_restarted.connect(_on_game_restarted)
	_game.game_over.connect(_on_game_over)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_game.restart()
		get_viewport().set_input_as_handled()


func _on_ball_count_changed(balls_left: int) -> void:
	if balls_left <= 0:
		return
	var generation := _respawn_generation
	get_tree().create_timer(1.0).timeout.connect(
		_spawn_if_current.bind(generation),
		CONNECT_ONE_SHOT
	)


func _spawn_if_current(generation: int) -> void:
	if generation != _respawn_generation:
		return
	if _game.state == _game.GAME_OVER:
		return
	$Table.spawn_ball()


func _on_game_restarted() -> void:
	_respawn_generation += 1
	for node in get_tree().get_nodes_in_group("ball"):
		if is_instance_valid(node):
			node.queue_free()
	$Table.spawn_ball()


func _on_game_over(final_score: int, is_high_score: bool) -> void:
	print("Main game_over final_score=%d is_high_score=%s" % [final_score, is_high_score])
