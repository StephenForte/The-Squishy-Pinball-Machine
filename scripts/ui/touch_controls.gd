extends CanvasLayer

## Translates real multi-touch (and a single mouse stand-in) into the existing
## input actions. Keyboard paths stay first-class: a zone releases only when
## its last finger lifts *and* no matching key is still down (D-043).

const FLIPPER_BAND_START := 0.5
const MOUSE_INDEX := 999

var _zone_fingers: Dictionary = {
	&"flipper_left": {},
	&"flipper_right": {},
}
var _finger_zone: Dictionary = {}
var _launch_fingers: Dictionary = {}
var _ignored_fingers: Dictionary = {}
var _screen_touch_indices: Dictionary = {}
var _prefer_screen_touch := false
var _key_holds: Dictionary = {
	&"flipper_left": false,
	&"flipper_right": false,
}
var _we_pressed: Dictionary = {
	&"flipper_left": false,
	&"flipper_right": false,
}

@onready var _play: Control = $PlayArea


func _ready() -> void:
	layer = 12
	_play.focus_mode = Control.FOCUS_NONE
	_play.mouse_filter = Control.MOUSE_FILTER_STOP
	_play.gui_input.connect(_on_play_gui_input)
	var game := get_node_or_null("/root/Game")
	if game != null and game.has_signal("game_restarted"):
		if not game.game_restarted.is_connected(_on_game_restarted):
			game.game_restarted.connect(_on_game_restarted)


func _process(_delta: float) -> void:
	if _blocked():
		_play.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_clear_touch_holds()
		return
	_play.mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_action(&"flipper_left")
	_sync_action(&"flipper_right")


func _input(event: InputEvent) -> void:
	# Track A/D/arrows ourselves so a synthesized key (tests) and a real key
	# both combine with touch. Never mark the key handled.
	if event is InputEventKey:
		_note_key(event as InputEventKey)
		_sync_action(&"flipper_left")
		_sync_action(&"flipper_right")
		return
	# parse_input_event delivers ScreenTouch here; GUI/buttons still see it
	# because we do not mark it handled.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var local := _to_play(touch.position)
		if not _over_interactive_ui(local):
			_handle_screen_touch(touch.index, local, touch.pressed)
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var local := _to_play(drag.position)
		if not _over_interactive_ui(local):
			_handle_screen_drag(drag.index, local)


func _unhandled_input(event: InputEvent) -> void:
	# A real window never lands a button-center ScreenTouch here: GUI pick
	# delivers it to the button. Headless `-s` has a 0×0 window, so pick is
	# dead and the same event falls through. Guard both so the test and a
	# device agree. Do not mark the event handled — buttons still need it.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var local := _to_play(touch.position)
		if not _over_interactive_ui(local):
			_handle_screen_touch(touch.index, local, touch.pressed)
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_handle_screen_drag(drag.index, _to_play(drag.position))
		return
	if _is_mouse_standin(event):
		_handle_mouse_event(event)


func _on_play_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var local := _to_play(touch.position)
		if not _over_interactive_ui(local):
			_handle_screen_touch(touch.index, local, touch.pressed)
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_handle_screen_drag(drag.index, _to_play(drag.position))
		return
	if _is_mouse_standin(event):
		_handle_mouse_event(event)


func _on_game_restarted() -> void:
	_clear_all_touch_state()


func _handle_screen_touch(index: int, pos: Vector2, pressed: bool) -> void:
	_prefer_screen_touch = true
	if _finger_zone.has(MOUSE_INDEX) or _launch_fingers.has(MOUSE_INDEX):
		_leave_zone(MOUSE_INDEX)
		_launch_fingers.erase(MOUSE_INDEX)
		_ignored_fingers.erase(MOUSE_INDEX)
	if pressed:
		_screen_touch_indices[index] = true
	else:
		_screen_touch_indices.erase(index)
	_handle_finger(index, pos, pressed)


func _handle_screen_drag(index: int, pos: Vector2) -> void:
	_screen_touch_indices[index] = true
	if _finger_zone.has(index) or _launch_fingers.has(index):
		_move_finger(index, pos)


func _handle_mouse_event(event: InputEvent) -> void:
	if _prefer_screen_touch or not _screen_touch_indices.is_empty():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		_handle_finger(MOUSE_INDEX, _to_play(_mouse_pos(button)), button.pressed)
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _finger_zone.has(MOUSE_INDEX) or _launch_fingers.has(MOUSE_INDEX):
			_move_finger(MOUSE_INDEX, _to_play(_mouse_pos(event)))


