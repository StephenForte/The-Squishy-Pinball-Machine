extends SceneTree

## D-051. Game over must be readable on a touch device, and an unnamed score
## must be savable. Headless routes no GUI clicks; buttons are driven with
## pressed.emit() / text_submitted.emit(), and geometry is asserted directly.

const DESKTOP_HINT := "R restart · Esc menu"
## 64 CSS px at a 375-wide phone, mapped onto the 720-wide viewport.
const MIN_PX := 64.0 * 720.0 / 375.0
const FLOOR_Y := 1150.0
## Stand-in for a keyboard on the bottom half. A control that ends above this
## is still on screen while the field is focused.
const KEYBOARD_TOP := 640.0

var _cases_passed: int = 0
var _lb: Node
var _names: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("GAME_OVER_TOUCH start")
	DisplayServer.window_set_size(Vector2i(720, 1280))
	var profile := root.get_node_or_null("Profile")
	var game := root.get_node_or_null("Game")
	_lb = root.get_node_or_null("Leaderboard")
	if profile == null or game == null or _lb == null:
		_fail("Profile, Game, or Leaderboard autoload missing")
		return
	if _lb.has_signal("submit_attempted") and not _lb.submit_attempted.is_connected(_on_submit_attempted):
		_lb.submit_attempted.connect(_on_submit_attempted)
	_reset_profile(profile)
	game.high_score = 0
	game.restart()
	await process_frame

	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not change to main.tscn")
		return
	await process_frame
	await process_frame
	await process_frame
	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)
	if String(profile.player_name) != "":
		_fail("fresh profile name should be empty, got '%s'" % profile.player_name)
		return

	if not await _case_desktop_hint(main, game):
		return
	if not await _case_touch_layout(main, game):
		return
	if not await _case_return_key(main, game, profile):
		return
	if not await _case_focus_loss(main, game, profile):
		return
	if not await _case_save_button(main, game, profile):
		return
	if not await _case_decline(main, game, profile):
		return
	if not await _case_blank(main, game, profile):
		return
	if not await _case_restart_empty(main, game):
		return
	if not await _case_menu_commits(main, game, profile):
		return
	if not await _case_named_player_once(main, game, profile):
		return
	if not await _case_cancelled_skip(main, game, profile):
		return

	print("GAME_OVER_TOUCH PASS cases=%d" % _cases_passed)
	quit(0)


func _on_submit_attempted(_token: int, _attempt: int) -> void:
	var profile := root.get_node_or_null("Profile")
	_names.append(String(profile.player_name) if profile != null else "")


func _case_desktop_hint(main: Node, game: Node) -> bool:
	print("GAME_OVER_TOUCH case 1 desktop hint")
	if DisplayServer.is_touchscreen_available():
		return _fail("case 1: touchscreen reported before emulate_touch_from_mouse")
	if not await _go_game_over(main, game, 500):
		return false
	var hint := _hint(main)
	if hint == null:
		return _fail("case 1: HintLabel missing")
	if hint.text != DESKTOP_HINT:
		return _fail("case 1: desktop hint changed to '%s'" % hint.text)
	if _attempt_total() != 0:
		return _fail("case 1: unnamed game over submitted %d" % _attempt_total())
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 1 pass")
	return true


