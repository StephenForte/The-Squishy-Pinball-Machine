extends SceneTree

const SAVE_PATH := "user://profile.save"
const PROFILE_SCRIPT := preload("res://autoload/profile.gd")

var _cases_passed: int = 0
var _name_changed_count: int = 0
var _profile: Node
var _game: Node
var _theme: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_delete_profile()
	_profile = root.get_node_or_null("Profile")
	_game = root.get_node_or_null("Game")
	_theme = root.get_node_or_null("Theme")
	if _profile == null or _game == null or _theme == null:
		_fail("Profile, Game, or Theme autoload missing")
		return
	_profile._load_or_create()
	_profile.name_changed.connect(_on_name_changed)

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

	if not await _case_1_fresh(main):
		return
	if not await _case_3_focus_gates(main):
		return
	if not await _case_2_confirm(main):
		return
	if not await _case_4_rename_cancel(main):
		return
	if not await _case_5_reinstantiate():
		return
	if not await _case_6_launch(main):
		return
	if not await _case_7_per_name_identity():
		return
	if not await _case_8_name_case():
		return
	if not await _case_9_migrate_planner_save():
		return

	print("PROFILE PASS cases=%d" % _cases_passed)
	quit(0)


func _on_name_changed(_name: String) -> void:
	_name_changed_count += 1


func _case_1_fresh(main: Node) -> bool:
	if not _is_uuid_v4(String(_profile.player_id)):
		return _fail("case 1: player_id is not a v4 UUID: %s" % _profile.player_id)
	if String(_profile.player_name) != "":
		return _fail("case 1: expected empty name, got '%s'" % _profile.player_name)
	var title := _require_node(main, "Title")
	var entry := _require_node(main, "NameEntry")
	if title == null or entry == null:
		return false
	if not title.visible:
		return _fail("case 1: Title should be visible")
	if not entry.visible:
		return _fail("case 1: NameEntry should be visible on a fresh profile")
	await _wait_entry_focused(entry)
	if not entry.is_capturing():
		return _fail("case 1: NameEntry LineEdit should have focus")
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	_push_action(main, "launch_ball")
	var launched := false
	for _f in 5:
		await physics_frame
		if bool(ball.get("launched")):
			launched = true
			break
	_push_action(main, "launch_ball", false)
	if launched:
		return _fail("case 1: launch_ball launched before a name was set")
	if not title.visible:
		return _fail("case 1: Title hid before a name was set")
	_cases_passed += 1
	print("PROFILE case 1 pass")
	return true


func _case_3_focus_gates(main: Node) -> bool:
	var entry := _require_node(main, "NameEntry")
	var flipper := main.get_node_or_null("Table/FlipperLeft")
	if entry == null:
		return false
	if flipper == null:
		return _fail("case 3: missing Table/FlipperLeft")
	await _wait_entry_focused(entry)
	if not entry.is_capturing():
		return _fail("case 3: NameEntry should be focused")

	var angle_before: float = flipper.rotation
	Input.action_press("flipper_left")
	for _i in 10:
		await physics_frame
	Input.action_release("flipper_left")
	if absf(flipper.rotation - angle_before) >= 0.01:
		return _fail("case 3: flipper moved while NameEntry focused")

	_game.add_score(100)
	var state_before: int = _game.state
	var score_before: int = _game.score
	var balls_before: int = _game.balls_left
	_push_action(main, "restart")
	await process_frame
	await process_frame
	if _game.state != state_before or _game.score != score_before or _game.balls_left != balls_before:
		return _fail("case 3: restart changed game state while NameEntry focused")

	var palette_before: String = String(_theme.palette_id)
	var arrow := InputEventKey.new()
	arrow.pressed = true
	arrow.physical_keycode = KEY_RIGHT
	arrow.keycode = KEY_RIGHT
	main.get_viewport().push_input(arrow)
	await process_frame
	await process_frame
	arrow.pressed = false
	main.get_viewport().push_input(arrow)
	if String(_theme.palette_id) != palette_before:
		return _fail("case 3: Right arrow changed palette while NameEntry focused")

	var edit := entry.get_node_or_null("NameEdit") as LineEdit
	if edit == null:
		return _fail("case 3: missing NameEdit")
	edit.text = ""
	edit.caret_column = 0
	edit.grab_focus()
	await process_frame
	_type_char(main, KEY_A, 97)
	_type_char(main, KEY_SPACE, 32)
	_type_char(main, KEY_R, 114)
	_type_char(main, KEY_D, 100)
	await process_frame
	if edit.text != "a rd":
		return _fail("case 3: LineEdit should accept A/Space/R/D, got '%s'" % edit.text)
	edit.text = ""

	_cases_passed += 1
	print("PROFILE case 3 pass")
	return true


