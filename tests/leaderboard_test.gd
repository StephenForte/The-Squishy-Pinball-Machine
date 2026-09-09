extends SceneTree

## Leaderboard client against the local memory server (D-026). Never hits live.

const LOCAL_URL := "http://127.0.0.1:8787"
const CLOSED_URL := "http://127.0.0.1:1"
const CLIENT := "squish/1.0"

var _cases_passed: int = 0
var _leaderboard: Node
var _game: Node
var _profile: Node
var _last_submit: Dictionary = {}
var _got_submit := false
var _last_offline := ""
var _got_offline := false
var _got_board := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("LEADERBOARD start")
	_leaderboard = root.get_node_or_null("Leaderboard")
	_game = root.get_node_or_null("Game")
	_profile = root.get_node_or_null("Profile")
	if _leaderboard == null or _game == null or _profile == null:
		_fail("Leaderboard, Game, or Profile autoload missing")
		return
	if not _leaderboard.submitted.is_connected(_on_submitted):
		_leaderboard.submitted.connect(_on_submitted)
	if not _leaderboard.offline.is_connected(_on_offline):
		_leaderboard.offline.connect(_on_offline)
	if not _leaderboard.board_updated.is_connected(_on_board):
		_leaderboard.board_updated.connect(_on_board)

	OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
	OS.set_environment("SQUISH_LEADERBOARD_KEY", "devkey")

	if not await _healthz_ok(LOCAL_URL):
		_fail("local server /healthz not 200 — runner should have started it")
		return

	_profile.call("set_name", "Pat")
	_game.high_score = 0
	_game.restart()
	await process_frame

	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load main.tscn")
		return
	await process_frame
	await process_frame
	await process_frame

	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)

	if not await _case_1_title_top_five(main):
		return
	if not await _case_2_game_over_700(main):
		return
	if not await _case_3_second_game_300(main):
		return
	if not await _case_4_unreachable(main):
		return
	if not await _case_5_empty_name_no_post(main):
		return
	if not await _case_6_deploy_restart(main):
		return
	if not await _case_7_two_device_players(main):
		return

	print("LEADERBOARD PASS cases=%d" % _cases_passed)
	quit(0)


func _on_submitted(result: Dictionary) -> void:
	_got_submit = true
	_last_submit = result


func _on_offline(reason: String) -> void:
	_got_offline = true
	_last_offline = reason


func _on_board(_entries: Array, _total: int) -> void:
	_got_board = true


func _case_1_title_top_five(main: Node) -> bool:
	print("LEADERBOARD case 1 seed")
	for i in 6:
		var ok := await _api_post(_seed_id(i), "Seed%d" % i, 1000 - i * 50)
		if not ok:
			return _fail("case 1: seed POST %d failed" % i)
	_reset_wait_flags()
	_leaderboard.fetch_top(5)
	if not await _wait_flag("_got_board", 3500):
		return _fail("case 1: board_updated did not arrive")
	var title := _require_node(main, "Title")
	var top := _require_label(main, "TopFiveLabel")
	if title == null or top == null:
		return false
	if not title.visible:
		return _fail("case 1: Title should be visible")
	var text := top.text
	var lines := 0
	for line in text.split("\n"):
		if line.begins_with("1.") or line.begins_with("2.") or line.begins_with("3.") or line.begins_with("4.") or line.begins_with("5."):
			lines += 1
	if lines < 5:
		return _fail("case 1: TopFiveLabel should list 5 rows, got '%s'" % text)
	if not text.contains("Seed0") or not text.contains("Seed4"):
		return _fail("case 1: TopFiveLabel missing seeded names: '%s'" % text)
	if text.contains("Seed5"):
		return _fail("case 1: TopFiveLabel should not include 6th seed: '%s'" % text)
	_cases_passed += 1
	print("LEADERBOARD case 1 pass")
	return true