func _case_touch_layout(main: Node, game: Node) -> bool:
	print("GAME_OVER_TOUCH case 2 touch layout")
	Input.emulate_touch_from_mouse = true
	if not DisplayServer.is_touchscreen_available():
		return _fail("case 2: touchscreen was not reported")
	if not await _go_game_over(main, game, 500):
		return false
	var game_over := _game_over(main)
	var hint := _hint(main)
	var restart := _button(game_over, "RestartButton")
	var menu := _button(game_over, "MenuButton")
	var save := _button(game_over, "SaveButton")
	var skip := _button(game_over, "SkipButton")
	var edit := game_over.get_node_or_null("NameEdit") as LineEdit
	if hint == null or restart == null or menu == null or save == null or skip == null or edit == null:
		return _fail("case 2: game-over controls missing")
	if hint.text == DESKTOP_HINT or hint.text.contains("Esc") or hint.text.contains("R restart"):
		return _fail("case 2: touch hint still names keys: '%s'" % hint.text)
	if not hint.text.contains("Restart") or not hint.text.contains("Menu"):
		return _fail("case 2: touch hint does not name the buttons: '%s'" % hint.text)
	if not edit.visible or not save.visible or not skip.visible:
		return _fail("case 2: unnamed game over hid the name prompt")
	var theme := root.get_node_or_null("Theme")
	if theme == null or not theme.has_method("color"):
		return _fail("case 2: Theme missing")
	var pink: Color = theme.color("object_pink")
	var on_color: Color = theme.color("text_on_color")
	var probe := Button.new()
	game_over.add_child(probe)
	await process_frame
	var default_style := probe.get_theme_stylebox("normal")
	var default_bg := Color(0, 0, 0, 0)
	if default_style is StyleBoxFlat:
		default_bg = (default_style as StyleBoxFlat).bg_color
	probe.queue_free()
	for button in [restart, menu]:
		if not _assert_pink_button(button, pink, on_color, default_bg, "case 2"):
			return false
		var rect: Rect2 = button.get_global_rect()
		if rect.size.x < MIN_PX or rect.size.y < MIN_PX:
			return _fail("case 2: %s %s smaller than %.1f px" % [button.name, rect.size, MIN_PX])
		if rect.position.y + rect.size.y > FLOOR_Y:
			return _fail("case 2: %s extends below y=1150: %s" % [button.name, rect])
	var restart_rect := restart.get_global_rect()
	var menu_rect := menu.get_global_rect()
	if restart_rect.intersects(menu_rect):
		return _fail("case 2: Restart %s overlaps Menu %s" % [restart_rect, menu_rect])
	if not _assert_save_adjacent(edit, save):
		return false
	var skip_rect := skip.get_global_rect()
	var edit_rect := edit.get_global_rect()
	if skip_rect.intersects(edit_rect) or skip_rect.intersects(save.get_global_rect()):
		return _fail("case 2: Not now overlaps the name row")
	if skip_rect.position.y < edit_rect.position.y + edit_rect.size.y - 1.0:
		return _fail("case 2: Not now is not below the name field")
	edit.grab_focus()
	await process_frame
	await process_frame
	if not edit.has_focus():
		return _fail("case 2: NameEdit did not take focus")
	for button in [restart, menu, save, skip]:
		var rect: Rect2 = button.get_global_rect()
		if rect.position.y + rect.size.y >= KEYBOARD_TOP:
			return _fail("case 2: %s %s is under the keyboard while the field is focused" % [button.name, rect])
		if rect.intersects(edit.get_global_rect()) and button != save:
			return _fail("case 2: %s overlaps NameEdit while focused" % button.name)
		var hit := _top_stop_at(game_over, rect.get_center())
		if hit != button:
			return _fail("case 2: %s center hits %s" % [button.name, hit.name if hit != null else "nothing"])
	edit.release_focus()
	await process_frame
	if _attempt_total() != 0:
		return _fail("case 2: focusing an empty field submitted")
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 2 pass")
	return true


func _case_return_key(main: Node, game: Node, profile: Node) -> bool:
	print("GAME_OVER_TOUCH case 3 return key alone")
	_reset_profile(profile)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, game, 700):
		return false
	if _attempt_snapshot() != before:
		return _fail("case 3: unnamed game over submitted before a name")
	var edit := _game_over(main).get_node_or_null("NameEdit") as LineEdit
	if edit == null or not edit.visible:
		return _fail("case 3: NameEdit missing")
	edit.text = "Dad"
	edit.text_submitted.emit("Dad")
	await process_frame
	await process_frame
	if not _assert_one_submit(before, names_before, "Dad", "case 3"):
		return false
	if String(profile.player_name) != "Dad":
		return _fail("case 3: name is '%s'" % profile.player_name)
	# The field blur that follows a commit must not post a second score.
	if edit.has_focus():
		edit.release_focus()
	await process_frame
	await process_frame
	if not _assert_one_submit(before, names_before, "Dad", "case 3 after blur"):
		return false
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 3 pass")
	return true