func _handle_finger(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _finger_zone.has(index) or _launch_fingers.has(index) or _ignored_fingers.has(index):
			return
		if _blocked():
			_ignored_fingers[index] = true
			return
		var zone := _zone_at(pos)
		if zone == &"launch":
			_launch_fingers[index] = true
			return
		_enter_zone(index, zone)
		return
	if _ignored_fingers.has(index):
		_ignored_fingers.erase(index)
		_launch_fingers.erase(index)
		_leave_zone(index)
		return
	_lift_finger(index)


func _move_finger(index: int, pos: Vector2) -> void:
	if _blocked():
		_clear_touch_holds()
		return
	var zone := _zone_at(pos)
	if zone == &"launch":
		if _finger_zone.has(index):
			_leave_zone(index)
			_launch_fingers[index] = true
		return
	if _launch_fingers.has(index):
		_launch_fingers.erase(index)
		_enter_zone(index, zone)
		return
	var current: StringName = _finger_zone.get(index, &"")
	if current != zone:
		_leave_zone(index)
		_enter_zone(index, zone)


func _lift_finger(index: int) -> void:
	var was_launch := _launch_fingers.has(index)
	_launch_fingers.erase(index)
	_leave_zone(index)
	if was_launch and not _blocked():
		_fire_launch()


func _enter_zone(index: int, zone: StringName) -> void:
	_finger_zone[index] = zone
	var fingers: Dictionary = _zone_fingers[zone]
	fingers[index] = true
	_sync_action(zone)


func _leave_zone(index: int) -> void:
	if not _finger_zone.has(index):
		return
	var zone: StringName = _finger_zone[index]
	_finger_zone.erase(index)
	var fingers: Dictionary = _zone_fingers[zone]
	fingers.erase(index)
	_sync_action(zone)


func _sync_action(action: StringName) -> void:
	var want := _touch_holds(action) or _keyboard_holds(action)
	if want:
		if not Input.is_action_pressed(action):
			Input.action_press(action)
			_we_pressed[action] = true
		elif not _keyboard_holds(action) and _touch_holds(action):
			_we_pressed[action] = true
	elif bool(_we_pressed.get(action, false)):
		if Input.is_action_pressed(action):
			Input.action_release(action)
		_we_pressed[action] = false


func _touch_holds(action: StringName) -> bool:
	var fingers: Variant = _zone_fingers.get(action, {})
	return typeof(fingers) == TYPE_DICTIONARY and not (fingers as Dictionary).is_empty()


func _note_key(key: InputEventKey) -> void:
	if key.echo:
		return
	var action := _action_for_key(key)
	if action == &"":
		return
	_key_holds[action] = key.pressed


func _action_for_key(key: InputEventKey) -> StringName:
	var physical := key.physical_keycode
	var code := key.keycode
	if physical == KEY_A or physical == KEY_LEFT or code == KEY_A or code == KEY_LEFT:
		return &"flipper_left"
	if physical == KEY_D or physical == KEY_RIGHT or code == KEY_D or code == KEY_RIGHT:
		return &"flipper_right"
	return &""


func _keyboard_holds(action: StringName) -> bool:
	if bool(_key_holds.get(action, false)):
		return true
	match action:
		&"flipper_left":
			return Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
		&"flipper_right":
			return Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
		_:
			return false


func _fire_launch() -> void:
	var press := InputEventAction.new()
	press.action = &"launch_ball"
	press.pressed = true
	get_viewport().push_input(press)
	var release := InputEventAction.new()
	release.action = &"launch_ball"
	release.pressed = false
	get_viewport().push_input(release)


func _clear_all_touch_state() -> void:
	_clear_touch_holds()
	_screen_touch_indices.clear()


func _clear_touch_holds() -> void:
	_finger_zone.clear()
	_launch_fingers.clear()
	_ignored_fingers.clear()
	(_zone_fingers[&"flipper_left"] as Dictionary).clear()
	(_zone_fingers[&"flipper_right"] as Dictionary).clear()
	_we_pressed[&"flipper_left"] = true
	_we_pressed[&"flipper_right"] = true
	_sync_action(&"flipper_left")
	_sync_action(&"flipper_right")


func _blocked() -> bool:
	var main := get_parent()
	if main == null:
		return false
	var title := main.get_node_or_null("Title")
	if title != null and title.has_method("is_capturing_name") and title.is_capturing_name():
		return true
	var settings := main.get_node_or_null("Title/Settings")
	if settings != null and settings.has_method("is_open") and settings.is_open():
		return true
	return false


func _over_interactive_ui(pos: Vector2) -> bool:
	var main := get_parent()
	if main == null:
		return false
	for layer_name in ["Title", "GameOver"]:
		var layer := main.get_node_or_null(layer_name)
		if layer == null or not layer.visible:
			continue
		if _node_blocks_touch(layer, pos):
			return true
	return false


func _node_blocks_touch(node: Node, pos: Vector2) -> bool:
	if node is BaseButton or node is LineEdit:
		var ctrl := node as Control
		if (
			ctrl.is_visible_in_tree()
			and ctrl.mouse_filter != Control.MOUSE_FILTER_IGNORE
			and ctrl.get_global_rect().has_point(pos)
		):
			return true
	for child in node.get_children():
		if _node_blocks_touch(child, pos):
			return true
	return false


func _zone_at(pos: Vector2) -> StringName:
	var area := _play_size()
	if pos.y >= area.y * FLIPPER_BAND_START:
		if pos.x < area.x * 0.5:
			return &"flipper_left"
		return &"flipper_right"
	return &"launch"


func _to_play(pos: Vector2) -> Vector2:
	var area := _play_size()
	var local_rect := Rect2(Vector2.ZERO, area).grow(2.0)
	if local_rect.has_point(pos):
		return pos
	var vp := get_viewport()
	if vp == null:
		return pos
	var converted: Vector2 = vp.get_screen_transform() * pos
	if local_rect.has_point(converted):
		return converted
	return pos


func _play_size() -> Vector2:
	if _play != null and _play.size.x > 0.0 and _play.size.y > 0.0:
		return _play.size
	return Vector2(720, 1280)


func _mouse_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).position
	return Vector2.ZERO


func _is_mouse_standin(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	return event is InputEventMouseMotion
