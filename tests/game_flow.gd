extends SceneTree

const GAME_SCRIPT := preload("res://autoload/game.gd")
const SAVE_PATH := "user://highscore.save"

var _cases_passed: int = 0
var _autoload_used: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_delete_save()
	var game := _acquire_game()
	if game == null:
		_fail("could not acquire Game")
		return
	# Autoload _ready may have loaded a leftover save before we deleted it.
	game.high_score = 0
	game.restart()
	await process_frame

	if not await _case_1_fresh(game):
		return
	if not await _case_2_three_drains(game):
		return
	if not await _case_3_score_and_high(game):
		return
	if not await _case_4_restart_and_lower(game):
		return
	if not await _case_5_persistence(game):
		return

	print("FLOW PASS cases=%d game_over_emits=1" % _cases_passed)
	print("FLOW autoload_used=%s" % _autoload_used)
	quit(0)


func _acquire_game() -> Node:
	var existing: Node = root.get_node_or_null("Game")
	if existing != null:
		_autoload_used = true
		print("FLOW Game source=autoload path=root/Game")
		return existing
	var game: Node = GAME_SCRIPT.new()
	game.name = "Game"
	root.add_child(game)
	print("FLOW Game source=manual instantiate=autoload/game.gd")
	return game


func _case_1_fresh(game: Node) -> bool:
	var ready_or_playing: bool = game.state == game.READY or game.state == game.PLAYING
	if game.balls_left != 3 or game.score != 0 or not ready_or_playing:
		return _fail(
			"case 1: expected balls=3 score=0 READY/PLAYING, got balls=%s score=%s state=%s"
			% [game.balls_left, game.score, game.state]
		)
	_cases_passed += 1
	print("FLOW case 1 pass")
	return true


func _case_2_three_drains(game: Node) -> bool:
	var counts: Array[int] = []
	var overs: Array = []
	var on_count := func(n: int) -> void:
		counts.append(n)
	var on_over := func(final_score: int, is_high: bool) -> void:
		overs.append({"final_score": final_score, "is_high_score": is_high})
	game.ball_count_changed.connect(on_count)
	game.game_over.connect(on_over)

	game.on_ball_drained()
	game.on_ball_drained()
	if game.balls_left != 2 or counts != [2]:
		game.ball_count_changed.disconnect(on_count)
		game.game_over.disconnect(on_over)
		return _fail(
			"case 2: same-frame double drain should decrement once, balls=%s counts=%s"
			% [game.balls_left, counts]
		)
	await physics_frame
	game.on_ball_drained()
	await physics_frame
	game.on_ball_drained()
	await physics_frame
	if counts != [2, 1, 0]:
		game.ball_count_changed.disconnect(on_count)
		game.game_over.disconnect(on_over)
		return _fail("case 2: expected counts [2,1,0], got %s" % [counts])
	if overs.size() != 1:
		game.ball_count_changed.disconnect(on_count)
		game.game_over.disconnect(on_over)
		return _fail("case 2: expected game_over exactly once, got %d" % overs.size())
	if game.state != game.GAME_OVER:
		game.ball_count_changed.disconnect(on_count)
		game.game_over.disconnect(on_over)
		return _fail("case 2: expected GAME_OVER, got %s" % game.state)

	var counts_before := counts.size()
	var overs_before := overs.size()
	game.on_ball_drained()
	await physics_frame
	if counts.size() != counts_before or overs.size() != overs_before:
		game.ball_count_changed.disconnect(on_count)
		game.game_over.disconnect(on_over)
		return _fail("case 2: fourth on_ball_drained emitted signals")

	game.ball_count_changed.disconnect(on_count)
	game.game_over.disconnect(on_over)
	_cases_passed += 1
	print("FLOW case 2 pass game_over_emits=1")
	return true