func _case_focus_loss(main: Node, game: Node, profile: Node) -> bool:
	print("GAME_OVER_TOUCH case 4 focus loss")
	_reset_profile(profile)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, game, 640):
		return false
	var edit := _game_over(main).get_node_or_null("NameEdit") as LineEdit
	if edit == null:
		return _fail("case 4: NameEdit missing")
	edit.text = "Mo"
	edit.grab_focus()
	await process_frame
	if not edit.has_focus():
		return _fail("case 4: NameEdit did not take focus")
	edit.release_focus()
	await process_frame
	await process_frame
	if not _assert_one_submit(before, names_before, "Mo", "case 4"):
		return false
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 4 pass")
	return true


func _case_save_button(main: Node, game: Node, profile: Node) -> bool:
	print("GAME_OVER_TOUCH case 5 save button")
	_reset_profile(profile)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, game, 610):
		return false
	var game_over := _game_over(main)
	var edit := game_over.get_node_or_null("NameEdit") as LineEdit
	var save := _button(game_over, "SaveButton")
	if edit == null or save == null:
		return _fail("case 5: name controls missing")
	edit.text = "Lux"
	edit.grab_focus()
	await process_frame
	save.pressed.emit()
	await process_frame
	await process_frame
	if not _assert_one_submit(before, names_before, "Lux", "case 5"):
		return false
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 5 pass")
	return true


func _case_decline(main: Node, game: Node, profile: Node) -> bool:
	print("GAME_OVER_TOUCH case 6 decline")
	_reset_profile(profile)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, game, 550):
		return false
	var game_over := _game_over(main)
	var edit := game_over.get_node_or_null("NameEdit") as LineEdit
	var skip := _button(game_over, "SkipButton")
	if edit == null or skip == null:
		return _fail("case 6: name controls missing")
	edit.text = "Sam"
	edit.grab_focus()
	await process_frame
	# button_down lands in the same click as focus leaving the field.
	skip.button_down.emit()
	edit.focus_exited.emit()
	skip.pressed.emit()
	await process_frame
	await process_frame
	if _attempt_snapshot() != before or _names.size() != names_before:
		return _fail("case 6: decline submitted (%s names=%s)" % [_attempt_snapshot(), _names])
	if String(profile.player_name) != "":
		return _fail("case 6: decline set name to '%s'" % profile.player_name)
	if edit.visible:
		return _fail("case 6: decline left the prompt up")
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 6 pass")
	return true


func _case_blank(main: Node, game: Node, profile: Node) -> bool:
	print("GAME_OVER_TOUCH case 7 blank name")
	_reset_profile(profile)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, game, 540):
		return false
	var edit := _game_over(main).get_node_or_null("NameEdit") as LineEdit
	if edit == null:
		return _fail("case 7: NameEdit missing")
	edit.text = "   "
	edit.text_submitted.emit("   ")
	await process_frame
	edit.text = ""
	edit.grab_focus()
	await process_frame
	edit.release_focus()
	await process_frame
	await process_frame
	if _attempt_snapshot() != before or _names.size() != names_before:
		return _fail("case 7: blank name submitted")
	if String(profile.player_name) != "":
		return _fail("case 7: blank name set '%s'" % profile.player_name)
	if not edit.visible:
		return _fail("case 7: blank confirm dismissed the prompt")
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 7 pass")
	return true


func _case_restart_empty(main: Node, game: Node) -> bool:
	print("GAME_OVER_TOUCH case 8 restart while focused")
	var before := _attempt_snapshot()
	if not await _go_game_over(main, game, 20):
		return false
	var game_over := _game_over(main)
	var edit := game_over.get_node_or_null("NameEdit") as LineEdit
	var restart := _button(game_over, "RestartButton")
	if edit == null or restart == null:
		return _fail("case 8: controls missing")
	edit.grab_focus()
	await process_frame
	if not edit.has_focus():
		return _fail("case 8: NameEdit did not take focus")
	restart.pressed.emit()
	await process_frame
	await process_frame
	if game.state != game.READY:
		return _fail("case 8: expected READY after RestartButton, got %s" % game.state)
	if game_over.visible:
		return _fail("case 8: GameOver should be hidden after RestartButton")
	if _attempt_snapshot() != before:
		return _fail("case 8: empty restart submitted")
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 8 pass")
	return true


