extends SceneTree

## D-053. A typed name is resolved on the server and adopted. An existing name
## takes that player's id. A new name is kept across a reload. A failed
## resolve — transport, 409, 429 — leaves Profile.player_id alone and does
## not submit a score.

const PORT := 18791
const TWIN_A := "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
const TWIN_B := "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"
const LATE_ID := "cccccccc-dddd-4eee-8fff-000000000001"

var _cases_passed: int = 0
var _profile: Node
var _leaderboard: Node
var _game: Node
var _server_pid: int = -1
var _db_path: String = ""
var _log_path: String = ""
var _seed_path: String = ""
var _got_resolve: bool = false
var _resolve_ok: bool = false
var _resolve_info: Dictionary = {}
var _names: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("NAME_CLAIM start")
	_profile = root.get_node_or_null("Profile")
	_leaderboard = root.get_node_or_null("Leaderboard")
	_game = root.get_node_or_null("Game")
	if _profile == null or _leaderboard == null or _game == null:
		_fail("Profile, Leaderboard, or Game missing")
		return
	if not _leaderboard.has_method("resolve_name") or not _leaderboard.has_signal("name_resolved"):
		_fail("resolve API missing")
		return
	if not _leaderboard.name_resolved.is_connected(_on_name_resolved):
		_leaderboard.name_resolved.connect(_on_name_resolved)
	if _leaderboard.has_signal("submit_attempted") and not _leaderboard.submit_attempted.is_connected(_on_submit_attempted):
		_leaderboard.submit_attempted.connect(_on_submit_attempted)
	_db_path = ProjectSettings.globalize_path("user://t37-claim.sqlite")
	_log_path = ProjectSettings.globalize_path("user://t37-server.log")
	_seed_path = ProjectSettings.globalize_path("user://t37-seed.mjs")
	if not _start_server():
		return
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	OS.set_environment("SQUISH_LEADERBOARD_KEY", "devkey")

	var natasha_id := ""
	if not await _case_existing_name(natasha_id):
		return
	natasha_id = String(_profile.player_id)
	if not await _case_case_insensitive(natasha_id):
		return
	if not await _case_new_name_persists():
		return
	if not await _case_sanitize():
		return
	if not await _case_ambiguous():
		return
	if not await _case_stale_success():
		return

	_game.high_score = 0
	_game.restart()
	await process_frame
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load main.tscn")
		return
	for _i in 4:
		await process_frame
	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)

	if not await _case_return_key_one_score(main):
		return
	if not await _case_focus_one_score(main):
		return
	if not await _case_save_one_score(main):
		return
	if not await _case_decline_zero(main):
		return
	if not await _case_cancelled_skip_then_save(main):
		return
	if not await _case_ambiguous_no_score(main):
		return
	if not await _case_title_commits(main, natasha_id):
		return
	if not await _case_late_claim_posts_score(main):
		return
	if not await _case_transport_no_score(main):
		return
	if not await _case_rate_limit_no_score(main):
		return

	_cleanup()
	print("NAME_CLAIM PASS cases=%d" % _cases_passed)
	quit(0)


func _on_name_resolved(_generation: int, ok: bool, info: Dictionary) -> void:
	_got_resolve = true
	_resolve_ok = ok
	_resolve_info = info


func _on_submit_attempted(_token: int, _attempt: int) -> void:
	_names.append(String(_profile.player_name))


func _case_existing_name(natasha_id: String) -> bool:
	print("NAME_CLAIM case 1 create Natasha and reload")
	_fresh_profile()
	if not await _resolve("Natasha"):
		return _fail("case 1: resolve did not finish")
	if not _resolve_ok:
		return _fail("case 1: Natasha resolve failed %s" % _resolve_info)
	natasha_id = String(_profile.player_id)
	if not _is_uuid(natasha_id):
		return _fail("case 1: id is not a uuid: %s" % natasha_id)
	if String(_profile.player_name) != "Natasha":
		return _fail("case 1: name '%s'" % _profile.player_name)
	if String(_profile.players.get("natasha", "")) != natasha_id:
		return _fail("case 1: players[natasha] is not the resolved id")
	_profile._load_or_create()
	if String(_profile.player_id) != natasha_id or String(_profile.player_name) != "Natasha":
		return _fail("case 1: reload dropped %s/%s" % [_profile.player_id, _profile.player_name])
	_cases_passed += 1
	print("NAME_CLAIM case 1 pass id=%s" % natasha_id)
	return true


