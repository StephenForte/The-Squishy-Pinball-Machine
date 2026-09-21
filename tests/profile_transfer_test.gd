extends SceneTree

## Profile transfer by player id (D-048). Never hits live: restore HTTP
## outcomes are driven through Leaderboard's own callback.

const SAVE_PATH := "user://profile.save"
const SENTINEL_URL := "http://127.0.0.1:1"
const LIVE_COUNT_URL := "http://127.0.0.1:2"
const CLOUD_ID := "6a7a41f5-0000-4000-8000-000000000001"
const OTHER_ID := "b8aa808f-0000-4000-8000-000000000002"

var _cases_passed: int = 0
var _profile: Node
var _leaderboard: Node
var _game: Node
var _name_changed_count: int = 0
var _avatar_changed_count: int = 0
var _restore_ok: bool = false
var _restore_reason: String = ""
var _got_restore: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("TRANSFER start")
	_profile = root.get_node_or_null("Profile")
	_leaderboard = root.get_node_or_null("Leaderboard")
	_game = root.get_node_or_null("Game")
	if _profile == null or _leaderboard == null or _game == null:
		_fail("Profile, Leaderboard, or Game autoload missing")
		return
	if not _profile.has_method("adopt_identity"):
		_fail("Profile.adopt_identity missing")
		return
	if not _leaderboard.has_method("restore_profile"):
		_fail("Leaderboard.restore_profile missing")
		return
	if not _leaderboard.has_signal("restore_finished"):
		_fail("Leaderboard.restore_finished missing")
		return
	if not _profile.name_changed.is_connected(_on_name_changed):
		_profile.name_changed.connect(_on_name_changed)
	if not _profile.avatar_changed.is_connected(_on_avatar_changed):
		_profile.avatar_changed.connect(_on_avatar_changed)
	if not _leaderboard.restore_finished.is_connected(_on_restore_finished):
		_leaderboard.restore_finished.connect(_on_restore_finished)

	if not _case_1_overwrite_existing_mapping():
		return
	if not _case_2_reject_leaves_untouched():
		return
	if not _case_3_404_does_not_adopt():
		return
	if not _case_4_restore_does_not_put():
		return
	if not _case_5_round_trip_survives_reload():
		return
	if not _case_5b_stale_restore_ignored():
		return

	if String(_profile.player_name).is_empty():
		_profile.call("set_name", "Dad")
	_game.high_score = 0
	_game.restart()
	await process_frame

	print("TRANSFER loading main.tscn")
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

	if not await _case_6_overlay_hidden_default(main):
		return
	if not await _case_7_restore_messages(main):
		return
	if not await _case_8_success_reflects(main):
		return
	if not await _case_9_lineedit_does_not_leak(main):
		return

	print("TRANSFER PASS cases=%d" % _cases_passed)
	quit(0)


func _on_name_changed(_name: String) -> void:
	_name_changed_count += 1


func _on_avatar_changed(_avatar_id: String) -> void:
	_avatar_changed_count += 1


func _on_restore_finished(ok: bool, reason: String) -> void:
	_got_restore = true
	_restore_ok = ok
	_restore_reason = reason


