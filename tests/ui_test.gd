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
	if not await _case_2_score(main, game):
		return
	if not await _case_3_three_drains(main, game):
		return
	if not await _case_4_restart_redraw(main, game):
		return
	if not await _case_5_lower_game(main, game):
		return
	if not await _case_6_restart_button(main, game):
		return
	if not await _case_7_restart_action(main, game):
		return

	print("UI PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_initial(main: Node) -> bool:
	var score_label := _require_label(main, "ScoreLabel")
	var balls_label := _require_label(main, "BallsLabel")
	var game_over := _require_node(main, "GameOver")
	if score_label == null or balls_label == null or game_over == null:
		return false
	if not _shows_number(score_label.text, 0):
		return _fail("case 1: ScoreLabel should show 0, got '%s'" % score_label.text)
	if not _shows_number(balls_label.text, 3):
		return _fail("case 1: BallsLabel should show 3, got '%s'" % balls_label.text)
	if game_over.visible:
		return _fail("case 1: GameOver should not be visible")
	_cases_passed += 1
	print("UI case 1 pass")
	return true


func _case_2_score(main: Node, game: Node) -> bool:
	var score_label := _require_label(main, "ScoreLabel")
	if score_label == null:
		return false
	game.add_score(250)
	await process_frame
	if not score_label.text.contains("250"):
		return _fail("case 2: ScoreLabel should contain 250 within one frame, got '%s'" % score_label.text)
	_cases_passed += 1
	print("UI case 2 pass")
	return true


func _case_3_three_drains(main: Node, game: Node) -> bool:
	var balls_label := _require_label(main, "BallsLabel")
	var game_over := _require_node(main, "GameOver")
	var new_high := _require_label(main, "NewHighScoreLabel")
	var final_label := _require_label(main, "FinalScoreLabel")
	if balls_label == null or game_over == null or new_high == null or final_label == null:
		return false

	var expected: Array[int] = [2, 1, 0]
	for n in expected:
		game.on_ball_drained()
		await physics_frame
		await process_frame
		if not _shows_number(balls_label.text, n):
			return _fail("case 3: BallsLabel should show %d, got '%s'" % [n, balls_label.text])

	if not game_over.visible:
		return _fail("case 3: GameOver should be visible after third drain")
	if not final_label.text.contains("250"):
		return _fail("case 3: final-score text should contain 250, got '%s'" % final_label.text)
	if not new_high.visible:
		return _fail("case 3: NewHighScoreLabel should be visible on a new high")
	_cases_passed += 1
	print("UI case 3 pass")
	return true


func _case_4_restart_redraw(main: Node, game: Node) -> bool:
	var score_label := _require_label(main, "ScoreLabel")
	var balls_label := _require_label(main, "BallsLabel")
	var high_label := _require_label(main, "HighScoreLabel")
	var game_over := _require_node(main, "GameOver")
	if score_label == null or balls_label == null or high_label == null or game_over == null:
		return false

	game.restart()
	await process_frame
	if game_over.visible:
		return _fail("case 4: GameOver should be hidden after restart")
	if not _shows_number(score_label.text, 0):
		return _fail("case 4: ScoreLabel should show 0 after restart, got '%s'" % score_label.text)
	if not _shows_number(balls_label.text, 3):
		return _fail("case 4: BallsLabel should show 3 after restart, got '%s'" % balls_label.text)
	if not high_label.text.contains("250"):
		return _fail("case 4: HighScoreLabel should contain 250 after restart, got '%s'" % high_label.text)
	_cases_passed += 1
	print("UI case 4 pass")
	return true


func _case_5_lower_game(main: Node, game: Node) -> bool:
	var new_high := _require_label(main, "NewHighScoreLabel")
	var game_over := _require_node(main, "GameOver")
	if new_high == null or game_over == null:
		return false

	game.add_score(50)
	for _i in 3:
		game.on_ball_drained()
		await physics_frame
		await process_frame
	if not game_over.visible:
		return _fail("case 5: GameOver should be visible after a lower game")
	if new_high.visible:
		return _fail("case 5: NewHighScoreLabel must not be visible when high score stands")
	_cases_passed += 1
	print("UI case 5 pass")
	return true


func _case_6_restart_button(main: Node, game: Node) -> bool:
	var game_over := _require_node(main, "GameOver")
	var button := _require_button(main, "RestartButton")
	if game_over == null or button == null:
		return false
	button.pressed.emit()
	await process_frame
	if game.state != game.READY:
		return _fail("case 6: expected Game.state READY after RestartButton, got %s" % game.state)
	if game_over.visible:
		return _fail("case 6: GameOver should be hidden after RestartButton")
	_cases_passed += 1
	print("UI case 6 pass")
	return true


func _case_7_restart_action(main: Node, game: Node) -> bool:
	var game_over := _require_node(main, "GameOver")
	if game_over == null:
		return false

	game.add_score(10)
	for _i in 3:
		game.on_ball_drained()
		await physics_frame
		await process_frame
	if not game_over.visible:
		return _fail("case 7: GameOver should be showing before the restart action")
	if game.state != game.GAME_OVER:
		return _fail("case 7: expected GAME_OVER before the restart action, got %s" % game.state)

	var ev := InputEventAction.new()
	ev.action = "restart"
	ev.pressed = true
	main.get_viewport().push_input(ev)
	await process_frame
	await process_frame
	if game.state != game.READY:
		return _fail("case 7: panel swallowed restart; Game.state=%s" % game.state)
	_cases_passed += 1
	print("UI case 7 pass")
	return true


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


func _require_label(root_node: Node, node_name: String) -> Label:
	var node := _require_node(root_node, node_name)
	if node == null:
		return null
	if not (node is Label):
		_fail("%s is not a Label" % node_name)
		return null
	return node as Label


func _require_button(root_node: Node, node_name: String) -> Button:
	var node := _require_node(root_node, node_name)
	if node == null:
		return null
	if not (node is Button):
		_fail("%s is not a Button" % node_name)
		return null
	return node as Button


func _shows_number(text: String, value: int) -> bool:
	var re := RegEx.new()
	re.compile("\\d+")
	var found: PackedStringArray = []
	for m in re.search_all(text):
		found.append(m.get_string())
	if found.is_empty():
		return false
	return found[found.size() - 1] == str(value)


func _delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("highscore.save"):
		dir.remove("highscore.save")


func _fail(message: String) -> bool:
	push_error("UI FAIL %s" % message)
	print("UI FAIL %s" % message)
	quit(1)
	return false
