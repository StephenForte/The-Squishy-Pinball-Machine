extends SceneTree

const BALL_SCENE := preload("res://scenes/ball.tscn")
const EXPECTED_HITS := [100, 200, 300, 400, 500, 500]
const SHAKE_FRAMES := 36

var _game: Node
var _table: Node2D
var _hud: Node
var _streak_label: Label
var _effects: Node2D
var _camera: Camera2D
var _fireworks: CPUParticles2D
var _cases_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load scenes/main.tscn")
		return
	await process_frame
	await physics_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("Game autoload missing")
		return
	_table = current_scene.get_node_or_null("Table")
	_hud = current_scene.get_node_or_null("HUD")
	if _table == null or _hud == null:
		_fail("Table or HUD missing on main.tscn")
		return
	_streak_label = _hud.get_node_or_null("StreakLabel") as Label
	_effects = _table.get_node_or_null("Effects") as Node2D
	if _streak_label == null or _effects == null:
		_fail("StreakLabel or Effects missing")
		return
	_camera = _effects.get_node_or_null("Camera2D") as Camera2D
	_fireworks = _effects.get_node_or_null("Fireworks") as CPUParticles2D
	if _camera == null or _fireworks == null:
		_fail("Camera2D or Fireworks missing on Effects")
		return
	if not _camera.enabled or not _camera.is_current():
		_fail("Camera2D must be enabled and current")
		return

	if not await _case_1_cap():
		return
	if not await _case_2_window():
		return
	if not await _case_3_reset():
		return
	if not await _case_4_big_score():
		return
	if not await _case_5_shake():
		return

	print("STREAK PASS cases=%d" % _cases_passed)
	quit(0)


func _case_1_cap() -> bool:
	_game.restart()
	await process_frame
	var seen: Array[int] = []
	var on_streak := func(streak: int) -> void:
		seen.append(streak)
	_game.streak_changed.connect(on_streak)
	var awarded: Array[int] = []
	for _i in EXPECTED_HITS.size():
		awarded.append(int(_game.register_bumper_hit()))
		await _wait_sec(0.5)
	_game.streak_changed.disconnect(on_streak)
	if awarded != EXPECTED_HITS:
		return _fail("case 1: returns %s expected %s" % [awarded, EXPECTED_HITS])
	for n in range(1, 6):
		if not seen.has(n):
			return _fail("case 1: streak_changed missing %d, seen=%s" % [n, seen])
	if int(_game.streak) != 5:
		return _fail("case 1: streak %d expected 5" % _game.streak)
	if int(_game.score) != 2000:
		return _fail("case 1: score %d expected 2000" % _game.score)
	await process_frame
	if not _streak_label.visible or _streak_label.text != "x5":
		return _fail(
			"case 1: StreakLabel visible=%s text='%s' expected x5"
			% [_streak_label.visible, _streak_label.text]
		)
	_cases_passed += 1
	print("STREAK case 1 pass")
	return true


func _case_2_window() -> bool:
	await _wait_sec(2.1)
	await process_frame
	if int(_game.streak) != 0:
		return _fail("case 2: streak %d after 2.1s, expected 0" % _game.streak)
	var points := int(_game.register_bumper_hit())
	await process_frame
	if points != 100:
		return _fail("case 2: hit after expiry returned %d, expected 100" % points)
	if int(_game.streak) != 1:
		return _fail("case 2: streak %d expected 1" % _game.streak)
	if _streak_label.visible:
		return _fail("case 2: StreakLabel should be hidden at streak 1")
	_cases_passed += 1
	print("STREAK case 2 pass")
	return true


func _case_3_reset() -> bool:
	_game.restart()
	await process_frame
	_game.register_bumper_hit()
	_game.register_bumper_hit()
	_game.register_bumper_hit()
	if int(_game.streak) != 3:
		return _fail("case 3: setup streak %d expected 3" % _game.streak)
	_game.on_ball_drained()
	await process_frame
	if int(_game.streak) != 0:
		return _fail("case 3: drain left streak %d, expected 0" % _game.streak)
	_game.register_bumper_hit()
	_game.register_bumper_hit()
	_game.register_bumper_hit()
	if int(_game.streak) != 3:
		return _fail("case 3: restreak %d expected 3" % _game.streak)
	_game.restart()
	await process_frame
	if int(_game.streak) != 0:
		return _fail("case 3: restart left streak %d, expected 0" % _game.streak)
	if _streak_label.visible:
		return _fail("case 3: StreakLabel still visible after restart")
	_cases_passed += 1
	print("STREAK case 3 pass")
	return true


