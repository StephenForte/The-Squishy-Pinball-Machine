extends SceneTree

const TABLE_SCENE := preload("res://scenes/table.tscn")
const VIEWPORT := Rect2(0, 0, 720, 1280)
const MARGIN := 8.0
const LAUNCH_COUNT := 20
const FRAMES_PER_LAUNCH := 600


func _initialize() -> void:
	_run_soak.call_deferred()


func _run_soak() -> void:
	var table: Node2D = TABLE_SCENE.instantiate()
	root.add_child(table)
	await process_frame
	await physics_frame

	var launcher: Node = table.get_node("Launcher")
	var impulse_min: float = launcher.LAUNCH_IMPULSE_MIN
	var impulse_max: float = launcher.LAUNCH_IMPULSE
	var frames := 0
	var bounds := VIEWPORT.grow(-MARGIN)

	for i in LAUNCH_COUNT:
		var ball := await _fresh_lane_ball(table)
		if ball == null:
			push_error("SOAK: no lane ball available for launch %d" % (i + 1))
			print("SOAK FAIL launches=%d frames=%d out_of_bounds=1" % [i + 1, frames])
			quit(1)
			return
		var t := 0.0 if LAUNCH_COUNT == 1 else float(i) / float(LAUNCH_COUNT - 1)
		var impulse: float = lerpf(impulse_min, impulse_max, t)
		launcher.launch(impulse)
		if not bool(ball.get("launched")):
			push_error("SOAK: launch %d impulse=%s did not fire" % [i + 1, impulse])
			print("SOAK FAIL launches=%d frames=%d out_of_bounds=1" % [i + 1, frames])
			quit(1)
			return
		for _f in FRAMES_PER_LAUNCH:
			await physics_frame
			frames += 1
			for node in get_nodes_in_group("ball"):
				if not (node is Node2D):
					continue
				if not is_instance_valid(node) or node.is_queued_for_deletion():
					continue
				var pos: Vector2 = (node as Node2D).global_position
				if not bounds.has_point(pos):
					push_error(
						"SOAK: ball out of bounds at %s on launch %d frame %d"
						% [pos, i + 1, frames]
					)
					print(
						"SOAK FAIL launches=%d frames=%d out_of_bounds=1"
						% [i + 1, frames]
					)
					quit(1)
					return

	var fallback := await _fresh_lane_ball(table)
	if fallback == null:
		push_error("SOAK: no lane ball for relaunch regression")
		print(
			"SOAK FAIL launches=%d frames=%d out_of_bounds=0 relaunch=0"
			% [LAUNCH_COUNT, frames]
		)
		quit(1)
		return
	launcher.launch(1100.0)
	if not bool(fallback.get("launched")):
		push_error("SOAK: weak launch did not fire")
		print(
			"SOAK FAIL launches=%d frames=%d out_of_bounds=0 relaunch=0"
			% [LAUNCH_COUNT, frames]
		)
		quit(1)
		return
	for _w in FRAMES_PER_LAUNCH:
		await physics_frame
	if not is_instance_valid(fallback) or _find_lane_ball() != fallback:
		push_error("SOAK: weak launch did not fall back into the lane")
		print(
			"SOAK FAIL launches=%d frames=%d out_of_bounds=0 relaunch=0"
			% [LAUNCH_COUNT, frames]
		)
		quit(1)
		return
	var y_before: float = fallback.global_position.y
	launcher.launch(1850.0)
	for _r in 120:
		await physics_frame
	if not is_instance_valid(fallback):
		push_error("SOAK: ball freed during relaunch")
		print(
			"SOAK FAIL launches=%d frames=%d out_of_bounds=0 relaunch=0"
			% [LAUNCH_COUNT, frames]
		)
		quit(1)
		return
	var moved: float = absf(fallback.global_position.y - y_before)
	if moved <= 20.0:
		push_error("SOAK: relaunch after fallback moved only %s px" % moved)
		print(
			"SOAK FAIL launches=%d frames=%d out_of_bounds=0 relaunch=0"
			% [LAUNCH_COUNT, frames]
		)
		quit(1)
		return

	print(
		"SOAK PASS launches=%d frames=%d out_of_bounds=0 relaunch=1"
		% [LAUNCH_COUNT, frames]
	)
	quit(0)


func _fresh_lane_ball(table: Node) -> Node2D:
	for node in get_nodes_in_group("ball"):
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	if table.get("_respawn_pending"):
		table.set("_respawn_pending", false)
	table.spawn_ball()
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
