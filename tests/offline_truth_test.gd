extends SceneTree

## Fetch failures say which failure they were, and a 200 that arrives is not
## left looking offline. Callbacks are driven directly: under --fixed-fps a
## real delay trips the watchdog in a fraction of a second of wall time.

var _lb: Node
var _game_over: Node
var _title: Node
var _top: Label
var _offline: Label
var _list: Node
var _offline_count := 0
var _late_calls: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("OFFLINE start")
	var dir := OS.get_user_data_dir()
	if not dir.ends_with("SquishyPinballTest"):
		_fail("running against real user dir %s" % dir)
		return
	_lb = root.get_node_or_null("Leaderboard")
	if _lb == null:
		_fail("Leaderboard autoload missing")
		return
	if not _lb.offline.is_connected(_on_offline_signal):
		_lb.offline.connect(_on_offline_signal)
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
	# The title fetch started in _ready. Retire it so a late closed-port
	# callback cannot paint offline over the cases below.
	_lb._fetch_gen = 100
	_game_over = main.get_node_or_null("GameOver")
	_title = main.get_node_or_null("Title")
	if _game_over == null or _title == null:
		_fail("GameOver or Title missing")
		return
	_top = _title.get_node_or_null("TopFiveLabel") as Label
	_offline = _game_over.get_node_or_null("OfflineLabel") as Label
	_list = _game_over.get_node_or_null("LeaderboardList")
	if _top == null or _offline == null or _list == null:
		_fail("board labels missing")
		return
	_game_over.visible = true
	for _i in 8:
		await process_frame
	_offline_count = 0

	if not _case_distinct_lines():
		return
	if not _case_success_fills_and_hides():
		return
	if not _case_late_timeout_keeps_success():
		return
	if not _case_superseded_fetch_is_ignored():
		return
	if not _case_failure_keeps_cached_board():
		return
	if not _case_late_http_success_wins():
		return
	if not _case_submit_does_not_accept_late_body():
		return
	if not _case_empty_success_is_not_offline():
		return

	print("OFFLINE PASS cases=8")
	quit(0)


func _on_offline_signal(_reason: String) -> void:
	_offline_count += 1


func _on_late_call(ok: bool, code: int, _parsed: Variant, reason: String) -> void:
	_late_calls.append({"ok": ok, "code": code, "reason": reason})


func _case_distinct_lines() -> bool:
	print("OFFLINE case 1 distinct lines")
	var reasons: PackedStringArray = PackedStringArray([
		"timeout", "unreachable", "http_500", "bad_json", "request_failed",
	])
	var seen: Dictionary = {}
	for reason in reasons:
		var line := String(_lb.offline_line(reason))
		if line == "Leaderboard offline":
			return _fail("case 1: '%s' still uses the generic sentence" % reason)
		if seen.has(line):
			return _fail("case 1: '%s' and '%s' share '%s'" % [reason, seen[line], line])
		seen[line] = reason
		_game_over._on_offline(reason)
		if not _offline.visible or _offline.text != line:
			return _fail("case 1: game over showed '%s' for %s" % [_offline.text, reason])
		_title._on_offline(reason)
		if _top.text != line:
			return _fail("case 1: title showed '%s' for %s" % [_top.text, reason])
	var denied := String(_lb.offline_line("http_401"))
	var broken := String(_lb.offline_line("http_500"))
	if denied == broken:
		return _fail("case 1: 401 and 500 render the same")
	print("OFFLINE case 1 pass")
	return true


func _case_success_fills_and_hides() -> bool:
	print("OFFLINE case 2 success fills and hides")
	var before := _offline_count
	var gen := _next_gen()
	_lb._on_fetch_finished(true, 200, _board("Nia", 40), "", gen)
	if _offline_count != before:
		return _fail("case 2: success emitted offline")
	if not _assert_showing("Nia", "case 2"):
		return false
	print("OFFLINE case 2 pass")
	return true


func _case_late_timeout_keeps_success() -> bool:
	print("OFFLINE case 3 late timeout after success")
	var before := _offline_count
	var gen := int(_lb._fetch_gen)
	_lb._on_fetch_finished(false, 0, null, "timeout", gen)
	if _offline_count != before:
		return _fail("case 3: late timeout re-reported offline")
	if not _assert_showing("Nia", "case 3"):
		return false
	print("OFFLINE case 3 pass")
	return true


func _case_superseded_fetch_is_ignored() -> bool:
	print("OFFLINE case 4 superseded fetch")
	var current := _next_gen()
	_lb._on_fetch_finished(true, 200, _board("Bea", 70), "", current)
	if not _assert_showing("Bea", "case 4 setup"):
		return false
	var before := _offline_count
	var stale := current - 1
	_lb._on_fetch_finished(true, 200, _board("Zoe", 1), "", stale)
	_lb._on_fetch_finished(false, 0, null, "timeout", stale)
	if _offline_count != before:
		return _fail("case 4: stale fetch reported offline")
	if not _assert_showing("Bea", "case 4"):
		return false
	if _list_text().contains("Zoe") or _top.text.contains("Zoe"):
		return _fail("case 4: stale success overwrote Bea")
	print("OFFLINE case 4 pass")
	return true