func _case_case_insensitive(natasha_id: String) -> bool:
	print("NAME_CLAIM case 2 natasha adopts Natasha's id")
	_fresh_profile()
	var local_id := String(_profile.player_id)
	if local_id == natasha_id:
		return _fail("case 2: fresh id collided with Natasha")
	if not await _resolve("natasha"):
		return _fail("case 2: resolve did not finish")
	if not _resolve_ok:
		return _fail("case 2: resolve failed %s" % _resolve_info)
	if String(_profile.player_id) != natasha_id:
		return _fail("case 2: id %s want %s" % [_profile.player_id, natasha_id])
	if String(_profile.player_name) != "Natasha":
		return _fail("case 2: display '%s' want Natasha" % _profile.player_name)
	if bool(_resolve_info.get("created", true)):
		return _fail("case 2: existing name was created again")
	if String(_profile.players.get("natasha", "")) != natasha_id:
		return _fail("case 2: mapping was not overwritten")
	_cases_passed += 1
	print("NAME_CLAIM case 2 pass")
	return true


func _case_new_name_persists() -> bool:
	print("NAME_CLAIM case 3 new name survives reload")
	_fresh_profile()
	var local_id := String(_profile.player_id)
	if not await _resolve("BrandNew"):
		return _fail("case 3: resolve did not finish")
	if not _resolve_ok:
		return _fail("case 3: resolve failed %s" % _resolve_info)
	var created_id := String(_profile.player_id)
	if created_id == local_id or not _is_uuid(created_id):
		return _fail("case 3: id %s did not replace local %s" % [created_id, local_id])
	if not bool(_resolve_info.get("created", false)):
		return _fail("case 3: new name was not created")
	if String(_profile.player_name) != "BrandNew":
		return _fail("case 3: name '%s'" % _profile.player_name)
	_profile._load_or_create()
	if String(_profile.player_id) != created_id or String(_profile.player_name) != "BrandNew":
		return _fail("case 3: reload dropped the new id")
	if String(_profile.players.get("brandnew", "")) != created_id:
		return _fail("case 3: reload dropped players[brandnew]")
	_cases_passed += 1
	print("NAME_CLAIM case 3 pass id=%s" % created_id)
	return true


func _case_sanitize() -> bool:
	print("NAME_CLAIM case 4 server sanitize")
	_fresh_profile()
	if not await _resolve("  Nat  asha "):
		return _fail("case 4: resolve did not finish")
	if not _resolve_ok:
		return _fail("case 4: resolve failed %s" % _resolve_info)
	if String(_profile.player_name) != "Nat asha":
		return _fail("case 4: name '%s' want 'Nat asha'" % _profile.player_name)
	_cases_passed += 1
	print("NAME_CLAIM case 4 pass")
	return true


func _case_ambiguous() -> bool:
	print("NAME_CLAIM case 5 409 does not adopt")
	_fresh_profile()
	var before_id := String(_profile.player_id)
	var before_players := JSON.stringify(_profile.players)
	var pushes := int(_leaderboard._profile_push_count)
	if not await _resolve("Twin"):
		return _fail("case 5: resolve did not finish")
	if _resolve_ok:
		return _fail("case 5: ambiguous name succeeded")
	if String(_resolve_info.get("reason", "")) != "http_409":
		return _fail("case 5: reason '%s' want http_409" % _resolve_info.get("reason", ""))
	if not _identity_held(before_id, "", before_players):
		return _fail("case 5: 409 changed identity")
	if int(_leaderboard._profile_push_count) != pushes:
		return _fail("case 5: 409 pushed a profile")
	_cases_passed += 1
	print("NAME_CLAIM case 5 pass")
	return true


