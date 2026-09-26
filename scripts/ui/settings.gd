extends Control

## Title-screen settings overlay (D-035, D-052). Hidden on boot.
## Two pages, stacked from the page buttons downward so a new section
## takes the next free row instead of a hand-picked y.
## Look: avatar and theme. This phone: restore, this device, app icon.
## While visible it consumes S, menu/Escape, restart/R, launch_ball/Space
## and change_name/N so those keys do not reach main.gd or open NameEntry.
## Guard is is_visible_in_tree(): a closed overlay must not steal Escape/R.
## Children run _unhandled_input before parents, so this Control under Title
## beats scripts/main.gd without editing it.

const PAGE_LOOK := "look"
const PAGE_DEVICE := "device"
const SECTION_GAP := 12.0

var _page := PAGE_LOOK
var _pending_link_id := ""
var _restore_busy := false
## Headless has no clipboard. Tests turn this on so Paste can be driven
## without DisplayServer.clipboard_get, which errors there. Devices leave it off.
var _clipboard_stand_in_on := false
var _clipboard_stand_in := ""

@onready var _heading: Label = $Heading
@onready var _close: Button = $CloseButton
@onready var _look_button: Button = $LookButton
@onready var _device_button: Button = $DeviceButton
@onready var _avatar: Control = $AvatarPicker
@onready var _theme: Control = $ThemePicker
@onready var _icon: Control = $IconPicker
@onready var _this_device: Control = $ThisDevice
@onready var _restore: Control = $RestoreProfile
@onready var _name_label: Label = $ThisDevice/NameLabel
@onready var _show_toggle: Button = $ThisDevice/ShowCodeToggle
@onready var _code_label: Label = $ThisDevice/CodeLabel
@onready var _copy_button: Button = $ThisDevice/CopyButton
@onready var _restore_edit: LineEdit = $RestoreProfile/CodeEdit
@onready var _paste_button: Button = $RestoreProfile/PasteButton
@onready var _restore_button: Button = $RestoreProfile/RestoreButton
@onready var _status_label: Label = $RestoreProfile/StatusLabel
@onready var _link_panel: Control = $LinkRestore
@onready var _link_prompt: Label = $LinkRestore/Prompt
@onready var _link_code: Label = $LinkRestore/CodeLabel
@onready var _link_confirm: Button = $LinkRestore/ConfirmButton
@onready var _link_cancel: Button = $LinkRestore/CancelButton
@onready var _link_status: Label = $LinkRestore/StatusLabel


func _ready() -> void:
	visible = false
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(close)
	_look_button.focus_mode = Control.FOCUS_NONE
	_look_button.pressed.connect(_on_look_pressed)
	_device_button.focus_mode = Control.FOCUS_NONE
	_device_button.pressed.connect(_on_device_pressed)
	_show_toggle.focus_mode = Control.FOCUS_NONE
	_show_toggle.pressed.connect(_on_show_code_pressed)
	_copy_button.focus_mode = Control.FOCUS_NONE
	_copy_button.pressed.connect(_on_copy_pressed)
	_paste_button.focus_mode = Control.FOCUS_NONE
	_paste_button.pressed.connect(_on_paste_pressed)
	_restore_button.focus_mode = Control.FOCUS_NONE
	_restore_button.pressed.connect(_on_restore_pressed)
	_link_confirm.focus_mode = Control.FOCUS_NONE
	_link_confirm.pressed.connect(_on_link_confirm)
	_link_cancel.focus_mode = Control.FOCUS_NONE
	_link_cancel.pressed.connect(_on_link_cancel)
	if _restore_edit != null:
		_restore_edit.focus_mode = Control.FOCUS_CLICK
		_restore_edit.text_submitted.connect(_on_restore_submitted)
	_set_code_visible(false)
	if _link_panel != null:
		_link_panel.visible = false
	resized.connect(queue_redraw)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null:
		if theme_node.has_signal("palette_changed"):
			theme_node.palette_changed.connect(_apply_theme)
		_apply_theme()
	var profile := get_node_or_null("/root/Profile")
	if profile != null:
		if profile.has_signal("name_changed") and not profile.name_changed.is_connected(_on_profile_name_changed):
			profile.name_changed.connect(_on_profile_name_changed)
		if profile.has_signal("avatar_changed") and not profile.avatar_changed.is_connected(_on_profile_avatar_changed):
			profile.avatar_changed.connect(_on_profile_avatar_changed)
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard != null and leaderboard.has_signal("restore_finished"):
		if not leaderboard.restore_finished.is_connected(_on_restore_finished):
			leaderboard.restore_finished.connect(_on_restore_finished)
	_refresh_transfer_ui()
	_page = PAGE_LOOK
	_apply_page_layout()
	_kick_link_offer.call_deferred()
	queue_redraw()


