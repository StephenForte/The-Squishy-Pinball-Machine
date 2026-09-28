extends Node

## Autoload Leaderboard. Posts on game over and caches the board (D-026 / D-028).
## HTTP is always async: callers never wait. Offline is a quiet signal, not an error.

signal board_updated(entries: Array, total_players: int)
signal submitted(result: Dictionary)
signal offline(reason: String)
signal submit_attempted(token: int, attempt: int)
signal profile_synced(profile: Dictionary)
signal restore_finished(ok: bool, reason: String)
## generation, ok, info. Success info is the adopted player_id, name, avatar.
## Failure info is code, reason, error — and nothing was adopted.
signal name_resolved(generation: int, ok: bool, info: Dictionary)
## generation, info. `answered` is false when the server could not be read.
## `held` is true only when that name already belongs to a player.
## `queried` is the raw name this call asked about.
signal name_lookup(generation: int, info: Dictionary)
## True after this boot's gap-fill PUT, or a score POST, returned 409
## name_taken for the id this device still holds (D-058, T43).
## Runtime only: recomputed from the next boot, never written to the save.
signal identity_unconfirmed_changed(unconfirmed: bool)
## A score POST was answered 409 name_taken for the id still on the device.
## `token` is that submit. Game over opens the invite only when the token
## is the game currently on screen.
signal refused_score(token: int)

const BASE_URL := "https://squish-leaderboard.onrender.com"
const KEY := "a419f5979f6891504b3af89a20e13125"
const CLIENT := "squish/1.0"
const REQUEST_TIMEOUT := 3.0
## Runner sentinel (tests/run_all.sh): every suite except leaderboard_test
## points here. Profile name/avatar changes must not enqueue doomed HTTP.
const _CLOSED_SENTINEL_URL := "http://127.0.0.1:1"

var retry_delays_sec: Array = [5.0, 10.0, 20.0, 30.0]
var submit_attempts: Dictionary = {}
## GET /v1/leaderboard/me requests actually sent. Stays 0 when the closed
## sentinel skips HTTP and when the current player has no name (D-057).
var best_fetch_count: int = 0
## This process has seen a profile PUT answered 409 name_taken.
var refused_name_count: int = 0
## player_id of each POST /v1/scores actually sent, including a 409.
var score_post_ids: Array = []
## D-058. The device id is unknown and its saved name is held by someone else.
var identity_unconfirmed: bool = false

var last_entries: Array = []
var last_total_players: int = 0

var _submit_token: int = 0
## Bumped once per game_over, including a game that does not submit.
## `_game_over_submit_token` is that game's submit, or -1 when none started.
var _game_over_epoch: int = 0
var _game_over_submit_token: int = -1
var _submitted_tokens: Dictionary = {}
## token → {score: int, in_flight: bool, retry_pending: bool}
var _submit_state: Dictionary = {}
var _hooked_titles: Dictionary = {}
var _fetch_gen: int = 0
## Generation that already applied a readable board. A later callback for
## that same generation (watchdog timeout after the body, or the reverse)
## must not paint offline over it.
var _fetch_ok_gen: int = -1
var _restore_gen: int = 0
## Bumped to retire an in-flight resolve so a late 200 cannot adopt.
var _resolve_gen: int = 0
## One generation per lookup_name call. Listeners ignore a generation they
## did not ask for; a newer call does not drop an older answer.
var _lookup_gen: int = 0
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


func push_profile(gap_fill_id: String = "") -> void:
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
	_http_request(HTTPClient.METHOD_PUT, url, body, _on_push_profile_finished.bind(gap_fill_id), true)


func fetch_profile(player_id: String, from_boot: bool = false) -> void:
	if player_id.is_empty():
		return
	if _profile_http_skipped():
		return
	var url := "%s/v1/profile?player_id=%s" % [_base_url(), player_id]
	_http_request(HTTPClient.METHOD_GET, url, "", _on_fetch_profile_finished.bind(player_id, from_boot))


## User-initiated transfer. Own callback: the boot reconcilers all no-op when
## data.player_id != the id this device already holds (D-048).
func restore_profile(player_id: String) -> void:
	var id := player_id.strip_edges()
	if id.is_empty():
		return
	_restore_gen += 1
	var gen := _restore_gen
	if _profile_http_skipped():
		restore_finished.emit(false, "offline")
		return
	var url := "%s/v1/profile?player_id=%s" % [_base_url(), id]
	_http_request(HTTPClient.METHOD_GET, url, "", _on_restore_profile_finished.bind(gen, id))


