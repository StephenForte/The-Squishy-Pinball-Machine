extends SceneTree

## D-064. Restart, Menu and Not you? are a phone-sized 96 px, not the old
## full-canvas targets. Each state GameOver actually shows keeps them in
## range, clear of every other control, and above the floor. Pressed is a
## darker fill than normal; hover matches neither.

const MIN_PX := 48.0 * 720.0 / 375.0
const MAX_H := 100.0
const FLOOR_Y := 1150.0
const TARGET_H := 96.0
const NAMED_BUTTONS := ["RestartButton", "MenuButton", "NotYouButton"]
## Header labels already share an edge; active_player_test exempts that seam.
## Godot reports those rects a few pixels taller than the offsets.
const HEADER_SEAM := {
	"TitleLabel": true,
	"FinalScoreLabel": true,
	"GameOverHighScoreLabel": true,
	"NewHighScoreLabel": true,
	"YourRankLabel": true,
	"OfflineLabel": true,
}
## Save / Skip / Yes / No share _style_button. Their boxes must not move.
const UNTOUCHED := {
	"SaveButton": Vector2(140, 128),
	"SkipButton": Vector2(640, 124),
	"YesButton": Vector2(310, 128),
	"NoButton": Vector2(310, 128),
}

var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("GAMEOVER_BUTTONS start")
	DisplayServer.window_set_size(Vector2i(720, 1280))
	var game := root.get_node_or_null("Game")
	var profile := root.get_node_or_null("Profile")
	if game == null or profile == null:
		_fail("Game or Profile missing")
		return
	_reset_profile(profile)
	game.high_score = 0
	game.restart()
	await process_frame
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not change to main.tscn")
		return
	for _i in 4:
		await process_frame
	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)
	if not await _go_game_over(main, game, 500):
		return
	var panel := main.get_node_or_null("GameOver")
	if panel == null:
		_fail("GameOver missing")
		return
	if not _assert_state(panel, "invite"):
		return
	if not _assert_styles(panel):
		return
	if not _assert_untouched(panel):
		return
	if not _assert_not_you_fits(panel):
		return
	panel.call("_show_welcome", "Dad")
	await process_frame
	if not _assert_state(panel, "welcome"):
		return
	panel.call("_hide_invite")
	await process_frame
	if not _assert_state(panel, "closed"):
		return
	panel._bound_name = "Dad"
	panel._bound_id = "buttons-test-id"
	panel.call("_show_saving_line")
	await process_frame
	if not _assert_state(panel, "saving"):
		return
	var leaderboard := root.get_node_or_null("Leaderboard")
	if leaderboard == null:
		_fail("Leaderboard missing")
		return
	leaderboard.score_post_ids.append("buttons-test-id")
	panel.call("_show_saved_line", {"rank": 2, "total_players": 5})
	await process_frame
	if not _assert_state(panel, "saved"):
		return
	panel._last_submit = {}
	panel.call("_on_offline", "unreachable")
	await process_frame
	if not _assert_state(panel, "offline"):
		return
	print("GAMEOVER_BUTTONS PASS cases=%d" % _cases_passed)
	quit(0)


func _assert_state(panel: Node, state_name: String) -> bool:
	print("GAMEOVER_BUTTONS state %s" % state_name)
	var nodes := _visible_controls(panel)
	if nodes.is_empty():
		return _fail("%s: no visible controls" % state_name)
	var by_name := {}
	for node in nodes:
		by_name[String(node.name)] = node
		var rect: Rect2 = (node as Control).get_global_rect()
		if rect.position.y + rect.size.y > FLOOR_Y:
			return _fail("%s: %s extends below y=1150 %s" % [state_name, node.name, rect])
	for i in nodes.size():
		var left: Control = nodes[i]
		var left_rect := left.get_global_rect()
		for j in range(i + 1, nodes.size()):
			var right: Control = nodes[j]
			if _contains(left, right) or _contains(right, left):
				continue
			if HEADER_SEAM.has(String(left.name)) and HEADER_SEAM.has(String(right.name)):
				continue
			var shared := left_rect.intersection(right.get_global_rect())
			if shared.get_area() <= 0.5:
				continue
			return _fail("%s: %s %s overlaps %s %s" % [state_name, left.name, left_rect, right.name, right.get_global_rect()])
	for button_name in NAMED_BUTTONS:
		if not by_name.has(button_name):
			if button_name == "NotYouButton" and state_name != "saved":
				continue
			return _fail("%s: %s not visible" % [state_name, button_name])
		var button: Button = by_name[button_name]
		var rect := button.get_global_rect()
		if rect.size.y < MIN_PX or rect.size.y > MAX_H:
			return _fail("%s: %s height %.2f not in [%.2f, %.0f]" % [state_name, button_name, rect.size.y, MIN_PX, MAX_H])
		if abs(rect.size.y - TARGET_H) > 0.5:
			return _fail("%s: %s height %.2f is not %.0f" % [state_name, button_name, rect.size.y, TARGET_H])
		if rect.size.x < MIN_PX:
			return _fail("%s: %s width %.2f < %.2f" % [state_name, button_name, rect.size.x, MIN_PX])
		var font_size := button.get_theme_font_size("font_size")
		if font_size < 28 or font_size > 30:
			return _fail("%s: %s font %d not in 28-30" % [state_name, button_name, font_size])
	if by_name.has("NotYouButton"):
		var not_you: Button = by_name["NotYouButton"]
		var not_rect := not_you.get_global_rect()
		var center_x := not_rect.position.x + not_rect.size.x * 0.5
		if abs(center_x - 360.0) > 8.0:
			return _fail("%s: Not you? center x %.1f is not centred" % [state_name, center_x])
		if not_rect.size.x < 280.0 or not_rect.size.x > 400.0:
			return _fail("%s: Not you? width %.1f is not about half" % [state_name, not_rect.size.x])
		if by_name.has("SavedAsLabel"):
			var saved_rect: Rect2 = (by_name["SavedAsLabel"] as Control).get_global_rect()
			if not_rect.position.y + 0.5 < saved_rect.position.y + saved_rect.size.y:
				return _fail("%s: Not you? %s is not under SavedAs %s" % [state_name, not_rect, saved_rect])
	if by_name.has("HintLabel") and by_name.has("RestartButton"):
		var hint_rect: Rect2 = (by_name["HintLabel"] as Control).get_global_rect()
		var restart_rect: Rect2 = (by_name["RestartButton"] as Control).get_global_rect()
		if hint_rect.position.y + 0.5 < restart_rect.position.y + restart_rect.size.y:
			return _fail("%s: hint %s is not under Restart %s" % [state_name, hint_rect, restart_rect])
	_cases_passed += 1
	print("GAMEOVER_BUTTONS state %s pass" % state_name)
	return true


