extends SceneTree

## D-058, T43. An avatar-less device is not marked at boot (D-038). A score POST
## answered 409 name_taken for the id it still holds marks it unconfirmed and
## keeps that run: the game-over screen showing that game opens the pre-filled
## invite, and a claim posts that score once. A refusal for an older submit
## does not.

const PORT := 18796
const VIEWPORT := Rect2(0, 0, 720, 1280)
const KEYBOARD_TOP := 640.0
const MIN_TOUCH := 64.0
const DAD_ID := "b8aa808f-6d01-439e-87be-664baf0ead85"
const DEAD_ID := "f47ac10b-58cc-4372-a567-0e02b2c3d479"

var _cases_passed: int = 0
var _profile: Node
var _leaderboard: Node
var _game: Node
var _main: Node
var _server_pid: int = -1
var _log_path: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("REFUSED start")
	_profile = root.get_node_or_null("/root/Profile")
	_leaderboard = root.get_node_or_null("/root/Leaderboard")
	_game = root.get_node_or_null("/root/Game")
	if _profile == null or _leaderboard == null or _game == null:
		_fail("Profile, Leaderboard, or Game missing")
		return
	if not _leaderboard.has_signal("refused_score") or not _leaderboard.has_signal("identity_unconfirmed_changed"):
		_fail("refused score is not wired to the unconfirmed signal")
		return
	# Before any await. Leaderboard's deferred boot, and a profile.save left
	# by an earlier suite, must not gap-fill: this device has no avatar.
	_plant(DEAD_ID, "Dad", "")
	_leaderboard.identity_unconfirmed = false
	_log_path = ProjectSettings.globalize_path("user://t43-refused.log")
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	OS.set_environment("SQUISH_LEADERBOARD_KEY", "devkey")
	if not _start_server():
		return
	if not await _seed_profile(DAD_ID, "Dad", "frog_gus"):
		return
	if not await _load_main():
		return

	if not await _case_boot_avatarless():
		return
	if not await _case_refused_invite():
		return
	if not await _case_save_posts_once():
		return
	if not await _case_menu_after_claim():
		return
	if not await _case_next_game():
		return
	if not await _case_not_now_then_welcome():
		return
	if not await _case_stale_refusal():
		return
	if not await _case_other_refusals():
		return

	_cleanup()
	print("REFUSED PASS cases=%d" % _cases_passed)
	quit(0)


func _case_boot_avatarless() -> bool:
	print("REFUSED case 1 avatar-less boot sends no PUT")
	_show_title()
	await process_frame
	# An earlier suite's profile can make Leaderboard's deferred boot PUT
	# before this case runs. Let that finish, then measure this boot.
	if not await _wait_http_idle():
		return _fail("case 1: startup requests did not finish")
	_leaderboard.identity_unconfirmed = false
	var pushes := int(_leaderboard._profile_push_count)
	_leaderboard._boot_restore_profile()
	if not await _wait_http_idle():
		return _fail("case 1: boot requests did not finish")
	if int(_leaderboard._profile_push_count) != pushes:
		return _fail("case 1: PUTs %s → %s" % [pushes, _leaderboard._profile_push_count])
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 1: avatar-less boot marked unconfirmed")
	if String(_profile.player_id) != DEAD_ID or String(_profile.player_name) != "Dad":
		return _fail("case 1: identity changed to %s/%s" % [_profile.player_id, _profile.player_name])
	if String(_profile.avatar_id) != "":
		return _fail("case 1: avatar became '%s'" % _profile.avatar_id)
	var cloud := await _http_json(HTTPClient.METHOD_GET, "/v1/profile?player_id=%s" % DEAD_ID, "", false)
	if int(cloud.get("code", 0)) != 404:
		return _fail("case 1: dead id GET %s %s" % [cloud.get("code", 0), cloud.get("text", "")])
	var dad := await _http_json(HTTPClient.METHOD_GET, "/v1/profile?player_id=%s" % DAD_ID, "", false)
	if int(dad.get("code", 0)) != 200 or String(dad.get("text", "")).find("Dad") < 0:
		return _fail("case 1: holder profile %s %s" % [dad.get("code", 0), dad.get("text", "")])
	if _post_count(DEAD_ID) != 0:
		return _fail("case 1: posted under the dead id")
	_cases_passed += 1
	print("REFUSED case 1 pass puts=0")
	return true