func _case_failure_keeps_cached_board() -> bool:
	print("OFFLINE case 5 failure keeps cache")
	var gen := _next_gen()
	var before := _offline_count
	_lb._on_fetch_finished(false, 0, null, "unreachable", gen)
	if _offline_count != before + 1:
		return _fail("case 5: unreachable did not report offline")
	var line := String(_lb.offline_line("unreachable"))
	if not _offline.visible or _offline.text != line:
		return _fail("case 5: game over '%s' visible=%s" % [_offline.text, _offline.visible])
	if not _list_text().contains("Bea"):
		return _fail("case 5: failure blanked the game-over list '%s'" % _list_text())
	if not _top.text.contains("Bea") or not _top.text.contains(line):
		return _fail("case 5: title '%s'" % _top.text)
	if _top.text.contains("Zoe"):
		return _fail("case 5: title picked up a stale name")
	print("OFFLINE case 5 pass")
	return true


func _case_late_http_success_wins() -> bool:
	print("OFFLINE case 6 late http success")
	var gen := _next_gen()
	var cb: Callable = _lb._on_fetch_finished.bind(gen)
	var state := {"done": false, "http": null}
	_lb._on_http_watchdog(cb, state)
	if not _offline.visible:
		return _fail("case 6: watchdog did not show offline")
	var body := JSON.stringify(_board("Cleo", 90)).to_utf8_buffer()
	_lb._on_http_completed(
		HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body, cb, state, true
	)
	if not _assert_showing("Cleo", "case 6"):
		return false
	if _list_text().contains("Bea"):
		return _fail("case 6: list kept the previous board")
	if (_lb.last_entries as Array).is_empty():
		return _fail("case 6: 200 left last_entries empty")
	print("OFFLINE case 6 pass")
	return true


func _case_submit_does_not_accept_late_body() -> bool:
	print("OFFLINE case 7 submit ignores a late body")
	var entries_before := (_lb.last_entries as Array).duplicate(true)
	_late_calls.clear()
	var state := {"done": false, "http": null}
	_lb._on_http_watchdog(_on_late_call, state)
	var body := JSON.stringify(_board("Nope", 1)).to_utf8_buffer()
	_lb._on_http_completed(
		HTTPRequest.RESULT_SUCCESS, 201, PackedStringArray(), body, _on_late_call, state, false
	)
	if _late_calls.size() != 1:
		return _fail("case 7: late body changed callback count to %d" % _late_calls.size())
	var first: Dictionary = _late_calls[0]
	if bool(first.get("ok", true)) or String(first.get("reason", "")) != "timeout":
		return _fail("case 7: first callback was %s" % str(first))
	if str(_lb.last_entries) != str(entries_before):
		return _fail("case 7: late body changed the board")
	print("OFFLINE case 7 pass")
	return true


func _case_empty_success_is_not_offline() -> bool:
	print("OFFLINE case 8 empty success agrees")
	var gen := _next_gen()
	_lb._on_fetch_finished(true, 200, {"entries": [], "total_players": 0}, "", gen)
	if _offline.visible:
		return _fail("case 8: empty board left offline visible '%s'" % _offline.text)
	if _list.get_child_count() != 0:
		return _fail("case 8: empty board left %d rows" % _list.get_child_count())
	if _top.text.to_lower().contains("leaderboard") or _top.text.to_lower().contains("offline"):
		return _fail("case 8: title '%s'" % _top.text)
	var before := _offline_count
	_lb._on_fetch_finished(false, 0, null, "timeout", gen)
	if _offline_count != before or _offline.visible:
		return _fail("case 8: late timeout after an empty 200 showed offline")
	print("OFFLINE case 8 pass")
	return true


func _assert_showing(player_name: String, where: String) -> bool:
	if _offline.visible:
		return _fail("%s: offline visible '%s' while %s is on the board" % [where, _offline.text, player_name])
	if not _list_text().contains(player_name):
		return _fail("%s: list missing %s ('%s')" % [where, player_name, _list_text()])
	if _list.get_child_count() < 1:
		return _fail("%s: list empty after a fetch with entries" % where)
	if not _top.text.contains(player_name):
		return _fail("%s: title missing %s ('%s')" % [where, player_name, _top.text])
	if _top.text.to_lower().contains("leaderboard"):
		return _fail("%s: title still has a failure line '%s'" % [where, _top.text])
	return true


func _list_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for child in _list.get_children():
		if child is Label:
			parts.append(String((child as Label).text))
	return "\n".join(parts)


func _board(player_name: String, score: int) -> Dictionary:
	return {
		"entries": [{
			"rank": 1,
			"name": player_name,
			"score": score,
			"player_id": "00000000-0000-4000-8000-000000000099",
		}],
		"total_players": 1,
	}


func _next_gen() -> int:
	_lb._fetch_gen = int(_lb._fetch_gen) + 1
	return int(_lb._fetch_gen)


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _fail(message: String) -> bool:
	print("OFFLINE FAIL %s" % message)
	quit(1)
	return false