## Claim the typed name (D-053). Optional secret is sent only when set, so a
## later password can occupy the same field. A failure adopts nothing.
func resolve_name(raw_name: String, secret: String = "") -> int:
	_resolve_gen += 1
	var gen := _resolve_gen
	var payload := {"name": raw_name}
	if not secret.is_empty():
		payload["secret"] = secret
	if _profile_http_skipped():
		_emit_resolve_failure.call_deferred(gen, 0, "unreachable")
		return gen
	var url := "%s/v1/players/resolve" % _base_url()
	_http_request(
		HTTPClient.METHOD_POST,
		url,
		JSON.stringify(payload),
		_on_resolve_finished.bind(gen),
		false
	)
	return gen


## Drop a resolve that is no longer wanted (cancel, a newer claim). The
## in-flight response then fails the generation check and does not adopt.
func retire_name_resolve() -> void:
	_resolve_gen += 1


## The one place that asks whether a name is already held (D-059).
## GET /v1/players/lookup. The name is percent-encoded so a space, "&", "+",
## "#", "%" or non-ASCII byte is the same name resolve would claim.
## Does not adopt. A 200 with a boolean `held` is an answer; anything else
## (transport, 4xx including an older server's 404, 5xx, bad JSON) is unanswered.
func lookup_name(raw_name: String) -> int:
	_lookup_gen += 1
	var gen := _lookup_gen
	if _profile_http_skipped():
		_emit_lookup_unanswered.call_deferred(gen, raw_name)
		return gen
	var url := "%s/v1/players/lookup?name=%s" % [_base_url(), raw_name.uri_encode()]
	_http_request(
		HTTPClient.METHOD_GET,
		url,
		"",
		_on_lookup_finished.bind(gen, raw_name),
		false
	)
	return gen


func _emit_lookup_unanswered(gen: int, raw_name: String) -> void:
	name_lookup.emit(gen, {
		"answered": false,
		"held": false,
		"display": "",
		"queried": raw_name,
	})


func _on_lookup_finished(ok: bool, code: int, parsed: Variant, reason: String, gen: int, raw_name: String) -> void:
	var held_known := false
	var held := false
	var display := ""
	if ok and typeof(parsed) == TYPE_DICTIONARY:
		var data: Dictionary = parsed
		if typeof(data.get("held")) == TYPE_BOOL:
			held_known = true
			held = bool(data["held"])
			if typeof(data.get("name")) == TYPE_STRING:
				display = String(data["name"]).strip_edges()
	if not held_known:
		name_lookup.emit(gen, {
			"answered": false,
			"held": false,
			"display": "",
			"queried": raw_name,
			"code": code,
			"reason": reason,
		})
		return
	name_lookup.emit(gen, {
		"answered": true,
		"held": held,
		"display": display,
		"queried": raw_name,
	})


func _emit_resolve_failure(gen: int, code: int, reason: String) -> void:
	if gen != _resolve_gen:
		return
	name_resolved.emit(gen, false, {"code": code, "reason": reason, "error": ""})


func _on_resolve_finished(ok: bool, code: int, parsed: Variant, reason: String, gen: int) -> void:
	if gen != _resolve_gen:
		return
	if not ok or typeof(parsed) != TYPE_DICTIONARY:
		name_resolved.emit(gen, false, {
			"code": code,
			"reason": reason if not reason.is_empty() else "offline",
			"error": "",
		})
		return
	var data: Dictionary = parsed
	var profile := get_node_or_null("/root/Profile")
	if profile == null or not profile.has_method("adopt_identity"):
		name_resolved.emit(gen, false, {"code": code, "reason": "offline", "error": ""})
		return
	# The resolve response is already the cloud profile. Do not PUT it back.
	# Clear before adopt so name_changed cannot re-open the boot prompt.
	var was_unconfirmed := identity_unconfirmed
	if was_unconfirmed:
		identity_unconfirmed = false
	_suppress_profile_push = true
	var adopted := bool(profile.adopt_identity(
		String(data.get("player_id", "")),
		String(data.get("name", "")),
		String(data.get("avatar", ""))
	))
	_suppress_profile_push = false
	if not adopted:
		if was_unconfirmed:
			identity_unconfirmed = true
		name_resolved.emit(gen, false, {"code": code, "reason": "offline", "error": ""})
		return
	if was_unconfirmed:
		identity_unconfirmed_changed.emit(false)
	var adopted_id := String(profile.player_id)
	name_resolved.emit(gen, true, {
		"player_id": adopted_id,
		"name": String(profile.player_name),
		"avatar": String(profile.avatar_id),
		"created": bool(data.get("created", false)),
	})
	_fetch_server_best(adopted_id)