func _case_refused_invite() -> bool:
	print("REFUSED case 2 game over 409 opens the invite")
	var dead_before := _post_count(DEAD_ID)
	if not await _play_to_over(9000):
		return false
	var panel := _panel()
	if not await _wait_invite(panel, "Dad"):
		return _fail("case 2: invite did not open (unconfirmed=%s)" % _leaderboard.identity_unconfirmed)
	if not bool(_leaderboard.identity_unconfirmed):
		return _fail("case 2: 409 did not mark unconfirmed")
	if _post_count(DEAD_ID) != dead_before + 1:
		return _fail("case 2: dead posts %d want %d" % [_post_count(DEAD_ID), dead_before + 1])
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	var save := panel.get_node_or_null("SaveButton") as Button
	var offline := panel.get_node_or_null("OfflineLabel") as Label
	if edit == null or edit.text != "Dad" or not edit.visible:
		return _fail("case 2: prefill '%s'" % (edit.text if edit != null else ""))
	if save == null or save.disabled:
		return _fail("case 2: Save is disabled on a pre-filled name")
	if _said_no(offline, "409"):
		return _fail("case 2: showed '%s'" % (offline.text if offline != null else ""))
	if int(_game.score) != 9000:
		return _fail("case 2: score on screen is %s" % _game.score)
	if not _assert_panel(panel, "refused-invite"):
		return false
	print("REFUSED state refused-invite overlap_count=0")
	# A retry is armed synchronously. 409 must not arm one.
	var attempts_token := int(_leaderboard._submit_token)
	var state: Dictionary = _leaderboard._submit_state.get(attempts_token, {})
	if bool(state.get("retry_pending", false)):
		return _fail("case 2: refused POST armed a retry")
	if int(_leaderboard.submit_attempts.get(attempts_token, 0)) != 1:
		return _fail("case 2: attempts %s want 1" % _leaderboard.submit_attempts.get(attempts_token, 0))
	if _post_count(DEAD_ID) != dead_before + 1:
		return _fail("case 2: a second POST went out under the dead id")
	_cases_passed += 1
	print("REFUSED case 2 pass dead_posts=%d" % _post_count(DEAD_ID))
	return true


func _case_save_posts_once() -> bool:
	print("REFUSED case 3 Save posts 9000 once under the holder")
	var panel := _panel()
	var save := panel.get_node_or_null("SaveButton") as Button
	if save == null or not save.visible or save.disabled:
		return _fail("case 3: Save is not a live control")
	var dead_posts := _post_count(DEAD_ID)
	var dad_before := await _score_total(DAD_ID)
	# Positive control: the button's pressed signal is what commits.
	save.pressed.emit()
	if not await _wait_id(DAD_ID):
		return _fail("case 3: did not adopt Dad (id=%s)" % _profile.player_id)
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 3: claim left the identity unconfirmed")
	if not await _wait_score_total(DAD_ID, dad_before + 1):
		return _fail("case 3: holder did not gain a row")
	var rows := await _score_page(DAD_ID)
	if int(rows.get("total", -1)) != dad_before + 1 or not _page_has_score(rows, DAD_ID, 9000):
		return _fail("case 3: rows %s want one 9000" % rows)
	if _page_has_score(rows, DEAD_ID, 9000):
		return _fail("case 3: 9000 landed on the dead id")
	if _post_count(DEAD_ID) != dead_posts:
		return _fail("case 3: dead posts %d → %d" % [dead_posts, _post_count(DEAD_ID)])
	if _post_count(DAD_ID) != 1:
		return _fail("case 3: holder posts %d want 1" % _post_count(DAD_ID))
	var dead_rows := await _score_page(DEAD_ID)
	if int(dead_rows.get("total", -1)) != 0:
		return _fail("case 3: dead id holds rows %s" % dead_rows)
	_cases_passed += 1
	print("REFUSED case 3 pass")
	return true


func _case_menu_after_claim() -> bool:
	print("REFUSED case 4 menu after the claim has no boot prompt")
	var menu := _panel().get_node_or_null("MenuButton") as Button
	if menu == null:
		return _fail("case 4: Menu missing")
	menu.pressed.emit()
	for _i in 8:
		await process_frame
	var title := _main.get_node_or_null("Title")
	var welcome := _main.get_node_or_null("Title/NameEntry/WelcomeLabel") as Label
	var entry := _main.get_node_or_null("Title/NameEntry") as Control
	if title == null or not title.visible:
		return _fail("case 4: title did not return")
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 4: claim did not clear the state")
	if welcome != null and welcome.visible:
		return _fail("case 4: welcome stayed up ('%s')" % welcome.text)
	if entry != null and entry.visible:
		return _fail("case 4: name prompt stayed up after the claim")
	_cases_passed += 1
	print("REFUSED case 4 pass")
	return true


