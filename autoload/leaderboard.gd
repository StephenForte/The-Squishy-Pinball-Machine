extends Node

## Autoload Leaderboard. Posts on game over and caches the board (D-026 / D-028).
## HTTP is always async: callers never wait. Offline is a quiet signal, not an error.

signal board_updated(entries: Array, total_players: int)
signal submitted(result: Dictionary)
signal offline(reason: String)
signal submit_attempted(token: int, attempt: int)
signal profile_synced(profile: Dictionary)

const BASE_URL := "https://squish-leaderboard.onrender.com"
const KEY := "a419f5979f6891504b3af89a20e13125"
const CLIENT := "squish/1.0"
const REQUEST_TIMEOUT := 3.0
## Runner sentinel (tests/run_all.sh): every suite except leaderboard_test
## points here. Profile name/avatar changes must not enqueue doomed HTTP.
const _CLOSED_SENTINEL_URL := "http://127.0.0.1:1"

var retry_delays_sec: Array = [5.0, 10.0, 20.0, 30.0]
var submit_attempts: Dictionary = {}

var last_entries: Array = []
var last_total_players: int = 0

var _submit_token: int = 0
var _submitted_tokens: Dictionary = {}
## token → {score: int, in_flight: bool, retry_pending: bool}
var _submit_state: Dictionary = {}
var _hooked_titles: Dictionary = {}
var _fetch_gen: int = 0
var _profile_push_count: int = 0
## Set while adopting a cloud avatar so set_avatar does not fire a PUT (D-038).
var _suppress_profile_push: bool = false


func _ready() -> void:
	_connect_game()
	_connect_profile()
	var tree := get_tree()
	if tree != null and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	call_deferred("_bind_existing_tree")
	call_deferred("_boot_restore_profile")


func push_profile() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	var player_name := String(profile.player_name)
	if player_name.is_empty():
		return
	var player_id := String(profile.player_id)
	if player_id.is_empty():
		return
	if _profile_http_skipped():
		return
	_profile_push_count += 1
	var body := JSON.stringify({
		"player_id": player_id,
		"name": player_name,
		"avatar": String(profile.avatar_id),
		"client": CLIENT,
	})
	var url := "%s/v1/profile" % _base_url()
	_http_request(HTTPClient.METHOD_PUT, url, body, _on_push_profile_finished, true)


func fetch_profile(player_id: String, from_boot: bool = false) -> void:
	if player_id.is_empty():
		return
	if _profile_http_skipped():
		return
	var url := "%s/v1/profile?player_id=%s" % [_base_url(), player_id]
	_http_request(HTTPClient.METHOD_GET, url, "", _on_fetch_profile_finished.bind(player_id, from_boot))


func fetch_top(limit: int) -> void:
	_fetch_gen += 1
	var gen := _fetch_gen
	var clamped := clampi(limit, 1, 50)
	var url := "%s/v1/leaderboard?limit=%d" % [_base_url(), clamped]
	_http_request(HTTPClient.METHOD_GET, url, "", _on_fetch_finished.bind(gen))


func submit(score: int) -> void:
	_start_new_submit(score)


func _connect_game() -> void:
	var game := get_node_or_null("/root/Game")
	if game != null and game.has_signal("game_over") and not game.game_over.is_connected(_on_game_over):
		game.game_over.connect(_on_game_over)


func _connect_profile() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if profile.has_signal("name_changed") and not profile.name_changed.is_connected(_on_profile_name_changed):
		profile.name_changed.connect(_on_profile_name_changed)
	if profile.has_signal("avatar_changed") and not profile.avatar_changed.is_connected(_on_profile_avatar_changed):
		profile.avatar_changed.connect(_on_profile_avatar_changed)


func _on_profile_name_changed(_name: String) -> void:
	if _suppress_profile_push:
		return
	push_profile()


func _on_profile_avatar_changed(_avatar_id: String) -> void:
	if _suppress_profile_push:
		return
	push_profile()


func _boot_restore_profile() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if String(profile.player_name).is_empty():
		return
	var player_id := String(profile.player_id)
	if player_id.is_empty():
		return
	fetch_profile(player_id, true)


func _profile_http_skipped() -> bool:
	return _base_url() == _CLOSED_SENTINEL_URL


func _on_push_profile_finished(_ok: bool, _code: int, _parsed: Variant, _reason: String) -> void:
	# D-037: fire-and-forget. Failures are dropped; not enrolled in D-034.
	return