func _draw() -> void:
	var fill := Color(0.05, 0.04, 0.08, 0.92)
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node != null and theme_node.has_method("color"):
		fill = theme_node.color("background")
		fill.a = 0.97
	draw_rect(Rect2(Vector2.ZERO, size), fill)


func open() -> void:
	var title := get_parent()
	if title != null and title.has_method("is_capturing_name") and title.is_capturing_name():
		return
	_set_code_visible(false)
	_set_status("")
	_refresh_transfer_ui()
	if _pending_link_id != "":
		_present_link_offer(false)
	else:
		_page = PAGE_LOOK
		if _link_panel != null:
			_link_panel.visible = false
		_apply_page_layout()
	visible = true


func close() -> void:
	visible = false
	_set_code_visible(false)
	_abandon_inflight_restore()
	_release_restore_focus()
	# Close declines an unconfirmed link. It does not adopt.
	_pending_link_id = ""
	if _link_panel != null:
		_link_panel.visible = false


func is_open() -> bool:
	return is_visible_in_tree()


func show_page(page: String) -> void:
	if page != PAGE_LOOK and page != PAGE_DEVICE:
		return
	if _link_panel != null:
		_link_panel.visible = false
	_page = page
	_release_restore_focus()
	_apply_page_layout()


func current_page() -> String:
	return _page


## Query string or full URL. `restore` is the only key read. Empty when absent.
func restore_param_from_search(search: String) -> String:
	var q := search.strip_edges()
	if q.is_empty():
		return ""
	var hash := q.find("#")
	if hash >= 0:
		q = q.substr(0, hash)
	var scheme := q.find("://")
	if scheme >= 0:
		var slash := q.find("/", scheme + 3)
		q = q.substr(slash) if slash >= 0 else ""
	var qm := q.find("?")
	if qm >= 0:
		q = q.substr(qm + 1)
	elif q.begins_with("/"):
		return ""
	for part in q.split("&", false):
		var eq := part.find("=")
		if eq <= 0:
			continue
		var key := part.substr(0, eq).uri_decode()
		if key != "restore":
			continue
		return part.substr(eq + 1).uri_decode().strip_edges()
	return ""


## Web export only. A missing singleton or a non-web run returns "" and does
## not reference JavaScriptBridge by name, so desktop and headless still parse.
func page_search() -> String:
	if not OS.has_feature("web"):
		return ""
	if not Engine.has_singleton("JavaScriptBridge"):
		return ""
	var bridge := Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return ""
	var raw: Variant = bridge.call("eval", "window.location.search", true)
	if typeof(raw) != TYPE_STRING:
		return ""
	return raw


## Valid UUID v4 shows a confirm panel and does not adopt. Anything else is ignored.
func offer_restore_from_search(search: String) -> void:
	var raw := restore_param_from_search(search)
	if raw.is_empty():
		return
	if not _is_uuid_v4(raw):
		return
	_pending_link_id = raw
	_present_link_offer(true)


func _kick_link_offer() -> void:
	# NameEntry grabs focus in its own deferred call. Wait one more frame
	# so a link does not open Settings under that prompt.
	_offer_link_from_page_url.call_deferred()


func _offer_link_from_page_url() -> void:
	offer_restore_from_search(page_search())


func _present_link_offer(try_open: bool) -> void:
	if _pending_link_id == "" or _link_panel == null:
		return
	if _link_code != null:
		_link_code.text = _pending_link_id
	if _link_status != null:
		_link_status.text = ""
	_link_panel.visible = true
	for section in _all_sections():
		if section != null:
			section.visible = false
	if _look_button != null:
		_look_button.visible = false
	if _device_button != null:
		_device_button.visible = false
	var y := SECTION_GAP
	if _heading != null:
		y = _heading.offset_bottom + SECTION_GAP
	_place(_link_panel, y)
	_refresh_page_button_styles()
	if not try_open:
		return
	var title := get_parent()
	if title != null and title.has_method("is_capturing_name") and title.is_capturing_name():
		return
	visible = true


func _on_look_pressed() -> void:
	show_page(PAGE_LOOK)