func _case_menu_commits(main: Node, game: Node, profile: Node) -> bool:
	print("GAME_OVER_TOUCH case 9 menu keeps a typed name")
	_reset_profile(profile)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, game, 480):
		return false
	var game_over := _game_over(main)
	var title := main.get_node_or_null("Title")
	var edit := game_over.get_node_or_null("NameEdit") as LineEdit
	var menu := _button(game_over, "MenuButton")
	if title == null or edit == null or menu == null:
		return _fail("case 9: controls missing")
	edit.text = "Rex"
	edit.grab_focus()
	await process_frame
	menu.pressed.emit()
	await process_frame
	await process_frame
	if not title.visible:
		return _fail("case 9: Title should be visible after MenuButton")
	if game_over.visible:
		return _fail("case 9: GameOver should be hidden after MenuButton")
	if not _assert_one_submit(before, names_before, "Rex", "case 9"):
		return false
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 9 pass")
	return true


func _case_named_player_once(main: Node, game: Node, profile: Node) -> bool:
	print("GAME_OVER_TOUCH case 10 named player submits once")
	_reset_profile(profile)
	profile.call("set_name", "Dad")
	if String(profile.player_name) != "Dad":
		return _fail("case 10: could not set name")
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, game, 800):
		return false
	var game_over := _game_over(main)
	var edit := game_over.get_node_or_null("NameEdit") as LineEdit
	var save := _button(game_over, "SaveButton")
	if edit == null or save == null:
		return _fail("case 10: name controls missing")
	if edit.visible or save.visible:
		return _fail("case 10: named player was asked for a name again")
	await process_frame
	if not _assert_one_submit(before, names_before, "Dad", "case 10"):
		return false
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 10 pass")
	return true


func _case_cancelled_skip(main: Node, game: Node, profile: Node) -> bool:
	print("GAME_OVER_TOUCH case 11 cancelled Not now still saves")
	_reset_profile(profile)
	var before := _attempt_snapshot()
	var names_before := _names.size()
	if not await _go_game_over(main, game, 460):
		return false
	var game_over := _game_over(main)
	var edit := game_over.get_node_or_null("NameEdit") as LineEdit
	var skip := _button(game_over, "SkipButton")
	if edit == null or skip == null:
		return _fail("case 11: name controls missing")
	edit.text = "Nia"
	edit.grab_focus()
	await process_frame
	# Press-down then release outside the button: pressed never fires.
	skip.button_down.emit()
	edit.focus_exited.emit()
	skip.button_up.emit()
	await process_frame
	await process_frame
	if _attempt_snapshot() != before or _names.size() != names_before:
		return _fail("case 11: cancelled Not now submitted")
	if String(profile.player_name) != "":
		return _fail("case 11: cancelled Not now set name to '%s'" % profile.player_name)
	if not edit.visible:
		return _fail("case 11: cancelled Not now dismissed the prompt")
	edit.text = "Nia"
	edit.text_submitted.emit("Nia")
	await process_frame
	await process_frame
	if not _assert_one_submit(before, names_before, "Nia", "case 11"):
		return false
	_cases_passed += 1
	print("GAME_OVER_TOUCH case 11 pass")
	return true


func _assert_save_adjacent(edit: LineEdit, save: Button) -> bool:
	var edit_rect := edit.get_global_rect()
	var save_rect := save.get_global_rect()
	if save_rect.intersects(edit_rect):
		_fail("case 2: Save %s overlaps NameEdit %s" % [save_rect, edit_rect])
		return false
	var gap := save_rect.position.x - (edit_rect.position.x + edit_rect.size.x)
	if gap < 0.0 or gap > 16.0:
		_fail("case 2: Save is not beside the field, gap %.1f" % gap)
		return false
	if abs(save_rect.position.y - edit_rect.position.y) > 1.0:
		_fail("case 2: Save is not on the field's row")
		return false
	if abs((save_rect.position.y + save_rect.size.y) - (edit_rect.position.y + edit_rect.size.y)) > 1.0:
		_fail("case 2: Save height does not match the field")
		return false
	if save_rect.size.x < MIN_PX or save_rect.size.y < MIN_PX:
		_fail("case 2: Save %s smaller than %.1f px" % [save_rect.size, MIN_PX])
		return false
	return true