func _case_4_big_score() -> bool:
	_game.restart()
	await process_frame
	var emits: Array[int] = []
	var on_big := func(score: int) -> void:
		emits.append(score)
	_game.big_score_reached.connect(on_big)
	_game.add_score(9900)
	await process_frame
	if not emits.is_empty():
		_game.big_score_reached.disconnect(on_big)
		return _fail("case 4: big_score_reached at 9900, emits=%s" % [emits])
	var points := int(_game.register_bumper_hit())
	await process_frame
	if points != 100:
		_game.big_score_reached.disconnect(on_big)
		return _fail("case 4: bumper after 9900 returned %d, expected 100" % points)
	if emits.size() != 1 or emits[0] < 10000:
		_game.big_score_reached.disconnect(on_big)
		return _fail("case 4: expected one emit >= 10000, got %s" % [emits])
	if not _fireworks.emitting:
		_game.big_score_reached.disconnect(on_big)
		return _fail("case 4: Fireworks not emitting after big_score_reached")
	_game.add_score(500)
	_game.register_bumper_hit()
	await process_frame
	if emits.size() != 1:
		_game.big_score_reached.disconnect(on_big)
		return _fail("case 4: further scoring re-emitted, emits=%s" % [emits])
	_game.restart()
	await process_frame
	_game.add_score(10000)
	await process_frame
	_game.big_score_reached.disconnect(on_big)
	if emits.size() != 2 or emits[1] < 10000:
		return _fail("case 4: restart then 10000 should emit again, emits=%s" % [emits])
	if not _fireworks.emitting:
		return _fail("case 4: Fireworks not emitting on second game")
	_cases_passed += 1
	print("STREAK case 4 pass")
	return true


func _case_5_shake() -> bool:
	_game.restart()
	await process_frame
	await _free_balls()
	var ball := BALL_SCENE.instantiate() as RigidBody2D
	var spawn := Vector2(360, 640)
	ball.position = spawn
	ball.freeze = true
	_table.add_child(ball)
	await physics_frame
	ball.freeze = true
	ball.sleeping = true
	PhysicsServer2D.body_set_state(
		ball.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, spawn)
	)
	await physics_frame
	var ball_before := ball.global_position
	var table_before := _table.global_position
	var walls_before: Vector2 = (_table.get_node("Walls") as Node2D).global_position
	var bumper_before: Vector2 = (_table.get_node("Bumper1") as Node2D).global_position
	_effects.shake()
	var saw_offset := false
	for _i in SHAKE_FRAMES:
		await process_frame
		if _camera.offset != Vector2.ZERO:
			saw_offset = true
	if not is_instance_valid(ball):
		return _fail("case 5: frozen ball was freed")
	if ball.global_position != ball_before:
		return _fail(
			"case 5: ball moved during shake %s → %s" % [ball_before, ball.global_position]
		)
	if _table.global_position != table_before:
		return _fail("case 5: Table moved during shake")
	if (_table.get_node("Walls") as Node2D).global_position != walls_before:
		return _fail("case 5: Walls moved during shake")
	if (_table.get_node("Bumper1") as Node2D).global_position != bumper_before:
		return _fail("case 5: Bumper1 moved during shake")
	if not saw_offset:
		return _fail("case 5: Camera2D.offset never left zero")
	if _camera.offset != Vector2.ZERO:
		return _fail("case 5: Camera2D.offset %s did not return to zero" % _camera.offset)
	_cases_passed += 1
	print("STREAK case 5 pass")
	return true


func _wait_sec(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await process_frame
		var node := current_scene
		if node != null:
			elapsed += node.get_process_delta_time()
		else:
			elapsed += 1.0 / 120.0


func _free_balls() -> void:
	for node in get_nodes_in_group("ball"):
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _fail(message: String) -> bool:
	push_error("STREAK FAIL %s" % message)
	print("STREAK FAIL %s" % message)
	quit(1)
	return false