func _case_2_game_over_700(main: Node) -> bool:
	print("LEADERBOARD case 2 play 700")
	_reset_wait_flags()
	_game.add_score(700)
	for _i in 3:
		_game.on_ball_drained()
		await process_frame
		await process_frame
	if not await _wait_flag("_got_submit", 3500):
		return _fail("case 2: submitted did not arrive")
	if not bool(_last_submit.get("is_personal_best", false)):
		return _fail("case 2: expected is_personal_best true, got %s" % _last_submit)
	var rank := int(_last_submit.get("rank", 0))
	var total := int(_last_submit.get("total_players", 0))
	if rank <= 0 or total < 7:
		return _fail("case 2: bad rank/total %s" % _last_submit)
	var game_over := _require_node(main, "GameOver")
	var rank_label := _require_label(main, "YourRankLabel")
	var list := _require_node(main, "LeaderboardList")
	if game_over == null or rank_label == null or list == null:
		return false
	if not game_over.visible:
		return _fail("case 2: GameOver should be visible")
	var expected := "Rank %d of %d · Personal best!" % [rank, total]
	if rank_label.text != expected:
		return _fail("case 2: YourRankLabel '%s' expected '%s'" % [rank_label.text, expected])
	var highlighted := await _wait_highlighted_row(list, "Pat", 700, 3500)
	if highlighted == null:
		return _fail("case 2: player row not highlighted")
	if not highlighted.text.begins_with("▸"):
		return _fail("case 2: highlighted row should start with ▸")
	_cases_passed += 1
	print("LEADERBOARD case 2 pass")
	return true


func _case_3_second_game_300(main: Node) -> bool:
	print("LEADERBOARD case 3 play 300")
	_game.restart()
	await process_frame
	await process_frame
	_reset_wait_flags()
	_game.add_score(300)
	for _i in 3:
		_game.on_ball_drained()
		await process_frame
		await process_frame
	if not await _wait_flag("_got_submit", 3500):
		return _fail("case 3: submitted did not arrive")
	if bool(_last_submit.get("is_personal_best", true)):
		return _fail("case 3: expected is_personal_best false, got %s" % _last_submit)
	if int(_last_submit.get("best", 0)) != 700:
		return _fail("case 3: expected best 700, got %s" % _last_submit)
	var rank := int(_last_submit.get("rank", 0))
	var total := int(_last_submit.get("total_players", 0))
	var rank_label := _require_label(main, "YourRankLabel")
	if rank_label == null:
		return false
	_got_board = false
	if not await _wait_flag("_got_board", 3500):
		return _fail("case 3: board after submit did not arrive")
	await process_frame
	var expected := "Rank %d of %d" % [rank, total]
	if rank_label.text != expected:
		return _fail("case 3: YourRankLabel '%s' expected '%s'" % [rank_label.text, expected])
	if rank_label.text.contains("Personal best"):
		return _fail("case 3: rank line should not say personal best")
	_cases_passed += 1
	print("LEADERBOARD case 3 pass")
	return true


func _case_4_unreachable(main: Node) -> bool:
	print("LEADERBOARD case 4 unreachable")
	OS.set_environment("SQUISH_LEADERBOARD_URL", CLOSED_URL)
	_leaderboard._submitted_tokens[_leaderboard._submit_token] = true
	_reset_wait_flags()
	_leaderboard.fetch_top(5)
	if not await _wait_flag("_got_offline", 3500):
		OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
		return _fail("case 4: offline did not arrive within 3.5s")
	if _last_offline.is_empty():
		OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
		return _fail("case 4: offline reason empty")
	var title := _require_node(main, "Title")
	var game_over := _require_node(main, "GameOver")
	if title == null or game_over == null:
		OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
		return false
	_reset_wait_flags()
	_game.restart()
	await process_frame
	_game.add_score(50)
	for _i in 3:
		_game.on_ball_drained()
		await process_frame
	if not game_over.visible:
		OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
		return _fail("case 4: GameOver should still show while offline")
	await _wait_flag("_got_offline", 3500)
	var offline_label := _require_label(main, "OfflineLabel")
	if offline_label == null:
		OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
		return false
	if not offline_label.visible or offline_label.text != "Leaderboard offline":
		OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
		return _fail("case 4: OfflineLabel should be quiet 'Leaderboard offline'")
	if _got_submit:
		OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
		return _fail("case 4: submit should not succeed against a closed port")
	_game.restart()
	await process_frame
	await process_frame
	if game_over.visible:
		OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
		return _fail("case 4: restart should hide GameOver")
	if _game.state != _game.READY:
		OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
		return _fail("case 4: restart left state %s" % _game.state)
	# Cancel the 5 s retry so later cases do not POST after we restore the URL.
	_leaderboard._submitted_tokens[_leaderboard._submit_token] = true
	OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
	_cases_passed += 1
	print("LEADERBOARD case 4 pass reason=%s" % _last_offline)
	return true