func _case_stale_success() -> bool:
	print("NAME_CLAIM case 6 stale resolve does not adopt")
	_fresh_profile()
	var before_id := String(_profile.player_id)
	var before_players := JSON.stringify(_profile.players)
	_arm()
	var gen := int(_leaderboard.resolve_name("LateWin"))
	_leaderboard.retire_name_resolve()
	_leaderboard._on_resolve_finished(true, 200, {
		"player_id": LATE_ID,
		"name": "LateWin",
		"avatar": "bear_bounce",
		"created": true,
	}, "", gen)
	for _i in 20:
		await process_frame
	if _got_resolve:
		return _fail("case 6: stale resolve was delivered")
	if not _identity_held(before_id, "", before_players):
		return _fail("case 6: stale success adopted %s" % _profile.player_id)
	_cases_passed += 1
	print("NAME_CLAIM case 6 pass")
	return true


func _case_return_key_one_score(main: Node) -> bool:
	print("NAME_CLAIM case 7 return key submits once")
	return await _one_score(main, "Scorer", "return", 710)


func _case_focus_one_score(main: Node) -> bool:
	print("NAME_CLAIM case 8 focus loss submits once")
	return await _one_score(main, "Mo", "focus", 640)


func _case_save_one_score(main: Node) -> bool:
	print("NAME_CLAIM case 9 save button submits once")
	return await _one_score(main, "Lux", "save", 610)


func _one_score(main: Node, typed: String, how: String, points: int) -> bool:
	_unnamed()
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, points):
		return false
	var edit := _edit(main)
	var save := _button(main, "SaveButton")
	if edit == null or save == null or not edit.visible:
		return _fail("case %s: name prompt missing" % how)
	edit.text = typed
	_arm()
	if how == "return":
		edit.text_submitted.emit(typed)
	elif how == "focus":
		edit.grab_focus()
		await process_frame
		edit.release_focus()
	else:
		edit.grab_focus()
		await process_frame
		save.pressed.emit()
	if not await _wait_resolve():
		return _fail("case %s: resolve did not finish" % how)
	if not _resolve_ok:
		return _fail("case %s: resolve failed %s" % [how, _resolve_info])
	if String(_profile.player_name) != typed:
		return _fail("case %s: name '%s'" % [how, _profile.player_name])
	var after := _attempt_snapshot()
	if after.x != before.x + 1 or after.y != before.y + 1:
		return _fail("case %s: submissions %s → %s" % [how, before, after])
	if _names.size() != names_before + 1 or String(_names[_names.size() - 1]) != typed:
		return _fail("case %s: submit carried %s" % [how, _names])
	_arm()
	if edit.has_focus():
		edit.release_focus()
		for _i in 8:
			await process_frame
	if _attempt_snapshot() != after:
		return _fail("case %s: blur posted a second score" % how)
	_cases_passed += 1
	print("NAME_CLAIM %s pass id=%s" % [how, _profile.player_id])
	return true


func _case_decline_zero(main: Node) -> bool:
	print("NAME_CLAIM case 10 decline submits nothing")
	_unnamed()
	var before_id := String(_profile.player_id)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, 550):
		return false
	var edit := _edit(main)
	var skip := _button(main, "SkipButton")
	if edit == null or skip == null:
		return _fail("case 10: prompt missing")
	edit.text = "Sam"
	edit.grab_focus()
	await process_frame
	_arm()
	skip.button_down.emit()
	edit.focus_exited.emit()
	skip.pressed.emit()
	for _i in 20:
		await process_frame
	if _got_resolve:
		return _fail("case 10: decline resolved")
	if _attempt_snapshot() != before or _names.size() != names_before:
		return _fail("case 10: decline submitted")
	if String(_profile.player_id) != before_id or String(_profile.player_name) != "":
		return _fail("case 10: decline changed identity")
	_cases_passed += 1
	print("NAME_CLAIM case 10 pass")
	return true


