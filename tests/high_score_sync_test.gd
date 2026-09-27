extends SceneTree

## D-057. HIGH is max(this device's best, the server's best) for one player id.
## The id is the one the request was made for, not whoever is current when the
## body arrives. A smaller server number never rewrites the file.

const PORT := 18792
const SENTINEL := "http://127.0.0.1:1"
const ID_X := "11111111-2222-4333-8444-555555555555"
const ID_A := "aaaaaaaa-1111-4222-8333-444444444444"
const ID_B := "bbbbbbbb-1111-4222-8333-555555555555"
const ID_C := "cccccccc-1111-4222-8333-666666666666"
const ID_Y := "dddddddd-1111-4222-8333-777777777777"
const ID_S := "eeeeeeee-1111-4222-8333-888888888888"
const ID_O := "ffffffff-1111-4222-8333-999999999999"
const ID_R := "12121212-3434-4567-890a-bcbcbcbcbcbc"

var _cases_passed: int = 0
var _profile: Node
var _leaderboard: Node
var _game: Node
var _main: Node
var _server_pid: int = -1
var _log_path: String = ""
var _offline_hits: int = 0
var _last_over: Dictionary = {}
var _restore_ok: bool = false
var _restore_reason: String = ""
var _got_restore: bool = false
var _states: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("HIGH_SYNC start")
	_profile = root.get_node_or_null("/root/Profile")
	_leaderboard = root.get_node_or_null("/root/Leaderboard")
	_game = root.get_node_or_null("/root/Game")
	if _profile == null or _leaderboard == null or _game == null:
		_fail("Profile, Leaderboard, or Game missing")
		return
	if not _game.has_method("reconcile_best") or not _game.has_signal("high_score_changed"):
		_fail("reconcile API missing")
		return
	if not _leaderboard.offline.is_connected(_on_offline):
		_leaderboard.offline.connect(_on_offline)
	if not _game.game_over.is_connected(_on_game_over):
		_game.game_over.connect(_on_game_over)
	if _leaderboard.has_signal("restore_finished") and not _leaderboard.restore_finished.is_connected(_on_restore_finished):
		_leaderboard.restore_finished.connect(_on_restore_finished)
	_log_path = ProjectSettings.globalize_path("user://t42-high-sync.log")
	if not _start_server():
		return
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	OS.set_environment("SQUISH_LEADERBOARD_KEY", "devkey")

	if not await _case_sentinel():
		return
	if not await _load_main():
		return
	if not await _state_unnamed_title():
		return
	if not await _case_boot():
		return
	if not await _state_during_play_and_game_over():
		return
	if not await _case_never_lower():
		return
	if not await _case_unknown_and_transport():
		return
	if not await _case_misattribution():
		return
	if not await _case_claim():
		return
	if not await _case_submit():
		return
	if not await _case_restore():
		return
	if not _states_complete():
		return

	_cleanup()
	print("HIGH_SYNC PASS cases=%d" % _cases_passed)
	quit(0)


func _on_offline(_reason: String) -> void:
	_offline_hits += 1


func _on_game_over(final_score: int, is_high: bool) -> void:
	_last_over = {"score": final_score, "is_high": is_high}


func _on_restore_finished(ok: bool, reason: String) -> void:
	_got_restore = true
	_restore_ok = ok
	_restore_reason = reason


func _saw(state_name: String, detail: String) -> void:
	_states[state_name] = true
	print("HIGH_SYNC state %s %s" % [state_name, detail])


func _states_complete() -> bool:
	for state_name in ["unnamed-title", "named-idle-title", "welcome-back-confirming", "during-play", "game-over"]:
		if not bool(_states.get(state_name, false)):
			return _fail("missing state %s" % state_name)
	return true


