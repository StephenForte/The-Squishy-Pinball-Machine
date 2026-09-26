extends SceneTree

## D-052. Settings is two pages. A transfer code is pasted or confirmed from
## a link; it is never adopted just because the URL carried it.

const VIEWPORT := Rect2(0, 0, 720, 1280)
const KEYBOARD_TOP := 640.0
const VISIBLE_BAND := Rect2(0, 0, 720, KEYBOARD_TOP)
const VALID_ID := "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"

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
	if not await _case_paste(main):
		return
	if not await _case_link(main):
		return
	if not await _case_dismiss_cancels_inflight(main):
		return

	print("SETTINGS_PAGES PASS cases=%d" % _cases_passed)
	quit(0)


func _case_pages(main: Node) -> bool:
	print("SETTINGS_PAGES case 1 pages")
	var settings := _settings(main)
	if settings == null:
		return _fail("case 1: Settings missing")
	if settings.is_visible_in_tree():
		return _fail("case 1: Settings opened itself with no link")
	if String(settings.page_search()) != "":
		return _fail("case 1: non-web page_search returned '%s'" % settings.page_search())
	settings.open()
	await process_frame
	if String(settings.current_page()) != "look":
		return _fail("case 1: open should land on look, got %s" % settings.current_page())
	if not _section_visible(settings, "AvatarPicker") or not _section_visible(settings, "ThemePicker"):
		return _fail("case 1: look page should show avatar and theme")
	if _section_visible(settings, "IconPicker") or _section_visible(settings, "RestoreProfile"):
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
	if not _section_visible(settings, "IconPicker") or not _section_visible(settings, "RestoreProfile"):
		return _fail("case 1: phone page missing icon or restore")
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
	settings.show_page("device")
	await process_frame
	var edits := _line_edits(settings)
	if edits.is_empty():
		return _fail("case 3: phone page has no text field")
	var close := settings.get_node_or_null("CloseButton") as Button
	if close == null:
		return _fail("case 3: CloseButton missing")
	for edit in edits:
		edit.grab_focus()
		await process_frame
		if not edit.has_focus():
			return _fail("case 3: %s did not take focus" % edit.name)
		var rect := edit.get_global_rect()
		if not VISIBLE_BAND.encloses(rect):
			return _fail("case 3: focused %s %s is not entirely above y=640" % [edit.name, rect])
		var close_rect := close.get_global_rect()
		if not close.visible or not VISIBLE_BAND.encloses(close_rect):
			return _fail("case 3: Close %s is not above the keyboard while %s is focused" % [close_rect, edit.name])
		edit.release_focus()
	var paste := settings.get_node_or_null("RestoreProfile/PasteButton") as Button
	var restore := settings.get_node_or_null("RestoreProfile/RestoreButton") as Button
	var field := settings.get_node_or_null("RestoreProfile/CodeEdit") as LineEdit
	if paste == null or restore == null or field == null:
		return _fail("case 3: paste row missing")
	var field_rect := field.get_global_rect()
	var paste_rect := paste.get_global_rect()
	if paste_rect.position.y < field_rect.end.y:
		return _fail("case 3: Paste overlaps the field")
	if paste_rect.position.y - field_rect.end.y > 16.0:
		return _fail("case 3: Paste is not next to the field %s vs %s" % [paste_rect, field_rect])
	if not VISIBLE_BAND.encloses(paste_rect) or not VISIBLE_BAND.encloses(restore.get_global_rect()):
		return _fail("case 3: Paste or Restore sits under the keyboard")
	_cases_passed += 1
	print("SETTINGS_PAGES case 3 pass")
	return true


