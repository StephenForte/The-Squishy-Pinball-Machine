extends CanvasLayer

var _dismissed := false
var _flippers_enabled := true

@onready var _name_entry: Control = $NameEntry
@onready var _player_name_label: Label = $PlayerNameLabel
@onready var _top_five_label: Label = $TopFiveLabel
@onready var _avatar_view: TextureRect = $AvatarView
@onready var _settings_button: Button = $SettingsButton
@onready var _settings: Control = $Settings

var _leaderboard: Node
var _title_offline := false
var _placeholder_avatar: Texture2D


func _ready() -> void:
	visible = true
	_leaderboard = get_node_or_null("/root/Leaderboard")
	var theme_node := get_node("/root/Theme")
	theme_node.palette_changed.connect(_apply_theme)
	_apply_theme(theme_node.palette_id)
	var profile := get_node("/root/Profile")
	if not profile.name_changed.is_connected(_on_name_changed):
		profile.name_changed.connect(_on_name_changed)
	if not profile.avatar_changed.is_connected(_on_avatar_changed):
		profile.avatar_changed.connect(_on_avatar_changed)
	_settings_button.focus_mode = Control.FOCUS_NONE
	_settings_button.pressed.connect(_open_settings)
	_refresh_name_ui(String(profile.player_name))
	_refresh_avatar()
	if _leaderboard != null:
		if _leaderboard.has_signal("board_updated") and not _leaderboard.board_updated.is_connected(_on_board_updated):
			_leaderboard.board_updated.connect(_on_board_updated)
		if _leaderboard.has_signal("offline") and not _leaderboard.offline.is_connected(_on_offline):
			_leaderboard.offline.connect(_on_offline)
		if (_leaderboard.last_entries as Array).size() > 0:
			_render_top_five(_leaderboard.last_entries)
		else:
			_top_five_label.text = ""


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
	_top_five_label.add_theme_color_override("font_color", primary)
	var style := StyleBoxFlat.new()
	style.bg_color = theme_node.color("object_pink")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_settings_button.add_theme_stylebox_override("normal", style)
	_settings_button.add_theme_stylebox_override("hover", style)
	_settings_button.add_theme_stylebox_override("pressed", style)
	_settings_button.add_theme_color_override("font_color", theme_node.color("text_on_color"))


func _on_name_changed(new_name: String) -> void:
	_refresh_name_ui(new_name)
	_refresh_avatar()


func _on_avatar_changed(_avatar_id: String) -> void:
	_refresh_avatar()


func show_menu() -> void:
	_dismissed = false
	visible = true
	_close_settings()
	var profile := get_node_or_null("/root/Profile")
	if profile != null:
		_refresh_name_ui(String(profile.player_name))
		_refresh_avatar()
	else:
		_refresh_name_ui("")
		_refresh_avatar()
	if _leaderboard != null and _leaderboard.has_method("fetch_top"):
		_leaderboard.fetch_top(5)


func is_capturing_name() -> bool:
	return _is_capturing_name()


func _on_board_updated(entries: Array, _total_players: int) -> void:
	_title_offline = false
	_render_top_five(entries)


func _on_offline(_reason: String) -> void:
	_title_offline = true
	var cached: Array = []
	if _leaderboard != null:
		cached = _leaderboard.last_entries
	_render_top_five(cached)


func _render_top_five(entries: Array) -> void:
	var lines: PackedStringArray = PackedStringArray()
	var shown := 0
	for entry_variant in entries:
		if shown >= 5:
			break
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var rank := int(entry.get("rank", shown + 1))
		var player_name := String(entry.get("name", ""))
		var score := int(entry.get("score", 0))
		lines.append("%d. %s  %d" % [rank, player_name, score])
		shown += 1
	if _title_offline:
		if lines.is_empty():
			_top_five_label.text = "Leaderboard offline"
		else:
			_top_five_label.text = "\n".join(lines) + "\nLeaderboard offline"
	else:
		_top_five_label.text = "\n".join(lines)


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


func _refresh_avatar() -> void:
	if _avatar_view == null:
		return
	var profile := get_node_or_null("/root/Profile")
	var id := ""
	if profile != null:
		id = String(profile.avatar_id)
	if id.is_empty():
		_avatar_view.texture = _placeholder_texture()
		return
	var path := SquishyCatalog.sprite_path(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		_avatar_view.texture = _placeholder_texture()
		return
	var tex := load(path) as Texture2D
	_avatar_view.texture = tex if tex != null else _placeholder_texture()


func _placeholder_texture() -> Texture2D:
	if _placeholder_avatar != null:
		return _placeholder_avatar
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.18, 0.16, 0.22, 0.9))
	_placeholder_avatar = ImageTexture.create_from_image(img)
	return _placeholder_avatar


func _open_settings() -> void:
	if _dismissed or _is_capturing_name() or _needs_name():
		return
	if _settings != null and _settings.has_method("open"):
		_settings.open()


func _close_settings() -> void:
	if _settings != null and _settings.has_method("close"):
		_settings.close()
	elif _settings != null:
		_settings.visible = false


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
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_S:
			_open_settings()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("change_name"):
		_name_entry.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("launch_ball"):
		_dismissed = true
		_close_settings()
		_name_entry.release_name_focus()
		_set_flippers_enabled(true)
		visible = false