func _case_sentinel() -> bool:
	print("HIGH_SYNC case 8 closed sentinel")
	OS.set_environment("SQUISH_LEADERBOARD_URL", SENTINEL)
	_profile.player_id = ID_X
	_profile.player_name = "Dad"
	_profile.players = {"dad": ID_X}
	_profile.avatar_id = ""
	_profile.avatars = {}
	_profile._save()
	if not bool(_leaderboard._profile_http_skipped()):
		OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
		return _fail("case 8: sentinel was not skipped")
	var before_fetch := int(_leaderboard.best_fetch_count)
	var before_http := _http_nodes()
	_leaderboard._boot_restore_profile()
	_leaderboard._fetch_server_best(ID_X)
	_leaderboard.resolve_name("Dad")
	for _i in 8:
		await process_frame
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	if int(_leaderboard.best_fetch_count) != before_fetch or _http_nodes() != before_http:
		return _fail("case 8: requests best_fetch %s→%s http %s→%s" % [before_fetch, _leaderboard.best_fetch_count, before_http, _http_nodes()])
	_cases_passed += 1
	print("HIGH_SYNC case 8 pass best_fetch_count=%d http_nodes=%d" % [before_fetch, before_http])
	return true


func _state_unnamed_title() -> bool:
	print("HIGH_SYNC state unnamed-title")
	_fresh_unnamed()
	var before_fetch := int(_leaderboard.best_fetch_count)
	_leaderboard._boot_restore_profile()
	for _i in 6:
		await process_frame
	var high := _hud_text()
	if high != "HIGH  0":
		return _fail("unnamed-title: HUD '%s' want HIGH  0" % high)
	if String(_profile.player_name) != "":
		return _fail("unnamed-title: name '%s'" % _profile.player_name)
	if int(_leaderboard.best_fetch_count) != before_fetch:
		return _fail("unnamed-title: best fetch %s → %s" % [before_fetch, _leaderboard.best_fetch_count])
	var title := _main.get_node_or_null("Title")
	if title == null or not title.visible:
		return _fail("unnamed-title: title not showing")
	_saw("unnamed-title", "HIGH='%s' best_fetch_count=%d" % [high, before_fetch])
	return true


func _case_boot() -> bool:
	print("HIGH_SYNC case 1 boot")
	if not await _seed_score(ID_X, "Dad", 14300):
		return _fail("case 1: could not seed 14300")
	_game.high_scores[ID_X] = 7400
	_game._save_high_scores()
	if not bool(_profile.adopt_identity(ID_X, "Dad", "")):
		return _fail("case 1: could not adopt Dad")
	if int(_game.high_score) != 7400:
		return _fail("case 1: device high %s want 7400" % _game.high_score)
	if _hud_text() != "HIGH  7400":
		return _fail("case 1: HUD '%s' before reconcile" % _hud_text())
	var before_fetch := int(_leaderboard.best_fetch_count)
	_leaderboard._boot_restore_profile()
	if not await _wait_high(ID_X, 14300, 2000):
		return _fail("case 1: high did not become 14300 (hud '%s')" % _hud_text())
	if int(_leaderboard.best_fetch_count) < before_fetch + 1:
		return _fail("case 1: boot did not ask /me")
	if _hud_text() != "HIGH  14300":
		return _fail("case 1: HUD '%s'" % _hud_text())
	if not _saved_high_is(ID_X, 14300):
		return _fail("case 1: file %s" % _high_file())
	_game._load_high_scores()
	if int(_game.high_score) != 14300 or int(_game.high_scores.get(ID_X, 0)) != 14300:
		return _fail("case 1: reload high %s" % _game.high_scores)
	var title := _main.get_node_or_null("Title")
	if title == null or not title.visible or int(_game.state) != int(_game.READY):
		return _fail("case 1: expected named idle title")
	_saw("named-idle-title", "HIGH='%s'" % _hud_text())
	_cases_passed += 1
	print("HIGH_SYNC case 1 pass")
	return true


