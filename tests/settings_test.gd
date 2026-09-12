extends SceneTree

const VIEWPORT := Rect2(0, 0, 720, 1280)
const TITLE_FLOOR := 1150.0
const SAVE_PATH := "user://profile.save"

var _cases_passed: int = 0
var _avatar_changed_count: int = 0
var _last_avatar_id: String = ""
var _game: Node
var _profile: Node
var _theme: Node
var _app_icon: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("SETTINGS start")
	_game = root.get_node_or_null("Game")
	_profile = root.get_node_or_null("Profile")
	_theme = root.get_node_or_null("Theme")
	_app_icon = root.get_node_or_null("AppIcon")
	if _game == null or _profile == null or _theme == null or _app_icon == null:
		_fail("Game, Profile, Theme, or AppIcon autoload missing")
		return
	if String(_profile.player_name).is_empty():
		_profile.call("set_name", "Dad")
	if not _profile.avatar_changed.is_connected(_on_avatar_changed):
		_profile.avatar_changed.connect(_on_avatar_changed)
	_game.high_score = 0
	_game.restart()
	await process_frame

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

	if not await _case_1_overlay_hidden(main):
		return
	if not await _case_2_toggle_keys(main):
		return
	if not await _case_3_open_consumes(main):
		return
	if not await _case_4_picker_keys(main):
		return
	if not await _case_5_name_entry(main):
		return
	if not await _case_5b_n_while_open(main):
		return
	if not await _case_6_layout(main):
		return
	if not await _case_7_avatar_ids(main):
		return
	if not await _case_8_pick_avatar(main):
		return

	print("SETTINGS PASS cases=%d" % _cases_passed)
	quit(0)


func _on_avatar_changed(avatar_id: String) -> void:
	_avatar_changed_count += 1
	_last_avatar_id = avatar_id


func _case_1_overlay_hidden(main: Node) -> bool:
	print("SETTINGS case 1 overlay hidden on boot")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var theme_picker := main.get_node_or_null("Title/Settings/ThemePicker")
	var icon_picker := main.get_node_or_null("Title/Settings/IconPicker")
	if settings == null:
		return _fail("case 1: Title/Settings missing")
	if theme_picker == null or icon_picker == null:
		return _fail("case 1: ThemePicker/IconPicker must be children of Settings")
	if settings.visible or settings.is_visible_in_tree():
		return _fail("case 1: Settings must be hidden on boot")
	if theme_picker.get_parent() != settings or icon_picker.get_parent() != settings:
		return _fail("case 1: pickers are not Settings children")
	_cases_passed += 1
	print("SETTINGS case 1 pass")
	return true


func _case_2_toggle_keys(main: Node) -> bool:
	print("SETTINGS case 2 S toggle and Escape close")
	var title := main.get_node_or_null("Title")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var button := main.get_node_or_null("Title/SettingsButton") as Button
	if title == null or settings == null or button == null:
		return _fail("case 2: Title, Settings, or SettingsButton missing")
	if not title.visible:
		return _fail("case 2: Title should be visible")

	_press_key(main, KEY_S)
	await process_frame
	await process_frame
	if not settings.is_visible_in_tree():
		return _fail("case 2: S on the title should open Settings")

	_press_key(main, KEY_S)
	await process_frame
	await process_frame
	if settings.is_visible_in_tree():
		return _fail("case 2: S again should close Settings")

	button.pressed.emit()
	await process_frame
	if not settings.is_visible_in_tree():
		return _fail("case 2: SettingsButton should open Settings")

	_press_escape(main)
	await process_frame
	await process_frame
	if settings.is_visible_in_tree():
		return _fail("case 2: Escape should close Settings")

	_open_settings(main)
	await process_frame
	var close_btn := settings.get_node_or_null("CloseButton") as Button
	if close_btn == null:
		return _fail("case 2: CloseButton missing")
	close_btn.pressed.emit()
	await process_frame
	if settings.is_visible_in_tree():
		return _fail("case 2: CloseButton should close Settings")

	_cases_passed += 1
	print("SETTINGS case 2 pass")
	return true


