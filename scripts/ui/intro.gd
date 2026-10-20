extends CanvasLayer

## Full-screen "Ready Player One.." card (D-064). Shown when the title hides
## (Play / Space / tap) and when a restart leaves the title hidden. Menu and
## "Not you?" show the title, so the deferred restart check does not play.
## Input is swallowed on every path that can still reach the table: _input
## (before GUI and _unhandled_input), flipper physics polling, the launcher's
## _unhandled_input, and TouchControls via _blocked().

const FONT_PATH := "res://assets/fonts/PressStart2P-Latin.woff2"
const MESSAGE := "Ready Player One.."
const HOLD_SEC := 2.0
const FADE_SEC := 0.15
const FONT_PX := 32
const GOLD := Color(1.0, 210.0 / 255.0, 28.0 / 255.0, 1.0)
const LAYER_ABOVE_GAME_OVER := 30

var _showing := false
var _elapsed := 0.0
var _pending_restart := false
var _gameplay_blocked := false

@onready var _card: CanvasItem = $Card
@onready var _label: Label = $Card/Message


func _ready() -> void:
	layer = LAYER_ABOVE_GAME_OVER
	visible = false
	_style_message()
	_build_scanlines()
	var title := _title()
	if title != null and title.has_signal("visibility_changed"):
		if not title.visibility_changed.is_connected(_on_title_visibility_changed):
			title.visibility_changed.connect(_on_title_visibility_changed)
	var game := get_node_or_null("/root/Game")
	if game != null and game.has_signal("game_restarted"):
		if not game.game_restarted.is_connected(_on_game_restarted):
			game.game_restarted.connect(_on_game_restarted)


func _process(delta: float) -> void:
	if not _showing:
		return
	# A hitch must not skip the card. Fixed-fps tests step well under this.
	_elapsed += minf(delta, 0.05)
	var phase := fmod(_elapsed, 1.2)
	if _label != null:
		_label.modulate.a = 1.0 if phase < 0.6 else 0.4
	if _elapsed < HOLD_SEC:
		_set_card_alpha(1.0)
		return
	var fade := (_elapsed - HOLD_SEC) / FADE_SEC
	if fade >= 1.0:
		_finish()
		return
	_set_card_alpha(1.0 - fade)


func _input(event: InputEvent) -> void:
	if not _showing or not _is_blocked_event(event):
		return
	_release_blocked_press(event)
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _on_title_visibility_changed() -> void:
	var title := _title()
	if title != null and title.visible:
		_pending_restart = false
		if _showing:
			_finish()
		return
	# Title just hid. This runs inside the dismiss launch's _unhandled_input,
	# before the launcher (an earlier sibling) is notified. Marking the event
	# handled stops that same press from firing the ball.
	_pending_restart = false
	_begin(true)


func _on_game_restarted() -> void:
	# Menu and "Not you?" call restart() and then show the title. Defer so
	# that show lands before the check.
	_pending_restart = true
	call_deferred("_begin_if_title_hidden")


func _begin_if_title_hidden() -> void:
	if not _pending_restart:
		return
	_pending_restart = false
	var title := _title()
	if title != null and title.visible:
		return
	_begin(false)


func _begin(mark_handled: bool) -> void:
	_showing = true
	_elapsed = 0.0
	_set_card_alpha(1.0)
	if _label != null:
		_label.modulate.a = 1.0
	visible = true
	_block_gameplay(true)
	for action in _blocked_actions():
		if Input.is_action_pressed(action):
			Input.action_release(action)
	if mark_handled:
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _finish() -> void:
	var was_showing := _showing
	_showing = false
	_elapsed = 0.0
	visible = false
	_set_card_alpha(1.0)
	if _label != null:
		_label.modulate.a = 1.0
	if was_showing:
		_block_gameplay(false)


func _style_message() -> void:
	if _label == null:
		return
	_label.text = MESSAGE
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = load(FONT_PATH)
	if not (font is FontFile):
		push_error("Intro: Press Start 2P did not import from %s" % FONT_PATH)
		_label.text = ""
		return
	_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", FONT_PX)
	_label.add_theme_color_override("font_color", GOLD)
	_label.add_theme_color_override("font_outline_color", Color(GOLD.r, GOLD.g, GOLD.b, 0.9))
	_label.add_theme_color_override("font_shadow_color", Color(GOLD.r, GOLD.g, GOLD.b, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_constant_override("shadow_outline_size", 10)
	_label.add_theme_constant_override("shadow_offset_x", 0)
	_label.add_theme_constant_override("shadow_offset_y", 0)


func _build_scanlines() -> void:
	var scan := get_node_or_null("Card/Scanlines") as TextureRect
	if scan == null:
		return
	var image := Image.create(1, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.set_pixel(0, 0, Color(1, 1, 1, 0.035))
	scan.texture = ImageTexture.create_from_image(image)
	scan.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	scan.stretch_mode = TextureRect.STRETCH_TILE
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _block_gameplay(block: bool) -> void:
	if block == _gameplay_blocked:
		return
	_gameplay_blocked = block
	var main := get_parent()
	if main == null:
		return
	var flippers_on := not block
	if flippers_on and _title_capturing():
		flippers_on = false
	for path in ["Table/FlipperLeft", "Table/FlipperRight"]:
		var flipper := main.get_node_or_null(path)
		if flipper == null:
			continue
		if block and ("rest_rad" in flipper) and ("angle" in flipper):
			var rest := float(flipper.rest_rad)
			flipper.angle = rest
			flipper.rotation = rest
		flipper.set_physics_process(flippers_on)
	var launcher := main.get_node_or_null("Table/Launcher")
	if launcher != null:
		launcher.set_process_unhandled_input(not block)


func _is_blocked_event(event: InputEvent) -> bool:
	for action in _blocked_actions():
		if event.is_action(action):
			return true
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return (
			code == KEY_SPACE
			or code == KEY_A
			or code == KEY_D
			or code == KEY_LEFT
			or code == KEY_RIGHT
			or code == KEY_R
			or code == KEY_ESCAPE
		)
	return (
		event is InputEventScreenTouch
		or event is InputEventScreenDrag
		or event is InputEventMouseButton
	)


func _release_blocked_press(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	for action in _blocked_actions():
		if event.is_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)


func _blocked_actions() -> Array[StringName]:
	return [
		&"launch_ball",
		&"flipper_left",
		&"flipper_right",
		&"restart",
		&"menu",
	]


func _set_card_alpha(alpha: float) -> void:
	if _card != null:
		_card.modulate.a = alpha


func _title() -> Node:
	var main := get_parent()
	if main == null:
		return null
	return main.get_node_or_null("Title")


func _title_capturing() -> bool:
	var title := _title()
	return title != null and title.has_method("is_capturing_name") and bool(title.is_capturing_name())
