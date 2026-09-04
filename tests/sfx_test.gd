extends SceneTree

const BALL_SCENE := preload("res://scenes/ball.tscn")
const DROP_ABOVE := 60.0
const CONTACT_WAIT := 180
const SETTLE_FRAMES := 30
const HOLD_FRAMES := 20
const WIRE_WAIT := 180

var _game: Node
var _sfx: Node
var _table: Node2D
var _bank: Node
var _events_passed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_sfx = root.get_node_or_null("Sfx")
	if _sfx == null:
		_fail("Sfx autoload missing")
		return
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load scenes/main.tscn")
		return
	await process_frame
	await physics_frame
	if not await _wait_wired():
		return
	_game = root.get_node_or_null("Game")
	_table = current_scene.get_node_or_null("Table")
	if _game == null or _table == null:
		_fail("Game or Table missing")
		return
	_bank = _table.get_node_or_null("TargetBank")
	if _bank == null:
		_fail("TargetBank missing")
		return

	_release_flippers()
	_sfx.reset_counts()

	if not await _case_wavs():
		return
	if not await _case_bumper():
		return
	if not await _case_target():
		return
	if not await _case_all_targets():
		return
	if not await _case_drains():
		return
	if not await _case_big_score():
		return
	if not await _case_flipper():
		return

	print("SFX PASS events=%d" % _events_passed)
	quit(0)


func _wait_wired() -> bool:
	for _i in WIRE_WAIT:
		if bool(_sfx.table_wired):
			return true
		await process_frame
	return _fail("Sfx did not wire bumpers/targets in time")


func _case_wavs() -> bool:
	var dir := DirAccess.open("res://assets/sfx")
	if dir == null:
		return _fail("assets/sfx missing")
	dir.list_dir_begin()
	var found := 0
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".wav"):
			var stream: Resource = load("res://assets/sfx/%s" % fname)
			if not stream is AudioStreamWAV:
				return _fail("wav %s is not AudioStreamWAV" % fname)
			if (stream as AudioStreamWAV).get_length() <= 0.0:
				return _fail("wav %s has length 0" % fname)
			found += 1
		fname = dir.get_next()
	if found < 7:
		return _fail("expected >=7 wavs, found %d" % found)
	print("SFX wavs pass count=%d" % found)
	return true


func _case_bumper() -> bool:
	_game.restart()
	await process_frame
	await physics_frame
	_sfx.reset_counts()
	var bumpers := get_nodes_in_group("bumpers")
	if bumpers.is_empty():
		return _fail("bumper: no bumpers")
	if not await _drop_on_bumper(bumpers[0] as Node2D):
		return false
	for _i in SETTLE_FRAMES:
		await physics_frame
	if _sfx.count_of("bumper") != 1:
		return _fail("bumper: plays=%d expected 1" % _sfx.count_of("bumper"))
	if not _sfx.last_stream.get("bumper") is AudioStreamWAV:
		return _fail("bumper: last_stream is not AudioStreamWAV")
	_events_passed += 1
	print("SFX bumper pass plays=1")
	return true


func _drop_on_bumper(bumper: Node2D) -> bool:
	await _free_balls()
	var ball := await _spawn_ball(bumper.global_position + Vector2(0, -DROP_ABOVE), Vector2.ZERO)
	if ball == null:
		return _fail("bumper: no ball above %s" % bumper.global_position)
	for _i in CONTACT_WAIT:
		await physics_frame
		if _sfx.count_of("bumper") >= 1:
			return true
	return _fail("bumper: no scored hit at %s" % bumper.global_position)


func _case_target() -> bool:
	_game.restart()
	await process_frame
	await physics_frame
	for target in _bank_targets():
		target.reset()
	_sfx.reset_counts()
	var targets := _bank_targets()
	if targets.is_empty():
		return _fail("target: no targets")
	if not await _drive_into_target(targets[0]):
		return false
	for _i in SETTLE_FRAMES:
		await physics_frame
	if _sfx.count_of("target") != 1:
		return _fail("target: plays=%d expected 1" % _sfx.count_of("target"))
	if not _sfx.last_stream.get("target") is AudioStreamWAV:
		return _fail("target: last_stream is not AudioStreamWAV")
	_events_passed += 1
	print("SFX target pass plays=1")
	return true


func _drive_into_target(target: Node) -> bool:
	await _free_balls()
	var node := target as Node2D
	var inward := Vector2(360, 640) - node.global_position
	if inward.length_squared() < 0.0001:
		inward = Vector2.DOWN
	inward = inward.normalized()
	var pos := node.global_position + inward * 52.0
	var ball := await _spawn_ball(pos, -inward * 520.0)
	if ball == null:
		return _fail("target: no ball at %s" % node.global_position)
	for _i in CONTACT_WAIT:
		await physics_frame
		if _sfx.count_of("target") >= 1:
			return true
	return _fail("target: no hit at %s" % node.global_position)


