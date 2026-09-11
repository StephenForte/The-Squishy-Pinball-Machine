extends Node

## Autoload Leaderboard. Posts on game over and caches the board (D-026 / D-028).
## HTTP is always async: callers never wait. Offline is a quiet signal, not an error.

signal board_updated(entries: Array, total_players: int)
signal submitted(result: Dictionary)
signal offline(reason: String)
signal submit_attempted(token: int, attempt: int)

const BASE_URL := "https://squish-leaderboard.onrender.com"
const KEY := "a419f5979f6891504b3af89a20e13125"
const CLIENT := "squish/1.0"
const REQUEST_TIMEOUT := 3.0

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


func _ready() -> void:
	_connect_game()
	var tree := get_tree()
	if tree != null and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	call_deferred("_bind_existing_tree")


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
