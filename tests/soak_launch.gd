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
	var out_of_bounds := 0
	var frames := 0
	var bounds := VIEWPORT.grow(-MARGIN)

	for i in LAUNCH_COUNT:
		var ball := await _ensure_lane_ball(table)
		if ball == null:
			out_of_bounds += 1
			push_error("SOAK: no lane ball available for launch %d" % (i + 1))
			break
		while not bool(ball.get("_ccd_ready")):
			await physics_frame
			if not is_instance_valid(ball):
				ball = await _ensure_lane_ball(table)
				if ball == null:
					break
		if ball == null:
			out_of_bounds += 1
			push_error("SOAK: lane ball lost before launch %d" % (i + 1))
			break
		var t := 0.0 if LAUNCH_COUNT == 1 else float(i) / float(LAUNCH_COUNT - 1)
		var impulse: float = lerpf(impulse_min, impulse_max, t)
		launcher.launch(impulse)
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
					out_of_bounds += 1
					push_error(
						"SOAK: ball out of bounds at %s on launch %d frame %d"
						% [pos, i + 1, frames]
					)

	if out_of_bounds == 0:
		print("SOAK PASS launches=%d frames=%d out_of_bounds=0" % [LAUNCH_COUNT, frames])
		quit(0)
	else:
		print(
			"SOAK FAIL launches=%d frames=%d out_of_bounds=%d"
			% [LAUNCH_COUNT, frames, out_of_bounds]
		)
		quit(1)


func _ensure_lane_ball(table: Node) -> Node2D:
	for _wait in 180:
		var lane := _find_lane_ball()
		if lane != null:
			return lane
		await physics_frame
	if table.has_method("spawn_ball"):
		table.spawn_ball()
		await physics_frame
		return _find_lane_ball()
	return null


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
