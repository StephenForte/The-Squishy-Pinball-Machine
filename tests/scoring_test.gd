extends SceneTree

const BALL_SCENE := preload("res://scenes/ball.tscn")
const DROP_ABOVE := 60.0
const CONTACT_WAIT := 180
const KICK_CHECK_FRAMES := 10
const TARGET_DRIVE_SPEED := 520.0
const TARGET_STANDOFF := 52.0
const BANK_RESET_FRAMES := 90
const DRAIN_LIMIT := 3000
## 1300 never leaves the lane (T2 fallback: min y≈459 at x=666). Exit
## threshold is ~1600. 1750 covers a mid playfield arc; 1700 can rest on
## an idle flipper (T3 paddle hold), which is not a bumper wedge.
const LAUNCH_IMPULSES := [1600.0, 1750.0, 1850.0]

var _game: Node
var _table: Node2D
var _bank: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load scenes/main.tscn")
		return
	await process_frame
	await physics_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("Game autoload missing")
		return
	_table = current_scene.get_node_or_null("Table")
	if _table == null:
		_fail("Table missing on main.tscn")
		return
	_bank = _table.get_node_or_null("TargetBank")
	if _bank == null:
		_fail("TargetBank missing")
		return

	if not await _case_1_bumpers():
		return
	if not await _case_2_targets():
		return
	if not await _case_3_restart():
		return
	if not await _case_4_drains():
		return

	print("SCORE PASS bumpers=3 targets=3 bonus=1 drains=3")
	quit(0)


func _case_1_bumpers() -> bool:
	_game.restart()
	await process_frame
	await physics_frame
	var bumpers := get_nodes_in_group("bumpers")
	if bumpers.size() < 3:
		return _fail("case 1: expected >=3 bumpers, got %d" % bumpers.size())
	var checked := 0
	for bumper in bumpers:
		if not (bumper is Node2D):
			continue
		if checked >= 3:
			break
		if not await _drop_on_bumper(bumper as Node2D):
			return false
		checked += 1
	if checked != 3:
		return _fail("case 1: checked %d bumpers, need 3" % checked)
	print("SCORE case 1 pass bumpers=3")
	return true


func _drop_on_bumper(bumper: Node2D) -> bool:
	await _free_balls()
	var start_score: int = _game.score
	var ball := await _spawn_ball(bumper.global_position + Vector2(0, -DROP_ABOVE), Vector2.ZERO)
	if ball == null:
		return _fail("case 1: no ball above bumper at %s" % bumper.global_position)
	var speed_at := [-1.0]
	var on_score := func(_n: int) -> void:
		if is_instance_valid(ball):
			speed_at[0] = ball.linear_velocity.length()
	_game.score_changed.connect(on_score)
	var scored := false
	for _i in CONTACT_WAIT:
		await physics_frame
		if _game.score != start_score:
			scored = true
			break
	_game.score_changed.disconnect(on_score)
	if not scored:
		return _fail("case 1: bumper at %s did not score" % bumper.global_position)
	if _game.score - start_score != 100:
		return _fail(
			"case 1: expected +100 at %s, got +%d"
			% [bumper.global_position, _game.score - start_score]
		)
	for _k in KICK_CHECK_FRAMES:
		await physics_frame
	if not is_instance_valid(ball):
		return _fail("case 1: ball freed after bumper at %s" % bumper.global_position)
	if _game.score - start_score != 100:
		return _fail(
			"case 1: extra score after kick at %s, delta=%d"
			% [bumper.global_position, _game.score - start_score]
		)
	var speed_after := ball.linear_velocity.length()
	if speed_after <= speed_at[0]:
		return _fail(
			"case 1: kick not real at %s contact=%.1f after=%.1f"
			% [bumper.global_position, speed_at[0], speed_after]
		)
	return true


func _case_2_targets() -> bool:
	_game.restart()
	await process_frame
	await physics_frame
	for target in _bank_targets():
		target.reset()
	var targets := _bank_targets()
	if targets.size() != 3:
		return _fail("case 2: expected 3 targets, got %d" % targets.size())

	var bonus_emits := [0]
	var on_bonus := func() -> void:
		bonus_emits[0] += 1
	_bank.all_targets_hit.connect(on_bonus)

	for i in targets.size():
		var target: Node = targets[i]
		var before: int = _game.score
		if not await _drive_into_target(target):
			_bank.all_targets_hit.disconnect(on_bonus)
			return false
		if not bool(target.lit):
			_bank.all_targets_hit.disconnect(on_bonus)
			return _fail("case 2: target %d not lit after first hit" % i)
		if i < 2:
			if _game.score - before != 500:
				_bank.all_targets_hit.disconnect(on_bonus)
				return _fail(
					"case 2: target %d expected +500, got +%d" % [i, _game.score - before]
				)
		var mid: int = _game.score
		if not await _drive_into_target(target):
			_bank.all_targets_hit.disconnect(on_bonus)
			return false
		if _game.score != mid:
			_bank.all_targets_hit.disconnect(on_bonus)
			return _fail(
				"case 2: lit target %d scored +%d, expected 0" % [i, _game.score - mid]
			)

	if bonus_emits[0] != 1:
		_bank.all_targets_hit.disconnect(on_bonus)
		return _fail("case 2: all_targets_hit emitted %d, expected 1" % bonus_emits[0])
	if _game.score < 2500:
		_bank.all_targets_hit.disconnect(on_bonus)
		return _fail("case 2: score %d missing +2500 bonus" % _game.score)
	for _r in BANK_RESET_FRAMES:
		await physics_frame
	for target in targets:
		if bool(target.lit):
			_bank.all_targets_hit.disconnect(on_bonus)
			return _fail("case 2: target still lit after bank reset")
	_bank.all_targets_hit.disconnect(on_bonus)
	print("SCORE case 2 pass targets=3 bonus=1")
	return true


