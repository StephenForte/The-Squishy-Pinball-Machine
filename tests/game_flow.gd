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
	if not await _case_6_two_players(game):
		return
	if not await _case_7_migrate_old_highscore(game):
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
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fail("case 5: save is not a dictionary, got %s" % [json.data])
	var stored: Variant = json.data.get("high_scores", null)
	if typeof(stored) != TYPE_DICTIONARY:
		return _fail("case 5: expected high_scores map, got %s" % [json.data])
	var found_300 := false
	for key in (stored as Dictionary).keys():
		if int((stored as Dictionary)[key]) == 300:
			found_300 = true
			break
	if not found_300:
		return _fail("case 5: expected a 300 under high_scores, got %s" % [json.data])

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


func _case_6_two_players(game: Node) -> bool:
	print("FLOW case 6 two players")
	var profile := root.get_node_or_null("Profile")
	if profile == null:
		return _fail("case 6: Profile autoload missing")
	# Earlier cases (and leftover profile.save from prior suites) may already
	# have a Natasha slot with a best. Isolate this case to the two new games.
	game.high_scores = {}
	profile.call("set_name", "Dad")
	await process_frame
	var dad_id := String(profile.player_id)
	game.high_score = 0
	game.restart()
	await process_frame
	if not await _play_score(game, 700, true):
		return false
	if game.high_score != 700:
		return _fail("case 6: Dad high should be 700, got %s" % game.high_score)
	if int(game.high_scores.get(dad_id, -1)) != 700:
		return _fail("case 6: Dad slot missing 700: %s" % game.high_scores)

	profile.call("set_name", "Natasha")
	await process_frame
	var natasha_id := String(profile.player_id)
	if natasha_id == dad_id:
		return _fail("case 6: Natasha should have a different player_id")
	if game.high_score != 0:
		return _fail("case 6: Natasha should start at 0, got %s" % game.high_score)
	game.restart()
	await process_frame
	if not await _play_score(game, 500, true):
		return false
	if game.high_score != 500:
		return _fail("case 6: Natasha high should be 500, got %s" % game.high_score)
	if int(game.high_scores.get(dad_id, -1)) != 700:
		return _fail("case 6: Dad best should stay 700, got %s" % game.high_scores)

	if change_scene_to_file("res://scenes/main.tscn") != OK:
		return _fail("case 6: could not load main.tscn")
	await process_frame
	await process_frame
	await process_frame
	var main := current_scene
	if main == null:
		return _fail("case 6: main scene did not load")
	_silence_table_drain(main)
	var high_label := main.find_child("HighScoreLabel", true, false) as Label
	if high_label == null:
		return _fail("case 6: HighScoreLabel missing")
	if not high_label.text.contains("500"):
		return _fail("case 6: HUD HIGH should show 500 after Natasha, got '%s'" % high_label.text)

	profile.call("set_name", "Dad")
	await process_frame
	if game.high_score != 700:
		return _fail("case 6: switching back to Dad should restore 700, got %s" % game.high_score)
	# HUD does not subscribe to Profile.name_changed (verified). Restart is
	# the existing signal that redraws HIGH from Game.high_score.
	game.restart()
	await process_frame
	if not high_label.text.contains("700"):
		return _fail("case 6: HUD HIGH should show 700 after switching back to Dad, got '%s'" % high_label.text)

	_cases_passed += 1
	print("FLOW case 6 pass")
	return true


func _case_7_migrate_old_highscore(game: Node) -> bool:
	print("FLOW case 7 migrate old highscore")
	const PLANNER_ID := "6c107d4d-64d7-49f3-9e09-8db3a4ba9e3b"
	var profile := root.get_node_or_null("Profile")
	if profile == null:
		return _fail("case 7: Profile autoload missing")
	_write_text("user://profile.save", '{"player_id":"%s","player_name":"Natasha"}' % PLANNER_ID)
	profile._load_or_create()
	await process_frame
	if String(profile.player_id) != PLANNER_ID:
		return _fail("case 7: profile migrate should keep %s" % PLANNER_ID)
	_write_text(SAVE_PATH, '{"high_score":8600}')
	game._load_high_scores()
	if game.high_score != 8600:
		return _fail("case 7: Natasha should keep 8600, got %s" % game.high_score)
	if int(game.high_scores.get(PLANNER_ID, -1)) != 8600:
		return _fail("case 7: migrated slot missing: %s" % game.high_scores)
	var first := _read_highscore_save()
	if typeof(first.get("high_scores", null)) != TYPE_DICTIONARY:
		return _fail("case 7: first boot should rewrite high_scores, got %s" % first)
	if int((first["high_scores"] as Dictionary).get(PLANNER_ID, -1)) != 8600:
		return _fail("case 7: first boot dropped 8600: %s" % first)
	if first.has("high_score"):
		return _fail("case 7: old high_score key should be gone after migrate: %s" % first)
	game._load_high_scores()
	var second := _read_highscore_save()
	if int((second.get("high_scores", {}) as Dictionary).get(PLANNER_ID, -1)) != 8600:
		return _fail("case 7: second boot dropped 8600: %s" % second)
	if game.high_score != 8600:
		return _fail("case 7: second boot high_score=%s" % game.high_score)
	profile.call("set_name", "Dad")
	await process_frame
	if game.high_score != 0:
		return _fail("case 7: Dad should start at 0, got %s" % game.high_score)
	if int(game.high_scores.get(PLANNER_ID, -1)) != 8600:
		return _fail("case 7: adding Dad must not drop Natasha's 8600")
	_cases_passed += 1
	print("FLOW case 7 pass")
	return true


func _play_score(game: Node, points: int, expect_high: bool) -> bool:
	var overs: Array = []
	var on_over := func(final_score: int, is_high: bool) -> void:
		overs.append({"final_score": final_score, "is_high_score": is_high})
	game.game_over.connect(on_over)
	game.add_score(points)
	game.on_ball_drained()
	await physics_frame
	game.on_ball_drained()
	await physics_frame
	game.on_ball_drained()
	await physics_frame
	game.game_over.disconnect(on_over)
	if overs.size() != 1 or overs[0]["final_score"] != points or overs[0]["is_high_score"] != expect_high:
		return _fail("play %d: expected game_over(%d, %s), got %s" % [points, points, expect_high, overs])
	return true


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _read_highscore_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)


func _delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("highscore.save"):
		dir.remove("highscore.save")


func _fail(message: String) -> bool:
	push_error("FLOW FAIL %s" % message)
	print("FLOW FAIL %s" % message)
	quit(1)
	return false