func _state_during_play_and_game_over() -> bool:
	print("HIGH_SYNC case 7 is_high_score and play states")
	var play := _main.get_node_or_null("Title/PlayButton") as Button
	if play != null:
		play.pressed.emit()
	for _i in 4:
		await process_frame
	_game.add_score(9000)
	await physics_frame
	if int(_game.state) != int(_game.PLAYING):
		return _fail("during-play: state %s" % _game.state)
	if _hud_text() != "HIGH  14300":
		return _fail("during-play: HUD '%s'" % _hud_text())
	var title := _main.get_node_or_null("Title")
	if title != null and title.visible:
		return _fail("during-play: title still showing")
	_saw("during-play", "HIGH='%s'" % _hud_text())
	_last_over = {}
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	await process_frame
	if _last_over.is_empty():
		return _fail("case 7: game_over did not emit")
	if int(_last_over.get("score", -1)) != 9000 or bool(_last_over.get("is_high", true)):
		return _fail("case 7: over %s" % _last_over)
	if int(_game.high_score) != 14300:
		return _fail("case 7: high moved to %s" % _game.high_score)
	var label := _over_text()
	if label != "HIGH  14300":
		return _fail("game-over: GameOverHighScoreLabel '%s'" % label)
	var banner := _main.get_node_or_null("GameOver/NewHighScoreLabel") as Label
	if banner == null or banner.visible:
		return _fail("case 7: NEW HIGH SCORE still showing")
	var panel := _main.get_node_or_null("GameOver")
	if panel == null or not panel.visible:
		return _fail("game-over: panel hidden")
	_saw("game-over", "HIGH='%s' is_high_score=false" % label)
	_cases_passed += 1
	print("HIGH_SYNC case 7 pass")
	return true


func _case_never_lower() -> bool:
	print("HIGH_SYNC case 3 never lower")
	if not await _wait_submits_idle(2000):
		return _fail("case 3: score submit still in flight")
	_write_marked_high(ID_X, 20000)
	_game._load_high_scores()
	if int(_game.high_score) != 20000:
		return _fail("case 3: loaded %s" % _game.high_score)
	var before := _high_file()
	if before.find("T42_KEEP") < 0:
		return _fail("case 3: marker missing before fetch")
	_leaderboard._boot_restore_profile()
	await _wait_msec(800)
	if int(_game.high_score) != 20000 or int(_game.high_scores.get(ID_X, 0)) != 20000:
		return _fail("case 3: high lowered to %s" % _game.high_scores)
	var after := _high_file()
	if after.find("T42_KEEP") < 0 or after != before:
		return _fail("case 3: file rewritten (%s)" % after)
	_cases_passed += 1
	print("HIGH_SYNC case 3 pass")
	return true


func _case_unknown_and_transport() -> bool:
	print("HIGH_SYNC case 4 unknown player and transport failure")
	if not bool(_profile.adopt_identity(ID_Y, "Ghost", "")):
		return _fail("case 4: could not adopt Ghost")
	_write_marked_high(ID_Y, 5000)
	_game._load_high_scores()
	if int(_game.high_score) != 5000:
		return _fail("case 4: loaded %s" % _game.high_score)
	var file_before := _high_file()
	var offline_before := _offline_hits
	var top_before := _label_text("Title/TopFiveLabel")
	var over_offline_before := _label_text("GameOver/OfflineLabel")
	_leaderboard._boot_restore_profile()
	await _wait_msec(800)
	if int(_game.high_score) != 5000 or _high_file() != file_before:
		return _fail("case 4: 404 changed device high or file")
	if _offline_hits != offline_before:
		return _fail("case 4: 404 emitted offline")
	if _label_text("Title/TopFiveLabel") != top_before or _label_text("GameOver/OfflineLabel") != over_offline_before:
		return _fail("case 4: 404 changed offline text")
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:9")
	_leaderboard._fetch_server_best(ID_Y)
	await _wait_msec(600)
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	if int(_game.high_score) != 5000 or _high_file() != file_before:
		return _fail("case 4: transport failure changed device high or file")
	if _offline_hits != offline_before:
		return _fail("case 4: transport failure emitted offline")
	if _label_text("Title/TopFiveLabel") != top_before or _label_text("GameOver/OfflineLabel") != over_offline_before:
		return _fail("case 4: transport failure changed offline text")
	_cases_passed += 1
	print("HIGH_SYNC case 4 pass")
	return true


