extends Node2D

## Display-only: camera-offset shake and placeholder fireworks.
## Never moves Table or any physics body (D-018).

const SHAKE_DURATION := 0.26
const SHAKE_AMPLITUDE := 9.0

@onready var _camera: Camera2D = $Camera2D
@onready var _fireworks: CPUParticles2D = $Fireworks

var _shake_left: float = 0.0


func _ready() -> void:
	_camera.enabled = true
	_camera.make_current()
	_camera.offset = Vector2.ZERO
	_fireworks.emitting = false
	var game: Node = get_node("/root/Game")
	game.big_score_reached.connect(_on_big_score_reached)
	game.game_restarted.connect(_on_game_restarted)
	for bumper in get_tree().get_nodes_in_group("bumpers"):
		if bumper.has_signal("hit"):
			bumper.hit.connect(_on_bumper_hit)


func shake() -> void:
	_shake_left = SHAKE_DURATION
	_camera.offset = Vector2(SHAKE_AMPLITUDE, 0.0)


func _process(delta: float) -> void:
	if _shake_left <= 0.0:
		return
	_shake_left -= delta
	if _shake_left <= 0.0:
		_camera.offset = Vector2.ZERO
		return
	var mag := SHAKE_AMPLITUDE * (_shake_left / SHAKE_DURATION)
	_camera.offset = Vector2(randf_range(-mag, mag), randf_range(-mag, mag))


func _on_bumper_hit() -> void:
	shake()


func _on_big_score_reached(_score: int) -> void:
	_fireworks.restart()


func _on_game_restarted() -> void:
	_shake_left = 0.0
	_camera.offset = Vector2.ZERO
	_fireworks.emitting = false