func _case_2_confirm(main: Node) -> bool:
	var entry := _require_node(main, "NameEntry")
	var title := _require_node(main, "Title")
	if entry == null or title == null:
		return false
	var edit := entry.get_node_or_null("NameEdit") as LineEdit
	if edit == null:
		return _fail("case 2: missing NameEdit")
	_name_changed_count = 0
	edit.text = "  Nat  asha "
	edit.text_submitted.emit(edit.text)
	await process_frame
	await process_frame
	if String(_profile.player_name) != "Nat asha":
		return _fail("case 2: expected name 'Nat asha', got '%s'" % _profile.player_name)
	if _name_changed_count != 1:
		return _fail("case 2: name_changed fired %d times, expected 1" % _name_changed_count)
	if entry.visible:
		return _fail("case 2: NameEntry should be hidden after confirm")
	var name_line := _require_node(main, "PlayerNameLabel") as Label
	if name_line == null:
		return false
	if name_line.text != "Playing as Nat asha · N to change":
		return _fail("case 2: title name line was '%s'" % name_line.text)
	if not FileAccess.file_exists(SAVE_PATH):
		return _fail("case 2: profile.save was not written")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("case 2: profile.save is not JSON")
	var data: Dictionary = parsed
	if String(data.get("player_id", "")) != String(_profile.player_id):
		return _fail("case 2: profile.save player_id mismatch")
	if String(data.get("player_name", "")) != "Nat asha":
		return _fail("case 2: profile.save name was '%s'" % data.get("player_name", ""))
	if not title.visible:
		return _fail("case 2: Title should stay visible after naming")
	_cases_passed += 1
	print("PROFILE case 2 pass")
	return true


func _case_4_rename_cancel(main: Node) -> bool:
	var entry := _require_node(main, "NameEntry")
	if entry == null:
		return false
	_push_action(main, "change_name")
	await process_frame
	await process_frame
	if not entry.visible:
		return _fail("case 4: NameEntry should reopen on change_name")
	var edit := entry.get_node_or_null("NameEdit") as LineEdit
	if edit == null:
		return _fail("case 4: missing NameEdit")
	if edit.text != "Nat asha":
		return _fail("case 4: expected prefill 'Nat asha', got '%s'" % edit.text)
	await _wait_entry_focused(entry)
	edit.text = "Other"
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	main.get_viewport().push_input(esc)
	await process_frame
	await process_frame
	esc.pressed = false
	main.get_viewport().push_input(esc)
	if String(_profile.player_name) != "Nat asha":
		return _fail("case 4: Escape changed the name to '%s'" % _profile.player_name)
	if entry.visible:
		return _fail("case 4: NameEntry should hide on Escape")
	_cases_passed += 1
	print("PROFILE case 4 pass")
	return true


func _case_5_reinstantiate() -> bool:
	var clone: Node = PROFILE_SCRIPT.new()
	root.add_child(clone)
	await process_frame
	var clone_id := String(clone.get("player_id"))
	var clone_name := String(clone.get("player_name"))
	clone.queue_free()
	await process_frame
	if clone_id != String(_profile.player_id) or clone_name != String(_profile.player_name):
		return _fail(
			"case 5: re-instantiated Profile id/name %s/%s != %s/%s"
			% [clone_id, clone_name, _profile.player_id, _profile.player_name]
		)
	_cases_passed += 1
	print("PROFILE case 5 pass")
	return true


func _case_6_launch(main: Node) -> bool:
	var title := _require_node(main, "Title")
	if title == null:
		return false
	if String(_profile.player_name).is_empty():
		return _fail("case 6: name must be set before launch")
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	_push_action(main, "launch_ball")
	var launched := false
	for _f in 5:
		await physics_frame
		if bool(ball.get("launched")):
			launched = true
			break
	_push_action(main, "launch_ball", false)
	if title.visible:
		return _fail("case 6: Title should hide on first Space after a name is set")
	if not launched:
		return _fail("case 6: Space did not launch after a name is set")
	_cases_passed += 1
	print("PROFILE case 6 pass")
	return true


func _case_7_per_name_identity() -> bool:
	print("PROFILE case 7 per-name identity")
	_name_changed_count = 0
	_profile.call("set_name", "Dad")
	await process_frame
	var dad_id := String(_profile.player_id)
	if not _is_uuid_v4(dad_id):
		return _fail("case 7: Dad player_id is not a v4 UUID: %s" % dad_id)
	if String(_profile.player_name) != "Dad":
		return _fail("case 7: expected name Dad, got '%s'" % _profile.player_name)
	_profile.call("set_name", "Natasha")
	await process_frame
	var natasha_id := String(_profile.player_id)
	if not _is_uuid_v4(natasha_id):
		return _fail("case 7: Natasha player_id is not a v4 UUID")
	if natasha_id == dad_id:
		return _fail("case 7: new name must mint a new UUID")
	if String(_profile.player_name) != "Natasha":
		return _fail("case 7: expected name Natasha, got '%s'" % _profile.player_name)
	_profile.call("set_name", "Dad")
	await process_frame
	if String(_profile.player_id) != dad_id:
		return _fail("case 7: switching back to Dad should restore %s, got %s" % [dad_id, _profile.player_id])
	if String(_profile.player_name) != "Dad":
		return _fail("case 7: display name should be Dad, got '%s'" % _profile.player_name)
	var data := _read_profile_save()
	if data.is_empty():
		return _fail("case 7: profile.save missing or invalid")
	var saved_players: Variant = data.get("players", {})
	if typeof(saved_players) != TYPE_DICTIONARY:
		return _fail("case 7: players map missing")
	if String(saved_players.get("dad", "")) != dad_id:
		return _fail("case 7: players.dad should be %s" % dad_id)
	if String(saved_players.get("natasha", "")) != natasha_id:
		return _fail("case 7: players.natasha should be %s" % natasha_id)
	_cases_passed += 1
	print("PROFILE case 7 pass dad=%s natasha=%s" % [dad_id, natasha_id])
	return true