func _case_misattribution() -> bool:
	print("HIGH_SYNC case 5 misattribution")
	if not await _seed_score(ID_A, "Ann", 14300):
		return _fail("case 5: could not seed Ann")
	_game.high_scores[ID_A] = 5000
	_game.high_scores[ID_B] = 1000
	_game._save_high_scores()
	if not bool(_profile.adopt_identity(ID_A, "Ann", "")):
		return _fail("case 5: could not adopt Ann")
	_leaderboard._fetch_server_best(ID_A)
	if int(_game.high_scores.get(ID_A, 0)) != 5000:
		return _fail("case 5: response applied before the identity change")
	if not bool(_profile.adopt_identity(ID_B, "Bea", "")):
		return _fail("case 5: could not adopt Bea")
	if String(_profile.player_id) != ID_B:
		return _fail("case 5: current id %s" % _profile.player_id)
	if int(_game.high_scores.get(ID_A, 0)) != 5000 or int(_game.high_scores.get(ID_B, 0)) != 1000:
		return _fail("case 5: slots moved during the switch %s" % _game.high_scores)
	if not await _wait_slot(ID_A, 14300, 2000):
		return _fail("case 5: A's slot stayed %s" % _game.high_scores.get(ID_A, 0))
	if String(_profile.player_id) != ID_B:
		return _fail("case 5: current changed to %s while A's best landed" % _profile.player_id)
	if int(_game.high_scores.get(ID_B, 0)) != 1000:
		return _fail("case 5: B's slot %s" % _game.high_scores.get(ID_B, 0))
	if int(_game.high_score) != 1000:
		return _fail("case 5: current high %s" % _game.high_score)
	if _hud_text() != "HIGH  1000":
		return _fail("case 5: HUD '%s'" % _hud_text())
	_cases_passed += 1
	print("HIGH_SYNC case 5 pass")
	return true


func _case_claim() -> bool:
	print("HIGH_SYNC case 2 claim")
	if not await _seed_score(ID_C, "Cee", 14300):
		return _fail("case 2: could not seed Cee")
	_game.high_scores[ID_B] = 1000
	_game.high_scores[ID_C] = 2000
	_game._save_high_scores()
	if String(_profile.player_id) != ID_B:
		return _fail("case 2: expected Bea current, got %s" % _profile.player_id)
	if _hud_text() != "HIGH  1000":
		return _fail("case 2: HUD '%s' before claim" % _hud_text())
	var title := _main.get_node_or_null("Title")
	if title == null or not title.has_method("show_menu"):
		return _fail("case 2: title missing")
	title.show_menu()
	await process_frame
	var entry := title.get_node_or_null("NameEntry")
	var edit := title.get_node_or_null("NameEntry/NameEdit") as LineEdit
	var confirm := title.get_node_or_null("NameEntry/ConfirmButton") as Button
	var welcome := title.get_node_or_null("NameEntry/WelcomeLabel") as Label
	var yes := title.get_node_or_null("NameEntry/YesButton") as Button
	if entry == null or edit == null or confirm == null or welcome == null or yes == null:
		return _fail("case 2: name prompt missing")
	if not entry.visible:
		entry.open(false)
		await process_frame
	edit.text = "Cee"
	var fetches_before := int(_leaderboard.best_fetch_count)
	confirm.pressed.emit()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000:
		if welcome.visible:
			break
		await process_frame
	if not welcome.visible:
		return _fail("case 2: existing name did not ask welcome back")
	if String(_profile.player_id) != ID_B or int(_game.high_scores.get(ID_C, 0)) != 2000:
		return _fail("case 2: welcome adopted early %s" % _profile.player_id)
	if _hud_text() != "HIGH  1000":
		return _fail("case 2: HUD '%s' changed before That's me" % _hud_text())
	if int(_leaderboard.best_fetch_count) != fetches_before:
		return _fail("case 2: best fetch ran before That's me")
	if welcome.text.find("Cee") < 0:
		return _fail("case 2: welcome '%s'" % welcome.text)
	_saw("welcome-back-confirming", "HIGH='%s' before That's me" % _hud_text())
	yes.pressed.emit()
	if not await _wait_high(ID_C, 14300, 2000):
		return _fail("case 2: claim did not reach 14300 (id %s hud '%s')" % [_profile.player_id, _hud_text()])
	if String(_profile.player_id) != ID_C:
		return _fail("case 2: id %s" % _profile.player_id)
	if _hud_text() != "HIGH  14300":
		return _fail("case 2: HUD '%s'" % _hud_text())
	if int(_game.high_scores.get(ID_B, 0)) != 1000:
		return _fail("case 2: Bea's slot changed %s" % _game.high_scores)
	_cases_passed += 1
	print("HIGH_SYNC case 2 pass")
	return true