func _case_5_empty_name_no_post(main: Node) -> bool:
	print("LEADERBOARD case 5 empty name")
	var before := await _api_get_board()
	if before.is_empty():
		return _fail("case 5: could not GET board before")
	var before_total := int(before.get("total_players", -1))
	var before_entries: Array = before.get("entries", [])
	_profile.call("set_name", "")
	if String(_profile.player_name) != "":
		return _fail("case 5: name did not clear")
	_reset_wait_flags()
	_game.restart()
	await process_frame
	_game.add_score(400)
	for _i in 3:
		_game.on_ball_drained()
		await process_frame
	# Give a late POST a moment; none should happen.
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 800:
		await process_frame
	if _got_submit:
		return _fail("case 5: submitted fired with empty name")
	var after := await _api_get_board()
	if after.is_empty():
		return _fail("case 5: could not GET board after")
	if int(after.get("total_players", -2)) != before_total:
		return _fail("case 5: total_players changed %s → %s" % [before_total, after.get("total_players")])
	var after_entries: Array = after.get("entries", [])
	if after_entries.size() != before_entries.size():
		return _fail("case 5: entry count changed")
	_cases_passed += 1
	print("LEADERBOARD case 5 pass")
	return true


func _case_6_deploy_restart(main: Node) -> bool:
	print("LEADERBOARD case 6 deploy bounce")
	_profile.call("set_name", "Pat")
	_kill_local_server()
	var down := false
	var down_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - down_start < 3000:
		if not await _healthz_ok(LOCAL_URL):
			down = true
			break
		await _wait_msec(100)
	if not down:
		return _fail("case 6: server still answering /healthz after kill")
	_reset_wait_flags()
	_leaderboard.fetch_top(5)
	if not await _wait_flag("_got_offline", 3500):
		return _fail("case 6: expected offline while server is down (board=%s offline=%s)" % [_got_board, _got_offline])
	if _start_local_server() < 0:
		return _fail("case 6: failed to restart local server")
	if not await _wait_healthz(10000):
		return _fail("case 6: server did not return after restart")
	_reset_wait_flags()
	_leaderboard.fetch_top(5)
	if not await _wait_flag("_got_board", 3500):
		return _fail("case 6: fetch after restart did not succeed")
	var title := _require_node(main, "Title")
	if title == null:
		return false
	_cases_passed += 1
	print("LEADERBOARD case 6 pass")
	return true


func _case_7_two_device_players(main: Node) -> bool:
	print("LEADERBOARD case 7 two players on one device")
	OS.set_environment("SQUISH_LEADERBOARD_URL", LOCAL_URL)
	_game.restart()
	await process_frame
	_profile.call("set_name", "Dad")
	await process_frame
	var dad_id := String(_profile.player_id)
	if dad_id.is_empty():
		return _fail("case 7: Dad has no player_id")
	_reset_wait_flags()
	_game.add_score(811)
	for _i in 3:
		_game.on_ball_drained()
		await process_frame
		await process_frame
	if not await _wait_flag("_got_submit", 3500):
		return _fail("case 7: Dad submit did not arrive")
	_profile.call("set_name", "Natasha")
	await process_frame
	var natasha_id := String(_profile.player_id)
	if natasha_id.is_empty() or natasha_id == dad_id:
		return _fail("case 7: Natasha player_id should differ from Dad (%s vs %s)" % [natasha_id, dad_id])
	_game.restart()
	await process_frame
	_reset_wait_flags()
	_game.add_score(822)
	for _i in 3:
		_game.on_ball_drained()
		await process_frame
		await process_frame
	if not await _wait_flag("_got_submit", 3500):
		return _fail("case 7: Natasha submit did not arrive")
	var board := await _api_get_board()
	if board.is_empty():
		return _fail("case 7: could not GET board")
	var entries: Array = board.get("entries", [])
	var dad_row: Dictionary = {}
	var natasha_row: Dictionary = {}
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var pid := String(entry.get("player_id", ""))
		var pname := String(entry.get("name", ""))
		if pid == dad_id or pname == "Dad":
			dad_row = entry
		if pid == natasha_id or pname == "Natasha":
			natasha_row = entry
	if dad_row.is_empty() or natasha_row.is_empty():
		return _fail("case 7: board missing Dad/Natasha rows: %s" % entries)
	if String(dad_row.get("player_id", "")) == String(natasha_row.get("player_id", "")):
		return _fail("case 7: Dad and Natasha posted the same player_id")
	if String(dad_row.get("name", "")) != "Dad":
		return _fail("case 7: Dad row name was '%s'" % dad_row.get("name", ""))
	if String(natasha_row.get("name", "")) != "Natasha":
		return _fail("case 7: Natasha row name was '%s'" % natasha_row.get("name", ""))
	if int(dad_row.get("score", 0)) != 811:
		return _fail("case 7: Dad score should be 811, got %s" % dad_row)
	if int(natasha_row.get("score", 0)) != 822:
		return _fail("case 7: Natasha score should be 822, got %s" % natasha_row)
	_cases_passed += 1
	print("LEADERBOARD case 7 pass dad=%s natasha=%s" % [dad_id, natasha_id])
	return true


