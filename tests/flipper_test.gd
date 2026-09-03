extends SceneTree

const TABLE_SCENE := preload("res://scenes/table.tscn")
const BALL_SCENE := preload("res://scenes/ball.tscn")
const VIEWPORT := Rect2(0, 0, 720, 1280)
const HIT_FRAMES := 30
const WATCH_FRAMES := 300
const HOLD_FRAMES := 60
const ANGLE_TOL_DEG := 3.0
const TIP_FLIPS := 20
const TIP_GAP_FRAMES := 40
const MIN_UP_VY := -600.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var table: Node2D = TABLE_SCENE.instantiate()
	root.add_child(table)
	await process_frame
	await physics_frame
	_free_balls()
	await process_frame

	if not await _test_rest_clears_drain(table):
		quit(1)
		return

	table.get_node("Drain").monitoring = false
	_free_balls()
	await process_frame

	var hits := 0
	if not await _test_hit(table, "FlipperLeft", "flipper_left"):
		quit(1)
		return
	hits += 1
	if not await _test_hit(table, "FlipperRight", "flipper_right"):
		quit(1)
		return
	hits += 1

	if not await _test_hold(table):
		quit(1)
		return

	var tip := await _test_tip(table)
	if tip.flips != TIP_FLIPS or tip.oob != 0:
		print(
			"TIP FAIL flips=%d oob=%d"
			% [tip.flips, tip.oob]
		)
		quit(1)
		return
	print("TIP PASS flips=%d oob=0" % TIP_FLIPS)

	print("FLIP PASS hits=%d hold=1 tip_flips=%d oob=0" % [hits, TIP_FLIPS])
	quit(0)


func _test_rest_clears_drain(table: Node2D) -> bool:
	table.get_node("Drain").monitoring = true
	_release_flippers()
	_free_balls()
	await process_frame
	await physics_frame

	for flipper_name in ["FlipperLeft", "FlipperRight"]:
		var flipper: Node2D = table.get_node(flipper_name)
		var ball := await _spawn_frozen_ball(table, flipper.ball_rest_spot(0.92))
		if ball == null:
			print("REST FAIL %s no_ball" % flipper_name)
			return false
		ball.freeze = false
		ball.sleeping = false
		for _i in 8:
			await physics_frame
			if not is_instance_valid(ball) or ball.is_queued_for_deletion():
				print("REST FAIL %s drained_on_paddle" % flipper_name)
				return false
			if ball.global_position.distance_to(flipper.global_position) > flipper.LENGTH + 24.0:
				print("REST FAIL %s left_paddle" % flipper_name)
				return false
		ball.queue_free()
		await process_frame

	print("REST PASS")
	return true


func _test_hit(table: Node2D, flipper_name: String, action: StringName) -> bool:
	_release_flippers()
	_free_balls()
	await process_frame
	await physics_frame

	var flipper: Node2D = table.get_node(flipper_name)
	var ball := await _spawn_frozen_ball(table, flipper.ball_rest_spot(0.86))
	if ball == null:
		print("HIT %s FAIL no_ball" % action)
		return false

	Input.action_press(action)
	await physics_frame
	ball.freeze = false
	ball.sleeping = false
	for _i in HIT_FRAMES:
		await physics_frame

	if not is_instance_valid(ball):
		print("HIT %s FAIL freed vy=n/a" % action)
		_release_flippers()
		return false
	var vy: float = ball.linear_velocity.y
	if vy >= MIN_UP_VY:
		print("HIT %s FAIL vy=%.1f" % [action, vy])
		_release_flippers()
		return false

	for _w in WATCH_FRAMES:
		await physics_frame
		if not is_instance_valid(ball) or not VIEWPORT.has_point(ball.global_position):
			var pos := Vector2.INF if not is_instance_valid(ball) else ball.global_position
			print("HIT %s FAIL oob=%s vy=%.1f" % [action, pos, vy])
			_release_flippers()
			return false

	print("HIT %s PASS vy=%.1f" % [action, vy])
	_release_flippers()
	for _settle in 20:
		await physics_frame
	return true


func _test_hold(table: Node2D) -> bool:
	_release_flippers()
	for _clear in 20:
		await physics_frame

	var left: Node2D = table.get_node("FlipperLeft")
	var right: Node2D = table.get_node("FlipperRight")
	Input.action_press("flipper_left")
	Input.action_press("flipper_right")
	for _up in HOLD_FRAMES:
		await physics_frame
	if not _near_angle(left.rotation, left.up_rad) or not _near_angle(right.rotation, right.up_rad):
		print(
			"HOLD FAIL up L=%.2f R=%.2f"
			% [rad_to_deg(left.rotation), rad_to_deg(right.rotation)]
		)
		_release_flippers()
		return false

	_release_flippers()
	for _down in HOLD_FRAMES:
		await physics_frame
	if not _near_angle(left.rotation, left.rest_rad) or not _near_angle(right.rotation, right.rest_rad):
		print(
			"HOLD FAIL rest L=%.2f R=%.2f"
			% [rad_to_deg(left.rotation), rad_to_deg(right.rotation)]
		)
		return false

	print("HOLD PASS")
	return true


func _test_tip(table: Node2D) -> Dictionary:
	_release_flippers()
	_free_balls()
	await process_frame
	await physics_frame

	var flipper: Node2D = table.get_node("FlipperLeft")
	var flips := 0
	var oob := 0

	for _i in TIP_FLIPS:
		_release_flippers()
		_free_balls()
		await process_frame
		await physics_frame
		var ball := await _spawn_frozen_ball(table, flipper.ball_rest_spot(0.92))
		if ball == null:
			return {flips = flips, oob = 1}
		Input.action_press("flipper_left")
		await physics_frame
		ball.freeze = false
		ball.sleeping = false
		var up_frames := 0
		while up_frames < 18:
			await physics_frame
			up_frames += 1
			if not _ball_ok(ball, flipper, true):
				oob = 1
				_release_flippers()
				return {flips = flips, oob = oob}
		flips += 1
		Input.action_release("flipper_left")
		for _gap in TIP_GAP_FRAMES:
			await physics_frame
			if not _ball_ok(ball, flipper, false):
				oob = 1
				return {flips = flips, oob = oob}

	return {flips = flips, oob = oob}


func _ball_ok(ball: Node, flipper: Node2D, flipper_up: bool) -> bool:
	if not is_instance_valid(ball):
		return false
	if not VIEWPORT.has_point(ball.global_position):
		return false
	if flipper_up and flipper.is_below_rest_line(ball.global_position):
		return false
	return true


func _spawn_frozen_ball(table: Node2D, pos: Vector2) -> RigidBody2D:
	var ball := BALL_SCENE.instantiate() as RigidBody2D
	ball.freeze = true
	ball.position = pos
	table.add_child(ball)
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
	return ball if is_instance_valid(ball) else null


func _free_balls() -> void:
	for node in get_nodes_in_group("ball"):
		if is_instance_valid(node):
			node.queue_free()


func _release_flippers() -> void:
	if Input.is_action_pressed("flipper_left"):
		Input.action_release("flipper_left")
	if Input.is_action_pressed("flipper_right"):
		Input.action_release("flipper_right")


func _near_angle(actual: float, expected: float) -> bool:
	return absf(angle_difference(actual, expected)) <= deg_to_rad(ANGLE_TOL_DEG)