func _drive_into_target(target: Node) -> bool:
	await _free_balls()
	var node := target as Node2D
	var inward := Vector2(360, 640) - node.global_position
	if inward.length_squared() < 0.0001:
		inward = Vector2.DOWN
	inward = inward.normalized()
	var pos := node.global_position + inward * TARGET_STANDOFF
	var ball := await _spawn_ball(pos, -inward * TARGET_DRIVE_SPEED)
	if ball == null:
		return _fail("case 2: no ball for target at %s" % node.global_position)
	for _i in CONTACT_WAIT:
		await physics_frame
		if not is_instance_valid(ball):
			return _fail("case 2: ball freed before contact at %s" % node.global_position)
		if ball.global_position.distance_to(node.global_position) <= 48.0:
			for _settle in 8:
				await physics_frame
			return true
	return _fail("case 2: no contact with target at %s" % node.global_position)


func _case_3_restart() -> bool:
	_game.restart()
	await process_frame
	await physics_frame
	for target in _bank_targets():
		target.reset()
	var targets := _bank_targets()
	if not await _drive_into_target(targets[0]):
		return false
	if not await _drive_into_target(targets[1]):
		return false
	if not bool(targets[0].lit) or not bool(targets[1].lit):
		return _fail("case 3: failed to light two targets")
	_game.restart()
	await process_frame
	await physics_frame
	if _game.score != 0:
		return _fail("case 3: score %d after restart, expected 0" % _game.score)
	if bool(targets[0].lit) or bool(targets[1].lit):
		return _fail("case 3: targets still lit after Game.restart()")
	print("SCORE case 3 pass restart")
	return true


func _case_4_drains() -> bool:
	_game.restart()
	await process_frame
	await physics_frame
	var launcher: Node = _table.get_node("Launcher")
	var drained := 0
	for impulse in LAUNCH_IMPULSES:
		var ball := await _fresh_lane_ball()
		if ball == null:
			return _fail("case 4: no lane ball for impulse %s" % impulse)
		var before: int = _game.balls_left
		launcher.launch(impulse)
		if not bool(ball.get("launched")):
			return _fail("case 4: launch impulse %s did not fire" % impulse)
		var got := false
		for _f in DRAIN_LIMIT:
			await physics_frame
			if _game.balls_left < before:
				got = true
				break
		if not got:
			return _fail("case 4: impulse %s did not drain within %d frames" % [impulse, DRAIN_LIMIT])
		drained += 1
	print("SCORE case 4 pass drains=3")
	return true


func _fresh_lane_ball() -> Node2D:
	await _free_balls()
	_table.spawn_ball()
	await physics_frame
	var ball := _find_lane_ball()
	if ball == null:
		return null
	while is_instance_valid(ball) and not bool(ball.get("_ccd_ready")):
		await physics_frame
	return ball if is_instance_valid(ball) else null


func _find_lane_ball() -> Node2D:
	for node in get_nodes_in_group("ball"):
		if not (node is Node2D):
			continue
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var pos: Vector2 = (node as Node2D).global_position
		if pos.x > 620.0 and pos.y > 1100.0:
			return node
	return null


func _spawn_ball(pos: Vector2, vel: Vector2) -> RigidBody2D:
	var ball := BALL_SCENE.instantiate() as RigidBody2D
	ball.position = pos
	_table.add_child(ball)
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	PhysicsServer2D.body_set_state(
		ball.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, pos)
	)
	await physics_frame
	while is_instance_valid(ball) and not bool(ball.get("_ccd_ready")):
		await physics_frame
	if not is_instance_valid(ball):
		return null
	ball.sleeping = false
	ball.linear_velocity = vel
	return ball


func _free_balls() -> void:
	for node in get_nodes_in_group("ball"):
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _bank_targets() -> Array:
	var out: Array = []
	for child in _bank.get_children():
		if child.is_in_group("targets"):
			out.append(child)
	return out


func _fail(message: String) -> bool:
	push_error("SCORE FAIL %s" % message)
	print("SCORE FAIL %s" % message)
	quit(1)
	return false
