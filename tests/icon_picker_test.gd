extends SceneTree

const CATALOG_PATH := "res://assets/design/icons/app_icons.json"
const VIEWPORT := Rect2(0, 0, 720, 1280)

var _cases_passed: int = 0
var _app_icon: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("ICON_PICKER start")
	_delete_save()
	_app_icon = root.get_node_or_null("AppIcon")
	if _app_icon == null:
		_fail("AppIcon autoload missing")
		return
	var profile := root.get_node_or_null("Profile")
	if profile != null and String(profile.player_name).is_empty():
		profile.call("set_name", "Dad")

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

	if not await _case_1_present(main):
		return
	if not await _case_2_cycle(main):
		return
	if not await _case_3_preview(main):
		return
	if not await _case_4_key(main):
		return
	if not await _case_5_layout(main):
		return

	print("ICON_PICKER PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_present(main: Node) -> bool:
	print("ICON_PICKER case 1 present")
	var title := main.get_node_or_null("Title")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var picker := _icon_picker(main)
	if title == null:
		return _fail("case 1: Title missing")
	if settings == null:
		return _fail("case 1: Title/Settings missing")
	if picker == null:
		return _fail("case 1: Title/Settings/IconPicker missing")
	if not title.visible:
		return _fail("case 1: Title should be visible")
	if picker.is_visible_in_tree():
		return _fail("case 1: IconPicker should stay hidden while Settings is closed")
	settings.visible = true
	await process_frame
	if not picker.visible or not picker.is_visible_in_tree():
		return _fail("case 1: IconPicker should be visible once Settings is open")
	var name_label := picker.get_node_or_null("NameLabel") as Label
	if name_label == null:
		return _fail("case 1: NameLabel missing")
	var expected := String(_app_icon.icon_name(_app_icon.icon_id))
	if name_label.text != expected:
		return _fail("case 1: NameLabel '%s' != '%s'" % [name_label.text, expected])
	_cases_passed += 1
	print("ICON_PICKER case 1 pass")
	return true


func _case_2_cycle(main: Node) -> bool:
	print("ICON_PICKER case 2 cycle")
	var picker := _icon_picker(main)
	var next_btn := picker.get_node_or_null("NextButton") as Button
	var prev_btn := picker.get_node_or_null("PrevButton") as Button
	if next_btn == null or prev_btn == null:
		return _fail("case 2: missing cycle buttons")
	var ids: PackedStringArray = _app_icon.icon_ids()
	if ids.size() < 2:
		return _fail("case 2: catalog too small")
	var start_id := String(_app_icon.icon_id)
	var start_idx := _id_index(ids, start_id)
	if start_idx < 0:
		return _fail("case 2: current id %s not in catalog" % start_id)

	next_btn.pressed.emit()
	await process_frame
	var after_one := String(_app_icon.icon_id)
	var want_next := String(ids[posmod(start_idx + 1, ids.size())])
	if after_one != want_next:
		return _fail("case 2: NextButton -> %s want %s" % [after_one, want_next])

	_app_icon.set_icon(start_id)
	await process_frame
	for _i in 4:
		next_btn.pressed.emit()
		await process_frame
	if String(_app_icon.icon_id) != start_id:
		return _fail("case 2: NextButton ×4 -> %s want %s" % [_app_icon.icon_id, start_id])

	var first_id := String(ids[0])
	var last_id := String(ids[ids.size() - 1])
	_app_icon.set_icon(first_id)
	await process_frame
	prev_btn.pressed.emit()
	await process_frame
	if String(_app_icon.icon_id) != last_id:
		return _fail("case 2: Prev from first -> %s want %s" % [_app_icon.icon_id, last_id])
	_cases_passed += 1
	print("ICON_PICKER case 2 pass")
	return true


func _case_3_preview(main: Node) -> bool:
	print("ICON_PICKER case 3 preview")
	var picker := _icon_picker(main)
	var preview := picker.get_node_or_null("Preview") as TextureRect
	var next_btn := picker.get_node_or_null("NextButton") as Button
	if preview == null or next_btn == null:
		return _fail("case 3: Preview or NextButton missing")
	var ids: PackedStringArray = _app_icon.icon_ids()
	_app_icon.set_icon(String(ids[0]))
	await process_frame
	for _i in ids.size():
		if not _preview_matches(preview, String(_app_icon.icon_id)):
			return false
		next_btn.pressed.emit()
		await process_frame
	if not _preview_matches(preview, String(_app_icon.icon_id)):
		return false
	_cases_passed += 1
	print("ICON_PICKER case 3 pass")
	return true


func _case_4_key(main: Node) -> bool:
	print("ICON_PICKER case 4 key")
	var picker := _icon_picker(main)
	var ids: PackedStringArray = _app_icon.icon_ids()
	var start_id := String(_app_icon.icon_id)
	var start_idx := _id_index(ids, start_id)
	_press_i()
	await process_frame
	await process_frame
	var after_i := String(_app_icon.icon_id)
	var want := String(ids[posmod(start_idx + 1, ids.size())])
	if after_i != want:
		return _fail("case 4: I key -> %s want %s" % [after_i, want])
	if after_i == start_id:
		return _fail("case 4: I key did not advance")

	picker.visible = false
	await process_frame
	var hidden_before := String(_app_icon.icon_id)
	_press_i()
	await process_frame
	await process_frame
	if String(_app_icon.icon_id) != hidden_before:
		return _fail("case 4: I key advanced while IconPicker hidden")
	picker.visible = true
	await process_frame
	_cases_passed += 1
	print("ICON_PICKER case 4 pass")
	return true


func _case_5_layout(main: Node) -> bool:
	print("ICON_PICKER case 5 layout")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var picker := _icon_picker(main) as Control
	if settings == null or picker == null:
		return _fail("case 5: missing Settings or IconPicker")
	settings.visible = true
	await process_frame
	var picker_rect: Rect2 = picker.get_global_rect()
	for child in settings.get_children():
		if child == picker or not (child is Control):
			continue
		var sibling := child as Control
		var sibling_rect: Rect2 = sibling.get_global_rect()
		if picker_rect.intersects(sibling_rect):
			return _fail(
				"case 5: IconPicker intersects Settings/%s %s vs %s"
				% [sibling.name, picker_rect, sibling_rect]
			)
	if not VIEWPORT.encloses(picker_rect):
		return _fail("case 5: IconPicker %s outside viewport %s" % [picker_rect, VIEWPORT])
	_cases_passed += 1
	print("ICON_PICKER case 5 pass")
	return true


func _icon_picker(main: Node) -> Node:
	return main.get_node_or_null("Title/Settings/IconPicker")


func _preview_matches(preview: TextureRect, icon_id: String) -> bool:
	if preview.texture == null:
		return _fail("case 3: Preview.texture is null for %s" % icon_id)
	var got := String(preview.texture.resource_path)
	var want := _catalog_icon_path(icon_id)
	if got != want:
		return _fail("case 3: Preview path %s want %s" % [got, want])
	return true


func _catalog_icon_path(id: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	for entry_var in parsed.get("icons", []):
		var entry: Dictionary = entry_var
		if String(entry.get("id", "")) == id:
			var assets: Dictionary = entry.get("assets", {})
			return String(assets.get("icon", ""))
	return ""


func _id_index(ids: PackedStringArray, id: String) -> int:
	for i in ids.size():
		if String(ids[i]) == id:
			return i
	return -1


func _press_i() -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.physical_keycode = KEY_I
	Input.parse_input_event(ev)


func _delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("app_icon.save"):
		dir.remove("app_icon.save")


func _fail(message: String) -> bool:
	push_error("ICON_PICKER FAIL %s" % message)
	print("ICON_PICKER FAIL %s" % message)
	quit(1)
	return false
