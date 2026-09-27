extends SceneTree

## T39. First-run title: no two visible controls share area, Play stays off the
## HUD score row, and every interactive control is at least 64 px and on screen.
## An existing name asks before it adopts. Backing out keeps the local id.
## Accepting adopts once and posts at most one score. A new name still commits
## on the return key alone.

const PORT := 18793
const VIEWPORT := Rect2(0, 0, 720, 1280)
const KEYBOARD_TOP := 640.0
const MIN_TOUCH := 64.0

var _cases_passed: int = 0
var _profile: Node
var _leaderboard: Node
var _server_pid: int = -1
var _log_path: String = ""
var _ok_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("TITLE_COMPOSE start")
	DisplayServer.window_set_size(Vector2i(720, 1280))
	_profile = root.get_node_or_null("Profile")
	_leaderboard = root.get_node_or_null("Leaderboard")
	if _profile == null or _leaderboard == null:
		_fail("Profile or Leaderboard missing")
		return
	if not _leaderboard.name_resolved.is_connected(_on_name_resolved):
		_leaderboard.name_resolved.connect(_on_name_resolved)
	_log_path = ProjectSettings.globalize_path("user://t39-server.log")
	_reset_profile()
	if String(_profile.player_name) != "":
		_fail("fresh profile name should be empty")
		return

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null or change_scene_to_packed(packed) != OK:
		_fail("could not load main.tscn")
		return
	for _i in 4:
		await process_frame
	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)

	if not await _case_first_run(main):
		return
	if not await _case_named_layout(main):
		return
	if not await _case_welcome_back(main):
		return
	if not await _case_new_name_one_tap(main):
		return

	_cleanup()
	print("TITLE_COMPOSE PASS cases=%d" % _cases_passed)
	quit(0)


func _on_name_resolved(_generation: int, ok: bool, _info: Dictionary) -> void:
	if ok:
		_ok_count += 1


func _case_first_run(main: Node) -> bool:
	print("TITLE_COMPOSE case 1 first run, no name")
	var title := main.get_node_or_null("Title")
	if title == null or not title.visible:
		return _fail("case 1: Title missing or hidden")
	if String(_profile.player_name) != "":
		return _fail("case 1: name is set")
	var entry := title.get_node_or_null("NameEntry") as Control
	var name_button := title.get_node_or_null("NameButton") as Control
	if entry == null or not entry.visible:
		return _fail("case 1: NameEntry should be visible with no name")
	if name_button != null and name_button.visible:
		return _fail("case 1: NameButton should be hidden with no name")
	if not _assert_layout(main, title, "case 1"):
		return false
	_cases_passed += 1
	print("TITLE_COMPOSE case 1 pass")
	return true


func _case_named_layout(main: Node) -> bool:
	print("TITLE_COMPOSE case 2 named layout")
	_profile.call("set_name", "Ada")
	await process_frame
	await process_frame
	var title := main.get_node_or_null("Title")
	if title == null:
		return _fail("case 2: Title missing")
	if String(_profile.player_name) != "Ada":
		return _fail("case 2: name was not set")
	var entry := title.get_node_or_null("NameEntry") as Control
	if entry != null and entry.visible:
		return _fail("case 2: NameEntry should hide once a name exists")
	if not _assert_layout(main, title, "case 2"):
		return false
	_reset_profile()
	if title.has_method("show_menu"):
		title.show_menu()
	await process_frame
	await process_frame
	if String(_profile.player_name) != "":
		return _fail("case 2: profile did not reset")
	_cases_passed += 1
	print("TITLE_COMPOSE case 2 pass")
	return true


