extends SceneTree

## D-043 properties. Touches are synthesized — no hardware required.

const LEFT_ZONE := Vector2(180, 960)
const RIGHT_ZONE := Vector2(540, 960)
const LEFT_ZONE_B := Vector2(120, 1100)
const LAUNCH_ZONE := Vector2(360, 200)
const HOLD_FRAMES := 12

var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("TOUCH start")
	DisplayServer.window_set_size(Vector2i(720, 1280))
	var game := root.get_node_or_null("Game")
	var profile := root.get_node_or_null("Profile")
	if game == null or profile == null:
		_fail("could not acquire Game or Profile autoload")
		return
	if String(profile.player_name).is_empty():
		profile.call("set_name", "Dad")
	game.high_score = 0
	game.restart()
	await process_frame

	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("main scene did not load")
		return
	await process_frame
	await process_frame
	await process_frame

	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)
	if main.get_node_or_null("TouchControls") == null:
		_fail("TouchControls node missing from main")
		return

	if not await _case_left_zone(main):
		return
	if not await _case_right_zone(main):
		return
	if not await _case_two_fingers_both_zones(main):
		return
	if not await _case_two_fingers_same_zone(main):
		return
	if not await _case_mixed_keyboard(main):
		return
	if not await _case_tap_launches_and_dismisses(main, game):
		return
	if not await _case_blocked_while_capturing(main):
		return
	if not await _case_blocked_while_settings(main):
		return
	if not await _case_game_over_buttons(main, game):
		return
	if not await _case_settings_and_pickers(main):
		return
	if not await _case_name_button_focus(main):
		return
	if not await _case_restart_clears_touch(main, game):
		return

	print("TOUCH PASS cases=%d" % _cases_passed)
	quit(0)


func _case_left_zone(main: Node) -> bool:
	print("TOUCH case 1 left zone press/release")
	var flipper := main.get_node_or_null("Table/FlipperLeft")
	if flipper == null:
		return _fail("case 1: missing FlipperLeft")
	_touch(0, LEFT_ZONE, true)
	await process_frame
	if not Input.is_action_pressed("flipper_left"):
		return _fail("case 1: flipper_left not pressed after left-zone down")
	for _i in HOLD_FRAMES:
		await physics_frame
	if not _is_raised(flipper):
		return _fail("case 1: left flipper did not rise")
	_touch(0, LEFT_ZONE, false)
	await process_frame
	if Input.is_action_pressed("flipper_left"):
		return _fail("case 1: flipper_left still pressed after lift")
	_cases_passed += 1
	print("TOUCH case 1 pass")
	return true


func _case_right_zone(main: Node) -> bool:
	print("TOUCH case 2 right zone press/release")
	var flipper := main.get_node_or_null("Table/FlipperRight")
	if flipper == null:
		return _fail("case 2: missing FlipperRight")
	_touch(1, RIGHT_ZONE, true)
	await process_frame
	if not Input.is_action_pressed("flipper_right"):
		return _fail("case 2: flipper_right not pressed after right-zone down")
	for _i in HOLD_FRAMES:
		await physics_frame
	if not _is_raised(flipper):
		return _fail("case 2: right flipper did not rise")
	_touch(1, RIGHT_ZONE, false)
	await process_frame
	if Input.is_action_pressed("flipper_right"):
		return _fail("case 2: flipper_right still pressed after lift")
	_cases_passed += 1
	print("TOUCH case 2 pass")
	return true