func _assert_pink_button(button: Button, pink: Color, on_color: Color, default_bg: Color, label: String) -> bool:
	for state in ["normal", "hover", "pressed"]:
		var style := button.get_theme_stylebox(state)
		if not (style is StyleBoxFlat):
			_fail("%s: %s %s style is not StyleBoxFlat" % [label, button.name, state])
			return false
		var bg: Color = (style as StyleBoxFlat).bg_color
		if bg != pink:
			_fail("%s: %s %s bg %s is not object_pink %s" % [label, button.name, state, bg, pink])
			return false
		if bg == default_bg:
			_fail("%s: %s %s bg is the default button colour" % [label, button.name, state])
			return false
	if button.get_theme_color("font_color") != on_color:
		_fail("%s: %s font is not text_on_color" % [label, button.name])
		return false
	return true


func _assert_one_submit(before: Vector2i, names_before: int, expected: String, label: String) -> bool:
	var after := _attempt_snapshot()
	if after.x != before.x + 1 or after.y != before.y + 1:
		_fail("%s: expected one submission, tokens %s → %s" % [label, before, after])
		return false
	if _names.size() != names_before + 1:
		_fail("%s: submit signals %d → %d" % [label, names_before, _names.size()])
		return false
	if String(_names[_names.size() - 1]) != expected:
		_fail("%s: submission carried '%s', expected '%s'" % [label, _names[_names.size() - 1], expected])
		return false
	return true


func _attempt_snapshot() -> Vector2i:
	var counts: Dictionary = _lb.submit_attempts
	var total := 0
	for value in counts.values():
		total += int(value)
	return Vector2i(counts.size(), total)


func _attempt_total() -> int:
	return _attempt_snapshot().y


func _go_game_over(main: Node, game: Node, points: int) -> bool:
	if game.state == game.GAME_OVER:
		game.restart()
		await process_frame
		await process_frame
	var title := main.get_node_or_null("Title")
	if title != null and title.visible:
		if not await _dismiss_title(main):
			_fail("could not leave the title")
			return false
	game.add_score(points)
	for _i in 3:
		game.on_ball_drained()
		await physics_frame
		await process_frame
	var game_over := _game_over(main)
	if game_over == null or not game_over.visible:
		_fail("GameOver should be visible")
		return false
	if game.state != game.GAME_OVER:
		_fail("expected GAME_OVER, got %s" % game.state)
		return false
	return true


func _dismiss_title(main: Node) -> bool:
	var title := main.get_node_or_null("Title")
	if title == null:
		return false
	var entry := title.get_node_or_null("NameEntry")
	if entry != null and entry.has_method("release_name_focus"):
		entry.call("release_name_focus")
	await process_frame
	_push_action(main, "launch_ball")
	await process_frame
	await process_frame
	_push_action(main, "launch_ball", false)
	await process_frame
	return not title.visible


func _game_over(main: Node) -> Node:
	return main.get_node_or_null("GameOver")


func _hint(main: Node) -> Label:
	var game_over := _game_over(main)
	if game_over == null:
		return null
	return game_over.get_node_or_null("HintLabel") as Label


func _button(game_over: Node, node_name: String) -> Button:
	if game_over == null:
		return null
	return game_over.get_node_or_null(node_name) as Button


func _top_stop_at(node: Node, point: Vector2) -> Control:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return null
	if node is Control:
		var ctrl := node as Control
		if ctrl.clip_contents and not ctrl.get_global_rect().has_point(point):
			return null
	var children := node.get_children()
	for i in range(children.size() - 1, -1, -1):
		var found := _top_stop_at(children[i], point)
		if found != null:
			return found
	if node is Control:
		var leaf := node as Control
		if leaf.mouse_filter == Control.MOUSE_FILTER_STOP and leaf.get_global_rect().has_point(point):
			return leaf
	return null


func _reset_profile(profile: Node) -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("profile.save"):
		dir.remove("profile.save")
	if profile.has_method("_load_or_create"):
		profile.call("_load_or_create")


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


func _fail(message: String) -> bool:
	push_error("GAME_OVER_TOUCH FAIL %s" % message)
	print("GAME_OVER_TOUCH FAIL %s" % message)
	quit(1)
	return false