func _case_1_overwrite_existing_mapping() -> bool:
	print("TRANSFER case 1 overwrite existing players[key]")
	_profile.call("set_name", "Dad")
	var local_id := String(_profile.player_id)
	if not _is_uuid_v4(local_id):
		return _fail("case 1: local Dad id is not UUID v4: %s" % local_id)
	if String(_profile.players.get("dad", "")) != local_id:
		return _fail("case 1: players[dad] should be %s" % local_id)
	_name_changed_count = 0
	_avatar_changed_count = 0
	if not bool(_profile.adopt_identity(CLOUD_ID, "Dad", "bear_bounce")):
		return _fail("case 1: adopt_identity should succeed")
	if String(_profile.player_id) != CLOUD_ID:
		return _fail("case 1: player_id %s want %s" % [_profile.player_id, CLOUD_ID])
	if String(_profile.player_name) != "Dad":
		return _fail("case 1: name %s want Dad" % _profile.player_name)
	if String(_profile.players.get("dad", "")) != CLOUD_ID:
		return _fail("case 1: players[dad] was not overwritten, got %s" % _profile.players.get("dad", ""))
	if String(_profile.players.get("dad", "")) == local_id:
		return _fail("case 1: previous local id was kept")
	if String(_profile.avatar_id) != "bear_bounce":
		return _fail("case 1: avatar_id %s want bear_bounce" % _profile.avatar_id)
	if String(_profile.avatars.get("dad", "")) != "bear_bounce":
		return _fail("case 1: avatars[dad] %s want bear_bounce" % _profile.avatars.get("dad", ""))
	if _name_changed_count < 1 or _avatar_changed_count < 1:
		return _fail("case 1: expected name_changed and avatar_changed")
	_cases_passed += 1
	print("TRANSFER case 1 pass")
	return true


func _case_2_reject_leaves_untouched() -> bool:
	print("TRANSFER case 2 rejected adopt leaves state")
	if not bool(_profile.adopt_identity(OTHER_ID, "Dad", "frog_gus")):
		return _fail("case 2: setup adopt failed")
	var before_id := String(_profile.player_id)
	var before_name := String(_profile.player_name)
	var before_players: Dictionary = _profile.players.duplicate(true)
	var before_avatars: Dictionary = _profile.avatars.duplicate(true)
	_name_changed_count = 0
	_avatar_changed_count = 0
	if bool(_profile.adopt_identity("not-a-uuid", "Dad", "bear_bounce")):
		return _fail("case 2: bad uuid should be rejected")
	if bool(_profile.adopt_identity(CLOUD_ID, "   ", "bear_bounce")):
		return _fail("case 2: whitespace name should be rejected")
	if bool(_profile.adopt_identity(CLOUD_ID, "", "bear_bounce")):
		return _fail("case 2: empty name should be rejected")
	if String(_profile.player_id) != before_id:
		return _fail("case 2: player_id changed on reject: %s" % _profile.player_id)
	if String(_profile.player_name) != before_name:
		return _fail("case 2: player_name changed on reject")
	if _dict_string(_profile.players) != _dict_string(before_players):
		return _fail("case 2: players changed on reject")
	if _dict_string(_profile.avatars) != _dict_string(before_avatars):
		return _fail("case 2: avatars changed on reject")
	if _name_changed_count != 0 or _avatar_changed_count != 0:
		return _fail("case 2: reject emitted signals")
	_cases_passed += 1
	print("TRANSFER case 2 pass")
	return true


func _case_3_404_does_not_adopt() -> bool:
	print("TRANSFER case 3 404 does not adopt")
	if not bool(_profile.adopt_identity(OTHER_ID, "Dad", "frog_gus")):
		return _fail("case 3: setup adopt failed")
	var before_id := String(_profile.player_id)
	var before_players: Dictionary = _profile.players.duplicate(true)
	_reset_restore_flags()
	_finish_restore(false, 404, null, "http_404")
	if not _got_restore:
		return _fail("case 3: restore_finished did not fire")
	if _restore_ok or _restore_reason != "not_found":
		return _fail("case 3: expected not_found, got ok=%s reason=%s" % [_restore_ok, _restore_reason])
	if String(_profile.player_id) != before_id:
		return _fail("case 3: 404 adopted player_id %s" % _profile.player_id)
	if _dict_string(_profile.players) != _dict_string(before_players):
		return _fail("case 3: 404 mutated players")
	_cases_passed += 1
	print("TRANSFER case 3 pass")
	return true


