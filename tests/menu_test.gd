extends SceneTree

var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node_or_null("Game")
	var profile := root.get_node_or_null("Profile")
	if game == null or profile == null:
		_fail("could not acquire Game or Profile autoload")
		return
	if String(profile.player_name).is_empty():
		profile.call("set_name", "Dad")
	game.high_score = 0
	game.restart()
	await process_frame

	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("main scene did not load")
		return
	await process_frame
	await process_frame
	await process_frame

	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)

	if not await _case_1_menu_mid_game(main, game):
		return
	if not await _case_2_space_from_menu(main):
		return
	if not await _case_3_menu_button(main, game):
		return
	if not await _case_4_escape_while_capturing(main, game):
		return
	if not await _case_5_restart_title_stays_hidden(main, game):
		return

	print("MENU PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_menu_mid_game(main: Node, game: Node) -> bool:
	var title := _require_node(main, "Title")
	var game_over := _require_node(main, "GameOver")
	if title == null or game_over == null:
		return false
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	_push_action(main, "launch_ball")
	var launched := false
	for _f in 5:
		await physics_frame
		if is_instance_valid(ball) and bool(ball.get("launched")):
			launched = true
			break
	_push_action(main, "launch_ball", false)
	if not launched:
		return _fail("case 1: ball did not launch")
	if title.visible:
		return _fail("case 1: Title should hide after launch")
	game.add_score(100)
	await process_frame
	if game.score <= 0:
		return _fail("case 1: expected score > 0 before menu")

	_push_action(main, "menu")
	await process_frame
	await process_frame
	_push_action(main, "menu", false)
	await process_frame

	if game.state != game.READY:
		return _fail("case 1: expected Game READY after menu, got %s" % game.state)
	if game.score != 0:
		return _fail("case 1: expected score 0 after menu, got %d" % game.score)
	if game.balls_left != 3:
		return _fail("case 1: expected balls 3 after menu, got %d" % game.balls_left)
	if not title.visible:
		return _fail("case 1: Title should be visible after menu")
	if game_over.visible:
		return _fail("case 1: GameOver should be hidden after menu")
	var balls := _live_balls()
	if balls.size() != 1:
		return _fail("case 1: expected exactly one ball, got %d" % balls.size())
	if not _is_lane_ball(balls[0]):
		return _fail("case 1: the remaining ball is not in the lane")
	_cases_passed += 1
	print("MENU case 1 pass")
	return true


func _case_2_space_from_menu(main: Node) -> bool:
	var title := _require_node(main, "Title")
	if title == null:
		return false
	if not title.visible:
		return _fail("case 2: Title should be visible before Space")
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	_push_action(main, "launch_ball")
	var launched := false
	for _f in 5:
		await physics_frame
		if is_instance_valid(ball) and bool(ball.get("launched")):
			launched = true
			break
	_push_action(main, "launch_ball", false)
	if title.visible:
		return _fail("case 2: Title should hide after Space")
	if not launched:
		return _fail("case 2: Space did not launch the ball")
	_cases_passed += 1
	print("MENU case 2 pass")
	return true


func _case_3_menu_button(main: Node, game: Node) -> bool:
	var title := _require_node(main, "Title")
	var game_over := _require_node(main, "GameOver")
	if title == null or game_over == null:
		return false
	for _i in 3:
		game.on_ball_drained()
		await physics_frame
		await process_frame
	if not game_over.visible:
		return _fail("case 3: GameOver should be visible after three drains")
	var menu_button := game_over.get_node_or_null("MenuButton") as Button
	if menu_button == null:
		return _fail("case 3: missing MenuButton")
	menu_button.pressed.emit()
	await process_frame
	await process_frame
	if not title.visible:
		return _fail("case 3: Title should be visible after MenuButton")
	if game_over.visible:
		return _fail("case 3: GameOver should be hidden after MenuButton")
	_cases_passed += 1
	print("MENU case 3 pass")
	return true


func _case_4_escape_while_capturing(main: Node, game: Node) -> bool:
	var title := _require_node(main, "Title")
	var entry := _require_node(main, "NameEntry")
	if title == null or entry == null:
		return false
	if not title.visible:
		return _fail("case 4: Title should be visible")
	game.add_score(50)
	await process_frame
	_push_action(main, "change_name")
	await process_frame
	await process_frame
	for _i in 10:
		if entry.has_method("is_capturing") and entry.is_capturing():
			break
		if entry.has_method("grab_name_focus"):
			entry.grab_name_focus()
		await process_frame
	if not entry.is_capturing():
		return _fail("case 4: NameEntry should be capturing after N")

	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	main.get_viewport().push_input(esc)
	await process_frame
	await process_frame
	esc.pressed = false
	main.get_viewport().push_input(esc)
	await process_frame

	if entry.visible:
		return _fail("case 4: NameEntry should close on Escape")
	if not title.visible:
		return _fail("case 4: Title should stay visible; menu must not fire")
	if game.score != 50:
		return _fail("case 4: menu fired while capturing (score reset to %d)" % game.score)
	_cases_passed += 1
	print("MENU case 4 pass")
	return true


func _case_5_restart_title_stays_hidden(main: Node, game: Node) -> bool:
	var title := _require_node(main, "Title")
	if title == null:
		return false
	if not title.visible:
		return _fail("case 5: Title should be visible before Space")
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	_push_action(main, "launch_ball")
	for _f in 5:
		await physics_frame
	_push_action(main, "launch_ball", false)
	if title.visible:
		return _fail("case 5: Title should hide after Space")
	_push_action(main, "restart")
	await process_frame
	await process_frame
	_push_action(main, "restart", false)
	if title.visible:
		return _fail("case 5: Title should stay hidden after plain R")
	if game.state != game.READY:
		return _fail("case 5: expected READY after R, got %s" % game.state)
	_cases_passed += 1
	print("MENU case 5 pass")
	return true


func _push_action(main: Node, action: StringName, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	main.get_viewport().push_input(ev)


func _live_balls() -> Array[Node]:
	var out: Array[Node] = []
	for node in get_nodes_in_group("ball"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			out.append(node)
	return out


func _is_lane_ball(node: Node) -> bool:
	if not (node is Node2D):
		return false
	var pos: Vector2 = (node as Node2D).global_position
	return pos.x > 620.0 and pos.y > 1100.0


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


func _fail(message: String) -> bool:
	push_error("MENU FAIL %s" % message)
	print("MENU FAIL %s" % message)
	quit(1)
	return false
