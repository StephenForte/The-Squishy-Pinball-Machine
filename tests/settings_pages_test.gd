extends SceneTree

## D-052 pages, after D-053 removed transfer. Settings still opens, pages and
## closes. The phone page is the app icon. There is no transfer field, so the
## keyboard-line rule is checked on the controls that remain: every one of
## them sits above y=640.

const VIEWPORT := Rect2(0, 0, 720, 1280)
const KEYBOARD_TOP := 640.0

var _cases_passed: int = 0
var _profile: Node
var _leaderboard: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("SETTINGS_PAGES start")
	_profile = root.get_node_or_null("Profile")
	_leaderboard = root.get_node_or_null("Leaderboard")
	if _profile == null or _leaderboard == null:
		_fail("Profile or Leaderboard autoload missing")
		return
	if String(_profile.player_name).is_empty():
		_profile.call("set_name", "Dad")
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load main.tscn")
		return
	for _i in 5:
		await process_frame

	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)

	if not await _case_pages(main):
		return
	if not await _case_geometry(main):
		return
	if not await _case_keyboard(main):
		return
	if not await _case_reopen(main):
		return
	if not await _case_icon_still_works(main):
		return
	if not await _case_close_does_not_adopt(main):
		return

	print("SETTINGS_PAGES PASS cases=%d" % _cases_passed)
	quit(0)


func _case_pages(main: Node) -> bool:
	print("SETTINGS_PAGES case 1 pages")
	var settings := _settings(main)
	if settings == null:
		return _fail("case 1: Settings missing")
	if settings.is_visible_in_tree():
		return _fail("case 1: Settings opened itself")
	if settings.has_method("page_search") or settings.has_method("offer_restore_from_search") or settings.has_method("use_clipboard_stand_in"):
		return _fail("case 1: transfer API is still on Settings")
	if not _transfer_gone(settings):
		return _fail("case 1: transfer nodes are still in the scene")
	settings.open()
	await process_frame
	if String(settings.current_page()) != "look":
		return _fail("case 1: open should land on look, got %s" % settings.current_page())
	if not _section_visible(settings, "AvatarPicker") or not _section_visible(settings, "ThemePicker"):
		return _fail("case 1: look page should show avatar and theme")
	if _section_visible(settings, "IconPicker"):
		return _fail("case 1: phone controls visible on the look page")
	var device := settings.get_node_or_null("DeviceButton") as Button
	var look := settings.get_node_or_null("LookButton") as Button
	if device == null or look == null:
		return _fail("case 1: page buttons missing")
	if not _in_view(device) or not _in_view(look):
		return _fail("case 1: page buttons outside the viewport")
	if device.size.y < 96.0 or look.size.y < 96.0:
		return _fail("case 1: page buttons shorter than a finger")
	device.pressed.emit()
	await process_frame
	if String(settings.current_page()) != "device":
		return _fail("case 1: DeviceButton did not open the phone page")
	if not _section_visible(settings, "IconPicker"):
		return _fail("case 1: phone page missing the app icon")
	if _section_visible(settings, "AvatarPicker") or _section_visible(settings, "ThemePicker"):
		return _fail("case 1: look controls visible on the phone page")
	if not look.visible or not _in_view(look):
		return _fail("case 1: My look is not reachable from the phone page")
	look.pressed.emit()
	await process_frame
	if String(settings.current_page()) != "look":
		return _fail("case 1: LookButton did not return to look")
	if not device.visible or not _in_view(device):
		return _fail("case 1: This phone is not reachable from the look page")
	_cases_passed += 1
	print("SETTINGS_PAGES case 1 pass")
	return true