func _case_4_restore_does_not_put() -> bool:
	print("TRANSFER case 4 restore does not PUT")
	if not bool(_profile.adopt_identity(OTHER_ID, "Dad", "frog_gus")):
		return _fail("case 4: setup adopt failed")
	OS.set_environment("SQUISH_LEADERBOARD_URL", LIVE_COUNT_URL)
	var before := int(_leaderboard._profile_push_count)
	_reset_restore_flags()
	_finish_restore(true, 200, {
		"player_id": CLOUD_ID,
		"name": "Dad",
		"avatar": "bear_bounce",
	}, "")
	OS.set_environment("SQUISH_LEADERBOARD_URL", SENTINEL_URL)
	if not _got_restore or not _restore_ok:
		return _fail("case 4: restore should succeed, got ok=%s reason=%s" % [_restore_ok, _restore_reason])
	if String(_profile.player_id) != CLOUD_ID:
		return _fail("case 4: player_id %s want %s" % [_profile.player_id, CLOUD_ID])
	if int(_leaderboard._profile_push_count) != before:
		return _fail("case 4: restore must not PUT, count %s → %s" % [before, _leaderboard._profile_push_count])
	_cases_passed += 1
	print("TRANSFER case 4 pass")
	return true


func _case_5_round_trip_survives_reload() -> bool:
	print("TRANSFER case 5 round trip reload")
	if not bool(_profile.adopt_identity(CLOUD_ID, "Dad", "bear_bounce")):
		return _fail("case 5: adopt failed")
	if String(_profile.player_id) != CLOUD_ID:
		return _fail("case 5: adopt did not set id")
	_profile._load_or_create()
	if String(_profile.player_id) != CLOUD_ID:
		return _fail("case 5: reload dropped id, got %s" % _profile.player_id)
	if String(_profile.player_name) != "Dad":
		return _fail("case 5: reload dropped name, got %s" % _profile.player_name)
	if String(_profile.players.get("dad", "")) != CLOUD_ID:
		return _fail("case 5: reload dropped players[dad]")
	var disk := _read_profile_save()
	if String(disk.get("player_id", "")) != CLOUD_ID:
		return _fail("case 5: profile.save player_id %s want %s" % [disk.get("player_id", ""), CLOUD_ID])
	_cases_passed += 1
	print("TRANSFER case 5 pass")
	return true


func _case_5b_stale_restore_ignored() -> bool:
	print("TRANSFER case 5b stale restore ignored")
	if not bool(_profile.adopt_identity(OTHER_ID, "Dad", "frog_gus")):
		return _fail("case 5b: setup adopt failed")
	var before_id := String(_profile.player_id)
	_leaderboard._restore_gen += 1
	var stale: int = int(_leaderboard._restore_gen)
	_leaderboard._restore_gen += 1
	_reset_restore_flags()
	_leaderboard._on_restore_profile_finished(true, 200, {
		"player_id": CLOUD_ID,
		"name": "Dad",
		"avatar": "bear_bounce",
	}, "", stale)
	if _got_restore:
		return _fail("case 5b: stale restore_finished should be dropped")
	if String(_profile.player_id) != before_id:
		return _fail("case 5b: stale success adopted %s" % _profile.player_id)
	_finish_restore(false, 404, null, "http_404")
	if not _got_restore or _restore_ok or _restore_reason != "not_found":
		return _fail("case 5b: current 404 should still surface")
	if String(_profile.player_id) != before_id:
		return _fail("case 5b: current 404 changed player_id")
	_cases_passed += 1
	print("TRANSFER case 5b pass")
	return true