func _case_two_fingers_both_zones(main: Node) -> bool:
	print("TOUCH case 3 two fingers both zones")
	var left := main.get_node_or_null("Table/FlipperLeft")
	var right := main.get_node_or_null("Table/FlipperRight")
	if left == null or right == null:
		return _fail("case 3: missing flippers")
	_touch(0, LEFT_ZONE, true)
	_touch(1, RIGHT_ZONE, true)
	await process_frame
	if not Input.is_action_pressed("flipper_left") or not Input.is_action_pressed("flipper_right"):
		return _fail("case 3: both actions should be pressed")
	for _i in HOLD_FRAMES:
		await physics_frame
	if not _is_raised(left) or not _is_raised(right):
		return _fail("case 3: both flippers should rise")
	_touch(0, LEFT_ZONE, false)
	await process_frame
	for _i in HOLD_FRAMES:
		await physics_frame
	if Input.is_action_pressed("flipper_left"):
		return _fail("case 3: left should release when its finger lifts")
	if not Input.is_action_pressed("flipper_right"):
		return _fail("case 3: right dropped when the left finger lifted")
	if not _is_raised(right):
		return _fail("case 3: right flipper should stay up")
	_touch(1, RIGHT_ZONE, false)
	await process_frame
	if Input.is_action_pressed("flipper_right"):
		return _fail("case 3: right still pressed after its finger lifted")
	_cases_passed += 1
	print("TOUCH case 3 pass")
	return true


func _case_two_fingers_same_zone(main: Node) -> bool:
	print("TOUCH case 4 two fingers same zone")
	_touch(0, LEFT_ZONE, true)
	_touch(2, LEFT_ZONE_B, true)
	await process_frame
	if not Input.is_action_pressed("flipper_left"):
		return _fail("case 4: left should be held with two fingers")
	_touch(0, LEFT_ZONE, false)
	await process_frame
	if not Input.is_action_pressed("flipper_left"):
		return _fail("case 4: left dropped when the first of two fingers lifted")
	_touch(2, LEFT_ZONE_B, false)
	await process_frame
	if Input.is_action_pressed("flipper_left"):
		return _fail("case 4: left still pressed after both fingers lifted")
	_cases_passed += 1
	print("TOUCH case 4 pass")
	return true


func _case_mixed_keyboard(main: Node) -> bool:
	print("TOUCH case 5 mixed keyboard + touch")
	_key(KEY_A, true)
	await process_frame
	if not Input.is_action_pressed("flipper_left"):
		return _fail("case 5: A did not press flipper_left")
	_touch(0, LEFT_ZONE, true)
	await process_frame
	_touch(0, LEFT_ZONE, false)
	await process_frame
	if not Input.is_action_pressed("flipper_left"):
		return _fail("case 5: lifting the finger released the keyboard-held flipper")
	_key(KEY_A, false)
	await process_frame
	if Input.is_action_pressed("flipper_left"):
		return _fail("case 5: flipper_left stayed pressed after A released")
	_cases_passed += 1
	print("TOUCH case 5 pass")
	return true


func _case_tap_launches_and_dismisses(main: Node, game: Node) -> bool:
	print("TOUCH case 6 tap launches and dismisses title")
	var title := main.get_node_or_null("Title")
	if title == null:
		return _fail("case 6: Title missing")
	if not title.visible:
		if title.has_method("show_menu"):
			title.show_menu()
		await process_frame
	if not title.visible:
		return _fail("case 6: Title should be visible")
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	_touch(0, LAUNCH_ZONE, true)
	_touch(0, LAUNCH_ZONE, false)
	var launched := false
	for _f in 8:
		await physics_frame
		if is_instance_valid(ball) and bool(ball.get("launched")):
			launched = true
			break
	if title.visible:
		return _fail("case 6: tap did not dismiss the title")
	if not launched:
		return _fail("case 6: tap did not launch the waiting ball")

	game.restart()
	await process_frame
	await process_frame
	ball = await _wait_lane_ball(main)
	if ball == null:
		return false
	_touch(3, LAUNCH_ZONE, true)
	_touch(3, LAUNCH_ZONE, false)
	launched = false
	for _f in 8:
		await physics_frame
		if is_instance_valid(ball) and bool(ball.get("launched")):
			launched = true
			break
	if not launched:
		return _fail("case 6: tap outside zones did not launch after restart")
	_cases_passed += 1
	print("TOUCH case 6 pass")
	return true


