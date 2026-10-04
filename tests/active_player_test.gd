extends SceneTree

## D-062. The active player is on the HUD during play, and game over says who
## the score was saved to. "Not you?" opens the title rename and does not
## move a score that already posted. Headless routes no clicks: buttons are
## pressed.emit(), and N is the change_name action.

const PORT := 18798
const SENTINEL := "http://127.0.0.1:1"
const LONG_NAME := "ABCDEFGHIJKLMNOP"
const MIN_TOUCH := 64.0

var _cases_passed: int = 0
var _profile: Node
var _leaderboard: Node
var _game: Node
var _main: Node
var _server_pid: int = -1
var _temp_dir: String = ""
var _log_path: String = ""
var _got_submit := false
var _last_submit: Dictionary = {}
var _offline_reason := ""
var _capture_attempt := false
var _captured_id := ""
var _captured_name := ""

const _HUD_SEAM := {
	"ScoreLabel": true,
	"BallsLabel": true,
	"HighScoreLabel": true,
}
const _HEADER_SEAM := {
	"TitleLabel": true,
	"FinalScoreLabel": true,
	"GameOverHighScoreLabel": true,
	"NewHighScoreLabel": true,
	"YourRankLabel": true,
	"OfflineLabel": true,
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("ACTIVE_PLAYER start")
	DisplayServer.window_set_size(Vector2i(720, 1280))
	_profile = root.get_node_or_null("Profile")
	_leaderboard = root.get_node_or_null("Leaderboard")
	_game = root.get_node_or_null("Game")
	if _profile == null or _leaderboard == null or _game == null:
		_fail("autoloads missing")
		return
	if _leaderboard.has_signal("submitted") and not _leaderboard.submitted.is_connected(_on_submitted):
		_leaderboard.submitted.connect(_on_submitted)
	if _leaderboard.has_signal("offline") and not _leaderboard.offline.is_connected(_on_offline):
		_leaderboard.offline.connect(_on_offline)
	_reset_profile()
	_leaderboard.identity_unconfirmed = false
	_game.high_score = 0
	_game.restart()
	await process_frame
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not change to main.tscn")
		return
	for _i in 4:
		await process_frame
	_main = current_scene
	if _main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain()
	# Game over connects submit_attempted in its _ready. This listener must
	# run after that one, so the screen snapshots the posting name before
	# the test renames the profile.
	if _leaderboard.has_signal("submit_attempted") and not _leaderboard.submit_attempted.is_connected(_on_submit_attempted):
		_leaderboard.submit_attempted.connect(_on_submit_attempted)

	if not await _case_hud():
		return
	if not _start_server():
		return
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	OS.set_environment("SQUISH_LEADERBOARD_KEY", "devkey")
	if not await _case_unnamed_invite():
		return
	if not await _case_unconfirmed_invite():
		return
	if not await _case_saved_binding():
		return
	if not await _case_sixteen_and_emit():
		return
	if not await _case_offline():
		return

	_cleanup()
	print("ACTIVE_PLAYER PASS cases=%d" % _cases_passed)
	quit(0)


func _on_submitted(result: Dictionary) -> void:
	_got_submit = true
	_last_submit = result


func _on_offline(reason: String) -> void:
	_offline_reason = reason


func _on_submit_attempted(_token: int, _attempt: int) -> void:
	if not _capture_attempt:
		return
	_capture_attempt = false
	_captured_id = String(_profile.player_id)
	_captured_name = String(_profile.player_name)


func _case_hud() -> bool:
	print("ACTIVE_PLAYER case hud")
	var hud := _main.get_node_or_null("HUD")
	var name_label := hud.get_node_or_null("PlayerNameLabel") as Label if hud != null else null
	if name_label == null:
		return _fail("hud: PlayerNameLabel missing")
	if String(_profile.player_name) != "":
		return _fail("hud: fresh name '%s'" % _profile.player_name)
	await process_frame
	if name_label.visible:
		return _fail("hud: unnamed run shows a name")
	_profile.call("set_name", "Dad")
	await process_frame
	if not name_label.visible or name_label.text != "Dad":
		return _fail("hud: expected Dad, visible=%s text='%s'" % [name_label.visible, name_label.text])
	if name_label.get_theme_font_size("font_size") < 24:
		return _fail("hud: font %d < 24" % name_label.get_theme_font_size("font_size"))
	var theme := root.get_node_or_null("Theme")
	if theme == null or not theme.has_method("color"):
		return _fail("hud: Theme missing")
	var primary: Color = theme.color("text_primary")
	if name_label.get_theme_color("font_color") != primary:
		return _fail("hud: name colour %s is not text_primary %s" % [name_label.get_theme_color("font_color"), primary])
	if not _assert_overlap(hud, "named-idle", _HUD_SEAM):
		return false
	_profile.call("set_name", "Mom")
	await process_frame
	if name_label.text != "Mom" or not name_label.visible:
		return _fail("hud: name_changed left '%s'" % name_label.text)
	_profile.call("set_name", "Dad")
	await process_frame
	_game.streak_changed.emit(3)
	await process_frame
	var streak := hud.get_node_or_null("StreakLabel") as CanvasItem
	if streak == null or not streak.visible:
		return _fail("hud: streak label did not show")
	if not _assert_overlap(hud, "streak", _HUD_SEAM):
		return false
	_game.streak_changed.emit(0)
	await process_frame
	_game.board_shifted.emit(1, 2, 400)
	await process_frame
	var board := hud.get_node_or_null("BoardLabel") as CanvasItem
	if board == null or not board.visible:
		return _fail("hud: board label did not show")
	if not _assert_overlap(hud, "board", _HUD_SEAM):
		return false
	_game.board_shifted.emit(0, 0, 0)
	await process_frame
	_profile.call("set_name", LONG_NAME)
	await process_frame
	if name_label.text != LONG_NAME:
		return _fail("hud: 16-char text '%s'" % name_label.text)
	if not _assert_one_line(name_label, "hud sixteen-char"):
		return false
	if not _assert_overlap(hud, "sixteen-char", _HUD_SEAM):
		return false
	_profile.call("set_name", "")
	await process_frame
	if name_label.visible or String(_profile.player_name) != "":
		return _fail("hud: clearing the name left '%s' visible=%s" % [name_label.text, name_label.visible])
	_cases_passed += 1
	print("ACTIVE_PLAYER case hud pass")
	return true


func _case_unnamed_invite() -> bool:
	print("ACTIVE_PLAYER case unnamed invite")
	if String(_profile.player_name) != "":
		_profile.call("set_name", "")
	_leaderboard.identity_unconfirmed = false
	if not await _drain_to_over(420):
		return false
	var panel := _panel()
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	var saved := panel.get_node_or_null("SavedAsLabel") as Label
	var not_you := panel.get_node_or_null("NotYouButton") as Button
	if edit == null or not edit.visible:
		return _fail("unnamed: invite did not open")
	if saved != null and saved.visible:
		return _fail("unnamed: saved-as visible '%s'" % saved.text)
	if not_you != null and not_you.visible:
		return _fail("unnamed: Not you? visible")
	if not await _wait_board():
		return _fail("unnamed: board did not arrive")
	if not _assert_overlap(panel, "unnamed-invite", _HEADER_SEAM):
		return false
	var skip := panel.get_node_or_null("SkipButton") as Button
	if skip == null or not skip.visible:
		return _fail("unnamed: Not now missing")
	skip.pressed.emit()
	await process_frame
	_cases_passed += 1
	print("ACTIVE_PLAYER case unnamed invite pass")
	return true


func _case_unconfirmed_invite() -> bool:
	print("ACTIVE_PLAYER case unconfirmed invite")
	_profile.call("set_name", "Dad")
	_leaderboard.identity_unconfirmed = true
	if not await _drain_to_over(430):
		return false
	var panel := _panel()
	var edit := panel.get_node_or_null("NameEdit") as LineEdit
	var saved := panel.get_node_or_null("SavedAsLabel") as Label
	if edit == null or not edit.visible or edit.text != "Dad":
		return _fail("unconfirmed: invite text '%s'" % (edit.text if edit != null else "missing"))
	if saved != null and saved.visible:
		return _fail("unconfirmed: saved-as visible '%s'" % saved.text)
	if not await _wait_board():
		return _fail("unconfirmed: board did not arrive")
	if not _assert_overlap(panel, "unconfirmed-invite", _HEADER_SEAM):
		return false
	_leaderboard.identity_unconfirmed = false
	_cases_passed += 1
	print("ACTIVE_PLAYER case unconfirmed invite pass")
	return true


func _case_saved_binding() -> bool:
	print("ACTIVE_PLAYER case saved binding")
	_leaderboard.identity_unconfirmed = false
	if String(_profile.player_name) != "Dad":
		_profile.call("set_name", "Dad")
	_got_submit = false
	_last_submit = {}
	_capture_attempt = true
	_captured_id = ""
	_captured_name = ""
	if not await _drain_to_over(880):
		return false
	var panel := _panel()
	var saved := panel.get_node_or_null("SavedAsLabel") as Label
	var not_you := panel.get_node_or_null("NotYouButton") as Button
	if saved == null or not_you == null:
		return _fail("saved: controls missing")
	if saved.text != "SAVING AS DAD…":
		return _fail("saving line '%s'" % saved.text)
	# The POST body is already built. Changing player before the 201 must not
	# change who this score says it is saving as.
	_profile.call("set_name", "Mom")
	if saved.text != "SAVING AS DAD…":
		return _fail("saving line followed the rename: '%s'" % saved.text)
	if String(_profile.player_name) != "Mom":
		return _fail("rename during flight left '%s'" % _profile.player_name)
	if not_you.visible:
		return _fail("saving: Not you? showed before the save landed")
	if not _assert_overlap(panel, "saving", _HEADER_SEAM):
		return false
	if not await _wait_saved(saved):
		return _fail("saved line '%s' submit=%s ids=%s" % [saved.text, _last_submit, _leaderboard.score_post_ids])
	var rank := int(_last_submit.get("rank", 0))
	var total := int(_last_submit.get("total_players", 0))
	var expected := "SAVED AS DAD · %s OF %d" % [_ordinal(rank), total]
	if saved.text != expected:
		var edit := panel.get_node_or_null("NameEdit") as CanvasItem
		return _fail("saved line '%s' expected '%s' edit=%s not_you=%s submit=%s ids=%s" % [saved.text, expected, edit.visible if edit != null else "nil", not_you.visible, _last_submit, _leaderboard.score_post_ids])
	if saved.text.contains("MOM"):
		return _fail("saved line followed the current player")
	var rank_label := panel.get_node_or_null("YourRankLabel") as Label
	var rank_expected := "Rank %d of %d" % [rank, total]
	if bool(_last_submit.get("is_personal_best", false)):
		rank_expected += " · Personal best!"
	if rank_label == null or rank_label.text != rank_expected:
		return _fail("rank label '%s' expected '%s'" % [rank_label.text if rank_label != null else "", rank_expected])
	var ids: Array = _leaderboard.score_post_ids
	if ids.is_empty() or String(ids[ids.size() - 1]) != _captured_id:
		return _fail("POST id %s captured %s" % [ids, _captured_id])
	if String(_profile.player_id) == _captured_id:
		return _fail("current id still the posted id; name=%s players=%s captured=%s" % [_profile.player_name, _profile.players, _captured_id])
	if not not_you.visible:
		return _fail("saved: Not you? hidden")
	if not_you.size.y < MIN_TOUCH:
		return _fail("Not you? height %.1f < 64" % not_you.size.y)
	if not _assert_one_line(saved, "saved Dad"):
		return false
	if not _assert_overlap(panel, "saved", _HEADER_SEAM):
		return false
	var before := await _score_rows()
	if before.is_empty() and int(before.get("total", -1)) < 1:
		return _fail("no score row after 201: %s" % before)
	if not _rows_have(before, _captured_id, "Dad", 880):
		return _fail("row is not Dad 880: %s" % before)
	_push_action("change_name")
	if not await _wait_rename_open():
		return false
	var after := await _score_rows()
	if _row_key(after) != _row_key(before):
		return _fail("keyboard Not you? changed rows\nbefore %s\nafter %s" % [_row_key(before), _row_key(after)])
	if not _rows_have(after, _captured_id, "Dad", 880):
		return _fail("Dad's row moved after Not you?: %s" % after)
	_cases_passed += 1
	print("ACTIVE_PLAYER case saved binding pass")
	return true


func _case_sixteen_and_emit() -> bool:
	print("ACTIVE_PLAYER case sixteen-char")
	if not await _close_rename():
		return false
	_profile.call("set_name", LONG_NAME)
	await process_frame
	_got_submit = false
	_last_submit = {}
	_capture_attempt = false
	if not await _drain_to_over(640):
		return false
	var panel := _panel()
	var saved := panel.get_node_or_null("SavedAsLabel") as Label
	var not_you := panel.get_node_or_null("NotYouButton") as Button
	if saved == null or not_you == null:
		return _fail("sixteen: controls missing")
	if not await _wait_saved(saved):
		return _fail("sixteen: saved line '%s' submit=%s" % [saved.text, _last_submit])
	if not saved.visible or not saved.text.begins_with("SAVED AS %s · " % LONG_NAME):
		return _fail("sixteen saved line '%s'" % saved.text)
	if not _assert_one_line(saved, "game over sixteen-char"):
		return false
	if not not_you.visible or not_you.size.y < MIN_TOUCH:
		return _fail("sixteen: Not you? %s" % (not_you.size if not_you != null else Vector2.ZERO))
	if not _assert_overlap(panel, "sixteen-char-saved", _HEADER_SEAM):
		return false
	var before := await _score_rows()
	var posted_id := String(_profile.player_id)
	not_you.pressed.emit()
	if not await _wait_rename_open():
		return false
	var after := await _score_rows()
	if _row_key(after) != _row_key(before):
		return _fail("pressed Not you? changed rows\nbefore %s\nafter %s" % [_row_key(before), _row_key(after)])
	if not _rows_have(after, posted_id, LONG_NAME, 640):
		return _fail("16-char row moved: %s" % after)
	_cases_passed += 1
	print("ACTIVE_PLAYER case sixteen-char pass")
	return true


func _case_offline() -> bool:
	print("ACTIVE_PLAYER case offline")
	if not await _close_rename():
		return false
	if String(_profile.player_name).is_empty():
		_profile.call("set_name", "Dad")
	var before := await _score_rows()
	OS.set_environment("SQUISH_LEADERBOARD_URL", SENTINEL)
	_offline_reason = ""
	_got_submit = false
	if not await _drain_to_over(510):
		return false
	var panel := _panel()
	var saved := panel.get_node_or_null("SavedAsLabel") as Label
	var offline := panel.get_node_or_null("OfflineLabel") as Label
	var not_you := panel.get_node_or_null("NotYouButton") as Button
	if not await _wait_offline_visible(offline):
		return _fail("offline label did not show")
	var expected := String(_leaderboard.offline_line(_offline_reason))
	if offline.text != expected:
		return _fail("offline '%s' expected '%s' (%s)" % [offline.text, expected, _offline_reason])
	if saved != null and saved.visible:
		return _fail("offline: saved-as still visible '%s'" % saved.text)
	if not_you != null and not_you.visible:
		return _fail("offline: Not you? visible")
	if not _assert_overlap(panel, "offline-failure", _HEADER_SEAM):
		return false
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	var after := await _score_rows()
	if _row_key(after) != _row_key(before):
		return _fail("failed save wrote a row\nbefore %s\nafter %s" % [_row_key(before), _row_key(after)])
	_cases_passed += 1
	print("ACTIVE_PLAYER case offline pass")
	return true


func _assert_one_line(label: Label, where: String) -> bool:
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return _fail("%s: wrapping is on" % where)
	if label.get_line_count() != 1:
		return _fail("%s: %d lines '%s'" % [where, label.get_line_count(), label.text])
	if label.text.contains("\n"):
		return _fail("%s: text contains a newline" % where)
	var font := label.get_theme_font("font")
	if font == null:
		return _fail("%s: no font" % where)
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	if width > label.get_global_rect().size.x + 1.0:
		return _fail("%s: text width %.1f exceeds %.1f ('%s')" % [where, width, label.get_global_rect().size.x, label.text])
	return true


func _assert_overlap(panel: Node, state_name: String, seam: Dictionary) -> bool:
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
	var overlap := 0
	for i in kids.size():
		var rect: Rect2 = (kids[i] as Control).get_global_rect()
		for j in range(i + 1, kids.size()):
			var other: Rect2 = (kids[j] as Control).get_global_rect()
			var shared := rect.intersection(other)
			if shared.get_area() <= 0.5:
				continue
			var left_name := String(kids[i].name)
			var right_name := String(kids[j].name)
			if seam.has(left_name) and seam.has(right_name):
				continue
			overlap += 1
			return _fail("%s: %s %s overlaps %s %s" % [state_name, left_name, rect, right_name, other])
	print("ACTIVE_PLAYER state %s overlap_count=%d" % [state_name, overlap])
	return true


func _drain_to_over(points: int) -> bool:
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
	_game.add_score(points)
	for _i in 2:
		_game.on_ball_drained()
		await process_frame
	_game.on_ball_drained()
	var panel := _panel()
	if panel == null or not panel.visible or _game.state != _game.GAME_OVER:
		return _fail("expected GAME_OVER")
	return true


func _wait_saved(saved: Label) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 4000:
		if saved.text.begins_with("SAVED AS "):
			await process_frame
			return true
		await process_frame
	return false


func _wait_board() -> bool:
	var start := Time.get_ticks_msec()
	var offline := _panel().get_node_or_null("OfflineLabel") as CanvasItem
	while Time.get_ticks_msec() - start < 3000:
		if offline == null or not offline.visible:
			return true
		await process_frame
	return offline == null or not offline.visible


func _wait_offline_visible(offline: Label) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000:
		if offline != null and offline.visible and not _offline_reason.is_empty():
			await process_frame
			return true
		await process_frame
	return offline != null and offline.visible


func _wait_rename_open() -> bool:
	var title := _main.get_node_or_null("Title")
	if title == null:
		return _fail("title missing")
	var entry := title.get_node_or_null("NameEntry") as Control
	var edit := entry.get_node_or_null("NameEdit") as LineEdit if entry != null else null
	if edit == null:
		return _fail("name entry missing")
	for _i in 20:
		if title.visible and entry.visible and edit.visible and edit.has_focus():
			return true
		await process_frame
	if not title.visible or not entry.visible or not edit.has_focus():
		return _fail("rename not open title=%s entry=%s focus=%s" % [title.visible, entry.visible, edit.has_focus()])
	return true


func _close_rename() -> bool:
	var title := _main.get_node_or_null("Title")
	if title == null or not title.visible:
		return true
	var entry := title.get_node_or_null("NameEntry") as CanvasItem
	if entry == null or not entry.visible:
		return true
	_push_key(KEY_ESCAPE)
	for _i in 10:
		await process_frame
		if not entry.visible:
			return true
	if entry.visible:
		return _fail("escape left the rename open")
	return true


func _panel() -> Node:
	return _main.get_node_or_null("GameOver")


func _push_action(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_main.get_viewport().push_input(ev)


func _push_key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.pressed = true
	down.keycode = keycode
	down.physical_keycode = keycode
	_main.get_viewport().push_input(down)


func _ordinal(n: int) -> String:
	var teen := n % 100
	if teen >= 11 and teen <= 13:
		return "%dTH" % n
	match n % 10:
		1:
			return "%dST" % n
		2:
			return "%dND" % n
		3:
			return "%dRD" % n
		_:
			return "%dTH" % n


func _rows_have(page: Dictionary, player_id: String, player_name: String, score: int) -> bool:
	var rows: Variant = page.get("rows", [])
	if typeof(rows) != TYPE_ARRAY:
		return false
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if String(row.get("player_id", "")).to_lower() == player_id.to_lower() and String(row.get("name", "")) == player_name and int(row.get("score", -1)) == score:
			return true
	return false


func _row_key(page: Dictionary) -> String:
	var rows: Variant = page.get("rows", [])
	if typeof(rows) != TYPE_ARRAY:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		parts.append("%s|%s|%s|%s" % [row.get("id", ""), row.get("player_id", ""), row.get("name", ""), row.get("score", "")])
	parts.sort()
	return "\n".join(parts)


func _score_rows() -> Dictionary:
	var got := await _http_json(HTTPClient.METHOD_GET, "/v1/admin/scores?limit=50", "", true)
	var parsed: Variant = JSON.parse_string(String(got.get("text", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"total": -1, "rows": [], "code": int(got.get("code", 0)), "text": got.get("text", "")}
	var data: Dictionary = parsed
	data["code"] = int(got.get("code", 0))
	return data


func _http_json(method: int, path: String, body: String, admin: bool) -> Dictionary:
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


func _reset_profile() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("profile.save"):
		dir.remove("profile.save")
	if _profile.has_method("_load_or_create"):
		_profile.call("_load_or_create")


func _silence_table_drain() -> void:
	var table := _main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _start_server() -> bool:
	var made: Array = []
	var mk := OS.execute("/usr/bin/mktemp", PackedStringArray(["-d"]), made, true, false)
	if mk != 0 or made.is_empty():
		return _fail("mktemp failed")
	_temp_dir = String(made[0]).strip_edges()
	_log_path = _temp_dir.path_join("lb.log")
	_free_port()
	var root_path := ProjectSettings.globalize_path("res://")
	var cmd := "cd '%s/server' && exec env DB_PATH=:memory: SQUISH_KEY=devkey SQUISH_ADMIN_KEY=dev-admin PORT=%d node --no-warnings=ExperimentalWarning src/index.js > '%s' 2>&1" % [root_path, PORT, _log_path]
	_server_pid = OS.create_process("/bin/bash", ["-lc", cmd])
	if _server_pid <= 0:
		return _fail("server did not spawn")
	for _i in 25:
		var output: Array = []
		var code := OS.execute("/usr/bin/curl", ["-sf", "--max-time", "1", "http://127.0.0.1:%d/healthz" % PORT], output, true, false)
		if code == 0:
			return true
		OS.delay_msec(200)
	if FileAccess.file_exists(_log_path):
		print(FileAccess.get_file_as_string(_log_path))
	return _fail("server did not become healthy")


func _free_port() -> void:
	OS.execute("/bin/bash", ["-lc", "pids=$(lsof -ti tcp:%d 2>/dev/null || true); if [ -n \"$pids\" ]; then kill $pids 2>/dev/null || true; sleep 0.2; kill -9 $pids 2>/dev/null || true; fi" % PORT])


func _cleanup() -> void:
	if _server_pid > 0:
		OS.execute("/bin/kill", ["-TERM", str(_server_pid)])
		OS.execute("/bin/kill", ["-KILL", str(_server_pid)])
		_server_pid = -1
	_free_port()
	if _temp_dir != "":
		OS.execute("/bin/rm", ["-rf", _temp_dir])
		_temp_dir = ""


func _fail(message: String) -> bool:
	push_error("ACTIVE_PLAYER FAIL %s" % message)
	print("ACTIVE_PLAYER FAIL %s" % message)
	_cleanup()
	quit(1)
	return false