func _case_6_overlay_hidden_default(main: Node) -> bool:
	print("TRANSFER case 6 overlay hidden default")
	var settings := main.get_node_or_null("Title/Settings") as Control
	if settings == null:
		return _fail("case 6: Title/Settings missing")
	var toggle := settings.get_node_or_null("ThisDevice/ShowCodeToggle") as Button
	var code := settings.get_node_or_null("ThisDevice/CodeLabel") as Label
	var copy := settings.get_node_or_null("ThisDevice/CopyButton") as Button
	var restore := settings.get_node_or_null("RestoreProfile") as Control
	var edit := settings.get_node_or_null("RestoreProfile/CodeEdit") as LineEdit
	if toggle == null or code == null or copy == null or restore == null or edit == null:
		return _fail("case 6: transfer nodes missing")
	if code.visible or copy.visible:
		return _fail("case 6: transfer code must be hidden by default")
	_open_settings(main)
	await process_frame
	if code.visible or copy.visible:
		return _fail("case 6: opening Settings revealed the transfer code")
	if toggle.text != "Show transfer code":
		return _fail("case 6: toggle text %s" % toggle.text)
	toggle.pressed.emit()
	await process_frame
	if not code.visible or not copy.visible:
		return _fail("case 6: toggle should reveal code and Copy")
	if String(code.text) != String(_profile.player_id):
		return _fail("case 6: CodeLabel %s want %s" % [code.text, _profile.player_id])
	copy.pressed.emit()
	await process_frame
	_close_settings(main)
	await process_frame
	_cases_passed += 1
	print("TRANSFER case 6 pass")
	return true


func _case_7_restore_messages(main: Node) -> bool:
	print("TRANSFER case 7 restore messages")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var edit := settings.get_node_or_null("RestoreProfile/CodeEdit") as LineEdit
	var button := settings.get_node_or_null("RestoreProfile/RestoreButton") as Button
	var status := settings.get_node_or_null("RestoreProfile/StatusLabel") as Label
	if settings == null or edit == null or button == null or status == null:
		return _fail("case 7: restore UI missing")
	_open_settings(main)
	await process_frame
	status.text = "stale"
	edit.text = "   "
	button.pressed.emit()
	await process_frame
	if status.text != "stale":
		return _fail("case 7: whitespace input should be a silent no-op, got '%s'" % status.text)
	edit.text = ""
	button.pressed.emit()
	await process_frame
	if status.text != "stale":
		return _fail("case 7: empty input should be a silent no-op, got '%s'" % status.text)
	edit.text = "not-a-uuid"
	button.pressed.emit()
	await process_frame
	if status.text != "that code doesn't look right":
		return _fail("case 7: bad uuid message '%s'" % status.text)
	_reset_restore_flags()
	_finish_restore(false, 404, null, "http_404")
	await process_frame
	if status.text != "no profile found":
		return _fail("case 7: 404 message '%s'" % status.text)
	_reset_restore_flags()
	_finish_restore(false, 0, null, "unreachable")
	await process_frame
	if status.text != "couldn't reach the leaderboard":
		return _fail("case 7: offline message '%s'" % status.text)
	_close_settings(main)
	await process_frame
	_cases_passed += 1
	print("TRANSFER case 7 pass")
	return true


func _case_8_success_reflects(main: Node) -> bool:
	print("TRANSFER case 8 success reflects name and avatar")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var name_label := settings.get_node_or_null("ThisDevice/NameLabel") as Label
	var picker := settings.get_node_or_null("AvatarPicker")
	if settings == null or name_label == null or picker == null:
		return _fail("case 8: overlay nodes missing")
	if not bool(_profile.adopt_identity(OTHER_ID, "LocalPat", "frog_gus")):
		return _fail("case 8: setup adopt failed")
	_open_settings(main)
	await process_frame
	OS.set_environment("SQUISH_LEADERBOARD_URL", LIVE_COUNT_URL)
	var before := int(_leaderboard._profile_push_count)
	_reset_restore_flags()
	_finish_restore(true, 200, {
		"player_id": CLOUD_ID,
		"name": "Dad",
		"avatar": "bear_bounce",
	}, "")
	OS.set_environment("SQUISH_LEADERBOARD_URL", SENTINEL_URL)
	await process_frame
	await process_frame
	if String(_profile.player_id) != CLOUD_ID or String(_profile.player_name) != "Dad":
		return _fail("case 8: restore did not adopt")
	if String(_profile.avatar_id) != "bear_bounce":
		return _fail("case 8: avatar %s want bear_bounce" % _profile.avatar_id)
	if int(_leaderboard._profile_push_count) != before:
		return _fail("case 8: success path PUT, count %s → %s" % [before, _leaderboard._profile_push_count])
	if name_label.text != "Dad":
		return _fail("case 8: overlay name '%s' want Dad" % name_label.text)
	if picker.has_method("offered_ids"):
		var choice := picker.get_node_or_null("Grid/Choice_bear_bounce") as BaseButton
		if choice == null:
			return _fail("case 8: AvatarPicker missing Choice_bear_bounce")
		if choice.modulate == Color.WHITE:
			return _fail("case 8: AvatarPicker did not highlight bear_bounce")
	_close_settings(main)
	await process_frame
	_cases_passed += 1
	print("TRANSFER case 8 pass")
	return true


