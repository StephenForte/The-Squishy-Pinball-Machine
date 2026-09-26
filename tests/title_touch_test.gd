extends SceneTree

## D-049. Fresh device: empty name must not lock the title.
## A launch while the name field is actually focused must still be swallowed.

const DESKTOP_CONTROLS := "A / ←   Left flipper\nD / →   Right flipper\nSpace   Launch\nR       Restart\nEsc     Menu"
## 64 CSS px at the 375-wide phone the planner reproduced, mapped onto the
## 720-wide viewport (uniform canvas scale).
const MIN_PLAY_PX := 64.0 * 720.0 / 375.0
## settings_test case 6: visible Title controls must not pass y=1150.
const TITLE_FLOOR := 1150.0

var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("TITLE_TOUCH start")
	DisplayServer.window_set_size(Vector2i(720, 1280))
	var profile := root.get_node_or_null("Profile")
	if profile == null:
		_fail("Profile autoload missing")
		return
	_reset_profile(profile)
	if String(profile.player_name) != "":
		_fail("fresh profile name should be empty, got '%s'" % profile.player_name)
		return

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("could not load main.tscn")
		return
	if change_scene_to_packed(packed) != OK:
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

	var title := main.get_node_or_null("Title")
	if title == null:
		_fail("Title missing")
		return
	if String(profile.player_name) != "":
		_fail("profile name changed while loading, got '%s'" % profile.player_name)
		return

	if not await _case_desktop_hints(title):
		return
	if not await _case_launch_with_empty_name(main, title):
		return
	if not await _case_settings_with_empty_name(main, title):
		return
	if not await _case_play_button(main, title):
		return
	if not await _case_launch_blocked_while_capturing(main, title):
		return

	print("TITLE_TOUCH PASS cases=%d" % _cases_passed)
	quit(0)


func _case_desktop_hints(title: Node) -> bool:
	print("TITLE_TOUCH case 1 desktop control hints")
	var label := title.get_node_or_null("ControlsLabel") as Label
	if label == null:
		return _fail("case 1: ControlsLabel missing")
	var touch := DisplayServer.is_touchscreen_available()
	print("TITLE_TOUCH case 1 touchscreen=%s" % touch)
	if touch:
		if label.text == DESKTOP_CONTROLS:
			return _fail("case 1: touch device still shows keyboard hints")
		if not label.text.contains("Tap the table"):
			return _fail("case 1: touch hints missing, got '%s'" % label.text)
	else:
		if label.text != DESKTOP_CONTROLS:
			return _fail("case 1: desktop hints changed to '%s'" % label.text)
	_cases_passed += 1
	print("TITLE_TOUCH case 1 pass")
	return true


func _case_launch_with_empty_name(main: Node, title: Node) -> bool:
	print("TITLE_TOUCH case 2 empty name launch dismisses")
	if not title.visible:
		return _fail("case 2: Title should start visible")
	if not await _release_name_capture(title):
		return _fail("case 2: could not leave the name field")
	if _name_is_capturing(title):
		return _fail("case 2: name field still capturing")
	var profile := root.get_node_or_null("Profile")
	if profile == null or String(profile.player_name) != "":
		return _fail("case 2: name was not empty")
	_push_action(main, "launch_ball")
	await process_frame
	await process_frame
	_push_action(main, "launch_ball", false)
	if title.visible:
		return _fail("case 2: launch_ball left the title up with an empty name")
	_cases_passed += 1
	print("TITLE_TOUCH case 2 pass")
	return true


func _case_settings_with_empty_name(main: Node, title: Node) -> bool:
	print("TITLE_TOUCH case 3 settings opens while name field is focused")
	if title.has_method("show_menu"):
		title.show_menu()
	await process_frame
	await process_frame
	if not title.visible:
		return _fail("case 3: Title should be visible")
	if not await _wait_capturing(title):
		return _fail("case 3: name field did not capture on an empty name")
	var button := title.get_node_or_null("SettingsButton") as Button
	var settings := title.get_node_or_null("Settings")
	if button == null or settings == null:
		return _fail("case 3: SettingsButton or Settings missing")
	button.pressed.emit()
	await process_frame
	var open := false
	if settings.has_method("is_open"):
		open = bool(settings.is_open())
	else:
		open = settings.visible
	if not open:
		return _fail("case 3: Settings button did not open the overlay while the name field was focused")
	if settings.has_method("close"):
		settings.close()
	await process_frame
	_cases_passed += 1
	print("TITLE_TOUCH case 3 pass")
	return true