func _case_welcome_back(main: Node) -> bool:
	print("TITLE_COMPOSE case 3 welcome back")
	if not _start_server():
		return false
	OS.set_environment("SQUISH_LEADERBOARD_URL", "http://127.0.0.1:%d" % PORT)
	OS.set_environment("SQUISH_LEADERBOARD_KEY", "devkey")
	var created: Dictionary = await _raw_resolve("Natasha")
	if int(created.get("code", 0)) != 201 and int(created.get("code", 0)) != 200:
		return _fail("case 3: could not create Natasha (%s)" % created)
	var natasha_id := String(created.get("player_id", ""))
	if natasha_id.is_empty():
		return _fail("case 3: Natasha id missing")
	_reset_profile()
	var before_id := String(_profile.player_id)
	if before_id == natasha_id:
		return _fail("case 3: fresh id collided with Natasha")
	var title := main.get_node_or_null("Title")
	if title == null or not title.has_method("show_menu"):
		return _fail("case 3: Title missing")
	title.show_menu()
	await process_frame
	await process_frame
	var edit := title.get_node_or_null("NameEntry/NameEdit") as LineEdit
	var welcome := title.get_node_or_null("NameEntry/WelcomeLabel") as Label
	var yes := title.get_node_or_null("NameEntry/YesButton") as Button
	var no := title.get_node_or_null("NameEntry/NoButton") as Button
	if edit == null or welcome == null or yes == null or no == null:
		return _fail("case 3: welcome controls missing")
	_ok_count = 0
	edit.text = "natasha"
	edit.text_submitted.emit("natasha")
	if not await _wait_welcome(welcome):
		return _fail("case 3: existing name did not ask welcome back")
	if _ok_count != 0:
		return _fail("case 3: resolve succeeded before accept")
	if String(_profile.player_id) != before_id or String(_profile.player_name) != "":
		return _fail("case 3: peek adopted %s/%s" % [_profile.player_id, _profile.player_name])
	if welcome.text.find("Welcome back") < 0 or welcome.text.find("Natasha") < 0:
		return _fail("case 3: welcome copy '%s'" % welcome.text)
	no.pressed.emit()
	await process_frame
	await process_frame
	if welcome.visible:
		return _fail("case 3: Not me left the welcome up")
	if String(_profile.player_id) != before_id or String(_profile.player_name) != "":
		return _fail("case 3: Not me changed identity")
	if edit.text != "natasha":
		return _fail("case 3: Not me dropped the typed name")
	var submits_before := _submit_total()
	_ok_count = 0
	edit.text_submitted.emit("natasha")
	if not await _wait_welcome(welcome):
		return _fail("case 3: second try did not ask again")
	if String(_profile.player_id) != before_id:
		return _fail("case 3: second peek adopted")
	yes.pressed.emit()
	if not await _wait_ok(1):
		return _fail("case 3: accept did not adopt (ok=%d id=%s)" % [_ok_count, _profile.player_id])
	if _ok_count != 1:
		return _fail("case 3: adopted %d times" % _ok_count)
	if String(_profile.player_id) != natasha_id:
		return _fail("case 3: id %s want %s" % [_profile.player_id, natasha_id])
	if String(_profile.player_name) != "Natasha":
		return _fail("case 3: display '%s'" % _profile.player_name)
	for _i in 10:
		await process_frame
	if _ok_count != 1:
		return _fail("case 3: a later resolve adopted again (%d)" % _ok_count)
	var posted := _submit_total() - submits_before
	if posted > 1:
		return _fail("case 3: accept posted %d scores" % posted)
	_cases_passed += 1
	print("TITLE_COMPOSE case 3 pass id=%s scores=%d" % [natasha_id, posted])
	return true


func _case_new_name_one_tap(main: Node) -> bool:
	print("TITLE_COMPOSE case 4 new name, return key, no welcome")
	_reset_profile()
	var title := main.get_node_or_null("Title")
	if title == null or not title.has_method("show_menu"):
		return _fail("case 4: Title missing")
	title.show_menu()
	await process_frame
	await process_frame
	var edit := title.get_node_or_null("NameEntry/NameEdit") as LineEdit
	var welcome := title.get_node_or_null("NameEntry/WelcomeLabel") as Label
	if edit == null or welcome == null:
		return _fail("case 4: name prompt missing")
	_ok_count = 0
	edit.text = "Pip"
	edit.text_submitted.emit("Pip")
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000 and _ok_count < 1 and not welcome.visible:
		await process_frame
	if welcome.visible:
		return _fail("case 4: a new name asked welcome back")
	if _ok_count != 1 or String(_profile.player_name) != "Pip":
		return _fail("case 4: return key did not commit (ok=%d name=%s)" % [_ok_count, _profile.player_name])
	_cases_passed += 1
	print("TITLE_COMPOSE case 4 pass")
	return true


