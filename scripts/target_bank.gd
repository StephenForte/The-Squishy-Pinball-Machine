extends Node

## Owns the stand-up targets. Lighting every child scores the D-005 bonus,
## emits all_targets_hit once, then resets after 0.5 s. Restart clears them.
signal all_targets_hit

const BONUS := 2500
const RESET_DELAY_SEC := 0.5

var _bonus_pending: bool = false
var _reset_generation: int = 0


func _ready() -> void:
	get_node("/root/Game").game_restarted.connect(_on_game_restarted)
	for target in _targets():
		if not target.hit.is_connected(_on_target_hit):
			target.hit.connect(_on_target_hit)


func _on_target_hit() -> void:
	if _bonus_pending:
		return
	for target in _targets():
		if not bool(target.lit):
			return
	_bonus_pending = true
	get_node("/root/Game").add_score(BONUS)
	all_targets_hit.emit()
	var generation := _reset_generation
	get_tree().create_timer(RESET_DELAY_SEC).timeout.connect(
		_reset_if_current.bind(generation),
		CONNECT_ONE_SHOT
	)


func _on_game_restarted() -> void:
	_reset_generation += 1
	_bonus_pending = false
	reset_all()


func reset_all() -> void:
	for target in _targets():
		target.reset()


func _reset_if_current(generation: int) -> void:
	if generation != _reset_generation:
		return
	_bonus_pending = false
	reset_all()


func _targets() -> Array:
	var out: Array = []
	for child in get_children():
		if child.is_in_group("targets"):
			out.append(child)
	return out
