extends SceneTree

const SAVE_PATH := "user://highscore.save"

var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_delete_save()
	var game := root.get_node_or_null("Game")
	if game == null:
		_fail("could not acquire Game autoload")
		return
	game.high_score = 0
	game.restart()
	await process_frame

	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame

	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return

	_silence_table_drain(main)

	if not await _case_1_initial(main):
		return
	if not await _case_2_launch(main):
		return
	if not await _case_3_restart_title_stays_hidden(main, game):
		return

	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	main = current_scene
	if main == null:
		_fail("main scene did not reload for case 4")
		return
	_silence_table_drain(main)
	if not await _case_4_flipper_while_title(main):
		return

	print("TITLE PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_initial(main: Node) -> bool:
	var title := _require_node(main, "Title")
	var game_over := _require_node(main, "GameOver")
	if title == null or game_over == null:
		return false
	if not title.visible:
		return _fail("case 1: Title should be visible at start")
	if game_over.visible:
		return _fail("case 1: GameOver should be hidden at start")
	_cases_passed += 1
	print("TITLE case 1 pass")
	return true


func _case_2_launch(main: Node) -> bool:
	var title := _require_node(main, "Title")
	if title == null:
		return false
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	var ev := InputEventAction.new()
	ev.action = "launch_ball"
	ev.pressed = true
	main.get_viewport().push_input(ev)
	var launched := false
	for _f in 5:
		await physics_frame
		if bool(ball.get("launched")):
			launched = true
			break
	ev.pressed = false
	main.get_viewport().push_input(ev)
	if title.visible:
		return _fail("case 2: Title should be hidden after launch_ball")
	if not launched:
		return _fail(
			"case 2: ball was not launched within 5 frames (title may have swallowed input)"
		)
	_cases_passed += 1
	print("TITLE case 2 pass")
	return true


func _case_3_restart_title_stays_hidden(main: Node, game: Node) -> bool:
	var title := _require_node(main, "Title")
	if title == null:
		return false
	for _i in 3:
		game.on_ball_drained()
		await physics_frame
		await process_frame
	game.restart()
	await process_frame
	await process_frame
	if title.visible:
		return _fail("case 3: Title should stay hidden after restart")
	_cases_passed += 1
	print("TITLE case 3 pass")
	return true


func _case_4_flipper_while_title(main: Node) -> bool:
	var title := _require_node(main, "Title")
	var flipper := main.get_node_or_null("Table/FlipperLeft")
	if title == null:
		return false
	if flipper == null:
		return _fail("case 4: missing Table/FlipperLeft")
	if not title.visible:
		return _fail("case 4: Title should be visible")
	var angle_before: float = flipper.rotation
	Input.action_press("flipper_left")
	for _i in 10:
		await physics_frame
	Input.action_release("flipper_left")
	if absf(flipper.rotation - angle_before) < 0.01:
		return _fail("case 4: flipper did not move while title visible")
	_cases_passed += 1
	print("TITLE case 4 pass")
	return true


func _wait_lane_ball(main: Node) -> Node:
	var table := main.get_node_or_null("Table")
	if table == null:
		_fail("missing Table node")
		return null
	var ball: Node = null
	for node in get_nodes_in_group("ball"):
		if node is Node2D and is_instance_valid(node):
			var pos: Vector2 = (node as Node2D).global_position
			if pos.x > 620.0 and pos.y > 1100.0:
				ball = node
				break
	if ball == null:
		_fail("no lane ball available")
		return null
	while is_instance_valid(ball) and not bool(ball.get("_ccd_ready")):
		await physics_frame
	return ball if is_instance_valid(ball) else null


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _require_node(root_node: Node, node_name: String) -> Node:
	var node := root_node.find_child(node_name, true, false)
	if node == null:
		_fail("missing node %s" % node_name)
	return node


func _delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("highscore.save"):
		dir.remove("highscore.save")


func _fail(message: String) -> bool:
	push_error("TITLE FAIL %s" % message)
	print("TITLE FAIL %s" % message)
	quit(1)
	return false