func _case_3_open_consumes(main: Node) -> bool:
	print("SETTINGS case 3 open consumes Escape/R/Space")
	var title := main.get_node_or_null("Title")
	var settings := main.get_node_or_null("Title/Settings") as Control
	if title == null or settings == null:
		return _fail("case 3: Title or Settings missing")

	_game.add_score(100)
	await process_frame
	var score_before: int = _game.score
	var balls_before: int = _game.balls_left
	var state_before: int = _game.state
	var title_visible: bool = title.visible

	_open_settings(main)
	await process_frame
	if not settings.is_visible_in_tree():
		return _fail("case 3: Settings should be open")

	_push_action(main, "menu")
	await process_frame
	await process_frame
	_push_action(main, "menu", false)
	await process_frame
	if _game.score != score_before or _game.balls_left != balls_before or _game.state != state_before:
		return _fail("case 3: Escape returned to menu while Settings open")
	if title.visible != title_visible:
		return _fail("case 3: Title visibility changed on Escape while Settings open")
	if settings.is_visible_in_tree():
		return _fail("case 3: Escape should close Settings")

	_open_settings(main)
	await process_frame
	_push_action(main, "restart")
	await process_frame
	await process_frame
	_push_action(main, "restart", false)
	if _game.score != score_before or _game.state != state_before:
		return _fail("case 3: R restarted while Settings open")
	if not settings.is_visible_in_tree():
		return _fail("case 3: R should leave Settings open")

	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	_push_action(main, "launch_ball")
	var launched := false
	for _f in 5:
		await physics_frame
		if is_instance_valid(ball) and bool(ball.get("launched")):
			launched = true
			break
	_push_action(main, "launch_ball", false)
	if launched:
		return _fail("case 3: Space launched while Settings open")
	if not title.visible:
		return _fail("case 3: Space hid the title while Settings open")
	if not settings.is_visible_in_tree():
		return _fail("case 3: Space should leave Settings open")

	_close_settings(main)
	await process_frame
	_cases_passed += 1
	print("SETTINGS case 3 pass")
	return true


func _case_4_picker_keys(main: Node) -> bool:
	print("SETTINGS case 4 picker keys gated on overlay")
	var settings := main.get_node_or_null("Title/Settings") as Control
	if settings == null:
		return _fail("case 4: Settings missing")
	_close_settings(main)
	await process_frame

	var icon_before := String(_app_icon.icon_id)
	var palette_before := String(_theme.palette_id)
	_press_key(main, KEY_I)
	await process_frame
	await process_frame
	_press_key(main, KEY_RIGHT)
	await process_frame
	await process_frame
	if String(_app_icon.icon_id) != icon_before:
		return _fail("case 4: I changed AppIcon while Settings closed")
	if String(_theme.palette_id) != palette_before:
		return _fail("case 4: ←/→ changed Theme while Settings closed")

	_open_settings(main)
	await process_frame
	_press_key(main, KEY_I)
	await process_frame
	await process_frame
	if String(_app_icon.icon_id) == icon_before:
		return _fail("case 4: I should cycle AppIcon while Settings open")
	_press_key(main, KEY_RIGHT)
	await process_frame
	await process_frame
	if String(_theme.palette_id) == palette_before:
		return _fail("case 4: → should cycle Theme while Settings open")

	_close_settings(main)
	await process_frame
	_cases_passed += 1
	print("SETTINGS case 4 pass")
	return true


func _case_5_name_entry(main: Node) -> bool:
	print("SETTINGS case 5 S quiet while NameEntry captures")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var entry := main.get_node_or_null("Title/NameEntry")
	if settings == null or entry == null:
		return _fail("case 5: Settings or NameEntry missing")
	_close_settings(main)
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
		return _fail("case 5: NameEntry should be capturing")

	var edit := entry.get_node_or_null("NameEdit") as LineEdit
	if edit == null:
		return _fail("case 5: NameEdit missing")
	edit.text = ""
	edit.caret_column = 0
	edit.grab_focus()
	await process_frame
	_type_char(main, KEY_I, 105)
	_type_char(main, KEY_S, 115)
	await process_frame
	if edit.text != "is":
		return _fail("case 5: LineEdit should accept i/s, got '%s'" % edit.text)
	if settings.is_visible_in_tree():
		return _fail("case 5: S opened Settings while NameEntry capturing")

	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	main.get_viewport().push_input(esc)
	await process_frame
	await process_frame
	esc.pressed = false
	main.get_viewport().push_input(esc)
	await process_frame

	_cases_passed += 1
	print("SETTINGS case 5 pass")
	return true


func _case_5b_n_while_open(main: Node) -> bool:
	print("SETTINGS case 5b N while Settings open")
	var settings := main.get_node_or_null("Title/Settings") as Control
	var entry := main.get_node_or_null("Title/NameEntry")
	if settings == null or entry == null:
		return _fail("case 5b: Settings or NameEntry missing")
	_open_settings(main)
	await process_frame
	if not settings.is_visible_in_tree():
		return _fail("case 5b: Settings should be open")
	_push_action(main, "change_name")
	await process_frame
	await process_frame
	_push_action(main, "change_name", false)
	if entry.visible or (entry.has_method("is_capturing") and entry.is_capturing()):
		return _fail("case 5b: N opened NameEntry under Settings")
	if not settings.is_visible_in_tree():
		return _fail("case 5b: N should leave Settings open")
	_close_settings(main)
	await process_frame
	_cases_passed += 1
	print("SETTINGS case 5b pass")
	return true