func _case_cancelled_skip_then_save(main: Node) -> bool:
	print("NAME_CLAIM case 11 cancelled Not now still saves")
	_unnamed()
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, 460):
		return false
	var edit := _edit(main)
	var skip := _button(main, "SkipButton")
	if edit == null or skip == null:
		return _fail("case 11: prompt missing")
	edit.text = "Nia"
	edit.grab_focus()
	await process_frame
	_arm()
	skip.button_down.emit()
	edit.focus_exited.emit()
	skip.button_up.emit()
	for _i in 8:
		await process_frame
	if _got_resolve or _attempt_snapshot() != before:
		return _fail("case 11: cancelled Not now resolved or submitted")
	_arm()
	edit.text_submitted.emit("Nia")
	if not await _wait_resolve():
		return _fail("case 11: save after cancel did not resolve")
	if not _resolve_ok or String(_profile.player_name) != "Nia":
		return _fail("case 11: save did not adopt, ok=%s name=%s" % [_resolve_ok, _profile.player_name])
	var after := _attempt_snapshot()
	if after.x != before.x + 1 or after.y != before.y + 1 or _names.size() != names_before + 1:
		return _fail("case 11: submissions %s → %s" % [before, after])
	_cases_passed += 1
	print("NAME_CLAIM case 11 pass")
	return true


func _case_ambiguous_no_score(main: Node) -> bool:
	print("NAME_CLAIM case 12 409 submits nothing")
	_unnamed()
	var before_id := String(_profile.player_id)
	var before_players := JSON.stringify(_profile.players)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, 480):
		return false
	var edit := _edit(main)
	var prompt := _prompt(main)
	if edit == null or prompt == null:
		return _fail("case 12: prompt missing")
	edit.text = "Twin"
	_arm()
	edit.text_submitted.emit("Twin")
	if not await _wait_resolve():
		return _fail("case 12: resolve did not finish")
	if _resolve_ok:
		return _fail("case 12: Twin was adopted")
	if not _identity_held(before_id, "", before_players):
		return _fail("case 12: 409 changed identity")
	if _attempt_snapshot() != before or _names.size() != names_before:
		return _fail("case 12: 409 submitted")
	if edit.text != "Twin":
		return _fail("case 12: field dropped Twin")
	if prompt.text.find("409") < 0:
		return _fail("case 12: prompt '%s' does not name 409" % prompt.text)
	_cases_passed += 1
	print("NAME_CLAIM case 12 pass")
	return true


func _case_title_commits(main: Node, natasha_id: String) -> bool:
	print("NAME_CLAIM case 13 title commits three ways")
	if not await _title_commit(main, "return", "ReturnKid", ""):
		return false
	if not await _title_commit(main, "focus", "BlurKid", ""):
		return false
	if not await _title_commit(main, "done", "natasha", natasha_id):
		return false
	_cases_passed += 1
	print("NAME_CLAIM case 13 pass")
	return true