func _case_submit() -> bool:
	print("HIGH_SYNC case 6 submit")
	if not await _seed_score(ID_S, "SubKid", 14300):
		return _fail("case 6: could not seed SubKid")
	_game.high_scores[ID_S] = 1000
	_game.high_scores[ID_O] = 0
	_game._save_high_scores()
	if not bool(_profile.adopt_identity(ID_S, "SubKid", "")):
		return _fail("case 6: could not adopt SubKid")
	if int(_game.state) == int(_game.GAME_OVER):
		_game.restart()
		await process_frame
		await process_frame
	_game.add_score(50)
	await physics_frame
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	await physics_frame
	var fetches_before := int(_leaderboard.best_fetch_count)
	_game.on_ball_drained()
	if int(_game.high_scores.get(ID_S, 0)) != 1000:
		return _fail("case 6: best applied before the identity could change")
	if not bool(_profile.adopt_identity(ID_O, "OtherKid", "")):
		return _fail("case 6: could not adopt OtherKid")
	if int(_game.high_scores.get(ID_S, 0)) != 1000:
		return _fail("case 6: best applied during the switch")
	if not await _wait_slot(ID_S, 14300, 2000):
		return _fail("case 6: submitting id stayed %s" % _game.high_scores.get(ID_S, 0))
	if String(_profile.player_id) != ID_O:
		return _fail("case 6: current id %s" % _profile.player_id)
	if int(_game.high_scores.get(ID_O, 0)) != 0:
		return _fail("case 6: OtherKid slot %s" % _game.high_scores.get(ID_O, 0))
	if _hud_text() != "HIGH  0":
		return _fail("case 6: HUD '%s' followed the other player" % _hud_text())
	if int(_leaderboard.best_fetch_count) != fetches_before:
		return _fail("case 6: /me ran; the 201 should have been the source")
	_cases_passed += 1
	print("HIGH_SYNC case 6 pass")
	return true


func _case_restore() -> bool:
	print("HIGH_SYNC case 9 restore_profile")
	if not await _seed_score(ID_R, "RestKid", 14300):
		return _fail("case 9: could not seed RestKid")
	if not await _seed_profile(ID_R, "RestKid"):
		return _fail("case 9: could not seed RestKid's profile")
	_game.high_scores[ID_R] = 100
	_game._save_high_scores()
	_got_restore = false
	_restore_ok = false
	_leaderboard.restore_profile(ID_R)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000:
		if String(_profile.player_id) == ID_R and int(_game.high_score) == 14300 and _hud_text() == "HIGH  14300":
			break
		await process_frame
	if not _got_restore or not _restore_ok:
		return _fail("case 9: restore %s %s" % [_restore_ok, _restore_reason])
	if String(_profile.player_id) != ID_R or int(_game.high_score) != 14300:
		return _fail("case 9: id %s high %s" % [_profile.player_id, _game.high_score])
	if _hud_text() != "HIGH  14300":
		return _fail("case 9: HUD '%s'" % _hud_text())
	if int(_game.high_scores.get(ID_R, 0)) != 14300:
		return _fail("case 9: slot %s" % _game.high_scores)
	_cases_passed += 1
	print("HIGH_SYNC case 9 pass")
	return true


func _load_main() -> bool:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		return _fail("could not load main.tscn")
	if change_scene_to_packed(packed) != OK:
		return _fail("could not show main.tscn")
	for _i in 4:
		await process_frame
	_main = current_scene
	if _main == null:
		return _fail("main scene did not load")
	_silence_table_drain(_main)
	return true