func _case_next_game() -> bool:
	print("REFUSED case 5 next game posts 201 with no invite")
	var dad_before := await _score_total(DAD_ID)
	var posts_before := _post_count(DAD_ID)
	if not await _play_to_over(4200):
		return false
	var panel := _panel()
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	if edit != null and edit.visible:
		return _fail("case 5: a confirmed player got the invite")
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 5: the next game became unconfirmed")
	if not await _wait_score_total(DAD_ID, dad_before + 1):
		return _fail("case 5: 4200 did not land")
	var rows := await _score_page(DAD_ID)
	if not _page_has_score(rows, DAD_ID, 4200):
		return _fail("case 5: rows %s missing 4200" % rows)
	if _post_count(DAD_ID) != posts_before + 1:
		return _fail("case 5: posts %d → %d" % [posts_before, _post_count(DAD_ID)])
	_cases_passed += 1
	print("REFUSED case 5 pass")
	return true


func _case_not_now_then_welcome() -> bool:
	print("REFUSED case 6 Not now, then Welcome back on the title")
	_plant(DEAD_ID, "Dad", "")
	_leaderboard.identity_unconfirmed = false
	if not await _back_to_title():
		return false
	var dad_before := await _score_total(DAD_ID)
	var dead_before := _post_count(DEAD_ID)
	if not await _play_to_over(8000):
		return false
	var panel := _panel()
	if not await _wait_invite(panel, "Dad"):
		return _fail("case 6: invite did not open")
	var skip := panel.get_node_or_null("SkipButton") as Button
	if skip == null or not skip.visible:
		return _fail("case 6: Not now is not showing")
	skip.pressed.emit()
	await process_frame
	await process_frame
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	if edit != null and edit.visible:
		return _fail("case 6: Not now left the invite up")
	if String(_profile.player_id) != DEAD_ID:
		return _fail("case 6: Not now adopted %s" % _profile.player_id)
	if not bool(_leaderboard.identity_unconfirmed):
		return _fail("case 6: Not now cleared the state")
	if _post_count(DEAD_ID) != dead_before + 1:
		return _fail("case 6: dead posts %d want %d" % [_post_count(DEAD_ID), dead_before + 1])
	if await _score_total(DAD_ID) != dad_before:
		return _fail("case 6: Not now wrote a row")
	var menu := panel.get_node_or_null("MenuButton") as Button
	if menu == null:
		return _fail("case 6: Menu missing")
	menu.pressed.emit()
	for _i in 8:
		await process_frame
	var welcome := _main.get_node_or_null("Title/NameEntry/WelcomeLabel") as Label
	if not await _wait_welcome(welcome, "Dad"):
		return _fail("case 6: title welcome '%s' visible=%s" % [welcome.text if welcome != null else "", welcome.visible if welcome != null else false])
	if welcome.text.find("Welcome back") < 0:
		return _fail("case 6: title text '%s'" % welcome.text)
	_cases_passed += 1
	print("REFUSED case 6 pass")
	return true