func _title_commit(main: Node, how: String, typed: String, expect_id: String) -> bool:
	_unnamed()
	var title := main.get_node_or_null("Title")
	if title == null or not title.has_method("show_menu"):
		return _fail("case 13: Title missing")
	title.show_menu()
	await process_frame
	await process_frame
	var entry := title.get_node_or_null("NameEntry")
	var edit := title.get_node_or_null("NameEntry/NameEdit") as LineEdit
	var confirm := title.get_node_or_null("NameEntry/ConfirmButton") as Button
	if entry == null or edit == null or confirm == null:
		return _fail("case 13: name prompt missing")
	if not entry.visible:
		entry.open(false)
		await process_frame
	edit.text = typed
	_arm()
	if how == "return":
		edit.text_submitted.emit(typed)
	elif how == "focus":
		edit.grab_focus()
		await process_frame
		edit.release_focus()
	else:
		confirm.pressed.emit()
	if not await _wait_resolve():
		return _fail("case 13 %s: resolve did not finish" % how)
	if not _resolve_ok:
		return _fail("case 13 %s: resolve failed %s" % [how, _resolve_info])
	if expect_id != "" and String(_profile.player_id) != expect_id:
		return _fail("case 13 %s: id %s want %s" % [how, _profile.player_id, expect_id])
	if expect_id == "" and String(_profile.player_name) != typed:
		return _fail("case 13 %s: name '%s'" % [how, _profile.player_name])
	if expect_id != "" and String(_profile.player_name) != "Natasha":
		return _fail("case 13 %s: display '%s'" % [how, _profile.player_name])
	var kept := String(_profile.player_id)
	_profile._load_or_create()
	if String(_profile.player_id) != kept:
		return _fail("case 13 %s: reload dropped id" % how)
	return true


func _case_late_claim_posts_score(main: Node) -> bool:
	print("NAME_CLAIM case 16 a claim landing after game over still posts")
	_unnamed()
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, 390):
		return false
	# The title's claim, not this invite's. The invite must not drop it.
	_arm()
	_leaderboard.resolve_name("LatePost")
	if not await _wait_resolve():
		return _fail("case 16: resolve did not finish")
	if not _resolve_ok or String(_profile.player_name) != "LatePost":
		return _fail("case 16: did not adopt %s" % _resolve_info)
	var after := _attempt_snapshot()
	if after.x != before.x + 1 or after.y != before.y + 1:
		return _fail("case 16: submissions %s → %s" % [before, after])
	if _names.size() != names_before + 1 or String(_names[_names.size() - 1]) != "LatePost":
		return _fail("case 16: submit carried %s" % _names)
	var save := _button(main, "SaveButton")
	if save != null and save.visible:
		save.pressed.emit()
		for _i in 8:
			await process_frame
	if _attempt_snapshot() != after:
		return _fail("case 16: save posted a second score")
	_cases_passed += 1
	print("NAME_CLAIM case 16 pass")
	return true


func _case_transport_no_score(main: Node) -> bool:
	print("NAME_CLAIM case 14 transport failure submits nothing")
	_unnamed()
	var before_id := String(_profile.player_id)
	var before_players := JSON.stringify(_profile.players)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, 430):
		return false
	var edit := _edit(main)
	var prompt := _prompt(main)
	if edit == null or prompt == null:
		return _fail("case 14: prompt missing")
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:9")
	edit.text = "OffKid"
	_arm()
	edit.text_submitted.emit("OffKid")
	if not await _wait_resolve(3000):
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 14: resolve did not finish")
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	if _resolve_ok:
		return _fail("case 14: transport failure adopted")
	if not _identity_held(before_id, "", before_players):
		return _fail("case 14: transport failure changed identity")
	if _attempt_snapshot() != before or _names.size() != names_before:
		return _fail("case 14: transport failure submitted")
	if edit.text != "OffKid":
		return _fail("case 14: field dropped OffKid")
	var line := prompt.text
	if line.find("409") >= 0 or line.find("429") >= 0 or line == "Name this score":
		return _fail("case 14: prompt '%s' is not a transport failure" % line)
	_cases_passed += 1
	print("NAME_CLAIM case 14 pass line=%s" % line)
	return true


