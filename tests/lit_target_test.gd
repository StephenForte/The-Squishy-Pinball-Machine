extends SceneTree

## D-061: an unlit stand-up target still scores 500 and lights. Every later
## hit scores a flat 100, emits hit, and never completes the bank again.

const COOLDOWN_SEC := 0.13
const RESET_WAIT_SEC := 0.45

var _game: Node
var _table: Node2D
var _bank: Node
var _ball: Node2D
var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("LIT_TARGET start")
	var main := load("res://scenes/main.tscn") as PackedScene
	if main == null:
		_fail("could not load scenes/main.tscn")
		return
	if change_scene_to_packed(main) != OK:
		_fail("could not change to main.tscn")
		return
	await process_frame
	await physics_frame
	_game = root.get_node_or_null("/root/Game")
	if _game == null:
		_fail("Game autoload missing")
		return
	_table = current_scene.get_node_or_null("Table") as Node2D
	if _table == null:
		_fail("Table missing on main.tscn")
		return
	_bank = _table.get_node_or_null("TargetBank")
	if _bank == null:
		_fail("TargetBank missing")
		return
	if not await _case_1_unlit_then_lit_scores():
		return
	if not await _case_2_cooldown_scores_once():
		return
	if not await _case_3_bank_once_then_rehits():
		return
	if not await _case_4_restart():
		return

	print("LIT_TARGET PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_unlit_then_lit_scores() -> bool:
	if not await _fresh():
		return false
	var target: Node = _targets()[0]
	var hits: Array = [0]
	var on_hit := func() -> void:
		hits[0] += 1
	target.hit.connect(on_hit)
	var before: int = _game.score
	_strike(target)
	if _game.score - before != 500:
		target.hit.disconnect(on_hit)
		return _fail("case 1: unlit hit +%d, expected +500" % (_game.score - before))
	if not bool(target.lit):
		target.hit.disconnect(on_hit)
		return _fail("case 1: target not lit after first hit")
	if hits[0] != 1:
		target.hit.disconnect(on_hit)
		return _fail("case 1: unlit hit emitted %d, expected 1" % hits[0])
	await create_timer(COOLDOWN_SEC).timeout
	var mid: int = _game.score
	_strike(target)
	if _game.score - mid != 100:
		target.hit.disconnect(on_hit)
		return _fail("case 1: second hit +%d, expected +100" % (_game.score - mid))
	if int(_game.streak) != 0:
		target.hit.disconnect(on_hit)
		return _fail("case 1: lit hit changed streak to %d" % int(_game.streak))
	await create_timer(COOLDOWN_SEC).timeout
	var late: int = _game.score
	_strike(target)
	target.hit.disconnect(on_hit)
	if _game.score - late != 100:
		return _fail("case 1: third hit +%d, expected +100" % (_game.score - late))
	if hits[0] != 3:
		return _fail("case 1: hit emitted %d times, expected 3" % hits[0])
	if not bool(target.lit):
		return _fail("case 1: target went dark after re-hits")
	_cases_passed += 1
	print("LIT_TARGET case 1 pass")
	return true


func _case_2_cooldown_scores_once() -> bool:
	if not await _fresh():
		return false
	var target: Node = _targets()[0]
	var before: int = _game.score
	_strike(target)
	if _game.score - before != 500:
		return _fail("case 2: positive control +%d, expected +500" % (_game.score - before))
	var mid: int = _game.score
	_strike(target)
	if _game.score != mid:
		return _fail("case 2: in-cooldown hit +%d, expected 0" % (_game.score - mid))
	if not bool(target.lit):
		return _fail("case 2: cooldown hit cleared lit")
	_cases_passed += 1
	print("LIT_TARGET case 2 pass")
	return true


func _case_3_bank_once_then_rehits() -> bool:
	if not await _fresh():
		return false
	var targets := _targets()
	var bonus := [0]
	var on_bonus := func() -> void:
		bonus[0] += 1
	_bank.all_targets_hit.connect(on_bonus)
	var before: int = _game.score
	for target in targets:
		_strike(target)
	if bonus[0] != 1:
		_bank.all_targets_hit.disconnect(on_bonus)
		return _fail("case 3: bonus emitted %d on completion, expected 1" % bonus[0])
	if _game.score - before != 5000:
		_bank.all_targets_hit.disconnect(on_bonus)
		return _fail("case 3: completion +%d, expected +5000" % (_game.score - before))
	for target in targets:
		if not bool(target.lit):
			_bank.all_targets_hit.disconnect(on_bonus)
			return _fail("case 3: a target was unlit at completion")
	# 0.13 s clears the 0.12 s cooldown and is still inside the 0.5 s reset.
	await create_timer(COOLDOWN_SEC).timeout
	for target in targets:
		if not bool(target.lit):
			_bank.all_targets_hit.disconnect(on_bonus)
			return _fail("case 3: target reset before the re-hit window")
	var hits := [0]
	var on_hit := func() -> void:
		hits[0] += 1
	for target in targets:
		target.hit.connect(on_hit)
	var mid: int = _game.score
	for target in targets:
		var one: int = _game.score
		_strike(target)
		if _game.score - one != 100:
			_disconnect_hits(targets, on_hit)
			_bank.all_targets_hit.disconnect(on_bonus)
			return _fail("case 3: window re-hit +%d, expected +100" % (_game.score - one))
	for target in targets:
		target.hit.disconnect(on_hit)
	if _game.score - mid != 500:
		_bank.all_targets_hit.disconnect(on_bonus)
		return _fail("case 3: window re-hits +%d, expected +500" % (_game.score - mid))
	if hits[0] != 5:
		_bank.all_targets_hit.disconnect(on_bonus)
		return _fail("case 3: window re-hits emitted hit %d times, expected 5" % hits[0])
	if bonus[0] != 1:
		_bank.all_targets_hit.disconnect(on_bonus)
		return _fail("case 3: bonus emitted %d after window re-hits, expected 1" % bonus[0])
	await create_timer(RESET_WAIT_SEC).timeout
	await process_frame
	for target in targets:
		if bool(target.lit):
			_bank.all_targets_hit.disconnect(on_bonus)
			return _fail("case 3: target still lit after bank reset")
	if bonus[0] != 1:
		_bank.all_targets_hit.disconnect(on_bonus)
		return _fail("case 3: bonus emitted %d after reset, expected 1" % bonus[0])
	var after: int = _game.score
	_strike(targets[0])
	_bank.all_targets_hit.disconnect(on_bonus)
	if _game.score - after != 500:
		return _fail("case 3: post-reset hit +%d, expected +500" % (_game.score - after))
	if not bool(targets[0].lit):
		return _fail("case 3: post-reset hit did not light")
	if bonus[0] != 1:
		return _fail("case 3: post-reset hit emitted bonus %d, expected 1" % bonus[0])
	_cases_passed += 1
	print("LIT_TARGET case 3 pass")
	return true


func _case_4_restart() -> bool:
	if not await _fresh():
		return false
	var targets := _targets()
	_strike(targets[0])
	_strike(targets[1])
	await create_timer(COOLDOWN_SEC).timeout
	if not await _fresh():
		return false
	for target in _targets():
		if bool(target.lit):
			return _fail("case 4: target still lit after restart")
	if int(_game.score) != 0:
		return _fail("case 4: score %d after restart, expected 0" % int(_game.score))
	var before: int = _game.score
	_strike(_targets()[0])
	if _game.score - before != 500:
		return _fail("case 4: first hit after restart +%d, expected +500" % (_game.score - before))
	if not bool(_targets()[0].lit):
		return _fail("case 4: first hit after restart did not light")
	_cases_passed += 1
	print("LIT_TARGET case 4 pass")
	return true


func _fresh() -> bool:
	_game.restart()
	await process_frame
	await physics_frame
	_ball = null
	for node in get_nodes_in_group("ball"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is Node2D:
			_ball = node
			break
	if _ball == null:
		return _fail("no live ball after restart")
	if _ball is RigidBody2D:
		var body := _ball as RigidBody2D
		body.freeze = true
		body.sleeping = true
		body.linear_velocity = Vector2.ZERO
	if _targets().size() != 5:
		return _fail("expected 5 targets, got %d" % _targets().size())
	for target in _targets():
		if bool(target.lit):
			return _fail("target lit after restart")
	return true


func _targets() -> Array:
	var out: Array = []
	for child in _bank.get_children():
		if child.is_in_group("targets"):
			out.append(child)
	return out


func _strike(target: Node) -> void:
	if not is_instance_valid(_ball) or _ball.is_queued_for_deletion():
		push_error("LIT_TARGET strike without a live ball")
		return
	target.call("_on_sensor_body_entered", _ball)


func _disconnect_hits(targets: Array, on_hit: Callable) -> void:
	for target in targets:
		if target.hit.is_connected(on_hit):
			target.hit.disconnect(on_hit)


func _fail(message: String) -> bool:
	push_error("LIT_TARGET FAIL %s" % message)
	print("LIT_TARGET FAIL %s" % message)
	quit(1)
	return false