func _case_6_layout(main: Node) -> bool:
	print("SETTINGS case 6 layout")
	var title := main.get_node_or_null("Title")
	var settings := main.get_node_or_null("Title/Settings") as Control
	if title == null or settings == null:
		return _fail("case 6: Title or Settings missing")

	_open_settings(main)
	await process_frame
	var settings_rect: Rect2 = settings.get_global_rect()
	if not VIEWPORT.encloses(settings_rect):
		return _fail("case 6: Settings %s outside viewport" % settings_rect)

	var kids: Array[Control] = []
	for child in settings.get_children():
		if child is Control:
			kids.append(child)
	for i in kids.size():
		for j in range(i + 1, kids.size()):
			var a: Rect2 = kids[i].get_global_rect()
			var b: Rect2 = kids[j].get_global_rect()
			if a.intersects(b):
				return _fail(
					"case 6: Settings children intersect %s %s vs %s %s"
					% [kids[i].name, a, kids[j].name, b]
				)

	_close_settings(main)
	await process_frame
	for child in title.get_children():
		if not (child is Control):
			continue
		var node := child as Control
		if node.name == "Shade" or node.name == "Settings":
			continue
		if not node.visible or not node.is_visible_in_tree():
			continue
		var rect: Rect2 = node.get_global_rect()
		if rect.end.y > TITLE_FLOOR:
			return _fail("case 6: Title/%s extends below y=1150: %s" % [node.name, rect])

	_cases_passed += 1
	print("SETTINGS case 6 pass")
	return true


func _case_7_avatar_ids(main: Node) -> bool:
	print("SETTINGS case 7 avatar catalog ids")
	var picker := main.get_node_or_null("Title/Settings/AvatarPicker")
	if picker == null or not picker.has_method("offered_ids"):
		return _fail("case 7: AvatarPicker missing offered_ids")
	var got: PackedStringArray = picker.offered_ids()
	var want := _loadable_avatar_ids()
	if got.size() != want.size():
		return _fail("case 7: offered %d ids, catalog-loadable %d" % [got.size(), want.size()])
	for i in want.size():
		if String(got[i]) != String(want[i]):
			return _fail("case 7: offered[%d]=%s want %s" % [i, got[i], want[i]])
	_cases_passed += 1
	print("SETTINGS case 7 pass count=%d" % got.size())
	return true


func _case_8_pick_avatar(main: Node) -> bool:
	print("SETTINGS case 8 pick avatar")
	var picker := main.get_node_or_null("Title/Settings/AvatarPicker")
	var view := main.get_node_or_null("Title/AvatarView") as TextureRect
	if picker == null or view == null:
		return _fail("case 8: AvatarPicker or AvatarView missing")
	var ids: PackedStringArray = picker.offered_ids()
	if ids.is_empty():
		return _fail("case 8: no offered avatar ids")
	var pick_id := String(ids[0])
	if String(_profile.avatar_id) == pick_id and ids.size() > 1:
		pick_id = String(ids[1])

	_open_settings(main)
	await process_frame
	_avatar_changed_count = 0
	var button := picker.get_node_or_null("Grid/Choice_%s" % pick_id) as BaseButton
	if button == null:
		return _fail("case 8: missing Choice_%s" % pick_id)
	button.pressed.emit()
	await process_frame
	await process_frame
	if String(_profile.avatar_id) != pick_id:
		return _fail("case 8: avatar_id %s want %s" % [_profile.avatar_id, pick_id])
	if _avatar_changed_count != 1:
		return _fail("case 8: avatar_changed fired %d times, expected 1" % _avatar_changed_count)
	if _last_avatar_id != pick_id:
		return _fail("case 8: avatar_changed id %s want %s" % [_last_avatar_id, pick_id])
	var data := _read_profile_save()
	if String((data.get("avatars", {}) as Dictionary).get(_name_key(String(_profile.player_name)), "")) != pick_id:
		return _fail("case 8: profile.save avatars missing %s: %s" % [pick_id, data])
	if view.texture == null:
		return _fail("case 8: AvatarView texture is null")
	var got_path := String(view.texture.resource_path)
	var want_path := SquishyCatalog.sprite_path(pick_id)
	if got_path != want_path:
		return _fail("case 8: AvatarView path %s want %s" % [got_path, want_path])

	_close_settings(main)
	await process_frame
	_cases_passed += 1
	print("SETTINGS case 8 pass id=%s" % pick_id)
	return true


func _loadable_avatar_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var catalog: Dictionary = SquishyCatalog.data()
	for item_variant in catalog.get("squishies", []):
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_variant
		var id := String(item.get("id", ""))
		if id.is_empty():
			continue
		var path := SquishyCatalog.sprite_path(id)
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		if load(path) is Texture2D:
			out.append(id)
	return out


func _open_settings(main: Node) -> void:
	var settings := main.get_node_or_null("Title/Settings") as Control
	if settings != null:
		settings.visible = true


func _close_settings(main: Node) -> void:
	var settings := main.get_node_or_null("Title/Settings") as Control
	if settings != null:
		settings.visible = false


func _press_key(main: Node, physical: Key) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.physical_keycode = physical
	ev.keycode = physical
	main.get_viewport().push_input(ev)
	ev.pressed = false
	main.get_viewport().push_input(ev)


func _press_escape(main: Node) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	main.get_viewport().push_input(ev)
	ev.pressed = false
	main.get_viewport().push_input(ev)


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


func _read_profile_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _name_key(n: String) -> String:
	return n.to_lower()


func _fail(message: String) -> bool:
	push_error("SETTINGS FAIL %s" % message)
	print("SETTINGS FAIL %s" % message)
	quit(1)
	return false