func _wait_highlighted_row(list: Node, player_name: String, score: int, ms: int) -> Label:
	var start := Time.get_ticks_msec()
	var found: Label = null
	while Time.get_ticks_msec() - start < ms:
		found = _find_highlighted_row(list)
		if found != null and found.text.contains(player_name) and found.text.contains(str(score)):
			return found
		await process_frame
	return _find_highlighted_row(list)


func _find_highlighted_row(list: Node) -> Label:
	for child in list.get_children():
		if child is Label and String((child as Label).text).begins_with("▸"):
			return child as Label
	return null


func _seed_id(i: int) -> String:
	return "00000000-0000-4000-8000-%012d" % i


func _reset_wait_flags() -> void:
	_got_submit = false
	_got_offline = false
	_got_board = false
	_last_offline = ""
	_last_submit = {}


func _wait_flag(flag_name: String, ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		if bool(get(flag_name)):
			return true
		await process_frame
	return bool(get(flag_name))


func _wait_msec(ms: int) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		await process_frame


func _healthz_ok(base: String) -> bool:
	var output: Array = []
	var code := OS.execute("/usr/bin/curl", PackedStringArray([
		"-sf", "--max-time", "1", base + "/healthz",
	]), output)
	return code == 0


func _wait_healthz(ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		if await _healthz_ok(LOCAL_URL):
			return true
		await _wait_msec(250)
	return false


func _api_post(player_id: String, player_name: String, score: int) -> bool:
	var body := JSON.stringify({
		"player_id": player_id,
		"name": player_name,
		"score": score,
		"client": CLIENT,
	})
	var got := await _http(HTTPClient.METHOD_POST, LOCAL_URL + "/v1/scores", body, "devkey")
	return bool(got.get("ok", false)) and int(got.get("code", 0)) == 201


func _api_get_board() -> Dictionary:
	var got := await _http(HTTPClient.METHOD_GET, LOCAL_URL + "/v1/leaderboard?limit=50", "", "")
	if not bool(got.get("ok", false)):
		return {}
	var parsed: Variant = got.get("parsed")
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _http(method: int, url: String, body: String, key: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 3.0
	root.add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not key.is_empty():
		headers.append("X-Squish-Key: %s" % key)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0}
	var completed: Array = await http.request_completed
	http.queue_free()
	var result := int(completed[0])
	var code := int(completed[1])
	var raw: PackedByteArray = completed[3]
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	return {
		"ok": result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300,
		"code": code,
		"parsed": parsed,
	}


func _kill_local_server() -> void:
	var pid := _read_server_pid()
	if pid.is_empty():
		print("LEADERBOARD kill: no pid file")
		return
	var output: Array = []
	OS.execute("/bin/kill", PackedStringArray(["-9", pid]), output, true)
	print("LEADERBOARD kill pid=%s out=%s" % [pid, str(output)])


func _start_local_server() -> int:
	var root_path := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var pid := OS.create_process("/bin/bash", PackedStringArray([
		"-lc",
		"cd \"%s/server\" && exec env DB_PATH=:memory: SQUISH_KEY=devkey PORT=8787 node --no-warnings=ExperimentalWarning src/index.js >/tmp/squish-lb-test.log 2>&1" % root_path,
	]))
	if pid > 0:
		var file := FileAccess.open("/tmp/squish-lb-test.pid", FileAccess.WRITE)
		if file != null:
			file.store_string(str(pid))
	return pid


func _read_server_pid() -> String:
	if not FileAccess.file_exists("/tmp/squish-lb-test.pid"):
		return ""
	return FileAccess.get_file_as_string("/tmp/squish-lb-test.pid").strip_edges()


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


func _fail(message: String) -> bool:
	print("LEADERBOARD FAIL %s" % message)
	quit(1)
	return false
