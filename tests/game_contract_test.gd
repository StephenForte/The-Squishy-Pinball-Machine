extends SceneTree

## D-005 / D-011 / D-057 Game contract edges that the scene suites skip:
## GAME_OVER is a no-op for score and drain, and reconcile_best never
## stamps a late or smaller best onto the wrong slot.

const ID_A := "aaaaaaaa-1111-4222-8333-444444444444"
const ID_B := "bbbbbbbb-1111-4222-8333-555555555555"

var _cases_passed: int = 0
var _game: Node
var _profile: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("GAME_CONTRACT start")
	_game = root.get_node_or_null("/root/Game")
	_profile = root.get_node_or_null("/root/Profile")
	if _game == null:
		_fail("Game autoload missing")
		return
	if not _game.has_method("reconcile_best") or not _game.has_signal("high_score_changed"):
		_fail("reconcile API missing")
		return
	_game.restart()
	await process_frame

	if not await _case_1_ready_to_playing():
		return
	if not await _case_2_game_over_is_noop():
		return
	if not await _case_3_reconcile_edges():
		return

	print("GAME_CONTRACT PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_ready_to_playing() -> bool:
	print("GAME_CONTRACT case 1 READY → PLAYING")
	_game.restart()
	await process_frame
	if int(_game.state) != int(_game.READY) or int(_game.score) != 0:
		return _fail("case 1: expected READY score=0, got state=%s score=%s" % [_game.state, _game.score])
	var seen: Array = []
	var on_score := func(value: int) -> void:
		seen.append(value)
	_game.score_changed.connect(on_score)
	_game.add_score(250)
	_game.score_changed.disconnect(on_score)
	if int(_game.state) != int(_game.PLAYING):
		return _fail("case 1: add_score did not enter PLAYING (state=%s)" % _game.state)
	if int(_game.score) != 250 or seen != [250]:
		return _fail("case 1: score=%s emits=%s" % [_game.score, seen])
	_cases_passed += 1
	print("GAME_CONTRACT case 1 pass")
	return true


func _case_2_game_over_is_noop() -> bool:
	print("GAME_CONTRACT case 2 GAME_OVER no-op")
	_game.restart()
	await process_frame
	_game.add_score(400)
	var overs: Array = []
	var scores: Array = []
	var streaks: Array = []
	var on_over := func(final_score: int, is_high: bool) -> void:
		overs.append({"final_score": final_score, "is_high_score": is_high})
	var on_score := func(value: int) -> void:
		scores.append(value)
	var on_streak := func(streak: int) -> void:
		streaks.append(streak)
	_game.game_over.connect(on_over)
	_game.score_changed.connect(on_score)
	_game.streak_changed.connect(on_streak)
	_game.on_ball_drained()
	var same_frame := int(_game.balls_left)
	_game.on_ball_drained()
	if int(_game.balls_left) != same_frame:
		_disconnect_over(on_over, on_score, on_streak)
		return _fail("case 2: same-frame drain consumed a second life (%s→%s)" % [same_frame, _game.balls_left])
	await physics_frame
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	if int(_game.state) != int(_game.GAME_OVER):
		_disconnect_over(on_over, on_score, on_streak)
		return _fail("case 2: expected GAME_OVER, got %s" % _game.state)
	if overs.size() != 1 or int(overs[0]["final_score"]) != 400:
		_disconnect_over(on_over, on_score, on_streak)
		return _fail("case 2: game_over %s" % overs)
	var score_after := int(_game.score)
	var balls_after := int(_game.balls_left)
	var overs_after := overs.size()
	_game.add_score(9000)
	var bumper_points := int(_game.register_bumper_hit())
	_game.on_ball_drained()
	_disconnect_over(on_over, on_score, on_streak)
	if bumper_points != 0:
		return _fail("case 2: register_bumper_hit returned %d after GAME_OVER" % bumper_points)
	if int(_game.score) != score_after:
		return _fail("case 2: score moved to %s after GAME_OVER" % _game.score)
	if int(_game.balls_left) != balls_after:
		return _fail("case 2: balls_left moved to %s after GAME_OVER" % _game.balls_left)
	if overs.size() != overs_after:
		return _fail("case 2: extra game_over %s" % overs)
	if scores.size() != 0:
		return _fail("case 2: score_changed after GAME_OVER %s" % scores)
	if streaks.size() != 0:
		return _fail("case 2: streak_changed after GAME_OVER %s" % streaks)
	if int(_game.state) != int(_game.GAME_OVER):
		return _fail("case 2: state left GAME_OVER (%s)" % _game.state)
	_cases_passed += 1
	print("GAME_CONTRACT case 2 pass")
	return true


func _case_3_reconcile_edges() -> bool:
	print("GAME_CONTRACT case 3 reconcile_best")
	_game.high_scores = {}
	_game.high_scores[ID_A] = 7400
	_game.high_scores[ID_B] = 1000
	_game._save_high_scores()
	var emitted: Array = []
	var on_high := func(player_id: String, value: int) -> void:
		emitted.append({"id": player_id, "value": value})
	_game.high_score_changed.connect(on_high)

	_game.reconcile_best("", 99999)
	_game.reconcile_best(ID_A, 5000)
	_game.reconcile_best(ID_A, 7400)
	if int(_game.high_scores.get(ID_A, 0)) != 7400:
		_game.high_score_changed.disconnect(on_high)
		return _fail("case 3: empty/smaller rewrite A to %s" % _game.high_scores.get(ID_A, 0))
	if int(_game.high_scores.get(ID_B, 0)) != 1000:
		_game.high_score_changed.disconnect(on_high)
		return _fail("case 3: empty/smaller touched B %s" % _game.high_scores.get(ID_B, 0))
	if emitted.size() != 0:
		_game.high_score_changed.disconnect(on_high)
		return _fail("case 3: empty/smaller emitted %s" % emitted)

	_game.reconcile_best(ID_A, 14300)
	_game.high_score_changed.disconnect(on_high)
	if int(_game.high_scores.get(ID_A, 0)) != 14300:
		return _fail("case 3: larger best left A at %s" % _game.high_scores.get(ID_A, 0))
	if int(_game.high_scores.get(ID_B, 0)) != 1000:
		return _fail("case 3: larger best moved B to %s" % _game.high_scores.get(ID_B, 0))
	if emitted.size() != 1 or String(emitted[0]["id"]) != ID_A or int(emitted[0]["value"]) != 14300:
		return _fail("case 3: emit %s" % emitted)
	if not _saved_high_is(ID_A, 14300) or not _saved_high_is(ID_B, 1000):
		return _fail("case 3: file %s" % _high_file())

	if _profile != null:
		var previous_id := String(_profile.player_id)
		_profile.player_id = ID_B
		if int(_game.high_score) != 1000:
			_profile.player_id = previous_id
			return _fail("case 3: current high followed A after B became current (%s)" % _game.high_score)
		_profile.player_id = previous_id

	_cases_passed += 1
	print("GAME_CONTRACT case 3 pass")
	return true


func _disconnect_over(on_over: Callable, on_score: Callable, on_streak: Callable) -> void:
	if _game.game_over.is_connected(on_over):
		_game.game_over.disconnect(on_over)
	if _game.score_changed.is_connected(on_score):
		_game.score_changed.disconnect(on_score)
	if _game.streak_changed.is_connected(on_streak):
		_game.streak_changed.disconnect(on_streak)


func _saved_high_is(player_id: String, want: int) -> bool:
	var parsed: Variant = JSON.parse_string(_high_file())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var scores: Variant = (parsed as Dictionary).get("high_scores", {})
	if typeof(scores) != TYPE_DICTIONARY:
		return false
	return int((scores as Dictionary).get(player_id, -1)) == want


func _high_file() -> String:
	if not FileAccess.file_exists("user://highscore.save"):
		return ""
	return FileAccess.get_file_as_string("user://highscore.save")


func _fail(message: String) -> bool:
	push_error("GAME_CONTRACT FAIL %s" % message)
	print("GAME_CONTRACT FAIL %s" % message)
	quit(1)
	return false