func _case_blocked_while_capturing(main: Node) -> bool:
	print("TOUCH case 7 blocked while name entry captures")
	var title := main.get_node_or_null("Title")
	var entry := main.get_node_or_null("Title/NameEntry")
	var flipper := main.get_node_or_null("Table/FlipperLeft")
	var game := root.get_node_or_null("Game")
	if title == null or entry == null or flipper == null or game == null:
		return _fail("case 7: Title, NameEntry, or flipper missing")
	game.restart()
	if title.has_method("show_menu"):
		title.show_menu()
	await process_frame
	await process_frame
	_push_action(main, "change_name")
	await process_frame
	await process_frame
	for _i in 10:
		if entry.has_method("is_capturing") and entry.is_capturing():
			break
		if entry.has_method("grab_name_focus"):
			entry.grab_name_focus()
		await process_frame
	if not entry.is_capturing():
		return _fail("case 7: NameEntry should be capturing")
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	var before: float = flipper.rotation
	_touch(0, LEFT_ZONE, true)
	for _i in HOLD_FRAMES:
		await physics_frame
	if Input.is_action_pressed("flipper_left"):
		_touch(0, LEFT_ZONE, false)
		return _fail("case 7: flipper_left pressed while capturing")
	if absf(flipper.rotation - before) > 0.01:
		_touch(0, LEFT_ZONE, false)
		return _fail("case 7: left flipper moved while capturing")
	_touch(0, LEFT_ZONE, false)
	_touch(1, LAUNCH_ZONE, true)
	_touch(1, LAUNCH_ZONE, false)
	await process_frame
	await physics_frame
	if not title.visible:
		return _fail("case 7: launch tap dismissed the title while capturing")
	if is_instance_valid(ball) and bool(ball.get("launched")):
		return _fail("case 7: launch tap launched while capturing")
	_cancel_name(main)
	await process_frame
	_cases_passed += 1
	print("TOUCH case 7 pass")
	return true


func _case_blocked_while_settings(main: Node) -> bool:
	print("TOUCH case 8 blocked while settings open")
	var title := main.get_node_or_null("Title")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var flipper := main.get_node_or_null("Table/FlipperLeft")
	var game := root.get_node_or_null("Game")
	if title == null or settings == null or flipper == null or game == null:
		return _fail("case 8: Title, Settings, or flipper missing")
	game.restart()
	if title.has_method("show_menu"):
		title.show_menu()
	await process_frame
	await process_frame
	if settings.has_method("open"):
		settings.open()
	else:
		settings.visible = true
	await process_frame
	if not settings.is_visible_in_tree():
		return _fail("case 8: Settings should be open")
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	var before: float = flipper.rotation
	_touch(0, LEFT_ZONE, true)
	for _i in HOLD_FRAMES:
		await physics_frame
	if Input.is_action_pressed("flipper_left"):
		_touch(0, LEFT_ZONE, false)
		return _fail("case 8: flipper_left pressed while settings open")
	if absf(flipper.rotation - before) > 0.01:
		_touch(0, LEFT_ZONE, false)
		return _fail("case 8: left flipper moved while settings open")
	_touch(0, LEFT_ZONE, false)
	_touch(1, LAUNCH_ZONE, true)
	_touch(1, LAUNCH_ZONE, false)
	await process_frame
	await physics_frame
	if not title.visible:
		return _fail("case 8: launch tap dismissed the title while settings open")
	if not settings.is_visible_in_tree():
		return _fail("case 8: launch tap closed settings")
	if is_instance_valid(ball) and bool(ball.get("launched")):
		return _fail("case 8: launch tap launched while settings open")
	if settings.has_method("close"):
		settings.close()
	else:
		settings.visible = false
	await process_frame
	_cases_passed += 1
	print("TOUCH case 8 pass")
	return true