func fetch_top(limit: int) -> void:
	_fetch_gen += 1
	var gen := _fetch_gen
	var clamped := clampi(limit, 1, 50)
	var url := "%s/v1/leaderboard?limit=%d" % [_base_url(), clamped]
	# Late 2xx is accepted only here. Submit keeps the first callback so a
	# watchdog timeout still schedules D-034's retry and a late 201 cannot
	# land twice.
	_http_request(HTTPClient.METHOD_GET, url, "", _on_fetch_finished.bind(gen), false, true)


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
	_fetch_server_best(player_id)


func _profile_http_skipped() -> bool:
	return _base_url() == _CLOSED_SENTINEL_URL


## Ask /v1/leaderboard/me for the id bound here. The body has no player_id, so
## the callback must not write through Game.high_score (that would follow
## whoever is current when the response lands).
func _fetch_server_best(player_id: String) -> void:
	if player_id.is_empty():
		return
	var profile := get_node_or_null("/root/Profile")
	if profile == null or String(profile.player_name).is_empty():
		return
	if _profile_http_skipped():
		return
	best_fetch_count += 1
	var url := "%s/v1/leaderboard/me?player_id=%s" % [_base_url(), player_id]
	_http_request(HTTPClient.METHOD_GET, url, "", _on_server_best_finished.bind(player_id))


func _on_server_best_finished(ok: bool, code: int, parsed: Variant, _reason: String, requested_id: String) -> void:
	# 404 unknown_player means there is no server best yet. Transport failure
	# and any other non-2xx leave the device value alone and stay quiet.
	if code == 404 or not ok or typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	if not data.has("best"):
		return
	var game := get_node_or_null("/root/Game")
	if game == null or not game.has_method("reconcile_best"):
		return
	game.reconcile_best(requested_id, int(data["best"]))


func _on_push_profile_finished(_ok: bool, code: int, parsed: Variant, _reason: String, gap_fill_id: String) -> void:
	# D-037: fire-and-forget. Failures are dropped; not enrolled in D-034.
	# D-058: the boot gap-fill's 409 name_taken marks this session
	# unconfirmed. A score POST does the same in `_on_submit_finished`
	# (T43); D-038 still sends no gap-fill PUT without an avatar.
	# Transport failure is code 0. A 200 is the ordinary gap-fill and
	# changes nothing. No offline text either way.
	if code != 409 or not _body_error_is(parsed, "name_taken"):
		return
	refused_name_count += 1
	if gap_fill_id.is_empty():
		return
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if String(profile.player_id) != gap_fill_id:
		return
	if String(profile.player_name).is_empty():
		return
	_mark_unconfirmed()


func _body_error_is(parsed: Variant, error_name: String) -> bool:
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	return String((parsed as Dictionary).get("error", "")) == error_name


func _mark_unconfirmed() -> void:
	if identity_unconfirmed:
		return
	identity_unconfirmed = true
	identity_unconfirmed_changed.emit(true)


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


func _on_restore_profile_finished(ok: bool, code: int, parsed: Variant, _reason: String, gen: int, requested_id: String) -> void:
	if gen != _restore_gen:
		return
	# Check 404 before `not ok` — `_on_http_completed` reports every non-2xx
	# as ok == false. Transport failure is code 0, never a 404.
	if code == 404:
		restore_finished.emit(false, "not_found")
		return
	if not ok:
		restore_finished.emit(false, "offline")
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		restore_finished.emit(false, "offline")
		return
	var data: Dictionary = parsed
	var profile := get_node_or_null("/root/Profile")
	if profile == null or not profile.has_method("adopt_identity"):
		restore_finished.emit(false, "offline")
		return
	var was_unconfirmed := identity_unconfirmed
	if was_unconfirmed:
		identity_unconfirmed = false
	var adopted := false
	_suppress_profile_push = true
	adopted = bool(profile.adopt_identity(
		String(data.get("player_id", "")),
		String(data.get("name", "")),
		String(data.get("avatar", ""))
	))
	_suppress_profile_push = false
	if not adopted and was_unconfirmed:
		identity_unconfirmed = true
	if adopted:
		if was_unconfirmed:
			identity_unconfirmed_changed.emit(false)
		restore_finished.emit(true, "")
		var adopted_id := String(data.get("player_id", ""))
		if adopted_id.is_empty():
			adopted_id = requested_id
		_fetch_server_best(adopted_id)
	else:
		restore_finished.emit(false, "offline")


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
	push_profile(requested_id)


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
	# Epoch advances even when this game does not submit, so the screen can
	# tell "no post" from "the previous game's post".
	_game_over_epoch += 1
	_game_over_submit_token = -1
	fetch_top(10)
	# D-058: an unconfirmed id is dead. The invite claims, then posts once.
	if identity_unconfirmed:
		return
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if String(profile.player_name).is_empty():
		return
	if final_score <= 0:
		return
	_start_new_submit(final_score)
	_game_over_submit_token = _submit_token


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
	score_post_ids.append(player_id)
	var body := JSON.stringify({
		"player_id": player_id,
		"name": player_name,
		"score": score,
		"client": CLIENT,
	})
	var url := "%s/v1/scores" % _base_url()
	_http_request(HTTPClient.METHOD_POST, url, body, _on_submit_finished.bind(token, player_id), true)


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
	# This generation already applied a body. The watchdog (or HTTPRequest's
	# own timer) can still call back afterwards; that must not clear the
	# board or re-show offline.
	if gen == _fetch_ok_gen:
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
	_fetch_ok_gen = gen
	last_entries = entries.duplicate(true)
	last_total_players = int(data.get("total_players", last_entries.size()))
	board_updated.emit(last_entries, last_total_players)