func _case_play_button(main: Node, title: Node) -> bool:
	print("TITLE_TOUCH case 4 Play button")
	if title.has_method("show_menu"):
		title.show_menu()
	await process_frame
	await process_frame
	if not await _wait_capturing(title):
		return _fail("case 4: name field did not capture on an empty name")
	var play := title.get_node_or_null("PlayButton") as Button
	if play == null:
		return _fail("case 4: PlayButton missing")
	if not play.visible:
		return _fail("case 4: PlayButton should be visible")
	var rect := play.get_global_rect()
	if rect.size.x < MIN_PLAY_PX or rect.size.y < MIN_PLAY_PX:
		return _fail("case 4: PlayButton %s smaller than %.1f px" % [rect.size, MIN_PLAY_PX])
	if rect.end.y > TITLE_FLOOR:
		return _fail("case 4: PlayButton extends below y=1150: %s" % rect)
	for node_name in ["NameEntry", "SettingsButton", "NameButton"]:
		var other := title.get_node_or_null(node_name) as Control
		if other == null:
			return _fail("case 4: %s missing" % node_name)
		var other_rect := other.get_global_rect()
		if rect.intersects(other_rect):
			return _fail("case 4: PlayButton %s overlaps %s %s" % [rect, node_name, other_rect])
	# Fresh-device state: the name field is focused. Play must still start.
	play.pressed.emit()
	await process_frame
	await process_frame
	if title.visible:
		return _fail("case 4: PlayButton left the title up")
	_cases_passed += 1
	print("TITLE_TOUCH case 4 pass")
	return true


func _case_launch_blocked_while_capturing(main: Node, title: Node) -> bool:
	print("TITLE_TOUCH case 5 launch swallowed while capturing")
	if title.has_method("show_menu"):
		title.show_menu()
	await process_frame
	await process_frame
	if not await _wait_capturing(title):
		return _fail("case 5: name field did not capture")
	if not title.visible:
		return _fail("case 5: Title should be visible")
	_push_action(main, "launch_ball")
	await process_frame
	await process_frame
	_push_action(main, "launch_ball", false)
	if not title.visible:
		return _fail("case 5: launch_ball dismissed the title while the name field was focused")
	if not _name_is_capturing(title):
		return _fail("case 5: name field lost capture")
	_cases_passed += 1
	print("TITLE_TOUCH case 5 pass")
	return true


func _reset_profile(profile: Node) -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("profile.save"):
		dir.remove("profile.save")
	if profile.has_method("_load_or_create"):
		profile.call("_load_or_create")


func _release_name_capture(title: Node) -> bool:
	var entry := title.get_node_or_null("NameEntry")
	if entry == null:
		return false
	for _i in 10:
		if entry.has_method("is_capturing") and entry.is_capturing():
			break
		if entry.has_method("grab_name_focus"):
			entry.call("grab_name_focus")
		await process_frame
	if entry.has_method("release_name_focus"):
		entry.call("release_name_focus")
	await process_frame
	await process_frame
	return true


func _wait_capturing(title: Node) -> bool:
	var entry := title.get_node_or_null("NameEntry")
	if entry == null:
		return false
	for _i in 10:
		if entry.has_method("is_capturing") and entry.is_capturing():
			return true
		if entry.has_method("grab_name_focus"):
			entry.call("grab_name_focus")
		await process_frame
	return entry.has_method("is_capturing") and entry.is_capturing()


func _name_is_capturing(title: Node) -> bool:
	if title.has_method("is_capturing_name") and title.is_capturing_name():
		return true
	var entry := title.get_node_or_null("NameEntry")
	return entry != null and entry.has_method("is_capturing") and entry.is_capturing()


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
	push_error("TITLE_TOUCH FAIL %s" % message)
	print("TITLE_TOUCH FAIL %s" % message)
	quit(1)
	return false