func _case_geometry(main: Node) -> bool:
	print("SETTINGS_PAGES case 2 geometry")
	var settings := _settings(main)
	if settings == null:
		return _fail("case 2: Settings missing")
	for page in ["look", "device"]:
		settings.show_page(page)
		await process_frame
		await process_frame
		var controls := _interactives(settings)
		if controls.is_empty():
			return _fail("case 2: %s page has no interactive controls" % page)
		for i in controls.size():
			var a := controls[i]
			var a_rect := a.get_global_rect()
			if a_rect.size.x <= 1.0 or a_rect.size.y <= 1.0:
				return _fail("case 2: %s/%s has an empty rect %s" % [page, a.name, a_rect])
			if not VIEWPORT.encloses(a_rect):
				return _fail("case 2: %s/%s outside viewport %s" % [page, a.name, a_rect])
			for j in range(i + 1, controls.size()):
				var b := controls[j]
				var b_rect := b.get_global_rect()
				if a_rect.intersects(b_rect):
					return _fail("case 2: %s overlap %s %s vs %s %s" % [page, a.name, a_rect, b.name, b_rect])
	_cases_passed += 1
	print("SETTINGS_PAGES case 2 pass")
	return true


func _case_keyboard(main: Node) -> bool:
	print("SETTINGS_PAGES case 3 keyboard line")
	var settings := _settings(main)
	if settings == null:
		return _fail("case 3: Settings missing")
	if not _transfer_gone(settings):
		return _fail("case 3: transfer nodes returned")
	for page in ["look", "device"]:
		settings.show_page(page)
		await process_frame
		if not _line_edits(settings).is_empty():
			return _fail("case 3: %s page still has a text field" % page)
	settings.show_page("device")
	await process_frame
	var controls := _interactives(settings)
	if controls.is_empty():
		return _fail("case 3: phone page has no controls")
	for ctrl in controls:
		var rect := ctrl.get_global_rect()
		if rect.end.y > KEYBOARD_TOP:
			return _fail("case 3: device/%s %s is not entirely above y=640" % [ctrl.name, rect])
		if not VIEWPORT.encloses(rect):
			return _fail("case 3: device/%s outside the viewport %s" % [ctrl.name, rect])
	var close := settings.get_node_or_null("CloseButton") as Button
	if close == null or not close.visible:
		return _fail("case 3: CloseButton missing")
	if close.get_global_rect().end.y > KEYBOARD_TOP:
		return _fail("case 3: Close %s is under the keyboard line" % close.get_global_rect())
	_cases_passed += 1
	print("SETTINGS_PAGES case 3 pass")
	return true


func _case_reopen(main: Node) -> bool:
	print("SETTINGS_PAGES case 4 close and reopen")
	var settings := _settings(main)
	if settings == null:
		return _fail("case 4: Settings missing")
	var id_before := String(_profile.player_id)
	var name_before := String(_profile.player_name)
	settings.show_page("device")
	await process_frame
	if not _section_visible(settings, "IconPicker"):
		return _fail("case 4: icon missing before close")
	settings.close()
	await process_frame
	if settings.is_visible_in_tree():
		return _fail("case 4: close left Settings open")
	settings.open()
	await process_frame
	if not settings.is_visible_in_tree():
		return _fail("case 4: reopen did not show Settings")
	if String(settings.current_page()) != "look":
		return _fail("case 4: reopen landed on %s" % settings.current_page())
	if not _section_visible(settings, "AvatarPicker") or _section_visible(settings, "IconPicker"):
		return _fail("case 4: reopen did not restore the look page")
	if not _transfer_gone(settings):
		return _fail("case 4: transfer nodes appeared after reopen")
	if String(_profile.player_id) != id_before or String(_profile.player_name) != name_before:
		return _fail("case 4: paging changed identity")
	_cases_passed += 1
	print("SETTINGS_PAGES case 4 pass")
	return true