func _case_9_lineedit_does_not_leak(main: Node) -> bool:
	print("TRANSFER case 9 LineEdit does not leak keys")
	var title := main.get_node_or_null("Title")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var entry := main.get_node_or_null("Title/NameEntry")
	var edit := settings.get_node_or_null("RestoreProfile/CodeEdit") as LineEdit
	if title == null or settings == null or entry == null or edit == null:
		return _fail("case 9: nodes missing")
	_open_settings(main)
	await process_frame
	if not settings.is_visible_in_tree():
		return _fail("case 9: Settings should be open")
	edit.text = ""
	edit.grab_focus()
	await process_frame
	if not edit.has_focus():
		return _fail("case 9: CodeEdit should have focus")
	var score_before: int = _game.score
	var state_before: int = _game.state
	_type_char(main, KEY_S, 115)
	_type_char(main, KEY_R, 114)
	_type_char(main, KEY_SPACE, 32)
	_type_char(main, KEY_N, 110)
	await process_frame
	await process_frame
	if edit.text != "sr n":
		return _fail("case 9: CodeEdit should accept s/r/space/n, got '%s'" % edit.text)
	if not settings.is_visible_in_tree():
		return _fail("case 9: S closed Settings while CodeEdit focused")
	if not title.visible:
		return _fail("case 9: Space hid Title while CodeEdit focused")
	if _game.score != score_before or _game.state != state_before:
		return _fail("case 9: R restarted while CodeEdit focused")
	if entry.visible or (entry.has_method("is_capturing") and entry.is_capturing()):
		return _fail("case 9: N opened NameEntry while CodeEdit focused")
	_push_action(main, "menu")
	await process_frame
	await process_frame
	_push_action(main, "menu", false)
	if _game.score != score_before or _game.state != state_before:
		return _fail("case 9: Escape leaked to main.gd")
	_cases_passed += 1
	print("TRANSFER case 9 pass")
	return true


func _open_settings(main: Node) -> void:
	var settings := main.get_node_or_null("Title/Settings") as Control
	if settings != null and settings.has_method("open"):
		settings.open()
	elif settings != null:
		settings.visible = true


func _close_settings(main: Node) -> void:
	var settings := main.get_node_or_null("Title/Settings") as Control
	if settings != null and settings.has_method("close"):
		settings.close()
	elif settings != null:
		settings.visible = false


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


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _read_profile_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _dict_string(value: Dictionary) -> String:
	return JSON.stringify(value)


func _is_uuid_v4(value: String) -> bool:
	var re := RegEx.new()
	if re.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$") != OK:
		return false
	return re.search(value) != null


func _reset_restore_flags() -> void:
	_got_restore = false
	_restore_ok = false
	_restore_reason = ""


func _finish_restore(ok: bool, code: int, parsed: Variant, reason: String) -> void:
	_leaderboard._restore_gen += 1
	_leaderboard._on_restore_profile_finished(ok, code, parsed, reason, int(_leaderboard._restore_gen))


func _fail(message: String) -> bool:
	push_error("TRANSFER FAIL %s" % message)
	print("TRANSFER FAIL %s" % message)
	quit(1)
	return false
