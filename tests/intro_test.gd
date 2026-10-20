extends SceneTree

## D-064. The dismiss press must not launch, and nothing played during the card
## may move a flipper, launch, restart, or return to the title.

const SPAWN := Vector2(666, 1219)
const TOL := 2.0
const FONT_PATH := "res://assets/fonts/PressStart2P-Latin.woff2"

var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("INTRO start")
	DisplayServer.window_set_size(Vector2i(720, 1280))
	var game := root.get_node_or_null("Game")
	var profile := root.get_node_or_null("Profile")
	if game == null or profile == null:
		_fail("could not acquire Game or Profile")
		return
	if String(profile.player_name).is_empty():
		profile.call("set_name", "Dad")
	game.high_score = 0
	game.restart()
	await process_frame

	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("main scene did not load")
		return
	await process_frame
	await process_frame
	await process_frame
	var main := current_scene
	if main == null:
		_fail("main scene did not load")
		return
	_silence_table_drain(main)

	if not await _case_boot(main):
		return
	if not _case_font(main):
		return
	if not await _case_play_blocks_then_ends(main, game):
		return
	if not await _case_space_and_touch(main):
		return
	if not await _case_restart_button(main, game):
		return
	if not await _case_restart_key(main, game):
		return
	if not await _case_menu_button(main, game):
		return
	if not await _case_escape(main, game):
		return
	if not await _case_not_you(main, game):
		return

	await _save_shot(main)
	print("INTRO PASS cases=%d" % _cases_passed)
	quit(0)


func _case_boot(main: Node) -> bool:
	print("INTRO case 1 boot")
	var title := main.get_node_or_null("Title")
	var intro := main.get_node_or_null("Intro")
	if title == null or intro == null:
		return _fail("case 1: Title or Intro missing")
	if not title.visible:
		return _fail("case 1: Title should be visible at boot")
	if intro.visible:
		return _fail("case 1: Intro should be hidden at boot")
	if int(intro.get("layer")) <= 20:
		return _fail("case 1: Intro layer %s is not above GameOver" % intro.get("layer"))
	_cases_passed += 1
	print("INTRO case 1 pass")
	return true


func _case_font(main: Node) -> bool:
	print("INTRO case 2 font")
	var label := main.get_node_or_null("Intro/Card/Message") as Label
	if label == null:
		return _fail("case 2: Message label missing")
	if label.text != "Ready Player One..":
		return _fail("case 2: text is '%s'" % label.text)
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return _fail("case 2: label wraps")
	var font := label.get_theme_font("font")
	if not (font is FontFile):
		return _fail("case 2: font is not a FontFile (%s)" % font)
	var path := String((font as FontFile).resource_path)
	if path != FONT_PATH:
		return _fail("case 2: font path %s" % path)
	var px := label.get_theme_font_size("font_size")
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var viewport := _viewport_width(main)
	print("INTRO case 2 width=%s px=%s viewport=%s" % [width, px, viewport])
	if width > viewport - 80.0:
		return _fail("case 2: text width %s exceeds viewport %s minus 80" % [width, viewport])
	if px > 32:
		return _fail("case 2: font size %s is above 32" % px)
	_cases_passed += 1
	print("INTRO case 2 pass")
	return true


func _case_play_blocks_then_ends(main: Node, game: Node) -> bool:
	print("INTRO case 3 Play blocks input, then the card ends")
	var title := main.get_node_or_null("Title")
	var intro := main.get_node_or_null("Intro")
	var play := main.get_node_or_null("Title/PlayButton") as Button
	if title == null or intro == null or play == null:
		return _fail("case 3: Title, Intro, or PlayButton missing")
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	var state_before: int = game.state
	play.pressed.emit()
	await process_frame
	if title.visible:
		return _fail("case 3: Play left the title up")
	if not intro.visible:
		return _fail("case 3: Play did not show the intro")
	if bool(ball.get("launched")):
		return _fail("case 3: Play launched the ball")
	if not _near_spawn(ball):
		return _fail("case 3: ball left the lane at %s" % (ball as Node2D).global_position)

	var pos_before := (ball as Node2D).global_position
	var angles_before := _flip_angles(main)
	if not await _reject_input(main, game, ball, pos_before, angles_before, state_before):
		return false
	if not intro.visible:
		return _fail("case 3: intro ended during the input barrage")
	if not is_instance_valid(ball) or bool(ball.get("launched")) or not _near_spawn(ball):
		return _fail("case 3: ball moved while the card was up")

	# Barrage above already spent part of the 2.15 s. The rest must still be
	# long enough that this is the card, not a flash, and short enough to end.
	var extra := 0
	while intro.visible and extra < 340:
		await physics_frame
		extra += 1
	print("INTRO case 3 cleared after %d more frames" % extra)
	if intro.visible:
		return _fail("case 3: intro still up")
	if extra < 100:
		return _fail("case 3: intro cleared too soon (%d frames after the barrage)" % extra)
	if not is_instance_valid(ball) or bool(ball.get("launched")) or not _near_spawn(ball):
		return _fail("case 3: ball was not waiting in the lane after the card")
	if game.state != state_before:
		return _fail("case 3: state changed across the card (%s -> %s)" % [state_before, game.state])

	_push_action(main, "launch_ball")
	var launched := false
	for _i in 8:
		await physics_frame
		if is_instance_valid(ball) and bool(ball.get("launched")):
			launched = true
			break
	_push_action(main, "launch_ball", false)
	if not launched:
		return _fail("case 3: a launch after the card did not fire")
	_cases_passed += 1
	print("INTRO case 3 pass")
	return true