func _wait_high(player_id: String, want: int, ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		if String(_profile.player_id) == player_id and int(_game.high_score) == want:
			return true
		await process_frame
	return String(_profile.player_id) == player_id and int(_game.high_score) == want


func _wait_slot(player_id: String, want: int, ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		if int(_game.high_scores.get(player_id, 0)) == want:
			return true
		await process_frame
	return int(_game.high_scores.get(player_id, 0)) == want


func _submits_idle() -> bool:
	var states: Dictionary = _leaderboard._submit_state
	for key in states.keys():
		var state: Dictionary = states[key]
		if bool(state.get("in_flight", false)) or bool(state.get("retry_pending", false)):
			return false
	return true


func _wait_submits_idle(ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		if _submits_idle():
			await process_frame
			return _submits_idle()
		await process_frame
	return _submits_idle()


func _wait_msec(ms: int) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		await process_frame


func _hud_text() -> String:
	if _main == null:
		return ""
	var label := _main.get_node_or_null("HUD/HighScoreLabel") as Label
	if label == null:
		return ""
	return label.text


func _over_text() -> String:
	if _main == null:
		return ""
	var label := _main.get_node_or_null("GameOver/GameOverHighScoreLabel") as Label
	if label == null:
		return ""
	return label.text


func _label_text(path: String) -> String:
	if _main == null:
		return ""
	var label := _main.get_node_or_null(path) as Label
	if label == null:
		return ""
	return label.text


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


func _write_marked_high(player_id: String, value: int) -> void:
	var body := JSON.stringify({"high_scores": {player_id: value}, "T42_KEEP": 1})
	var file := FileAccess.open("user://highscore.save", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(body)


func _http_nodes() -> int:
	var n := 0
	for child in _leaderboard.get_children():
		if child is HTTPRequest:
			n += 1
	return n


func _fresh_unnamed() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("profile.save"):
		dir.remove("profile.save")
	_profile._load_or_create()


func _seed_score(player_id: String, player_name: String, score: int) -> bool:
	var body := '{"player_id":"%s","name":"%s","score":%d,"client":"squish/1.0"}' % [player_id, player_name, score]
	var got := await _http_json(HTTPClient.METHOD_POST, "/v1/scores", body, true)
	if int(got.get("code", 0)) != 201 or String(got.get("text", "")).find("\"best\"") < 0:
		print("HIGH_SYNC seed response %s %s" % [got.get("code", 0), got.get("text", "")])
		return false
	return true


func _seed_profile(player_id: String, player_name: String) -> bool:
	var body := '{"player_id":"%s","name":"%s","avatar":"","client":"squish/1.0"}' % [player_id, player_name]
	var got := await _http_json(HTTPClient.METHOD_PUT, "/v1/profile", body, true)
	if int(got.get("code", 0)) != 200 or String(got.get("text", "")).find("\"player_id\"") < 0:
		print("HIGH_SYNC profile response %s %s" % [got.get("code", 0), got.get("text", "")])
		return false
	return true


func _http_json(method: int, path: String, body: String, with_key: bool) -> Dictionary:
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


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _start_server() -> bool:
	_free_port()
	if not _spawn():
		return _fail("server did not spawn")
	if not _health():
		return _fail("server did not become healthy")
	return true


func _spawn() -> bool:
	var root_path := ProjectSettings.globalize_path("res://")
	var cmd := "cd '%s/server' && exec env DB_PATH=:memory: SQUISH_KEY=devkey PORT=%d node --no-warnings=ExperimentalWarning src/index.js > '%s' 2>&1" % [root_path, PORT, _log_path]
	_server_pid = OS.create_process("/bin/bash", ["-lc", cmd])
	return _server_pid > 0


func _health() -> bool:
	for _i in 25:
		var output: Array = []
		var code := OS.execute("/usr/bin/curl", ["-sf", "--max-time", "1", "http://127.0.0.1:%d/healthz" % PORT], output, true, false)
		if code == 0:
			return true
		OS.delay_msec(200)
	if FileAccess.file_exists(_log_path):
		print(FileAccess.get_file_as_string(_log_path))
	return false


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


func _free_port() -> void:
	OS.execute("/bin/bash", ["-lc", "pids=$(lsof -ti tcp:%d 2>/dev/null || true); if [ -n \"$pids\" ]; then kill $pids 2>/dev/null || true; sleep 0.2; kill -9 $pids 2>/dev/null || true; fi" % PORT])


func _cleanup() -> void:
	_kill_server()
	_free_port()
	if _log_path != "" and FileAccess.file_exists(_log_path):
		DirAccess.remove_absolute(_log_path)


func _fail(message: String) -> bool:
	push_error("HIGH_SYNC FAIL %s" % message)
	print("HIGH_SYNC FAIL %s" % message)
	_cleanup()
	quit(1)
	return false
