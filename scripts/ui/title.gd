extends CanvasLayer

var _dismissed := false
var _flippers_enabled := true

@onready var _name_entry: Control = $NameEntry
@onready var _player_name_label: Label = $PlayerNameLabel


func _ready() -> void:
	visible = true
	var theme_node := get_node("/root/Theme")
	theme_node.palette_changed.connect(_apply_theme)
	_apply_theme(theme_node.palette_id)
	var profile := get_node("/root/Profile")
	if not profile.name_changed.is_connected(_on_name_changed):
		profile.name_changed.connect(_on_name_changed)
	_refresh_name_ui(String(profile.player_name))


func _process(_delta: float) -> void:
	_set_flippers_enabled(not _is_capturing_name())


func _apply_theme(_id: String = "") -> void:
	var theme_node := get_node("/root/Theme")
	var primary: Color = theme_node.color("text_primary")
	var shade := get_node_or_null("Shade") as ColorRect
	if shade != null:
		var bg: Color = theme_node.color("background")
		bg.a = 0.78
		shade.color = bg
	$TableNameLabel.add_theme_color_override("font_color", theme_node.color("glow_gold"))
	$ControlsLabel.add_theme_color_override("font_color", primary)
	$PlayHintLabel.add_theme_color_override("font_color", primary)
	_player_name_label.add_theme_color_override("font_color", primary)


func _on_name_changed(new_name: String) -> void:
	_refresh_name_ui(new_name)


func show_menu() -> void:
	_dismissed = false
	visible = true
	var profile := get_node_or_null("/root/Profile")
	if profile != null:
		_refresh_name_ui(String(profile.player_name))
	else:
		_refresh_name_ui("")


func is_capturing_name() -> bool:
	return _is_capturing_name()


func _refresh_name_ui(player_name: String) -> void:
	var named := not player_name.is_empty()
	_player_name_label.text = "Playing as %s · N to change" % player_name if named else ""
	_player_name_label.visible = named
	$PlayHintLabel.visible = named
	if named:
		if _name_entry.visible:
			_name_entry.visible = false
		_name_entry.release_name_focus()
	else:
		_name_entry.open()


func _is_capturing_name() -> bool:
	return _name_entry != null and _name_entry.has_method("is_capturing") and _name_entry.is_capturing()


func _needs_name() -> bool:
	var profile := get_node_or_null("/root/Profile")
	return profile != null and String(profile.player_name).is_empty()


func _set_flippers_enabled(enabled: bool) -> void:
	if enabled == _flippers_enabled:
		return
	_flippers_enabled = enabled
	var main := get_parent()
	if main == null:
		return
	for path in ["Table/FlipperLeft", "Table/FlipperRight"]:
		var flipper := main.get_node_or_null(path)
		if flipper != null:
			flipper.set_physics_process(enabled)


func _input(event: InputEvent) -> void:
	if _dismissed:
		return
	# Swallow only synthetic actions. Real keys must reach NameEdit as text
	# (`_input` runs before GUI). Flippers are gated in `_process`.
	if not (event is InputEventAction):
		return
	var capturing := _is_capturing_name()
	if (capturing or _needs_name()) and event.is_action_pressed("launch_ball"):
		get_viewport().set_input_as_handled()
		return
	if capturing and event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
	if capturing and event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _dismissed:
		return
	if _is_capturing_name() or _needs_name():
		if event.is_action_pressed("launch_ball"):
			get_viewport().set_input_as_handled()
		if _is_capturing_name() and event.is_action_pressed("restart"):
			get_viewport().set_input_as_handled()
		if _is_capturing_name() and event.is_action_pressed("menu"):
			get_viewport().set_input_as_handled()
		if _is_capturing_name() and event is InputEventKey and event.pressed:
			var key := event as InputEventKey
			if key.physical_keycode == KEY_LEFT or key.physical_keycode == KEY_RIGHT:
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("change_name"):
		_name_entry.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("launch_ball"):
		_dismissed = true
		_name_entry.release_name_focus()
		_set_flippers_enabled(true)
		visible = false