func _case_space_and_touch(main: Node) -> bool:
	print("INTRO case 4 Space and touch")
	if not await _back_to_title(main):
		return false
	var title := main.get_node_or_null("Title")
	var intro := main.get_node_or_null("Intro")
	var ball := await _wait_lane_ball(main)
	if title == null or intro == null or ball == null:
		return false
	_push_action(main, "launch_ball")
	await process_frame
	_push_action(main, "launch_ball", false)
	if title.visible or not intro.visible:
		return _fail("case 4: Space did not swap the title for the intro")
	if bool(ball.get("launched")) or not _near_spawn(ball):
		return _fail("case 4: Space launched the ball")
	if not await _back_to_title(main):
		return false

	ball = await _wait_lane_ball(main)
	if ball == null:
		return false
	_touch(0, Vector2(360, 200), true)
	_touch(0, Vector2(360, 200), false)
	await process_frame
	await physics_frame
	if title.visible or not intro.visible:
		return _fail("case 4: tap did not swap the title for the intro")
	if bool(ball.get("launched")) or not _near_spawn(ball):
		return _fail("case 4: tap launched the ball")
	if not await _back_to_title(main):
		return false
	_cases_passed += 1
	print("INTRO case 4 pass")
	return true


func _case_restart_button(main: Node, game: Node) -> bool:
	print("INTRO case 5 Restart button")
	if not await _leave_title_without_waiting(main):
		return false
	if not await _to_game_over(game):
		return false
	var game_over := main.get_node_or_null("GameOver")
	var restart := game_over.get_node_or_null("RestartButton") if game_over != null else null
	if restart == null or not (restart is Button):
		return _fail("case 5: RestartButton missing")
	(restart as Button).pressed.emit()
	await process_frame
	await process_frame
	var intro := main.get_node_or_null("Intro")
	var title := main.get_node_or_null("Title")
	if intro == null or not intro.visible:
		return _fail("case 5: Restart button did not show the intro")
	if title != null and title.visible:
		return _fail("case 5: Title came back with Restart")
	var ball := await _wait_lane_ball(main)
	if ball == null:
		return false
	if bool(ball.get("launched")) or not _near_spawn(ball):
		return _fail("case 5: restart ball is not waiting at %s" % (ball as Node2D).global_position)
	if not await _back_to_title(main):
		return false
	_cases_passed += 1
	print("INTRO case 5 pass")
	return true


func _case_restart_key(main: Node, game: Node) -> bool:
	print("INTRO case 6 R")
	if not await _leave_title_without_waiting(main):
		return false
	if not await _to_game_over(game):
		return false
	_key(KEY_R, true)
	await process_frame
	await process_frame
	_key(KEY_R, false)
	var intro := main.get_node_or_null("Intro")
	var title := main.get_node_or_null("Title")
	if intro == null or not intro.visible:
		return _fail("case 6: R did not show the intro")
	if title != null and title.visible:
		return _fail("case 6: Title came back with R")
	if not await _back_to_title(main):
		return false
	_cases_passed += 1
	print("INTRO case 6 pass")
	return true