func _case_stale_refusal() -> bool:
	print("REFUSED case 7 a stale 409 does not take the newer game")
	_plant(DEAD_ID, "Dad", "")
	_leaderboard.identity_unconfirmed = false
	if not await _back_to_title():
		return false
	var dad_before := await _score_total(DAD_ID)
	if not await _arm_game(2222):
		return false
	# Two drains leave one ball. The third ends the game and starts the POST
	# synchronously; the 409 cannot be delivered until we yield.
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	var panel := _panel()
	if panel == null or not panel.visible or _game.state != _game.GAME_OVER:
		return _fail("case 7: newer game is not on screen")
	if int(_game.score) != 2222:
		return _fail("case 7: newer score is %s" % _game.score)
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	if edit != null and edit.visible:
		return _fail("case 7: invite opened before either 409 (HTTP was synchronous)")
	var screen_token := int(_leaderboard._submit_token)
	var dead_posts := _post_count(DEAD_ID)
	if dead_posts < 1:
		return _fail("case 7: the newer game did not POST")
	var old_token := screen_token + 1000
	_leaderboard._submit_state[old_token] = {
		"score": 1111,
		"in_flight": true,
		"retry_pending": false,
	}
	_leaderboard._on_submit_finished(
		false, 409, {"error": "name_taken"}, "http_409", old_token, DEAD_ID
	)
	if not bool(_leaderboard.identity_unconfirmed):
		return _fail("case 7: stale 409 for the current id did not mark unconfirmed")
	if edit != null and edit.visible:
		return _fail("case 7: stale 409 opened the invite over the newer game")
	if _post_count(DEAD_ID) != dead_posts:
		return _fail("case 7: stale 409 posted (%d → %d)" % [dead_posts, _post_count(DEAD_ID)])
	if int(_game.score) != 2222:
		return _fail("case 7: stale 409 replaced the score with %s" % _game.score)
	var offline := panel.get_node_or_null("OfflineLabel") as Label
	if _said_no(offline, "409"):
		return _fail("case 7: stale 409 showed '%s'" % offline.text)
	if await _score_total(DAD_ID) != dad_before:
		return _fail("case 7: stale 409 wrote a holder row")
	# The newer game's own 409, still in flight, may now open its invite.
	if not await _wait_invite(panel, "Dad"):
		return _fail("case 7: the newer game's own 409 did not open the invite")
	if int(_game.score) != 2222:
		return _fail("case 7: invite is for score %s" % _game.score)
	if _post_count(DEAD_ID) != dead_posts:
		return _fail("case 7: the newer 409 retried or posted 1111")
	if await _score_total(DAD_ID) != dad_before:
		return _fail("case 7: a row landed before Save")
	var save := panel.get_node_or_null("SaveButton") as Button
	if save == null or save.disabled:
		return _fail("case 7: Save is not live for the newer game")
	save.pressed.emit()
	if not await _wait_id(DAD_ID):
		return _fail("case 7: Save did not adopt Dad")
	if not await _wait_score_total(DAD_ID, dad_before + 1):
		return _fail("case 7: newer score did not land")
	var rows := await _score_page(DAD_ID)
	if not _page_has_score(rows, DAD_ID, 2222):
		return _fail("case 7: rows %s missing 2222" % rows)
	if _page_has_score(rows, DAD_ID, 1111) or _page_has_score(rows, DEAD_ID, 1111):
		return _fail("case 7: old score 1111 was posted %s" % rows)
	if int(rows.get("total", -1)) != dad_before + 1:
		return _fail("case 7: holder total %s want %d" % [rows.get("total", -1), dad_before + 1])
	if _post_count(DEAD_ID) != dead_posts:
		return _fail("case 7: dead posts grew to %d" % _post_count(DEAD_ID))
	_cases_passed += 1
	print("REFUSED case 7 pass")
	return true