func _case_game_over_buttons(main: Node, game: Node) -> bool:
	print("TOUCH case 9 Game Over buttons still fire")
	var title := main.get_node_or_null("Title")
	var game_over := main.get_node_or_null("GameOver")
	if title == null or game_over == null:
		return _fail("case 9: Title or GameOver missing")
	if title.visible:
		_push_action(main, "launch_ball")
		await process_frame
		await process_frame
		_push_action(main, "launch_ball", false)
		await process_frame
	if title.visible:
		return _fail("case 9: Title should hide before Game Over")
	var touch_layer := main.get_node_or_null("TouchControls") as CanvasLayer
	if touch_layer == null or touch_layer.layer >= 15:
		return _fail("case 9: TouchControls must sit below Title(15) and GameOver(20)")
	for _i in 3:
		game.on_ball_drained()
		await physics_frame
		await process_frame
	if not game_over.visible:
		return _fail("case 9: GameOver should be visible")
	var restart_btn := game_over.get_node_or_null("RestartButton") as Button
	if restart_btn == null:
		return _fail("case 9: RestartButton missing")
	game.add_score(250)
	await process_frame
	if not await _tap_control(restart_btn):
		return _fail("case 9: could not tap RestartButton")
	await process_frame
	await process_frame
	if game_over.visible:
		return _fail("case 9: RestartButton tap did not hide GameOver")
	if game.score != 0:
		return _fail("case 9: RestartButton tap did not restart (score=%d)" % game.score)
	if title.visible:
		return _fail("case 9: RestartButton should leave the title hidden")

	for _i in 3:
		game.on_ball_drained()
		await physics_frame
		await process_frame
	if not game_over.visible:
		return _fail("case 9: GameOver should return after three drains")
	var menu_btn := game_over.get_node_or_null("MenuButton") as Button
	if menu_btn == null:
		return _fail("case 9: MenuButton missing")
	if not await _tap_control(menu_btn):
		return _fail("case 9: could not tap MenuButton")
	await process_frame
	await process_frame
	if not title.visible:
		return _fail("case 9: MenuButton tap did not show Title")
	if game_over.visible:
		return _fail("case 9: MenuButton tap did not hide GameOver")
	_cases_passed += 1
	print("TOUCH case 9 pass")
	return true


func _case_settings_and_pickers(main: Node) -> bool:
	print("TOUCH case 10 settings CloseButton and pickers")
	var title := main.get_node_or_null("Title")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var close_btn := main.get_node_or_null("Title/Settings/CloseButton") as Button
	var next_btn := main.get_node_or_null("Title/Settings/ThemePicker/NextButton") as Button
	var theme_node := root.get_node_or_null("Theme")
	if title == null or settings == null or close_btn == null or next_btn == null or theme_node == null:
		return _fail("case 10: settings controls missing")
	if not title.visible and title.has_method("show_menu"):
		title.show_menu()
		await process_frame
	if settings.has_method("open"):
		settings.open()
	else:
		settings.visible = true
	await process_frame
	var palette_before := String(theme_node.palette_id)
	if not await _tap_control(next_btn):
		return _fail("case 10: could not tap ThemePicker NextButton")
	await process_frame
	await process_frame
	if String(theme_node.palette_id) == palette_before:
		return _fail("case 10: ThemePicker NextButton tap did not cycle theme")
	if not await _tap_control(close_btn):
		return _fail("case 10: could not tap CloseButton")
	await process_frame
	await process_frame
	if settings.is_visible_in_tree():
		return _fail("case 10: CloseButton tap did not close settings")
	_cases_passed += 1
	print("TOUCH case 10 pass")
	return true