func _case_rate_limit_no_score(main: Node) -> bool:
	print("NAME_CLAIM case 15 429 submits nothing")
	_unnamed()
	if not await _burn_resolve_limit():
		return _fail("case 15: could not fill the resolve limit")
	var before_id := String(_profile.player_id)
	var before_players := JSON.stringify(_profile.players)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, 420):
		return false
	var edit := _edit(main)
	var prompt := _prompt(main)
	if edit == null or prompt == null:
		return _fail("case 15: prompt missing")
	edit.text = "RateKid"
	_arm()
	edit.text_submitted.emit("RateKid")
	if not await _wait_resolve():
		return _fail("case 15: resolve did not finish")
	if _resolve_ok:
		return _fail("case 15: rate limit still adopted")
	if String(_resolve_info.get("reason", "")) != "http_429":
		return _fail("case 15: reason '%s' want http_429" % _resolve_info.get("reason", ""))
	if not _identity_held(before_id, "", before_players):
		return _fail("case 15: 429 changed identity")
	if _attempt_snapshot() != before or _names.size() != names_before:
		return _fail("case 15: 429 submitted")
	if edit.text != "RateKid":
		return _fail("case 15: field dropped RateKid")
	if prompt.text.find("429") < 0:
		return _fail("case 15: prompt '%s' does not name 429" % prompt.text)
	if prompt.text == _prompt_line_409():
		return _fail("case 15: 429 reused the 409 sentence")
	_cases_passed += 1
	print("NAME_CLAIM case 15 pass")
	return true


func _prompt_line_409() -> String:
	if _leaderboard.has_method("offline_line"):
		return String(_leaderboard.offline_line("http_409"))
	return ""


func _burn_resolve_limit() -> bool:
	# Earlier cases already spent part of the 60/min resolve budget.
	for i in 80:
		var code := await _raw_resolve("Burn%d" % i)
		if code == 429:
			return true
		if code != 200 and code != 201:
			print("NAME_CLAIM burn %d got %d" % [i, code])
			return false
	return false


func _raw_resolve(player_name: String) -> int:
	var http := HTTPRequest.new()
	http.timeout = 3.0
	root.add_child(http)
	var done := {"got": false, "code": 0}
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		done.got = true
		done.code = code
	)
	var err := http.request(
		"http://127.0.0.1:%d/v1/players/resolve" % PORT,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"name": player_name})
	)
	if err != OK:
		http.queue_free()
		return -1
	for _i in 40:
		if bool(done.got):
			break
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 50:
			await process_frame
	var code := int(done.code)
	http.queue_free()
	return code


func _resolve(player_name: String) -> bool:
	_arm()
	_leaderboard.resolve_name(player_name)
	return await _wait_resolve()


func _arm() -> void:
	_got_resolve = false
	_resolve_ok = false
	_resolve_info = {}


func _wait_resolve(ms: int = 3000) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		if _got_resolve:
			return true
		await process_frame
	return _got_resolve


func _identity_held(id: String, player_name: String, players_json: String) -> bool:
	return (
		String(_profile.player_id) == id
		and String(_profile.player_name) == player_name
		and JSON.stringify(_profile.players) == players_json
	)


func _fresh_profile() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("profile.save"):
		dir.remove("profile.save")
	_profile._load_or_create()


func _unnamed() -> void:
	_fresh_profile()


func _attempt_snapshot() -> Vector2i:
	var counts: Dictionary = _leaderboard.submit_attempts
	var total := 0
	for value in counts.values():
		total += int(value)
	return Vector2i(counts.size(), total)


func _go_game_over(main: Node, points: int) -> bool:
	if _game.state == _game.GAME_OVER:
		_game.restart()
		await process_frame
		await process_frame
	var title := main.get_node_or_null("Title")
	if title != null and title.visible:
		var entry := title.get_node_or_null("NameEntry")
		if entry != null and entry.has_method("release_name_focus"):
			entry.call("release_name_focus")
		await process_frame
		_push_action(main, "launch_ball")
		await process_frame
		await process_frame
		_push_action(main, "launch_ball", false)
		await process_frame
		if title.visible:
			_fail("could not leave the title")
			return false
	_game.add_score(points)
	for _i in 3:
		_game.on_ball_drained()
		await physics_frame
		await process_frame
	var game_over := main.get_node_or_null("GameOver")
	if game_over == null or not game_over.visible or _game.state != _game.GAME_OVER:
		_fail("expected GAME_OVER")
		return false
	return true