func _case_other_refusals() -> bool:
	print("REFUSED case 8 other refusals stay ordinary")
	if not await _wait_http_idle():
		return _fail("case 8: requests still in flight")
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 8: started unconfirmed")
	var panel := _panel()
	if panel == null or not panel.visible:
		return _fail("case 8: game over is not showing")
	var id := String(_profile.player_id)
	if not _refuse_latest(400, {"error": "invalid_score"}, "http_400", id):
		return _fail("case 8: 400 callback did not run")
	await process_frame
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 8: 400 marked unconfirmed")
	var offline := panel.get_node_or_null("OfflineLabel") as Label
	var want_400 := String(_leaderboard.offline_line("http_400"))
	if offline == null or not offline.visible or offline.text != want_400:
		return _fail("case 8: 400 text '%s' visible=%s want '%s'" % [offline.text if offline != null else "", offline.visible if offline != null else false, want_400])
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	if edit != null and edit.visible:
		return _fail("case 8: 400 opened the invite")
	if not _refuse_latest(409, {"error": "conflict"}, "http_409", id):
		return _fail("case 8: other 409 callback did not run")
	await process_frame
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 8: a 409 conflict marked unconfirmed")
	var want_409 := String(_leaderboard.offline_line("http_409"))
	if offline == null or not offline.visible or offline.text != want_409:
		return _fail("case 8: 409 text '%s' want '%s'" % [offline.text if offline != null else "", want_409])
	if edit != null and edit.visible:
		return _fail("case 8: other 409 opened the invite")
	var stranger := "abababab-1111-4222-8333-999999999999"
	if not _refuse_latest(409, {"error": "name_taken"}, "http_409", stranger):
		return _fail("case 8: foreign 409 callback did not run")
	await process_frame
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 8: name_taken for another id marked unconfirmed")
	if offline == null or not offline.visible or offline.text != want_409:
		return _fail("case 8: foreign 409 text '%s'" % (offline.text if offline != null else ""))
	# Transport failure still schedules today's retry, and does not mark.
	var delays: Array = _leaderboard.retry_delays_sec.duplicate()
	_leaderboard.retry_delays_sec = [0.05]
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:9")
	_leaderboard._submit_token += 1
	var token := int(_leaderboard._submit_token)
	_leaderboard._submit_state[token] = {"score": 50, "in_flight": true, "retry_pending": false}
	_leaderboard.submit_attempts[token] = 1
	_leaderboard._on_submit_finished(false, 0, null, "unreachable", token, id)
	var state: Dictionary = _leaderboard._submit_state.get(token, {})
	if not bool(state.get("retry_pending", false)):
		_leaderboard.retry_delays_sec = delays
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 8: transport failure did not schedule a retry")
	if bool(_leaderboard.identity_unconfirmed):
		_leaderboard.retry_delays_sec = delays
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 8: transport failure marked unconfirmed")
	var want_down := String(_leaderboard.offline_line("unreachable"))
	if offline == null or not offline.visible or offline.text != want_down:
		_leaderboard.retry_delays_sec = delays
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 8: transport text '%s' want '%s'" % [offline.text if offline != null else "", want_down])
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000 and int(_leaderboard.submit_attempts.get(token, 0)) < 2:
		await process_frame
	_leaderboard._submitted_tokens[token] = true
	_leaderboard.retry_delays_sec = delays
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	if int(_leaderboard.submit_attempts.get(token, 0)) < 2:
		return _fail("case 8: retry did not run (attempts=%s)" % _leaderboard.submit_attempts.get(token, 0))
	if bool(_leaderboard.identity_unconfirmed):
		return _fail("case 8: the retry marked unconfirmed")
	_cases_passed += 1
	print("REFUSED case 8 pass")
	return true


func _refuse_latest(code: int, body: Dictionary, reason: String, player_id: String) -> bool:
	_leaderboard._submit_token += 1
	var token := int(_leaderboard._submit_token)
	_leaderboard._submit_state[token] = {"score": 1, "in_flight": true, "retry_pending": false}
	_leaderboard.submit_attempts[token] = 1
	_leaderboard._on_submit_finished(false, code, body, reason, token, player_id)
	return int(_leaderboard.submit_attempts.get(token, 0)) == 1


func _said_no(offline: Label, code: String) -> bool:
	if offline == null or not offline.visible:
		return false
	return offline.text.find("said no (%s)" % code) >= 0


func _panel() -> Node:
	if _main == null:
		return null
	return _main.get_node_or_null("GameOver")


func _arm_game(score: int) -> bool:
	if _game.state == _game.GAME_OVER:
		_game.restart()
		for _i in 4:
			await process_frame
	var title := _main.get_node_or_null("Title")
	if title != null and title.visible:
		var play := title.get_node_or_null("PlayButton") as Button
		if play == null:
			return _fail("Play missing")
		play.pressed.emit()
		for _i in 8:
			await process_frame
		if title.visible:
			return _fail("could not leave the title")
	_game.add_score(score)
	return true


func _play_to_over(score: int) -> bool:
	if not await _arm_game(score):
		return false
	for _i in 3:
		_game.on_ball_drained()
		await physics_frame
		await process_frame
	var panel := _panel()
	if panel == null or not panel.visible or _game.state != _game.GAME_OVER:
		return _fail("expected GAME_OVER")
	return true


func _show_title() -> void:
	var title := _main.get_node_or_null("Title")
	if title != null and title.has_method("show_menu"):
		title.show_menu()


func _back_to_title() -> bool:
	if _main != null and _main.has_method("return_to_menu"):
		_main.return_to_menu()
	else:
		_game.restart()
		_show_title()
	for _i in 6:
		await process_frame
	var title := _main.get_node_or_null("Title")
	if title == null or not title.visible:
		return _fail("title did not return")
	return true