func _on_device_pressed() -> void:
	show_page(PAGE_DEVICE)


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node == null or not theme_node.has_method("color"):
		return
	_heading.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	_style_button(_close, theme_node, false)
	_style_button(_show_toggle, theme_node, false)
	_style_button(_copy_button, theme_node, false)
	_style_button(_paste_button, theme_node, false)
	_style_button(_restore_button, theme_node, false)
	_style_button(_link_confirm, theme_node, false)
	_style_button(_link_cancel, theme_node, false)
	var gold: Color = theme_node.color("glow_gold")
	var primary: Color = theme_node.color("text_primary")
	for path in ["ThisDevice/Caption", "RestoreProfile/Caption"]:
		var caption := get_node_or_null(path) as Label
		if caption != null:
			caption.add_theme_color_override("font_color", gold)
	if _link_prompt != null:
		_link_prompt.add_theme_color_override("font_color", gold)
	if _name_label != null:
		_name_label.add_theme_color_override("font_color", primary)
	if _code_label != null:
		_code_label.add_theme_color_override("font_color", primary)
	if _status_label != null:
		_status_label.add_theme_color_override("font_color", primary)
	if _link_code != null:
		_link_code.add_theme_color_override("font_color", primary)
	if _link_status != null:
		_link_status.add_theme_color_override("font_color", primary)
	if _restore_edit != null:
		_restore_edit.add_theme_color_override("font_color", primary)
		_restore_edit.add_theme_color_override("caret_color", primary)
	_refresh_page_button_styles()
	queue_redraw()


func _style_button(button: Button, theme_node: Node, selected: bool) -> void:
	if button == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = theme_node.color("glow_gold") if selected else theme_node.color("object_pink")
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	var font: Color = Color(0.12, 0.08, 0.16) if selected else theme_node.color("text_on_color")
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_disabled_color", font)
	button.add_theme_color_override("font_hover_color", font)
	button.add_theme_color_override("font_pressed_color", font)


func _refresh_page_button_styles() -> void:
	var theme_node := get_node_or_null("/root/Theme")
	if theme_node == null or not theme_node.has_method("color"):
		return
	_style_button(_look_button, theme_node, _page == PAGE_LOOK and not _link_is_showing())
	_style_button(_device_button, theme_node, _page == PAGE_DEVICE and not _link_is_showing())


func _on_profile_name_changed(_name: String) -> void:
	_refresh_transfer_ui()


func _on_profile_avatar_changed(_avatar_id: String) -> void:
	_refresh_transfer_ui()


func _refresh_transfer_ui() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	if _name_label != null:
		_name_label.text = String(profile.player_name)
	if _code_label != null:
		_code_label.text = String(profile.player_id)


func _on_show_code_pressed() -> void:
	_set_code_visible(not _code_is_visible())


func _code_is_visible() -> bool:
	return _code_label != null and _code_label.visible


func _set_code_visible(shown: bool) -> void:
	if _code_label != null:
		_code_label.visible = shown
	if _copy_button != null:
		_copy_button.visible = shown
	if _show_toggle != null:
		_show_toggle.text = "Hide transfer code" if shown else "Show transfer code"
	if shown:
		_refresh_transfer_ui()


func _on_copy_pressed() -> void:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return
	var id := String(profile.player_id)
	if id.is_empty():
		return
	DisplayServer.clipboard_set(id)


func _on_paste_pressed() -> void:
	if _restore_edit == null:
		return
	var text := _clipboard_text()
	if text.is_empty():
		return
	_restore_edit.text = text


func use_clipboard_stand_in(text: String) -> void:
	_clipboard_stand_in_on = true
	_clipboard_stand_in = text


func clear_clipboard_stand_in() -> void:
	_clipboard_stand_in_on = false
	_clipboard_stand_in = ""


func _clipboard_text() -> String:
	if _clipboard_stand_in_on:
		return _clipboard_stand_in.strip_edges()
	# Headless clipboard_get prints an engine error and returns "". Skip it.
	# Do not consult clipboard_has first: on the web the read itself is the
	# gesture that grants clipboard permission, and a false has() would skip it.
	if DisplayServer.get_name() == "headless":
		return ""
	return String(DisplayServer.clipboard_get()).strip_edges()


func _on_restore_submitted(_text: String) -> void:
	_on_restore_pressed()


func _on_restore_pressed() -> void:
	if _restore_edit == null:
		return
	_begin_restore(String(_restore_edit.text))


func _on_link_confirm() -> void:
	if _pending_link_id == "":
		return
	_begin_restore(_pending_link_id)


func _on_link_cancel() -> void:
	_abandon_inflight_restore()
	_pending_link_id = ""
	if _link_status != null:
		_link_status.text = ""
	if _link_panel != null:
		_link_panel.visible = false
	_apply_page_layout()


## Leaderboard adopts inside its own HTTP callback, before restore_finished.
## Not now / Close bump the existing generation so that callback is stale
## and drops the adopt (the same guard as a superseded restore).
func _abandon_inflight_restore() -> void:
	if not _restore_busy:
		return
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard != null:
		leaderboard._restore_gen = int(leaderboard._restore_gen) + 1
	_restore_busy = false
	_set_restore_busy(false)