func _assert_layout(main: Node, title: Node, label: String) -> bool:
	var kids := _visible_title_controls(title)
	var overlap := 0
	for i in kids.size():
		var rect: Rect2 = kids[i].get_global_rect()
		print("TITLE_COMPOSE layout %s %s %s" % [label, kids[i].name, rect])
		for j in range(i + 1, kids.size()):
			var shared: Rect2 = rect.intersection(kids[j].get_global_rect())
			if shared.get_area() > 0.5:
				overlap += 1
				_fail(
					"%s: %s %s overlaps %s %s"
					% [label, kids[i].name, rect, kids[j].name, kids[j].get_global_rect()]
				)
				return false
	print("TITLE_COMPOSE layout %s overlap_count=%d visible=%d" % [label, overlap, kids.size()])
	var hud := _hud_score_row(main)
	print("TITLE_COMPOSE layout %s hud_score %s" % [label, hud])
	for node in kids:
		var shared_hud: Rect2 = (node as Control).get_global_rect().intersection(hud)
		if shared_hud.get_area() > 0.5:
			return _fail("%s: %s intersects the HUD score row %s" % [label, node.name, hud])
	if not _assert_interactive(title, label):
		return false
	return true


func _visible_title_controls(title: Node) -> Array:
	var kids: Array = []
	for child in title.get_children():
		if not (child is Control):
			continue
		var node := child as Control
		if node.name == "Shade":
			continue
		if not node.visible or not node.is_visible_in_tree():
			continue
		kids.append(node)
	return kids


func _hud_score_row(main: Node) -> Rect2:
	var hud := main.get_node_or_null("HUD")
	var merged := Rect2()
	var any := false
	if hud == null:
		return merged
	for node_name in ["ScoreLabel", "BallsLabel", "HighScoreLabel"]:
		var label := hud.get_node_or_null(node_name) as Control
		if label == null or not label.visible:
			continue
		var rect := label.get_global_rect()
		merged = rect if not any else merged.merge(rect)
		any = true
	return merged


func _assert_interactive(title: Node, label: String) -> bool:
	return _walk_interactive(title, label)


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


func _wait_welcome(welcome: Label) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if welcome.visible:
			return true
		await process_frame
	return welcome.visible


func _wait_ok(want: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if _ok_count >= want:
			return true
		await process_frame
	return _ok_count >= want


func _submit_total() -> int:
	var counts: Dictionary = _leaderboard.submit_attempts
	var total := 0
	for value in counts.values():
		total += int(value)
	return total


func _raw_resolve(player_name: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 3.0
	root.add_child(http)
	var done := {"got": false, "code": 0, "player_id": ""}
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		done.got = true
		done.code = code
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			done.player_id = String(parsed.get("player_id", ""))
	)
	var err := http.request(
		"http://127.0.0.1:%d/v1/players/resolve" % PORT,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"name": player_name})
	)
	if err != OK:
		http.queue_free()
		return {"code": -1, "player_id": ""}
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000 and not bool(done.got):
		await process_frame
	var out := {"code": int(done.code), "player_id": String(done.player_id)}
	http.queue_free()
	return out


func _reset_profile() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("profile.save"):
		dir.remove("profile.save")
	if _profile != null and _profile.has_method("_load_or_create"):
		_profile.call("_load_or_create")


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _start_server() -> bool:
	_kill_server()
	var root_path := ProjectSettings.globalize_path("res://")
	var cmd := "cd '%s/server' && exec env DB_PATH=:memory: SQUISH_KEY=devkey PORT=%d node --no-warnings=ExperimentalWarning src/index.js > '%s' 2>&1" % [root_path, PORT, _log_path]
	_server_pid = OS.create_process("/bin/bash", ["-lc", cmd])
	if _server_pid <= 0:
		return _fail("case 3: server did not spawn")
	for _i in 25:
		var output: Array = []
		var code := OS.execute("/usr/bin/curl", ["-sf", "--max-time", "1", "http://127.0.0.1:%d/healthz" % PORT], output, true, false)
		if code == 0:
			return true
		OS.delay_msec(200)
	if FileAccess.file_exists(_log_path):
		print(FileAccess.get_file_as_string(_log_path))
	return _fail("case 3: server did not become healthy")


func _kill_server() -> void:
	if _server_pid > 0:
		OS.execute("/bin/kill", ["-TERM", str(_server_pid)])
		OS.execute("/bin/kill", ["-KILL", str(_server_pid)])
		_server_pid = -1
	OS.execute("/bin/bash", ["-lc", "pids=$(lsof -ti tcp:%d 2>/dev/null || true); if [ -n \"$pids\" ]; then kill $pids 2>/dev/null || true; fi" % PORT])


func _cleanup() -> void:
	_kill_server()
	if _log_path != "" and FileAccess.file_exists(_log_path):
		DirAccess.remove_absolute(_log_path)


func _fail(message: String) -> bool:
	push_error("TITLE_COMPOSE FAIL %s" % message)
	print("TITLE_COMPOSE FAIL %s" % message)
	_cleanup()
	quit(1)
	return false