func _case_all_targets() -> bool:
	_game.restart()
	await process_frame
	_sfx.reset_counts()
	_bank.all_targets_hit.emit()
	await process_frame
	if _sfx.count_of("all_targets") != 1:
		return _fail("all_targets: plays=%d expected 1" % _sfx.count_of("all_targets"))
	if not _sfx.last_stream.get("all_targets") is AudioStreamWAV:
		return _fail("all_targets: last_stream is not AudioStreamWAV")
	_events_passed += 1
	print("SFX all_targets pass plays=1")
	return true


func _case_drains() -> bool:
	_game.restart()
	await process_frame
	_sfx.reset_counts()
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	await physics_frame
	_game.on_ball_drained()
	await process_frame
	if _sfx.count_of("drain") != 3:
		return _fail("drain: plays=%d expected 3" % _sfx.count_of("drain"))
	if _sfx.count_of("game_over") != 1:
		return _fail("game_over: plays=%d expected 1" % _sfx.count_of("game_over"))
	if not _sfx.last_stream.get("drain") is AudioStreamWAV:
		return _fail("drain: last_stream is not AudioStreamWAV")
	if not _sfx.last_stream.get("game_over") is AudioStreamWAV:
		return _fail("game_over: last_stream is not AudioStreamWAV")
	_events_passed += 2
	print("SFX drains pass drain=3 game_over=1")
	return true


func _case_big_score() -> bool:
	_game.restart()
	await process_frame
	_sfx.reset_counts()
	_game.add_score(10000)
	await process_frame
	if _sfx.count_of("big_score") != 1:
		return _fail("big_score: plays=%d expected 1" % _sfx.count_of("big_score"))
	if not _sfx.last_stream.get("big_score") is AudioStreamWAV:
		return _fail("big_score: last_stream is not AudioStreamWAV")
	_game.add_score(500)
	await process_frame
	if _sfx.count_of("big_score") != 1:
		return _fail("big_score: re-fired, plays=%d" % _sfx.count_of("big_score"))
	_events_passed += 1
	print("SFX big_score pass plays=1")
	return true


func _case_flipper() -> bool:
	_release_flippers()
	await process_frame
	_sfx.reset_counts()
	Input.action_press("flipper_left")
	await process_frame
	if _sfx.count_of("flipper") != 1:
		_release_flippers()
		return _fail("flipper: press plays=%d expected 1" % _sfx.count_of("flipper"))
	for _i in HOLD_FRAMES:
		await process_frame
	if _sfx.count_of("flipper") != 1:
		_release_flippers()
		return _fail("flipper: hold extra plays=%d" % _sfx.count_of("flipper"))
	Input.action_release("flipper_left")
	await process_frame
	Input.action_press("flipper_right")
	await process_frame
	var after_right: int = _sfx.count_of("flipper")
	_release_flippers()
	if after_right != 2:
		return _fail("flipper: second press plays=%d expected 2" % after_right)
	if not _sfx.last_stream.get("flipper") is AudioStreamWAV:
		return _fail("flipper: last_stream is not AudioStreamWAV")
	_events_passed += 1
	print("SFX flipper pass press=1 hold=0 second=1")
	return true


func _release_flippers() -> void:
	if Input.is_action_pressed("flipper_left"):
		Input.action_release("flipper_left")
	if Input.is_action_pressed("flipper_right"):
		Input.action_release("flipper_right")


func _spawn_ball(pos: Vector2, vel: Vector2) -> RigidBody2D:
	var ball := BALL_SCENE.instantiate() as RigidBody2D
	ball.position = pos
	_table.add_child(ball)
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	PhysicsServer2D.body_set_state(
		ball.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, pos)
	)
	await physics_frame
	while is_instance_valid(ball) and not bool(ball.get("_ccd_ready")):
		await physics_frame
	if not is_instance_valid(ball):
		return null
	ball.sleeping = false
	ball.linear_velocity = vel
	return ball


func _free_balls() -> void:
	for node in get_nodes_in_group("ball"):
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _bank_targets() -> Array:
	var out: Array = []
	for child in _bank.get_children():
		if child.is_in_group("targets"):
			out.append(child)
	return out


func _fail(message: String) -> bool:
	push_error("SFX FAIL %s" % message)
	print("SFX FAIL %s" % message)
	quit(1)
	return false