func _assert_styles(panel: Node) -> bool:
	var theme := root.get_node_or_null("Theme")
	if theme == null or not theme.has_method("color"):
		return _fail("Theme missing")
	var pink: Color = theme.color("object_pink")
	for button_name in NAMED_BUTTONS:
		var button := panel.get_node_or_null(button_name) as Button
		if button == null:
			return _fail("style: %s missing" % button_name)
		var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
		var hover := button.get_theme_stylebox("hover") as StyleBoxFlat
		var pressed := button.get_theme_stylebox("pressed") as StyleBoxFlat
		if normal == null or hover == null or pressed == null:
			return _fail("style: %s missing a StyleBoxFlat" % button_name)
		if normal.bg_color != pink:
			return _fail("style: %s normal %s is not object_pink %s" % [button_name, normal.bg_color, pink])
		if pressed.bg_color == normal.bg_color or pressed.bg_color.get_luminance() >= normal.bg_color.get_luminance():
			return _fail("style: %s pressed %s is not darker than normal %s" % [button_name, pressed.bg_color, normal.bg_color])
		if hover.bg_color == normal.bg_color or hover.bg_color == pressed.bg_color:
			return _fail("style: %s hover %s is not distinct" % [button_name, hover.bg_color])
		if normal.corner_radius_top_left <= 8:
			return _fail("style: %s corner radius %d is not larger than 8" % [button_name, normal.corner_radius_top_left])
		if normal.shadow_size <= 0 and normal.shadow_offset == Vector2.ZERO:
			return _fail("style: %s has no drop shadow" % button_name)
	_cases_passed += 1
	print("GAMEOVER_BUTTONS styles pass")
	return true


func _assert_untouched(panel: Node) -> bool:
	for button_name in UNTOUCHED:
		var button := panel.get_node_or_null(button_name) as Button
		if button == null:
			return _fail("untouched: %s missing" % button_name)
		var expected: Vector2 = UNTOUCHED[button_name]
		var size := button.get_global_rect().size
		if abs(size.x - expected.x) > 0.5 or abs(size.y - expected.y) > 0.5:
			return _fail("untouched: %s size %s changed from %s" % [button_name, size, expected])
	_cases_passed += 1
	print("GAMEOVER_BUTTONS untouched geometry pass")
	return true


func _assert_not_you_fits(panel: Node) -> bool:
	var button := panel.get_node_or_null("NotYouButton") as Button
	if button == null:
		return _fail("fit: NotYouButton missing")
	var font := button.get_theme_font("font")
	if font == null:
		return _fail("fit: Not you? has no font")
	var style := button.get_theme_stylebox("normal") as StyleBoxFlat
	if style == null:
		return _fail("fit: Not you? has no normal style")
	var text_w := font.get_string_size("Not you?", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var inner := button.get_global_rect().size.x - style.content_margin_left - style.content_margin_right
	if text_w + 1.0 > inner:
		return _fail("fit: 'Not you?' at font 30 is %.1f px in a %.1f px content box" % [text_w, inner])
	_cases_passed += 1
	print("GAMEOVER_BUTTONS not-you fit pass text=%.1f inner=%.1f" % [text_w, inner])
	return true


func _visible_controls(panel: Node) -> Array:
	var found: Array = []
	_collect_visible(panel, found)
	return found


func _collect_visible(node: Node, found: Array) -> void:
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control and String(child.name) != "Shade":
			found.append(child)
		_collect_visible(child, found)


func _contains(ancestor: Node, node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent == ancestor:
			return true
		parent = parent.get_parent()
	return false


func _go_game_over(main: Node, game: Node, points: int) -> bool:
	var title := main.get_node_or_null("Title")
	if title != null and title.visible:
		var play := title.get_node_or_null("PlayButton") as Button
		if play == null:
			return _fail("Play missing")
		play.pressed.emit()
		for _i in 8:
			await process_frame
		if title.visible:
			return _fail("could not leave the title")
	game.add_score(points)
	for _i in 3:
		game.on_ball_drained()
		await process_frame
	var panel := main.get_node_or_null("GameOver")
	if panel == null or not panel.visible or game.state != game.GAME_OVER:
		return _fail("expected GAME_OVER")
	return true


func _silence_table_drain(main: Node) -> void:
	var table := main.get_node_or_null("Table")
	if table == null:
		return
	var drain := table.get_node_or_null("Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _reset_profile(profile: Node) -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("profile.save"):
		dir.remove("profile.save")
	if profile.has_method("_load_or_create"):
		profile.call("_load_or_create")


func _fail(message: String) -> bool:
	push_error("GAMEOVER_BUTTONS FAIL %s" % message)
	print("GAMEOVER_BUTTONS FAIL %s" % message)
	quit(1)
	return false