func _case_3_score_and_high(game: Node) -> bool:
	game.restart()
	await process_frame
	var scores: Array[int] = []
	var overs: Array = []
	var on_score := func(n: int) -> void:
		scores.append(n)
	var on_over := func(final_score: int, is_high: bool) -> void:
		overs.append({"final_score": final_score, "is_high_score": is_high})
	game.score_changed.connect(on_score)
	game.game_over.connect(on_over)

	game.add_score(100)
	game.add_score(100)
	game.add_score(100)
	if scores.is_empty() or scores[scores.size() - 1] != 300 or game.score != 300:
		game.score_changed.disconnect(on_score)
		game.game_over.disconnect(on_over)
		return _fail("case 3: expected score 300, scores=%s" % [scores])

	game.on_ball_drained()
	await physics_frame
	game.on_ball_drained()
	await physics_frame
	game.on_ball_drained()
	await physics_frame

	if overs.size() != 1:
		game.score_changed.disconnect(on_score)
		game.game_over.disconnect(on_over)
		return _fail("case 3: expected one game_over, got %d" % overs.size())
	if overs[0]["final_score"] != 300 or overs[0]["is_high_score"] != true:
		game.score_changed.disconnect(on_score)
		game.game_over.disconnect(on_over)
		return _fail("case 3: expected game_over(300, true), got %s" % [overs[0]])

	game.score_changed.disconnect(on_score)
	game.game_over.disconnect(on_over)
	_cases_passed += 1
	print("FLOW case 3 pass")
	return true


func _case_4_restart_and_lower(game: Node) -> bool:
	var restarts: Array[int] = [0]
	var counts_on_restart: Array[int] = []
	var on_restart := func() -> void:
		restarts[0] += 1
	var on_count := func(n: int) -> void:
		counts_on_restart.append(n)
	game.game_restarted.connect(on_restart)
	game.ball_count_changed.connect(on_count)
	game.restart()
	await process_frame
	game.game_restarted.disconnect(on_restart)
	game.ball_count_changed.disconnect(on_count)
	if restarts[0] != 1:
		return _fail("case 4: expected game_restarted once, got %d" % restarts[0])
	if not counts_on_restart.is_empty():
		return _fail(
			"case 4: restart must not emit ball_count_changed (would double-spawn), got %s"
			% [counts_on_restart]
		)
	if game.balls_left != 3 or game.score != 0 or game.high_score != 300:
		return _fail(
			"case 4: expected balls=3 score=0 high=300, got balls=%s score=%s high=%s"
			% [game.balls_left, game.score, game.high_score]
		)

	var overs: Array = []
	var on_over := func(final_score: int, is_high: bool) -> void:
		overs.append({"final_score": final_score, "is_high_score": is_high})
	game.game_over.connect(on_over)
	game.add_score(50)
	game.on_ball_drained()
	await physics_frame
	game.on_ball_drained()
	await physics_frame
	game.on_ball_drained()
	await physics_frame
	game.game_over.disconnect(on_over)
	if overs.size() != 1 or overs[0]["final_score"] != 50 or overs[0]["is_high_score"] != false:
		return _fail("case 4: expected game_over(50, false), got %s" % [overs])
	if game.high_score != 300:
		return _fail("case 4: high_score should stay 300, got %s" % game.high_score)

	_cases_passed += 1
	print("FLOW case 4 pass")
	return true


func _case_5_persistence(_game: Node) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return _fail("case 5: highscore.save missing")
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return _fail("case 5: could not read highscore.save")
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _fail("case 5: save did not parse")
	if typeof(json.data) != TYPE_DICTIONARY or int(json.data.get("high_score", -1)) != 300:
		return _fail("case 5: expected {\"high_score\": 300}, got %s" % [json.data])

	var write := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if write == null:
		return _fail("case 5: could not corrupt save")
	write.store_string("not-json{{{")
	write = null

	var fresh: Node = GAME_SCRIPT.new()
	root.add_child(fresh)
	await process_frame
	if fresh.high_score != 0:
		fresh.queue_free()
		return _fail("case 5: corrupt save should load high_score=0, got %s" % fresh.high_score)
	fresh.queue_free()

	_cases_passed += 1
	print("FLOW case 5 pass")
	return true


func _delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("highscore.save"):
		dir.remove("highscore.save")


func _fail(message: String) -> bool:
	push_error("FLOW FAIL %s" % message)
	print("FLOW FAIL %s" % message)
	quit(1)
	return false