func _begin_restore(raw: String) -> void:
	if _restore_busy:
		return
	var id := raw.strip_edges()
	if id.is_empty():
		return
	_set_status("")
	if _link_status != null and _link_is_showing():
		_link_status.text = ""
	if not _is_uuid_v4(id):
		_set_status("that code doesn't look right")
		if _link_is_showing() and _link_status != null:
			_link_status.text = "that code doesn't look right"
		return
	var leaderboard := get_node_or_null("/root/Leaderboard")
	if leaderboard == null or not leaderboard.has_method("restore_profile"):
		_set_status("couldn't reach the leaderboard")
		if _link_is_showing() and _link_status != null:
			_link_status.text = "couldn't reach the leaderboard"
		return
	_restore_busy = true
	_set_restore_busy(true)
	leaderboard.restore_profile(id)


func _on_restore_finished(ok: bool, reason: String) -> void:
	_restore_busy = false
	_set_restore_busy(false)
	if ok:
		_pending_link_id = ""
		_set_status("")
		if _link_status != null:
			_link_status.text = ""
		if _link_panel != null:
			_link_panel.visible = false
		if _restore_edit != null:
			_restore_edit.text = ""
		_refresh_transfer_ui()
		_page = PAGE_LOOK
		_apply_page_layout()
		return
	var message: String = "no profile found" if reason == "not_found" else "couldn't reach the leaderboard"
	_set_status(message)
	if _link_is_showing() and _link_status != null:
		_link_status.text = message


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _set_restore_busy(busy: bool) -> void:
	if _restore_button != null:
		_restore_button.disabled = busy
	if _link_confirm != null:
		_link_confirm.disabled = busy
	if _restore_edit != null:
		_restore_edit.editable = not busy


func _release_restore_focus() -> void:
	if _restore_edit != null and _restore_edit.has_focus():
		_restore_edit.release_focus()
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_release_focus()


func _is_uuid_v4(value: String) -> bool:
	var profile := get_node_or_null("/root/Profile")
	if profile == null or not profile.has_method("_is_uuid_v4"):
		return false
	return bool(profile._is_uuid_v4(value))


func _link_is_showing() -> bool:
	return _link_panel != null and _link_panel.visible and _pending_link_id != ""


func _all_sections() -> Array[Control]:
	var sections: Array[Control] = []
	for section in [_avatar, _theme, _restore, _this_device, _icon]:
		if section != null:
			sections.append(section)
	return sections


func _sections_for(page: String) -> Array[Control]:
	var sections: Array[Control] = []
	if page == PAGE_DEVICE:
		for section in [_restore, _this_device, _icon]:
			if section != null:
				sections.append(section)
		return sections
	for section in [_avatar, _theme]:
		if section != null:
			sections.append(section)
	return sections


func _apply_page_layout() -> void:
	var offering := _link_is_showing()
	for section in _all_sections():
		section.visible = false
	if offering:
		_place(_link_panel, _content_top())
		_refresh_page_button_styles()
		return
	if _link_panel != null:
		_link_panel.visible = false
	if _look_button != null:
		_look_button.visible = true
	if _device_button != null:
		_device_button.visible = true
	var y := _content_top()
	for section in _sections_for(_page):
		section.visible = true
		y = _place(section, y)
	_refresh_page_button_styles()


func _content_top() -> float:
	var bottom := 0.0
	if _look_button != null:
		bottom = maxf(bottom, _look_button.offset_bottom)
	if _device_button != null:
		bottom = maxf(bottom, _device_button.offset_bottom)
	return bottom + SECTION_GAP


func _place(ctrl: Control, y: float) -> float:
	if ctrl == null:
		return y
	var h := ctrl.offset_bottom - ctrl.offset_top
	if h < 1.0:
		h = ctrl.size.y
	ctrl.offset_top = y
	ctrl.offset_bottom = y + h
	return y + h + SECTION_GAP


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _restore_edit == null or not _restore_edit.has_focus():
		return
	# Swallow only synthetic actions. Real keys must reach CodeEdit as text
	# (`_input` runs before GUI).
	if not (event is InputEventAction):
		return
	if event.is_action_pressed("launch_ball") or event.is_action_pressed("restart") or event.is_action_pressed("change_name"):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("menu"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("launch_ball"):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("change_name"):
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_S:
		if _restore_edit != null and _restore_edit.has_focus():
			get_viewport().set_input_as_handled()
			return
		close()
		get_viewport().set_input_as_handled()