func _case_menu_button(main: Node, game: Node) -> bool:
	print("INTRO case 7 Menu button")
	if not await _leave_title_without_waiting(main):
		return false
	if not await _to_game_over(game):
		return false
	var game_over := main.get_node_or_null("GameOver")
	var menu := game_over.get_node_or_null("MenuButton") if game_over != null else null
	if menu == null or not (menu is Button):
		return _fail("case 7: MenuButton missing")
	(menu as Button).pressed.emit()
	await process_frame
	await process_frame
	var title := main.get_node_or_null("Title")
	var intro := main.get_node_or_null("Intro")
	if title == null or not title.visible:
		return _fail("case 7: Menu button did not show the title")
	if intro != null and intro.visible:
		return _fail("case 7: Menu button showed the intro")
	_cases_passed += 1
	print("INTRO case 7 pass")
	return true


func _case_escape(main: Node, game: Node) -> bool:
	print("INTRO case 8 Esc")
	if not await _leave_title_without_waiting(main):
		return false
	if not await _to_game_over(game):
		return false
	_key(KEY_ESCAPE, true)
	await process_frame
	await process_frame
	_key(KEY_ESCAPE, false)
	var title := main.get_node_or_null("Title")
	var intro := main.get_node_or_null("Intro")
	if title == null or not title.visible:
		return _fail("case 8: Esc did not show the title")
	if intro != null and intro.visible:
		return _fail("case 8: Esc showed the intro")
	_cases_passed += 1
	print("INTRO case 8 pass")
	return true


func _case_not_you(main: Node, game: Node) -> bool:
	print("INTRO case 9 Not you")
	if not await _leave_title_without_waiting(main):
		return false
	if not await _to_game_over(game):
		return false
	var game_over := main.get_node_or_null("GameOver")
	var not_you := game_over.get_node_or_null("NotYouButton") if game_over != null else null
	if not_you == null or not (not_you is Button):
		return _fail("case 9: NotYouButton missing")
	(not_you as Button).pressed.emit()
	await process_frame
	await process_frame
	var title := main.get_node_or_null("Title")
	var intro := main.get_node_or_null("Intro")
	if title == null or not title.visible:
		return _fail("case 9: Not you did not show the title")
	if intro != null and intro.visible:
		return _fail("case 9: Not you showed the intro")
	_cases_passed += 1
	print("INTRO case 9 pass")
	return true


func _reject_input(
	main: Node,
	game: Node,
	ball: Node,
	pos_before: Vector2,
	angles_before: Vector2,
	state_before: int
) -> bool:
	var probes: Array[Dictionary] = [
		{"kind": "action", "action": &"launch_ball"},
		{"kind": "key", "key": KEY_SPACE},
		{"kind": "touch", "pos": Vector2(360, 200)},
		{"kind": "key", "key": KEY_A},
		{"kind": "key", "key": KEY_D},
		{"kind": "key", "key": KEY_LEFT},
		{"kind": "key", "key": KEY_RIGHT},
		{"kind": "action", "action": &"flipper_left"},
		{"kind": "action", "action": &"flipper_right"},
		{"kind": "touch", "pos": Vector2(180, 960)},
		{"kind": "touch", "pos": Vector2(540, 960)},
		{"kind": "action", "action": &"restart"},
		{"kind": "key", "key": KEY_R},
		{"kind": "action", "action": &"menu"},
		{"kind": "key", "key": KEY_ESCAPE},
	]
	for probe in probes:
		var kind := String(probe.get("kind", ""))
		print("INTRO block %s" % probe)
		if kind == "action":
			_push_action(main, probe["action"])
		elif kind == "key":
			_key(int(probe["key"]), true)
		else:
			_touch(9, probe["pos"], true)
		for _i in 4:
			await physics_frame
		if kind == "action":
			_push_action(main, probe["action"], false)
		elif kind == "key":
			_key(int(probe["key"]), false)
		else:
			_touch(9, probe["pos"], false)
		await physics_frame
		if not is_instance_valid(ball):
			return _fail("input %s freed the ball" % probe)
		var pos := (ball as Node2D).global_position
		if pos.distance_to(pos_before) > TOL:
			return _fail("input %s moved the ball to %s" % [probe, pos])
		var angles := _flip_angles(main)
		if absf(angles.x - angles_before.x) > 0.01 or absf(angles.y - angles_before.y) > 0.01:
			return _fail("input %s moved a flipper to %s" % [probe, angles])
		if game.state != state_before:
			return _fail("input %s changed state to %s" % [probe, game.state])
		var title := main.get_node_or_null("Title")
		if title != null and title.visible:
			return _fail("input %s brought the title back" % probe)
	return true