func _case_paste(main: Node) -> bool:
	print("SETTINGS_PAGES case 4 paste")
	var settings := _settings(main)
	var edit := settings.get_node_or_null("RestoreProfile/CodeEdit") as LineEdit
	var paste := settings.get_node_or_null("RestoreProfile/PasteButton") as Button
	var status := settings.get_node_or_null("RestoreProfile/StatusLabel") as Label
	if settings == null or edit == null or paste == null or status == null:
		return _fail("case 4: paste nodes missing")
	settings.show_page("device")
	await process_frame
	edit.text = ""
	status.text = "MARKER"
	paste.pressed.emit()
	await process_frame
	if edit.text != "":
		return _fail("case 4: unsupported clipboard wrote '%s'" % edit.text)
	if status.text != "MARKER":
		return _fail("case 4: empty clipboard set status '%s'" % status.text)
	settings.use_clipboard_stand_in(VALID_ID)
	paste.pressed.emit()
	await process_frame
	if edit.text != VALID_ID:
		settings.clear_clipboard_stand_in()
		return _fail("case 4: paste left '%s'" % edit.text)
	if status.text != "MARKER":
		settings.clear_clipboard_stand_in()
		return _fail("case 4: paste rewrote status to '%s'" % status.text)
	settings.use_clipboard_stand_in("   ")
	paste.pressed.emit()
	await process_frame
	if edit.text != VALID_ID:
		settings.clear_clipboard_stand_in()
		return _fail("case 4: empty clipboard cleared the field")
	if status.text != "MARKER":
		settings.clear_clipboard_stand_in()
		return _fail("case 4: empty clipboard set status '%s'" % status.text)
	if status.text == "that code doesn't look right" or status.text == "no profile found":
		settings.clear_clipboard_stand_in()
		return _fail("case 4: empty clipboard reported a restore error")
	settings.clear_clipboard_stand_in()
	_cases_passed += 1
	print("SETTINGS_PAGES case 4 pass")
	return true


func _case_link(main: Node) -> bool:
	print("SETTINGS_PAGES case 5 link restore")
	var settings := _settings(main)
	if settings == null:
		return _fail("case 5: Settings missing")
	var id_before := String(_profile.player_id)
	var gen_before := int(_leaderboard._restore_gen)
	if String(settings.restore_param_from_search("?player_id=%s" % VALID_ID)) != "":
		return _fail("case 5: a different query key was treated as restore")
	if String(settings.restore_param_from_search("https://play.example/?utm=1&restore=%s#top" % VALID_ID)) != VALID_ID:
		return _fail("case 5: full URL did not yield the restore param")
	var padded := "https://play.example/?restore=%s" % VALID_ID.uri_encode()
	if String(settings.restore_param_from_search(padded)) != VALID_ID:
		return _fail("case 5: encoded restore param did not decode")

	settings.offer_restore_from_search("?restore=not-a-uuid")
	await process_frame
	var panel := settings.get_node_or_null("LinkRestore") as Control
	if panel == null:
		return _fail("case 5: LinkRestore missing")
	if panel.visible:
		return _fail("case 5: malformed restore opened the confirm panel")
	if String(_profile.player_id) != id_before or int(_leaderboard._restore_gen) != gen_before:
		return _fail("case 5: malformed restore adopted or called restore_profile")

	settings.offer_restore_from_search("?restore=aaaaaaaa-bbbb-1ccc-8ddd-eeeeeeeeeeee")
	await process_frame
	if panel.visible or String(_profile.player_id) != id_before:
		return _fail("case 5: non-v4 restore was not ignored")

	settings.offer_restore_from_search("?foo=1&restore=%s" % VALID_ID)
	await process_frame
	if not panel.visible or not settings.is_visible_in_tree():
		return _fail("case 5: a valid link did not offer restore")
	var look := settings.get_node_or_null("LookButton") as Button
	var device := settings.get_node_or_null("DeviceButton") as Button
	if look == null or device == null:
		return _fail("case 5: page buttons missing")
	if look.visible or device.visible:
		return _fail("case 5: page buttons stay up over the link confirm")
	var close := settings.get_node_or_null("CloseButton") as Button
	if close == null or not close.visible or not VIEWPORT.encloses(close.get_global_rect()):
		return _fail("case 5: Close is not reachable during the link confirm")
	if close.get_global_rect().intersects(panel.get_global_rect()):
		return _fail("case 5: Close overlaps the link confirm")
	var prompt := settings.get_node_or_null("LinkRestore/Prompt") as Label
	var code := settings.get_node_or_null("LinkRestore/CodeLabel") as Label
	var confirm := settings.get_node_or_null("LinkRestore/ConfirmButton") as Button
	var cancel := settings.get_node_or_null("LinkRestore/CancelButton") as Button
	if prompt == null or code == null or confirm == null or cancel == null:
		return _fail("case 5: confirm controls missing")
	if prompt.text.find("replaces") < 0:
		return _fail("case 5: prompt does not say what restore does")
	if code.text != VALID_ID:
		return _fail("case 5: confirm shows '%s'" % code.text)
	if String(_profile.player_id) != id_before or int(_leaderboard._restore_gen) != gen_before:
		return _fail("case 5: the link adopted before confirm")
	if not VIEWPORT.encloses(confirm.get_global_rect()) or not VIEWPORT.encloses(cancel.get_global_rect()):
		return _fail("case 5: confirm buttons outside the viewport")
	if confirm.get_global_rect().intersects(cancel.get_global_rect()):
		return _fail("case 5: Restore and Not now overlap")

	cancel.pressed.emit()
	await process_frame
	if panel.visible:
		return _fail("case 5: Not now left the panel up")
	if not look.visible or not device.visible:
		return _fail("case 5: Not now did not bring the pages back")
	if String(_profile.player_id) != id_before or int(_leaderboard._restore_gen) != gen_before:
		return _fail("case 5: Not now adopted or called restore_profile")

	settings.offer_restore_from_search("?restore=%s" % VALID_ID)
	await process_frame
	if not panel.visible:
		return _fail("case 5: second offer did not show the panel")
	var gen_at_confirm := int(_leaderboard._restore_gen)
	confirm.pressed.emit()
	await process_frame
	if int(_leaderboard._restore_gen) != gen_at_confirm + 1:
		return _fail("case 5: confirm called restore_profile %d times" % (int(_leaderboard._restore_gen) - gen_at_confirm))
	if String(_profile.player_id) != id_before:
		return _fail("case 5: offline confirm adopted %s" % _profile.player_id)
	var link_status := settings.get_node_or_null("LinkRestore/StatusLabel") as Label
	if link_status == null or link_status.text != "couldn't reach the leaderboard":
		return _fail("case 5: failed confirm status '%s'" % ("" if link_status == null else link_status.text))
	_cases_passed += 1
	print("SETTINGS_PAGES case 5 pass")
	return true


