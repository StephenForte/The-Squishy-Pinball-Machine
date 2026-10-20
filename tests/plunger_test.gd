extends SceneTree

const IMPULSE := 1850.0
## One physics tick after launch() on main: mass 1, impulse (0, -1850),
## gravity 980 at 120 Hz, ball still leaving the lane floor. Reading
## linear_velocity in the same call is 0 because Godot flushes the impulse
## on the next tick. This is the untouched result.
const EXPECTED_VELOCITY := Vector2(0.0, -1840.292)
const VEL_TOL := 0.05
const REST_FRAMES := 60
const FALLBACK_POS := Vector2(623, 1150)
const OUT_OF_LANE := Vector2(360, 600)

var _launches := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("PLUNGER start")
	var failed := false
	var table: Node2D = null
	var packed: PackedScene = load("res://scenes/table.tscn") as PackedScene
	if packed == null:
		print("PLUNGER FAIL table scene did not load")
		print("PLUNGER FAIL")
		quit(1)
		return
	table = packed.instantiate() as Node2D
	if table == null:
		print("PLUNGER FAIL table did not instantiate")
		print("PLUNGER FAIL")
		quit(1)
		return
	root.add_child(table)
	await process_frame

	var launcher := table.get_node_or_null("Launcher")
	var plunger := launcher.get_node_or_null("Plunger") if launcher != null else null
	if launcher == null or plunger == null:
		print("PLUNGER FAIL launcher or plunger missing")
		print("PLUNGER FAIL")
		quit(1)
		return
	if not launcher.has_signal("launched") or not launcher.has_method("lane_ball"):
		print("PLUNGER FAIL launcher missing launched or lane_ball")
		print("PLUNGER FAIL")
		quit(1)
		return

	_launches = 0
	launcher.launched.connect(_on_launched)

	for _i in 8:
		await physics_frame
	print("PLUNGER settled")

	if not bool(plunger.fits_lane()):
		failed = true
		print("PLUNGER FAIL drawn bounds leave the lane floor at %s" % plunger.global_position)
	else:
		print("PLUNGER bounds inside lane")

	var ball: Node2D = launcher.lane_ball() as Node2D
	if ball == null:
		failed = true
		print("PLUNGER FAIL no ball waiting at spawn")
	elif not bool(plunger.shows_cue()) or float(plunger.cue_alpha()) < 0.5:
		failed = true
		print(
			"PLUNGER FAIL cue at spawn shown=%s alpha=%s"
			% [plunger.shows_cue(), plunger.cue_alpha()]
		)
	else:
		print("PLUNGER cue visible at spawn alpha=%s" % plunger.cue_alpha())

	if ball != null:
		var before := _launches
		launcher.launch(IMPULSE)
		if _launches != before + 1:
			failed = true
			print("PLUNGER FAIL launched count %d after one launch" % _launches)
		else:
			print("PLUNGER launched once")
		if not bool(ball.get("launched")):
			failed = true
			print("PLUNGER FAIL ball.launch did not run")
		if bool(plunger.at_rest()) or not bool(plunger.is_releasing()):
			failed = true
			print(
				"PLUNGER FAIL release did not start pull=%s releasing=%s"
				% [plunger.pull_amount(), plunger.is_releasing()]
			)
		else:
			print("PLUNGER release started pull=%s" % plunger.pull_amount())
		if bool(plunger.shows_cue()):
			failed = true
			print("PLUNGER FAIL cue stayed up during release")
		await physics_frame
		var velocity: Vector2 = ball.linear_velocity
		print("PLUNGER velocity %s" % velocity)
		if velocity.distance_to(EXPECTED_VELOCITY) > VEL_TOL:
			failed = true
			print(
				"PLUNGER FAIL velocity %s expected %s"
				% [velocity, EXPECTED_VELOCITY]
			)

		var frames := 0
		while bool(plunger.is_releasing()) and frames < REST_FRAMES:
			await process_frame
			frames += 1
		if bool(plunger.is_releasing()) or not bool(plunger.at_rest()):
			failed = true
			print(
				"PLUNGER FAIL not at rest after %d frames pull=%s"
				% [frames, plunger.pull_amount()]
			)
		else:
			print("PLUNGER rest in %d frames" % frames)
		if launcher.lane_ball() != null or bool(plunger.shows_cue()):
			failed = true
			print(
				"PLUNGER FAIL cue after launch waiting=%s shown=%s"
				% [launcher.lane_ball(), plunger.shows_cue()]
			)
		else:
			print("PLUNGER cue hidden after launch")

	_free_balls()
	await process_frame
	await physics_frame
	var empty_before := _launches
	launcher.launch(IMPULSE)
	await process_frame
	if _launches != empty_before:
		failed = true
		print("PLUNGER FAIL launched fired on an empty lane count=%d" % _launches)
	elif not bool(plunger.at_rest()) or bool(plunger.shows_cue()):
		failed = true
		print("PLUNGER FAIL empty launch played a cue or a snap")
	else:
		print("PLUNGER empty launch silent")

	var stray := _place_ball(table, OUT_OF_LANE, true)
	await physics_frame
	await physics_frame
	var stray_before := _launches
	if bool(plunger.shows_cue()) or launcher.lane_ball() != null:
		failed = true
		print("PLUNGER FAIL cue shown for a ball outside the lane")
	launcher.launch(IMPULSE)
	await process_frame
	if _launches != stray_before:
		failed = true
		print("PLUNGER FAIL launched fired for a ball outside the lane")
	else:
		print("PLUNGER out-of-lane launch silent")
	if stray != null and is_instance_valid(stray):
		stray.queue_free()
	await process_frame

	var fallback := _place_ball(table, FALLBACK_POS, true)
	await physics_frame
	await physics_frame
	var sensor := launcher.get_node_or_null("LaneSensor") as Area2D
	var on_sensor := false
	if sensor != null and fallback != null:
		for body in sensor.get_overlapping_bodies():
			if body == fallback:
				on_sensor = true
	if fallback == null or on_sensor or launcher.lane_ball() != fallback:
		failed = true
		print(
			"PLUNGER FAIL fallback fixture sensor=%s lane_ball=%s"
			% [on_sensor, launcher.lane_ball()]
		)
	elif not bool(plunger.shows_cue()):
		failed = true
		print("PLUNGER FAIL cue hidden for fallback-lane ball")
	else:
		print("PLUNGER cue visible on fallback path")
	if fallback != null and is_instance_valid(fallback):
		fallback.queue_free()
	await process_frame
	await physics_frame

	if table.has_method("spawn_ball"):
		table.spawn_ball()
	for _i in 8:
		await physics_frame
	var action_ball: Node = launcher.lane_ball()
	if action_ball == null or not bool(plunger.shows_cue()):
		failed = true
		print("PLUNGER FAIL no cue for the respawned lane ball")
	else:
		var action_before := _launches
		var ev := InputEventAction.new()
		ev.action = "launch_ball"
		ev.pressed = true
		table.get_viewport().push_input(ev)
		var saw := false
		for _f in 5:
			await process_frame
			if _launches > action_before:
				saw = true
				break
		if not saw:
			failed = true
			print("PLUNGER FAIL launch_ball action did not emit launched")
		elif not bool(action_ball.get("launched")):
			failed = true
			print("PLUNGER FAIL launch_ball action did not fire the ball")
		elif bool(plunger.at_rest()):
			failed = true
			print("PLUNGER FAIL launch_ball action skipped the snap")
		else:
			print("PLUNGER action launch count=%d" % _launches)

	var theme := root.get_node_or_null("Theme")
	if theme == null or not theme.has_method("set_palette") or not theme.has_method("color"):
		failed = true
		print("PLUNGER FAIL Theme autoload missing")
	else:
		var wired := false
		for conn in theme.palette_changed.get_connections():
			if conn.callable.get_object() == plunger:
				wired = true
		if not wired:
			failed = true
			print("PLUNGER FAIL plunger is not listening to palette_changed")
		var before_color: Color = plunger.head_color()
		var saved_id := String(theme.palette_id)
		var saved_pick := String(theme.saved_palette_id)
		# In memory only. set_palette() writes user://settings.save and would
		# leak into later suites in this runner.
		theme.palette_id = "grape_jam"
		theme._rebuild_colors()
		theme.palette_changed.emit("grape_jam")
		var after_color: Color = plunger.head_color()
		theme.palette_id = saved_id
		theme.saved_palette_id = saved_pick
		theme._rebuild_colors()
		theme.palette_changed.emit(saved_id)
		if after_color.is_equal_approx(before_color):
			failed = true
			print("PLUNGER FAIL head color did not follow palette %s -> %s" % [before_color, after_color])
		else:
			print("PLUNGER theme %s -> %s" % [before_color, after_color])

	if failed:
		print("PLUNGER FAIL")
		quit(1)
		return
	print("PLUNGER PASS")
	quit(0)


func _on_launched(_impulse: float) -> void:
	_launches += 1


func _place_ball(table: Node2D, pos: Vector2, frozen: bool) -> RigidBody2D:
	var ball_scene := load("res://scenes/ball.tscn") as PackedScene
	if ball_scene == null:
		print("PLUNGER FAIL ball scene did not load")
		return null
	var ball := ball_scene.instantiate() as RigidBody2D
	if ball == null:
		print("PLUNGER FAIL ball did not instantiate")
		return null
	ball.freeze = frozen
	ball.position = pos
	table.add_child(ball)
	return ball


func _free_balls() -> void:
	for node in get_nodes_in_group("ball"):
		if is_instance_valid(node):
			node.queue_free()