func _leave_title_without_waiting(main: Node) -> bool:
	# The card is already proven to time out. Later cases only need the title
	# gone, so a direct return is not used — Play shows the card, and Menu
	# from inside it is blocked. Hide by playing, then step the card off by
	# asking the title to return once the card's own gate is what we are not
	# testing. Callers that need a hidden title with no card use the restart
	# path below: dismiss, then restart is the thing under test.
	var title := main.get_node_or_null("Title")
	var intro := main.get_node_or_null("Intro")
	if title == null:
		return _fail("title missing")
	if not title.visible:
		if intro != null and intro.visible:
			return await _wait_clear(intro)
		return true
	var play := title.get_node_or_null("PlayButton") as Button
	if play == null:
		return _fail("PlayButton missing")
	play.pressed.emit()
	await process_frame
	if title.visible:
		return _fail("could not leave the title")
	return await _wait_clear(intro)


func _to_game_over(game: Node) -> bool:
	if game.state == game.GAME_OVER:
		return true
	for _i in 3:
		game.on_ball_drained()
		await physics_frame
		await process_frame
	if game.state != game.GAME_OVER:
		return _fail("expected GAME_OVER, got %s" % game.state)
	return true


func _back_to_title(main: Node) -> bool:
	if main.has_method("return_to_menu"):
		main.return_to_menu()
	await process_frame
	await process_frame
	var title := main.get_node_or_null("Title")
	var intro := main.get_node_or_null("Intro")
	if title == null or not title.visible:
		return _fail("title did not return")
	if intro != null and intro.visible:
		return _fail("intro stayed up after returning to the title")
	return true


func _wait_clear(intro: Node) -> bool:
	if intro == null:
		return true
	var frames := 0
	while intro.visible and frames < 400:
		await physics_frame
		frames += 1
	if intro.visible:
		return _fail("intro did not clear")
	return true


func _near_spawn(ball: Node) -> bool:
	if not (ball is Node2D):
		return false
	return (ball as Node2D).global_position.distance_to(SPAWN) <= TOL


func _flip_angles(main: Node) -> Vector2:
	var left := main.get_node_or_null("Table/FlipperLeft") as Node2D
	var right := main.get_node_or_null("Table/FlipperRight") as Node2D
	var lx := left.rotation if left != null else 0.0
	var rx := right.rotation if right != null else 0.0
	return Vector2(lx, rx)


func _viewport_width(main: Node) -> float:
	var viewport := main.get_viewport()
	if viewport == null:
		return 720.0
	var width := viewport.get_visible_rect().size.x
	if width < 80.0:
		return 720.0
	return width


func _save_shot(main: Node) -> void:
	var path := OS.get_environment("INTRO_SHOT")
	if path.is_empty():
		return
	var intro := main.get_node_or_null("Intro")
	var title := main.get_node_or_null("Title")
	if title != null and title.visible:
		var play := title.get_node_or_null("PlayButton") as Button
		if play != null:
			play.pressed.emit()
	# frame_post_draw does not arrive under --fixed-fps -s, and awaiting it
	# hangs the runner. A couple of process frames is enough for the card.
	for _i in 3:
		await process_frame
	var viewport := main.get_viewport()
	if viewport == null or intro == null or not intro.visible:
		print("INTRO shot skipped")
		return
	RenderingServer.force_draw()
	var image := viewport.get_texture().get_image()
	if image == null:
		print("INTRO shot empty")
		return
	image.save_png(path)
	print("INTRO shot %s" % path)


func _wait_lane_ball(main: Node) -> Node:
	var ball: Node = null
	for _i in 30:
		for node in get_nodes_in_group("ball"):
			if node is Node2D and is_instance_valid(node) and not node.is_queued_for_deletion():
				var pos: Vector2 = (node as Node2D).global_position
				if pos.x > 620.0 and pos.y > 1100.0:
					ball = node
					break
		if ball != null:
			break
		await physics_frame
	if ball == null:
		_fail("no lane ball")
		return null
	var guard := 0
	while is_instance_valid(ball) and not bool(ball.get("_ccd_ready")) and guard < 20:
		await physics_frame
		guard += 1
	return ball if is_instance_valid(ball) else null


func _silence_table_drain(main: Node) -> void:
	var drain := main.get_node_or_null("Table/Drain")
	if drain != null and drain is Area2D:
		(drain as Area2D).monitoring = false


func _push_action(main: Node, action: StringName, pressed: bool = true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	var viewport := main.get_viewport()
	if viewport != null:
		viewport.push_input(event)


func _key(physical: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.pressed = pressed
	event.echo = false
	event.physical_keycode = physical
	event.keycode = physical
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _fail(message: String) -> bool:
	push_error("INTRO FAIL %s" % message)
	print("INTRO FAIL %s" % message)
	quit(1)
	return false