func _plant(player_id: String, player_name: String, avatar: String) -> void:
	_profile.player_id = player_id
	_profile.player_name = player_name
	_profile.players = {player_name.to_lower(): player_id}
	_profile.avatar_id = avatar
	if avatar.is_empty():
		_profile.avatars = {}
	else:
		_profile.avatars = {player_name.to_lower(): avatar}
	_profile._save()


func _post_count(player_id: String) -> int:
	var want := player_id.to_lower()
	var n := 0
	for id in _leaderboard.score_post_ids:
		if String(id).to_lower() == want:
			n += 1
	return n


func _wait_invite(panel: Node, name_part: String) -> bool:
	var edit := panel.get_node_or_null("NameEdit") as LineEdit if panel != null else null
	if edit == null:
		return false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if edit.visible and edit.text.find(name_part) >= 0:
			return true
		await process_frame
	return edit.visible and edit.text.find(name_part) >= 0


func _wait_welcome(welcome: Label, name_part: String) -> bool:
	if welcome == null:
		return false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if welcome.visible and welcome.text.find(name_part) >= 0:
			return true
		await process_frame
	return welcome.visible and welcome.text.find(name_part) >= 0


func _wait_id(player_id: String) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if String(_profile.player_id) == player_id:
			return true
		await process_frame
	return String(_profile.player_id) == player_id


func _wait_http_idle() -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000:
		if _http_nodes() == 0:
			await process_frame
			return _http_nodes() == 0
		await process_frame
	return _http_nodes() == 0


func _http_nodes() -> int:
	var n := 0
	for child in _leaderboard.get_children():
		if child is HTTPRequest:
			n += 1
	return n