## Short line for a fetch/submit failure. The signal reason stays precise;
## this is only the sentence a player reads. Wording is provisional.
func offline_line(reason: String) -> String:
	match reason:
		"timeout":
			return "The leaderboard took too long"
		"unreachable":
			return "Can't reach the leaderboard"
		"no_network":
			return "No connection to the leaderboard"
		"request_failed":
			return "The leaderboard blocked the answer"
		"bad_json":
			return "The leaderboard sent a blank answer"
	if reason.begins_with("http_"):
		var digits := reason.substr(5)
		var code := digits.to_int()
		if code >= 500:
			return "The leaderboard had a problem (%s)" % digits
		if code >= 400:
			return "The leaderboard said no (%s)" % digits
	return "Leaderboard offline"


func _on_submit_finished(ok: bool, code: int, parsed: Variant, reason: String, token: int, submitted_player_id: String) -> void:
	var state: Dictionary = _submit_state.get(token, {})
	if not state.is_empty():
		state["in_flight"] = false
	if ok and code == 201 and typeof(parsed) == TYPE_DICTIONARY:
		_submitted_tokens[token] = true
		var data: Dictionary = parsed
		# `best` belongs to the id in the POST body, captured at send time.
		if data.has("best"):
			var game := get_node_or_null("/root/Game")
			if game != null and game.has_method("reconcile_best"):
				game.reconcile_best(submitted_player_id, int(data["best"]))
		if token == _submit_token:
			submitted.emit(parsed)
		fetch_top(10)
		return
	# T43: 409 name_taken for the id still on the device is the same
	# unconfirmed signal as the boot gap-fill. The invite is the message,
	# so this path does not emit "said no (409)" and does not retry.
	# An older token still marks the id, but game over ignores it unless
	# that token is the game on screen.
	if _score_refusal_marks_unconfirmed(code, parsed, submitted_player_id):
		_mark_unconfirmed()
		refused_score.emit(token)
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


func _score_refusal_marks_unconfirmed(code: int, parsed: Variant, submitted_player_id: String) -> bool:
	if code != 409 or not _body_error_is(parsed, "name_taken"):
		return false
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return false
	if submitted_player_id.is_empty() or String(profile.player_id) != submitted_player_id:
		return false
	if String(profile.player_name).is_empty():
		return false
	return true


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


func _http_request(method: int, url: String, body: String, callback: Callable, with_key: bool = false, accept_late_success: bool = false) -> void:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if with_key:
		headers.append("X-Squish-Key: %s" % _write_key())
	var state := {"done": false, "http": http}
	http.request_completed.connect(
		_on_http_completed.bind(callback, state, accept_late_success),
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
	state: Dictionary,
	accept_late_success: bool = false
) -> void:
	var http: HTTPRequest = state.get("http") as HTTPRequest
	var already := bool(state.get("done", false))
	if not already:
		state.done = true
	if http != null and is_instance_valid(http):
		http.queue_free()
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	# Godot defers request_completed. The watchdog can set done and report
	# timeout in that gap, after the 2xx body was already copied into the
	# deferred call. A fetch still applies that body. Submit does not opt
	# in: its first callback owns the D-034 retry.
	if already and not (accept_late_success and success):
		return
	if not success:
		# Keep the JSON error body (409 name_taken). Callers still treat
		# ok == false as failure; 404 is checked before ok, as before.
		var fail_parsed: Variant = null
		var fail_text := body.get_string_from_utf8()
		if not fail_text.is_empty():
			fail_parsed = JSON.parse_string(fail_text)
		callback.call(false, response_code, fail_parsed, _result_reason(result, response_code))
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