func _case_icon_still_works(main: Node) -> bool:
	print("SETTINGS_PAGES case 5 app icon still pages")
	var settings := _settings(main)
	if settings == null:
		return _fail("case 5: Settings missing")
	settings.show_page("device")
	await process_frame
	var prev := settings.get_node_or_null("IconPicker/PrevButton") as Button
	var next := settings.get_node_or_null("IconPicker/NextButton") as Button
	var label := settings.get_node_or_null("IconPicker/NameLabel") as Label
	if prev == null or next == null or label == null:
		return _fail("case 5: icon controls missing")
	if not prev.visible or not next.visible:
		return _fail("case 5: icon buttons hidden")
	var prev_rect := prev.get_global_rect()
	var next_rect := next.get_global_rect()
	if prev_rect.intersects(next_rect):
		return _fail("case 5: icon buttons overlap")
	if prev_rect.end.y > KEYBOARD_TOP or next_rect.end.y > KEYBOARD_TOP:
		return _fail("case 5: icon buttons sit under y=640")
	var before := label.text
	var id_before := String(_profile.player_id)
	next.pressed.emit()
	await process_frame
	if label.text == before:
		return _fail("case 5: Next did not change the icon name")
	prev.pressed.emit()
	await process_frame
	if label.text != before:
		return _fail("case 5: Prev did not restore '%s', got '%s'" % [before, label.text])
	if String(_profile.player_id) != id_before:
		return _fail("case 5: icon change adopted a player")
	_cases_passed += 1
	print("SETTINGS_PAGES case 5 pass")
	return true


func _case_close_does_not_adopt(main: Node) -> bool:
	print("SETTINGS_PAGES case 6 close leaves identity")
	var settings := _settings(main)
	if settings == null:
		return _fail("case 6: Settings missing")
	if not _leaderboard.has_method("resolve_name") or not _leaderboard.has_method("retire_name_resolve"):
		return _fail("case 6: resolve API missing")
	var id_before := String(_profile.player_id)
	var name_before := String(_profile.player_name)
	var players_before := JSON.stringify(_profile.players)
	settings.show_page("device")
	await process_frame
	var close := settings.get_node_or_null("CloseButton") as Button
	if close == null:
		return _fail("case 6: CloseButton missing")
	close.pressed.emit()
	await process_frame
	if settings.is_visible_in_tree():
		return _fail("case 6: Close did not hide Settings")
	if String(_profile.player_id) != id_before or String(_profile.player_name) != name_before:
		return _fail("case 6: Close changed identity")
	if JSON.stringify(_profile.players) != players_before:
		return _fail("case 6: Close changed the players map")
	if not _transfer_gone(settings):
		return _fail("case 6: transfer nodes present at close")
	_cases_passed += 1
	print("SETTINGS_PAGES case 6 pass")
	return true


func _transfer_gone(settings: Node) -> bool:
	for node_name in ["ThisDevice", "RestoreProfile", "LinkRestore"]:
		if settings.get_node_or_null(node_name) != null:
			return false
	return true



func _settings(main: Node) -> Control:
	return main.get_node_or_null("Title/Settings") as Control


func _section_visible(settings: Control, node_name: String) -> bool:
	var section := settings.get_node_or_null(node_name) as Control
	return section != null and section.visible and section.is_visible_in_tree()


func _in_view(ctrl: Control) -> bool:
	return VIEWPORT.encloses(ctrl.get_global_rect())


func _interactives(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	_walk_interactives(node, out)
	return out


func _walk_interactives(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Button or child is LineEdit:
			var ctrl := child as Control
			if ctrl.visible and ctrl.is_visible_in_tree():
				out.append(ctrl)
		_walk_interactives(child, out)


func _line_edits(node: Node) -> Array[LineEdit]:
	var out: Array[LineEdit] = []
	_walk_edits(node, out)
	return out


func _walk_edits(node: Node, out: Array[LineEdit]) -> void:
	for child in node.get_children():
		if child is LineEdit:
			var edit := child as LineEdit
			if edit.visible and edit.is_visible_in_tree():
				out.append(edit)
		_walk_edits(child, out)


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _fail(message: String) -> bool:
	push_error("SETTINGS_PAGES FAIL %s" % message)
	print("SETTINGS_PAGES FAIL %s" % message)
	quit(1)
	return false