func _wait_score_total(player_id: String, want: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if await _score_total(player_id) >= want:
			return true
		await process_frame
	return await _score_total(player_id) >= want


func _score_total(player_id: String) -> int:
	var page := await _score_page(player_id)
	return int(page.get("total", -1))


func _score_page(player_id: String) -> Dictionary:
	var got := await _http_json(
		HTTPClient.METHOD_GET,
		"/v1/admin/scores?player_id=%s&limit=50" % player_id,
		"",
		false,
		true
	)
	var parsed: Variant = JSON.parse_string(String(got.get("text", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"total": -1, "rows": [], "code": int(got.get("code", 0))}
	var data: Dictionary = parsed
	data["code"] = int(got.get("code", 0))
	return data


func _page_has_score(page: Dictionary, player_id: String, score: int) -> bool:
	var rows: Variant = page.get("rows", [])
	if typeof(rows) != TYPE_ARRAY:
		return false
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if String(row.get("player_id", "")).to_lower() == player_id.to_lower() and int(row.get("score", -1)) == score:
			return true
	return false


func _seed_profile(player_id: String, player_name: String, avatar: String) -> bool:
	var body := JSON.stringify({
		"player_id": player_id,
		"name": player_name,
		"avatar": avatar,
		"client": "squish/1.0",
	})
	var got := await _http_json(HTTPClient.METHOD_PUT, "/v1/profile", body, true)
	if int(got.get("code", 0)) != 200:
		_fail("seed %s failed %s %s" % [player_name, got.get("code", 0), got.get("text", "")])
		return false
	return true


func _http_json(method: int, path: String, body: String, with_key: bool, admin: bool = false) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 3.0
	root.add_child(http)
	var done := {"got": false, "code": 0, "text": ""}
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, res_body: PackedByteArray) -> void:
		done.got = true
		done.code = code
		done.text = res_body.get_string_from_utf8()
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if with_key:
		headers.append("X-Squish-Key: devkey")
	if admin:
		headers.append("X-Squish-Admin: dev-admin")
	var err := http.request("http://127.0.0.1:%d%s" % [PORT, path], headers, method, body)
	if err != OK:
		http.queue_free()
		return {"code": 0, "text": ""}
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000:
		if bool(done.got):
			break
		await process_frame
	var code := int(done.code)
	var text := String(done.text)
	http.queue_free()
	return {"code": code, "text": text}


func _load_main() -> bool:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null or change_scene_to_packed(packed) != OK:
		_fail("could not load main.tscn")
		return false
	for _i in 4:
		await process_frame
	_main = current_scene
	if _main == null:
		_fail("main scene did not load")
		return false
	var table := _main.get_node_or_null("Table")
	if table != null:
		var drain := table.get_node_or_null("Drain")
		if drain != null and drain is Area2D:
			(drain as Area2D).monitoring = false
	return true


func _start_server() -> bool:
	_free_port(PORT)
	var root_path := ProjectSettings.globalize_path("res://")
	var cmd := "cd '%s/server' && exec env DB_PATH=:memory: SQUISH_KEY=devkey SQUISH_ADMIN_KEY=dev-admin PORT=%d node --no-warnings=ExperimentalWarning src/index.js > '%s' 2>&1" % [root_path, PORT, _log_path]
	_server_pid = OS.create_process("/bin/bash", ["-lc", cmd])
	if _server_pid <= 0:
		_fail("server did not spawn")
		return false
	for _i in 25:
		var output: Array = []
		var code := OS.execute("/usr/bin/curl", ["-sf", "--max-time", "1", "http://127.0.0.1:%d/healthz" % PORT], output, true, false)
		if code == 0:
			return true
		OS.delay_msec(200)
	if FileAccess.file_exists(_log_path):
		print(FileAccess.get_file_as_string(_log_path))
	_fail("server did not become healthy")
	return false


func _free_port(port: int) -> void:
	OS.execute("/bin/bash", ["-lc", "pids=$(lsof -ti tcp:%d 2>/dev/null || true); if [ -n \"$pids\" ]; then kill $pids 2>/dev/null || true; sleep 0.2; kill -9 $pids 2>/dev/null || true; fi" % port])


func _cleanup() -> void:
	if _server_pid > 0:
		OS.execute("/bin/kill", ["-TERM", str(_server_pid)])
		OS.execute("/bin/kill", ["-KILL", str(_server_pid)])
		_server_pid = -1
	_free_port(PORT)
	if _log_path != "" and FileAccess.file_exists(_log_path):
		DirAccess.remove_absolute(_log_path)


func _fail(message: String) -> bool:
	push_error("REFUSED FAIL %s" % message)
	print("REFUSED FAIL %s" % message)
	_cleanup()
	quit(1)
	return false


const _HEADER_SEAM := {
	"TitleLabel": true,
	"FinalScoreLabel": true,
	"GameOverHighScoreLabel": true,
	"NewHighScoreLabel": true,
	"YourRankLabel": true,
	"OfflineLabel": true,
}


func _assert_panel(panel: Node, label: String) -> bool:
	var kids: Array = []
	for child in panel.get_children():
		if not (child is Control):
			continue
		var node := child as Control
		if node.name == "Shade":
			continue
		if not node.visible or not node.is_visible_in_tree():
			continue
		kids.append(node)
	if not _assert_no_overlap(kids, label):
		return false
	return _assert_interactive(panel, label)


func _assert_no_overlap(kids: Array, label: String) -> bool:
	var overlap := 0
	for i in kids.size():
		var rect: Rect2 = (kids[i] as Control).get_global_rect()
		print("REFUSED layout %s %s %s" % [label, kids[i].name, rect])
		for j in range(i + 1, kids.size()):
			var shared: Rect2 = rect.intersection((kids[j] as Control).get_global_rect())
			if shared.get_area() <= 0.5:
				continue
			var left_name := String(kids[i].name)
			var right_name := String(kids[j].name)
			if _HEADER_SEAM.has(left_name) and _HEADER_SEAM.has(right_name):
				continue
			overlap += 1
			return _fail("%s: %s %s overlaps %s %s" % [label, left_name, rect, right_name, (kids[j] as Control).get_global_rect()])
	print("REFUSED layout %s overlap_count=%d visible=%d" % [label, overlap, kids.size()])
	return true


func _assert_interactive(node: Node, label: String) -> bool:
	return _walk_interactive(node, label)


func _walk_interactive(node: Node, label: String) -> bool:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return true
	if node is Button or node is LineEdit:
		var rect: Rect2 = (node as Control).get_global_rect()
		var smaller := minf(rect.size.x, rect.size.y)
		if smaller < MIN_TOUCH:
			return _fail("%s: %s smaller side %.1f < 64 %s" % [label, node.name, smaller, rect])
		if not VIEWPORT.encloses(rect):
			return _fail("%s: %s %s outside the viewport" % [label, node.name, rect])
		if node is LineEdit and rect.position.y + rect.size.y > KEYBOARD_TOP:
			return _fail("%s: %s %s is not entirely above y=640" % [label, node.name, rect])
	for child in node.get_children():
		if not _walk_interactive(child, label):
			return false
	return true