func _case_dismiss_cancels_inflight(main: Node) -> bool:
	print("SETTINGS_PAGES case 6 dismiss cancels in-flight restore")
	var settings := _settings(main)
	if settings == null:
		return _fail("case 6: Settings missing")
	var id_before := String(_profile.player_id)
	if not await _dismiss_drops_late_success(settings, "cancel"):
		return false
	if String(_profile.player_id) != id_before:
		return _fail("case 6: Not now let a late success adopt")
	if not await _dismiss_drops_late_success(settings, "close"):
		return false
	if String(_profile.player_id) != id_before:
		return _fail("case 6: Close let a late success adopt")
	_cases_passed += 1
	print("SETTINGS_PAGES case 6 pass")
	return true


func _dismiss_drops_late_success(settings: Control, how: String) -> bool:
	var id_before := String(_profile.player_id)
	settings.offer_restore_from_search("?restore=%s" % VALID_ID)
	await process_frame
	var panel := settings.get_node_or_null("LinkRestore") as Control
	var cancel := settings.get_node_or_null("LinkRestore/CancelButton") as Button
	if panel == null or not panel.visible or cancel == null:
		return _fail("case 6: %s offer did not show" % how)
	# restore_profile would have captured this generation, then gone async.
	var captured := int(_leaderboard._restore_gen) + 1
	_leaderboard._restore_gen = captured
	settings._restore_busy = true
	if how == "close":
		settings.close()
	else:
		cancel.pressed.emit()
	await process_frame
	if int(_leaderboard._restore_gen) != captured + 1:
		return _fail("case 6: %s did not retire the in-flight generation" % how)
	_leaderboard._on_restore_profile_finished(true, 200, {
		"player_id": VALID_ID,
		"name": "Stolen",
		"avatar": "bear_bounce",
	}, "", captured)
	await process_frame
	if String(_profile.player_id) != id_before or String(_profile.player_name) == "Stolen":
		return _fail("case 6: %s late success adopted %s" % [how, _profile.player_id])
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