func _on_fetch_profile_finished(ok: bool, code: int, parsed: Variant, _reason: String, requested_id: String, from_boot: bool) -> void:
	# D-038: 404 is a real "no cloud profile". Check it before `not ok` —
	# `_on_http_completed` reports every non-2xx as ok == false, including 404.
	# Transport failure is code 0, never a 404; do nothing at all.
	if code == 404:
		if from_boot:
			_reconcile_boot_missing_cloud(requested_id)
		return
	if not ok:
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	_adopt_cloud_avatar_if_local_empty(data)
	if from_boot:
		_reconcile_boot_divergence(data)
	profile_synced.emit(data)


func _reconcile_boot_missing_cloud(requested_id: String) -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if requested_id.is_empty() or String(profile.player_id) != requested_id:
		return
	if String(profile.player_name).is_empty():
		return
	if String(profile.avatar_id).is_empty():
		return
	push_profile()


func _reconcile_boot_divergence(data: Dictionary) -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if String(data.get("player_id", "")) != String(profile.player_id):
		return
	if String(profile.player_name).is_empty():
		return
	var local_avatar := String(profile.avatar_id)
	if local_avatar.is_empty():
		return
	if local_avatar == String(data.get("avatar", "")):
		return
	push_profile()


func _adopt_cloud_avatar_if_local_empty(data: Dictionary) -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	# Device wins: adopt only if this response is still for the current player
	# and the local avatar is empty *now*, not when the request went out (D-037).
	if String(data.get("player_id", "")) != String(profile.player_id):
		return
	if String(profile.player_name).is_empty():
		return
	if not String(profile.avatar_id).is_empty():
		return
	var server_avatar := String(data.get("avatar", ""))
	if server_avatar.is_empty():
		return
	# Adopting must not PUT the value the cloud already has (D-038 gap-fill).
	_suppress_profile_push = true
	profile.set_avatar(server_avatar)
	_suppress_profile_push = false


func _bind_existing_tree() -> void:
	_connect_game()
	var title := _find_title()
	if title != null:
		_hook_title(title)


func _on_node_added(node: Node) -> void:
	if node == null:
		return
	if node.name == "Title":
		_hook_title(node)
		return
	var nested := node.find_child("Title", false, false)
	if nested != null:
		_hook_title(nested)


func _find_title() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.find_child("Title", true, false)


func _hook_title(title: Node) -> void:
	if title == null or not is_instance_valid(title):
		return
	var id := title.get_instance_id()
	if _hooked_titles.has(id):
		return
	_hooked_titles[id] = true
	if title.has_signal("visibility_changed") and not title.visibility_changed.is_connected(_on_title_visibility_changed):
		title.visibility_changed.connect(_on_title_visibility_changed.bind(title))
	if bool(title.visible):
		fetch_top(5)


func _on_title_visibility_changed(title: Node) -> void:
	if title == null or not is_instance_valid(title):
		return
	if bool(title.visible):
		fetch_top(5)


func _on_game_over(final_score: int, _is_high_score: bool) -> void:
	fetch_top(10)
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if String(profile.player_name).is_empty():
		return
	if final_score <= 0:
		return
	_start_new_submit(final_score)


func _start_new_submit(score: int) -> void:
	_submit_token += 1
	var token := _submit_token
	_submit_state[token] = {
		"score": score,
		"in_flight": false,
		"retry_pending": false,
	}
	_begin_submit(token)


func _begin_submit(token: int) -> void:
	if _submitted_tokens.has(token):
		return
	var state: Dictionary = _submit_state.get(token, {})
	if state.is_empty():
		return
	if bool(state.get("in_flight", false)):
		return
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	var player_name := String(profile.player_name)
	var player_id := String(profile.player_id)
	if player_name.is_empty() or player_id.is_empty():
		return
	state["in_flight"] = true
	state["retry_pending"] = false
	var score := int(state.get("score", 0))
	_record_attempt(token)
	var body := JSON.stringify({
		"player_id": player_id,
		"name": player_name,
		"score": score,
		"client": CLIENT,
	})
	var url := "%s/v1/scores" % _base_url()
	_http_request(HTTPClient.METHOD_POST, url, body, _on_submit_finished.bind(token), true)


func _record_attempt(token: int) -> void:
	var n := int(submit_attempts.get(token, 0)) + 1
	submit_attempts[token] = n
	submit_attempted.emit(token, n)


func _schedule_retry(token: int) -> void:
	if _submitted_tokens.has(token):
		return
	var state: Dictionary = _submit_state.get(token, {})
	if state.is_empty() or bool(state.get("retry_pending", false)):
		return
	var attempts := int(submit_attempts.get(token, 0))
	if attempts > retry_delays_sec.size():
		return
	if attempts < 1:
		return
	var tree := get_tree()
	if tree == null:
		return
	var delay := float(retry_delays_sec[attempts - 1])
	state["retry_pending"] = true
	var timer := tree.create_timer(delay)
	timer.timeout.connect(_on_retry_timeout.bind(token), CONNECT_ONE_SHOT)