func _case_8_name_case() -> bool:
	print("PROFILE case 8 case-insensitive")
	_profile.call("set_name", "Natasha")
	await process_frame
	var natasha_id := String(_profile.player_id)
	_profile.call("set_name", "NATASHA")
	await process_frame
	if String(_profile.player_id) != natasha_id:
		return _fail("case 8: NATASHA should be the same player as Natasha")
	if String(_profile.player_name) != "Natasha":
		return _fail("case 8: display should stay Natasha, got '%s'" % _profile.player_name)
	_cases_passed += 1
	print("PROFILE case 8 pass")
	return true


func _case_9_migrate_planner_save() -> bool:
	print("PROFILE case 9 migrate planner save")
	const PLANNER_ID := "6c107d4d-64d7-49f3-9e09-8db3a4ba9e3b"
	_write_profile_text('{"player_id":"%s","player_name":"Natasha"}' % PLANNER_ID)
	_profile._load_or_create()
	await process_frame
	if String(_profile.player_id) != PLANNER_ID:
		return _fail("case 9: Natasha should keep %s, got %s" % [PLANNER_ID, _profile.player_id])
	if String(_profile.player_name) != "Natasha":
		return _fail("case 9: name should be Natasha, got '%s'" % _profile.player_name)
	var first := _read_profile_save()
	if String(first.get("player_id", "")) != PLANNER_ID:
		return _fail("case 9: migrated save player_id mismatch")
	if String((first.get("players", {}) as Dictionary).get("natasha", "")) != PLANNER_ID:
		return _fail("case 9: players.natasha missing after migrate: %s" % first)
	_profile._load_or_create()
	await process_frame
	var second := _read_profile_save()
	if String(second.get("player_id", "")) != PLANNER_ID:
		return _fail("case 9: second boot dropped player_id")
	if String((second.get("players", {}) as Dictionary).get("natasha", "")) != PLANNER_ID:
		return _fail("case 9: second boot dropped players.natasha")
	if String(_profile.player_id) != PLANNER_ID:
		return _fail("case 9: second boot changed in-memory id")
	_profile.call("set_name", "Dad")
	await process_frame
	var dad_id := String(_profile.player_id)
	if dad_id == PLANNER_ID or not _is_uuid_v4(dad_id):
		return _fail("case 9: Dad should mint a new UUID, got %s" % dad_id)
	_profile.call("set_name", "Natasha")
	await process_frame
	if String(_profile.player_id) != PLANNER_ID:
		return _fail("case 9: Natasha should still be %s after Dad" % PLANNER_ID)
	_cases_passed += 1
	print("PROFILE case 9 pass")
	return true


func _read_profile_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _write_profile_text(text: String) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)


func _wait_entry_focused(entry: Node) -> void:
	for _i in 10:
		if entry.has_method("is_capturing") and entry.is_capturing():
			return
		if entry.has_method("grab_name_focus"):
			entry.grab_name_focus()
		await process_frame


func _type_char(main: Node, keycode: Key, unicode: int) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = unicode
	main.get_viewport().push_input(ev)
	ev.pressed = false
	main.get_viewport().push_input(ev)


func _push_action(main: Node, action: StringName, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	main.get_viewport().push_input(ev)


func _wait_lane_ball(main: Node) -> Node:
	var table := main.get_node_or_null("Table")
	if table == null:
		_fail("missing Table node")
		return null
	var ball: Node = null
	for node in get_nodes_in_group("ball"):
		if node is Node2D and is_instance_valid(node):
			var pos: Vector2 = (node as Node2D).global_position
			if pos.x > 620.0 and pos.y > 1100.0:
				ball = node
				break
	if ball == null:
		_fail("no lane ball available")
		return null
	while is_instance_valid(ball) and not bool(ball.get("_ccd_ready")):
		await physics_frame
	return ball if is_instance_valid(ball) else null


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


func _delete_profile() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("profile.save"):
		dir.remove("profile.save")


func _is_uuid_v4(value: String) -> bool:
	var re := RegEx.new()
	re.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")
	return re.search(value) != null


func _fail(message: String) -> bool:
	push_error("PROFILE FAIL %s" % message)
	print("PROFILE FAIL %s" % message)
	quit(1)
	return false