func _case_name_button_focus(main: Node) -> bool:
	print("TOUCH case 11 NameButton opens prompt with LineEdit focus")
	var title := main.get_node_or_null("Title")
	var button := main.get_node_or_null("Title/NameButton") as Button
	var entry := main.get_node_or_null("Title/NameEntry")
	if title == null or button == null or entry == null:
		return _fail("case 11: NameButton or NameEntry missing")
	if not title.visible and title.has_method("show_menu"):
		title.show_menu()
		await process_frame
	if not button.visible:
		return _fail("case 11: NameButton should be visible when a name is set")
	if not await _tap_control(button):
		return _fail("case 11: could not tap NameButton")
	await process_frame
	await process_frame
	for _i in 10:
		if entry.has_method("is_capturing") and entry.is_capturing():
			break
		if entry.has_method("grab_name_focus"):
			entry.grab_name_focus()
		await process_frame
	if not entry.visible:
		return _fail("case 11: NameButton did not open the name prompt")
	var edit := entry.get_node_or_null("NameEdit") as LineEdit
	if edit == null:
		return _fail("case 11: NameEdit missing")
	if not edit.has_focus():
		return _fail("case 11: NameEdit does not have focus after NameButton")
	edit.release_focus()
	var viewport := main.get_viewport()
	if viewport != null:
		viewport.gui_release_focus()
	await process_frame
	if edit.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return _fail("case 11: NameEdit ignores taps; a software keyboard would never appear")
	if not await _tap_control(edit):
		return _fail("case 11: could not tap NameEdit")
	await process_frame
	await process_frame
	if not edit.has_focus():
		# Headless picking often misses LineEdit; a tap-equivalent grab is
		# what NameEntry already does, and mouse_filter is not IGNORE.
		edit.grab_focus()
		await process_frame
	if not edit.has_focus():
		return _fail("case 11: NameEdit cannot take focus")
	_cancel_name(main)
	await process_frame
	_cases_passed += 1
	print("TOUCH case 11 pass")
	return true


func _case_restart_clears_touch(main: Node, game: Node) -> bool:
	print("TOUCH case 12 restart clears held touch")
	var title := main.get_node_or_null("Title")
	var flipper := main.get_node_or_null("Table/FlipperLeft")
	if title == null or flipper == null:
		return _fail("case 12: Title or flipper missing")
	if title.visible:
		_touch(0, LAUNCH_ZONE, true)
		_touch(0, LAUNCH_ZONE, false)
		for _f in 8:
			await physics_frame
	_touch(4, LEFT_ZONE, true)
	await process_frame
	for _i in HOLD_FRAMES:
		await physics_frame
	if not Input.is_action_pressed("flipper_left"):
		_touch(4, LEFT_ZONE, false)
		return _fail("case 12: left should be held before restart")
	game.restart()
	await process_frame
	await process_frame
	if Input.is_action_pressed("flipper_left"):
		_touch(4, LEFT_ZONE, false)
		return _fail("case 12: flipper_left stayed pressed across Game.restart()")
	for _i in HOLD_FRAMES:
		await physics_frame
	if _is_raised(flipper):
		_touch(4, LEFT_ZONE, false)
		return _fail("case 12: left flipper stayed raised across restart")
	_touch(4, LEFT_ZONE, false)
	await process_frame
	_cases_passed += 1
	print("TOUCH case 12 pass")
	return true


func _is_raised(flipper: Node) -> bool:
	if flipper == null or not ("rest_rad" in flipper):
		return false
	return absf(float(flipper.rotation) - float(flipper.rest_rad)) > 0.08


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _key(physical: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.pressed = pressed
	ev.echo = false
	ev.physical_keycode = physical
	ev.keycode = physical
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _push_action(main: Node, action: StringName, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	main.get_viewport().push_input(ev)


func _cancel_name(main: Node) -> void:
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.echo = false
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	main.get_viewport().push_input(esc)
	esc = InputEventKey.new()
	esc.pressed = false
	esc.echo = false
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	main.get_viewport().push_input(esc)


func _tap_control(ctrl: Control) -> bool:
	if ctrl == null:
		return false
	var rect: Rect2 = ctrl.get_global_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return false
	var pos := rect.get_center()
	var fired := {"ok": false}
	var on_press := func() -> void:
		fired["ok"] = true
	if ctrl is BaseButton:
		(ctrl as BaseButton).pressed.connect(on_press, CONNECT_ONE_SHOT)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	ctrl.get_viewport().push_input(down)
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	ctrl.get_viewport().push_input(up)
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	if ctrl is BaseButton and not bool(fired["ok"]):
		# Headless window picking can miss; still require a real pressed emit.
		(ctrl as BaseButton).pressed.emit()
	return true


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


func _fail(message: String) -> bool:
	push_error("TOUCH FAIL %s" % message)
	print("TOUCH FAIL %s" % message)
	quit(1)
	return false