func _on_retry_timeout(token: int) -> void:
	if _submitted_tokens.has(token):
		return
	var state: Dictionary = _submit_state.get(token, {})
	if not state.is_empty():
		state["retry_pending"] = false
	_begin_submit(token)


func _on_fetch_finished(ok: bool, code: int, parsed: Variant, reason: String, gen: int) -> void:
	if gen != _fetch_gen:
		return
	if not ok:
		offline.emit(reason)
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		offline.emit("bad_json")
		return
	var data: Dictionary = parsed
	var entries: Array = data.get("entries", [])
	if typeof(entries) != TYPE_ARRAY:
		offline.emit("bad_json")
		return
	last_entries = entries.duplicate(true)
	last_total_players = int(data.get("total_players", last_entries.size()))
	board_updated.emit(last_entries, last_total_players)


func _on_submit_finished(ok: bool, code: int, parsed: Variant, reason: String, token: int) -> void:
	var state: Dictionary = _submit_state.get(token, {})
	if not state.is_empty():
		state["in_flight"] = false
	if ok and code == 201 and typeof(parsed) == TYPE_DICTIONARY:
		_submitted_tokens[token] = true
		if token == _submit_token:
			submitted.emit(parsed)
		fetch_top(10)
		return
	# Only the latest token talks to GameOver (same rule as submitted). A late
	# failure from an older game must not paint "Leaderboard offline" over a
	# score that already landed.
	if token == _submit_token:
		if not ok:
			offline.emit(reason)
		else:
			offline.emit("http_%d" % code if code > 0 else reason)
	if _is_retryable(code):
		_schedule_retry(token)


func _is_retryable(code: int) -> bool:
	if code == 400 or code == 401 or code == 404:
		return false
	if code >= 400 and code < 500 and code != 429:
		return false
	return true


func _base_url() -> String:
	var env := OS.get_environment("SQUISH_LEADERBOARD_URL").strip_edges()
	if env.is_empty():
		env = BASE_URL
	return env.rstrip("/")


func _write_key() -> String:
	var env := OS.get_environment("SQUISH_LEADERBOARD_KEY").strip_edges()
	if env.is_empty():
		return KEY
	return env


func _http_request(method: int, url: String, body: String, callback: Callable, with_key: bool = false) -> void:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if with_key:
		headers.append("X-Squish-Key: %s" % _write_key())
	var state := {"done": false, "http": http}
	http.request_completed.connect(
		_on_http_completed.bind(callback, state),
		CONNECT_ONE_SHOT
	)
	var tree := get_tree()
	if tree != null and REQUEST_TIMEOUT > 0.0:
		var watchdog := tree.create_timer(REQUEST_TIMEOUT + 0.25)
		watchdog.timeout.connect(func() -> void:
			_on_http_watchdog(callback, state)
		, CONNECT_ONE_SHOT)
	var err := http.request(url, headers, method, body)
	if err != OK:
		state.done = true
		http.queue_free()
		callback.call(false, 0, null, "request_failed")


func _on_http_watchdog(callback: Callable, state: Dictionary) -> void:
	if bool(state.get("done", false)):
		return
	state.done = true
	var http: HTTPRequest = state.get("http") as HTTPRequest
	if http != null and is_instance_valid(http):
		http.cancel_request()
		http.queue_free()
	callback.call(false, 0, null, "timeout")


func _on_http_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	callback: Callable,
	state: Dictionary
) -> void:
	var http: HTTPRequest = state.get("http") as HTTPRequest
	if bool(state.get("done", false)):
		if http != null and is_instance_valid(http):
			http.queue_free()
		return
	state.done = true
	if http != null and is_instance_valid(http):
		http.queue_free()
	var reason := _result_reason(result, response_code)
	if result != HTTPRequest.RESULT_SUCCESS:
		callback.call(false, response_code, null, reason)
		return
	if response_code < 200 or response_code >= 300:
		callback.call(false, response_code, null, reason)
		return
	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else {}
	callback.call(true, response_code, parsed, "")


func _result_reason(result: int, response_code: int) -> String:
	if result == HTTPRequest.RESULT_TIMEOUT:
		return "timeout"
	if result == HTTPRequest.RESULT_CANT_CONNECT or result == HTTPRequest.RESULT_CANT_RESOLVE:
		return "unreachable"
	if result == HTTPRequest.RESULT_CONNECTION_ERROR or result == HTTPRequest.RESULT_NO_RESPONSE:
		return "no_network"
	if result != HTTPRequest.RESULT_SUCCESS:
		return "request_failed"
	if response_code >= 500:
		return "http_%d" % response_code
	if response_code >= 400:
		return "http_%d" % response_code
	return "offline"