func _edit(main: Node) -> LineEdit:
	var game_over := main.get_node_or_null("GameOver")
	if game_over == null:
		return null
	return game_over.get_node_or_null("NameEdit") as LineEdit


func _prompt(main: Node) -> Label:
	var game_over := main.get_node_or_null("GameOver")
	if game_over == null:
		return null
	return game_over.get_node_or_null("NamePrompt") as Label


func _button(main: Node, node_name: String) -> Button:
	var game_over := main.get_node_or_null("GameOver")
	if game_over == null:
		return null
	return game_over.get_node_or_null(node_name) as Button


func _push_action(main: Node, action: StringName, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	main.get_viewport().push_input(ev)


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _start_server() -> bool:
	_delete_db()
	if not _spawn():
		return _fail("server did not spawn")
	if not _health():
		return _fail("server did not become healthy")
	_kill_server()
	OS.delay_msec(400)
	if not _seed_twins():
		return _fail("could not seed the ambiguous name")
	if not _spawn():
		return _fail("server did not respawn")
	if not _health():
		return _fail("server did not become healthy after seed")
	return true


func _spawn() -> bool:
	var root_path := ProjectSettings.globalize_path("res://")
	var cmd := "cd '%s/server' && exec env DB_PATH='%s' SQUISH_KEY=devkey PORT=%d node --no-warnings=ExperimentalWarning src/index.js > '%s' 2>&1" % [root_path, _db_path, PORT, _log_path]
	_server_pid = OS.create_process("/bin/bash", ["-lc", cmd])
	return _server_pid > 0


func _health() -> bool:
	for _i in 25:
		var output: Array = []
		var code := OS.execute("/usr/bin/curl", ["-sf", "--max-time", "1", "http://127.0.0.1:%d/healthz" % PORT], output, true, false)
		if code == 0 and FileAccess.file_exists(_db_path):
			return true
		OS.delay_msec(200)
	if FileAccess.file_exists(_log_path):
		print(FileAccess.get_file_as_string(_log_path))
	return false


func _seed_twins() -> bool:
	var script := """import { DatabaseSync } from 'node:sqlite';
const db = new DatabaseSync(process.argv[2]);
const now = new Date().toISOString();
const ins = db.prepare('INSERT INTO scores (player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?)');
ins.run('%s', 'Twin', 10, 'squish/1.0', now);
ins.run('%s', 'Twin', 20, 'squish/1.0', now);
db.close();
""" % [TWIN_A, TWIN_B]
	var file := FileAccess.open(_seed_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(script)
	file.close()
	var output: Array = []
	var code := OS.execute("/bin/bash", ["-lc", "node '%s' '%s'" % [_seed_path, _db_path]], output, true, false)
	if code != 0:
		print("NAME_CLAIM seed exit %s %s" % [code, output])
		return false
	return true


func _kill_server() -> void:
	if _server_pid <= 0:
		return
	var pid := str(_server_pid)
	OS.execute("/bin/kill", ["-TERM", pid])
	for _i in 20:
		var gone := OS.execute("/bin/kill", ["-0", pid])
		if gone != 0:
			break
		OS.delay_msec(100)
	OS.execute("/bin/kill", ["-KILL", pid])
	_server_pid = -1


func _delete_db() -> void:
	for suffix in ["", "-wal", "-shm"]:
		var path: String = _db_path + String(suffix)
		if path != "" and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _cleanup() -> void:
	_kill_server()
	_delete_db()
	if _seed_path != "" and FileAccess.file_exists(_seed_path):
		DirAccess.remove_absolute(_seed_path)
	if _log_path != "" and FileAccess.file_exists(_log_path):
		DirAccess.remove_absolute(_log_path)


func _is_uuid(value: String) -> bool:
	var re := RegEx.new()
	if re.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$") != OK:
		return false
	return re.search(value) != null


func _fail(message: String) -> bool:
	push_error("NAME_CLAIM FAIL %s" % message)
	print("NAME_CLAIM FAIL %s" % message)
	_cleanup()
	quit(1)
	return false
